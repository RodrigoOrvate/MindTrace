#include "inference_engine.h"

// GPU execution providers — priority: CUDA (NVIDIA) → DirectML (AMD/Intel) → CPU.
// CUDA:     requires onnxruntime-win-x64-gpu build + NVIDIA CUDA drivers.
// DirectML: requires onnxruntime-directml + DirectML.dll (from NuGet).
#include <d3d12.h>
#include <dxgi.h>

#include <QDebug>
#include <QFile>

#include <algorithm>
#include <atomic>
#include <array>
#include <cmath>
#include <thread>

// OrtDmlApi binary layout for ONNX Runtime 1.24.4.
// Member order is critical for correct DLL vtable mapping.
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

// ── GPU vendor detection via DXGI ─────────────────────────────────────────────
// Enumerates the first discrete (non-software) adapter to identify the vendor.
// Called once at session creation — no runtime overhead during inference.
enum class GpuVendor { Unknown, NVIDIA, AMD, Intel };

static GpuVendor detectGpuVendor()
{
    IDXGIFactory1* dxgiFactory = nullptr;
    if (FAILED(CreateDXGIFactory1(__uuidof(IDXGIFactory1),
                                  reinterpret_cast<void**>(&dxgiFactory))))
        return GpuVendor::Unknown;

    GpuVendor      vendor      = GpuVendor::Unknown;
    IDXGIAdapter1* dxgiAdapter = nullptr;
    for (UINT adapterIdx = 0;
         dxgiFactory->EnumAdapters1(adapterIdx, &dxgiAdapter) != DXGI_ERROR_NOT_FOUND;
         ++adapterIdx)
    {
        DXGI_ADAPTER_DESC1 adapterDesc{};
        dxgiAdapter->GetDesc1(&adapterDesc);
        dxgiAdapter->Release();
        if (adapterDesc.Flags & DXGI_ADAPTER_FLAG_SOFTWARE) continue;
        switch (adapterDesc.VendorId) {
            case 0x10DE: vendor = GpuVendor::NVIDIA; break;
            case 0x1002: vendor = GpuVendor::AMD;    break;
            case 0x8086: vendor = GpuVendor::Intel;  break;
        }
        if (vendor != GpuVendor::Unknown) break;
    }
    dxgiFactory->Release();
    return vendor;
}

static std::vector<int> detectActiveMosaicQuadrants(const QImage& frame, int brightnessThreshold = 45)
{
    std::vector<int> active;
    if (frame.isNull() || frame.width() < 2 || frame.height() < 2) return active;

    const int halfW = frame.width() / 2;
    const int halfH = frame.height() / 2;
    if (halfW <= 0 || halfH <= 0) return active;

    const std::array<QRect, 4> rois = {{
        QRect(0,     0,     halfW, halfH),  // 0: top-left
        QRect(halfW, 0,     halfW, halfH),  // 1: top-right
        QRect(0,     halfH, halfW, halfH),  // 2: bottom-left
        QRect(halfW, halfH, halfW, halfH),  // 3: bottom-right
    }};

    for (int idx = 0; idx < static_cast<int>(rois.size()); ++idx) {
        const QRect roi = rois[idx].intersected(frame.rect());
        if (roi.isEmpty()) continue;

        const int sampleStep = 12;
        int darkCount = 0;
        int sampleCount = 0;
        for (int y = roi.top(); y <= roi.bottom(); y += sampleStep) {
            for (int x = roi.left(); x <= roi.right(); x += sampleStep) {
                const QRgb px = frame.pixel(x, y);
                const int luma = (299 * qRed(px) + 587 * qGreen(px) + 114 * qBlue(px)) / 1000;
                if (luma <= brightnessThreshold) ++darkCount;
                ++sampleCount;
            }
        }

        if (sampleCount <= 0) continue;
        const double darkRatio = static_cast<double>(darkCount) / static_cast<double>(sampleCount);
        if (darkRatio < 0.60) {
            active.push_back(idx);
        } else {
            qDebug() << "[InferenceEngine] skip quadrant" << idx
                     << "(majority black, darkRatio=" << darkRatio << ")";
        }
    }

    return active;
}

