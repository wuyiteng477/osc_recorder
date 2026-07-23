import QtQuick

QtObject {
    id: store

    property int boardCount: 8
    property int channelsPerBoard: 8
    readonly property int channelCount: boardCount * channelsPerBoard
    property int maximumVisibleWaveforms: 8
    property int revision: 0
    property int selectedChannelIndex: 0
    readonly property int visibleChannelCount: visibleCount()
    readonly property var channelColors: ["#39e6bb", "#f2d05c", "#72d18c", "#c58bea", "#f0a35e", "#63b3ed", "#ef7aa8", "#a6d96a"]
    property var channelModel: ListModel { id: channelModel }

    Component.onCompleted: initializeChannels()

    function initializeChannels() {
        if (channelModel.count)
            return

        for (let board = 0; board < boardCount; ++board) {
            for (let local = 0; local < channelsPerBoard; ++local) {
                const channelId = board * channelsPerBoard + local + 1
                const defaultActive = channelId === 1

                channelModel.append({
                    channelId: channelId,
                    boardIndex: board,
                    channelIndex: local,
                    name: "CH" + channelId,
                    enabled: defaultActive,
                    visible: defaultActive,
                    selected: channelId === 1,
                    color: channelColors[local],
                    voltsPerDiv: 1.0,
                    verticalOffsetV: 0.0,
                    defaultOffsetV: 0.0,
                    signalFrequencyHz: 125 + (channelId % 16) * 47,
                    signalAmplitudeV: .55 + (channelId % 5) * .12,
                    signalPhase: channelId * .37,
                    engineeringUnit: "V",
                    connectionStatus: "Simulation"
                })
            }
        }

        ++revision
    }

    function channel(index) {
        return channelModel.get(index)
    }

    function activeViewChannels() {
        const channels = []
        // Display selection is independent from acquisition.  A visible but
        // non-acquiring channel still owns an empty real-time grid/view.
        for (let index = 0; index < channelModel.count && channels.length < maximumVisibleWaveforms; ++index) {
            if (channel(index).visible)
                channels.push(index)
        }

        return channels
    }

    function selectChannel(index) {
        if (index < 0 || index >= channelModel.count || index === selectedChannelIndex)
            return

        channelModel.setProperty(selectedChannelIndex, "selected", false)
        channelModel.setProperty(index, "selected", true)
        selectedChannelIndex = index
        ++revision
    }

    function visibleCount() {
        let count = 0

        for (let i = 0; i < channelModel.count; ++i) {
            if (channel(i).visible)
                ++count
        }

        return count
    }

    function enabledCount() {
        let count = 0

        for (let i = 0; i < channelModel.count; ++i) {
            if (channel(i).enabled)
                ++count
        }

        return count
    }

    function setRole(index, role, value) {
        if (channel(index)[role] !== value) {
            channelModel.setProperty(index, role, value)
            ++revision
            return true
        }

        return false
    }

}
