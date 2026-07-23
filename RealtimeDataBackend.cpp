#include "RealtimeDataBackend.h"

#include <QtMath>
#include <QDataStream>
#include <QIODevice>
#include <QRandomGenerator>
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
    m_triggerPrevious.fill(std::numeric_limits<float>::quiet_NaN());
}

QVariantMap RealtimeDataBackend::displaySnapshot() const { return m_displaySnapshot; }
int RealtimeDataBackend::historyCount() const { return int(m_historyCount); }
double RealtimeDataBackend::latestSampleTime() const { return m_historyCount ? timeAt(m_nextSample - 1) : 0.0; }
double RealtimeDataBackend::historyStartTime() const { return m_historyCount ? timeAt(m_nextSample - m_historyCount) : 0.0; }

float RealtimeDataBackend::valueFor(int channelIndex, quint64 sampleIndex) const
{
    const int channelId = channelIndex + 1;
    // Phase is derived exclusively from the shared sample clock.  The source
    // time is m_originTime + sampleIndex / sampleRate, so batching, pausing
    // and UI frame stalls cannot alter a channel's waveform phase.
    const double time = timeAt(sampleIndex);
    const double sampleRate = 1.0 / m_sampleInterval;
    const double nyquist = sampleRate * .5;
    const int type = channelIndex % 8;
    const double requestedFrequency = 70.0 + (channelId % 11) * 43.0 + (channelId / 8) * 17.0;
    // The dual-tone source reserves headroom for its second component.
    const double maxFundamental = nyquist * (type == 3 ? .18 : .35);
    const double frequency = std::min(requestedFrequency, std::max(1.0, maxFundamental));
    const double amplitude = .35 + ((channelId * 3) % 7) * .09;
    const double phase = channelId * .413;
    const double offset = ((channelId * 5) % 7 - 3) * .08;
    const double angle = Tau * frequency * time + phase;
    const double cycle = frequency * time + phase / Tau;
    const double unitCycle = cycle - std::floor(cycle);
    double waveform = 0.0;

    switch (type) {
    case 0: // Square
        waveform = qSin(angle) >= 0.0 ? 1.0 : -1.0;
        break;
    case 1: // Triangle
        waveform = 4.0 / Tau * qAsin(qSin(angle));
        break;
    case 2: // Sawtooth
        waveform = 2.0 * unitCycle - 1.0;
        break;
    case 3: { // Dual-tone sine, with both components safely below Nyquist.
        const double secondFrequency = std::min(frequency * 1.73, nyquist * .42);
        waveform = .68 * qSin(angle) + .32 * qSin(Tau * secondFrequency * time + phase * 1.7);
        break;
    }
    case 4: // Sine with a deliberately visible DC offset.
        waveform = qSin(angle);
        break;
    case 5: { // Sine plus deterministic small noise at the exact sample.
        quint32 hash = quint32(sampleIndex) ^ (quint32(channelId) * 0x9e3779b9U);
        hash ^= hash << 13; hash ^= hash >> 17; hash ^= hash << 5;
        waveform = qSin(angle) + .055 * (double(hash & 0xffffU) / 32767.5 - 1.0);
        break;
    }
    case 6: // Periodic pulse, duty cycle intentionally differs per channel.
        waveform = unitCycle < (.12 + (channelId % 4) * .04) ? 1.0 : -.32;
        break;
    case 7: // Amplitude-modulated sine gives CH8 a distinct slow envelope.
        waveform = (.42 + .58 * qSin(Tau * frequency * .11 * time + phase * .6)) * qSin(angle);
        break;
    }
    const double dcOffset = type == 4 ? offset * 1.8 : offset;
    return float(dcOffset + amplitude * waveform);
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
    // Never represent "before history" as begin - 1: when begin is zero that
    // wraps to UINT64_MAX and can turn a first post-clear paint into an
    // effectively endless raw/envelope loop.
    if (!m_historyCount || time < timeAt(begin)) return begin;
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
            bucket = { value, value, sampleIndex, sampleIndex, group, m_cacheEpoch, false };
        } else {
            if (!std::isfinite(bucket.minimum) || value < bucket.minimum) { bucket.minimum = value; bucket.minIndex = sampleIndex; }
            if (!std::isfinite(bucket.maximum) || value > bucket.maximum) { bucket.maximum = value; bucket.maxIndex = sampleIndex; }
        }
    }
}

