pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Rectangle {
    id: root
    color: "#132633"
    border.color: "#314b5b"
    clip: true

    required property bool activePage
    required property var channelStore
    required property var realtimeData
    required property int selectedChannelIndex
    required property bool simulationRunning
    required property string displayMode
    required property bool gridVisible
    required property real timePerDivMs
    required property real sharedWindowStart
    required property real sharedWindowEnd
    required property real sharedLatestTime
    required property real sharedHistoryOffset
    required property real samplePeriodSeconds
    required property string interpolationMode
    required property bool triggerFrameVisible
    required property real triggerTimeSeconds
    required property int triggerChannelIndex
    required property real triggerLevel
    property bool waveformLabelsVisible: true
    property var displaySnapshot: ({ channels: [], mode: "raw", sampleCount: 0, samplesPerPixel: 0 })
    readonly property bool interpolationAvailable: displaySnapshot.mode === "raw" && Number(displaySnapshot.samplesPerPixel) < 0.5
    signal selectedChannelRequested(int index)
    signal startRequested(); signal stopRequested(); signal verticalFitRequested(); signal resetPositionsRequested(); signal clearHistoryRequested()
    readonly property real visibleTimeSeconds: sharedWindowEnd - sharedWindowStart
    readonly property bool reviewingHistory: sharedHistoryOffset > 1e-9
    readonly property bool usesHistory: reviewingHistory || displayMode === "roll"
    readonly property var activeChannels: channelStore.activeViewChannels()
    readonly property int activeViewCount: Math.max(1, activeChannels.length)

    function formatNumber(value) { return Number(value).toFixed(1).replace(/\.0$/, "") }
    function formatTime(value) { return Math.abs(value) < 1 ? formatNumber(value * 1000) + " ms" : formatNumber(value) + " s" }
    function schedulePaint() {
        if (!activePage || waveformCanvas.width <= 0 || waveformCanvas.height <= 0)
            return
        // The C++ backend creates one immutable, shared, compact snapshot for
        // this paint.  No channel-specific raw-buffer lookup happens in QML.
        realtimeData.refreshDisplaySnapshot(sharedWindowStart, sharedWindowEnd,
                                            1 / samplePeriodSeconds, Math.floor(waveformCanvas.width), activeChannels)
        displaySnapshot = realtimeData.displaySnapshot
        waveformCanvas.requestPaint()
    }

    onSharedWindowStartChanged: schedulePaint()
    onSharedWindowEndChanged: schedulePaint()
    onSharedLatestTimeChanged: schedulePaint()
    onSharedHistoryOffsetChanged: schedulePaint()
    onTimePerDivMsChanged: schedulePaint()
    onDisplayModeChanged: schedulePaint()
    onGridVisibleChanged: schedulePaint()
    onSelectedChannelIndexChanged: schedulePaint()
    onActivePageChanged: { if (activePage) schedulePaint() }

    Connections {
        target: root.channelStore

        function onRevisionChanged() { root.schedulePaint() }
    }

    Connections {
        target: root.realtimeData
        function onHistoryChanged() { root.schedulePaint() }
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
                    // One C++ snapshot per display frame, shared by CH1–CH8.
                    const snapshot = root.displaySnapshot
                    const snapshotChannels = snapshot.channels || []
                    const windowDuration = Math.max(1e-12, root.sharedWindowEnd - root.sharedWindowStart)
                    const triggerX = (root.triggerTimeSeconds - root.sharedWindowStart) / windowDuration * width
                    const showTrigger = root.triggerFrameVisible && triggerX >= 0 && triggerX <= width

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
                        // Each channel owns an isolated drawing viewport.  This
                        // protects adjacent waveforms even for large manual
                        // offsets or a transiently oversized signal.
                        context.save()
                        context.beginPath()
                        context.rect(0, top + 1, width, Math.max(0, viewHeight - 2))
                        context.clip()
                        context.beginPath()
                        let drew = false

                        function yFor(value) { return top + viewHeight / 2 - (value + data.verticalOffsetV) * (divisionHeight / data.voltsPerDiv) }
                        function point(value, x) { const y = yFor(value); if (!drew) { context.moveTo(x, y); drew = true } else context.lineTo(x, y) }

                        const series = snapshotChannels[viewIndex] || ({ points: [] })
                        const points = series.points || []
                        let previousX = 0, previousY = 0, havePrevious = false
                        // Interpolation is meaningful only when true samples
                        // are farther apart than two pixels (spp < 0.5).  At
                        // normal density we always connect adjacent original
                        // samples directly, regardless of the selected mode.
                        const pointsOnly = root.interpolationAvailable && root.interpolationMode === "none"
                        if (pointsOnly)
                            context.fillStyle = data.color
                        for (let pointIndex = 0; pointIndex + 1 < points.length; pointIndex += 2) {
                            const x = points[pointIndex], value = points[pointIndex + 1]
                            if (!isFinite(x) || !isFinite(value)) { havePrevious = false; continue }
                            const y = yFor(value)
                            if (pointsOnly) {
                                // A real filled pixel marker remains visible at
                                // low timebases; a near-zero stroke is removed
                                // by Canvas anti-aliasing on high-DPI displays.
                                context.fillRect(Math.round(x) - 1, Math.round(y) - 1, 2, 2)
                            } else if (!havePrevious) {
                                context.moveTo(x, y)
                            } else if (root.interpolationAvailable && root.interpolationMode === "step") {
                                context.lineTo(x, previousY); context.lineTo(x, y)
                            } else if (root.interpolationAvailable && root.interpolationMode === "sine") {
                                // Half-cosine easing is a bounded sine-family
                                // interpolation between two real samples.  The
                                // segment count is capped so sparse data never
                                // expands into an unbounded display array.
                                const segments = Math.max(2, Math.min(8, Math.ceil(Math.abs(x - previousX) / 8)))
                                for (let segment = 1; segment <= segments; ++segment) {
                                    const ratio = segment / segments
                                    const eased = (1 - Math.cos(Math.PI * ratio)) / 2
                                    context.lineTo(previousX + (x - previousX) * ratio,
                                                   previousY + (y - previousY) * eased)
                                }
                            } else {
                                // Auto and linear use only adjacent real samples. Envelope points
                                // already arrive in true min/max sample order from C++.
                                context.lineTo(x, y)
                            }
                            previousX = x; previousY = y; havePrevious = true; drew = true
                        }
                        if (drew && !pointsOnly) context.stroke()
                        context.restore()

                        if (showTrigger) {
                            context.strokeStyle = "#f2c94c"
                            context.lineWidth = 1
                            context.setLineDash([4, 3])
                            context.beginPath()
                            context.moveTo(triggerX, top)
                            context.lineTo(triggerX, top + viewHeight)
                            context.stroke()
                            context.setLineDash([])
                            if (channelIndex === root.triggerChannelIndex) {
                                const triggerY = top + viewHeight / 2 - (root.triggerLevel + data.verticalOffsetV) * (divisionHeight / data.voltsPerDiv)
                                context.strokeStyle = "#f2c94c"
                                context.setLineDash([3, 3])
                                context.beginPath()
                                context.moveTo(0, triggerY)
                                context.lineTo(width, triggerY)
                                context.stroke()
                                context.setLineDash([])
                            }
                        }

                        const current = points.length >= 2 ? points[points.length - 1] : 0

                        context.fillStyle = data.color
                        context.font = "12px sans-serif"
                        if (root.waveformLabelsVisible)
                            context.fillText(data.name + "  " + root.formatNumber(current) + " V  " + root.formatNumber(data.voltsPerDiv) + " V/div", 8, top + 15)

                        if (channelIndex === root.selectedChannelIndex) {
                            context.strokeStyle = data.color
                            context.lineWidth = 1
                            context.strokeRect(.5, top + .5, width - 1, Math.max(0, viewHeight - 1))
                        }

                        context.strokeStyle = "#365467"
                        context.beginPath()
                        context.moveTo(0, top + viewHeight)
                        context.lineTo(width, top + viewHeight)
                        context.stroke()
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                enabled: root.activeChannels.length > 0
                hoverEnabled: true
                cursorShape: containsMouse ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: mouse => {
                    const viewHeight = waveformCanvas.height / root.activeChannels.length
                    const canvasY = mouse.y - waveformCanvas.y
                    const viewIndex = Math.max(0, Math.min(root.activeChannels.length - 1, Math.floor(canvasY / viewHeight)))
                    root.selectedChannelRequested(root.activeChannels[viewIndex])
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
                text: root.formatTime(-root.sharedHistoryOffset - root.visibleTimeSeconds)
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
                text: root.formatTime(-root.sharedHistoryOffset)
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