// Returns true if CUDA EP was successfully registered in *sessionOptions*.
// Only registers the provider — actual driver validation happens inside
// tryCreateSessions(). Falls through to DirectML if session creation throws.
static bool tryAddCudaProvider(Ort::SessionOptions& sessionOptions)
{
    try {
        OrtCUDAProviderOptions cudaOptions{};
        cudaOptions.device_id = 0;
        sessionOptions.AppendExecutionProvider_CUDA(cudaOptions);
        return true;
    } catch (const Ort::Exception&) {
        return false;  // Standard (DirectML) ORT build — CUDA EP not compiled in.
    }
}

// Returns true if DirectML EP was successfully registered (AMD/Intel/NVIDIA, DX12).
// Tries the typed GetExecutionProviderApi first, then the generic string-based API.
static bool tryAddDmlProvider(Ort::SessionOptions& sessionOptions)
{
    try {
        qDebug() << "[ORT] Tentando ativar DirectML (GPU AMD/Intel)...";

        sessionOptions.DisableMemPattern();
        sessionOptions.SetExecutionMode(ExecutionMode::ORT_SEQUENTIAL);

        const OrtDmlApi* dmlApi    = nullptr;
        const OrtApi*    ortApi    = OrtGetApiBase()->GetApi(ORT_API_VERSION);
        OrtStatus*       apiStatus = ortApi->GetExecutionProviderApi(
            "DML", ORT_API_VERSION, reinterpret_cast<const void**>(&dmlApi));

        if (apiStatus == nullptr && dmlApi != nullptr) {
            qDebug() << "[ORT] OrtDmlApi encontrada. Chamando AppendExecutionProvider_DML(device_id: 0)...";
            OrtStatus* addStatus = dmlApi->SessionOptionsAppendExecutionProvider_DML(sessionOptions, 0);
            if (addStatus == nullptr) {
                qDebug() << "[ORT] DirectML ativado via OrtDmlApi!";
                return true;
            }
            qDebug() << "[ORT] Falha ao registrar DML via API especifica.";
        } else {
            qDebug() << "[ORT] GetExecutionProviderApi('DML') falhou ou retornou nulo.";
        }

        // Fallback: generic string-based provider API.
        qDebug() << "[ORT] Tentando fallback para API generica de strings...";
        std::unordered_map<std::string, std::string> dmlOptions;
        dmlOptions["device_id"] = "0";
        sessionOptions.AppendExecutionProvider("DML", dmlOptions);
        qDebug() << "[ORT] DirectML ativado via API generica!";
        return true;
    } catch (const Ort::Exception& e) {
        qDebug() << "[ORT] Erro ao carregar DirectML:" << e.what();
        return false;
    } catch (...) {
        qDebug() << "[ORT] Erro desconhecido ao carregar DirectML.";
        return false;
    }
}

// ── Construction / destruction ─────────────────────────────────────────────────

InferenceEngine::InferenceEngine(QObject* parent)
    : QThread(parent)
    , m_env(ORT_LOGGING_LEVEL_WARNING, "MindTrace")
    , m_scanners{BehaviorScanner(30), BehaviorScanner(30), BehaviorScanner(30)}
{}

InferenceEngine::~InferenceEngine()
{
    requestStop();
    // Always wait for full thread exit — timed waits can return early during slow
    // session creation and leave the thread running into QObject teardown.
    wait();
}

// ── Public configuration ───────────────────────────────────────────────────────

void InferenceEngine::loadModel(const QString& modelPath)
{
    QMutexLocker lock(&m_mutex);
    m_modelPath = modelPath;
}

void InferenceEngine::loadBehaviorModel(const QString& behaviorModelDir)
{
    QMutexLocker lock(&m_mutex);
    m_behaviorModelDir = behaviorModelDir;
    m_behaviorEnabled  = !behaviorModelDir.isEmpty();
}

void InferenceEngine::setZones(int fieldIndex, const std::vector<Zone>& zones)
{
    if (fieldIndex >= 0 && fieldIndex < 3)
        m_scanners[fieldIndex].setZones(zones);
}

void InferenceEngine::setFloorPolygon(int fieldIndex, const std::vector<std::pair<float, float>>& poly)
{
    if (fieldIndex >= 0 && fieldIndex < 3)
        m_scanners[fieldIndex].setFloorPolygon(poly);
}

void InferenceEngine::setVelocity(int fieldIndex, float velocity)
{
    if (fieldIndex >= 0 && fieldIndex < 3)
        m_scanners[fieldIndex].setVelocity(velocity);
}

void InferenceEngine::setFullFrameMode(bool enabled)
{
    m_fullFrame.store(enabled, std::memory_order_relaxed);
}