void RealtimeDataBackend::markGapLevels(quint64 sampleIndex, int channelIndex)
{
    for (auto &level : m_levels) {
        const quint64 group = sampleIndex / level.groupSize;
        const quint64 slot = group % level.capacity;
        auto &bucket = level.channels[channelIndex][slot];
        if (bucket.epoch != m_cacheEpoch || bucket.group != group) {
            level.groups[slot] = group;
            bucket = { std::numeric_limits<float>::quiet_NaN(), std::numeric_limits<float>::quiet_NaN(), sampleIndex, sampleIndex, group, m_cacheEpoch, true };
        } else {
            bucket.hasGap = true;
        }
    }
}

void RealtimeDataBackend::appendSimulatedSamples(double startTime, double sampleInterval, int count, const QVariantList &enabledChannels)
{
    if (count <= 0 || sampleInterval <= 0.0) return;
    // Single-trigger capture freezes only display history.  The raw source
    // still advances so recording and source-side trigger detection continue.
    const bool retainDisplayHistory = !m_displayHistoryFrozen;
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
    QByteArray recordingPayload;
    bool blockHasGap = false;
    QDataStream recordingStream(&recordingPayload, QIODevice::WriteOnly);
    if (m_recordingBlockPublishing) {
        recordingPayload.reserve(count * int(enabled.size()) * int(sizeof(float)));
        recordingStream.setByteOrder(QDataStream::LittleEndian);
        recordingStream.setFloatingPointPrecision(QDataStream::SinglePrecision);
    }
    for (int offset = 0; offset < count; ++offset) {
        const quint64 index = m_nextSample++;
        const quint64 slot = index % Capacity;
        const double time = startTime + double(offset) * sampleInterval;
        m_activeEvents.erase(std::remove_if(m_activeEvents.begin(), m_activeEvents.end(),
            [index](const SimEvent &event) { return index >= event.start + event.duration; }), m_activeEvents.end());
        scheduleEventIfDue(index, enabled, 1.0 / sampleInterval);
        quint64 validMask = enabledMask;
        for (const int channel : enabled) {
            bool valid = true;
            const float value = applySimulationEvents(index, channel, valueFor(channel, index), &valid);
            if (m_recordingBlockPublishing)
                recordingStream << (valid ? value : std::numeric_limits<float>::quiet_NaN());
            if (valid) {
                if (retainDisplayHistory) {
                    m_raw[channel][slot] = value;
                    updateLevels(index, channel, value);
                }
                const float previous = m_triggerPrevious[channel];
                // This deliberately observes the raw post-simulation sample only;
                // it never consults the event list to create a trigger result.
                if (std::isfinite(previous) && std::fabs(value - previous) >= 0.9f)
                    emit rawTriggerDetected({{"channelId", channel + 1}, {"sampleIndex", qulonglong(index)}, {"previous", previous}, {"value", value}, {"delta", value - previous}});
                m_triggerPrevious[channel] = value;
                evaluateEdgeTrigger(index, channel, value, true);
            } else {
                validMask &= ~(quint64(1) << channel);
                blockHasGap = true;
                if (retainDisplayHistory) markGapLevels(index, channel);
                m_triggerPrevious[channel] = std::numeric_limits<float>::quiet_NaN();
                evaluateEdgeTrigger(index, channel, value, false);
            }
        }
        if (retainDisplayHistory) {
            m_validMasks[slot] = validMask;
            m_historyCount = std::min<quint64>(Capacity, m_historyCount + 1);
        }
    }
    if (m_recordingBlockPublishing && recordingStream.status() == QDataStream::Ok)
        emit rawSampleBlockReady(startTime, recordingPayload, blockHasGap);
    if (retainDisplayHistory) {
        ++m_dataRevision;
        emit historyChanged();
    }
}

