#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include "RecorderBackend.h"

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setApplicationVersion(QStringLiteral("0.1.0"));

    QQmlApplicationEngine engine;
    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &app,
        []() { QCoreApplication::exit(-1); },
        Qt::QueuedConnection);
    engine.loadFromModule("osc_recorder", "Main");

    return QGuiApplication::exec();
}
