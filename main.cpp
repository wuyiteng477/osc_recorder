#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include "RecorderBackend.h"
#include "RealtimeDataBackend.h"

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

    if (!engine.rootObjects().isEmpty()) {
        QObject *root = engine.rootObjects().constFirst();
        auto *realtime = root->findChild<RealtimeDataBackend *>("realtimeDataBackend");
        auto *recorder = root->findChild<RecorderBackend *>("recorderBackend");
        if (realtime && recorder)
            QObject::connect(realtime, &RealtimeDataBackend::rawSampleBlockReady,
                             recorder, &RecorderBackend::enqueueRawSampleBlock,
                             Qt::DirectConnection);
    }

    return QGuiApplication::exec();
}
