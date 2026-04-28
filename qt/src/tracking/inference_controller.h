#pragma once

#include <QCamera>
#include <QImage>
#include <QMediaCaptureSession>
#include <QMediaDevices>
#include <QMediaPlayer>
#include <QMediaRecorder>
#include <QObject>
#include <QStringList>
#include <QVideoFrame>
#include <QVideoSink>

#include <memory>

#include "inference_engine.h"
#include "dshow_capture.h"

/// Headless QMediaPlayer feeds frames to QVideoSink (Qt 6 replacement for
/// QAbstractVideoSurface). Every decoded frame is forwarded to InferenceEngine
/// for ONNX inference. The visible video in QML uses a separate MediaPlayer +
/// VideoOutput pair and can still use hardware acceleration.
class InferenceController : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool isAnalyzing READ isAnalyzing NOTIFY analyzingChanged)

public:
    explicit InferenceController(QObject* parent = nullptr);
    ~InferenceController() override;

    bool isAnalyzing() const;

    Q_INVOKABLE QString defaultModelDir() const;

    /// Load a directory of per-behaviour ONNX classifiers at runtime.
    Q_INVOKABLE void loadBehaviorModel(const QString& behaviorModelPath);

    Q_INVOKABLE void setZones(int fieldIndex, const QList<QVariant>& zones);
    Q_INVOKABLE void setFloorPolygon(int fieldIndex, const QList<QVariant>& points);

    /// Pass the current body velocity (m/s) from QML for rule-based classification.
    Q_INVOKABLE void setVelocity(int fieldIndex, float velocity);

    /// EI mode: process the full frame as field 0. Call before startAnalysis.
    Q_INVOKABLE void setFullFrameMode(bool enabled);

    Q_INVOKABLE void startAnalysis(const QString& videoPath, const QString& modelDir);
    Q_INVOKABLE void stopAnalysis();

    /// Returns a QVariantList of {name, backend, ...} maps for each detected camera.
    Q_INVOKABLE QVariantList listVideoInputs();

    Q_INVOKABLE void startLiveAnalysis(const QString& cameraName, const QString& modelDir);
    Q_INVOKABLE void startLiveAnalysis(const QString& cameraName,
                                       const QString& modelDir,
                                       const QString& saveDirectory,
                                       const QString& preferredFileName,
                                       int            preferredWidth,
                                       int            preferredHeight,
                                       double         preferredFps);

    Q_INVOKABLE QString liveRecordingPath() const;

    Q_INVOKABLE bool startLivePreview(const QString& cameraName);
    Q_INVOKABLE void stopLivePreview();

    /// Connect the QML VideoOutput used for live display to the capture session.
    Q_INVOKABLE void setLivePreviewOutput(QObject* videoOutput);

    Q_INVOKABLE void   setPlaybackRate(double rate);
    Q_INVOKABLE qint64 position() const;
    Q_INVOKABLE void   seekTo(qint64 ms);

    /// Export a CSV with 21 features + ruleLabel per frame for B-SOiD analysis.
    Q_INVOKABLE bool exportBehaviorFeatures(const QString& csvPath, int fieldIndex);

    /// Returns [{frameIdx, ruleLabel, movNose, movBody, movMean}] for BoutEditorPanel.
    Q_INVOKABLE QVariantList getBehaviorFrames(int fieldIndex) const;

    Q_INVOKABLE QString      behaviorCachePath(const QString& experimentPath, int fieldIndex) const;
    Q_INVOKABLE bool         behaviorCacheExists(const QString& experimentPath, int fieldIndex) const;
    Q_INVOKABLE bool         saveBehaviorCache(const QString& experimentPath, int fieldIndex);
    Q_INVOKABLE QVariantList getBehaviorFramesFromCache(const QString& experimentPath, int fieldIndex) const;

    Q_INVOKABLE bool    writeTextFile(const QString& filePath, const QString& content,
                                      bool utf8Bom = false);
    Q_INVOKABLE QString readTextFile(const QString& filePath) const;

    Q_INVOKABLE bool savePdfReport(const QString& pdfPath,
                                   const QStringList& imagePaths,
                                   const QString& title,
                                   const QStringList& captions = QStringList());

signals:
    void analyzingChanged();
    void readyReceived();
    void trackReceived(int fieldIndex, float x, float y, float likelihood);
    void bodyReceived (int fieldIndex, float x, float y, float likelihood);
    void behaviorReceived(int fieldIndex, int labelId);
    void dimsReceived (int width, int height);
    void fpsReceived  (double fps);
    void errorOccurred(QString errorMsg);
    void infoReceived (QString message);

private slots:
    void onVideoFrameChanged(const QVideoFrame& frame);
    void onMediaStatusChanged(QMediaPlayer::MediaStatus status);

private:
    void setAnalyzing(bool analyzing);
    void processImageFrame(QImage img);
    void onDirectShowFrame(const QImage& img);

    QMediaPlayer*         m_player;
    QVideoSink*           m_videoSink;
    InferenceEngine*      m_engine;

    // Live camera mode state.
    bool                  m_isLiveMode       = false;
    bool                  m_isDirectShowMode = false;
    QCamera*              m_camera           = nullptr;
    QMediaCaptureSession* m_captureSession   = nullptr;
    QMediaRecorder*       m_mediaRecorder    = nullptr;
    QVideoSink*           m_livePreviewSink  = nullptr;
    QString               m_liveRecordingPath;
    std::unique_ptr<DShowCapture> m_dshowCapture;

    bool   m_isAnalyzing          = false;
    bool   m_isPreviewOnly        = false;
    bool   m_modelReady           = false;
    int    m_videoW               = 0;
    int    m_videoH               = 0;
    qint64 m_liveFpsWindowStartMs = 0;
    int    m_liveFpsFrameCount    = 0;
    qint64 m_liveTotalFrameCount  = 0;
    bool   m_loggedLiveNullFrame  = false;
};
