import QtQuick

QtObject {
    id: store
    property int boardCount: 8
    property int channelsPerBoard: 8
    readonly property int channelCount: boardCount * channelsPerBoard
    property int historyCapacity: 100000
    property int maximumVisibleWaveforms: 8
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
        if (channelModel.count) return
        for (let board = 0; board < boardCount; ++board) for (let local = 0; local < channelsPerBoard; ++local) {
            const channelId = board * channelsPerBoard + local + 1
            const defaultActive = channelId === 1
            channelModel.append({ channelId: channelId, boardIndex: board, channelIndex: local,
                name: "CH" + channelId, enabled: defaultActive, visible: defaultActive, selected: channelId === 1,
                color: channelColors[local], voltsPerDiv: 1.0, verticalOffsetV: 0.0, defaultOffsetV: 0.0,
                signalFrequencyHz: 125 + (channelId % 16) * 47, signalAmplitudeV: .55 + (channelId % 5) * .12,
                signalPhase: channelId * .37, connectionStatus: "Simulation" })
        }
        ++revision
    }
    function channel(index) { return channelModel.get(index) }
    function activeViewChannels() {
        const channels = []
        for (let index = 0; index < channelModel.count && channels.length < 8; ++index) if (channel(index).enabled) channels.push(index)
        return channels
    }
    function selectChannel(index) { if (index < 0 || index >= channelModel.count || index === selectedChannelIndex) return; channelModel.setProperty(selectedChannelIndex, "selected", false); channelModel.setProperty(index, "selected", true); selectedChannelIndex = index; ++revision }
    function historyValue(channelIndex, bufferIndex) { return channelBuffers[channelIndex] ? channelBuffers[channelIndex][bufferIndex] : undefined }
    function updateFrame(channelIndex) { return updateFrames[channelIndex] || [] }
    function visibleCount() { let count = 0; for (let i = 0; i < channelModel.count; ++i) if (channel(i).visible) ++count; return count }
    function enabledCount() { let count = 0; for (let i = 0; i < channelModel.count; ++i) if (channel(i).enabled) ++count; return count }
    function setRole(index, role, value) { if (channel(index)[role] !== value) { channelModel.setProperty(index, role, value); ++revision; return true } return false }
    function initializeHistory() { if (historyTimes.length !== historyCapacity) historyTimes = new Array(historyCapacity); if (channelBuffers.length !== channelCount) { const buffers = []; for (let i = 0; i < channelCount; ++i) buffers.push(new Array(historyCapacity)); channelBuffers = buffers } }
    function valueFor(data, time) {
        const carrier = Math.sin(2 * Math.PI * data.signalFrequencyHz * time + data.signalPhase)
        const harmonic = .08 * Math.sin(2 * Math.PI * data.signalFrequencyHz * 3 * time + data.signalPhase + .4)
        const modulation = 1 + .12 * Math.sin(2 * Math.PI * (.06 + data.channelId * .01) * time + data.signalPhase)
        const noise = .012 * Math.sin((190 + data.channelId * 31) * time) + .006 * Math.sin((430 + data.channelId * 41) * time)
        return data.signalAmplitudeV * (modulation * (carrier + harmonic) + noise)
    }
    function appendSamples(startTime, interval, count) {
        initializeHistory()
        for (let sample = 0; sample < count; ++sample) { const time = startTime + sample * interval, writeIndex = (historyStartIndex + historyCount) % historyCapacity; historyTimes[writeIndex] = time
            for (let index = 0; index < channelModel.count; ++index) { const data = channel(index); if (data.enabled) channelBuffers[index][writeIndex] = valueFor(data, time) }
            if (historyCount < historyCapacity) ++historyCount; else historyStartIndex = (historyStartIndex + 1) % historyCapacity }
        ++sampleRevision; ++revision
    }
    function buildUpdateFrames(latestTime, visibleSeconds, pointCount, channelIndices) {
        const frames = updateFrames.slice(), actualStart = latestTime - visibleSeconds, limit = Math.min(channelIndices.length, maximumVisibleWaveforms)
        for (let item = 0; item < limit; ++item) { const index = channelIndices[item], data = channel(index); if (!data.enabled) continue; const frame = new Array(pointCount)
            for (let point = 0; point < pointCount; ++point) { const relative = pointCount > 1 ? point / (pointCount - 1) * visibleSeconds : 0; frame[point] = valueFor(data, actualStart + relative) }
            frames[index] = frame }
        updateFrames = frames; ++frameRevision
    }
    function clearHistory() { historyStartIndex = 0; historyCount = 0; historyTimes = []; channelBuffers = []; updateFrames = []; ++sampleRevision; ++revision }
}
