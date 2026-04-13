#include <QApplication>
#include <QQmlApplicationEngine>
#include "inference_controller.h"
#include "BehaviorTimeline.h"
#include <QQmlContext>
#include <QtQml>
#include <QMessageBox>

#include "ExperimentManager.h"
#include "ExperimentTableModel.h"
#include "ArenaModel.h"
#include "ArenaConfigModel.h"
#include "ThemeSettings.h"
#include <QFile>
#include <QTextStream>
#include <QDateTime>

// Redireciona todos os logs do Qt para um arquivo ao lado do exe
static QFile *g_logFile = nullptr;
static void messageHandler(QtMsgType type, const QMessageLogContext &ctx, const QString &msg)
{
    Q_UNUSED(ctx)
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
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("MindTrace"));
    app.setOrganizationName(QStringLiteral("NeuroLab"));

    // Log em arquivo — applicationDirPath() só funciona após QApplication
    QFile logFile(QCoreApplication::applicationDirPath() + "/mindtrace.log");
    if (logFile.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
        g_logFile = &logFile;
        qInstallMessageHandler(messageHandler);
    }

    qDebug() << "MindTrace iniciando...";

    // ── Registro de tipos C++ no motor QML ──────────────────────────────
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

    qDebug() << "Tipos QML registrados.";

    qmlRegisterType<InferenceController>("MindTrace.Tracking", 1, 0, "InferenceController");
    qmlRegisterType<BehaviorTimeline>("MindTrace.Tracking", 1, 0, "BehaviorTimeline");

    QQmlApplicationEngine engine;

    // Registra ThemeSettings como context property para acesso QML
    ThemeSettings *themeSettings = new ThemeSettings(&engine);
    engine.rootContext()->setContextProperty("ThemeSettings", themeSettings);

    // Coleta todos os warnings/erros emitidos pelo motor QML
    QStringList qmlErrors;
    QObject::connect(&engine, &QQmlApplicationEngine::warnings,
        [&qmlErrors](const QList<QQmlError> &warnings) {
            for (const QQmlError &e : warnings) {
                qCritical() << e.toString();
                qmlErrors << e.toString();
            }
        });

    const QUrl url(QStringLiteral("qrc:/qml/core/main.qml"));
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreated,
        &app, [url, &qmlErrors](QObject *obj, const QUrl &objUrl) {
            if (!obj && url == objUrl) {
                QString details = qmlErrors.isEmpty()
                    ? "(sem detalhes — verifique build/mindtrace.log)"
                    : qmlErrors.join("\n");
                QMessageBox::critical(nullptr, "MindTrace — Erro de inicialização",
                    "Falha ao carregar a interface QML:\n\n" + details);
                QCoreApplication::exit(-1);
            }
        },
        Qt::QueuedConnection);

    qDebug() << "Carregando QML:" << url;
    engine.load(url);

    qDebug() << "app.exec() iniciando...";
    return app.exec();
}
