#include "inference_engine.h"
#include <QDebug>
#include <algorithm>
#include <thread>

// GPU execution providers — priority: CUDA (NVIDIA) → DirectML (AMD/Intel) → CPU
// CUDA:     requires onnxruntime-win-x64-gpu build + NVIDIA CUDA drivers.
// DirectML: requires onnxruntime-win-x64 standard build + DirectX 12 (Windows 10+).
// Note: dml_provider_factory.h not needed — uses generic GetExecutionProviderApi("DML") API.
#include <dxgi.h>

// ── GPU vendor detection via DXGI ─────────────────────────────────────────────
// Enumerates the first discrete (non-software) adapter to identify the vendor.
// Called once at session creation — no runtime overhead during inference.
enum class GpuVendor { Unknown, NVIDIA, AMD, Intel };

static GpuVendor detectGpuVendor() {
    IDXGIFactory1* factory = nullptr;
    if (FAILED(CreateDXGIFactory1(__uuidof(IDXGIFactory1),
                                  reinterpret_cast<void**>(&factory))))
        return GpuVendor::Unknown;

    GpuVendor vendor = GpuVendor::Unknown;
    IDXGIAdapter1* adapter = nullptr;
    for (UINT i = 0; factory->EnumAdapters1(i, &adapter) != DXGI_ERROR_NOT_FOUND; ++i) {
        DXGI_ADAPTER_DESC1 desc{};
        adapter->GetDesc1(&desc);
        adapter->Release();
        if (desc.Flags & DXGI_ADAPTER_FLAG_SOFTWARE) continue; // skip WARP/software
        switch (desc.VendorId) {
            case 0x10DE: vendor = GpuVendor::NVIDIA; break;
            case 0x1002: vendor = GpuVendor::AMD;    break;
            case 0x8086: vendor = GpuVendor::Intel;  break;
        }
        if (vendor != GpuVendor::Unknown) break;
    }
    factory->Release();
    return vendor;
}

// Returns true if CUDA EP was successfully registered (NVIDIA + CUDA ORT build).
static bool try_add_cuda_provider(Ort::SessionOptions& opts) {
    try {
        OrtCUDAProviderOptions cuda_options{};
        cuda_options.device_id = 0;
        opts.AppendExecutionProvider_CUDA(cuda_options);
        return true;
    } catch (const Ort::Exception&) {
        return false;   // Standard (DirectML) ORT build — CUDA EP not compiled in
    }
}

// Returns true if DirectML EP was successfully registered (AMD/Intel/NVIDIA, DX12).
// Uses the generic AppendExecutionProvider("DML", {}) API available in ORT 1.20+.
static bool try_add_dml_provider(Ort::SessionOptions& opts) {
    try {
        // DirectML requer estas opções obrigatoriamente
        opts.DisableMemPattern();
        opts.SetExecutionMode(ExecutionMode::ORT_SEQUENTIAL);

        std::unordered_map<std::string, std::string> dml_options;
        dml_options["device_id"] = "0";
        opts.AppendExecutionProvider("DML", dml_options);
        return true;
    } catch (const Ort::Exception&) {
        return false;  // DirectML EP not available or failed to initialize
    }
}

InferenceEngine::InferenceEngine(QObject* parent)
    : QThread(parent)
    , m_env(ORT_LOGGING_LEVEL_WARNING, "MindTrace")
{}

InferenceEngine::~InferenceEngine()
{
    requestStop();
    wait(5000);
}

void InferenceEngine::loadModel(const QString& path)
{
    QMutexLocker lock(&m_mutex);
    m_modelPath = path;
}

void InferenceEngine::enqueueFrame(const QImage& frame, int videoW, int videoH)
{
    QMutexLocker lock(&m_mutex);
    m_pending    = {frame, videoW, videoH};
    m_hasPending = true;
    m_cond.wakeOne();
}

void InferenceEngine::requestStop()
{
    QMutexLocker lock(&m_mutex);
    m_stop = true;
    m_cond.wakeAll();
}

// ── Session creation ──────────────────────────────────────────────────────────

