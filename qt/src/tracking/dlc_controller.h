#pragma once
#include <QObject>
#include <QMediaPlayer>
#include <QVideoSink>
#include <QVideoFrame>
#include "onnx_tracker.h"

// ── DLC Controller ─────────────────────────────────────────────────────────
// Headless QMediaPlayer feeds frames to QVideoSink (Qt 6 replacement for
// QAbstractVideoSurface). Every decoded frame is forwarded to OnnxTracker
// for inference. The visible video in QML uses a separate MediaPlayer with
// its own VideoOutput and can still use hardware acceleration.
class DlcController : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool isAnalyzing READ isAnalyzing NOTIFY analyzingChanged)

public:
    explicit DlcController(QObject* parent = nullptr);
    ~DlcController() override;

    bool isAnalyzing() const;

    Q_INVOKABLE QString defaultModelDir() const;
    Q_INVOKABLE void startAnalysis(const QString& videoPath, const QString& modelDir);
    Q_INVOKABLE void stopAnalysis();
    Q_INVOKABLE void setPlaybackRate(double rate);
    Q_INVOKABLE qint64 position() const;
    Q_INVOKABLE void seekTo(qint64 ms);

signals:
    void analyzingChanged();
    void readyReceived();                                       // Model loaded, tracking active
    void trackReceived(int campo, float x, float y, float p);  // Nose — mosaico px
    void bodyReceived (int campo, float x, float y, float p);  // Body — mosaico px
    void dimsReceived (int width, int height);
    void fpsReceived  (double fps);
    void errorOccurred(QString errorMsg);
    void infoReceived (QString message);

private slots:
    void onVideoFrameChanged(const QVideoFrame& frame);
    void onMediaStatusChanged(QMediaPlayer::MediaStatus status);

private:
    void setAnalyzing(bool v);

    QMediaPlayer* m_player;
    QVideoSink*   m_videoSink;
    OnnxTracker*  m_tracker;

    bool m_isAnalyzing = false;
    bool m_modelReady  = false;
    int  m_videoW      = 0;
    int  m_videoH      = 0;
};
