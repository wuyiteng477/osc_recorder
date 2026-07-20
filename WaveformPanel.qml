import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Rectangle {
    id: root
    required property bool simulationRunning
    required property bool hasSimulationData
    required property bool channelEnabled
    required property real voltsPerDiv
    required property real timePerDivMs
    required property real verticalOffsetV
    required property real signalFrequencyHz
    required property real signalAmplitudeV
    required property real waveformPhase
    signal startRequested()
    signal stopRequested()
    signal autoFitRequested()
    signal resetRequested()
    color: "#101922"

    function formatNumber(value) { return Number(value).toFixed(1).replace(/\.0$/, "") }
    onWaveformPhaseChanged: waveformCanvas.requestPaint()
    onHasSimulationDataChanged: waveformCanvas.requestPaint()
    onChannelEnabledChanged: waveformCanvas.requestPaint()
    onVoltsPerDivChanged: waveformCanvas.requestPaint()
    onTimePerDivMsChanged: waveformCanvas.requestPaint()
    onVerticalOffsetVChanged: waveformCanvas.requestPaint()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12
        RowLayout {
            Layout.fillWidth: true
            Label { text: "CH1 " + qsTr("\u5b9e\u65f6\u6ce2\u5f62"); color: "#d9e4ec"; font.pixelSize: 17; font.bold: true }
            Item { Layout.fillWidth: true }
            Label {
                text: root.simulationRunning ? qsTr("\u6b63\u5728\u6a21\u62df\u91c7\u96c6") : (root.hasSimulationData ? qsTr("\u6a21\u62df\u91c7\u96c6\u5df2\u505c\u6b62") : qsTr("\u7b49\u5f85\u91c7\u96c6\u6570\u636e"))
                color: root.simulationRunning ? "#35d19b" : "#8fa3b4"; font.pixelSize: 13
            }
        }
        Rectangle {
            Layout.fillWidth: true; Layout.fillHeight: true
            color: "#071018"; border.color: "#2a4253"; clip: true
            Canvas {
                id: waveformCanvas
                anchors.fill: parent
                anchors.margins: 1
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onPaint: {
                    const context = getContext("2d")
                    const w = width
                    const h = height
                    if (w <= 0 || h <= 0) return
                    context.clearRect(0, 0, w, h)
                    context.fillStyle = "#071018"
                    context.fillRect(0, 0, w, h)

                    const divW = w / 10
                    const divH = h / 8
                    context.strokeStyle = "#193141"
                    context.lineWidth = 1
                    for (let column = 0; column <= 10; ++column) {
                        const x = column * divW
                        context.beginPath(); context.moveTo(x, 0); context.lineTo(x, h); context.stroke()
                    }
                    for (let row = 0; row <= 8; ++row) {
                        const y = row * divH
                        context.beginPath(); context.moveTo(0, y); context.lineTo(w, y); context.stroke()
                    }
                    context.strokeStyle = "#24495b"
                    context.setLineDash([3, 4])
                    context.beginPath(); context.moveTo(0, h / 2); context.lineTo(w, h / 2); context.stroke()
                    context.setLineDash([])

                    if (root.hasSimulationData && root.channelEnabled) {
                        const visibleTimeSeconds = root.timePerDivMs * 10 / 1000
                        const pixelsPerVolt = divH / root.voltsPerDiv
                        const amplitudeBreath = 1 + 0.01 * Math.sin(root.waveformPhase)
                        context.strokeStyle = "#39e6bb"
                        context.lineWidth = 2
                        context.beginPath()
                        for (let sample = 0; sample <= 1024; ++sample) {
                            const x = sample / 1024 * w
                            const time = sample / 1024 * visibleTimeSeconds
                            const base = Math.sin(2 * Math.PI * root.signalFrequencyHz * time)
                            const harmonic = 0.08 * Math.sin(2 * Math.PI * root.signalFrequencyHz * 3 * time + 0.4)
                            const noise = 0.018 * Math.sin(sample * 0.73 + root.waveformPhase * 1.7)
                            const voltage = root.signalAmplitudeV * amplitudeBreath * (base + harmonic + noise)
                            const y = h / 2 - (voltage + root.verticalOffsetV) * pixelsPerVolt
                            if (sample === 0) context.moveTo(x, y); else context.lineTo(x, y)
                        }
                        context.stroke()
                    }
                }
            }
            Label { anchors.centerIn: parent; visible: !root.hasSimulationData; text: qsTr("\u7b49\u5f85\u91c7\u96c6\u6570\u636e"); color: "#7790a0"; font.pixelSize: 20 }
            Label { anchors.centerIn: parent; visible: root.hasSimulationData && !root.channelEnabled; text: qsTr("CH1 \u5df2\u5173\u95ed"); color: "#7790a0"; font.pixelSize: 18 }
            Label { anchors.left: parent.left; anchors.top: parent.top; anchors.margins: 12; text: root.formatNumber(root.voltsPerDiv) + " V/div     " + root.formatNumber(root.timePerDivMs) + " ms/div"; color: "#8fa3b4"; font.pixelSize: 12 }
        }
        RowLayout {
            Layout.fillWidth: true; spacing: 10
            Button {
                id: startButton; text: qsTr("\u5f00\u59cb\u6a21\u62df"); enabled: !root.simulationRunning; onClicked: root.startRequested()
                contentItem: Text { text: startButton.text; color: startButton.enabled ? "#ffffff" : "#8292a0"; font.pixelSize: 14; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                background: Rectangle { implicitWidth: 106; implicitHeight: 34; radius: 4; color: startButton.enabled ? "#168b7c" : "#294c4a" }
            }
            Button {
                id: stopButton; text: qsTr("\u505c\u6b62\u6a21\u62df"); enabled: root.simulationRunning; onClicked: root.stopRequested()
                contentItem: Text { text: stopButton.text; color: stopButton.enabled ? "#ffffff" : "#8292a0"; font.pixelSize: 14; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                background: Rectangle { implicitWidth: 106; implicitHeight: 34; radius: 4; color: stopButton.enabled ? "#a1514d" : "#483837" }
            }
            Button {
                id: autoButton; text: qsTr("\u81ea\u52a8\u9002\u914d"); onClicked: root.autoFitRequested()
                contentItem: Text { text: autoButton.text; color: "#d9e4ec"; font.pixelSize: 14; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                background: Rectangle { implicitWidth: 96; implicitHeight: 34; radius: 4; color: "#285b73" }
            }
            Button {
                id: resetButton; text: qsTr("\u663e\u793a\u590d\u4f4d"); onClicked: root.resetRequested()
                contentItem: Text { text: resetButton.text; color: "#d9e4ec"; font.pixelSize: 14; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                background: Rectangle { implicitWidth: 96; implicitHeight: 34; radius: 4; color: "#354452" }
            }
            Item { Layout.fillWidth: true }
        }
    }
}
