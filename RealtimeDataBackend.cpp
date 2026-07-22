#include "RealtimeDataBackend.h"

#include <QtMath>
#include <algorithm>
#include <cmath>
#include <limits>

namespace { constexpr double Tau = 6.28318530717958647692; }

RealtimeDataBackend::RealtimeDataBackend(QObject *parent) : QObject(parent), m_validMasks(Capacity, 0)
{
    for (auto &channel : m_raw)
        channel.assign(Capacity, std::numeric_limits<float>::quiet_NaN());
    for (int levelIndex = 0; levelIndex < int(m_levels.size()); ++levelIndex) {
        auto &level = m_levels[levelIndex];
        level.groupSize = quint64(1) << (2 * (levelIndex + 1)); // 4, 16, 64 ...
        level.capacity = (Capacity + level.groupSize - 1) / level.groupSize + 2;
        level.groups.assign(level.capacity, std::numeric_limits<quint64>::max());
        for (auto &channel : level.channels)
            channel.resize(level.capacity);
    }
}

QVariantMap RealtimeDataBackend::displaySnapshot() const { return m_displaySnapshot; }
int RealtimeDataBackend::historyCount() const { return int(m_historyCount); }
double RealtimeDataBackend::latestSampleTime() const { return m_historyCount ? timeAt(m_nextSample - 1) : 0.0; }
double RealtimeDataBackend::historyStartTime() const { return m_historyCount ? timeAt(m_nextSample - m_historyCount) : 0.0; }

float RealtimeDataBackend::valueFor(int channelIndex, double time) const
{
    const int channelId = channelIndex + 1;
    const double frequency = 125.0 + (channelId % 16) * 47.0;
    const double amplitude = .55 + (channelId % 5) * .12;
    const double phase = channelId * .37;
    const double carrier = qSin(Tau * frequency * time + phase);
    const double harmonic = .08 * qSin(Tau * frequency * 3.0 * time + phase + .4);
    const double modulation = 1.0 + .12 * qSin(Tau * (.06 + channelId * .01) * time + phase);
    const double noise = .012 * qSin((190 + channelId * 31) * time) + .006 * qSin((430 + channelId * 41) * time);
    return float(amplitude * (modulation * (carrier + harmonic) + noise));
}

bool RealtimeDataBackend::isInHistory(quint64 index) const { return index >= m_nextSample - m_historyCount && index < m_nextSample; }
double RealtimeDataBackend::timeAt(quint64 index) const { return m_originTime + double(index) * m_sampleInterval; }
float RealtimeDataBackend::valueAt(int channel, quint64 index) const
{
    if (!isInHistory(index) || !(m_validMasks[index % Capacity] & (quint64(1) << channel)))
        return std::numeric_limits<float>::quiet_NaN();
    return m_raw[channel][index % Capacity];
}

quint64 RealtimeDataBackend::firstSampleIndexAtOrAfter(double time) const
{
    const quint64 begin = m_nextSample - m_historyCount;
    if (!m_historyCount || time <= timeAt(begin)) return begin;
    if (time > latestSampleTime()) return m_nextSample;
    return std::clamp<quint64>(quint64(std::ceil((time - m_originTime) / m_sampleInterval - 1e-9)), begin, m_nextSample);
}

quint64 RealtimeDataBackend::lastSampleIndexAtOrBefore(double time) const
{
    const quint64 begin = m_nextSample - m_historyCount;
    if (!m_historyCount || time < timeAt(begin)) return begin - 1;
    if (time >= latestSampleTime()) return m_nextSample - 1;
    return std::clamp<quint64>(quint64(std::floor((time - m_originTime) / m_sampleInterval + 1e-9)), begin, m_nextSample - 1);
}

void RealtimeDataBackend::updateLevels(quint64 sampleIndex, int channelIndex, float value)
{
    if (!std::isfinite(value)) return;
    for (auto &level : m_levels) {
        const quint64 group = sampleIndex / level.groupSize;
        const quint64 slot = group % level.capacity;
        auto &bucket = level.channels[channelIndex][slot];
        if (bucket.epoch != m_cacheEpoch || bucket.group != group) {
            level.groups[slot] = group;
            bucket = { value, value, sampleIndex, sampleIndex, group, m_cacheEpoch };
        } else {
            if (value < bucket.minimum) { bucket.minimum = value; bucket.minIndex = sampleIndex; }
            if (value > bucket.maximum) { bucket.maximum = value; bucket.maxIndex = sampleIndex; }
        }
    }
}

