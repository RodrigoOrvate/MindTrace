#include "onnx_tracker.h"
#include <QDebug>
#include <algorithm>
#include <thread>

OnnxTracker::OnnxTracker(QObject* parent)
    : QThread(parent)
    , m_env(ORT_LOGGING_LEVEL_WARNING, "MindTrace")
{}

OnnxTracker::~OnnxTracker()
{
    requestStop();
    wait(5000);
}

void OnnxTracker::loadModel(const QString& path)
{
    QMutexLocker lock(&m_mutex);
    m_modelPath = path;
}

void OnnxTracker::enqueueFrame(const QImage& frame, int videoW, int videoH)
{
    QMutexLocker lock(&m_mutex);
    m_pending    = {frame, videoW, videoH};
    m_hasPending = true;
    m_cond.wakeOne();
}

void OnnxTracker::requestStop()
{
    QMutexLocker lock(&m_mutex);
    m_stop = true;
    m_cond.wakeAll();
}

// ── Session creation ──────────────────────────────────────────────────────────

bool OnnxTracker::createSession()
{
    try {
        Ort::SessionOptions opts;
        opts.SetIntraOpNumThreads(2);
        opts.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);

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

void OnnxTracker::run()
{
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

void OnnxTracker::processJob(const Job& job)
{
    if (job.frame.isNull() || job.videoW <= 0 || job.videoH <= 0) return;

    const int halfW = job.videoW / 2;
    const int halfH = job.videoH / 2;
    const float scaleX = static_cast<float>(halfW) / MODEL_W;
    const float scaleY = static_cast<float>(halfH) / MODEL_H;

    // 3 active campos: top-left, top-right, bottom-left
    const int offsets[3][2] = {{0, 0}, {halfW, 0}, {0, halfH}};

    // Prepare all crops first (main thread), then infer in parallel
    struct CropJob { QImage crop; int campo, ox, oy; };
    CropJob cropJobs[3];
    int validCount = 0;
    for (int i = 0; i < 3; i++) {
        int ox = offsets[i][0];
        int oy = offsets[i][1];
        QImage crop = job.frame.copy(ox, oy, halfW, halfH);
        if (crop.isNull()) continue;
        if (crop.width() != MODEL_W || crop.height() != MODEL_H)
            crop = crop.scaled(MODEL_W, MODEL_H,
                               Qt::IgnoreAspectRatio, Qt::SmoothTransformation);
        crop = crop.convertToFormat(QImage::Format_RGB888);
        cropJobs[validCount++] = {std::move(crop), i, ox, oy};
    }

    // Launch one thread per campo — each uses its own Ort::Session
    std::vector<std::thread> threads;
    threads.reserve(validCount);
    for (int j = 0; j < validCount; j++) {
        const auto& cj = cropJobs[j];
        threads.emplace_back([this, &cj, scaleX, scaleY]() {
            inferCrop(cj.crop, cj.campo, cj.ox, cj.oy, scaleX, scaleY);
        });
    }
    for (auto& t : threads) t.join();
}

// ── Per-crop ONNX inference ───────────────────────────────────────────────────

void OnnxTracker::inferCrop(const QImage& crop, int campo,
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
