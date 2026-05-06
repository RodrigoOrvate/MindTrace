#pragma once

#include <QImage>
#include <QMutex>
#include <QString>
#include <QThread>
#include <QWaitCondition>

#include <atomic>
#include <memory>
#include <string>
#include <vector>

// Header-only C++ wrapper around the ONNX Runtime C API.
// Located in onnxruntime-win-x64-1.24.4/include/ (or the GPU variant for CUDA).
// Requires MSVC 14.4+ (VS 2022) and Windows 10+.
#include "onnxruntime_cxx_api.h"
#include "BehaviorScanner.h"

/// Runs ONNX pose and behaviour inference on video frames in a dedicated thread.
///
/// Frames are delivered via enqueueFrame() — thread-safe, single-slot queue that
/// always retains the most recent frame and discards any pending predecessor.
class InferenceEngine : public QThread
{
    Q_OBJECT
public:
    explicit InferenceEngine(QObject* parent = nullptr);
    ~InferenceEngine() override;

    /// Store the pose model path for loading at thread start. Call before start().
    void loadModel(const QString& modelPath);

    /// Store the behaviour model directory. Call before start().
    void loadBehaviorModel(const QString& behaviorModelDir);

    void setZones(int fieldIndex, const std::vector<Zone>& zones);
    void setFloorPolygon(int fieldIndex, const std::vector<std::pair<float, float>>& poly);

    /// Receive the current body velocity (m/s) for rule-based classification.
    void setVelocity(int fieldIndex, float velocity);

    /// EI mode: process the full frame as field 0 instead of the top-left quadrant.
    /// Must be called before start().
    void setFullFrameMode(bool enabled);

    /// Thread-safe. Replaces any pending frame with the new one (single-slot queue).
    void enqueueFrame(const QImage& frame, int videoWidth, int videoHeight);

    /// Manually set which quadrants map to which field.
    void setManualQuadrantMapping(const std::vector<int>& mapping);
    void clearManualQuadrantMapping();

    /// Signal the worker thread to exit cleanly on its next iteration.
    void requestStop();

    /// B-SOiD: read per-field frame history after stopAnalysis().
    const std::vector<FrameRecord>& getScannerHistory(int fieldIndex) const;
    void clearScannerHistory(int fieldIndex);

signals:
    /// Emitted (queued) when all ONNX sessions are loaded and ready.
    void modelReady();
    /// Nose keypoint — mosaico pixel coordinates.
    void trackResult(int fieldIndex, float x, float y, float likelihood);
    /// Body keypoint — mosaico pixel coordinates.
    void bodyResult(int fieldIndex, float x, float y, float likelihood);
    void behaviorResult(int fieldIndex, int labelId);
    void errorMsg(QString message);
    void infoMsg(QString message);

protected:
    void run() override;

private:
    struct PendingJob {
        QImage frame;
        int    videoWidth  = 0;
        int    videoHeight = 0;
    };

    bool createSession();
    bool tryCreateSessions(Ort::SessionOptions& sessionOptions);
    void processJob(const PendingJob& job);
    void inferCrop(const QImage& crop, int fieldIndex,
                   int cropOffsetX, int cropOffsetY,
                   float scaleX, float scaleY);

    // DLC ResNet-50 model constants.
    static constexpr float STRIDE     = 8.0f;
    static constexpr float LOCREF_STD = 7.2801f;
    static constexpr int   MODEL_W    = 360;
    static constexpr int   MODEL_H    = 240;
    static constexpr int   HEAT_ROWS  = 30;
    static constexpr int   HEAT_COLS  = 46;

    // Binary behaviour classifiers — one ONNX session per class, shared across all fields.
    struct BehaviorSessionInfo {
        std::unique_ptr<Ort::Session> session;
        std::string inputName;
        std::string probOutputName;
        int         behaviorIndex = 0;
    };

    Ort::Env                         m_env;
    std::unique_ptr<Ort::Session>    m_sessions[3];       // one per field — concurrent inference
    std::vector<BehaviorSessionInfo> m_behaviorSessions;  // shared across all fields

    std::string              m_inputName;
    std::vector<std::string> m_outputNames;

    bool              m_hasLocrefOutput = false;
    bool              m_behaviorEnabled = false;
    std::atomic<bool> m_fullFrame{false};

    QString        m_modelPath;
    QString        m_behaviorModelDir;
    QMutex         m_mutex;
    QWaitCondition m_cond;
    bool           m_pendingAvailable = false;
    bool           m_stopRequested    = false;
    PendingJob     m_pendingJob;

    BehaviorScanner m_scanners[3];
    std::vector<int> m_lastActiveQuadrants{0, 1, 2};
    std::vector<int> m_manualQuadrants;
    bool             m_manualQuadrantEnabled = false;
};