bool InferenceEngine::createSession()
{
    try {
        Ort::SessionOptions opts;

        // ── GPU provider chain com detecção automática de vendor ──────
        // DXGI detecta o fabricante da GPU (NVIDIA/AMD/Intel) antes de tentar
        // qualquer provider, evitando exceções desnecessárias para AMD/Intel.
        const GpuVendor vendor = detectGpuVendor();

        if (vendor == GpuVendor::NVIDIA && try_add_cuda_provider(opts)) {
            // NVIDIA + onnxruntime-win-x64-gpu build: máximo desempenho via CUDA
            opts.SetIntraOpNumThreads(1);
            emit infoMsg("Modo GPU: CUDA ativo (NVIDIA)");
        } else if (try_add_dml_provider(opts)) {
            // AMD/Intel (ou NVIDIA sem build CUDA): DirectML via DirectX 12
            const QString gpuName = (vendor == GpuVendor::NVIDIA) ? "NVIDIA" :
                                    (vendor == GpuVendor::AMD)    ? "AMD"    : "Intel";
            opts.SetIntraOpNumThreads(1);
            emit infoMsg(QString("Modo GPU: DirectML ativo (%1, DirectX 12)").arg(gpuName));
        } else {
            opts.SetIntraOpNumThreads(4);
            opts.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);
            emit infoMsg("Modo CPU: GPU não disponível");
        }

        // Create one session per campo for parallel inference
        for (int i = 0; i < 3; i++) {
            m_sessions[i] = std::make_unique<Ort::Session>(
                m_env, m_modelPath.toStdWString().c_str(), opts);
        }

        Ort::AllocatorWithDefaultOptions alloc;

        // Query names from the first session (identical across all three)
        m_inputName = m_sessions[0]->GetInputNameAllocated(0, alloc).get();

        m_outputNames.clear();
        size_t outCount = m_sessions[0]->GetOutputCount();
        for (size_t i = 0; i < outCount; i++) {
            m_outputNames.push_back(m_sessions[0]->GetOutputNameAllocated(i, alloc).get());
        }
        m_hasLocref = (m_outputNames.size() >= 2);
        return true;

    } catch (const Ort::Exception& e) {
        emit errorMsg(QString("ONNX load error: ") + e.what());
        return false;
    }
}

// ── Thread main loop ──────────────────────────────────────────────────────────

void InferenceEngine::run()
{
    // Reset stop/pending flags so re-starting after stopAnalysis() works correctly.
    // m_stop is set to true by requestStop() — without this reset the while loop
    // would break immediately on the second (and every subsequent) session.
    {
        QMutexLocker lock(&m_mutex);
        m_stop       = false;
        m_hasPending = false;
    }

    if (!createSession()) return;
    emit modelReady();

    while (true) {
        Job job;
        {
            QMutexLocker lock(&m_mutex);
            while (!m_hasPending && !m_stop)
                m_cond.wait(&m_mutex);
            if (m_stop) break;
            job          = std::move(m_pending);
            m_hasPending = false;
        }
        processJob(job);
    }
}

// ── Per-frame processing ──────────────────────────────────────────────────────

void InferenceEngine::processJob(const Job& job)
{
    if (job.frame.isNull() || job.videoW <= 0 || job.videoH <= 0) return;

    const int halfW = job.videoW / 2;
    const int halfH = job.videoH / 2;
    const float scaleX = static_cast<float>(halfW) / MODEL_W;
    const float scaleY = static_cast<float>(halfH) / MODEL_H;

    // 3 active campos: top-left, top-right, bottom-left
    const int offsets[3][2] = {{0, 0}, {halfW, 0}, {0, halfH}};

    // Each thread owns its crop, resize, convert, and infer — fully parallel
    std::vector<std::thread> threads;
    threads.reserve(3);
    for (int i = 0; i < 3; i++) {
        const int ox = offsets[i][0];
        const int oy = offsets[i][1];
        threads.emplace_back([this, &job, i, ox, oy, halfW, halfH, scaleX, scaleY]() {
            // Crop (cheap — pointer copy when bounds are valid)
            QImage crop = job.frame.copy(ox, oy, halfW, halfH);
            if (crop.isNull()) return;

            // Resize only if needed — FastTransformation is ~3x faster than Smooth
            if (crop.width() != MODEL_W || crop.height() != MODEL_H)
                crop = crop.scaled(MODEL_W, MODEL_H,
                                   Qt::IgnoreAspectRatio, Qt::FastTransformation);

            // Convert to RGB (in-place when possible)
            crop = crop.convertToFormat(QImage::Format_RGB888);

            inferCrop(crop, i, ox, oy, scaleX, scaleY);
        });
    }
    for (auto& t : threads) t.join();
}

