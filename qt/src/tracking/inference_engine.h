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
// Located in onnxruntime-win-x64-1.24.4/include/ (or onnxruntime-win-x64-gpu-1.24.4 for CUDA).
// Requires MSVC 14.4+ (VS 2022). Windows 10+ required.
#include "onnxruntime_cxx_api.h"
#include "BehaviorScanner.h"

// Runs ONNX inference on video frames in a dedicated thread.
// Receives QImage frames via enqueueFrame() (thread-safe, single-slot queue —
// always processes the most recent frame).
class InferenceEngine : public QThread
{
    Q_OBJECT
public:
    explicit InferenceEngine(QObject* parent = nullptr);
    ~InferenceEngine() override;

    // Call before start(). Stores model path for loading inside run().
    void loadModel(const QString& modelPath);
    void loadBehaviorModel(const QString& behaviorModelPath);
    void setZones(int campo, const std::vector<Zone>& zones);
    void setFloorPolygon(int campo, const std::vector<std::pair<float,float>>& poly);
    void setVelocity(int campo, float velocity);  // m/s para comportamento

    // Thread-safe. Replaces any pending frame with the new one.
    void enqueueFrame(const QImage& frame, int videoW, int videoH);

    // Ask the thread to exit cleanly.
    void requestStop();

    // B-SOiD: acesso ao histórico de frames de cada scanner (leitura após stopAnalysis)
    const std::vector<FrameRecord>& getScannerHistory(int campo) const;
    void clearScannerHistory(int campo);

signals:
    // Emitted (from tracker thread, use QueuedConnection) when model is ready.
    void modelReady();
    // Nose and body detections — mosaico pixel coordinates.
    void trackResult(int campo, float x, float y, float p);
    void bodyResult (int campo, float x, float y, float p);
    void behaviorResult(int campo, int labelId);
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
    bool tryCreateSessions(Ort::SessionOptions& opts);
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

    // One behavior session per behavior class (binary classifiers — one .onnx each).
    struct BehaviorSessionInfo {
        std::unique_ptr<Ort::Session> session;
        std::string inputName;
        std::string probOutputName;
        int behaviorIndex;
    };

    Ort::Env                      m_env;
    // One session per campo for pose — allows 3 concurrent inferences
    std::unique_ptr<Ort::Session> m_sessions[3];
    // One session per behavior class (shared across all campi)
    std::vector<BehaviorSessionInfo> m_behaviorSessions;

    std::string                   m_inputName;
    std::vector<std::string>      m_outputNames;

    bool                          m_hasLocref = false;
    bool                          m_behaviorEnabled = false;

    QString        m_modelPath;
    QString        m_bModelDir;  // directory containing individual behavior .onnx files
    QMutex         m_mutex;
    QWaitCondition m_cond;
    bool           m_hasPending = false;
    bool           m_stop       = false;
    Job            m_pending;

    BehaviorScanner m_scanners[3];
};
