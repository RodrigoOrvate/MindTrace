#include "inference_engine.h"

// GPU execution providers — priority: CUDA (NVIDIA) → DirectML (AMD/Intel) → CPU.
// CUDA:     requires onnxruntime-win-x64-gpu build + NVIDIA CUDA drivers.
// DirectML: requires onnxruntime-directml + DirectML.dll (from NuGet).
#include <d3d12.h>
#include <dxgi.h>

#include <QDebug>
#include <QDir>
#include <QFile>
#include <QPainter>
#include <QTextStream>
#include <QRegularExpression>

#include <algorithm>
#include <atomic>
#include <array>
#include <cmath>
#include <filesystem>
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

void InferenceEngine::beginRawTracking(const QString& experimentDir)
{
    // All raw tracking output lives under <experimentDir>/tracking/
    const QString trackingDir = experimentDir + "/tracking";
    m_rawTrackingDir = trackingDir;
    qDebug() << "[InferenceEngine] beginRawTracking path:" << trackingDir;
    for (auto& w : m_rawWriters) {
        if (w.file.is_open()) {
            w.file.flush();
            w.file.close();
        }
    }

    if (experimentDir.isEmpty()) return;

    // Ensure the tracking directory exists
    QDir().mkpath(trackingDir);

    for (int i = 0; i < 3; ++i) {
        const QString filePath = trackingDir + "/raw_tracking_campo" + QString::number(i + 1) + ".csv";
        m_rawWriters[i].file.open(std::filesystem::path(filePath.toStdWString()),
                      std::ios::out | std::ios::trunc);
        if (m_rawWriters[i].file.is_open()) {
            // UTF-8 BOM so Excel opens the file correctly
            m_rawWriters[i].file << "\xEF\xBB\xBF";
            m_rawWriters[i].file
                << "Frame,FieldIndex,CropOffsetX,CropOffsetY,ScaleX,ScaleY,"
                << "VideoW,VideoH,MosaicNoseX,MosaicNoseY,NoseLikelihood,"
                << "MosaicBodyX,MosaicBodyY,BodyLikelihood\n";
            m_rawWriters[i].frameCounter = 0;
            qDebug() << "[InferenceEngine] raw tracking writer opened:" << filePath;
        } else {
            qWarning() << "[InferenceEngine] could not open raw tracking writer:" << filePath;
        }
    }
}

void InferenceEngine::endRawTracking()
{
    for (auto& w : m_rawWriters) {
        if (w.file.is_open()) {
            w.file.flush();
            w.file.close();
        }
        w.frameCounter = 0;
    }
    if (!m_rawTrackingDir.isEmpty())
        generateTrackingMaps(m_rawTrackingDir);
    m_rawTrackingDir.clear();
}

void InferenceEngine::setTrackingAnimalNames(const QStringList& names)
{
    QMutexLocker lock(&m_mutex);
    m_trackingAnimalNames = names;
}