// ── Per-crop ONNX inference ───────────────────────────────────────────────────

void InferenceEngine::inferCrop(const QImage& crop, int campo,
                              int ox, int oy,
                              float scaleX, float scaleY)
{
    // Build float32 input tensor [1, MODEL_H, MODEL_W, 3]
    std::vector<float> input(MODEL_H * MODEL_W * 3);
    for (int r = 0; r < MODEL_H; r++) {
        const uchar* src = crop.constScanLine(r);
        float*       dst = input.data() + r * MODEL_W * 3;
        for (int c = 0; c < MODEL_W; c++) {
            dst[c * 3 + 0] = static_cast<float>(src[c * 3 + 0]); // R
            dst[c * 3 + 1] = static_cast<float>(src[c * 3 + 1]); // G
            dst[c * 3 + 2] = static_cast<float>(src[c * 3 + 2]); // B
        }
    }

    int64_t shape[] = {1, MODEL_H, MODEL_W, 3};
    auto    mem     = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeCPU);
    Ort::Value inTensor = Ort::Value::CreateTensor<float>(
        mem, input.data(), input.size(), shape, 4);

    const char* inNames[] = {m_inputName.c_str()};
    std::vector<const char*> outNames;
    for (auto& s : m_outputNames) outNames.push_back(s.c_str());
    const size_t numOut = m_hasLocref ? 2 : 1;

    std::vector<Ort::Value> outputs;
    try {
        outputs = m_sessions[campo]->Run(
            Ort::RunOptions{nullptr},
            inNames, &inTensor, 1,
            outNames.data(), numOut);
    } catch (const Ort::Exception& e) {
        emit errorMsg(QString("ONNX run error: ") + e.what());
        return;
    }

    // scoremap: [1, HEAT_ROWS, HEAT_COLS, 2]
    const float* scoreData = outputs[0].GetTensorData<float>();
    // locref:   [1, HEAT_ROWS, HEAT_COLS, 4]
    const float* locData = (m_hasLocref && outputs.size() >= 2)
                           ? outputs[1].GetTensorData<float>() : nullptr;

    // Process nose (ch=0) and body (ch=1)
    for (int ch = 0; ch < 2; ch++) {
        // Find peak in HEAT_ROWS × HEAT_COLS heatmap for this channel
        float bestVal = -1e9f;
        int   bestR = 0, bestC = 0;
        for (int r = 0; r < HEAT_ROWS; r++) {
            for (int c = 0; c < HEAT_COLS; c++) {
                float v = scoreData[r * HEAT_COLS * 2 + c * 2 + ch];
                if (v > bestVal) { bestVal = v; bestR = r; bestC = c; }
            }
        }

        if (bestVal < 0.05f) continue;

        // Locref channels: dx_nose=0, dy_nose=1, dx_body=2, dy_body=3
        const int dxCh = (ch == 0) ? 0 : 2;
        const int dyCh = (ch == 0) ? 1 : 3;
        const float ldx = locData ? locData[bestR * HEAT_COLS * 4 + bestC * 4 + dxCh] : 0.f;
        const float ldy = locData ? locData[bestR * HEAT_COLS * 4 + bestC * 4 + dyCh] : 0.f;

        // Crop-space pixel coords
        const float px = (bestC + 0.5f) * STRIDE + ldx * LOCREF_STD;
        const float py = (bestR + 0.5f) * STRIDE + ldy * LOCREF_STD;

        // Mosaico-space pixel coords
        const float mx = px * scaleX + static_cast<float>(ox);
        const float my = py * scaleY + static_cast<float>(oy);

        if (ch == 0)
            emit trackResult(campo, mx, my, bestVal);
        else
            emit bodyResult(campo, mx, my, bestVal);
    }
}