void InferenceEngine::enqueueFrame(const QImage& frame, int videoWidth, int videoHeight)
{
    QMutexLocker lock(&m_mutex);
    m_pendingJob       = {frame, videoWidth, videoHeight};
    m_pendingAvailable = true;
    m_cond.wakeOne();
}

void InferenceEngine::requestStop()
{
    QMutexLocker lock(&m_mutex);
    m_stopRequested = true;
    m_cond.wakeAll();
}

const std::vector<FrameRecord>& InferenceEngine::getScannerHistory(int fieldIndex) const
{
    static const std::vector<FrameRecord> empty;
    if (fieldIndex < 0 || fieldIndex >= 3) return empty;
    return m_scanners[fieldIndex].frameHistory();
}

void InferenceEngine::clearScannerHistory(int fieldIndex)
{
    if (fieldIndex >= 0 && fieldIndex < 3)
        m_scanners[fieldIndex].clearHistory();
}

void InferenceEngine::setManualQuadrantMapping(const std::vector<int>& mapping)
{
    QMutexLocker lock(&m_mutex);
    m_manualQuadrants = mapping;
    m_manualQuadrantEnabled = true;
}

void InferenceEngine::clearManualQuadrantMapping()
{
    QMutexLocker lock(&m_mutex);
    m_manualQuadrants.clear();
    m_manualQuadrantEnabled = false;
}

// ── Session creation ───────────────────────────────────────────────────────────

bool InferenceEngine::tryCreateSessions(Ort::SessionOptions& sessionOptions)
{
    try {
        emit infoMsg("Carregando modelos de pose (GPU)...");
        for (int sessionIdx = 0; sessionIdx < 3; ++sessionIdx) {
            m_sessions[sessionIdx] = std::make_unique<Ort::Session>(
                m_env, m_modelPath.toStdWString().c_str(), sessionOptions);
        }

        if (m_behaviorEnabled && !m_behaviorModelDir.isEmpty()) {
            // Load individual binary classifiers (one .onnx per behaviour class).
            // Expected files: walking.onnx, sniffing.onnx, grooming.onnx,
            //                 resting.onnx, rearing.onnx
            // Indices align with QML behaviorNames: [Walking=0, Sniffing=1, Grooming=2,
            //                                        Resting=3, Rearing=4]
            static const std::pair<const char*, int> BEHAVIOR_MAP[] = {
                {"walking",  0},
                {"sniffing", 1},
                {"grooming", 2},
                {"resting",  3},
                {"rearing",  4},
            };

            m_behaviorSessions.clear();

            Ort::SessionOptions behaviorSessionOpts;
            behaviorSessionOpts.SetIntraOpNumThreads(1);
            behaviorSessionOpts.SetExecutionMode(ExecutionMode::ORT_SEQUENTIAL);
            behaviorSessionOpts.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_DISABLE_ALL);

            Ort::AllocatorWithDefaultOptions behaviorAllocator;
            int loadedCount = 0;

            for (auto& [name, behaviorIdx] : BEHAVIOR_MAP) {
                const QString behaviorModelPath = m_behaviorModelDir + "/" + name + ".onnx";
                if (!QFile::exists(behaviorModelPath)) {
                    qDebug() << "[Behavior] Nao encontrado:" << behaviorModelPath;
                    continue;
                }
                try {
                    auto session = std::make_unique<Ort::Session>(
                        m_env, behaviorModelPath.toStdWString().c_str(), behaviorSessionOpts);

                    BehaviorSessionInfo behaviorSession;
                    behaviorSession.behaviorIndex = behaviorIdx;
                    behaviorSession.inputName =
                        session->GetInputNameAllocated(0, behaviorAllocator).get();

                    const size_t outputCount = session->GetOutputCount();
                    for (size_t outputIdx = 0; outputIdx < outputCount; ++outputIdx) {
                        auto typeInfo = session->GetOutputTypeInfo(outputIdx);
                        if (typeInfo.GetONNXType() == ONNX_TYPE_TENSOR) {
                            const auto elemType =
                                typeInfo.GetTensorTypeAndShapeInfo().GetElementType();
                            if (elemType == ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT) {
                                behaviorSession.probOutputName =
                                    session->GetOutputNameAllocated(outputIdx, behaviorAllocator).get();
                                break;
                            }
                        }
                    }

                    if (behaviorSession.probOutputName.empty()) {
                        qDebug() << "[Behavior] Sem saida float em:" << behaviorModelPath;
                        continue;
                    }

                    behaviorSession.session = std::move(session);
                    m_behaviorSessions.push_back(std::move(behaviorSession));
                    qDebug() << "[Behavior] Carregado:" << name
                             << "-> behaviorNames[" << behaviorIdx << "]";
                    ++loadedCount;
                } catch (const Ort::Exception& e) {
                    qDebug() << "[Behavior] Falha ao carregar" << name << ":" << e.what();
                }
            }

            m_behaviorEnabled = loadedCount > 0;
            if (loadedCount > 0)
                emit infoMsg(QString("Behavior: %1 classificador(es) carregado(s)").arg(loadedCount));
            else
                qDebug() << "[Behavior] Nenhum modelo carregado — usando rule-based";
        }
        return true;
    } catch (const Ort::Exception& e) {
        qDebug() << "[ORT] Falha ao criar sessao de pose:" << e.what();
        for (int sessionIdx = 0; sessionIdx < 3; ++sessionIdx)
            m_sessions[sessionIdx].reset();
        m_behaviorSessions.clear();
        return false;
    }
}

