#include "inference_controller.h"
#include <QCoreApplication>

// Retorna o primeiro .onnx encontrado no diretório (exclui subpastas).
// Usado para carregar o modelo de pose independente do nome do arquivo.
static QString findPoseModel(const QString &dir)
{
    const QStringList entries = QDir(dir).entryList({"*.onnx"}, QDir::Files);
    return entries.isEmpty() ? QString() : dir + "/" + entries.first();
}
#include <QStandardPaths>
#include <QFile>
#include <QFileInfo>
#include <QDir>
#include <QImage>
#include <QMetaObject>
#include <QMediaMetaData>
#include <QTextStream>
#include <QDebug>
#include <QDateTime>
#include <QMediaFormat>
#include <QCameraFormat>
#include <QVideoFrameFormat>
#include <QPdfWriter>
#include <QPainter>
#include <QPageSize>
#include <QPageLayout>
#include <climits>
#include <QRegularExpression>
#include <QTimer>
#include <algorithm>

InferenceController::InferenceController(QObject* parent)
    : QObject(parent)
    , m_player(new QMediaPlayer(this))
    , m_videoSink(new QVideoSink(this))
    , m_engine(new InferenceEngine(this))
{
    // â”€â”€ Attach sink to headless player â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    // Qt 6: QVideoSink replaces QAbstractVideoSurface. The sink receives every
    // decoded frame on the multimedia thread, forwarding it to the InferenceEngine.
    // The visible video in QML uses a separate MediaPlayer + VideoOutput pair.
    m_player->setVideoOutput(m_videoSink);

    // â”€â”€ Frame delivery â†’ engine (multimedia thread, DirectConnection) â”€â”€â”€â”€â”€â”€â”€
    connect(m_videoSink, &QVideoSink::videoFrameChanged,
            this, &InferenceController::onVideoFrameChanged,
            Qt::DirectConnection);

    // â”€â”€ InferenceEngine signals â†’ InferenceController signals â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    connect(m_engine, &InferenceEngine::modelReady, this, [this]() {
        m_modelReady = true;
        if (m_isAnalyzing) {
            // Normal start: emit ready to unblock the UI
            emit readyReceived();
        } else {
            // Pre-warm completed silently â€” sessions ready for instant start
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

    // â”€â”€ Media player status â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    connect(m_player, &QMediaPlayer::mediaStatusChanged,
            this, &InferenceController::onMediaStatusChanged);

    // â”€â”€ Pre-warm: load ONNX sessions immediately at construction â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    // Sessions take several seconds to load. Starting the engine thread here
    // means sessions will be ready before the user clicks "Start Analysis".
    {
        const QString appDir     = QCoreApplication::applicationDirPath();
        QString preWarmModel = findPoseModel(appDir);
        if (preWarmModel.isEmpty())
            preWarmModel = findPoseModel(defaultModelDir());

        if (QFile::exists(preWarmModel)) {
            // AUTO-LOAD BEHAVIOR MODELS DISABLED - Use rule-based classifySimple instead
            // To enable ONNX behavior models, uncomment below and ensure behavior_models/ folder exists
            /*
            QString behaviorModelDir = preWarmModel;
            behaviorModelDir = QFileInfo(preWarmModel).absolutePath() + "/behavior_models";
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
    stopLivePreview();
}

// â”€â”€ Properties â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

void InferenceController::processImageFrame(QImage img)
{
    if (img.isNull()) return;

    // Count live frames even before modelReady so the DirectShow watchdog
    // detects camera signal correctly (avoids false "Sem sinal").
    if (m_isLiveMode) {
        const qint64 nowMs = QDateTime::currentMSecsSinceEpoch();
        if (m_liveFpsWindowStartMs <= 0)
            m_liveFpsWindowStartMs = nowMs;
        m_liveFpsFrameCount++;

        const qint64 elapsed = nowMs - m_liveFpsWindowStartMs;
        if (elapsed >= 1000) {
            const double measuredFps = (1000.0 * static_cast<double>(m_liveFpsFrameCount))
                                       / static_cast<double>(elapsed);
            QMetaObject::invokeMethod(this, [this, measuredFps]() {
                emit fpsReceived(measuredFps);
            }, Qt::QueuedConnection);
            m_liveFpsWindowStartMs = nowMs;
            m_liveFpsFrameCount = 0;
        }
    }

    if (!m_modelReady || !m_isAnalyzing) return;

    if (img.format() != QImage::Format_RGB888)
        img = img.convertToFormat(QImage::Format_RGB888);

    const int w = img.width();
    const int h = img.height();

    if (m_videoW != w || m_videoH != h) {
        m_videoW = w;
        m_videoH = h;
        QMetaObject::invokeMethod(this, [this, w, h]() {
            emit dimsReceived(w, h);
        }, Qt::QueuedConnection);
    }

    m_engine->enqueueFrame(img, w, h);
}

void InferenceController::onDirectShowFrame(const QImage& img)
{
    if (img.isNull())
        return;

    // Keep inference off the UI thread (DirectShow callback thread calls this).
    // This avoids UI stalls/freeze when live analysis is active.
    processImageFrame(img);
    // Mirror DirectShow frames to QML VideoOutput on UI thread without shared locks.
    if (m_livePreviewSink) {
        QMetaObject::invokeMethod(this, [this, img]() {
            if (m_livePreviewSink)
                m_livePreviewSink->setVideoFrame(QVideoFrame(img));
        }, Qt::QueuedConnection);
    }
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

void InferenceController::setFullFrameMode(bool enabled) {
    m_engine->setFullFrameMode(enabled);
}

void InferenceController::setLivePreviewOutput(QObject* videoOutput) {
    qDebug() << "[setLivePreviewOutput] mode directshow=" << m_isDirectShowMode
             << "captureSession?" << (m_captureSession != nullptr)
             << "videoOutput?" << (videoOutput != nullptr);
    if (m_livePreviewSink) {
        m_livePreviewSink->disconnect(this);
        m_livePreviewSink = nullptr;
    }

    if (m_isDirectShowMode) {
        if (!videoOutput) {
            emit infoReceived("Live preview DirectShow: desativado.");
            return;
        }
        QObject* sinkObj = videoOutput->property("videoSink").value<QObject*>();
        auto* sink = qobject_cast<QVideoSink*>(sinkObj);
        if (!sink) {
            emit infoReceived("Live preview DirectShow sem videoSink valido.");
            return;
        }
        m_livePreviewSink = sink;
        emit infoReceived("Live preview DirectShow: ativo.");
        return;
    }

    if (!m_captureSession) {
        emit infoReceived("Live preview: capture session indisponivel.");
        return;
    }

    m_captureSession->setVideoOutput(videoOutput);
    if (!videoOutput)
        return;

    QObject* sinkObj = videoOutput->property("videoSink").value<QObject*>();
    auto* sink = qobject_cast<QVideoSink*>(sinkObj);
    if (!sink) {
        emit infoReceived("Live preview sem videoSink valido.");
        return;
    }

    m_livePreviewSink = sink;
    connect(m_livePreviewSink, &QVideoSink::videoFrameChanged,
            this, &InferenceController::onVideoFrameChanged,
            Qt::DirectConnection);
}

QVariantList InferenceController::getBehaviorFrames(int campo) const
{
    if (campo < 0 || campo >= 3) return {};
    const auto& history = m_engine->getScannerHistory(campo);
    QVariantList result;
    result.reserve(static_cast<int>(history.size()));
    for (const auto& rec : history) {
        QVariantMap m;
        m["frameIdx"]  = rec.frameIdx;
        m["ruleLabel"] = rec.ruleLabel;
        m["movNose"]   = static_cast<double>(rec.features[0]);
        m["movBody"]   = static_cast<double>(rec.features[1]);
        m["movMean"]   = static_cast<double>(rec.features[3]);
        result.append(m);
    }
    return result;
}

QString InferenceController::behaviorCachePath(const QString& experimentPath, int campo) const
{
    if (campo < 0 || campo >= 3) return QString();
    QString base = experimentPath.trimmed();
    if (base.startsWith("file:///")) base = base.mid(8);
    if (base.isEmpty()) return QString();
    return QDir(base).filePath(QStringLiteral("analysis_cache/behavior_features_campo%1.csv")
                               .arg(campo + 1));
}

bool InferenceController::behaviorCacheExists(const QString& experimentPath, int campo) const
{
    const QString path = behaviorCachePath(experimentPath, campo);
    return !path.isEmpty() && QFile::exists(path);
}

bool InferenceController::saveBehaviorCache(const QString& experimentPath, int campo)
{
    const QString path = behaviorCachePath(experimentPath, campo);
    if (path.isEmpty()) return false;
    QFileInfo fi(path);
    QDir().mkpath(fi.absolutePath());
    return exportBehaviorFeatures(path, campo);
}

QVariantList InferenceController::getBehaviorFramesFromCache(const QString& experimentPath, int campo) const
{
    QVariantList result;
    if (campo < 0 || campo >= 3) return result;

    const QString path = behaviorCachePath(experimentPath, campo);
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return result;

    QTextStream in(&file);
    QString header = in.readLine();
    Q_UNUSED(header)

    while (!in.atEnd()) {
        const QString line = in.readLine().trimmed();
        if (line.isEmpty()) continue;
        const QStringList cols = line.split(',');
        // frame + 21 features + rule_label = 23
        if (cols.size() < 23) continue;

        bool okFrame = false, okRule = false, okNose = false, okBody = false, okMean = false;
        const int frameIdx = cols[0].toInt(&okFrame);
        const double movNose = cols[1].toDouble(&okNose);
        const double movBody = cols[2].toDouble(&okBody);
        const double movMean = cols[4].toDouble(&okMean);   // bp_mean
        const int ruleLabel = cols[22].toInt(&okRule);
        if (!okFrame || !okRule || !okNose || !okBody || !okMean) continue;

        QVariantMap m;
        m["frameIdx"] = frameIdx;
        m["ruleLabel"] = ruleLabel;
        m["movNose"] = movNose;
        m["movBody"] = movBody;
        m["movMean"] = movMean;
        result.append(m);
    }
    return result;
}

bool InferenceController::writeTextFile(const QString& filePath, const QString& content, bool utf8Bom)
{
    QString path = filePath.trimmed();
    if (path.startsWith("file:///"))
        path = path.mid(8);
    if (path.isEmpty())
        return false;

    QFileInfo fi(path);
    if (!QDir().mkpath(fi.absolutePath()))
        return false;

    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text))
        return false;

    QTextStream out(&file);
    out.setEncoding(QStringConverter::Utf8);
    if (utf8Bom)
        out << "\xEF\xBB\xBF";
    out << content;
    file.close();
    return true;
}

QString InferenceController::readTextFile(const QString& filePath) const
{
    QString path = filePath.trimmed();
    if (path.startsWith("file:///"))
        path = path.mid(8);
    if (path.isEmpty())
        return QString();

    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return QString();

    QTextStream in(&file);
    in.setEncoding(QStringConverter::Utf8);
    return in.readAll();
}

bool InferenceController::savePdfReport(const QString& pdfPath,
                                        const QStringList& imagePaths,
                                        const QString& title,
                                        const QStringList& captions)
{
    QString outPath = pdfPath.trimmed();
    if (outPath.startsWith("file:///"))
        outPath = outPath.mid(8);
    if (outPath.isEmpty() || imagePaths.isEmpty())
        return false;

    QFileInfo fi(outPath);
    if (!QDir().mkpath(fi.absolutePath()))
        return false;

    QPdfWriter pdf(outPath);
    pdf.setResolution(150);
    pdf.setPageSize(QPageSize(QPageSize::A4));
    pdf.setPageMargins(QMarginsF(12, 12, 12, 12), QPageLayout::Millimeter);

    QPainter painter(&pdf);
    if (!painter.isActive())
        return false;

    const QRect page = painter.viewport();
    const int margin = 36;
    const QRect contentRect = page.adjusted(margin, margin, -margin, -margin);

    bool drewAny = false;
    for (int i = 0; i < imagePaths.size(); ++i) {
        QString imgPath = imagePaths[i].trimmed();
        if (imgPath.startsWith("file:///"))
            imgPath = imgPath.mid(8);
        QImage img(imgPath);
        if (img.isNull())
            continue;

        if (drewAny)
            pdf.newPage();
        drewAny = true;

        painter.fillRect(page, Qt::white);
        painter.setPen(QColor("#111827"));

        painter.setFont(QFont("Segoe UI", 11, QFont::Bold));
        const QString pageTitle = title.isEmpty() ? QStringLiteral("MindTrace Results Report") : title;
        painter.drawText(contentRect.left(), contentRect.top(), contentRect.width(), 26,
                         Qt::AlignLeft | Qt::AlignVCenter, pageTitle);

        painter.setFont(QFont("Segoe UI", 9));
        const QString cap = (i < captions.size() ? captions[i] : QString());
        const int captionH = cap.isEmpty() ? 0 : 24;
        if (!cap.isEmpty()) {
            painter.drawText(contentRect.left(), contentRect.top() + 28, contentRect.width(), 20,
                             Qt::AlignLeft | Qt::AlignVCenter, cap);
        }

        QRect imgRect = contentRect.adjusted(0, 34 + captionH, 0, 0);
        if (imgRect.height() < 40)
            imgRect = contentRect.adjusted(0, 34, 0, 0);

        const QSize target = img.size().scaled(imgRect.size(), Qt::KeepAspectRatio);
        const QRect centered(QPoint(imgRect.left() + (imgRect.width() - target.width()) / 2,
                                    imgRect.top() + (imgRect.height() - target.height()) / 2),
                            target);
        painter.drawImage(centered, img);
    }

    painter.end();
    return drewAny;
}

bool InferenceController::exportBehaviorFeatures(const QString& csvPath, int campo)
{
    if (campo < 0 || campo >= 3) return false;

    const auto& history = m_engine->getScannerHistory(campo);
    if (history.empty()) {
        qWarning() << "[InferenceController] exportBehaviorFeatures: histÃ³rico vazio para campo" << campo;
        return false;
    }

    QFile file(csvPath);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        qWarning() << "[InferenceController] exportBehaviorFeatures: nÃ£o foi possÃ­vel abrir" << csvPath;
        return false;
    }

    QTextStream out(&file);
    // UTF-8 BOM para compatibilidade com Excel
    out.setEncoding(QStringConverter::Utf8);
    out << "\xEF\xBB\xBF";

    // CabeÃ§alho
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

// â”€â”€ Control â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

void InferenceController::startAnalysis(const QString& videoPath, const QString& modelDir)
{
    if (m_isAnalyzing) return;

    QString cleanVideo = videoPath;
    if (cleanVideo.startsWith("file:///"))
        cleanVideo = cleanVideo.mid(8);

    m_videoW = 0;
    m_videoH = 0;

    // Behavior model is NOT auto-loaded â€” rule-based is the default.
    // If the user previously loaded a model via loadBehaviorModel(), it stays active.
    // To reset to rule-based, call loadBehaviorModel("") explicitly.

    if (m_modelReady && m_engine->isRunning()) {
        qDebug() << "[startAnalysis] using pre-warmed sessions (skip loadModel)";
        // Sessions were pre-warmed â€” emit ready on next event loop tick so
        // the caller's setAnalyzing(true) fires before QML reacts to readyReceived.
        QMetaObject::invokeMethod(this, [this]() {
            emit readyReceived();
        }, Qt::QueuedConnection);
    } else if (!m_engine->isRunning()) {
        // Locate model only when we really need to (engine stopped / no pre-warm).
        QString appDir    = QCoreApplication::applicationDirPath();
        QString modelPath = findPoseModel(appDir);
        if (modelPath.isEmpty())
            modelPath = findPoseModel(defaultModelDir());
        if (!modelDir.isEmpty() && QFile::exists(modelDir))
            modelPath = modelDir;

        if (!QFile::exists(modelPath)) {
            emit errorOccurred("Modelo ONNX nao encontrado em: " + appDir);
            return;
        }

        m_engine->loadModel(modelPath);
        // Engine stopped (first run without pre-warm, or after stopAnalysis) â€” start fresh
        m_modelReady = false;
        m_engine->start();
    }
    // else: engine running but pre-warm still in progress â€”
    //       modelReady signal will fire later and emit readyReceived() since m_isAnalyzing==true

    // Start headless playback â€” QVideoSink delivers every decoded frame
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

QVariantList InferenceController::listVideoInputs()
{
    QVariantList result;
    QStringList seenNames;

    const auto devices = QMediaDevices::videoInputs();
    qDebug() << "[listVideoInputs] Qt devices:" << devices.size();
    for (const auto& dev : devices) {
        qDebug() << "  Qt:" << dev.description();
        QVariantMap map;
        map["name"] = dev.description();
        map["backend"] = "qt";
        result.append(map);
        seenNames.append(dev.description());
    }

    const auto dsInputs = DShowCapture::enumerateInputs();
    qDebug() << "[listVideoInputs] DShow devices:" << dsInputs.size();
    for (const auto& ds : dsInputs) {
        qDebug() << "  DShow:" << ds.name
                 << "composite=" << ds.hasComposite
                 << "svideo=" << ds.hasSVideo
                 << "hauppauge=" << ds.isHauppauge;
        QString label = ds.name;
        if (label.isEmpty())
            continue;

        if (seenNames.contains(label, Qt::CaseInsensitive))
            label += " [DirectShow]";
        else
            seenNames.append(label);

        QVariantMap map;
        map["name"] = label;
        map["backend"] = "dshow";
        map["hasComposite"] = ds.hasComposite;
        map["hasSVideo"] = ds.hasSVideo;
        map["isHauppauge"] = ds.isHauppauge;
        result.append(map);
    }

    qDebug() << "[listVideoInputs] Total entries returned:" << result.size();
    return result;
}

void InferenceController::startLiveAnalysis(const QString& cameraName, const QString& modelDir)
{
    // preferredWidth/Height = 0 â†’ use camera's default format (honors DroidCam/driver setting)
    startLiveAnalysis(cameraName, modelDir, QString(), QString(), 0, 0, 0.0);
}

QString InferenceController::liveRecordingPath() const
{
    return m_liveRecordingPath;
}

bool InferenceController::startLivePreview(const QString& cameraName)
{
    if (m_isAnalyzing)
        return false;

    stopLivePreview();

    m_videoW = 0;
    m_videoH = 0;
    m_isLiveMode = true;
    m_isDirectShowMode = false;
    m_isPreviewOnly = true;
    m_liveRecordingPath.clear();

    QString normalizedCameraName = cameraName;
    QString preferredAnalogInput = "Composite";
    QString preferredBackend;
    {
        const QStringList parts = cameraName.split("|", Qt::SkipEmptyParts);
        if (!parts.isEmpty())
            normalizedCameraName = parts.first().trimmed();
        for (int i = 1; i < parts.size(); ++i) {
            const QString token = parts[i].trimmed();
            const QString low = token.toLower();
            if (low.startsWith("input:"))
                preferredAnalogInput = token.mid(6).trimmed();
            else if (low.startsWith("backend:"))
                preferredBackend = token.mid(8).trimmed().toLower();
        }
    }
    const bool explicitDShow = preferredBackend == "dshow"
                               || cameraName.contains("|input:", Qt::CaseInsensitive)
                               || normalizedCameraName.endsWith("[DirectShow]");
    normalizedCameraName.replace(" [DirectShow]", "");

    bool hasDShowMatch = explicitDShow;
    if (!explicitDShow) {
        const auto dsInputs = DShowCapture::enumerateInputs();
        const auto dsIt = std::find_if(dsInputs.begin(), dsInputs.end(),
                                       [&](const DShowVideoInput& d) { return d.name == normalizedCameraName; });
        hasDShowMatch = (dsIt != dsInputs.end());
    }
    if (!hasDShowMatch) {
        m_isLiveMode = false;
        m_isPreviewOnly = false;
        return false;
    }

    m_dshowCapture = std::make_unique<DShowCapture>();
    QString dsError;
    if (!m_dshowCapture->start(normalizedCameraName,
                               preferredAnalogInput,
                               [this](const QImage& img) { onDirectShowFrame(img); },
                               &dsError)) {
        emit infoReceived("DirectShow preview falhou: " + dsError);
        m_dshowCapture.reset();
        m_isLiveMode = false;
        m_isPreviewOnly = false;
        return false;
    }

    m_isDirectShowMode = true;
    emit infoReceived(QStringLiteral("Arena preview DirectShow: ") + normalizedCameraName);
    return true;
}

void InferenceController::stopLivePreview()
{
    if (m_isDirectShowMode && m_dshowCapture) {
        m_dshowCapture->stop();
        m_dshowCapture.reset();
    }
    if (m_livePreviewSink) {
        m_livePreviewSink->disconnect(this);
        m_livePreviewSink = nullptr;
    }
    if (m_mediaRecorder) {
        if (m_mediaRecorder->recorderState() == QMediaRecorder::RecordingState)
            m_mediaRecorder->stop();
        delete m_mediaRecorder;
        m_mediaRecorder = nullptr;
    }
    if (m_camera) {
        m_camera->stop();
        delete m_camera;
        m_camera = nullptr;
    }
    if (m_captureSession) {
        m_captureSession->setRecorder(nullptr);
        m_captureSession->setVideoOutput(nullptr);
        delete m_captureSession;
        m_captureSession = nullptr;
    }
    m_isPreviewOnly = false;
    m_isLiveMode = false;
    m_isDirectShowMode = false;
    m_liveFpsWindowStartMs = 0;
    m_liveFpsFrameCount = 0;
    m_loggedLiveNullFrame = false;
}

void InferenceController::startLiveAnalysis(const QString& cameraName,
                                            const QString& modelDir,
                                            const QString& saveDirectory,
                                            const QString& preferredFileName,
                                            int preferredWidth,
                                            int preferredHeight,
                                            double preferredFps)
{
    qDebug() << "[startLiveAnalysis] camera=" << cameraName << "isAnalyzing=" << m_isAnalyzing;
    if (m_isAnalyzing) return;
    if (m_isPreviewOnly)
        stopLivePreview();
    qDebug() << "[startLiveAnalysis][A] entered";

    m_videoW = 0;
    m_videoH = 0;
    m_isLiveMode = true;
    m_isDirectShowMode = false;
    m_isPreviewOnly = false;
    m_liveRecordingPath.clear();
    qDebug() << "[startLiveAnalysis][B] live state reset";
    qDebug() << "[startLiveAnalysis][C] dshow preview queue reset";

    const bool engineRunningNow = m_engine->isRunning();
    qDebug() << "[startLiveAnalysis][D] modelReady=" << m_modelReady
             << "engineRunning=" << engineRunningNow;
    if (m_modelReady && engineRunningNow) {
        qDebug() << "[startLiveAnalysis] using pre-warmed sessions (skip loadModel)";
        QMetaObject::invokeMethod(this, [this]() { emit readyReceived(); }, Qt::QueuedConnection);
    } else if (!engineRunningNow) {
        // Locate model only when needed (engine stopped / no pre-warm available).
        QString appDir    = QCoreApplication::applicationDirPath();
        QString modelPath = findPoseModel(appDir);
        if (modelPath.isEmpty())
            modelPath = findPoseModel(defaultModelDir());
        if (!modelDir.isEmpty() && QFile::exists(modelDir))
            modelPath = modelDir;
        if (!QFile::exists(modelPath)) {
            emit errorOccurred("Modelo ONNX nao encontrado em: " + appDir);
            return;
        }

        qDebug() << "[startLiveAnalysis] modelPath resolved:" << modelPath;
        m_engine->loadModel(modelPath);
        qDebug() << "[startLiveAnalysis] loadModel done. modelReady=" << m_modelReady
                 << "engineRunning=" << m_engine->isRunning();
        m_modelReady = false;
        m_engine->start();
        qDebug() << "[startLiveAnalysis] engine started for live mode";
    }
    qDebug() << "[startLiveAnalysis][E] engine path done";

    // FPS is measured from received frames.
    m_liveFpsWindowStartMs = 0;
    m_liveFpsFrameCount = 0;
    m_loggedLiveNullFrame = false;

    // Prefer DirectShow for analog capture cards (e.g. Hauppauge Composite).
    QString normalizedCameraName = cameraName;
    QString preferredAnalogInput = "Composite";
    QString preferredBackend;
    bool retryAttempted = false;
    {
        const QStringList parts = cameraName.split("|", Qt::SkipEmptyParts);
        if (!parts.isEmpty())
            normalizedCameraName = parts.first().trimmed();
        for (int i = 1; i < parts.size(); ++i) {
            const QString token = parts[i].trimmed();
            const QString low = token.toLower();
            if (low.startsWith("input:"))
                preferredAnalogInput = token.mid(6).trimmed();
            else if (low.startsWith("backend:"))
                preferredBackend = token.mid(8).trimmed().toLower();
            else if (low.startsWith("retry:"))
                retryAttempted = true;
        }
    }
    const bool explicitDShow = preferredBackend == "dshow"
                               || cameraName.contains("|input:", Qt::CaseInsensitive)
                               || normalizedCameraName.endsWith("[DirectShow]");
    const bool explicitQt = preferredBackend == "qt";
    normalizedCameraName.replace(" [DirectShow]", "");
    qDebug() << "[startLiveAnalysis][F] camera tokens parsed";

    // Virtual cameras (OBS, etc.) are often better on Qt, but when user explicitly
    // selected DirectShow we must avoid Qt device probing here (some environments
    // can block/hang on videoInputs enumeration).
    const QString normLower = normalizedCameraName.toLower();
    const bool isVirtualCamera = normLower.contains("virtual camera")
                                 || normLower.contains("obs virtual");
    bool hasQtMatchNow = false;
    if (!explicitDShow) {
        const auto qtInputsNow = QMediaDevices::videoInputs();
        const QString wantedLowerNow = normalizedCameraName.trimmed().toLower();
        for (const auto& dev : qtInputsNow) {
            const QString descLower = dev.description().trimmed().toLower();
            if (descLower == wantedLowerNow
                || (!wantedLowerNow.isEmpty()
                    && (descLower.contains(wantedLowerNow) || wantedLowerNow.contains(descLower)))) {
                hasQtMatchNow = true;
                break;
            }
        }
    }
    if (isVirtualCamera && explicitDShow && hasQtMatchNow) {
        emit infoReceived(QStringLiteral("Virtual camera detectada (%1): Qt encontrou dispositivo, priorizando backend Qt.")
                          .arg(normalizedCameraName));
    } else if (isVirtualCamera && explicitDShow && !hasQtMatchNow) {
        emit infoReceived(QStringLiteral("Virtual camera detectada (%1): Qt nao encontrou dispositivo, mantendo DirectShow.")
                          .arg(normalizedCameraName));
    }

    // Some DirectShow drivers can block during device enumeration.
    // If backend was explicitly requested as dshow, skip enumeration and try open directly.
    bool hasDShowMatch = explicitDShow;
    QList<DShowVideoInput> dsInputs;
    if (!explicitDShow) {
        dsInputs = DShowCapture::enumerateInputs();
        const auto dsIt = std::find_if(dsInputs.begin(), dsInputs.end(),
                                       [&](const DShowVideoInput& d) { return d.name == normalizedCameraName; });
        hasDShowMatch = (dsIt != dsInputs.end());
    }
    const bool shouldTryDShow = !explicitQt
                                && (explicitDShow || hasDShowMatch)
                                && !(isVirtualCamera && hasQtMatchNow);
    qDebug() << "[startLiveAnalysis] parsed cameraName=" << normalizedCameraName
             << "preferredBackend=" << preferredBackend
             << "preferredInput=" << preferredAnalogInput
             << "explicitDShow=" << explicitDShow
             << "explicitQt=" << explicitQt
             << "hasQtMatchNow=" << hasQtMatchNow
             << "hasDShowMatch=" << hasDShowMatch
             << "shouldTryDShow=" << shouldTryDShow;

    if (shouldTryDShow) {
        m_dshowCapture = std::make_unique<DShowCapture>();
        QString dsError;
        if (m_dshowCapture->start(normalizedCameraName,
                                  preferredAnalogInput,
                                  [this](const QImage& img) { onDirectShowFrame(img); },
                                  &dsError)) {
            m_isDirectShowMode = true;
            emit infoReceived(QStringLiteral("📹 Camera: ") + normalizedCameraName + " (DirectShow)");
            if (hasDShowMatch)
                emit infoReceived(QStringLiteral("DirectShow input: ") + preferredAnalogInput);
            emit infoReceived("Live recording file: ");
            setAnalyzing(true);

            // Watchdog: if no frames arrive, auto-try alternate analog input once.
            const QString watchCameraName = normalizedCameraName;
            const QString watchInput = preferredAnalogInput;
            const bool watchRetryAttempted = retryAttempted;
            QTimer::singleShot(2200, this, [this,
                                            watchCameraName,
                                            watchInput,
                                            watchRetryAttempted,
                                            modelDir,
                                            saveDirectory,
                                            preferredFileName,
                                            preferredWidth,
                                            preferredHeight,
                                            preferredFps]() {
                if (!m_isAnalyzing || !m_isDirectShowMode)
                    return;
                if (m_liveFpsFrameCount > 0)
                    return;

                if (!watchRetryAttempted) {
                    const bool currentSVideo = watchInput.trimmed().toLower().contains("s-video")
                                               || watchInput.trimmed().toLower().contains("svideo");
                    const QString altInput = currentSVideo ? QStringLiteral("Composite")
                                                           : QStringLiteral("S-Video");
                    emit infoReceived(QStringLiteral("DirectShow sem frames em %1, tentando %2...")
                                      .arg(watchInput, altInput));
                    stopAnalysis();
                    startLiveAnalysis(watchCameraName + " |input:" + altInput + " |retry:1",
                                      modelDir,
                                      saveDirectory,
                                      preferredFileName,
                                      preferredWidth,
                                      preferredHeight,
                                      preferredFps);
                    return;
                }

                emit errorOccurred("Sem sinal de video da placa de captura (DirectShow). Verifique cabos/fonte e padrao analogico.");
                stopAnalysis();
            });
            return;
        }
        emit infoReceived("DirectShow falhou: " + dsError);
        // Se o dispositivo estava na lista DShow (hasDShowMatch), não fazer fallback para Qt camera:
        // evita abrir a primeira webcam disponível quando a placa de captura falha.
        if (explicitDShow || hasDShowMatch) {
            emit errorOccurred("Falha ao abrir a placa de captura (DirectShow): " + dsError);
            m_dshowCapture.reset();
            return;
        }
        m_dshowCapture.reset();
    }

    // Fallback to Qt camera backend.
    const auto devices = QMediaDevices::videoInputs();
    QStringList qtDeviceNames;
    qtDeviceNames.reserve(devices.size());
    for (const auto& d : devices)
        qtDeviceNames.append(d.description());
    emit infoReceived(QString("Qt video inputs: %1").arg(qtDeviceNames.join(" | ")));

    QCameraDevice selected;
    const QString wantedLower = normalizedCameraName.trimmed().toLower();
    for (const auto& dev : devices) {
        const QString desc = dev.description().trimmed();
        const QString descLower = desc.toLower();
        if (desc == normalizedCameraName || desc == cameraName
            || descLower == wantedLower
            || (!wantedLower.isEmpty() && (descLower.contains(wantedLower) || wantedLower.contains(descLower)))) {
            selected = dev;
            break;
        }
    }
    if (selected.isNull()) {
        emit errorOccurred("Camera solicitada nao encontrada no backend Qt: " + normalizedCameraName);
        return;
    }

    emit infoReceived(QStringLiteral("📹 Camera: ") + selected.description());

    // Build capture pipeline: QCamera -> QMediaCaptureSession.
    m_camera         = new QCamera(selected);
    m_captureSession = new QMediaCaptureSession();
    connect(m_camera, &QCamera::errorOccurred, this,
            [this](QCamera::Error, const QString& errorString) {
                emit errorOccurred("Camera error: " + errorString);
            });

    auto pixFmtName = [](QVideoFrameFormat::PixelFormat pix) -> QString {
        switch (pix) {
            case QVideoFrameFormat::Format_Jpeg:    return "MJPEG";
            case QVideoFrameFormat::Format_NV12:    return "NV12";
            case QVideoFrameFormat::Format_NV21:    return "NV21";
            case QVideoFrameFormat::Format_YUV420P: return "YUV420P";
            case QVideoFrameFormat::Format_YUYV:    return "YUYV";
            case QVideoFrameFormat::Format_UYVY:    return "UYVY";
            case QVideoFrameFormat::Format_BGRA8888:return "BGRA8888";
            case QVideoFrameFormat::Format_BGRX8888:return "BGRX8888";
            case QVideoFrameFormat::Format_RGBA8888:return "RGBA8888";
            case QVideoFrameFormat::Format_RGBX8888:return "RGBX8888";
            case QVideoFrameFormat::Format_Invalid: return "Invalid";
            default: return QString("Unknown(%1)").arg(static_cast<int>(pix));
        }
    };

    const auto formats = selected.videoFormats();
    emit infoReceived(QString("Camera device: %1 (%2 formats advertised)")
                      .arg(selected.description()).arg(formats.size()));
    for (int i = 0; i < formats.size(); ++i) {
        const auto& f = formats[i];
        const QSize r = f.resolution();
        emit infoReceived(QString("  [%1] %2x%3  %4-%5 fps  fmt=%6")
                          .arg(i).arg(r.width()).arg(r.height())
                          .arg(f.minFrameRate(), 0, 'f', 1)
                          .arg(f.maxFrameRate(), 0, 'f', 1)
                          .arg(pixFmtName(f.pixelFormat())));
    }

    if (preferredWidth > 0) {
        QCameraFormat bestFormat;
        bool hasBest = false;
        int bestScore = INT_MAX;
        for (const auto& fmt : formats) {
            const QSize res = fmt.resolution();
            if (!res.isValid()) continue;

            const int dw = qAbs(res.width()  - preferredWidth);
            const int dh = qAbs(res.height() - preferredHeight);
            const double maxFps = fmt.maxFrameRate();
            const int fpsPenalty = static_cast<int>(qAbs(maxFps - preferredFps) * 12.0);

            int pixPenalty = 0;
            const auto pix = fmt.pixelFormat();
            if (pix == QVideoFrameFormat::Format_Jpeg)
                pixPenalty = 250;
            else if (pix == QVideoFrameFormat::Format_Invalid)
                pixPenalty = 400;

            const int score = dw + dh + fpsPenalty + pixPenalty;
            if (!hasBest || score < bestScore) {
                bestScore = score;
                bestFormat = fmt;
                hasBest = true;
            }
        }
        if (hasBest) {
            m_camera->setCameraFormat(bestFormat);
            const QSize chosenRes = bestFormat.resolution();
            emit infoReceived(QString("Live profile applied: %1x%2 @ up to %3 FPS  fmt=%4")
                              .arg(chosenRes.width()).arg(chosenRes.height())
                              .arg(bestFormat.maxFrameRate(), 0, 'f', 2)
                              .arg(pixFmtName(bestFormat.pixelFormat())));
        }
        emit infoReceived(QString("Live profile requested: %1x%2 @ %3 FPS")
                          .arg(preferredWidth).arg(preferredHeight).arg(preferredFps, 0, 'f', 0));
    } else {
        emit infoReceived("Live profile: using camera default format (no preference set).");
    }

    m_captureSession->setCamera(m_camera);
    m_captureSession->setVideoOutput(nullptr);

    QString outDir = saveDirectory.trimmed();
    if (outDir.startsWith("file:///"))
        outDir = outDir.mid(8);
    if (outDir.isEmpty()) {
        outDir = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation)
                 + "/MindTrace_Data/live_recordings";
    }
    QDir().mkpath(outDir);
    QDir out(outDir);
    QString baseName = preferredFileName.trimmed();
    if (baseName.startsWith("file:///"))
        baseName = QFileInfo(baseName.mid(8)).fileName();
    baseName = QFileInfo(baseName).completeBaseName();
    if (baseName.isEmpty())
        baseName = "live";
    baseName.replace(QRegularExpression(QStringLiteral("[\\\\/:*?\"<>|]")), "_");

    QString candidate = out.filePath(baseName + ".mp4");
    if (QFile::exists(candidate)) {
        const QString stamp = QDateTime::currentDateTime().toString("yyyyMMdd_HHmmss");
        candidate = out.filePath(baseName + "_" + stamp + ".mp4");
    }
    m_liveRecordingPath = candidate;

    m_mediaRecorder = new QMediaRecorder(this);
    QMediaFormat mediaFormat;
    mediaFormat.setFileFormat(QMediaFormat::MPEG4);
    mediaFormat.setVideoCodec(QMediaFormat::VideoCodec::H264);
    m_mediaRecorder->setMediaFormat(mediaFormat);
    m_mediaRecorder->setOutputLocation(QUrl::fromLocalFile(m_liveRecordingPath));
    connect(m_mediaRecorder, &QMediaRecorder::errorOccurred, this,
            [this](QMediaRecorder::Error, const QString& errorString) {
                emit errorOccurred("Recorder error: " + errorString);
            });
    if (preferredWidth > 0) {
        m_mediaRecorder->setVideoResolution(preferredWidth, preferredHeight);
        m_mediaRecorder->setVideoFrameRate(preferredFps);
    }
    m_captureSession->setRecorder(m_mediaRecorder);
    emit infoReceived("Live recording file: " + m_liveRecordingPath);

    m_camera->start();
    m_mediaRecorder->record();
    setAnalyzing(true);

    // Watchdog for Qt camera backend: give clear diagnostics instead of silent white preview.
    const QString watchCameraName = selected.description();
    QTimer::singleShot(2600, this, [this, watchCameraName]() {
        if (!m_isAnalyzing || !m_isLiveMode || m_isDirectShowMode)
            return;
        if (m_liveFpsFrameCount > 0)
            return;
        emit errorOccurred("Sem frames da camera (Qt backend): " + watchCameraName
                           + ". Tente trocar para formato MJPEG/YUY2 no driver/OBS ou selecionar a entrada [DirectShow].");
        stopAnalysis();
    });
}

void InferenceController::stopAnalysis()
{
    if (!m_isAnalyzing) return;

    if (m_isLiveMode) {
        if (m_isDirectShowMode && m_dshowCapture) {
            m_dshowCapture->stop();
            m_dshowCapture.reset();
        }
        if (m_livePreviewSink) { m_livePreviewSink->disconnect(this); m_livePreviewSink = nullptr; }
        if (m_mediaRecorder)  {
            if (m_mediaRecorder->recorderState() == QMediaRecorder::RecordingState)
                m_mediaRecorder->stop();
            delete m_mediaRecorder;
            m_mediaRecorder = nullptr;
        }
        if (m_camera)         { m_camera->stop();         delete m_camera;         m_camera         = nullptr; }
        if (m_captureSession) {
            m_captureSession->setRecorder(nullptr);
            m_captureSession->setVideoOutput(nullptr);
            delete m_captureSession;
            m_captureSession = nullptr;
        }
        m_isLiveMode = false;
        m_isDirectShowMode = false;
    } else {
        m_player->stop();
    }

    m_engine->requestStop();
    m_engine->wait(3000);
    m_liveFpsWindowStartMs = 0;
    m_liveFpsFrameCount = 0;
    m_loggedLiveNullFrame = false;
    setAnalyzing(false);
}

// â”€â”€ Frame capture (multimedia thread) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

void InferenceController::onVideoFrameChanged(const QVideoFrame& frame)
{
    // Log real pixel format on first live frame for diagnostics.
    if (m_isLiveMode && m_videoW == 0 && m_videoH == 0) {
        const int fw = frame.width();
        const int fh = frame.height();
        const QVideoFrameFormat::PixelFormat pix = frame.surfaceFormat().pixelFormat();
        auto pixStr = [](QVideoFrameFormat::PixelFormat p) -> QString {
            switch (p) {
                case QVideoFrameFormat::Format_Jpeg:    return "MJPEG";
                case QVideoFrameFormat::Format_NV12:    return "NV12";
                case QVideoFrameFormat::Format_NV21:    return "NV21";
                case QVideoFrameFormat::Format_YUV420P: return "YUV420P";
                case QVideoFrameFormat::Format_YUYV:    return "YUYV";
                case QVideoFrameFormat::Format_UYVY:    return "UYVY";
                case QVideoFrameFormat::Format_BGRA8888:return "BGRA8888";
                case QVideoFrameFormat::Format_RGBA8888:return "RGBA8888";
                case QVideoFrameFormat::Format_Invalid: return "Invalid";
                default: return QString("Unknown(%1)").arg(static_cast<int>(p));
            }
        };
        const QString msg = QString("First frame actual: %1x%2  fmt=%3")
                            .arg(fw).arg(fh).arg(pixStr(pix));
        QMetaObject::invokeMethod(this, [this, msg]() {
            emit infoReceived(msg);
        }, Qt::QueuedConnection);
    }

    QImage image = frame.toImage();
    if (image.isNull()) {
        if (m_isLiveMode && !m_loggedLiveNullFrame) {
            m_loggedLiveNullFrame = true;
            const QVideoFrameFormat::PixelFormat pix = frame.surfaceFormat().pixelFormat();
            auto pixStr = [](QVideoFrameFormat::PixelFormat p) -> QString {
                switch (p) {
                    case QVideoFrameFormat::Format_Jpeg:    return "MJPEG";
                    case QVideoFrameFormat::Format_NV12:    return "NV12";
                    case QVideoFrameFormat::Format_NV21:    return "NV21";
                    case QVideoFrameFormat::Format_YUV420P: return "YUV420P";
                    case QVideoFrameFormat::Format_YUYV:    return "YUYV";
                    case QVideoFrameFormat::Format_UYVY:    return "UYVY";
                    case QVideoFrameFormat::Format_BGRA8888:return "BGRA8888";
                    case QVideoFrameFormat::Format_RGBA8888:return "RGBA8888";
                    case QVideoFrameFormat::Format_Invalid: return "Invalid";
                    default: return QString("Unknown(%1)").arg(static_cast<int>(p));
                }
            };
            QMetaObject::invokeMethod(this, [this, pix, pixStr]() {
                emit infoReceived(QString("Live frame conversion falhou (QVideoFrame::toImage nulo). PixelFormat=%1 (%2)")
                                  .arg(pixStr(pix))
                                  .arg(static_cast<int>(pix)));
            }, Qt::QueuedConnection);
        }
        return;
    }

    processImageFrame(image);
}

// Player status â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
        emit errorOccurred("VÃ­deo invÃ¡lido ou nÃ£o suportado pelo codec do sistema.");
        setAnalyzing(false);
    }
}
