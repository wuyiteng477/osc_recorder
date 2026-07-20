import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Rectangle {
    id: root
    required property bool activePage
    required property bool simulationRunning
    required property bool hasSimulationData
    required property bool channelEnabled
    required property string displayMode
    required property bool gridVisible
    required property real voltsPerDiv
    required property real timePerDivMs
    required property real verticalOffsetV
    required property var historyTimes
    required property var historyValues
    required property int historyStartIndex
    required property int historyCount
    required property int historyCapacity
    required property real samplePeriodSeconds
    required property real latestSampleTime
    required property real historyOffsetSeconds
    required property int historyRevision
    required property var updateFrameSamples
    required property int updateFrameRevision
    signal updateFrameRequested(real visibleSeconds, int pointCount)
    signal startRequested()
    signal stopRequested()
    signal verticalFitRequested()
    signal resetPositionsRequested()
    signal clearHistoryRequested()
    color: "#101922"

    readonly property real visibleTimeSeconds: timePerDivMs * 10 / 1000
    readonly property bool reviewingHistory: historyOffsetSeconds > 0.000001
    readonly property bool usesHistoryWindow: reviewingHistory || displayMode === "roll"
    readonly property real historyStartTime: historyCount > 0 ? historyTimes[historyStartIndex] : 0
    readonly property bool historyDataAccumulating: usesHistoryWindow && hasSimulationData && latestSampleTime - historyStartTime + 0.000001 < visibleTimeSeconds
    readonly property bool historySamplesSparse: usesHistoryWindow && hasSimulationData && !historyDataAccumulating && visibleHistorySampleCount < 20
    readonly property int visibleHistorySampleCount: hasSimulationData ? Math.max(0, Math.min(historyCount - 1, Math.floor((latestSampleTime - historyOffsetSeconds - historyStartTime) / samplePeriodSeconds)) - Math.max(0, Math.ceil((latestSampleTime - historyOffsetSeconds - visibleTimeSeconds - historyStartTime) / samplePeriodSeconds)) + 1) : 0
    function formatNumber(value) { return Number(value).toFixed(1).replace(/\.0$/, "") }
    function formatTime(seconds) { return Math.abs(seconds) < 1 ? formatNumber(seconds * 1000) + " ms" : formatNumber(seconds) + " s" }
    function historyIndex(logicalIndex) { return (historyStartIndex + logicalIndex) % historyCapacity }
    function requestUpdateFrame() {
        if (!activePage || waveformCanvas.width <= 0 || displayMode !== "update" || reviewingHistory) return
        const pointCount = Math.max(1024, Math.min(4096, Math.round(waveformCanvas.width * 2)))
        root.updateFrameRequested(visibleTimeSeconds, pointCount)
    }
    function schedulePaint() { if (activePage && !paintTimer.running) paintTimer.start() }
    component ActionButton: Button {
        id: control
        property color fillColor: "#223542"
        implicitHeight: 32
        contentItem: Text { text: control.text; color: control.enabled ? "#d9e4ec" : "#71818d"; font.pixelSize: 13; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
        background: Rectangle { radius: 4; color: control.enabled ? control.fillColor : "#29333a" }
    }
    onHistoryRevisionChanged: { if (displayMode === "update" && !reviewingHistory) requestUpdateFrame(); schedulePaint() }
    onUpdateFrameRevisionChanged: schedulePaint()
    onVoltsPerDivChanged: schedulePaint()
    onTimePerDivMsChanged: { requestUpdateFrame(); schedulePaint() }
    onVerticalOffsetVChanged: schedulePaint()
    onChannelEnabledChanged: schedulePaint()
    onHistoryOffsetSecondsChanged: { if (!reviewingHistory) requestUpdateFrame(); schedulePaint() }
    onDisplayModeChanged: { requestUpdateFrame(); schedulePaint() }
    onGridVisibleChanged: schedulePaint()
    onActivePageChanged: { if (activePage) { requestUpdateFrame(); schedulePaint() } }
    Timer { id: paintTimer; interval: 33; repeat: false; onTriggered: waveformCanvas.requestPaint() }

    ColumnLayout {
        anchors.fill: parent; anchors.margins: 16; spacing: 10
        RowLayout {
            Layout.fillWidth: true
            Label { text: "CH1 " + qsTr("实时波形"); color: "#d9e4ec"; font.pixelSize: 17; font.bold: true }
            Item { Layout.fillWidth: true }
            Label { text: root.reviewingHistory ? qsTr("历史回看：距最新 ") + root.formatTime(root.historyOffsetSeconds) : (root.simulationRunning ? qsTr("模拟采集中 · ") + (root.displayMode === "update" ? qsTr("更新模式") : qsTr("滚动模式")) : qsTr("模拟采集已停止")); color: root.reviewingHistory ? "#e8a94b" : "#35d19b"; font.pixelSize: 13 }
        }
        Rectangle {
            Layout.fillWidth: true; Layout.fillHeight: true; color: "#071018"; border.color: "#2a4253"; clip: true
            Canvas {
                id: waveformCanvas
                anchors.fill: parent; anchors.margins: 1
                onWidthChanged: { root.requestUpdateFrame(); root.schedulePaint() }
                onHeightChanged: root.schedulePaint()
                onPaint: {
                    const context = getContext("2d"), w = width, h = height
                    if (w <= 0 || h <= 0) return
                    context.clearRect(0, 0, w, h)
                    context.fillStyle = "#071018"; context.fillRect(0, 0, w, h)
                    const divW = w / 10, divH = h / 8
                    if (root.gridVisible) {
                        context.strokeStyle = "#193141"; context.lineWidth = 1
                        for (let c = 0; c <= 10; ++c) { context.beginPath(); context.moveTo(c * divW, 0); context.lineTo(c * divW, h); context.stroke() }
                        for (let r = 0; r <= 8; ++r) { context.beginPath(); context.moveTo(0, r * divH); context.lineTo(w, r * divH); context.stroke() }
                    }
                    context.strokeStyle = "#24495b"; context.setLineDash([3, 4]); context.beginPath(); context.moveTo(0, h / 2); context.lineTo(w, h / 2); context.stroke(); context.setLineDash([])
                    if (!root.hasSimulationData || !root.channelEnabled) return
                    const pixelsPerVolt = divH / root.voltsPerDiv
                    context.strokeStyle = "#39e6bb"; context.lineWidth = 2; context.beginPath()
                    let drew = false
                    if (!root.usesHistoryWindow) {
                        const frame = root.updateFrameSamples
                        for (let i = 0; i < frame.length; ++i) {
                            const x = frame.length > 1 ? i / (frame.length - 1) * w : 0
                            const y = h / 2 - (frame[i] + root.verticalOffsetV) * pixelsPerVolt
                            if (!drew) { context.moveTo(x, y); drew = true } else context.lineTo(x, y)
                        }
                    } else {
                        const endTime = root.latestSampleTime - root.historyOffsetSeconds
                        const startTime = endTime - root.visibleTimeSeconds
                        const firstLogical = Math.max(0, Math.ceil((startTime - root.historyStartTime) / root.samplePeriodSeconds))
                        const lastLogical = Math.min(root.historyCount - 1, Math.floor((endTime - root.historyStartTime) / root.samplePeriodSeconds))
                        const visibleCount = Math.max(0, lastLogical - firstLogical + 1)
                        const maxDrawPoints = Math.max(1024, Math.min(4096, Math.round(w * 2)))
                        function drawLogical(logical) {
                            const index = root.historyIndex(logical)
                            const time = root.historyTimes[index]
                            const x = (time - startTime) / root.visibleTimeSeconds * w
                            const y = h / 2 - (root.historyValues[index] + root.verticalOffsetV) * pixelsPerVolt
                            if (!drew) { context.moveTo(x, y); drew = true } else context.lineTo(x, y)
                        }
                        if (visibleCount <= maxDrawPoints) {
                            for (let logical = firstLogical; logical <= lastLogical; ++logical) drawLogical(logical)
                        } else {
                            const bucketCount = Math.max(1, Math.floor(maxDrawPoints / 4))
                            const bucketWidth = visibleCount / bucketCount
                            for (let bucket = 0; bucket < bucketCount; ++bucket) {
                                const bucketFirst = firstLogical + Math.floor(bucket * bucketWidth)
                                const bucketLast = Math.min(lastLogical, firstLogical + Math.floor((bucket + 1) * bucketWidth) - 1)
                                let minLogical = bucketFirst, maxLogical = bucketFirst
                                let minValue = root.historyValues[root.historyIndex(bucketFirst)]
                                let maxValue = minValue
                                for (let logical = bucketFirst + 1; logical <= bucketLast; ++logical) {
                                    const value = root.historyValues[root.historyIndex(logical)]
                                    if (value < minValue) { minValue = value; minLogical = logical }
                                    if (value > maxValue) { maxValue = value; maxLogical = logical }
                                }
                                const candidates = [bucketFirst, minLogical, maxLogical, bucketLast]
                                candidates.sort((a, b) => a - b)
                                let previous = -1
                                for (let i = 0; i < candidates.length; ++i) if (candidates[i] !== previous) { drawLogical(candidates[i]); previous = candidates[i] }
                            }
                        }
                    }
                    if (drew) context.stroke()
                }
            }
            Label { anchors.centerIn: parent; visible: !root.hasSimulationData; text: qsTr("等待采集数据"); color: "#7790a0"; font.pixelSize: 20 }
            Label { anchors.centerIn: parent; visible: root.historyDataAccumulating; text: qsTr("历史数据积累中"); color: "#e8a94b"; font.pixelSize: 16 }
            Label { anchors.horizontalCenter: parent.horizontalCenter; anchors.top: parent.top; anchors.topMargin: 36; visible: root.historySamplesSparse; text: qsTr("当前历史采样点较少"); color: "#e8a94b"; font.pixelSize: 13 }
            Label { anchors.centerIn: parent; visible: root.hasSimulationData && !root.channelEnabled; text: qsTr("CH1 已关闭"); color: "#7790a0"; font.pixelSize: 18 }
            Label { anchors.left: parent.left; anchors.top: parent.top; anchors.margins: 12; text: root.formatNumber(root.voltsPerDiv) + " V/div     " + root.formatNumber(root.timePerDivMs) + " ms/div"; color: "#8fa3b4"; font.pixelSize: 12 }
            Label { anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 12; text: root.formatTime(-root.historyOffsetSeconds - root.visibleTimeSeconds); color: "#8fa3b4"; font.pixelSize: 12 }
            Label { anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 12; text: root.formatTime(-root.historyOffsetSeconds); color: "#8fa3b4"; font.pixelSize: 12 }
        }
        RowLayout {
            Layout.fillWidth: true; spacing: 8
            ActionButton { text: qsTr("开始模拟"); enabled: !root.simulationRunning; fillColor: "#168b7c"; Layout.preferredWidth: 94; onClicked: root.startRequested() }
            ActionButton { text: qsTr("停止模拟"); enabled: root.simulationRunning; fillColor: "#a1514d"; Layout.preferredWidth: 94; onClicked: root.stopRequested() }
            ActionButton { text: qsTr("垂直适配"); fillColor: "#285b73"; Layout.preferredWidth: 84; onClicked: root.verticalFitRequested() }
            ActionButton { text: qsTr("位置复位"); fillColor: "#354452"; Layout.preferredWidth: 84; onClicked: root.resetPositionsRequested() }
            Item { Layout.fillWidth: true }
            ActionButton { text: qsTr("清除历史"); fillColor: "#493b3a"; Layout.preferredWidth: 84; onClicked: root.clearHistoryRequested() }
        }
    }
}
