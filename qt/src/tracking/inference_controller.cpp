#include "inference_controller.h"
#include <QCoreApplication>
#include <QStandardPaths>
#include <QFile>
#include <QDir>
#include <QImage>
#include <QMetaObject>
#include <QMediaMetaData>
#include <QTextStream>
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
        if (m_isAnalyzing) {
            // Normal start: emit ready to unblock the UI
            emit readyReceived();
        } else {
            // Pre-warm completed silently — sessions ready for instant start
            qDebug() << "[InferenceController] Sessions pre-warmed successfully.";
        }
    }, Qt::QueuedConnection);

    connect(m_engine, &InferenceEngine::trackResult, this,
            [this](int c, float x, float y, float p) {
                emit trackReceived(c, x, y, p);
            }, Qt::QueuedConnection);

    connect(m_engine, &InferenceEngine::bodyResult, this,
            [this](int c, float x, float y, float p) {
                emit bodyReceived(c, x, y, p);
            }, Qt::QueuedConnection);

    connect(m_engine, &InferenceEngine::behaviorResult, this,
            [this](int campo, int labelId) {
                emit behaviorReceived(campo, labelId);
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

    // ── Pre-warm: load ONNX sessions immediately at construction ─────────────
    // Sessions take several seconds to load. Starting the engine thread here
    // means sessions will be ready before the user clicks "Start Analysis".
    {
        const QString appDir     = QCoreApplication::applicationDirPath();
        QString preWarmModel     = appDir + "/Network-MemoryLab-v2.onnx";
        if (!QFile::exists(preWarmModel))
            preWarmModel = defaultModelDir() + "/Network-MemoryLab-v2.onnx";

        if (QFile::exists(preWarmModel)) {
            // AUTO-LOAD BEHAVIOR MODELS DISABLED - Use rule-based classifySimple instead
            // To enable ONNX behavior models, uncomment below and ensure behavior_models/ folder exists
            /*
            QString behaviorModelDir = preWarmModel;
            behaviorModelDir.replace("Network-MemoryLab-v2.onnx", "behavior_models");
            if (!QDir(behaviorModelDir).exists()) {
                behaviorModelDir = appDir + "/behavior_models";
            }

            if (QDir(behaviorModelDir).exists()) {
                m_engine->loadBehaviorModel(behaviorModelDir);
                qDebug() << "[InferenceController] Auto-loading behavior_models from:" << behaviorModelDir;
            }
            */

            m_engine->loadModel(preWarmModel);
            m_engine->start();
            qDebug() << "[InferenceController] Pre-warming ONNX sessions in background...";
        }
    }
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

void InferenceController::loadBehaviorModel(const QString& path)
{
    m_engine->loadBehaviorModel(path);
}

void InferenceController::setZones(int campo, const QList<QVariant>& zones) {
    std::vector<Zone> converted;
    converted.reserve(zones.size());
    for (const auto& z : zones) {
        QVariantMap m = z.toMap();
        Zone zone;
        zone.x = m.value("x", 0.0).toFloat();
        zone.y = m.value("y", 0.0).toFloat();
        zone.r = m.value("r", 0.0).toFloat();
        converted.push_back(zone);
    }
    m_engine->setZones(campo, converted);
}

void InferenceController::setFloorPolygon(int campo, const QList<QVariant>& points) {
    std::vector<std::pair<float,float>> poly;
    poly.reserve(points.size());
    for (const auto& p : points) {
        QVariantMap m = p.toMap();
        poly.push_back({ m.value("x", 0.0).toFloat(), m.value("y", 0.0).toFloat() });
    }
    m_engine->setFloorPolygon(campo, poly);
}

void InferenceController::setVelocity(int campo, float velocity) {
    m_engine->setVelocity(campo, velocity);
}

bool InferenceController::exportBehaviorFeatures(const QString& csvPath, int campo)
{
    if (campo < 0 || campo >= 3) return false;

    const auto& history = m_engine->getScannerHistory(campo);
    if (history.empty()) {
        qWarning() << "[InferenceController] exportBehaviorFeatures: histórico vazio para campo" << campo;
        return false;
    }

    QFile file(csvPath);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        qWarning() << "[InferenceController] exportBehaviorFeatures: não foi possível abrir" << csvPath;
        return false;
    }

    QTextStream out(&file);
    // UTF-8 BOM para compatibilidade com Excel
    out.setEncoding(QStringConverter::Utf8);
    out << "\xEF\xBB\xBF";

    // Cabeçalho
    out << "frame,move_nose,move_body,bp_sum,bp_mean,bp_min,bp_max"
           ",roll2s_mean,roll2s_sum,roll5s_mean,roll5s_sum"
           ",roll6s_mean,roll6s_sum,roll7_5s_mean,roll7_5s_sum"
           ",roll15s_mean,roll15s_sum"
           ",prob_sum,prob_mean"
           ",low_prob_01,low_prob_05,low_prob_075"
           ",rule_label\n";

    for (const auto& rec : history) {
        out << rec.frameIdx;
        for (size_t i = 0; i < 21; ++i)
            out << ',' << rec.features[i];
        out << ',' << rec.ruleLabel << '\n';
    }

    file.close();
    qDebug() << "[InferenceController] exportBehaviorFeatures: exportados"
             << history.size() << "frames para" << csvPath;
    return true;
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

    m_videoW = 0;
    m_videoH = 0;

    // Behavior model is NOT auto-loaded — rule-based is the default.
    // If the user previously loaded a model via loadBehaviorModel(), it stays active.
    // To reset to rule-based, call loadBehaviorModel("") explicitly.

    m_engine->loadModel(modelPath);

    if (m_modelReady && m_engine->isRunning()) {
        // Sessions were pre-warmed — emit ready on next event loop tick so
        // the caller's setAnalyzing(true) fires before QML reacts to readyReceived.
        QMetaObject::invokeMethod(this, [this]() {
            emit readyReceived();
        }, Qt::QueuedConnection);
    } else if (!m_engine->isRunning()) {
        // Engine stopped (first run without pre-warm, or after stopAnalysis) — start fresh
        m_modelReady = false;
        m_engine->start();
    }
    // else: engine running but pre-warm still in progress —
    //       modelReady signal will fire later and emit readyReceived() since m_isAnalyzing==true

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
