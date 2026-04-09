#include "inference_engine.h"
#include <QDebug>
#include <algorithm>
#include <thread>

// GPU execution providers — priority: CUDA (NVIDIA) → DirectML (AMD/Intel) → CPU
// CUDA:     requires onnxruntime-win-x64-gpu build + NVIDIA CUDA drivers.
// DirectML: requires onnxruntime-directml + DirectML.dll (from NuGet).
// Definimos a interface manualmente para evitar erro de cabeçalho ausente.
#include <d3d12.h>
#include <dxgi.h>

// Estrutura binária exata da OrtDmlApi para ONNX Runtime 1.24.4
// A ordem dos membros é crítica para o mapeamento correto na DLL.
typedef struct OrtDmlApi {
    OrtStatus* (ORT_API_CALL* SessionOptionsAppendExecutionProvider_DML)(_In_ OrtSessionOptions* options, int device_id);
    OrtStatus* (ORT_API_CALL* SessionOptionsAppendExecutionProvider_DML1)(_In_ OrtSessionOptions* options, _In_ void* dml_device, _In_ void* cmd_queue);
    OrtStatus* (ORT_API_CALL* CreateGPUAllocationFromD3DResource)(_In_ ID3D12Resource* d3d_resource, _Out_ void** dml_resource);
    OrtStatus* (ORT_API_CALL* FreeGPUAllocation)(_In_ void* dml_resource);
    OrtStatus* (ORT_API_CALL* GetD3D12ResourceFromAllocation)(_In_ OrtAllocator* provider, _In_ void* dml_resource, _Out_ ID3D12Resource** d3d_resource);
    OrtStatus* (ORT_API_CALL* SessionOptionsAppendExecutionProvider_DML2)(_In_ OrtSessionOptions* options, const void* device_opts);
    OrtStatus* (ORT_API_CALL* GetDMLDevice)(_In_ OrtSessionOptions* options, _Out_ void** dmlDevice);
    OrtStatus* (ORT_API_CALL* GetDMLCommandQueue)(_In_ OrtSessionOptions* options, _Out_ ID3D12CommandQueue** dmlCommandQueue);
} OrtDmlApi;

// Declaração do helper que o ORT exporta para obter as APIs dos providers
// Já declarado em onnxruntime_c_api.h

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
// Tenta primeiro a API específica (via GetExecutionProviderApi) e cai para a genérica.
static bool try_add_dml_provider(Ort::SessionOptions& opts) {
    try {
        qDebug() << "[ORT] Tentando ativar DirectML (GPU AMD/Intel)...";
        
        // Opções obrigatórias para DirectML
        opts.DisableMemPattern();
        opts.SetExecutionMode(ExecutionMode::ORT_SEQUENTIAL);

        // 1. Tenta obter a API específica do DirectML via OrtApi
        const OrtDmlApi* dml_api = nullptr;
        const OrtApi* api = OrtGetApiBase()->GetApi(ORT_API_VERSION);
        
        OrtStatus* status = api->GetExecutionProviderApi("DML", ORT_API_VERSION, reinterpret_cast<const void**>(&dml_api));
        if (status == nullptr && dml_api != nullptr) {
            qDebug() << "[ORT] OrtDmlApi encontrada. Chamando AppendExecutionProvider_DML(device_id: 0)...";
            OrtStatus* add_status = dml_api->SessionOptionsAppendExecutionProvider_DML(opts, 0);
            if (add_status == nullptr) {
                qDebug() << "[ORT] DirectML ativado via OrtDmlApi!";
                return true; 
            } else {
                qDebug() << "[ORT] Falha ao registrar DML via API específica.";
            }
        } else {
            qDebug() << "[ORT] GetExecutionProviderApi('DML') falhou ou retornou nulo. A DLL onnxruntime.dll pode ser a versão de CPU.";
        }

        // 2. Fallback para API genérica de configuração via string
        qDebug() << "[ORT] Tentando fallback para API genérica de strings...";
        std::unordered_map<std::string, std::string> dml_options;
        dml_options["device_id"] = "0";
        opts.AppendExecutionProvider("DML", dml_options);
        qDebug() << "[ORT] DirectML ativado via API genérica!";
        return true;
    } catch (const Ort::Exception& e) {
        qDebug() << "[ORT] Erro ao carregar DirectML:" << e.what();
        return false;
    } catch (...) {
        qDebug() << "[ORT] Erro desconhecido ao carregar DirectML.";
        return false;
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

// Helper: tenta criar as 3 sessões ONNX com as opções fornecidas.
// Retorna true se todas foram criadas com sucesso, false caso contrário.
// Em caso de falha, reseta os ponteiros para não deixar sessões parciais.
bool InferenceEngine::tryCreateSessions(Ort::SessionOptions& opts)
{
    try {
        for (int i = 0; i < 3; i++) {
            m_sessions[i] = std::make_unique<Ort::Session>(
                m_env, m_modelPath.toStdWString().c_str(), opts);
        }
        return true;
    } catch (const Ort::Exception& e) {
        qDebug() << "[ORT] Falha ao criar sessão:" << e.what();
        for (int i = 0; i < 3; i++) m_sessions[i].reset();
        return false;
    }
}

bool InferenceEngine::createSession()
{
    // DXGI detecta o fabricante da GPU uma única vez
    const GpuVendor vendor = detectGpuVendor();

    // ── Tentativa 1: CUDA (NVIDIA) ────────────────────────────────────────────
    // try_add_cuda_provider apenas registra o provider nas opções — não valida
    // se os drivers CUDA/cuDNN estão disponíveis. A validação real acontece em
    // tryCreateSessions(). Se falhar (ex: cudart não instalado), cai para DML.
    if (vendor == GpuVendor::NVIDIA) {
        Ort::SessionOptions opts;
        if (try_add_cuda_provider(opts)) {
            opts.SetIntraOpNumThreads(1);
            if (tryCreateSessions(opts)) {
                emit infoMsg("Modo GPU: CUDA ativo (NVIDIA)");
                goto sessions_ready;
            }
            qDebug() << "[ORT] CUDA registrado mas sessão falhou (CUDA runtime/cuDNN ausente?). Tentando DirectML...";
        }
    }

    // ── Tentativa 2: DirectML (AMD/Intel/NVIDIA sem CUDA) ─────────────────────
    {
        Ort::SessionOptions opts;
        if (try_add_dml_provider(opts)) {
            opts.SetIntraOpNumThreads(1);
            if (tryCreateSessions(opts)) {
                const QString gpuName = (vendor == GpuVendor::NVIDIA) ? "NVIDIA" :
                                        (vendor == GpuVendor::AMD)    ? "AMD"    : "Intel";
                emit infoMsg(QString("Modo GPU: DirectML ativo (%1, DirectX 12)").arg(gpuName));
                goto sessions_ready;
            }
            qDebug() << "[ORT] DirectML registrado mas sessão falhou. Usando CPU.";
        }
    }

    // ── Tentativa 3: CPU fallback ─────────────────────────────────────────────
    {
        Ort::SessionOptions opts;
        opts.SetIntraOpNumThreads(4);
        opts.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);
        if (!tryCreateSessions(opts)) {
            emit errorMsg("ONNX: falha ao criar sessão mesmo em modo CPU.");
            return false;
        }
        emit infoMsg("Modo CPU: GPU não disponível");
    }

sessions_ready:
    try {
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