void InferenceEngine::generateTrackingMaps(const QString& experimentDir)
{
    struct TrackingPoint {
        double noseX = -1.0;
        double noseY = -1.0;
        double bodyX = -1.0;
        double bodyY = -1.0;
        double noseLikelihood = 0.0;
        double bodyLikelihood = 0.0;
    };

    // Jet colormap: maps t in [0,1] to RGB  (matches matplotlib 'jet')
    const auto jetColor = [](double t) -> QColor {
        if (t < 0.0) t = 0.0; else if (t > 1.0) t = 1.0;
        double r, g, b;
        if      (t < 0.125) { r = 0.0;           g = 0.0;               b = 0.5 + t * 4.0; }
        else if (t < 0.375) { r = 0.0;           g = (t-0.125)*4.0;     b = 1.0; }
        else if (t < 0.625) { r = (t-0.375)*4.0; g = 1.0;               b = 1.0-(t-0.375)*4.0; }
        else if (t < 0.875) { r = 1.0;           g = 1.0-(t-0.625)*4.0; b = 0.0; }
        else                { r = 1.0-(t-0.875)*4.0; g = 0.0;           b = 0.0; }
        return QColor::fromRgbF(r, g, b);
    };

    // Purples colormap: light lavender to dark purple  (mimics matplotlib Purples)
    const auto purpleColor = [](double t) -> QColor {
        if (t < 0.0) t = 0.0; else if (t > 1.0) t = 1.0;
        const int r = static_cast<int>(242.0 + t * (63.0  - 242.0));
        const int g = static_cast<int>(240.0 + t * (0.0   - 240.0));
        const int b = static_cast<int>(247.0 + t * (125.0 - 247.0));
        return QColor(r, g, b);
    };

    QStringList animalNames;
    {
        QMutexLocker lock(&m_mutex);
        animalNames = m_trackingAnimalNames;
    }

    for (int fieldIndex = 0; fieldIndex < 3; ++fieldIndex) {
        QFile input(experimentDir + "/raw_tracking_campo" + QString::number(fieldIndex + 1) + ".csv");
        if (!input.open(QIODevice::ReadOnly | QIODevice::Text))
            continue;

        QTextStream stream(&input);
        stream.readLine();   // skip header
        std::vector<TrackingPoint> points;
        int cropWidth  = 720;
        int cropHeight = 480;
        while (!stream.atEnd()) {
            const QStringList cols = stream.readLine().trimmed().split(',');
            if (cols.size() < 14) continue;
            bool ok1, ok2, ok3, ok4;
            const double offsetX = cols.at(2).toDouble(&ok1);
            const double offsetY = cols.at(3).toDouble(&ok2);
            const double scaleX  = cols.at(4).toDouble(&ok3);
            const double scaleY  = cols.at(5).toDouble(&ok4);
            if (!ok1 || !ok2 || !ok3 || !ok4 || scaleX <= 0 || scaleY <= 0) continue;
            cropWidth  = static_cast<int>(std::lround(scaleX * MODEL_W));
            cropHeight = static_cast<int>(std::lround(scaleY * MODEL_H));
            if (cropWidth  < 1) cropWidth  = 1;
            if (cropHeight < 1) cropHeight = 1;

            TrackingPoint pt;
            bool v;
            pt.noseX = cols.at(8).toDouble(&v)  - offsetX; if (!v) continue;
            pt.noseY = cols.at(9).toDouble(&v)  - offsetY; if (!v) continue;
            pt.noseLikelihood = cols.at(10).toDouble(&v);   if (!v) continue;
            pt.bodyX = cols.at(11).toDouble(&v) - offsetX; if (!v) continue;
            pt.bodyY = cols.at(12).toDouble(&v) - offsetY; if (!v) continue;
            pt.bodyLikelihood = cols.at(13).toDouble(&v);   if (!v) continue;
            points.push_back(pt);
        }
        input.close();

        if (points.empty()) continue;

        // ── Filtering and Smoothing ─────────────────────────────────────────
        auto calcPercentile = [](std::vector<double> v, double p) -> double {
            if (v.empty()) return 0.0;
            if (v.size() == 1) return v.front();
            std::sort(v.begin(), v.end());
            double index = p * (v.size() - 1);
            size_t lower = static_cast<size_t>(index);
            size_t upper = lower + 1;
            double weight = index - lower;
            if (upper >= v.size()) return v.back();
            return v[lower] * (1.0 - weight) + v[upper] * weight;
        };

        // 1. IQR Filter
        std::vector<double> rawXs, rawYs;
        for (const auto& pt : points) {
            if (pt.bodyLikelihood >= 0.5) {
                rawXs.push_back(pt.bodyX);
                rawYs.push_back(pt.bodyY);
            }
        }

        if (rawXs.size() >= 5) {
            double q1_x = calcPercentile(rawXs, 0.25);
            double q3_x = calcPercentile(rawXs, 0.75);
            double q1_y = calcPercentile(rawYs, 0.25);
            double q3_y = calcPercentile(rawYs, 0.75);

            double dispersao = ((q3_x - q1_x) + (q3_y - q1_y)) / 2.0;
            double limite_iqr = 1.5;
            if (dispersao > 150) limite_iqr = 0.4;
            else if (dispersao > 120) limite_iqr = 0.6;
            else if (dispersao > 90) limite_iqr = 0.8;
            else if (dispersao > 60) limite_iqr = 1.0;
            else if (dispersao > 30) limite_iqr = 1.2;

            double iqr_x = q3_x - q1_x;
            if (iqr_x < 10.0) iqr_x = 10.0;
            double iqr_y = q3_y - q1_y;
            if (iqr_y < 10.0) iqr_y = 10.0;
            double min_x = q1_x - limite_iqr * iqr_x;
            double max_x = q3_x + limite_iqr * iqr_x;
            double min_y = q1_y - limite_iqr * iqr_y;
            double max_y = q3_y + limite_iqr * iqr_y;

            for (auto& pt : points) {
                if (pt.bodyLikelihood >= 0.5) {
                    if (pt.bodyX < min_x || pt.bodyX > max_x || pt.bodyY < min_y || pt.bodyY > max_y) {
                        pt.bodyLikelihood = 0.0;
                    }
                }
            }
        }

        // 2. Jump Filter
        std::vector<double> dists;
        double last_x = -1, last_y = -1;
        for (const auto& pt : points) {
            if (pt.bodyLikelihood >= 0.5) {
                if (last_x >= 0) {
                    dists.push_back(std::hypot(pt.bodyX - last_x, pt.bodyY - last_y));
                }
                last_x = pt.bodyX;
                last_y = pt.bodyY;
            }
        }

        if (dists.size() >= 5) {
            double mean_dist = 0.0;
            for (double d : dists) mean_dist += d;
            mean_dist /= dists.size();

            double p95 = calcPercentile(dists, 0.95);
            double p99 = calcPercentile(dists, 0.99);
            double limite_salto = p95 * 1.5;
            if (p99 > limite_salto) limite_salto = p99;
            if (mean_dist * 3.0 > limite_salto) limite_salto = mean_dist * 3.0;
            if (12.0 > limite_salto) limite_salto = 12.0;

            // Re-eval valid points for mobility check
            std::vector<double> mobXs, mobYs;
            for (const auto& pt : points) {
                if (pt.bodyLikelihood >= 0.5) {
                    mobXs.push_back(pt.bodyX);
                    mobYs.push_back(pt.bodyY);
                }
            }
            
            if (mobXs.size() >= 5) {
                double span_x = calcPercentile(mobXs, 0.95) - calcPercentile(mobXs, 0.05);
                double span_y = calcPercentile(mobYs, 0.95) - calcPercentile(mobYs, 0.05);
                bool baixa_mobilidade = (p95 < 3.0) || (span_x < 20.0 && span_y < 20.0);

                if (!baixa_mobilidade) {
                    std::vector<double> point_dists(points.size(), 0.0);
                    last_x = -1;
                    last_y = -1;
                    for (size_t i = 0; i < points.size(); ++i) {
                        if (points[i].bodyLikelihood >= 0.5) {
                            if (last_x >= 0) {
                                point_dists[i] = std::hypot(points[i].bodyX - last_x, points[i].bodyY - last_y);
                            }
                            last_x = points[i].bodyX;
                            last_y = points[i].bodyY;
                        }
                    }

                    for (size_t i = 0; i < points.size(); ++i) {
                        if (points[i].bodyLikelihood >= 0.5) {
                            if (point_dists[i] > limite_salto) {
                                points[i].bodyLikelihood = 0.0; // Filter out jump
                            }
                        }
                    }
                }
            }
        }

        // 3. Savitzky-Golay Filter (Window=11, Poly=3)
        std::vector<size_t> valid_idxs;
        std::vector<double> valid_xs, valid_ys;
        for (size_t k = 0; k < points.size(); ++k) {
            if (points[k].bodyLikelihood >= 0.5) {
                valid_idxs.push_back(k);
                valid_xs.push_back(points[k].bodyX);
                valid_ys.push_back(points[k].bodyY);
            }
        }

        const int w = 11;
        if (valid_idxs.size() >= static_cast<size_t>(w)) {
            std::vector<double> smoothed_xs = valid_xs;
            std::vector<double> smoothed_ys = valid_ys;
            const double coeffs[11] = {-36, 9, 44, 69, 84, 89, 84, 69, 44, 9, -36};
            const double norm = 429.0;
            const int half_w = 5;

            for (size_t k = half_w; k < valid_xs.size() - half_w; ++k) {
                double sum_x = 0, sum_y = 0;
                for (int j = -half_w; j <= half_w; ++j) {
                    sum_x += valid_xs[k + j] * coeffs[j + half_w];
                    sum_y += valid_ys[k + j] * coeffs[j + half_w];
                }
                smoothed_xs[k] = sum_x / norm;
                smoothed_ys[k] = sum_y / norm;
            }

            for (size_t k = 0; k < valid_idxs.size(); ++k) {
                points[valid_idxs[k]].bodyX = smoothed_xs[k];
                points[valid_idxs[k]].bodyY = smoothed_ys[k];
            }
        }

        // ── Dynamic Scaling (fit to 60x60 cm plot) ──────────────────────────
        double minX = 1e9, maxX = -1e9;
        double minY = 1e9, maxY = -1e9;
        for(const auto& pt: points) {
            if (pt.bodyLikelihood < 0.5) continue;
            if (pt.bodyX < minX) minX = pt.bodyX;
            if (pt.bodyX > maxX) maxX = pt.bodyX;
            if (pt.bodyY < minY) minY = pt.bodyY;
            if (pt.bodyY > maxY) maxY = pt.bodyY;
        }
        if (minX > maxX) { minX = 0; maxX = cropWidth; }
        if (minY > maxY) { minY = 0; maxY = cropHeight; }
        
        // Add 2% padding
        double padX = (maxX - minX) * 0.02;
        double padY = (maxY - minY) * 0.02;
        minX -= padX; maxX += padX;
        minY -= padY; maxY += padY;
        if (maxX - minX < 1) maxX = minX + 1;
        if (maxY - minY < 1) maxY = minY + 1;

        // ── Layout constants ────────────────────────────────────────────────
        const int plotLeft    = 100;
        const int plotTop     = 68;
        const int plotSize    = 720;
        const int colorbarLeft = plotLeft + plotSize + 35;
        const int colorbarW   = 22;
        const int colorbarH   = plotSize;
        const int imageWidth  = colorbarLeft + 100;
        const int imageHeight = plotTop + plotSize + 90;

        // Map body coords (dynamic bounding box) → image pixels.
        const auto plotPoint = [&](double x, double y) {
            return QPointF(plotLeft + (x - minX) * plotSize / (maxX - minX),
                           plotTop  + plotSize - (y - minY) * plotSize / (maxY - minY));
        };

        // Labels
        const QString animalLabel = (fieldIndex < animalNames.size() && !animalNames.at(fieldIndex).isEmpty())
                                    ? animalNames.at(fieldIndex)
                                    : QStringLiteral("Animal %1").arg(fieldIndex + 1);
        const QString campoLabel  = QStringLiteral("Campo %1").arg(fieldIndex + 1);

        // Sanitize animal name for filenames
        QString safeAnimalName = animalLabel;
        safeAnimalName.replace(" ", "_");
        safeAnimalName.replace(QRegularExpression("[^a-zA-Z0-9_-]"), "");

        // ── Directory Structure ──────────────────────────────────────────────
        const QString trajPngDir = experimentDir + "/tracking/trajectory/png";
        const QString trajSvgDir = experimentDir + "/tracking/trajectory/svg";
        const QString heatPngDir = experimentDir + "/tracking/heatmap/png";
        const QString heatSvgDir = experimentDir + "/tracking/heatmap/svg";
        
        QDir().mkpath(trajPngDir);
        QDir().mkpath(trajSvgDir);
        QDir().mkpath(heatPngDir);
        QDir().mkpath(heatSvgDir);
        
        const QString baseTrajPng = trajPngDir + QStringLiteral("/tracking_trajectory_campo%1_%2.png").arg(fieldIndex + 1).arg(safeAnimalName);
        const QString baseTrajSvg = trajSvgDir + QStringLiteral("/tracking_trajectory_campo%1_%2.svg").arg(fieldIndex + 1).arg(safeAnimalName);
        const QString baseHeatPng = heatPngDir + QStringLiteral("/tracking_heatmap_campo%1_%2.png").arg(fieldIndex + 1).arg(safeAnimalName);
        const QString baseHeatSvg = heatSvgDir + QStringLiteral("/tracking_heatmap_campo%1_%2.svg").arg(fieldIndex + 1).arg(safeAnimalName);

        // ── Shared grid helper ──────────────────────────────────────────────
        const auto drawGrid = [&](QPainter& p, bool darkMode) {
            const QColor borderCol  = darkMode ? QColor(200,200,200)       : QColor("#333333");
            const QColor gridCol    = darkMode ? QColor(255,255,255,55)    : QColor(180,180,180,180);
            const QColor tickCol    = darkMode ? Qt::white                 : Qt::black;
            p.setPen(QPen(borderCol, 1.5));
            p.setBrush(Qt::NoBrush);
            p.drawRect(plotLeft, plotTop, plotSize, plotSize);
            p.setPen(QPen(gridCol, 1, Qt::DotLine));
            for (int s = 1; s < 6; ++s) {
                p.drawLine(plotLeft + s * plotSize / 6, plotTop,
                           plotLeft + s * plotSize / 6, plotTop + plotSize);
                p.drawLine(plotLeft, plotTop + s * plotSize / 6,
                           plotLeft + plotSize, plotTop + s * plotSize / 6);
            }
            p.setPen(tickCol);
            p.setFont(QFont("Segoe UI", 10));
            for (int s = 0; s <= 6; ++s) {
                const int xPx = plotLeft + s * plotSize / 6;
                const int yPx = plotTop  + (6 - s) * plotSize / 6;
                p.drawText(xPx - 10, plotTop + plotSize + 18, QString::number(s * 10));
                p.drawText(plotLeft - 38, yPx + 4,            QString::number(s * 10));
            }
            p.setFont(QFont("Segoe UI", 11));
            p.drawText(plotLeft + plotSize/2 - 22, plotTop + plotSize + 44, "X (cm)");
            p.save();
            p.translate(32, plotTop + plotSize/2 + 22);
            p.rotate(-90);
            p.drawText(0, 0, "Y (cm)");
            p.restore();
        };

        // ── 1. TRAJECTORY PLOT (Purples colormap) ──────────────────────────
        {
            QImage img(imageWidth, imageHeight, QImage::Format_ARGB32);
            img.fill(Qt::white);
            QPainter tp(&img);
            tp.setRenderHint(QPainter::Antialiasing);

            drawGrid(tp, false);

            const size_t nPts = points.size();
            for (size_t i = 1; i < nPts; ++i) {
                const auto& prev = points[i - 1];
                const auto& curr = points[i];
                if (prev.bodyLikelihood < 0.5 || curr.bodyLikelihood < 0.5) continue;
                const double t = static_cast<double>(i) / static_cast<double>(nPts > 1 ? nPts - 1 : 1);
                tp.setPen(QPen(purpleColor(t), 2.5, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
                tp.drawLine(plotPoint(prev.bodyX, prev.bodyY), plotPoint(curr.bodyX, curr.bodyY));
            }

            // Title (two lines)
            tp.setPen(Qt::black);
            tp.setFont(QFont("Segoe UI", 18, QFont::Bold));
            tp.drawText(QRect(plotLeft, 6, plotSize, 30),
                        Qt::AlignHCenter | Qt::AlignVCenter,
                        "Trajetória — " + campoLabel);
            tp.setFont(QFont("Segoe UI", 11));
            tp.drawText(QRect(plotLeft, 35, plotSize, 22),
                        Qt::AlignHCenter | Qt::AlignVCenter,
                        "Animal: " + animalLabel);

            // Colorbar: light (início) at bottom → dark (fim) at top
            tp.setPen(Qt::NoPen);
            for (int cs = 0; cs < colorbarH; ++cs) {
                const double t = 1.0 - static_cast<double>(cs) / static_cast<double>(colorbarH - 1);
                tp.setBrush(purpleColor(t));
                tp.drawRect(colorbarLeft, plotTop + cs, colorbarW, 2);
            }
            tp.setPen(Qt::black);
            tp.setFont(QFont("Segoe UI", 9));
            tp.drawText(colorbarLeft, plotTop - 3, "Fim");
            tp.drawText(colorbarLeft, plotTop + colorbarH + 11, "Início");
            tp.save();
            tp.translate(colorbarLeft + colorbarW + 14, plotTop + colorbarH / 2 + 22);
            tp.rotate(-90);
            tp.drawText(0, 0, "Tempo");
            tp.restore();

            tp.end();
            img.save(baseTrajPng);
        }

        // ── 2. HEATMAP PLOT (visitation frequency, Jet colormap) ───────────
        const int heatBins = 60;
        std::vector<int> visitCount(heatBins * heatBins, 0);
        int maxCount = 0;
        for (const auto& pt : points) {
            if (pt.bodyLikelihood < 0.5) continue;
            const int bx = static_cast<int>((pt.bodyX - minX) / (maxX - minX) * heatBins);
            const int by = static_cast<int>((pt.bodyY - minY) / (maxY - minY) * heatBins);
            const int safeBx = (bx < 0) ? 0 : ((bx >= heatBins) ? heatBins - 1 : bx);
            const int safeBy = (by < 0) ? 0 : ((by >= heatBins) ? heatBins - 1 : by);
            const int idx = safeBy * heatBins + safeBx;
            if (++visitCount[idx] > maxCount) maxCount = visitCount[idx];
        }
        if (maxCount < 1) maxCount = 1;

        {
            QImage img(imageWidth, imageHeight, QImage::Format_ARGB32);
            img.fill(QColor("#050510"));
            QPainter hp(&img);
            hp.setRenderHint(QPainter::Antialiasing, false);

            // Dark background for the plot area (unvisited = near-black)
            hp.setPen(Qt::NoPen);
            hp.setBrush(QColor(8, 8, 28));
            hp.drawRect(plotLeft, plotTop, plotSize, plotSize);

            // Heatmap cells (log scale for better visual contrast)
            const int cellSize = plotSize / heatBins;
            for (int by = 0; by < heatBins; ++by) {
                for (int bx = 0; bx < heatBins; ++bx) {
                    const int cnt = visitCount[by * heatBins + bx];
                    if (cnt == 0) continue;
                    const double t = std::log1p(static_cast<double>(cnt)) /
                                     std::log1p(static_cast<double>(maxCount));
                    hp.setBrush(jetColor(t));
                    hp.drawRect(plotLeft + bx * cellSize,
                                plotTop  + plotSize - (by + 1) * cellSize,
                                cellSize + 1, cellSize + 1);
                }
            }

            hp.setRenderHint(QPainter::Antialiasing);

            drawGrid(hp, true);

            // Title
            hp.setPen(Qt::white);
            hp.setFont(QFont("Segoe UI", 18, QFont::Bold));
            hp.drawText(QRect(plotLeft, 6, plotSize, 30),
                        Qt::AlignHCenter | Qt::AlignVCenter,
                        "Mapa de Calor — " + campoLabel);
            hp.setFont(QFont("Segoe UI", 11));
            hp.drawText(QRect(plotLeft, 35, plotSize, 22),
                        Qt::AlignHCenter | Qt::AlignVCenter,
                        "Animal: " + animalLabel);

            // Colorbar (jet: top=red=high, bottom=blue=low)
            hp.setPen(Qt::NoPen);
            for (int cs = 0; cs < colorbarH; ++cs) {
                const double t = 1.0 - static_cast<double>(cs) / static_cast<double>(colorbarH - 1);
                hp.setBrush(jetColor(t));
                hp.drawRect(colorbarLeft, plotTop + cs, colorbarW, 2);
            }
            hp.setPen(Qt::white);
            hp.setFont(QFont("Segoe UI", 9));
            hp.drawText(colorbarLeft, plotTop - 3, "Alto");
            hp.drawText(colorbarLeft, plotTop + colorbarH + 11, "Baixo");
            hp.save();
            hp.translate(colorbarLeft + colorbarW + 14, plotTop + colorbarH / 2 + 32);
            hp.rotate(-90);
            hp.drawText(0, 0, "Frequência");
            hp.restore();

            hp.end();
            img.save(baseHeatPng);
        }

        // ── 3. SVG OUTPUTS (Trajectory and Heatmap) ────────────────────────
        {
            // ViewBox perfectly wraps the dynamic bounding box
            const double vbW = maxX - minX;
            const double vbH = maxY - minY;
            const QString svgStart = QStringLiteral("<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"%1 %2 %3 %4\" width=\"100%\" height=\"100%\">\n<rect x=\"%1\" y=\"%2\" width=\"%3\" height=\"%4\" fill=\"#101024\"/>\n")
                                         .arg(minX).arg(minY).arg(vbW).arg(vbH);
            const QString svgEnd = QStringLiteral("</svg>\n");

            // --- Trajectory SVG ---
            QFile svgTraj(baseTrajSvg);
            if (svgTraj.open(QIODevice::WriteOnly | QIODevice::Text)) {
                QTextStream out(&svgTraj);
                out << svgStart;
                QStringList pts;
                for (const auto& pt : points) {
                    if (pt.bodyLikelihood >= 0.5)
                        pts << QString::number(pt.bodyX, 'f', 1) + "," + QString::number(pt.bodyY, 'f', 1);
                }
                if (!pts.isEmpty())
                    out << "<polyline points=\"" << pts.join(' ') << "\" fill=\"none\" stroke=\"#b07bff\" stroke-width=\"2\"/>\n";
                out << svgEnd;
            }

            // --- Heatmap SVG ---
            QFile svgHeat(baseHeatSvg);
            if (svgHeat.open(QIODevice::WriteOnly | QIODevice::Text)) {
                QTextStream out(&svgHeat);
                out << svgStart;
                
                const double binW = vbW / heatBins;
                const double binH = vbH / heatBins;
                
                for (int by = 0; by < heatBins; ++by) {
                    for (int bx = 0; bx < heatBins; ++bx) {
                        const int cnt = visitCount[by * heatBins + bx];
                        if (cnt == 0) continue;
                        const double t = std::log1p(static_cast<double>(cnt)) /
                                         std::log1p(static_cast<double>(maxCount));
                        QColor c = jetColor(t);
                        out << "<rect x=\"" << (minX + bx * binW) << "\" y=\"" << (minY + by * binH) 
                            << "\" width=\"" << binW << "\" height=\"" << binH 
                            << "\" fill=\"" << c.name() << "\"/>\n";
                    }
                }
                out << svgEnd;
            }
        }
    }
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

    // --- Write raw coordinates to per-field CSV ---
    // Logged unconditionally (before the behaviour-validity check below) so
    // every processed frame gets a row with a contiguous frame index, which
    // downstream trajectory/heatmap generation relies on. Previously this
    // block sat after the `validPose` early-return and was skipped for every
    // frame where the behaviour scanner's warm-up window hadn't filled yet.
    auto& writer = m_rawWriters[fieldIndex];
    if (writer.file.is_open()) {
        writer.frameCounter++;
        // Columns: Frame, FieldIndex, CropOffsetX, CropOffsetY, ScaleX, ScaleY,
        //          VideoW, VideoH, MosaicNoseX, MosaicNoseY, NoseLikelihood,
        //          MosaicBodyX, MosaicBodyY, BodyLikelihood
        writer.file << writer.frameCounter << ','
                    << fieldIndex << ','
                    << cropOffsetX << ',' << cropOffsetY << ','
                    << scaleX << ',' << scaleY << ','
                    << static_cast<int>(scaleX * MODEL_W * 2) << ','
                    << static_cast<int>(scaleY * MODEL_H * 2) << ','
                    << static_cast<int>(nosePoint.x * scaleX + cropOffsetX) << ','
                    << static_cast<int>(nosePoint.y * scaleY + cropOffsetY) << ','
                    << nosePoint.p << ','
                    << static_cast<int>(bodyPoint.x * scaleX + cropOffsetX) << ','
                    << static_cast<int>(bodyPoint.y * scaleY + cropOffsetY) << ','
                    << bodyPoint.p << '\n';
    }

    // Rule-based behaviour classification (no ONNX behaviour models active).
    const bool validPose = m_scanners[fieldIndex].pushFrame(nosePoint, bodyPoint);
    if (!validPose) return;

    const int behaviorLabel = m_scanners[fieldIndex].classifySimple();
    emit behaviorResult(fieldIndex, behaviorLabel);
}