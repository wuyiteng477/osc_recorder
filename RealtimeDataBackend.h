#pragma once

#include <QObject>
#include <QVariantList>
#include <QVariantMap>
#include <QString>
#include <QByteArray>
#include <QtQmlIntegration/qqmlintegration.h>
#include <array>
#include <limits>
#include <vector>

// Owns the simulated acquisition history and all display decimation.  QML is
// deliberately limited to metadata and drawing the compact immutable snapshot.
class RealtimeDataBackend : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QVariantMap displaySnapshot READ displaySnapshot NOTIFY displaySnapshotChanged)
    Q_PROPERTY(int historyCount READ historyCount NOTIFY historyChanged)
    Q_PROPERTY(double historyStartTime READ historyStartTime NOTIFY historyChanged)
    Q_PROPERTY(double latestSampleTime READ latestSampleTime NOTIFY historyChanged)

public:
    explicit RealtimeDataBackend(QObject *parent = nullptr);
    QVariantMap displaySnapshot() const;
    int historyCount() const;
    double historyStartTime() const;
    double latestSampleTime() const;

    Q_INVOKABLE void appendSimulatedSamples(double startTime, double sampleInterval, int count, const QVariantList &enabledChannels);
    Q_INVOKABLE void configureSimulationEvents(const QString &mode);
    Q_INVOKABLE void setRecordingBlockPublishing(bool enabled);
    Q_INVOKABLE QVariantList simulatedEvents() const;
    Q_INVOKABLE void configureEdgeTrigger(int channelIndex, const QString &edge, double level, double hysteresis, const QString &mode);
    Q_INVOKABLE void rearmEdgeTrigger();
    Q_INVOKABLE void setDisplayHistoryFrozen(bool frozen);
    Q_INVOKABLE void clearHistory();
    Q_INVOKABLE void refreshDisplaySnapshot(double windowStart, double windowEnd, double sampleRate, int plotWidth, const QVariantList &visibleChannels);
    Q_INVOKABLE double zeroCrossingFrequency(int channelIndex, double endTime, double durationSeconds) const;
    Q_INVOKABLE QVariantMap channelRange(int channelIndex, double startTime, double endTime) const;
    // Uses the retained, undecimated raw samples only.  The map separates
    // general statistics from period validity so a short window can still show
    // amplitude while clearly reporting an unreliable frequency as "--".
    Q_INVOKABLE QVariantMap measureWindow(int channelIndex, double startTime, double endTime,
                                          const QString &thresholdMode, double threshold,
                                          double hysteresis, const QString &edge,
                                          double lowThreshold, double highThreshold) const;

signals:
    void historyChanged();
    void displaySnapshotChanged();
    void simulationEventOccurred(const QVariantMap &event);
    void rawSampleBlockReady(double startTime, const QByteArray &payload, bool hasGap);
    void rawTriggerDetected(const QVariantMap &trigger);
    void edgeTriggerDetected(const QVariantMap &trigger);

private:
    static constexpr int ChannelCount = 64;
    static constexpr quint64 Capacity = 262144;
    struct Bucket { float minimum = 0.f; float maximum = 0.f; quint64 minIndex = 0; quint64 maxIndex = 0; quint64 group = std::numeric_limits<quint64>::max(); quint32 epoch = 0; bool hasGap = false; };
    struct Level { quint64 groupSize = 1; quint64 capacity = 0; std::vector<quint64> groups; std::array<std::vector<Bucket>, ChannelCount> channels; };
    enum class SimEventType { Spike, StepRecover, Pulse, Dropout, NoiseBurst };
    struct SimEvent { quint64 id = 0; SimEventType type = SimEventType::Spike; int channel = -1; quint64 start = 0; quint64 duration = 1; float amplitude = 0.f; quint32 seed = 0; };

    float valueFor(int channelIndex, quint64 sampleIndex) const;
    quint64 firstSampleIndexAtOrAfter(double time) const;
    quint64 lastSampleIndexAtOrBefore(double time) const;
    bool isInHistory(quint64 sampleIndex) const;
    float valueAt(int channelIndex, quint64 sampleIndex) const;
    double timeAt(quint64 sampleIndex) const;
    void updateLevels(quint64 sampleIndex, int channelIndex, float value);
    void markGapLevels(quint64 sampleIndex, int channelIndex);
    void resetHistoryStorage();
    void resetEventSchedule();
    void evaluateEdgeTrigger(quint64 sampleIndex, int channelIndex, float value, bool valid);
    quint32 nextRandom();
    void scheduleEventIfDue(quint64 sampleIndex, const std::vector<int> &enabledChannels, double sampleRate);
    float applySimulationEvents(quint64 sampleIndex, int channelIndex, float value, bool *valid) const;
    static QString eventTypeName(SimEventType type);
    QVariantList rawSeries(int channelIndex, quint64 first, quint64 last, double windowStart, double duration, int width) const;
    QVariantList envelopeSeries(int channelIndex, quint64 first, quint64 last, quint64 groupSize, double windowStart, double duration, int width) const;

    std::array<std::vector<float>, ChannelCount> m_raw;
    std::vector<quint64> m_validMasks;
    // Raw samples are level 0.  Cached aggregate levels begin at 4 samples.
    std::array<Level, 8> m_levels;
    quint64 m_nextSample = 0;
    quint64 m_historyCount = 0;
    quint64 m_dataRevision = 0;
    quint64 m_snapshotRevision = std::numeric_limits<quint64>::max();
    quint32 m_cacheEpoch = 1;
    double m_originTime = 0.0;
    double m_sampleInterval = 1.0 / 5000.0;
    double m_snapshotStart = 0.0, m_snapshotEnd = 0.0, m_snapshotRate = 0.0;
    int m_snapshotWidth = 0;
    std::vector<int> m_snapshotChannels;
    QVariantMap m_displaySnapshot;
    QString m_eventMode = QStringLiteral("off");
    quint32 m_eventSeed = 12345;
    quint32 m_eventState = 12345;
    std::array<quint64, ChannelCount> m_nextEventSamples {};
    quint64 m_nextEventId = 1;
    std::vector<SimEvent> m_activeEvents;
    QVariantList m_eventHistory;
    std::array<float, ChannelCount> m_triggerPrevious {};
    int m_edgeTriggerChannel = 0;
    QString m_edgeTriggerEdge = QStringLiteral("rising");
    QString m_edgeTriggerMode = QStringLiteral("auto");
    float m_edgeTriggerLevel = 0.f;
    float m_edgeTriggerHysteresis = .1f;
    float m_edgeTriggerPrevious = std::numeric_limits<float>::quiet_NaN();
    bool m_edgeTriggerArmed = true;
    bool m_singleTriggerCaptured = false;
    bool m_displayHistoryFrozen = false;
    bool m_recordingBlockPublishing = false;
};
