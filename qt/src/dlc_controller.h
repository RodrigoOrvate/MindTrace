#pragma once
#include <QObject>
#include <QMediaPlayer>
#include <QAbstractVideoSurface>
#include <QVideoFrame>
#include "onnx_tracker.h"

// ── Frame capture surface ──────────────────────────────────────────────────
// Registers as the video output on the headless C++ QMediaPlayer.
// Forces WMF to decode to CPU memory (no DXVA), giving us every frame
// for ONNX inference. The visible video is handled by a separate QML
// MediaPlayer (displayPlayer), which can still use hardware acceleration.
class FrameCaptureSurface : public QAbstractVideoSurface
{
    Q_OBJECT
public:
    explicit FrameCaptureSurface(QObject* parent = nullptr)
        : QAbstractVideoSurface(parent) {}

    QList<QVideoFrame::PixelFormat> supportedPixelFormats(
        QAbstractVideoBuffer::HandleType type) const override
    {
        Q_UNUSED(type);
        return {
            QVideoFrame::Format_RGB32,
            QVideoFrame::Format_ARGB32,
            QVideoFrame::Format_ARGB32_Premultiplied,
            QVideoFrame::Format_RGB24,
            QVideoFrame::Format_BGR24,
            QVideoFrame::Format_BGRA32,
            QVideoFrame::Format_BGRA32_Premultiplied,
        };
    }

    bool present(const QVideoFrame& frame) override
    {
        QVideoFrame f = frame;
        const int w = f.width();
        const int h = f.height();
        if (!f.map(QAbstractVideoBuffer::ReadOnly)) return false;

        QImage::Format fmt = QVideoFrame::imageFormatFromPixelFormat(f.pixelFormat());
        QImage img;
        if (fmt != QImage::Format_Invalid)
            img = QImage(f.bits(), w, h, f.bytesPerLine(), fmt).copy();
        else
            img = QImage(f.bits(), w, h, f.bytesPerLine(), QImage::Format_RGB32).copy();
        f.unmap();

        if (!img.isNull())
            emit frameReady(img, w, h);
        return true;
    }

signals:
    void frameReady(QImage img, int w, int h);
};

// ── DLC Controller ─────────────────────────────────────────────────────────
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
    void onFrameCaptured(const QImage& img, int w, int h);
    void onMediaStatusChanged(QMediaPlayer::MediaStatus status);

private:
    void setAnalyzing(bool v);

    QMediaPlayer*        m_player;
    FrameCaptureSurface* m_captureSurface;
    OnnxTracker*         m_tracker;

    bool m_isAnalyzing = false;
    bool m_modelReady  = false;
    int  m_videoW      = 0;
    int  m_videoH      = 0;
};
