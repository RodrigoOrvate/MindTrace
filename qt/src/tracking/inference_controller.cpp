#include "inference_controller.h"

#include <QCameraFormat>
#include <QCoreApplication>
#include <QDateTime>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QImage>
#include <QMediaFormat>
#include <QMediaMetaData>
#include <QMetaObject>
#include <QPageLayout>
#include <QPageSize>
#include <QPainter>
#include <QPdfWriter>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QTextStream>
#include <QTimer>
#include <QVideoFrameFormat>

#include <algorithm>
#include <climits>

// Returns the first .onnx file found in *dir* (top-level only, no subdirectories).
// Allows loading the pose model regardless of its filename.
static QString findPoseModel(const QString& dir)
{
    const QStringList entries = QDir(dir).entryList({"*.onnx"}, QDir::Files);
    return entries.isEmpty() ? QString() : dir + "/" + entries.first();
}

// Maps a QVideoFrameFormat::PixelFormat to a short human-readable label.
// Used in diagnostic messages on the first live frame and on null-frame errors.
static QString pixelFormatName(QVideoFrameFormat::PixelFormat pixelFormat)
{
    switch (pixelFormat) {
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
        default: return QString("Unknown(%1)").arg(static_cast<int>(pixelFormat));
    }
}

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
            [this](int fieldIndex, float x, float y, float likelihood) {
                emit trackReceived(fieldIndex, x, y, likelihood);
            }, Qt::QueuedConnection);

    connect(m_engine, &InferenceEngine::bodyResult, this,
            [this](int fieldIndex, float x, float y, float likelihood) {
                emit bodyReceived(fieldIndex, x, y, likelihood);
            }, Qt::QueuedConnection);

    connect(m_engine, &InferenceEngine::behaviorResult, this,
            [this](int fieldIndex, int labelId) {
                emit behaviorReceived(fieldIndex, labelId);
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

void InferenceController::setAnalyzing(bool analyzing)
{
    if (m_isAnalyzing != analyzing) { m_isAnalyzing = analyzing; emit analyzingChanged(); }
}

void InferenceController::processImageFrame(QImage img)
{
    if (img.isNull()) return;

    // Count live frames even before modelReady so the DirectShow watchdog
    // detects camera signal correctly (avoids false "Sem sinal").
    if (m_isLiveMode) {
        m_liveTotalFrameCount++;
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

void InferenceController::setZones(int fieldIndex, const QList<QVariant>& zones)
{
    std::vector<Zone> converted;
    converted.reserve(zones.size());
    for (const auto& zoneVariant : zones) {
        const QVariantMap zoneMap = zoneVariant.toMap();
        Zone zone;
        zone.x = zoneMap.value("x", 0.0).toFloat();
        zone.y = zoneMap.value("y", 0.0).toFloat();
        zone.r = zoneMap.value("r", 0.0).toFloat();
        converted.push_back(zone);
    }
    m_engine->setZones(fieldIndex, converted);
}

void InferenceController::setFloorPolygon(int fieldIndex, const QList<QVariant>& points)
{
    std::vector<std::pair<float, float>> poly;
    poly.reserve(points.size());
    for (const auto& pointVariant : points) {
        const QVariantMap pointMap = pointVariant.toMap();
        poly.push_back({pointMap.value("x", 0.0).toFloat(),
                        pointMap.value("y", 0.0).toFloat()});
    }
    m_engine->setFloorPolygon(fieldIndex, poly);
}

void InferenceController::setVelocity(int fieldIndex, float velocity)
{
    m_engine->setVelocity(fieldIndex, velocity);
}

void InferenceController::setFullFrameMode(bool enabled)
{
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

QVariantList InferenceController::getBehaviorFrames(int fieldIndex) const
{
    if (fieldIndex < 0 || fieldIndex >= 3) return {};
    const auto& history = m_engine->getScannerHistory(fieldIndex);
    QVariantList result;
    result.reserve(static_cast<int>(history.size()));
    for (const auto& rec : history) {
        QVariantMap entry;
        entry["frameIdx"]  = rec.frameIdx;
        entry["ruleLabel"] = rec.ruleLabel;
        entry["movNose"]   = static_cast<double>(rec.features[0]);
        entry["movBody"]   = static_cast<double>(rec.features[1]);
        entry["movMean"]   = static_cast<double>(rec.features[3]);
        result.append(entry);
    }
    return result;
}

QString InferenceController::behaviorCachePath(const QString& experimentPath, int fieldIndex) const
{
    if (fieldIndex < 0 || fieldIndex >= 3) return QString();
    QString cleanPath = experimentPath.trimmed();
    if (cleanPath.startsWith("file:///")) cleanPath = cleanPath.mid(8);
    if (cleanPath.isEmpty()) return QString();
    return QDir(cleanPath).filePath(
        QStringLiteral("analysis_cache/behavior_features_campo%1.csv").arg(fieldIndex + 1));
}

bool InferenceController::behaviorCacheExists(const QString& experimentPath, int fieldIndex) const
{
    const QString cachePath = behaviorCachePath(experimentPath, fieldIndex);
    return !cachePath.isEmpty() && QFile::exists(cachePath);
}

bool InferenceController::saveBehaviorCache(const QString& experimentPath, int fieldIndex)
{
    const QString cachePath = behaviorCachePath(experimentPath, fieldIndex);
    if (cachePath.isEmpty()) return false;
    QDir().mkpath(QFileInfo(cachePath).absolutePath());
    return exportBehaviorFeatures(cachePath, fieldIndex);
}

QVariantList InferenceController::getBehaviorFramesFromCache(const QString& experimentPath,
                                                             int fieldIndex) const
{
    QVariantList result;
    if (fieldIndex < 0 || fieldIndex >= 3) return result;

    const QString cachePath = behaviorCachePath(experimentPath, fieldIndex);
    QFile cacheFile(cachePath);
    if (!cacheFile.open(QIODevice::ReadOnly | QIODevice::Text))
        return result;

    QTextStream csvStream(&cacheFile);
    Q_UNUSED(csvStream.readLine())  // skip header

    while (!csvStream.atEnd()) {
        const QString dataLine = csvStream.readLine().trimmed();
        if (dataLine.isEmpty()) continue;
        const QStringList fields = dataLine.split(',');
        // frame + 21 features + rule_label = 23 columns
        if (fields.size() < 23) continue;

        bool okFrame = false, okRule = false, okNose = false, okBody = false, okMean = false;
        const int    frameIdx  = fields[0].toInt(&okFrame);
        const double movNose   = fields[1].toDouble(&okNose);
        const double movBody   = fields[2].toDouble(&okBody);
        const double movMean   = fields[4].toDouble(&okMean);  // bp_mean
        const int    ruleLabel = fields[22].toInt(&okRule);
        if (!okFrame || !okRule || !okNose || !okBody || !okMean) continue;

        QVariantMap entry;
        entry["frameIdx"]  = frameIdx;
        entry["ruleLabel"] = ruleLabel;
        entry["movNose"]   = movNose;
        entry["movBody"]   = movBody;
        entry["movMean"]   = movMean;
        result.append(entry);
    }
    return result;
}

bool InferenceController::writeTextFile(const QString& filePath, const QString& content,
                                        bool utf8Bom)
{
    QString cleanPath = filePath.trimmed();
    if (cleanPath.startsWith("file:///"))
        cleanPath = cleanPath.mid(8);
    if (cleanPath.isEmpty())
        return false;

    if (!QDir().mkpath(QFileInfo(cleanPath).absolutePath()))
        return false;

    QFile outputFile(cleanPath);
    if (!outputFile.open(QIODevice::WriteOnly | QIODevice::Text))
        return false;

    QTextStream textStream(&outputFile);
    textStream.setEncoding(QStringConverter::Utf8);
    if (utf8Bom)
        textStream << "\xEF\xBB\xBF";
    textStream << content;
    outputFile.close();
    return true;
}

QString InferenceController::readTextFile(const QString& filePath) const
{
    QString cleanPath = filePath.trimmed();
    if (cleanPath.startsWith("file:///"))
        cleanPath = cleanPath.mid(8);
    if (cleanPath.isEmpty())
        return QString();

    QFile inputFile(cleanPath);
    if (!inputFile.open(QIODevice::ReadOnly | QIODevice::Text))
        return QString();

    QTextStream textStream(&inputFile);
    textStream.setEncoding(QStringConverter::Utf8);
    return textStream.readAll();
}

bool InferenceController::savePdfReport(const QString& pdfPath,
                                        const QStringList& imagePaths,
                                        const QString& title,
                                        const QStringList& captions)
{
    QString cleanPath = pdfPath.trimmed();
    if (cleanPath.startsWith("file:///"))
        cleanPath = cleanPath.mid(8);
    if (cleanPath.isEmpty() || imagePaths.isEmpty())
        return false;

    if (!QDir().mkpath(QFileInfo(cleanPath).absolutePath()))
        return false;

    QPdfWriter pdf(cleanPath);
    pdf.setResolution(150);
    pdf.setPageSize(QPageSize(QPageSize::A4));
    pdf.setPageMargins(QMarginsF(12, 12, 12, 12), QPageLayout::Millimeter);

    QPainter painter(&pdf);
    if (!painter.isActive())
        return false;

    const QRect page        = painter.viewport();
    const int   margin      = 36;
    const QRect contentRect = page.adjusted(margin, margin, -margin, -margin);

    bool drewAny = false;
    for (int imageIndex = 0; imageIndex < imagePaths.size(); ++imageIndex) {
        QString resolvedPath = imagePaths[imageIndex].trimmed();
        if (resolvedPath.startsWith("file:///"))
            resolvedPath = resolvedPath.mid(8);
        QImage pageImage(resolvedPath);
        if (pageImage.isNull())
            continue;

        if (drewAny) pdf.newPage();
        drewAny = true;

        painter.fillRect(page, Qt::white);
        painter.setPen(QColor("#111827"));

        const QString pageTitle = title.isEmpty()
            ? QStringLiteral("MindTrace Results Report") : title;
        painter.setFont(QFont("Segoe UI", 11, QFont::Bold));
        painter.drawText(contentRect.left(), contentRect.top(), contentRect.width(), 26,
                         Qt::AlignLeft | Qt::AlignVCenter, pageTitle);

        const QString caption       = (imageIndex < captions.size()) ? captions[imageIndex] : QString();
        const int     captionHeight = caption.isEmpty() ? 0 : 24;
        painter.setFont(QFont("Segoe UI", 9));
        if (!caption.isEmpty()) {
            painter.drawText(contentRect.left(), contentRect.top() + 28,
                             contentRect.width(), 20,
                             Qt::AlignLeft | Qt::AlignVCenter, caption);
        }

        QRect imageRect = contentRect.adjusted(0, 34 + captionHeight, 0, 0);
        if (imageRect.height() < 40)
            imageRect = contentRect.adjusted(0, 34, 0, 0);

        const QSize scaledSize = pageImage.size().scaled(imageRect.size(), Qt::KeepAspectRatio);
        const QRect centeredRect(
            QPoint(imageRect.left() + (imageRect.width()  - scaledSize.width())  / 2,
                   imageRect.top()  + (imageRect.height() - scaledSize.height()) / 2),
            scaledSize);
        painter.drawImage(centeredRect, pageImage);
    }

    painter.end();
    return drewAny;
}

bool InferenceController::exportBehaviorFeatures(const QString& csvPath, int fieldIndex)
{
    if (fieldIndex < 0 || fieldIndex >= 3) return false;

    const auto& history = m_engine->getScannerHistory(fieldIndex);
    if (history.empty()) {
        qWarning() << "[InferenceController] exportBehaviorFeatures: historico vazio para campo"
                   << fieldIndex;
        return false;
    }

    QFile csvFile(csvPath);
    if (!csvFile.open(QIODevice::WriteOnly | QIODevice::Text)) {
        qWarning() << "[InferenceController] exportBehaviorFeatures: nao foi possivel abrir"
                   << csvPath;
        return false;
    }

    QTextStream csvStream(&csvFile);
    csvStream.setEncoding(QStringConverter::Utf8);
    csvStream << "\xEF\xBB\xBF";  // UTF-8 BOM for Excel compatibility

    csvStream << "frame,move_nose,move_body,bp_sum,bp_mean,bp_min,bp_max"
                 ",roll2s_mean,roll2s_sum,roll5s_mean,roll5s_sum"
                 ",roll6s_mean,roll6s_sum,roll7_5s_mean,roll7_5s_sum"
                 ",roll15s_mean,roll15s_sum"
                 ",prob_sum,prob_mean"
                 ",low_prob_01,low_prob_05,low_prob_075"
                 ",rule_label\n";

    for (const auto& rec : history) {
        csvStream << rec.frameIdx;
        for (size_t i = 0; i < 21; ++i)
            csvStream << ',' << rec.features[i];
        csvStream << ',' << rec.ruleLabel << '\n';
    }

    csvFile.close();
    qDebug() << "[InferenceController] exportBehaviorFeatures: exportados"
             << history.size() << "frames para" << csvPath;
    return true;
}

// â”€â”€ Control â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

void InferenceController::startAnalysis(const QString& videoPath, const QString& modelDir)
{
    if (m_isAnalyzing) return;

    QString localVideoPath = videoPath;
    if (localVideoPath.startsWith("file:///"))
        localVideoPath = localVideoPath.mid(8);

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
    m_player->setSource(QUrl::fromLocalFile(localVideoPath));  // Qt 6: setSource (was setMedia)
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
    QString preferredTvStandard;
    QString preferredBackend;
    int retryStage = 0;
    {
        const QStringList parts = cameraName.split("|", Qt::SkipEmptyParts);
        if (!parts.isEmpty())
            normalizedCameraName = parts.first().trimmed();
        for (int i = 1; i < parts.size(); ++i) {
            const QString token = parts[i].trimmed();
            const QString low = token.toLower();
            if (low.startsWith("input:"))
                preferredAnalogInput = token.mid(6).trimmed();
            else if (low.startsWith("tv:"))
                preferredTvStandard = token.mid(3).trimmed();
            else if (low.startsWith("backend:"))
                preferredBackend = token.mid(8).trimmed().toLower();
            else if (low.startsWith("retry:"))
                retryStage = token.mid(6).trimmed().toInt();
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
                               preferredTvStandard,
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
    const QString watchCameraName = normalizedCameraName;
    const QString watchInput = preferredAnalogInput;
    const QString watchTv = preferredTvStandard;
    const int watchRetryStage = retryStage;
    QTimer::singleShot(2200, this, [this, watchCameraName, watchInput, watchTv, watchRetryStage]() {
        if (!m_isPreviewOnly || !m_isDirectShowMode)
            return;
        if (m_liveTotalFrameCount > 2)
            return;

        if (watchRetryStage == 0) {
            const QString tvLower = watchTv.trimmed().toLower();
            const bool usingNtsc = tvLower.contains("ntsc");
            const QString altTv = usingNtsc ? QStringLiteral("PAL_M")
                                            : QStringLiteral("NTSC_M");
            emit infoReceived(QStringLiteral("Preview travado, tentando padrao TV %1...").arg(altTv));
            stopLivePreview();
            startLivePreview(watchCameraName + " |backend:dshow |input:" + watchInput + " |tv:" + altTv + " |retry:1");
            return;
        }

        if (watchRetryStage == 1) {
            const bool currentSVideo = watchInput.trimmed().toLower().contains("s-video")
                                       || watchInput.trimmed().toLower().contains("svideo");
            const QString altInput = currentSVideo ? QStringLiteral("Composite")
                                                   : QStringLiteral("S-Video");
            emit infoReceived(QStringLiteral("Preview ainda travado em %1, tentando entrada %2...")
                              .arg(watchInput, altInput));
            stopLivePreview();
            startLivePreview(watchCameraName + " |backend:dshow |input:" + altInput + " |tv:" + watchTv + " |retry:2");
        }
    });
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
    m_liveTotalFrameCount = 0;
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
    m_liveTotalFrameCount = 0;
    m_loggedLiveNullFrame = false;

    // Prefer DirectShow for analog capture cards (e.g. Hauppauge Composite).
    QString normalizedCameraName = cameraName;
    QString preferredAnalogInput = "Composite";
    QString preferredTvStandard;
    QString preferredBackend;
    int retryStage = 0;
    {
        const QStringList parts = cameraName.split("|", Qt::SkipEmptyParts);
        if (!parts.isEmpty())
            normalizedCameraName = parts.first().trimmed();
        for (int i = 1; i < parts.size(); ++i) {
            const QString token = parts[i].trimmed();
            const QString low = token.toLower();
            if (low.startsWith("input:"))
                preferredAnalogInput = token.mid(6).trimmed();
            else if (low.startsWith("tv:"))
                preferredTvStandard = token.mid(3).trimmed();
            else if (low.startsWith("backend:"))
                preferredBackend = token.mid(8).trimmed().toLower();
            else if (low.startsWith("retry:"))
                retryStage = token.mid(6).trimmed().toInt();
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
             << "preferredTv=" << preferredTvStandard
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
                                  preferredTvStandard,
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
            const QString watchTv = preferredTvStandard;
            const int watchRetryStage = retryStage;
            QTimer::singleShot(2200, this, [this,
                                            watchCameraName,
                                            watchInput,
                                            watchTv,
                                            watchRetryStage,
                                            modelDir,
                                            saveDirectory,
                                            preferredFileName,
                                            preferredWidth,
                                            preferredHeight,
                                            preferredFps]() {
                if (!m_isAnalyzing || !m_isDirectShowMode)
                    return;
                if (m_liveTotalFrameCount > 2)
                    return;

                if (watchRetryStage == 0) {
                    const QString tvLower = watchTv.trimmed().toLower();
                    const bool usingNtsc = tvLower.contains("ntsc");
                    const QString altTv = usingNtsc ? QStringLiteral("PAL_M")
                                                    : QStringLiteral("NTSC_M");
                    emit infoReceived(QStringLiteral("DirectShow com stream travado, tentando padrao TV %1...")
                                      .arg(altTv));
                    stopAnalysis();
                    startLiveAnalysis(watchCameraName + " |input:" + watchInput + " |tv:" + altTv + " |retry:1",
                                      modelDir,
                                      saveDirectory,
                                      preferredFileName,
                                      preferredWidth,
                                      preferredHeight,
                                      preferredFps);
                    return;
                }

                if (watchRetryStage == 1) {
                    const bool currentSVideo = watchInput.trimmed().toLower().contains("s-video")
                                               || watchInput.trimmed().toLower().contains("svideo");
                    const QString altInput = currentSVideo ? QStringLiteral("Composite")
                                                           : QStringLiteral("S-Video");
                    emit infoReceived(QStringLiteral("DirectShow ainda travado em %1, tentando entrada %2...")
                                      .arg(watchInput, altInput));
                    stopAnalysis();
                    startLiveAnalysis(watchCameraName + " |input:" + altInput + " |tv:" + watchTv + " |retry:2",
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
                          .arg(pixelFormatName(f.pixelFormat())));
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
                              .arg(pixelFormatName(bestFormat.pixelFormat())));
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
    if (m_isLiveMode) {
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
    } else if (m_isAnalyzing) {
        m_player->stop();
    }

    // Important: pre-warm may leave InferenceEngine running even when
    // m_isAnalyzing is false. Always stop thread during teardown.
    // Do not use a short timeout here: if the thread is still creating ONNX
    // sessions, a timed wait can return early and QThread may be destroyed
    // while still running.
    if (m_engine && m_engine->isRunning()) {
        m_engine->requestStop();
        m_engine->wait();
    }

    m_isLiveMode = false;
    m_isDirectShowMode = false;
    m_liveFpsWindowStartMs = 0;
    m_liveFpsFrameCount = 0;
    m_liveTotalFrameCount = 0;
    m_loggedLiveNullFrame = false;
    setAnalyzing(false);
}

// â”€â”€ Frame capture (multimedia thread) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

void InferenceController::onVideoFrameChanged(const QVideoFrame& frame)
{
    // Log real pixel format on first live frame for diagnostics.
    if (m_isLiveMode && m_videoW == 0 && m_videoH == 0) {
        const QVideoFrameFormat::PixelFormat pixFmt = frame.surfaceFormat().pixelFormat();
        const QString msg = QString("First frame actual: %1x%2  fmt=%3")
                            .arg(frame.width()).arg(frame.height())
                            .arg(pixelFormatName(pixFmt));
        QMetaObject::invokeMethod(this, [this, msg]() {
            emit infoReceived(msg);
        }, Qt::QueuedConnection);
    }

    QImage image = frame.toImage();
    if (image.isNull()) {
        if (m_isLiveMode && !m_loggedLiveNullFrame) {
            m_loggedLiveNullFrame = true;
            const QVideoFrameFormat::PixelFormat pixFmt = frame.surfaceFormat().pixelFormat();
            QMetaObject::invokeMethod(this, [this, pixFmt]() {
                emit infoReceived(
                    QString("Live frame conversion falhou (QVideoFrame::toImage nulo). "
                            "PixelFormat=%1 (%2)")
                    .arg(pixelFormatName(pixFmt))
                    .arg(static_cast<int>(pixFmt)));
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
        // Qt 6: metaData() returns QMediaMetaData — access via enum key.
        double fps = m_player->metaData().value(QMediaMetaData::VideoFrameRate).toDouble();
        if (fps <= 0.0) fps = 30.0;
        emit fpsReceived(fps);

    } else if (status == QMediaPlayer::EndOfMedia) {
        setAnalyzing(false);

    } else if (status == QMediaPlayer::InvalidMedia) {
        emit errorOccurred("Video invalido ou nao suportado pelo codec do sistema.");
        setAnalyzing(false);
    }
}