void RealtimeDataBackend::configureSimulationEvents(const QString &mode)
{
    const QString normalized = mode == QStringLiteral("automatic") ? mode : QStringLiteral("off");
    if (m_eventMode == normalized)
        return;
    m_eventMode = normalized;
    resetEventSchedule();
}

void RealtimeDataBackend::setRecordingBlockPublishing(bool enabled)
{
    m_recordingBlockPublishing = enabled;
}

void RealtimeDataBackend::configureEdgeTrigger(int channelIndex, const QString &edge, double level, double hysteresis, const QString &mode)
{
    const int boundedChannel = std::clamp(channelIndex, 0, ChannelCount - 1);
    const QString normalizedEdge = (edge == QStringLiteral("falling") || edge == QStringLiteral("both")) ? edge : QStringLiteral("rising");
    const QString normalizedMode = mode == QStringLiteral("off") ? mode
        : (mode == QStringLiteral("normal") || mode == QStringLiteral("single")) ? mode : QStringLiteral("auto");
    const float boundedHysteresis = float(std::clamp(hysteresis, .001, 10.0));
    if (m_edgeTriggerChannel == boundedChannel && m_edgeTriggerEdge == normalizedEdge && m_edgeTriggerMode == normalizedMode
        && qFuzzyCompare(m_edgeTriggerLevel, float(level)) && qFuzzyCompare(m_edgeTriggerHysteresis, boundedHysteresis))
        return;
    m_edgeTriggerChannel = boundedChannel;
    m_edgeTriggerEdge = normalizedEdge;
    m_edgeTriggerMode = normalizedMode;
    m_edgeTriggerLevel = float(level);
    m_edgeTriggerHysteresis = boundedHysteresis;
    rearmEdgeTrigger();
}

void RealtimeDataBackend::rearmEdgeTrigger()
{
    m_edgeTriggerPrevious = std::numeric_limits<float>::quiet_NaN();
    m_edgeTriggerArmed = true;
    m_singleTriggerCaptured = false;
}

void RealtimeDataBackend::setDisplayHistoryFrozen(bool frozen)
{
    if (m_displayHistoryFrozen == frozen) return;
    m_displayHistoryFrozen = frozen;
    if (!frozen) {
        // Resuming begins a clean time/cache generation. This prevents new
        // data from overwriting a frozen circular capture with mismatched
        // timestamps while keeping the frozen range intact until re-arm.
        resetHistoryStorage();
        emit historyChanged();
        emit displaySnapshotChanged();
    }
}

void RealtimeDataBackend::evaluateEdgeTrigger(quint64 sampleIndex, int channelIndex, float value, bool valid)
{
    if (m_edgeTriggerMode == QStringLiteral("off")) return;
    if (channelIndex != m_edgeTriggerChannel) return;
    if (!valid || !std::isfinite(value)) {
        // A gap is a hard discontinuity: never form an edge by comparing the
        // point before it with the first point after it.
        m_edgeTriggerPrevious = std::numeric_limits<float>::quiet_NaN();
        m_edgeTriggerArmed = true;
        return;
    }
    const float halfHysteresis = m_edgeTriggerHysteresis * .5f;
    const float lower = m_edgeTriggerLevel - halfHysteresis;
    const float upper = m_edgeTriggerLevel + halfHysteresis;
    if (m_edgeTriggerEdge == QStringLiteral("rising")) {
        if (value <= lower) m_edgeTriggerArmed = true;
    } else if (m_edgeTriggerEdge == QStringLiteral("falling")) {
        if (value >= upper) m_edgeTriggerArmed = true;
    } else if (value <= lower || value >= upper) {
        m_edgeTriggerArmed = true;
    }
    const float previous = m_edgeTriggerPrevious;
    const bool risingCrossed = previous < upper && value >= upper;
    const bool fallingCrossed = previous > lower && value <= lower;
    const bool crossed = std::isfinite(previous) && m_edgeTriggerArmed
        && (m_edgeTriggerEdge == QStringLiteral("rising") ? risingCrossed : m_edgeTriggerEdge == QStringLiteral("falling") ? fallingCrossed : (risingCrossed || fallingCrossed));
    m_edgeTriggerPrevious = value;
    if (!crossed || (m_edgeTriggerMode == QStringLiteral("single") && m_singleTriggerCaptured)) return;
    m_edgeTriggerArmed = false;
    if (m_edgeTriggerMode == QStringLiteral("single")) m_singleTriggerCaptured = true;
    emit edgeTriggerDetected({{"triggerSampleIndex", qulonglong(sampleIndex)}, {"timeSeconds", timeAt(sampleIndex)}, {"channelId", channelIndex + 1},
        {"edge", m_edgeTriggerEdge}, {"level", m_edgeTriggerLevel}, {"hysteresis", m_edgeTriggerHysteresis}, {"mode", m_edgeTriggerMode}});
}