bool InferenceEngine::createSession()
{
    const GpuVendor vendor = detectGpuVendor();

    // Attempt 1: CUDA (NVIDIA). Provider registration alone does not validate
    // that CUDA/cuDNN are installed — tryCreateSessions() does the real check.
    if (vendor == GpuVendor::NVIDIA) {
        Ort::SessionOptions sessionOptions;
        if (tryAddCudaProvider(sessionOptions)) {
            sessionOptions.SetIntraOpNumThreads(1);
            if (tryCreateSessions(sessionOptions)) {
                emit infoMsg("Modo GPU: CUDA ativo (NVIDIA)");
                goto sessions_ready;
            }
            qDebug() << "[ORT] CUDA registrado mas sessao falhou. Tentando DirectML...";
        }
    }

    // Attempt 2: DirectML (AMD/Intel/NVIDIA without CUDA).
    {
        Ort::SessionOptions sessionOptions;
        if (tryAddDmlProvider(sessionOptions)) {
            sessionOptions.SetIntraOpNumThreads(1);
            if (tryCreateSessions(sessionOptions)) {
                const QString gpuName = (vendor == GpuVendor::NVIDIA) ? "NVIDIA" :
                                        (vendor == GpuVendor::AMD)    ? "AMD"    : "Intel";
                emit infoMsg(QString("Modo GPU: DirectML ativo (%1, DirectX 12)").arg(gpuName));
                goto sessions_ready;
            }
            qDebug() << "[ORT] DirectML registrado mas sessao falhou. Usando CPU.";
        }
    }

    // Attempt 3: CPU fallback.
    {
        Ort::SessionOptions sessionOptions;
        sessionOptions.SetIntraOpNumThreads(4);
        sessionOptions.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);
        if (!tryCreateSessions(sessionOptions)) {
            emit errorMsg("ONNX: falha ao criar sessao mesmo em modo CPU.");
            return false;
        }
        emit infoMsg("Modo CPU: GPU nao disponivel");
    }

sessions_ready:
    try {
        Ort::AllocatorWithDefaultOptions allocator;
        m_inputName = m_sessions[0]->GetInputNameAllocated(0, allocator).get();

        m_outputNames.clear();
        const size_t outputCount = m_sessions[0]->GetOutputCount();
        for (size_t outputIdx = 0; outputIdx < outputCount; ++outputIdx)
            m_outputNames.push_back(m_sessions[0]->GetOutputNameAllocated(outputIdx, allocator).get());

        m_hasLocrefOutput = (m_outputNames.size() >= 2);
        return true;
    } catch (const Ort::Exception& e) {
        emit errorMsg(QString("ONNX load error: ") + e.what());
        return false;
    }
}

// ── Thread main loop ───────────────────────────────────────────────────────────

