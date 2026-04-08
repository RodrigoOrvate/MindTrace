#include "inference_controller.h"
#include <QCoreApplication>
#include <QStandardPaths>
#include <QFile>
#include <QImage>
#include <QMetaObject>
#include <QMediaMetaData>
#include <QDebug>

InferenceController::InferenceController(QObject* parent)
    : QObject(parent)
    , m_player(new QMediaPlayer(this))
    , m_videoSink(new QVideoSink(this))
    , m_engine(new InferenceEngine(this))
{
    // ── Attach sink to headless player ───────────────────────────────────────
    // Qt 6: QVideoSink replaces QAbstractVideoSurface. The sink receives every
    // decoded frame on the multimedia thread, forwarding it to the InferenceEngine.
    // The visible video in QML uses a separate MediaPlayer + VideoOutput pair.
    m_player->setVideoOutput(m_videoSink);

    // ── Frame delivery → engine (multimedia thread, DirectConnection) ───────
    connect(m_videoSink, &QVideoSink::videoFrameChanged,
            this, &InferenceController::onVideoFrameChanged,
            Qt::DirectConnection);

    // ── InferenceEngine signals → InferenceController signals ──────────────────────────
    connect(m_engine, &InferenceEngine::modelReady, this, [this]() {
        m_modelReady = true;
        emit readyReceived();
    }, Qt::QueuedConnection);

    connect(m_engine, &InferenceEngine::trackResult, this,
            [this](int c, float x, float y, float p) {
                emit trackReceived(c, x, y, p);
            }, Qt::QueuedConnection);

    connect(m_engine, &InferenceEngine::bodyResult, this,
            [this](int c, float x, float y, float p) {
                emit bodyReceived(c, x, y, p);
            }, Qt::QueuedConnection);

    connect(m_engine, &InferenceEngine::errorMsg, this,
            [this](QString msg) { emit errorOccurred(msg); },
            Qt::QueuedConnection);

    connect(m_engine, &InferenceEngine::infoMsg, this,
            [this](QString msg) { emit infoReceived(msg); },
            Qt::QueuedConnection);

    // ── Media player status ───────────────────────────────────────────────────
    connect(m_player, &QMediaPlayer::mediaStatusChanged,
            this, &InferenceController::onMediaStatusChanged);
}

InferenceController::~InferenceController()
{
    stopAnalysis();
}

// ── Properties ────────────────────────────────────────────────────────────────

bool InferenceController::isAnalyzing() const { return m_isAnalyzing; }

QString InferenceController::defaultModelDir() const
{
    return QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation)
           + "/MindTrace_Data/DLC_Model";
}

void InferenceController::setAnalyzing(bool v)
{
    if (m_isAnalyzing != v) { m_isAnalyzing = v; emit analyzingChanged(); }
}

// ── Control ───────────────────────────────────────────────────────────────────

void InferenceController::startAnalysis(const QString& videoPath, const QString& modelDir)
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
    m_engine->loadModel(modelPath);
    if (!m_engine->isRunning())
        m_engine->start();

    // Start headless playback — QVideoSink delivers every decoded frame
    m_player->setSource(QUrl::fromLocalFile(cleanVideo));  // Qt 6: setSource (was setMedia)
    m_player->setPlaybackRate(1.0);
    m_player->play();

    setAnalyzing(true);
}

void InferenceController::setPlaybackRate(double rate)
{
    m_player->setPlaybackRate(rate);
}

qint64 InferenceController::position() const
{
    return m_player->position();
}

void InferenceController::seekTo(qint64 ms)
{
    m_player->setPosition(ms);
}

void InferenceController::stopAnalysis()
{
    if (!m_isAnalyzing) return;
    m_player->stop();
    m_engine->requestStop();
    m_engine->wait(3000);
    setAnalyzing(false);
}

// ── Frame capture (multimedia thread) ────────────────────────────────────────

void InferenceController::onVideoFrameChanged(const QVideoFrame& frame)
{
    // Guard: drop frames until model is loaded
    if (!m_modelReady || !m_isAnalyzing) return;

    // Qt 6: QVideoFrame::toImage() handles mapping/unmapping internally
    QImage img = frame.toImage();
    if (img.isNull()) return;

    // Ensure RGB888 for ONNX input tensor
    if (img.format() != QImage::Format_RGB888)
        img = img.convertToFormat(QImage::Format_RGB888);

    const int w = img.width();
    const int h = img.height();

    // Emit dims once when they become known (queued to main thread)
    if (m_videoW != w || m_videoH != h) {
        m_videoW = w;
        m_videoH = h;
        QMetaObject::invokeMethod(this, [this, w, h]() {
            emit dimsReceived(w, h);
        }, Qt::QueuedConnection);
    }

    // Hand off to the ONNX engine thread (single-slot queue, drops stale frames)
    m_engine->enqueueFrame(img, w, h);
}

// ── Player status ─────────────────────────────────────────────────────────────

void InferenceController::onMediaStatusChanged(QMediaPlayer::MediaStatus status)
{
    if (status == QMediaPlayer::LoadedMedia) {
        // Qt 6: metaData() returns QMediaMetaData, access via enum key
        double fps = m_player->metaData().value(QMediaMetaData::VideoFrameRate).toDouble();
        if (fps <= 0.0) fps = 30.0;
        emit fpsReceived(fps);

    } else if (status == QMediaPlayer::EndOfMedia) {
        setAnalyzing(false);

    } else if (status == QMediaPlayer::InvalidMedia) {
        emit errorOccurred("Vídeo inválido ou não suportado pelo codec do sistema.");
        setAnalyzing(false);
    }
}