QVariantList RealtimeDataBackend::simulatedEvents() const { return m_eventHistory; }

quint32 RealtimeDataBackend::nextRandom()
{
    quint32 state = m_eventState ? m_eventState : 12345;
    state ^= state << 13; state ^= state >> 17; state ^= state << 5;
    return m_eventState = state;
}

QString RealtimeDataBackend::eventTypeName(SimEventType type)
{
    switch (type) {
    case SimEventType::Spike: return QStringLiteral("spike");
    case SimEventType::StepRecover: return QStringLiteral("step_recover");
    case SimEventType::Pulse: return QStringLiteral("pulse");
    case SimEventType::Dropout: return QStringLiteral("dropout");
    case SimEventType::NoiseBurst: return QStringLiteral("noise_burst");
    }
    return QStringLiteral("unknown");
}

void RealtimeDataBackend::resetEventSchedule()
{
    // A fresh seed is deliberately chosen for every acquisition generation:
    // this is a stochastic test source, rather than a replay fixture.
    m_eventSeed = QRandomGenerator::global()->generate();
    m_eventState = m_eventSeed ? m_eventSeed : 1;
    m_nextEventSamples.fill(std::numeric_limits<quint64>::max());
    m_nextEventId = 1;
    m_activeEvents.clear();
    m_eventHistory.clear();
    m_triggerPrevious.fill(std::numeric_limits<float>::quiet_NaN());
}

void RealtimeDataBackend::scheduleEventIfDue(quint64 sampleIndex, const std::vector<int> &enabledChannels, double sampleRate)
{
    if (m_eventMode != QStringLiteral("automatic") || enabledChannels.empty()) return;
    const quint64 rate = std::max<quint64>(1, quint64(std::llround(sampleRate)));
    // Every enabled channel owns an independent next-event position.  Thus
    // enabling eight channels does not create eight copies of the same event.
    for (const int channel : enabledChannels) {
        auto &next = m_nextEventSamples[channel];
        if (next == std::numeric_limits<quint64>::max()) {
            next = sampleIndex + rate * (1 + nextRandom() % 5);
            continue;
        }
        if (sampleIndex != next) continue;
        const auto type = static_cast<SimEventType>(nextRandom() % 5);
        quint64 duration = 1;
        switch (type) {
        case SimEventType::Spike: duration = 1; break;
        case SimEventType::StepRecover: duration = rate / 5 + nextRandom() % std::max<quint64>(1, rate / 5); break;
        case SimEventType::Pulse: duration = std::max<quint64>(1, rate / 100 + nextRandom() % std::max<quint64>(1, rate / 25)); break;
        case SimEventType::Dropout: duration = std::max<quint64>(1, rate / 50 + nextRandom() % std::max<quint64>(1, rate / 10)); break;
        case SimEventType::NoiseBurst: duration = std::max<quint64>(1, rate / 20 + nextRandom() % std::max<quint64>(1, rate / 10)); break;
        }
        const float amplitude = .75f + float(nextRandom() % 125) / 100.f;
        const quint64 id = m_nextEventId++;
        const SimEvent event { id, type, channel, sampleIndex, duration, amplitude, m_eventSeed };
        m_activeEvents.push_back(event);
        QVariantMap detail {{"eventId", qulonglong(event.id)}, {"eventType", eventTypeName(event.type)}, {"channelId", event.channel + 1},
            {"startSampleIndex", qulonglong(event.start)}, {"durationSamples", qulonglong(event.duration)}, {"amplitude", event.amplitude}, {"randomSeed", event.seed}};
        m_eventHistory << detail;
        if (m_eventHistory.size() > 256) m_eventHistory.removeFirst();
        emit simulationEventOccurred(detail);
        next = sampleIndex + duration + rate * (1 + nextRandom() % 5);
    }
}