void InferenceEngine::run()
{
    // Reset flags so a re-start after stopAnalysis() works correctly.
    // m_stopRequested is set true by requestStop() — without this reset the
    // while loop would break immediately on every subsequent session.
    {
        QMutexLocker lock(&m_mutex);
        m_stopRequested    = false;
        m_pendingAvailable = false;
    }

    // Reset scanners so stale movement history from the previous session does
    // not contaminate the first frames of the new one.
    for (auto& scanner : m_scanners) scanner.reset();
    m_lastActiveQuadrants = {0, 1, 2};

    if (!createSession()) return;
    emit modelReady();

    while (true) {
        PendingJob job;
        {
            QMutexLocker lock(&m_mutex);
            while (!m_pendingAvailable && !m_stopRequested)
                m_cond.wait(&m_mutex);
            if (m_stopRequested) break;
            job                = std::move(m_pendingJob);
            m_pendingAvailable = false;
        }
        processJob(job);
    }
}

// ── Per-frame processing ───────────────────────────────────────────────────────

void InferenceEngine::processJob(const PendingJob& job)
{
    if (job.frame.isNull() || job.videoWidth <= 0 || job.videoHeight <= 0) return;

    // EI mode: single field covering the entire frame.
    if (m_fullFrame.load(std::memory_order_relaxed)) {
        const float scaleX = static_cast<float>(job.videoWidth)  / MODEL_W;
        const float scaleY = static_cast<float>(job.videoHeight) / MODEL_H;
        QImage crop = job.frame.copy(0, 0, job.videoWidth, job.videoHeight);
        if (crop.isNull()) return;
        if (crop.width() != MODEL_W || crop.height() != MODEL_H)
            crop = crop.scaled(MODEL_W, MODEL_H, Qt::IgnoreAspectRatio, Qt::FastTransformation);
        crop = crop.convertToFormat(QImage::Format_RGB888);
        inferCrop(crop, 0, 0, 0, scaleX, scaleY);
        return;
    }

    // Mosaic mode: 3 quadrant half-frames processed in parallel.
    const int halfW = job.videoWidth  / 2;
    const int halfH = job.videoHeight / 2;
    const float scaleX = static_cast<float>(halfW) / MODEL_W;
    const float scaleY = static_cast<float>(halfH) / MODEL_H;

    // Dynamic mapping: field N uses the N-th active quadrant (skip black quadrants).
    std::vector<int> activeQuadrants;
    bool manualMode = false;
    {
        QMutexLocker lock(&m_mutex);
        if (m_manualQuadrantEnabled) {
            activeQuadrants = m_manualQuadrants;
            manualMode = true;
        }
    }

    if (!manualMode) {
        activeQuadrants = detectActiveMosaicQuadrants(job.frame);
        if (!activeQuadrants.empty())
            m_lastActiveQuadrants = activeQuadrants;
        else
            activeQuadrants = m_lastActiveQuadrants;
    }
    const int offsets[4][2] = {{0, 0}, {halfW, 0}, {0, halfH}, {halfW, halfH}};

    std::vector<std::thread> workerThreads;
    workerThreads.reserve(3);
    for (int fieldIndex = 0; fieldIndex < 3; ++fieldIndex) {
        if (fieldIndex >= static_cast<int>(activeQuadrants.size()))
            break;
        const int quadrantIndex = activeQuadrants[fieldIndex];
        const int cropOffsetX = offsets[quadrantIndex][0];
        const int cropOffsetY = offsets[quadrantIndex][1];
        workerThreads.emplace_back([this, &job, fieldIndex,
                                    cropOffsetX, cropOffsetY,
                                    halfW, halfH, scaleX, scaleY]() {
            QImage crop = job.frame.copy(cropOffsetX, cropOffsetY, halfW, halfH);
            if (crop.isNull()) return;
            if (crop.width() != MODEL_W || crop.height() != MODEL_H)
                crop = crop.scaled(MODEL_W, MODEL_H,
                                   Qt::IgnoreAspectRatio, Qt::FastTransformation);
            crop = crop.convertToFormat(QImage::Format_RGB888);
            inferCrop(crop, fieldIndex, cropOffsetX, cropOffsetY, scaleX, scaleY);
        });
    }
    for (auto& thread : workerThreads) thread.join();
}

// ── Per-crop ONNX inference ────────────────────────────────────────────────────

