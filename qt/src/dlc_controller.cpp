#include "dlc_controller.h"
#include <QCoreApplication>
#include <QStandardPaths>
#include <QFile>
#include <QImage>
#include <QMetaObject>
#include <QDebug>

DlcController::DlcController(QObject* parent)
    : QObject(parent)
    , m_player(new QMediaPlayer(this))
    , m_captureSurface(new FrameCaptureSurface(this))
    , m_tracker(new OnnxTracker(this))
{
    // ── Register capture surface as the player's video output ────────────────
    // This forces WMF to decode frames to CPU memory instead of DXVA,
    // making every frame available for ONNX inference.
    m_player->setVideoOutput(m_captureSurface);

    // ── Frame capture → tracker (multimedia thread, DirectConnection) ────────
    connect(m_captureSurface, &FrameCaptureSurface::frameReady,
            this, &DlcController::onFrameCaptured,
            Qt::DirectConnection);

    // ── OnnxTracker signals → DlcController signals ──────────────────────────
    connect(m_tracker, &OnnxTracker::modelReady, this, [this]() {
        m_modelReady = true;
        emit readyReceived();
    }, Qt::QueuedConnection);

    connect(m_tracker, &OnnxTracker::trackResult, this,
            [this](int c, float x, float y, float p) {
                emit trackReceived(c, x, y, p);
            }, Qt::QueuedConnection);

    connect(m_tracker, &OnnxTracker::bodyResult, this,
            [this](int c, float x, float y, float p) {
                emit bodyReceived(c, x, y, p);
            }, Qt::QueuedConnection);

    connect(m_tracker, &OnnxTracker::errorMsg, this,
            [this](QString msg) { emit errorOccurred(msg); },
            Qt::QueuedConnection);

    connect(m_tracker, &OnnxTracker::infoMsg, this,
            [this](QString msg) { emit infoReceived(msg); },
            Qt::QueuedConnection);

    // ── Media player status ───────────────────────────────────────────────────
    connect(m_player, &QMediaPlayer::mediaStatusChanged,
            this, &DlcController::onMediaStatusChanged);
}

DlcController::~DlcController()
{
    stopAnalysis();
}

// ── Properties ────────────────────────────────────────────────────────────────

bool DlcController::isAnalyzing() const { return m_isAnalyzing; }

QString DlcController::defaultModelDir() const
{
    return QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation)
           + "/MindTrace_Data/DLC_Model";
}

void DlcController::setAnalyzing(bool v)
{
    if (m_isAnalyzing != v) { m_isAnalyzing = v; emit analyzingChanged(); }
}

// ── Control ───────────────────────────────────────────────────────────────────

void DlcController::startAnalysis(const QString& videoPath, const QString& modelDir)
{
    if (m_isAnalyzing) return;

    QString cleanVideo = videoPath;
    if (cleanVideo.startsWith("file:///"))
        cleanVideo = cleanVideo.mid(8);

    // Locate model
    QString appDir    = QCoreApplication::applicationDirPath();
    QString modelPath = appDir + "/Network-MemoryLab-v2.onnx";
    if (!QFile::exists(modelPath))
        modelPath = defaultModelDir() + "/Network-MemoryLab-v2.onnx";
    if (!modelDir.isEmpty() && QFile::exists(modelDir))
        modelPath = modelDir;

    if (!QFile::exists(modelPath)) {
        emit errorOccurred("Modelo ONNX não encontrado: " + modelPath);
        return;
    }

    m_modelReady = false;
    m_videoW     = 0;
    m_videoH     = 0;

    // Start model loading in background thread
    m_tracker->loadModel(modelPath);
    if (!m_tracker->isRunning())
        m_tracker->start();

    // Start headless playback at natural frame rate (frame-by-frame delivery
    // to tracker via FrameCaptureSurface)
    m_player->setMedia(QUrl::fromLocalFile(cleanVideo));
    m_player->setPlaybackRate(1.0);
    m_player->play();

    setAnalyzing(true);
}

void DlcController::setPlaybackRate(double rate)
{
    m_player->setPlaybackRate(rate);
}

qint64 DlcController::position() const
{
    return m_player->position();
}

void DlcController::seekTo(qint64 ms)
{
    m_player->setPosition(ms);
}

void DlcController::stopAnalysis()
{
    if (!m_isAnalyzing) return;
    m_player->stop();
    m_tracker->requestStop();
    m_tracker->wait(3000);
    setAnalyzing(false);
}

// ── Frame capture (multimedia thread) ────────────────────────────────────────

void DlcController::onFrameCaptured(const QImage& img, int w, int h)
{
    // Guard: drop frames until model is loaded
    if (!m_modelReady || !m_isAnalyzing) return;

    // Emit dims once when they become known (queued to main thread)
    if (m_videoW != w || m_videoH != h) {
        m_videoW = w;
        m_videoH = h;
        QMetaObject::invokeMethod(this, [this, w, h]() {
            emit dimsReceived(w, h);
        }, Qt::QueuedConnection);
    }

    // Hand off to the ONNX tracker thread (single-slot queue, drops stale frames)
    m_tracker->enqueueFrame(img, w, h);
}

// ── Player status ─────────────────────────────────────────────────────────────

void DlcController::onMediaStatusChanged(QMediaPlayer::MediaStatus status)
{
    if (status == QMediaPlayer::LoadedMedia) {
        double fps = m_player->metaData("VideoFrameRate").toDouble();
        if (fps <= 0.0) fps = 30.0;
        emit fpsReceived(fps);

    } else if (status == QMediaPlayer::EndOfMedia) {
        setAnalyzing(false);

    } else if (status == QMediaPlayer::InvalidMedia) {
        emit errorOccurred("Vídeo inválido ou não suportado pelo codec do sistema.");
        setAnalyzing(false);
    }
}