float RealtimeDataBackend::applySimulationEvents(quint64 sampleIndex, int channelIndex, float value, bool *valid) const
{
    for (const SimEvent &event : m_activeEvents) {
        if (event.channel != channelIndex || sampleIndex < event.start || sampleIndex >= event.start + event.duration) continue;
        const quint64 offset = sampleIndex - event.start;
        switch (event.type) {
        case SimEventType::Spike: if (offset == 0) value += event.amplitude; break;
        case SimEventType::StepRecover: value += event.amplitude * (1.f - float(offset) / float(std::max<quint64>(1, event.duration))); break;
        case SimEventType::Pulse: value += event.amplitude; break;
        case SimEventType::Dropout: *valid = false; break;
        case SimEventType::NoiseBurst: {
            quint32 hash = event.seed ^ quint32(sampleIndex) ^ (quint32(channelIndex + 1) * 0x9e3779b9U);
            hash ^= hash << 13; hash ^= hash >> 17; hash ^= hash << 5;
            value += event.amplitude * (float(hash & 0xffffU) / 32767.5f - 1.f);
            break;
        }
        }
    }
    return value;
}

QVariantList RealtimeDataBackend::rawSeries(int channel, quint64 first, quint64 last, double start, double duration, int width) const
{
    QVariantList values;
    if (last < first) return values;
    values.reserve(int(std::min<quint64>((last - first + 1) * 2, 3ull * quint64(width))));
    for (quint64 index = first; index <= last; ++index) {
        const float value = valueAt(channel, index);
        if (!std::isfinite(value)) {
            if (!values.isEmpty() && std::isfinite(values.last().toDouble())) values << std::numeric_limits<double>::quiet_NaN() << std::numeric_limits<double>::quiet_NaN();
            continue;
        }
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
        if (level.groups[slot] != group) {
            if (!values.isEmpty() && std::isfinite(values.last().toDouble())) values << std::numeric_limits<double>::quiet_NaN() << std::numeric_limits<double>::quiet_NaN();
            continue;
        }
        const auto &bucket = level.channels[channel][slot];
        if (bucket.epoch != m_cacheEpoch || bucket.group != group || bucket.hasGap || !std::isfinite(bucket.minimum) || !std::isfinite(bucket.maximum) || !isInHistory(bucket.minIndex) || !isInHistory(bucket.maxIndex)) {
            if (!values.isEmpty() && std::isfinite(values.last().toDouble())) values << std::numeric_limits<double>::quiet_NaN() << std::numeric_limits<double>::quiet_NaN();
            continue;
        }
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
    const bool overlapsHistory = m_historyCount && windowEnd >= historyStartTime() && windowStart <= latestSampleTime();
    const quint64 first = overlapsHistory ? firstSampleIndexAtOrAfter(windowStart) : 0;
    const quint64 last = overlapsHistory ? lastSampleIndexAtOrBefore(windowEnd) : 0;
    // The actual retained range is a safety bound during a rate-generation
    // transition.  Never select the raw path merely because a caller supplied
    // a lower new rate while old high-rate samples are still present.
    const double actualSamplesPerPixel = overlapsHistory && last >= first ? double(last - first + 1) / width : 0.0;
    const double samplesPerPixel = std::max(theoreticalSamplesPerPixel, actualSamplesPerPixel);
    const bool envelope = samplesPerPixel >= 2.0;
    quint64 groupSize = 1;
    if (envelope) while (groupSize < quint64(std::ceil(samplesPerPixel)) && groupSize < m_levels.back().groupSize) groupSize *= 4;

    QVariantList channels;
    channels.reserve(int(requestedChannels.size()));
    for (const int channel : requestedChannels) {
        QVariantMap series;
        series.insert("channelIndex", channel);
        series.insert("points", overlapsHistory ? (envelope ? envelopeSeries(channel, first, last, groupSize, windowStart, duration, width)
                                                      : rawSeries(channel, first, last, windowStart, duration, width)) : QVariantList{});
        channels << series;
    }
    QVariantMap snapshot;
    snapshot.insert("windowStart", windowStart); snapshot.insert("windowEnd", windowEnd);
    snapshot.insert("samplesPerPixel", samplesPerPixel); snapshot.insert("mode", envelope ? "envelope" : "raw");
    snapshot.insert("channels", channels); snapshot.insert("sampleCount", overlapsHistory && last >= first ? double(last - first + 1) : 0.0);
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

QVariantMap RealtimeDataBackend::measureWindow(int channel, double startTime, double endTime,
                                               const QString &thresholdMode, double threshold,
                                               double hysteresis, const QString &edge) const
{
    QVariantMap result{{"valid", false}, {"periodValid", false}, {"reason", QStringLiteral("data-insufficient")}};
    if (channel < 0 || channel >= ChannelCount || m_historyCount == 0 || endTime <= startTime)
        return result;

    const quint64 first = firstSampleIndexAtOrAfter(startTime);
    const quint64 last = lastSampleIndexAtOrBefore(endTime);
    // Do not present partial startup/aged-out windows as a valid measurement.
    if (last < first || first < m_nextSample - m_historyCount || last >= m_nextSample || last - first + 1 < 8)
        return result;

    double sum = 0.0, sumSquares = 0.0;
    float minimum = std::numeric_limits<float>::infinity();
    float maximum = -std::numeric_limits<float>::infinity();
    quint64 count = 0;
    bool hasGap = false;
    for (quint64 index = first; index <= last; ++index) {
        const float value = valueAt(channel, index);
        // NaN marks a simulated/recorded interruption.  A measurement must
        // never silently bridge it into a false edge period.  Amplitude
        // statistics can still use the finite samples on either side.
        if (!std::isfinite(value)) {
            hasGap = true;
            continue;
        }
        minimum = std::min(minimum, value);
        maximum = std::max(maximum, value);
        sum += value;
        sumSquares += double(value) * value;
        ++count;
    }
    if (count < 8) {
        result.insert("reason", hasGap ? QStringLiteral("gap") : QStringLiteral("data-insufficient"));
        return result;
    }

    const double mean = sum / double(count);
    result.insert("valid", true);
    result.insert("maximum", maximum);
    result.insert("minimum", minimum);
    result.insert("peakToPeak", double(maximum) - minimum);
    result.insert("mean", mean);
    result.insert("rms", std::sqrt(sumSquares / double(count)));
    result.insert("hasGap", hasGap);
    result.insert("reason", hasGap ? QStringLiteral("gap") : QStringLiteral("period-unavailable"));

    // Edge period/frequency uses one threshold plus hysteresis.  Low/middle/
    // high thresholds belong to future rise/fall-time measurements and are
    // intentionally not reused here.
    const double span = double(maximum) - minimum;
    if (!std::isfinite(span) || span <= 1e-9) {
        result.insert("reason", QStringLiteral("threshold-not-crossed"));
        return result;
    }
    const bool automatic = thresholdMode != QStringLiteral("manual");
    const double middle = automatic ? (double(minimum) + maximum) * .5 : threshold;
    const double effectiveHysteresis = automatic ? span * 0.05 : std::max(0.0, hysteresis);
    if (!std::isfinite(middle) || !std::isfinite(effectiveHysteresis)
            || middle - effectiveHysteresis * .5 < minimum
            || middle + effectiveHysteresis * .5 > maximum) {
        result.insert("reason", QStringLiteral("invalid-threshold"));
        return result;
    }
    result.insert("threshold", middle);
    result.insert("thresholdHysteresis", effectiveHysteresis);

    // A time measurement is never allowed to bridge a missing-data interval.
    // Amplitude results above remain valid because they use finite samples.
    if (hasGap) {
        result.insert("reason", QStringLiteral("gap"));
        return result;
    }

    // A discontinuity resets the edge detector and the preceding crossing.
    // We may still measure a complete period inside any later continuous
    // segment, but never form a period that crosses a missing-data interval.
    std::vector<double> periods;
    float previous = std::numeric_limits<float>::quiet_NaN();
    bool hasPrevious = false;
    double previousCrossing = std::numeric_limits<double>::quiet_NaN();
    const bool falling = edge == QStringLiteral("falling");
    const double lowerArm = middle - effectiveHysteresis * .5;
    const double upperArm = middle + effectiveHysteresis * .5;
    const double crossingLevel = middle;
    bool armed = false;
    for (quint64 index = first; index <= last; ++index) {
        const float current = valueAt(channel, index);
        if (!std::isfinite(current)) {
            hasPrevious = false;
            armed = false;
            previousCrossing = std::numeric_limits<double>::quiet_NaN();
            continue;
        }
        if (!hasPrevious) {
            previous = current;
            hasPrevious = true;
            armed = falling ? current >= upperArm : current <= lowerArm;
            continue;
        }
        if ((!falling && current <= lowerArm) || (falling && current >= upperArm))
            armed = true;
        const bool crossed = !falling
                ? (armed && previous < crossingLevel && current >= crossingLevel)
                : (armed && previous > crossingLevel && current <= crossingLevel);
        if (crossed) {
            const double span = double(current) - previous;
            const double fraction = std::abs(span) > 1e-12 ? (crossingLevel - previous) / span : 0.0;
            const double crossing = timeAt(index - 1) + std::clamp(fraction, 0.0, 1.0) * m_sampleInterval;
            if (std::isfinite(previousCrossing))
                periods.push_back(crossing - previousCrossing);
            previousCrossing = crossing;
            armed = false;
        }
        previous = current;
    }
    // Three same-direction edges (two adjacent periods) are the minimum
    // required to reject a one-off transition or a mixed edge pair.
    if (periods.size() < 2) {
        result.insert("reason", QStringLiteral("insufficient-edges"));
        return result;
    }

    double periodSum = 0.0;
    for (const double value : periods)
        periodSum += value;
    const double period = periodSum / double(periods.size());
    if (!std::isfinite(period) || period <= 0.0) {
        result.insert("reason", QStringLiteral("period-unavailable"));
        return result;
    }
    double variance = 0.0;
    for (const double value : periods) {
        const double delta = value - period;
        variance += delta * delta;
    }
    const double relativeDeviation = std::sqrt(variance / double(periods.size())) / period;
    if (relativeDeviation > 0.08) {
        result.insert("reason", QStringLiteral("period-inconsistent"));
        return result;
    }
    result.insert("periodValid", true);
    result.insert("period", period);
    result.insert("frequency", 1.0 / period);
    return result;
}

void RealtimeDataBackend::resetHistoryStorage()
{
    m_displayHistoryFrozen = false;
    m_nextSample = 0; m_historyCount = 0; m_originTime = 0.0; m_displaySnapshot.clear(); ++m_dataRevision;
    m_snapshotRevision = std::numeric_limits<quint64>::max();
    ++m_cacheEpoch;
    resetEventSchedule();
    rearmEdgeTrigger();
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