void InferenceEngine::inferCrop(const QImage& crop, int fieldIndex,
                                int cropOffsetX, int cropOffsetY,
                                float scaleX, float scaleY)
{
    // Build float32 input tensor [1, MODEL_H, MODEL_W, 3].
    std::vector<float> inputBuffer(MODEL_H * MODEL_W * 3);
    for (int row = 0; row < MODEL_H; ++row) {
        const uchar* rowPixels = crop.constScanLine(row);
        float*       inputRow  = inputBuffer.data() + row * MODEL_W * 3;
        for (int col = 0; col < MODEL_W; ++col) {
            inputRow[col * 3 + 0] = static_cast<float>(rowPixels[col * 3 + 0]); // R
            inputRow[col * 3 + 1] = static_cast<float>(rowPixels[col * 3 + 1]); // G
            inputRow[col * 3 + 2] = static_cast<float>(rowPixels[col * 3 + 2]); // B
        }
    }

    int64_t    inputShape[]  = {1, MODEL_H, MODEL_W, 3};
    auto       cpuMemInfo    = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeCPU);
    Ort::Value inputTensor   = Ort::Value::CreateTensor<float>(
        cpuMemInfo, inputBuffer.data(), inputBuffer.size(), inputShape, 4);

    const char*              inputNamePtr[]     = {m_inputName.c_str()};
    std::vector<const char*> outputNamePtrs;
    for (const auto& name : m_outputNames) outputNamePtrs.push_back(name.c_str());
    const size_t requestedOutputCount = m_hasLocrefOutput ? 2 : 1;

    std::vector<Ort::Value> outputs;
    try {
        outputs = m_sessions[fieldIndex]->Run(
            Ort::RunOptions{nullptr},
            inputNamePtr, &inputTensor, 1,
            outputNamePtrs.data(), requestedOutputCount);
    } catch (const Ort::Exception& e) {
        emit errorMsg(QString("ONNX run error: ") + e.what());
        return;
    }

    // scoremap: [1, HEAT_ROWS, HEAT_COLS, 2]
    const float* scoreData = outputs[0].GetTensorData<float>();
    // locref:   [1, HEAT_ROWS, HEAT_COLS, 4]
    const float* locData = (m_hasLocrefOutput && outputs.size() >= 2)
                           ? outputs[1].GetTensorData<float>() : nullptr;

    PosePoint nosePoint, bodyPoint;

    // Process nose (channel 0) and body (channel 1).
    for (int channel = 0; channel < 2; ++channel) {
        float peakScore = -1e9f;
        int   peakRow   = 0;
        int   peakCol   = 0;
        for (int row = 0; row < HEAT_ROWS; ++row) {
            for (int col = 0; col < HEAT_COLS; ++col) {
                const float heatmapScore = scoreData[row * HEAT_COLS * 2 + col * 2 + channel];
                if (heatmapScore > peakScore) {
                    peakScore = heatmapScore;
                    peakRow   = row;
                    peakCol   = col;
                }
            }
        }

        if (peakScore < 0.05f) continue;

        // Locref channel layout: dx_nose=0, dy_nose=1, dx_body=2, dy_body=3.
        const int   locrefDxChannel = (channel == 0) ? 0 : 2;
        const int   locrefDyChannel = (channel == 0) ? 1 : 3;
        const float locrefDx = locData
            ? locData[peakRow * HEAT_COLS * 4 + peakCol * 4 + locrefDxChannel] : 0.f;
        const float locrefDy = locData
            ? locData[peakRow * HEAT_COLS * 4 + peakCol * 4 + locrefDyChannel] : 0.f;

        // Crop-space pixel coordinates.
        const float cropX = (peakCol + 0.5f) * STRIDE + locrefDx * LOCREF_STD;
        const float cropY = (peakRow + 0.5f) * STRIDE + locrefDy * LOCREF_STD;

        // Mosaico-space pixel coordinates.
        const float mosaicX = cropX * scaleX + static_cast<float>(cropOffsetX);
        const float mosaicY = cropY * scaleY + static_cast<float>(cropOffsetY);

        if (channel == 0) {
            if (peakScore >= 0.75f)
                nosePoint = {cropX, cropY, peakScore};
            emit trackResult(fieldIndex, mosaicX, mosaicY, peakScore);
        } else {
            if (peakScore >= 0.75f)
                bodyPoint = {cropX, cropY, peakScore};
            emit bodyResult(fieldIndex, mosaicX, mosaicY, peakScore);
        }
    }

    // Rule-based behaviour classification (no ONNX behaviour models active).
    const bool validPose = m_scanners[fieldIndex].pushFrame(nosePoint, bodyPoint);
    if (!validPose) return;

    const int behaviorLabel = m_scanners[fieldIndex].classifySimple();
    emit behaviorResult(fieldIndex, behaviorLabel);
}
