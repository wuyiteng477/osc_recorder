pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Rectangle {
    id: root
    color: "#132633"
    border.color: "#314b5b"

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
    property bool waveformLabelsVisible: true
    signal selectedChannelRequested(int index)
    signal startRequested(); signal stopRequested(); signal verticalFitRequested(); signal resetPositionsRequested(); signal clearHistoryRequested()
    readonly property real visibleTimeSeconds: timePerDivMs * 10 / 1000
    readonly property bool reviewingHistory: historyOffsetSeconds > 1e-9
    readonly property bool usesHistory: reviewingHistory || displayMode === "roll"
    readonly property var activeChannels: channelStore.activeViewChannels()
    readonly property int activeViewCount: Math.max(1, activeChannels.length)

    function formatNumber(value) { return Number(value).toFixed(1).replace(/\.0$/, "") }
    function formatTime(value) { return Math.abs(value) < 1 ? formatNumber(value * 1000) + " ms" : formatNumber(value) + " s" }
    function schedulePaint() { if (activePage && waveformCanvas.width > 0 && waveformCanvas.height > 0) waveformCanvas.requestPaint() }

    onLatestSampleTimeChanged: schedulePaint()
    onHistoryOffsetSecondsChanged: schedulePaint()
    onTimePerDivMsChanged: schedulePaint()
    onDisplayModeChanged: schedulePaint()
    onGridVisibleChanged: schedulePaint()
    onSelectedChannelIndexChanged: schedulePaint()
    onActivePageChanged: { if (activePage) schedulePaint() }

    Connections {
        target: root.channelStore

        function onSampleRevisionChanged() { root.schedulePaint() }
        function onFrameRevisionChanged() { root.schedulePaint() }
        function onRevisionChanged() { root.schedulePaint() }
    }

    component ActionButton: AppButton { implicitHeight: 30 }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 8

        RowLayout {
            Layout.fillWidth: true

            Label {
                text: qsTr("\u5b9e\u65f6\u6ce2\u5f62") + "  (" + root.activeChannels.length + "/8)"
                color: "#d9e4ec"
                font.pixelSize: 17
                font.bold: true
            }

            Item {
                Layout.fillWidth: true
            }

            Label {
                text: root.simulationRunning ? qsTr("\u91c7\u96c6\u4e2d") : qsTr("\u5df2\u505c\u6b62")
                color: root.simulationRunning ? "#35d19b" : "#8fa3b4"
                font.bold: true
            }
        }

        Flickable {
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            contentWidth: legendRow.width
            contentHeight: height
            clip: true
            interactive: contentWidth > width
            boundsBehavior: Flickable.StopAtBounds

            Row {
                id: legendRow
                width: implicitWidth
                height: parent.height
                spacing: 6

                Repeater {
                    model: root.activeChannels

                    delegate: AppButton {
                        id: legend
                        required property int index
                        readonly property int channelIndex: root.activeChannels[index]
                        readonly property var info: root.channelStore.channel(channelIndex)
                        text: info.name + "  " + root.formatNumber(info.voltsPerDiv) + " V/div"
                        implicitHeight: 26
                        selected: root.selectedChannelIndex === legend.channelIndex
                        fillColor: "#172e39"
                        selectedFillColor: "#17313a"
                        borderColor: "#365467"
                        selectedBorderColor: legend.info.color
                        textColor: legend.info.color
                        selectedTextColor: legend.info.color

                        onClicked: root.selectedChannelRequested(channelIndex)
                    }
                }
            }

            ScrollBar.horizontal: ScrollBar {
                policy: ScrollBar.AsNeeded
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "#10242f"
            border.color: "#365467"
            clip: true

            Canvas {
                id: waveformCanvas; anchors.fill: parent; anchors.margins: 1
                onWidthChanged: root.schedulePaint()
                onPaint: {
                    const context = getContext("2d"), width = waveformCanvas.width, height = waveformCanvas.height
                    if (width <= 0 || height <= 0)
                        return

                    context.clearRect(0, 0, width, height)
                    context.fillStyle = "#10242f"
                    context.fillRect(0, 0, width, height)

                    if (!root.activeChannels.length)
                        return

                    const viewHeight = height / root.activeChannels.length, divWidth = width / 10
                    const end = root.latestSampleTime - root.historyOffsetSeconds, start = end - root.visibleTimeSeconds
                    const first = root.channelStore.firstLogicalIndexAtOrAfter(start)
                    const last = root.channelStore.lastLogicalIndexAtOrBefore(end)

                    for (let viewIndex = 0; viewIndex < root.activeChannels.length; ++viewIndex) {
                        const channelIndex = root.activeChannels[viewIndex], data = root.channelStore.channel(channelIndex), top = viewIndex * viewHeight, divisionHeight = viewHeight / 4
                        context.fillStyle = viewIndex % 2 ? "#112833" : "#10242f"
                        context.fillRect(0, top, width, viewHeight)

                        if (root.gridVisible) {
                            context.strokeStyle = "#1e4350"
                            context.lineWidth = 1

                            for (let x = 0; x <= 10; ++x) {
                                context.beginPath()
                                context.moveTo(x * divWidth, top)
                                context.lineTo(x * divWidth, top + viewHeight)
                                context.stroke()
                            }

                            for (let y = 0; y <= 4; ++y) {
                                context.beginPath()
                                context.moveTo(0, top + y * divisionHeight)
                                context.lineTo(width, top + y * divisionHeight)
                                context.stroke()
                            }
                        }

                        context.strokeStyle = "#4a8290"
                        context.setLineDash([3, 3])
                        context.beginPath()
                        context.moveTo(0, top + viewHeight / 2)
                        context.lineTo(width, top + viewHeight / 2)
                        context.stroke()
                        context.setLineDash([])

                        context.strokeStyle = data.color
                        context.lineWidth = 1.35
                        context.beginPath()
                        let drew = false

                        function yFor(value) { return top + viewHeight / 2 - (value + data.verticalOffsetV) * (divisionHeight / data.voltsPerDiv) }
                        function point(value, x) { const y = yFor(value); if (!drew) { context.moveTo(x, y); drew = true } else context.lineTo(x, y) }

                        const sampleCount = Math.max(0, last - first + 1); let envelopeMinimums = undefined, envelopeMaximums = undefined, envelopeColumns = 0
                        if (sampleCount <= Math.max(1, Math.floor(width))) {
                            // Preserve every acquired point when there are fewer samples than pixels.
                            for (let logical = first; logical <= last; ++logical) {
                                const buffer = (root.channelStore.historyStartIndex + logical) % root.channelStore.historyCapacity
                                const value = root.channelStore.historyValue(channelIndex, buffer)
                                if (value !== undefined)
                                    point(value, (root.channelStore.historyTimes[buffer] - start) / root.visibleTimeSeconds * width)
                            }
                        } else {
                            // Do not use a fixed stride: it aliases high-frequency channels.  Keep the
                            // min/max envelope for each pixel column, with X derived from sample time.
                            const columns = Math.max(1, Math.floor(width)), minimums = new Array(columns), maximums = new Array(columns)

                            for (let logical = first; logical <= last; ++logical) {
                                const buffer = (root.channelStore.historyStartIndex + logical) % root.channelStore.historyCapacity
                                const value = root.channelStore.historyValue(channelIndex, buffer)

                                if (value === undefined)
                                    continue

                                const x = (root.channelStore.historyTimes[buffer] - start) / root.visibleTimeSeconds * width
                                const column = Math.max(0, Math.min(columns - 1, Math.floor(x)))

                                if (minimums[column] === undefined || value < minimums[column])
                                    minimums[column] = value
                                if (maximums[column] === undefined || value > maximums[column])
                                    maximums[column] = value
                            }

                            // The connected centre trace keeps the waveform visually continuous;
                            // the min/max stroke below preserves high-frequency extrema.
                            for (let column = 0; column < columns; ++column) {
                                if (minimums[column] !== undefined) {
                                    const x = (column + .5) / columns * width
                                    point((minimums[column] + maximums[column]) / 2, x)
                                }
                            }

                            envelopeMinimums = minimums
                            envelopeMaximums = maximums
                            envelopeColumns = columns
                        }

                        if (drew)
                            context.stroke()

                        if (envelopeColumns > 0) {
                            context.globalAlpha = .55
                            context.beginPath()

                            for (let column = 0; column < envelopeColumns; ++column) {
                                if (envelopeMinimums[column] !== undefined) {
                                    const x = (column + .5) / envelopeColumns * width
                                    context.moveTo(x, yFor(envelopeMinimums[column]))
                                    context.lineTo(x, yFor(envelopeMaximums[column]))
                                }
                            }

                            context.stroke()
                            context.globalAlpha = 1
                        }

                        const latestBuffer = root.channelStore.historyCount ? (root.channelStore.historyStartIndex + root.channelStore.historyCount - 1) % root.channelStore.historyCapacity : 0
                        const current = root.channelStore.historyValue(channelIndex, latestBuffer) || 0

                        context.fillStyle = data.color
                        context.font = "12px sans-serif"
                        if (root.waveformLabelsVisible)
                            context.fillText(data.name + "  " + root.formatNumber(current) + " V  " + root.formatNumber(data.voltsPerDiv) + " V/div", 8, top + 15)

                        context.strokeStyle = "#365467"
                        context.beginPath()
                        context.moveTo(0, top + viewHeight)
                        context.lineTo(width, top + viewHeight)
                        context.stroke()
                    }
                }
            }

            Label {
                anchors.centerIn: parent
                visible: root.activeChannels.length === 0
                text: qsTr("\u8bf7\u5728\u901a\u9053\u8bbe\u7f6e\u4e2d\u542f\u7528\u901a\u9053")
                color: "#7790a0"
                font.pixelSize: 16
            }

            Label {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.margins: 10
                text: root.formatTime(-root.historyOffsetSeconds - root.visibleTimeSeconds)
                color: "#8fa3b4"
                font.pixelSize: 12
            }

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.margins: 10
                text: root.formatNumber(root.timePerDivMs) + " ms/div"
                color: "#8fa3b4"
                font.pixelSize: 12
            }

            Label {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 10
                text: root.formatTime(-root.historyOffsetSeconds)
                color: "#8fa3b4"
                font.pixelSize: 12
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            ActionButton {
                text: qsTr("\u5f00\u59cb\u6a21\u62df")
                enabled: !root.simulationRunning
                fillColor: "#168b7c"
                onClicked: root.startRequested()
            }

            ActionButton {
                text: qsTr("\u505c\u6b62\u6a21\u62df")
                enabled: root.simulationRunning
                fillColor: "#a1514d"
                onClicked: root.stopRequested()
            }

            ActionButton {
                text: qsTr("\u5782\u76f4\u9002\u914d")
                onClicked: root.verticalFitRequested()
            }

            ActionButton {
                text: qsTr("\u4f4d\u7f6e\u590d\u4f4d")
                onClicked: root.resetPositionsRequested()
            }

            ActionButton {
                text: root.waveformLabelsVisible ? qsTr("隐藏标注") : qsTr("显示标注")
                onClicked: { root.waveformLabelsVisible = !root.waveformLabelsVisible; root.schedulePaint() }
            }

            Item {
                Layout.fillWidth: true
            }

            ActionButton {
                text: qsTr("\u6e05\u9664\u5386\u53f2")
                fillColor: "#493b3a"
                onClicked: root.clearHistoryRequested()
            }
        }
    }
}
