#include "ArenaConfigModel.h"
#include "ArenaModel.h"
#include "BSoidAnalyzer.h"
#include "BehaviorTimeline.h"
#include "ExperimentManager.h"
#include "ExperimentTableModel.h"
#include "LanguageSettings.h"
#include "ThemeSettings.h"
#include "inference_controller.h"
#include "video_input_enumerator.h"

#include <QApplication>
#include <QDateTime>
#include <QFile>
#include <QMessageBox>
#include <QMutex>
#include <QMutexLocker>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QTextStream>
#include <QtQml>

// Redirect all Qt log messages to a file alongside the executable
static QFile *g_logFile = nullptr;
static QMutex g_logMutex;
static void messageHandler(QtMsgType type, const QMessageLogContext &ctx, const QString &msg)
{
    Q_UNUSED(ctx)
    QMutexLocker lock(&g_logMutex);
    if (!g_logFile || !g_logFile->isOpen()) return;
    QTextStream out(g_logFile);
    const char *level = "DEBUG";
    if      (type == QtWarningMsg)  level = "WARN ";
    else if (type == QtCriticalMsg) level = "ERROR";
    else if (type == QtFatalMsg)    level = "FATAL";
    out << QDateTime::currentDateTime().toString("hh:mm:ss.zzz")
        << " [" << level << "] " << msg << "\n";
    out.flush();
    if (type == QtFatalMsg) abort();
}

int main(int argc, char *argv[])
{
    QApplication app(argc, argv);
    QQuickStyle::setStyle(QStringLiteral("Basic"));
    app.setApplicationName(QStringLiteral("MindTrace"));
    app.setOrganizationName(QStringLiteral("NeuroLab"));

    // Log to file — applicationDirPath() is only valid after QApplication is constructed
    QFile logFile(QCoreApplication::applicationDirPath() + "/mindtrace.log");
    if (logFile.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
        g_logFile = &logFile;
        qInstallMessageHandler(messageHandler);
    }

    qDebug() << "MindTrace starting...";

    // Register C++ types with the QML engine
    qmlRegisterSingletonType<ExperimentManager>(
        "MindTrace.Backend", 1, 0, "ExperimentManager",
        [](QQmlEngine *engine, QJSEngine *) -> QObject * {
            auto *mgr = new ExperimentManager(engine);
            QQmlEngine::setObjectOwnership(mgr, QQmlEngine::CppOwnership);
            return mgr;
        });

    qmlRegisterType<ExperimentTableModel>(
        "MindTrace.Backend", 1, 0, "ExperimentTableModel");

    qmlRegisterSingletonType<ArenaModel>(
        "MindTrace.Backend", 1, 0, "ArenaModel",
        [](QQmlEngine *engine, QJSEngine *) -> QObject * {
            auto *model = new ArenaModel(engine);
            QQmlEngine::setObjectOwnership(model, QQmlEngine::CppOwnership);
            return model;
        });

    qmlRegisterSingletonType<ArenaConfigModel>(
        "MindTrace.Backend", 1, 0, "ArenaConfigModel",
        [](QQmlEngine *engine, QJSEngine *) -> QObject * {
            auto *cfg = new ArenaConfigModel(engine);
            QQmlEngine::setObjectOwnership(cfg, QQmlEngine::CppOwnership);
            return cfg;
        });

    qDebug() << "QML types registered.";

    qmlRegisterType<InferenceController>("MindTrace.Tracking", 1, 0, "InferenceController");
    qmlRegisterType<VideoInputEnumerator>("MindTrace.Tracking", 1, 0, "VideoInputEnumerator");
    qmlRegisterType<BehaviorTimeline>("MindTrace.Tracking", 1, 0, "BehaviorTimeline");
    qmlRegisterType<BSoidAnalyzer>("MindTrace.Analysis", 1, 0, "BSoidAnalyzer");

    QQmlApplicationEngine engine;

    // Expose settings as context properties for QML access
    ThemeSettings *themeSettings = new ThemeSettings(&engine);
    engine.rootContext()->setContextProperty("ThemeSettings", themeSettings);
    LanguageSettings *languageSettings = new LanguageSettings(&engine);
    engine.rootContext()->setContextProperty("LanguageSettings", languageSettings);

    // Collect all warnings and errors emitted by the QML engine
    QStringList qmlErrors;
    QObject::connect(&engine, &QQmlApplicationEngine::warnings,
        [&qmlErrors](const QList<QQmlError> &warnings) {
            for (const QQmlError &qmlError : warnings) {
                qCritical() << qmlError.toString();
                qmlErrors << qmlError.toString();
            }
        });

    const QUrl url(QStringLiteral("qrc:/qml/core/main.qml"));
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreated,
        &app, [url, &qmlErrors](QObject *obj, const QUrl &objUrl) {
            if (!obj && url == objUrl) {
                QString details = qmlErrors.isEmpty()
                    ? "(no details — check build/mindtrace.log)"
                    : qmlErrors.join("\n");
                QMessageBox::critical(nullptr, "MindTrace — Initialization Error",
                    "Failed to load QML interface:\n\n" + details);
                QCoreApplication::exit(-1);
            }
        },
        Qt::QueuedConnection);

    qDebug() << "Loading QML:" << url;
    engine.load(url);

    qDebug() << "Entering event loop...";
    return app.exec();
}
