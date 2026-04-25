#pragma once
#include <QObject>
#include <QMediaPlayer>
#include <QVideoSink>
#include <QVideoFrame>
#include <QCamera>
#include <QMediaCaptureSession>
#include <QMediaDevices>
#include <QMediaRecorder>
#include <QStringList>
#include <QImage>
#include <memory>
#include "inference_engine.h"
#include "dshow_capture.h"

// ── Inference Controller ───────────────────────────────────────────────────
// Headless QMediaPlayer feeds frames to QVideoSink (Qt 6 replacement for
// QAbstractVideoSurface). Every decoded frame is forwarded to InferenceEngine
// for inference. The visible video in QML uses a separate MediaPlayer with
// its own VideoOutput and can still use hardware acceleration.
class InferenceController : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool isAnalyzing READ isAnalyzing NOTIFY analyzingChanged)

public:
    explicit InferenceController(QObject* parent = nullptr);
    ~InferenceController() override;

    bool isAnalyzing() const;

    Q_INVOKABLE QString defaultModelDir() const;
    Q_INVOKABLE void loadBehaviorModel(const QString& behaviorModelPath);
    Q_INVOKABLE void setZones(int campo, const QList<QVariant>& zones);
    Q_INVOKABLE void setFloorPolygon(int campo, const QList<QVariant>& points);
    Q_INVOKABLE void setVelocity(int campo, float velocity);  // m/s para comportamento
    // EI: processa frame completo em vez de quadrante. Chamar antes de startAnalysis.
    Q_INVOKABLE void setFullFrameMode(bool enabled);
    Q_INVOKABLE void startAnalysis(const QString& videoPath, const QString& modelDir);
    Q_INVOKABLE void stopAnalysis();
    Q_INVOKABLE QVariantList listVideoInputs();
    Q_INVOKABLE void startLiveAnalysis(const QString& cameraName, const QString& modelDir);
    Q_INVOKABLE void startLiveAnalysis(const QString& cameraName,
                                       const QString& modelDir,
                                       const QString& saveDirectory,
                                       const QString& preferredFileName,
                                       int preferredWidth,
                                       int preferredHeight,
                                       double preferredFps);
    Q_INVOKABLE QString liveRecordingPath() const;
    Q_INVOKABLE bool startLivePreview(const QString& cameraName);
    Q_INVOKABLE void stopLivePreview();
    Q_INVOKABLE void setLivePreviewOutput(QObject* videoOutput);  // QML VideoOutput para display ao vivo
    Q_INVOKABLE void setPlaybackRate(double rate);
    Q_INVOKABLE qint64 position() const;
    Q_INVOKABLE void seekTo(qint64 ms);
    // B-SOiD: exporta CSV com features[21] + ruleLabel por frame para análise pós-sessão
    Q_INVOKABLE bool exportBehaviorFeatures(const QString& csvPath, int campo);
    // Revisão de bouts: retorna [{frameIdx, ruleLabel, movNose, movBody, movMean}] para QML
    Q_INVOKABLE QVariantList getBehaviorFrames(int campo) const;
    Q_INVOKABLE QString behaviorCachePath(const QString& experimentPath, int campo) const;
    Q_INVOKABLE bool behaviorCacheExists(const QString& experimentPath, int campo) const;
    Q_INVOKABLE bool saveBehaviorCache(const QString& experimentPath, int campo);
    Q_INVOKABLE QVariantList getBehaviorFramesFromCache(const QString& experimentPath, int campo) const;
    Q_INVOKABLE bool writeTextFile(const QString& filePath, const QString& content, bool utf8Bom = false);
    Q_INVOKABLE QString readTextFile(const QString& filePath) const;
    Q_INVOKABLE bool savePdfReport(const QString& pdfPath,
                                   const QStringList& imagePaths,
                                   const QString& title,
                                   const QStringList& captions = QStringList());

signals:
    void analyzingChanged();
    void readyReceived();                                       // Model loaded, tracking active
    void trackReceived(int campo, float x, float y, float p);  // Nose — mosaico px
    void bodyReceived (int campo, float x, float y, float p);  // Body — mosaico px
    void behaviorReceived(int campo, int labelId);             // Behavior classes
    void dimsReceived (int width, int height);
    void fpsReceived  (double fps);
    void errorOccurred(QString errorMsg);
    void infoReceived (QString message);

private slots:
    void onVideoFrameChanged(const QVideoFrame& frame);
    void onMediaStatusChanged(QMediaPlayer::MediaStatus status);

private:
    void setAnalyzing(bool v);
    void processImageFrame(QImage img);
    void onDirectShowFrame(const QImage& img);

    QMediaPlayer*         m_player;
    QVideoSink*           m_videoSink;
    InferenceEngine*      m_engine;

    // Live camera mode
    bool                  m_isLiveMode     = false;
    bool                  m_isDirectShowMode = false;
    QCamera*              m_camera         = nullptr;
    QMediaCaptureSession* m_captureSession = nullptr;
    QMediaRecorder*       m_mediaRecorder  = nullptr;
    QVideoSink*           m_livePreviewSink = nullptr;
    QString               m_liveRecordingPath;
    std::unique_ptr<DShowCapture> m_dshowCapture;

    bool m_isAnalyzing = false;
    bool m_isPreviewOnly = false;
    bool m_modelReady  = false;
    int  m_videoW      = 0;
    int  m_videoH      = 0;
    qint64 m_liveFpsWindowStartMs = 0;
    int    m_liveFpsFrameCount    = 0;
    bool   m_loggedLiveNullFrame  = false;

};
