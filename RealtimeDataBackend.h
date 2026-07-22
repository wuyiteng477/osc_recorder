#pragma once

#include <QObject>
#include <QVariantList>
#include <QVariantMap>
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
    Q_INVOKABLE void clearHistory();
    Q_INVOKABLE void refreshDisplaySnapshot(double windowStart, double windowEnd, double sampleRate, int plotWidth, const QVariantList &visibleChannels);
    Q_INVOKABLE double zeroCrossingFrequency(int channelIndex, double endTime, double durationSeconds) const;
    Q_INVOKABLE QVariantMap channelRange(int channelIndex, double startTime, double endTime) const;

signals:
    void historyChanged();
    void displaySnapshotChanged();

private:
    static constexpr int ChannelCount = 64;
    static constexpr quint64 Capacity = 262144;
    struct Bucket { float minimum = 0.f; float maximum = 0.f; quint64 minIndex = 0; quint64 maxIndex = 0; quint64 group = std::numeric_limits<quint64>::max(); };
    struct Level { quint64 groupSize = 1; quint64 capacity = 0; std::vector<quint64> groups; std::array<std::vector<Bucket>, ChannelCount> channels; };

    float valueFor(int channelIndex, double time) const;
    quint64 firstSampleIndexAtOrAfter(double time) const;
    quint64 lastSampleIndexAtOrBefore(double time) const;
    bool isInHistory(quint64 sampleIndex) const;
    float valueAt(int channelIndex, quint64 sampleIndex) const;
    double timeAt(quint64 sampleIndex) const;
    void updateLevels(quint64 sampleIndex, int channelIndex, float value);
    QVariantList rawSeries(int channelIndex, quint64 first, quint64 last, double windowStart, double duration, int width) const;
    QVariantList envelopeSeries(int channelIndex, quint64 first, quint64 last, quint64 groupSize, double windowStart, double duration, int width) const;

    std::array<std::vector<float>, ChannelCount> m_raw;
    // Raw samples are level 0.  Cached aggregate levels begin at 4 samples.
    std::array<Level, 8> m_levels;
    std::array<bool, ChannelCount> m_enabled {};
    quint64 m_nextSample = 0;
    quint64 m_historyCount = 0;
    double m_originTime = 0.0;
    double m_sampleInterval = 1.0 / 5000.0;
    QVariantMap m_displaySnapshot;
};
