pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

ApplicationWindow {
    id: window
    width: 1280; height: 760
    minimumWidth: 980; minimumHeight: 620
    visible: true
    title: qsTr("工业多通道示波记录软件")
    color: "#111821"

    property string currentPage: "realtime"
    property bool simulationRunning: false
    property bool channelEnabled: true
    property string displayMode: "stable"
    property real voltsPerDiv: 1.0
    property real timePerDivMs: 1.0
    property real verticalOffsetV: 0.0
    property real signalFrequencyHz: 500.0
    property real signalAmplitudeV: 1.0
    property int simulationSampleRate: 5000
    property int historyCapacity: 100000
    property var historyTimes: []
    property var historyValues: []
    property int historyStartIndex: 0
    property int historyCount: 0
    property real sampleTimeSeconds: 0.0
    property real latestSampleTime: 0.0
    property int historyRevision: 0
    property bool followLatest: true
    property real historyOffsetSeconds: 0.0
    readonly property bool hasSimulationData: historyCount > 0
    readonly property real historyStartTime: historyCount > 0 ? historyTimes[historyStartIndex] : 0.0
    readonly property real visibleTimeSeconds: timePerDivMs * 10 / 1000
    readonly property color panelColor: "#15212c"
    readonly property color borderColor: "#314252"
    readonly property color textColor: "#d9e4ec"
    readonly property color mutedTextColor: "#8fa3b4"
    readonly property color accentColor: "#19b4a5"

    function formatNumber(value) { return Number(value).toFixed(1).replace(/\.0$/, "") }
    function formatDuration(seconds) {
        const magnitude = Math.abs(seconds)
        return magnitude < 1 ? formatNumber(seconds * 1000) + " ms" : formatNumber(seconds) + " s"
    }
    function timestamp() {
        const now = new Date()
        return [now.getHours(), now.getMinutes(), now.getSeconds()].map(v => String(v).padStart(2, "0")).join(":")
    }
    function appendLog(message, level) {
        logModel.append({ "message": "[" + timestamp() + "] [" + (level || qsTr("信息")) + "] " + message })
        if (logModel.count > 100) logModel.remove(0)
        logView.positionViewAtEnd()
    }
    function pageTitle(page) {
        const titles = { realtime: qsTr("实时波形"), channels: qsTr("通道设置"), acquisition: qsTr("采集设置"), recording: qsTr("数据录制"), system: qsTr("系统状态") }
        return titles[page] || titles.realtime
    }
    function changePage(page) { if (currentPage !== page) { currentPage = page; appendLog(qsTr("已切换到") + pageTitle(page) + qsTr("页面")) } }
    function initializeHistory() { if (historyTimes.length !== historyCapacity) { historyTimes = new Array(historyCapacity); historyValues = new Array(historyCapacity) } }
    function generateValue(time) {
        const carrier = Math.sin(2 * Math.PI * signalFrequencyHz * time)
        const harmonic = 0.08 * Math.sin(2 * Math.PI * signalFrequencyHz * 3 * time + 0.4)
        const amplitude = 1.0 + 0.12 * Math.sin(2 * Math.PI * 0.09 * time + 0.7)
        const baseline = 0.07 * Math.sin(2 * Math.PI * 0.045 * time + 0.2)
        const noise = 0.012 * Math.sin(2 * Math.PI * 217.7 * time) + 0.006 * Math.sin(2 * Math.PI * 509.3 * time + 0.3)
        const eventPhase = time % 4.7
        const event = eventPhase < 0.22 ? -0.28 * Math.sin(Math.PI * eventPhase / 0.22) : 0
        return signalAmplitudeV * (amplitude * (carrier + harmonic) + baseline + noise + event)
    }
    function appendSimulationSamples(batchSize) {
        initializeHistory()
        const interval = 1.0 / simulationSampleRate
        for (let i = 0; i < batchSize; ++i) {
            const writeIndex = (historyStartIndex + historyCount) % historyCapacity
            historyTimes[writeIndex] = sampleTimeSeconds
            historyValues[writeIndex] = generateValue(sampleTimeSeconds)
            if (historyCount < historyCapacity) historyCount += 1
            else historyStartIndex = (historyStartIndex + 1) % historyCapacity
            latestSampleTime = sampleTimeSeconds
            sampleTimeSeconds += interval
        }
        if (followLatest) historyOffsetSeconds = 0
        else historyOffsetSeconds = Math.min(historyOffsetSeconds + batchSize / simulationSampleRate, maximumHistoryOffset())
        historyRevision += 1
    }
    function maximumHistoryOffset() { return Math.max(0, latestSampleTime - historyStartTime - visibleTimeSeconds) }
    function clampHistoryOffset() {
        historyOffsetSeconds = Math.min(Math.max(0, historyOffsetSeconds), maximumHistoryOffset())
        followLatest = historyOffsetSeconds <= 0.000001
    }
    function startSimulation() { if (!simulationRunning) { simulationRunning = true; appendLog(qsTr("模拟采集已启动")) } }
    function stopSimulation() { if (simulationRunning) { simulationRunning = false; appendLog(qsTr("模拟采集已停止")) } }
    function setVoltsPerDiv(value) { if (voltsPerDiv !== value) { voltsPerDiv = value; appendLog("CH1 " + qsTr("量程已设置为 ") + formatNumber(value) + " V/div") } }
    function setTimePerDiv(value) { if (timePerDivMs !== value) { timePerDivMs = value; clampHistoryOffset(); appendLog(qsTr("时基已设置为 ") + formatNumber(value) + " ms/div") } }
    function setVerticalOffset(value) { const bounded = Math.max(-5, Math.min(5, value)); if (verticalOffsetV !== bounded) { verticalOffsetV = bounded; appendLog("CH1 " + qsTr("垂直偏移已设置为 ") + formatNumber(bounded) + " V") } }
    function setChannelEnabled(enabled) { if (channelEnabled !== enabled) { channelEnabled = enabled; appendLog(enabled ? "CH1 " + qsTr("已开启") : "CH1 " + qsTr("已关闭")) } }
    function changeDisplayMode(mode) { if (displayMode !== mode) { displayMode = mode; appendLog(mode === "roll" ? qsTr("已切换到滚动显示") : qsTr("已切换到稳定显示")) } }
    function historyIndex(logicalIndex) { return (historyStartIndex + logicalIndex) % historyCapacity }
    function verticalFit() {
        if (!hasSimulationData) { appendLog(qsTr("当前没有可用于垂直适配的数据"), qsTr("提示")); return }
        const endTime = latestSampleTime - historyOffsetSeconds
        const startTime = endTime - visibleTimeSeconds
        let minimum = Infinity, maximum = -Infinity
        for (let logical = 0; logical < historyCount; ++logical) {
            const index = historyIndex(logical), time = historyTimes[index]
            if (time >= startTime && time <= endTime) { const value = historyValues[index]; minimum = Math.min(minimum, value); maximum = Math.max(maximum, value) }
        }
        if (!isFinite(minimum) || !isFinite(maximum)) { appendLog(qsTr("当前没有可用于垂直适配的数据"), qsTr("提示")); return }
        const peakToPeak = Math.max(0.001, maximum - minimum)
        const ranges = [0.2, 0.5, 1.0, 2.0, 5.0]
        let selected = ranges[ranges.length - 1]
        for (let i = 0; i < ranges.length; ++i) if (peakToPeak <= ranges[i] * 8 * 0.8) { selected = ranges[i]; break }
        voltsPerDiv = selected
        verticalOffsetV = Math.max(-5, Math.min(5, -(maximum + minimum) / 2))
        appendLog(qsTr("已执行垂直适配：量程 ") + formatNumber(voltsPerDiv) + " V/div，" + qsTr("偏移 ") + formatNumber(verticalOffsetV) + " V")
    }
    function resetPositions() {
        if (verticalOffsetV === 0 && followLatest) return
        verticalOffsetV = 0; historyOffsetSeconds = 0; followLatest = true
        appendLog(qsTr("波形水平和垂直位置已复位"))
    }
    function moveHistoryLeft() {
        if (!hasSimulationData) return
        const oldOffset = historyOffsetSeconds
        historyOffsetSeconds = Math.min(maximumHistoryOffset(), historyOffsetSeconds + visibleTimeSeconds * 0.5)
        followLatest = historyOffsetSeconds <= 0.000001
        if (historyOffsetSeconds !== oldOffset) appendLog(qsTr("水平位置已移至距最新 ") + formatDuration(historyOffsetSeconds))
    }
    function moveHistoryRight() {
        if (!hasSimulationData || historyOffsetSeconds <= 0.000001) return
        historyOffsetSeconds = Math.max(0, historyOffsetSeconds - visibleTimeSeconds * 0.5)
        followLatest = historyOffsetSeconds <= 0.000001
        appendLog(followLatest ? qsTr("水平位置已归零，已回到最新数据") : qsTr("水平位置已移至距最新 ") + formatDuration(historyOffsetSeconds))
    }
    function clearHistory() { historyStartIndex = 0; historyCount = 0; historyOffsetSeconds = 0; followLatest = true; historyRevision += 1; appendLog("CH1 " + qsTr("模拟历史已清除")) }

    ListModel { id: logModel }
    Component.onCompleted: { appendLog(qsTr("软件启动完成")); appendLog(qsTr("当前运行在模拟模式")); appendLog(qsTr("尚未连接采集设备"), qsTr("提示")) }
    Timer { interval: 20; running: window.simulationRunning; repeat: true; onTriggered: window.appendSimulationSamples(100) }
    component StatusItem: RowLayout { required property string label; required property string value; property color valueColor: window.textColor; spacing: 6; Label { text: parent.label + ":"; color: window.mutedTextColor; font.pixelSize: 13 } Label { text: parent.value; color: parent.valueColor; font.pixelSize: 13; font.bold: true } }

    ColumnLayout {
        anchors.fill: parent; spacing: 0
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 54; color: window.panelColor; border.color: window.borderColor
            RowLayout { anchors.fill: parent; anchors.leftMargin: 22; anchors.rightMargin: 22; spacing: 26
                Label { text: window.title; color: "#f0f6f8"; font.pixelSize: 18; font.bold: true; Layout.rightMargin: 16 }
                StatusItem { label: qsTr("设备"); value: qsTr("未连接"); valueColor: "#e8a94b" } StatusItem { label: qsTr("采集"); value: window.simulationRunning ? qsTr("运行中") : qsTr("已停止"); valueColor: window.simulationRunning ? "#35d19b" : window.mutedTextColor } StatusItem { label: qsTr("录制"); value: qsTr("已停止") } StatusItem { label: qsTr("磁盘空间"); value: "--" } StatusItem { label: qsTr("告警"); value: "0"; valueColor: "#35d19b" } Item { Layout.fillWidth: true } Label { text: qsTr("模拟模式"); color: window.accentColor; font.pixelSize: 13; font.bold: true }
            }
        }
        RowLayout { Layout.fillWidth: true; Layout.fillHeight: true; spacing: 0
            NavigationPanel { Layout.preferredWidth: 176; Layout.fillHeight: true; currentPage: window.currentPage; onPageRequested: page => window.changePage(page) }
            StackLayout { Layout.fillWidth: true; Layout.fillHeight: true; currentIndex: ["realtime", "channels", "acquisition", "recording", "system"].indexOf(window.currentPage)
                RowLayout { spacing: 0
                    WaveformPanel { Layout.fillWidth: true; Layout.fillHeight: true; simulationRunning: window.simulationRunning; hasSimulationData: window.hasSimulationData; channelEnabled: window.channelEnabled; displayMode: window.displayMode; voltsPerDiv: window.voltsPerDiv; timePerDivMs: window.timePerDivMs; verticalOffsetV: window.verticalOffsetV; historyTimes: window.historyTimes; historyValues: window.historyValues; historyStartIndex: window.historyStartIndex; historyCount: window.historyCount; historyCapacity: window.historyCapacity; latestSampleTime: window.latestSampleTime; historyOffsetSeconds: window.historyOffsetSeconds; historyRevision: window.historyRevision; onStartRequested: window.startSimulation(); onStopRequested: window.stopSimulation(); onVerticalFitRequested: window.verticalFit(); onResetPositionsRequested: window.resetPositions(); onClearHistoryRequested: window.clearHistory() }
                    ParameterPanel { Layout.preferredWidth: 250; Layout.fillHeight: true; channelEnabled: window.channelEnabled; voltsPerDiv: window.voltsPerDiv; timePerDivMs: window.timePerDivMs; verticalOffsetV: window.verticalOffsetV; displayMode: window.displayMode; hasSimulationData: window.hasSimulationData; historyOffsetSeconds: window.historyOffsetSeconds; maximumHistoryOffsetSeconds: window.maximumHistoryOffset(); onChannelEnabledRequested: enabled => window.setChannelEnabled(enabled); onVoltsPerDivRequested: value => window.setVoltsPerDiv(value); onTimePerDivRequested: value => window.setTimePerDiv(value); onVerticalOffsetRequested: value => window.setVerticalOffset(value); onDisplayModeRequested: mode => window.changeDisplayMode(mode); onMoveHistoryLeftRequested: window.moveHistoryLeft(); onMoveHistoryRightRequested: window.moveHistoryRight(); onResetHistoryPositionRequested: window.resetPositions() }
                }
                ChannelSettingsPage { } AcquisitionSettingsPage { } RecordingPage { } SystemStatusPage { simulationRunning: window.simulationRunning }
            }
        }
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 118; color: "#121d27"; border.color: window.borderColor
            ColumnLayout { anchors.fill: parent; anchors.margins: 10; spacing: 4; Label { text: qsTr("运行日志"); color: window.mutedTextColor; font.pixelSize: 12; font.bold: true } ListView { id: logView; Layout.fillWidth: true; Layout.fillHeight: true; model: logModel; clip: true; delegate: Label { required property string message; text: message; color: message.indexOf("[提示]") >= 0 ? "#e8a94b" : window.textColor; font.pixelSize: 13 } } }
        }
    }
}
