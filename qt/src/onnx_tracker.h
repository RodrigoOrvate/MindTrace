#pragma once
#include <QThread>
#include <QMutex>
#include <QWaitCondition>
#include <QImage>
#include <QString>
#include <memory>
#include <string>
#include <vector>
// Header-only C++ wrapper around the ONNX Runtime C API.
// Located in onnxruntime-win-x64-1.16.3/include/ (or copied to src/).
// Requires MSVC 14.2+ (VS 2019+) for constexpr BFloat16_t support.
#include "onnxruntime_cxx_api.h"

// Runs ONNX inference on video frames in a dedicated thread.
// Receives QImage frames via enqueueFrame() (thread-safe, single-slot queue —
// always processes the most recent frame).
class OnnxTracker : public QThread
{
    Q_OBJECT
public:
    explicit OnnxTracker(QObject* parent = nullptr);
    ~OnnxTracker() override;

    // Call before start(). Stores model path for loading inside run().
    void loadModel(const QString& modelPath);

    // Thread-safe. Replaces any pending frame with the new one.
    void enqueueFrame(const QImage& frame, int videoW, int videoH);

    // Ask the thread to exit cleanly.
    void requestStop();

signals:
    // Emitted (from tracker thread, use QueuedConnection) when model is ready.
    void modelReady();
    // Nose and body detections — mosaico pixel coordinates.
    void trackResult(int campo, float x, float y, float p);
    void bodyResult (int campo, float x, float y, float p);
    void errorMsg(QString msg);
    void infoMsg(QString msg);  // GPU/CPU mode report, general status

protected:
    void run() override;

private:
    struct Job {
        QImage frame;
        int    videoW = 0;
        int    videoH = 0;
    };

    bool createSession();
    void processJob(const Job& job);
    void inferCrop(const QImage& crop, int campo, int ox, int oy,
                   float scaleX, float scaleY);

    // Model constants (DLC ResNet-50 export)
    static constexpr float STRIDE     = 8.0f;
    static constexpr float LOCREF_STD = 7.2801f;
    static constexpr int   MODEL_W    = 360;
    static constexpr int   MODEL_H    = 240;
    static constexpr int   HEAT_ROWS  = 30;
    static constexpr int   HEAT_COLS  = 46;

    Ort::Env                      m_env;
    // One session per campo — allows 3 concurrent inferences
    std::unique_ptr<Ort::Session> m_sessions[3];
    std::string                   m_inputName;
    std::vector<std::string>      m_outputNames;
    bool                          m_hasLocref = false;

    QString        m_modelPath;
    QMutex         m_mutex;
    QWaitCondition m_cond;
    bool           m_hasPending = false;
    bool           m_stop       = false;
    Job            m_pending;
};
