import QtQuick

QtObject {
    id: store

    property int boardCount: 8
    property int channelsPerBoard: 8
    readonly property int channelCount: boardCount * channelsPerBoard
    // Shared timestamps plus 64 ring buffers: 100,000 samples/channel is the hard upper bound.
    property int historyCapacity: 100000
    property var historyTimes: []
    property var channelBuffers: []
    property var updateFrames: []
    property int historyStartIndex: 0
    property int historyCount: 0
    property int revision: 0
    property int sampleRevision: 0
    property int frameRevision: 0
    property int selectedChannelIndex: 0
    readonly property int visibleChannelCount: visibleCount()
    readonly property bool hasData: historyCount > 0
    readonly property real historyStartTime: historyCount > 0 ? historyTimes[historyStartIndex] : 0
    readonly property var channelColors: ["#39e6bb", "#f2d05c", "#72d18c", "#c58bea", "#f0a35e", "#63b3ed", "#ef7aa8", "#a6d96a"]

    property var channelModel: ListModel { id: channelModel }

    Component.onCompleted: initializeChannels()

    function initializeChannels() {
        if (channelModel.count > 0) return
        for (let board = 0; board < boardCount; ++board) {
            for (let local = 0; local < channelsPerBoard; ++local) {
                const channelId = board * channelsPerBoard + local + 1
                const activeByDefault = channelId <= 4
                channelModel.append({
                    channelId: channelId,
                    boardIndex: board,
                    channelIndex: local,
                    name: "CH" + channelId,
                    enabled: activeByDefault,
                    visible: activeByDefault,
                    selected: channelId === 1,
                    color: channelColors[local % channelColors.length],
                    voltsPerDiv: 1.0,
                    verticalOffsetV: (3.5 - local) * .35,
                    defaultOffsetV: (3.5 - local) * .35,
                    signalFrequencyHz: 125 + (channelId % 16) * 47,
                    signalAmplitudeV: .55 + (channelId % 5) * .12,
                    signalPhase: channelId * .37,
                    connectionStatus: "Simulation"
                })
            }
        }
        ++revision
    }

    function channel(index) { return channelModel.get(index) }
    function historyValue(channelIndex, bufferIndex) { return channelBuffers[channelIndex] ? channelBuffers[channelIndex][bufferIndex] : undefined }
    function updateFrame(channelIndex) { return updateFrames[channelIndex] || [] }
    function visibleCount() { let count = 0; for (let i = 0; i < channelModel.count; ++i) if (channel(i).visible) ++count; return count }
    function setRole(index, role, value) { if (channel(index)[role] !== value) { channelModel.setProperty(index, role, value); ++revision; return true } return false }
    function selectChannel(index) {
        if (index < 0 || index >= channelModel.count || index === selectedChannelIndex) return
        channelModel.setProperty(selectedChannelIndex, "selected", false)
        channelModel.setProperty(index, "selected", true)
        selectedChannelIndex = index
        ++revision
    }
    function initializeHistory() {
        if (historyTimes.length !== historyCapacity) historyTimes = new Array(historyCapacity)
        if (channelBuffers.length !== channelCount) {
            const buffers = []
            for (let i = 0; i < channelCount; ++i) buffers.push(new Array(historyCapacity))
            channelBuffers = buffers
        }
    }
    function valueFor(data, time) {
        const carrier = Math.sin(2 * Math.PI * data.signalFrequencyHz * time + data.signalPhase)
        const harmonic = .08 * Math.sin(2 * Math.PI * data.signalFrequencyHz * 3 * time + data.signalPhase + .4)
        const amplitude = 1 + .12 * Math.sin(2 * Math.PI * (.06 + data.channelId * .01) * time + data.signalPhase)
        const baseline = .07 * Math.sin(2 * Math.PI * (.035 + data.channelId * .008) * time)
        const noise = .012 * Math.sin((190 + data.channelId * 31) * time) + .006 * Math.sin((430 + data.channelId * 41) * time)
        const period = 4.1 + data.channelId * .035
        const eventPhase = ((time + data.channelId * .37) % period + period) % period
        const event = eventPhase < .20 ? -.25 * Math.sin(Math.PI * eventPhase / .20) : 0
        return data.signalAmplitudeV * (amplitude * (carrier + harmonic) + baseline + noise + event)
    }
    // One shared batch writes all enabled channels to the same timestamp ring.
    function appendSamples(startTime, interval, count) {
        initializeHistory()
        for (let sample = 0; sample < count; ++sample) {
            const time = startTime + sample * interval
            const writeIndex = (historyStartIndex + historyCount) % historyCapacity
            historyTimes[writeIndex] = time
            for (let index = 0; index < channelModel.count; ++index) {
                const data = channel(index)
                if (data.enabled) channelBuffers[index][writeIndex] = valueFor(data, time)
            }
            if (historyCount < historyCapacity) ++historyCount
            else historyStartIndex = (historyStartIndex + 1) % historyCapacity
        }
        ++sampleRevision
        ++revision
    }
    // Only visible, enabled channels receive a new display frame; others retain their last frame.
    function buildUpdateFrames(latestTime, visibleSeconds, pointCount) {
        const actualStart = latestTime - visibleSeconds
        const frames = updateFrames.slice()
        for (let index = 0; index < channelModel.count; ++index) {
            const data = channel(index)
            if (!data.enabled || !data.visible) continue
            const frame = new Array(pointCount)
            for (let i = 0; i < pointCount; ++i) {
                const relative = pointCount > 1 ? i / (pointCount - 1) * visibleSeconds : 0
                frame[i] = valueFor(data, actualStart + relative)
            }
            frames[index] = frame
        }
        updateFrames = frames
        ++frameRevision
        ++revision
    }
    function clearHistory() { historyStartIndex = 0; historyCount = 0; historyTimes = []; channelBuffers = []; updateFrames = []; ++sampleRevision; ++revision }
}
