import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Rectangle {
    id: root
    color: "#132633"; border.color: "#314b5b"
    required property bool activePage
    required property var channelStore
    required property int selectedChannelIndex
    required property bool simulationRunning
    required property string displayMode
    required property bool gridVisible
    required property real timePerDivMs
    required property real latestSampleTime
    required property real historyOffsetSeconds
    required property real samplePeriodSeconds
    signal selectedChannelRequested(int index)
    signal startRequested(); signal stopRequested(); signal verticalFitRequested(); signal resetPositionsRequested(); signal clearHistoryRequested()
    readonly property real visibleTimeSeconds: timePerDivMs * 10 / 1000
    readonly property bool reviewingHistory: historyOffsetSeconds > 1e-9
    readonly property bool usesHistory: reviewingHistory || displayMode === "roll"
    readonly property var activeChannels: channelStore.activeViewChannels()
    readonly property int activeViewCount: Math.max(1, activeChannels.length)
    function formatNumber(value) { return Number(value).toFixed(1).replace(/\.0$/, "") }
    function formatTime(value) { return Math.abs(value) < 1 ? formatNumber(value * 1000) + " ms" : formatNumber(value) + " s" }
    function pointBudget() { const base = Math.max(256, Math.min(2048, Math.round(waveformCanvas.width * 1.2 / activeViewCount))); return activeChannels.length > 6 ? Math.min(base, 512) : base }
    function schedulePaint() { if (activePage && waveformCanvas.width > 0 && waveformCanvas.height > 0) waveformCanvas.requestPaint() }
    function rebuildFrame() { if (displayMode === "update" && !reviewingHistory && waveformCanvas.width > 0) channelStore.buildUpdateFrames(latestSampleTime, visibleTimeSeconds, pointBudget(), activeChannels) }
    onLatestSampleTimeChanged: { rebuildFrame(); schedulePaint() }
    onHistoryOffsetSecondsChanged: { rebuildFrame(); schedulePaint() }
    onTimePerDivMsChanged: { rebuildFrame(); schedulePaint() }
    onDisplayModeChanged: { rebuildFrame(); schedulePaint() }
    onGridVisibleChanged: schedulePaint()
    onSelectedChannelIndexChanged: schedulePaint()
    onActivePageChanged: { if (activePage) { rebuildFrame(); schedulePaint() } }
    Connections { target: root.channelStore; function onSampleRevisionChanged() { root.rebuildFrame(); root.schedulePaint() } function onFrameRevisionChanged() { root.schedulePaint() } function onRevisionChanged() { root.rebuildFrame(); root.schedulePaint() } }
    component ActionButton: Button { id: button; property color fillColor: "#223542"; implicitHeight: 30; contentItem: Text { text: button.text; color: button.enabled ? "#d9e4ec" : "#71818d"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter } background: Rectangle { radius: 4; color: button.enabled ? button.fillColor : "#29333a"; border.color: "#365467" } }
    ColumnLayout {
        anchors.fill: parent; anchors.margins: 14; spacing: 8
        RowLayout { Layout.fillWidth: true; Label { text: qsTr("\u5b9e\u65f6\u6ce2\u5f62") + "  (" + root.activeChannels.length + "/8)"; color: "#d9e4ec"; font.pixelSize: 17; font.bold: true } Item { Layout.fillWidth: true } Label { text: root.simulationRunning ? qsTr("\u91c7\u96c6\u4e2d") : qsTr("\u5df2\u505c\u6b62"); color: root.simulationRunning ? "#35d19b" : "#8fa3b4"; font.bold: true } }
        Flickable { Layout.fillWidth: true; Layout.preferredHeight: 28; contentWidth: legendRow.width; contentHeight: height; clip: true; interactive: contentWidth > width; boundsBehavior: Flickable.StopAtBounds
            Row { id: legendRow; width: implicitWidth; height: parent.height; spacing: 6
                Repeater { model: root.activeChannels; delegate: Button { id: legend; required property int index; readonly property int channelIndex: root.activeChannels[index]; readonly property var info: root.channelStore.channel(channelIndex); text: info.name + "  " + root.formatNumber(info.voltsPerDiv) + " V/div"; implicitHeight: 26; contentItem: Text { text: legend.text; color: legend.info.color; font.pixelSize: 12; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter } background: Rectangle { radius: 3; color: "#172e39"; border.color: root.selectedChannelIndex === legend.channelIndex ? legend.info.color : "#365467" } onClicked: root.selectedChannelRequested(channelIndex) } }
            }
            ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
        }
        Rectangle { Layout.fillWidth: true; Layout.fillHeight: true; color: "#10242f"; border.color: "#365467"; clip: true
            Canvas {
                id: waveformCanvas; anchors.fill: parent; anchors.margins: 1
                onWidthChanged: { root.rebuildFrame(); root.schedulePaint() }
                onPaint: {
                    const context = getContext("2d"), width = waveformCanvas.width, height = waveformCanvas.height
                    if (width <= 0 || height <= 0) return
                    context.clearRect(0, 0, width, height); context.fillStyle = "#10242f"; context.fillRect(0, 0, width, height)
                    if (!root.activeChannels.length) return
                    const viewHeight = height / root.activeChannels.length, divWidth = width / 10
                    const end = root.latestSampleTime - root.historyOffsetSeconds, start = end - root.visibleTimeSeconds
                    const first = Math.max(0, Math.ceil((start - root.channelStore.historyStartTime) / root.samplePeriodSeconds))
                    const last = Math.min(root.channelStore.historyCount - 1, Math.floor((end - root.channelStore.historyStartTime) / root.samplePeriodSeconds))
                    for (let viewIndex = 0; viewIndex < root.activeChannels.length; ++viewIndex) {
                        const channelIndex = root.activeChannels[viewIndex], data = root.channelStore.channel(channelIndex), top = viewIndex * viewHeight, divisionHeight = viewHeight / 4, frame = root.channelStore.updateFrame(channelIndex)
                        context.fillStyle = viewIndex % 2 ? "#112833" : "#10242f"; context.fillRect(0, top, width, viewHeight)
                        if (root.gridVisible) { context.strokeStyle = "#1e4350"; context.lineWidth = 1; for (let x = 0; x <= 10; ++x) { context.beginPath(); context.moveTo(x * divWidth, top); context.lineTo(x * divWidth, top + viewHeight); context.stroke() } for (let y = 0; y <= 4; ++y) { context.beginPath(); context.moveTo(0, top + y * divisionHeight); context.lineTo(width, top + y * divisionHeight); context.stroke() } }
                        context.strokeStyle = "#4a8290"; context.setLineDash([3, 3]); context.beginPath(); context.moveTo(0, top + viewHeight / 2); context.lineTo(width, top + viewHeight / 2); context.stroke(); context.setLineDash([])
                        context.strokeStyle = data.color; context.lineWidth = 1.6; context.beginPath(); let drew = false
                        function point(value, x) { const y = top + viewHeight / 2 - (value + data.verticalOffsetV) * (divisionHeight / data.voltsPerDiv); if (!drew) { context.moveTo(x, y); drew = true } else context.lineTo(x, y) }
                        if (!root.usesHistory) { for (let p = 0; p < frame.length; ++p) point(frame[p], frame.length > 1 ? p / (frame.length - 1) * width : 0) }
                        else { const step = Math.max(1, Math.ceil(Math.max(0, last - first + 1) / root.pointBudget())); for (let logical = first; logical <= last; logical += step) { const bufferIndex = (root.channelStore.historyStartIndex + logical) % root.channelStore.historyCapacity, value = root.channelStore.historyValue(channelIndex, bufferIndex); if (value !== undefined) point(value, (root.channelStore.historyTimes[bufferIndex] - start) / root.visibleTimeSeconds * width) } }
                        if (drew) context.stroke()
                        const current = frame.length ? frame[frame.length - 1] : 0; context.fillStyle = data.color; context.font = "12px sans-serif"; context.fillText(data.name + "  " + root.formatNumber(current) + " V  " + root.formatNumber(data.voltsPerDiv) + " V/div", 8, top + 15)
                        context.strokeStyle = "#365467"; context.beginPath(); context.moveTo(0, top + viewHeight); context.lineTo(width, top + viewHeight); context.stroke()
                    }
                }
            }
            Label { anchors.centerIn: parent; visible: root.activeChannels.length === 0; text: qsTr("\u8bf7\u5728\u901a\u9053\u8bbe\u7f6e\u4e2d\u542f\u7528\u901a\u9053"); color: "#7790a0"; font.pixelSize: 16 }
            Label { anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 10; text: root.formatTime(-root.historyOffsetSeconds - root.visibleTimeSeconds); color: "#8fa3b4"; font.pixelSize: 12 }
            Label { anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.margins: 10; text: root.formatNumber(root.timePerDivMs) + " ms/div"; color: "#8fa3b4"; font.pixelSize: 12 }
            Label { anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 10; text: root.formatTime(-root.historyOffsetSeconds); color: "#8fa3b4"; font.pixelSize: 12 }
        }
        RowLayout { Layout.fillWidth: true; spacing: 8; ActionButton { text: qsTr("\u5f00\u59cb\u6a21\u62df"); enabled: !root.simulationRunning; fillColor: "#168b7c"; onClicked: root.startRequested() } ActionButton { text: qsTr("\u505c\u6b62\u6a21\u62df"); enabled: root.simulationRunning; fillColor: "#a1514d"; onClicked: root.stopRequested() } ActionButton { text: qsTr("\u5782\u76f4\u9002\u914d"); onClicked: root.verticalFitRequested() } ActionButton { text: qsTr("\u4f4d\u7f6e\u590d\u4f4d"); onClicked: root.resetPositionsRequested() } Item { Layout.fillWidth: true } ActionButton { text: qsTr("\u6e05\u9664\u5386\u53f2"); fillColor: "#493b3a"; onClicked: root.clearHistoryRequested() } }
    }
}
