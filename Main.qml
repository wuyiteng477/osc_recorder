pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

ApplicationWindow {
    id: window
    width: 1280
    height: 760
    minimumWidth: 980
    minimumHeight: 620
    visible: true
    title: qsTr("\u5de5\u4e1a\u591a\u901a\u9053\u793a\u6ce2\u8bb0\u5f55\u8f6f\u4ef6")
    color: "#111821"

    property string currentPage: "realtime"
    property bool simulationRunning: false
    property bool hasSimulationData: false
    property bool channelEnabled: true
    property real voltsPerDiv: 1.0
    property real timePerDivMs: 1.0
    property real verticalOffsetV: 0.0
    property real signalFrequencyHz: 200.0
    property real signalAmplitudeV: 1.0
    property real waveformPhase: 0.0

    readonly property color panelColor: "#15212c"
    readonly property color borderColor: "#314252"
    readonly property color textColor: "#d9e4ec"
    readonly property color mutedTextColor: "#8fa3b4"
    readonly property color accentColor: "#19b4a5"

    function pageTitle(page) {
        const titles = { "realtime": qsTr("\u5b9e\u65f6\u6ce2\u5f62"), "channels": qsTr("\u901a\u9053\u8bbe\u7f6e"), "acquisition": qsTr("\u91c7\u96c6\u8bbe\u7f6e"), "recording": qsTr("\u6570\u636e\u5f55\u5236"), "system": qsTr("\u7cfb\u7edf\u72b6\u6001") }
        return titles[page] || titles.realtime
    }
    function formatNumber(value) { return Number(value).toFixed(1).replace(/\.0$/, "") }
    function appendLog(message) {
        logModel.append({ "message": message })
        if (logModel.count > 100)
            logModel.remove(0)
    }
    function changePage(page) {
        if (currentPage === page)
            return
        currentPage = page
        appendLog(qsTr("[\u4fe1\u606f] \u5df2\u5207\u6362\u5230") + pageTitle(page) + qsTr("\u9875\u9762"))
    }
    function startSimulation() {
        if (!simulationRunning) {
            simulationRunning = true
            appendLog(qsTr("[\u4fe1\u606f] \u6a21\u62df\u91c7\u96c6\u5df2\u542f\u52a8"))
        }
    }
    function stopSimulation() {
        if (simulationRunning) {
            simulationRunning = false
            appendLog(qsTr("[\u4fe1\u606f] \u6a21\u62df\u91c7\u96c6\u5df2\u505c\u6b62"))
        }
    }
    function setVoltsPerDiv(value) {
        if (voltsPerDiv === value) return
        voltsPerDiv = value
        appendLog(qsTr("[\u4fe1\u606f] CH1 \u91cf\u7a0b\u5df2\u8bbe\u7f6e\u4e3a ") + formatNumber(value) + " V/div")
    }
    function setTimePerDiv(value) {
        if (timePerDivMs === value) return
        timePerDivMs = value
        appendLog(qsTr("[\u4fe1\u606f] \u65f6\u57fa\u5df2\u8bbe\u7f6e\u4e3a ") + formatNumber(value) + " ms/div")
    }
    function setVerticalOffset(value) {
        const bounded = Math.max(-5.0, Math.min(5.0, value))
        if (verticalOffsetV === bounded) return
        verticalOffsetV = bounded
        appendLog(qsTr("[\u4fe1\u606f] CH1 \u5782\u76f4\u504f\u79fb\u5df2\u8bbe\u7f6e\u4e3a ") + formatNumber(bounded) + " V")
    }
    function setChannelEnabled(enabled) {
        if (channelEnabled === enabled) return
        channelEnabled = enabled
        appendLog(enabled ? qsTr("[\u4fe1\u606f] CH1 \u5df2\u5f00\u542f") : qsTr("[\u4fe1\u606f] CH1 \u5df2\u5173\u95ed"))
    }
    function autoFit() {
        setVoltsPerDiv(0.5)
        verticalOffsetV = 0.0
        appendLog(qsTr("[\u4fe1\u606f] \u5df2\u6267\u884c\u6ce2\u5f62\u81ea\u52a8\u9002\u914d"))
    }
    function resetDisplay() {
        voltsPerDiv = 1.0
        timePerDivMs = 1.0
        verticalOffsetV = 0.0
        channelEnabled = true
        appendLog(qsTr("[\u4fe1\u606f] \u5b9e\u65f6\u6ce2\u5f62\u663e\u793a\u53c2\u6570\u5df2\u590d\u4f4d"))
    }

    ListModel {
        id: logModel
        ListElement { message: "[\u4fe1\u606f] \u8f6f\u4ef6\u542f\u52a8\u5b8c\u6210" }
        ListElement { message: "[\u4fe1\u606f] \u5f53\u524d\u8fd0\u884c\u5728\u6a21\u62df\u6a21\u5f0f" }
        ListElement { message: "[\u63d0\u793a] \u5c1a\u672a\u8fde\u63a5\u91c7\u96c6\u8bbe\u5907" }
    }

    // 相位只驱动轻微幅度与噪声变化，主波形的水平位置保持稳定。
    Timer {
        interval: 33
        running: window.simulationRunning
        repeat: true
        onTriggered: { window.waveformPhase += 0.06; window.hasSimulationData = true }
    }

    component StatusItem: RowLayout {
        required property string label
        required property string value
        property color valueColor: window.textColor
        spacing: 6
        Label { text: parent.label + ":"; color: window.mutedTextColor; font.pixelSize: 13 }
        Label { text: parent.value; color: parent.valueColor; font.pixelSize: 13; font.bold: true }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        Rectangle {
            Layout.fillWidth: true; Layout.preferredHeight: 54; color: window.panelColor; border.color: window.borderColor
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 22; anchors.rightMargin: 22; spacing: 26
                Label { text: window.title; color: "#f0f6f8"; font.pixelSize: 18; font.bold: true; Layout.rightMargin: 16 }
                StatusItem { label: qsTr("\u8bbe\u5907"); value: qsTr("\u672a\u8fde\u63a5"); valueColor: "#e8a94b" }
                StatusItem { label: qsTr("\u91c7\u96c6"); value: window.simulationRunning ? qsTr("\u8fd0\u884c\u4e2d") : qsTr("\u5df2\u505c\u6b62"); valueColor: window.simulationRunning ? "#35d19b" : window.mutedTextColor }
                StatusItem { label: qsTr("\u5f55\u5236"); value: qsTr("\u5df2\u505c\u6b62") }
                StatusItem { label: qsTr("\u78c1\u76d8\u7a7a\u95f4"); value: "--" }
                StatusItem { label: qsTr("\u544a\u8b66"); value: "0"; valueColor: "#35d19b" }
                Item { Layout.fillWidth: true }
                Label { text: qsTr("\u6a21\u62df\u6a21\u5f0f"); color: window.accentColor; font.pixelSize: 13; font.bold: true }
            }
        }
        RowLayout {
            Layout.fillWidth: true; Layout.fillHeight: true; spacing: 0
            NavigationPanel { Layout.preferredWidth: 176; Layout.fillHeight: true; currentPage: window.currentPage; onPageRequested: page => window.changePage(page) }
            StackLayout {
                Layout.fillWidth: true; Layout.fillHeight: true
                currentIndex: ["realtime", "channels", "acquisition", "recording", "system"].indexOf(window.currentPage)
                RowLayout {
                    spacing: 0
                    WaveformPanel {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        simulationRunning: window.simulationRunning; hasSimulationData: window.hasSimulationData; channelEnabled: window.channelEnabled
                        voltsPerDiv: window.voltsPerDiv; timePerDivMs: window.timePerDivMs; verticalOffsetV: window.verticalOffsetV
                        signalFrequencyHz: window.signalFrequencyHz; signalAmplitudeV: window.signalAmplitudeV; waveformPhase: window.waveformPhase
                        onStartRequested: window.startSimulation(); onStopRequested: window.stopSimulation(); onAutoFitRequested: window.autoFit(); onResetRequested: window.resetDisplay()
                    }
                    ParameterPanel {
                        Layout.preferredWidth: 250; Layout.fillHeight: true
                        channelEnabled: window.channelEnabled; voltsPerDiv: window.voltsPerDiv; timePerDivMs: window.timePerDivMs; verticalOffsetV: window.verticalOffsetV
                        onChannelEnabledRequested: enabled => window.setChannelEnabled(enabled)
                        onVoltsPerDivRequested: value => window.setVoltsPerDiv(value)
                        onTimePerDivRequested: value => window.setTimePerDiv(value)
                        onVerticalOffsetRequested: value => window.setVerticalOffset(value)
                    }
                }
                ChannelSettingsPage { }
                AcquisitionSettingsPage { }
                RecordingPage { }
                SystemStatusPage { simulationRunning: window.simulationRunning }
            }
        }
        Rectangle {
            Layout.fillWidth: true; Layout.preferredHeight: 118; color: "#121d27"; border.color: window.borderColor
            ColumnLayout {
                anchors.fill: parent; anchors.margins: 10; spacing: 4
                Label { text: qsTr("\u8fd0\u884c\u65e5\u5fd7"); color: window.mutedTextColor; font.pixelSize: 12; font.bold: true }
                ListView {
                    Layout.fillWidth: true; Layout.fillHeight: true; model: logModel; clip: true; verticalLayoutDirection: ListView.BottomToTop
                    delegate: Label { required property string message; text: message; color: message.indexOf("[\u63d0\u793a]") === 0 ? "#e8a94b" : window.textColor; font.pixelSize: 13 }
                }
            }
        }
    }
}