void RealtimeDataBackend::appendSimulatedSamples(double startTime, double sampleInterval, int count, const QVariantList &enabledChannels)
{
    if (count <= 0 || sampleInterval <= 0.0) return;
    // A fixed-dt ring and its min/max hierarchy cannot safely mix rates.
    // Switch generations before the first new-rate sample rather than
    // interpreting old timestamps with the new rate.
    if (m_historyCount && !qFuzzyCompare(sampleInterval, m_sampleInterval))
        resetHistoryStorage();
    if (m_nextSample == 0) m_originTime = startTime;
    m_sampleInterval = sampleInterval;
    quint64 enabledMask = 0;
    std::vector<int> enabled;
    enabled.reserve(enabledChannels.size());
    for (const auto &item : enabledChannels) {
        const int index = item.toInt();
        if (index >= 0 && index < ChannelCount && !(enabledMask & (quint64(1) << index))) {
            enabledMask |= quint64(1) << index;
            enabled.push_back(index);
        }
    }
    for (int offset = 0; offset < count; ++offset) {
        const quint64 index = m_nextSample++;
        const quint64 slot = index % Capacity;
        const double time = startTime + double(offset) * sampleInterval;
        m_validMasks[slot] = enabledMask;
        for (const int channel : enabled) {
            const float value = valueFor(channel, time);
            m_raw[channel][slot] = value;
            updateLevels(index, channel, value);
        }
        m_historyCount = std::min<quint64>(Capacity, m_historyCount + 1);
    }
    ++m_dataRevision;
    emit historyChanged();
}

QVariantList RealtimeDataBackend::rawSeries(int channel, quint64 first, quint64 last, double start, double duration, int width) const
{
    QVariantList values;
    if (last < first) return values;
    values.reserve(int(std::min<quint64>((last - first + 1) * 2, 3ull * quint64(width))));
    for (quint64 index = first; index <= last; ++index) {
        const float value = valueAt(channel, index);
        if (!std::isfinite(value)) continue;
        values << ((timeAt(index) - start) / duration * width) << value;
    }
    return values;
}

QVariantList RealtimeDataBackend::envelopeSeries(int channel, quint64 first, quint64 last, quint64 groupSize, double start, double duration, int width) const
{
    QVariantList values;
    if (last < first) return values;
    int levelIndex = 0;
    while (levelIndex + 1 < int(m_levels.size()) && m_levels[levelIndex].groupSize < groupSize) ++levelIndex;
    const auto &level = m_levels[levelIndex];
    const quint64 firstGroup = first / level.groupSize, lastGroup = last / level.groupSize;
    values.reserve(int(std::min<quint64>((lastGroup - firstGroup + 1) * 4, 4ull * quint64(width))));
    for (quint64 group = firstGroup; group <= lastGroup; ++group) {
        const auto slot = group % level.capacity;
        if (level.groups[slot] != group) continue;
        const auto &bucket = level.channels[channel][slot];
        if (bucket.epoch != m_cacheEpoch || bucket.group != group || !isInHistory(bucket.minIndex) || !isInHistory(bucket.maxIndex)) continue;
        const auto append = [&](quint64 index, float value) { values << ((timeAt(index) - start) / duration * width) << value; };
        // Min/max are emitted in their true sample order, never as a synthetic zig-zag.
        if (bucket.minIndex <= bucket.maxIndex) { append(bucket.minIndex, bucket.minimum); append(bucket.maxIndex, bucket.maximum); }
        else { append(bucket.maxIndex, bucket.maximum); append(bucket.minIndex, bucket.minimum); }
    }
    return values;
}

void RealtimeDataBackend::refreshDisplaySnapshot(double windowStart, double windowEnd, double sampleRate, int plotWidth, const QVariantList &visibleChannels)
{
    std::vector<int> requestedChannels;
    requestedChannels.reserve(visibleChannels.size());
    for (const auto &item : visibleChannels) {
        const int channel = item.toInt();
        if (channel >= 0 && channel < ChannelCount)
            requestedChannels.push_back(channel);
    }
    // Several QML bindings can request a paint in one UI frame.  A stable
    // window and data revision must reuse the immutable snapshot instead of
    // rebuilding all compact series repeatedly.
    if (m_snapshotRevision == m_dataRevision && m_snapshotStart == windowStart && m_snapshotEnd == windowEnd
        && m_snapshotRate == sampleRate && m_snapshotWidth == plotWidth && m_snapshotChannels == requestedChannels)
        return;
    const double duration = std::max(1e-12, windowEnd - windowStart);
    const int width = std::max(1, plotWidth);
    const double theoreticalSamplesPerPixel = sampleRate * duration / width;
    const quint64 first = m_historyCount ? firstSampleIndexAtOrAfter(windowStart) : 0;
    const quint64 last = m_historyCount ? lastSampleIndexAtOrBefore(windowEnd) : 0;
    // The actual retained range is a safety bound during a rate-generation
    // transition.  Never select the raw path merely because a caller supplied
    // a lower new rate while old high-rate samples are still present.
    const double actualSamplesPerPixel = m_historyCount && last >= first ? double(last - first + 1) / width : 0.0;
    const double samplesPerPixel = std::max(theoreticalSamplesPerPixel, actualSamplesPerPixel);
    const bool envelope = samplesPerPixel >= 2.0;
    quint64 groupSize = 1;
    if (envelope) while (groupSize < quint64(std::ceil(samplesPerPixel)) && groupSize < m_levels.back().groupSize) groupSize *= 4;

    QVariantList channels;
    channels.reserve(int(requestedChannels.size()));
    for (const int channel : requestedChannels) {
        QVariantMap series;
        series.insert("channelIndex", channel);
        series.insert("points", m_historyCount ? (envelope ? envelopeSeries(channel, first, last, groupSize, windowStart, duration, width)
                                                   : rawSeries(channel, first, last, windowStart, duration, width)) : QVariantList{});
        channels << series;
    }
    QVariantMap snapshot;
    snapshot.insert("windowStart", windowStart); snapshot.insert("windowEnd", windowEnd);
    snapshot.insert("samplesPerPixel", samplesPerPixel); snapshot.insert("mode", envelope ? "envelope" : "raw");
    snapshot.insert("channels", channels); snapshot.insert("sampleCount", m_historyCount && last >= first ? double(last - first + 1) : 0.0);
    m_displaySnapshot = snapshot;
    m_snapshotRevision = m_dataRevision;
    m_snapshotStart = windowStart; m_snapshotEnd = windowEnd; m_snapshotRate = sampleRate;
    m_snapshotWidth = plotWidth; m_snapshotChannels = std::move(requestedChannels);
    emit displaySnapshotChanged();
}

double RealtimeDataBackend::zeroCrossingFrequency(int channel, double endTime, double duration) const
{
    const quint64 first = firstSampleIndexAtOrAfter(endTime - duration), last = lastSampleIndexAtOrBefore(endTime);
    if (channel < 0 || channel >= ChannelCount || last <= first) return 0.0;
    int crossings = 0; float previous = std::numeric_limits<float>::quiet_NaN();
    for (quint64 index = first; index <= last; ++index) { const float value = valueAt(channel, index); if (std::isfinite(value) && std::isfinite(previous) && previous <= 0.f && value > 0.f) ++crossings; previous = value; }
    return last > first ? crossings / std::max(1e-12, timeAt(last) - timeAt(first)) : 0.0;
}

QVariantMap RealtimeDataBackend::channelRange(int channel, double start, double end) const
{
    float minimum = std::numeric_limits<float>::infinity(), maximum = -std::numeric_limits<float>::infinity();
    const quint64 first = firstSampleIndexAtOrAfter(start), last = lastSampleIndexAtOrBefore(end);
    if (channel >= 0 && channel < ChannelCount && last >= first)
        for (quint64 index = first; index <= last; ++index) { const float value = valueAt(channel, index); if (std::isfinite(value)) { minimum = std::min(minimum, value); maximum = std::max(maximum, value); } }
    return {{"minimum", minimum}, {"maximum", maximum}, {"valid", std::isfinite(minimum)}};
}

void RealtimeDataBackend::resetHistoryStorage()
{
    m_nextSample = 0; m_historyCount = 0; m_originTime = 0.0; m_displaySnapshot.clear(); ++m_dataRevision;
    m_snapshotRevision = std::numeric_limits<quint64>::max();
    ++m_cacheEpoch;
    // Epoch invalidation makes clear O(1): the old fixed-capacity raw and
    // aggregate arrays are ignored until their slots are overwritten.
    if (m_cacheEpoch == 0) {
        m_cacheEpoch = 1;
        for (auto &level : m_levels)
            for (auto &channel : level.channels)
                for (auto &bucket : channel)
                    bucket.epoch = 0;
    }
}

void RealtimeDataBackend::clearHistory()
{
    resetHistoryStorage();
    emit historyChanged(); emit displaySnapshotChanged();
}
