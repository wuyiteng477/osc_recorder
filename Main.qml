pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

ApplicationWindow {
    id: window
    width: 1280; height: 800; minimumWidth: 980; minimumHeight: 620; visible: true
    title: qsTr("\u5de5\u4e1a\u591a\u901a\u9053\u793a\u6ce2\u8bb0\u5f55\u8f6f\u4ef6")
    color: "#101820"
    property string currentPage: "realtime"
    property bool simulationRunning: false
    property int selectedChannelIndex: 0
    property string displayMode: "update"
    property bool gridVisible: true
    // Controls the language used for new runtime-log entries.  Acquisition and
    // waveform state are deliberately independent of this presentation option.
    property string logLanguage: "zh"
    property real timePerDivMs: 1.0
    property real historyOffsetSeconds: 0
    property bool followLatest: true
    property real sampleTimeSeconds: 0
    property real latestSampleTime: 0
    property int simulationSampleRate: 5000
    readonly property real visibleTimeSeconds: timePerDivMs * 10 / 1000
    readonly property real horizontalStepSeconds: timePerDivMs / 1000
    readonly property var selectedChannel: channelStore.channel(selectedChannelIndex)
    readonly property bool hasSimulationData: channelStore.hasData
    readonly property real historyStartTime: channelStore.historyStartTime
    ChannelStore { id: channelStore }

    function formatNumber(value) { return Number(value).toFixed(1).replace(/\.0$/, "") }
    function formatDuration(value) { return Math.abs(value) < 1 ? formatNumber(value * 1000) + " ms" : formatNumber(value) + " s" }
    function appendLog(chineseMessage, englishMessage, level) { const now = new Date(); const stamp = [now.getHours(), now.getMinutes(), now.getSeconds()].map(value => String(value).padStart(2, "0")).join(":"); const message = logLanguage === "en" ? (englishMessage || chineseMessage) : chineseMessage; logModel.append({ message: "[" + stamp + "] [" + (level || "INFO") + "] " + message }); if (logModel.count > 100) logModel.remove(0); logView.positionViewAtEnd() }
    function maximumHistoryOffset() { return Math.max(0, latestSampleTime - historyStartTime - visibleTimeSeconds) }
    function clampOffset() { historyOffsetSeconds = Math.max(0, Math.min(historyOffsetSeconds, maximumHistoryOffset())); if (historyOffsetSeconds < 1e-9) historyOffsetSeconds = 0; followLatest = historyOffsetSeconds === 0 }
    function appendSimulationSamples(count) { const interval = 1 / simulationSampleRate; channelStore.appendSamples(sampleTimeSeconds, interval, count); latestSampleTime = sampleTimeSeconds + (count - 1) * interval; sampleTimeSeconds += count * interval; if (followLatest) historyOffsetSeconds = 0; else historyOffsetSeconds = Math.min(maximumHistoryOffset(), historyOffsetSeconds + count * interval) }
    function setSelectedChannel(index) { if (index !== selectedChannelIndex) { selectedChannelIndex = index; channelStore.selectChannel(index); const name = channelStore.channel(index).name; appendLog(name + " 已选中", name + " selected") } }
    function setChannelEnabled(index, enabled) { const data = channelStore.channel(index); if (enabled && !data.enabled && channelStore.enabledCount() >= 8) { appendLog("实时显示最多只能启用八个通道", "Only eight channels can be enabled for real-time display", "NOTICE"); return } if (channelStore.setRole(index, "enabled", enabled)) { channelStore.setRole(index, "visible", enabled); appendLog(data.name + (enabled ? " 已启用" : " 已停用"), data.name + (enabled ? " enabled" : " disabled")) } }
    function setChannelVisible(index, visible) { const data = channelStore.channel(index); if (channelStore.setRole(index, "visible", visible)) appendLog(data.name + (visible ? " 已显示" : " 已隐藏"), data.name + (visible ? " shown" : " hidden")) }
    function toggleChannelVisible(index) { const visible = channelStore.channel(index).visible; setChannelVisible(index, !visible); if (!visible) setSelectedChannel(index); else if (selectedChannelIndex === index) { for (let i = 0; i < channelStore.channelModel.count; ++i) if (channelStore.channel(i).visible) { setSelectedChannel(i); break } } }
    function setChannelName(index, name) { const clean = name.trim(); if (clean.length && channelStore.setRole(index, "name", clean)) appendLog("CH" + channelStore.channel(index).channelId + " 已重命名为 " + clean, "CH" + channelStore.channel(index).channelId + " renamed to " + clean) }
    function setChannelColor(index, color) { if (channelStore.setRole(index, "color", color)) { const name = channelStore.channel(index).name; appendLog(name + " 颜色已更改", name + " color changed") } }
    function setVoltsPerDiv(value) { const data = selectedChannel; if (channelStore.setRole(selectedChannelIndex, "voltsPerDiv", value)) appendLog(data.name + " 量程 " + formatNumber(value) + " V/div", data.name + " range " + formatNumber(value) + " V/div") }
    function setVerticalOffset(value) { const data = selectedChannel, bounded = Math.max(-5, Math.min(5, value)); if (channelStore.setRole(selectedChannelIndex, "verticalOffsetV", bounded)) appendLog(data.name + " 垂直偏移 " + formatNumber(bounded) + " V", data.name + " vertical offset " + formatNumber(bounded) + " V") }
    function setTimePerDiv(value) { if (timePerDivMs === value) return; const oldVisible = visibleTimeSeconds, center = latestSampleTime - historyOffsetSeconds - oldVisible / 2, wasFollowing = followLatest; timePerDivMs = value; if (wasFollowing) historyOffsetSeconds = 0; else { historyOffsetSeconds = latestSampleTime - (center + visibleTimeSeconds / 2); clampOffset() } appendLog("时基 " + formatNumber(value) + " ms/div", "Timebase " + formatNumber(value) + " ms/div") }
    function moveHistoryLeft() { const before = historyOffsetSeconds; historyOffsetSeconds += horizontalStepSeconds; clampOffset(); if (before !== historyOffsetSeconds) appendLog("历史位置移动至 " + formatDuration(historyOffsetSeconds), "History moved to " + formatDuration(historyOffsetSeconds)) }
    function moveHistoryRight() { if (historyOffsetSeconds <= 1e-9) return; historyOffsetSeconds -= horizontalStepSeconds; clampOffset(); appendLog(followLatest ? "已回到最新采样" : "历史位置移动至 " + formatDuration(historyOffsetSeconds), followLatest ? "Returned to latest samples" : "History moved to " + formatDuration(historyOffsetSeconds)) }
    function changeDisplayMode(mode) { if (displayMode !== mode) { displayMode = mode; appendLog(mode === "roll" ? "滚动模式已启用" : "更新模式已启用", mode === "roll" ? "Scroll mode enabled" : "Update mode enabled") } }
    function setGridVisible(value) { if (gridVisible !== value) { gridVisible = value; appendLog(value ? "网格已显示" : "网格已隐藏", value ? "Grid shown" : "Grid hidden") } }
    function startSimulation() { if (!simulationRunning) { simulationRunning = true; appendSimulationSamples(100); appendLog("64 通道模拟采样已启动（8 卡 × 8 通道）", "64-channel simulation started (8 boards x 8 channels)") } }
    function stopSimulation() { if (simulationRunning) { simulationRunning = false; appendLog("64 通道模拟采样已停止", "64-channel simulation stopped") } }
    function clearHistory() { channelStore.clearHistory(); historyOffsetSeconds = 0; followLatest = true; appendLog("64 通道历史缓存已清除", "64-channel history cleared") }
    function verticalFit() { const data = selectedChannel, end = latestSampleTime - historyOffsetSeconds, start = end - visibleTimeSeconds; let min = Infinity, max = -Infinity; const first = Math.max(0, Math.ceil((start - historyStartTime) * simulationSampleRate)), last = Math.min(channelStore.historyCount - 1, Math.floor((end - historyStartTime) * simulationSampleRate)); for (let i = first; i <= last; ++i) { const value = channelStore.historyValue(selectedChannelIndex, (channelStore.historyStartIndex + i) % channelStore.historyCapacity); if (value !== undefined) { min = Math.min(min, value); max = Math.max(max, value) } } if (!isFinite(min)) { appendLog(data.name + " 没有可用于垂直拟合的采样", data.name + " has no samples for vertical fit", "NOTICE"); return } const p2p = Math.max(.001, max - min), ranges = [.2, .5, 1, 2, 5]; let range = 5; for (let i = 0; i < ranges.length; ++i) if (p2p <= ranges[i] * 6.4) { range = ranges[i]; break } channelStore.setRole(selectedChannelIndex, "voltsPerDiv", range); channelStore.setRole(selectedChannelIndex, "verticalOffsetV", Math.max(-5, Math.min(5, -(max + min) / 2))); appendLog(data.name + " 已应用垂直拟合", data.name + " vertical fit applied") }
    function resetPositions() { const data = selectedChannel; const changed = data.verticalOffsetV !== data.defaultOffsetV || !followLatest; channelStore.setRole(selectedChannelIndex, "verticalOffsetV", data.defaultOffsetV); historyOffsetSeconds = 0; followLatest = true; if (changed) appendLog(data.name + " 位置已重置", data.name + " position reset") }

    ListModel { id: logModel }
    Timer { interval: 20; running: window.simulationRunning; repeat: true; onTriggered: window.appendSimulationSamples(100) }
    Component.onCompleted: appendLog("软件已就绪，64 通道模拟模式", "Application ready in 64-channel simulation mode")

    ColumnLayout {
        anchors.fill: parent; spacing: 0
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 54; color: "#15212c"; border.color: "#314252"
            RowLayout { anchors.fill: parent; anchors.margins: 18; Label { text: window.title; color: "#f0f6f8"; font.pixelSize: 18; font.bold: true } Item { Layout.fillWidth: true } Label { text: window.simulationRunning ? qsTr("\u91c7\u96c6: \u8fd0\u884c\u4e2d") : qsTr("\u91c7\u96c6: \u5df2\u505c\u6b62"); color: window.simulationRunning ? "#35d19b" : "#8fa3b4"; font.bold: true } Label { text: qsTr("\u6a21\u62df\u6a21\u5f0f"); color: "#19b4a5"; font.bold: true } }
        }
        RowLayout { Layout.fillWidth: true; Layout.fillHeight: true; spacing: 0
            // The navigation is intentionally a column of its own, including
            // alongside the log, so it remains stable while pages change.
            NavigationPanel { Layout.preferredWidth: 176; Layout.fillHeight: true; currentPage: window.currentPage; onPageRequested: page => { if (window.currentPage !== page) { window.currentPage = page; window.appendLog("已打开 " + page + " 页面", "Opened " + page + " page") } } }
            ColumnLayout { Layout.fillWidth: true; Layout.fillHeight: true; spacing: 0
                StackLayout { Layout.fillWidth: true; Layout.fillHeight: true; currentIndex: ["realtime", "channels", "acquisition", "recording", "system"].indexOf(window.currentPage)
                WaveformPanel { activePage: window.currentPage === "realtime"; channelStore: channelStore; selectedChannelIndex: window.selectedChannelIndex; simulationRunning: window.simulationRunning; displayMode: window.displayMode; gridVisible: window.gridVisible; timePerDivMs: window.timePerDivMs; latestSampleTime: window.latestSampleTime; historyOffsetSeconds: window.historyOffsetSeconds; samplePeriodSeconds: 1 / window.simulationSampleRate; onSelectedChannelRequested: index => window.setSelectedChannel(index); onStartRequested: window.startSimulation(); onStopRequested: window.stopSimulation(); onVerticalFitRequested: window.verticalFit(); onResetPositionsRequested: window.resetPositions(); onClearHistoryRequested: window.clearHistory() }
                ChannelSettingsPage { channelStore: channelStore; onChannelNameRequested: (index, name) => window.setChannelName(index, name); onChannelEnabledRequested: (index, value) => window.setChannelEnabled(index, value); onChannelVisibleRequested: (index, value) => window.setChannelVisible(index, value); onChannelColorRequested: (index, color) => window.setChannelColor(index, color) }
                AcquisitionSettingsPage { }
                RecordingPage { }
                SystemStatusPage { simulationRunning: window.simulationRunning }
                }
                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 110; color: "#121d27"; border.color: "#314252"
                    ColumnLayout { anchors.fill: parent; anchors.margins: 8; spacing: 3
                        RowLayout { Layout.fillWidth: true
                            Label { text: qsTr("\u8fd0\u884c\u65e5\u5fd7 / Event Log"); color: "#8fa3b4"; font.bold: true }
                            Item { Layout.fillWidth: true }
                            ComboBox {
                                id: logLanguageSelector
                                Layout.preferredWidth: 104
                                model: [qsTr("\u4e2d\u6587"), "English"]
                                currentIndex: window.logLanguage === "zh" ? 0 : 1
                                onActivated: index => window.logLanguage = index === 0 ? "zh" : "en"
                                contentItem: Text { leftPadding: 8; rightPadding: logLanguageSelector.indicator.width + 6; text: logLanguageSelector.displayText; color: "#d9e4ec"; font.pixelSize: 12; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                                background: Rectangle { color: "#1a2a36"; border.color: "#3a5263"; radius: 3 }
                            }
                        }
                        ListView { id: logView; Layout.fillWidth: true; Layout.fillHeight: true; model: logModel; clip: true; maximumFlickVelocity: 2000; delegate: Label { required property string message; height: 16; text: message; color: "#d9e4ec"; font.pixelSize: 12; elide: Text.ElideRight } }
                    }
                }
            }
            // Keep the parameter controls in their own continuous right column.
            // It shares the full height of the central workspace and event log,
            // eliminating the otherwise unused lower-right rectangle.
            ParameterPanel { visible: window.currentPage === "realtime"; Layout.preferredWidth: visible ? 270 : 0; Layout.fillHeight: true; channelStore: channelStore; selectedChannelIndex: window.selectedChannelIndex; timePerDivMs: window.timePerDivMs; horizontalStepSeconds: window.horizontalStepSeconds; displayMode: window.displayMode; gridVisible: window.gridVisible; hasSimulationData: window.hasSimulationData; historyOffsetSeconds: window.historyOffsetSeconds; maximumHistoryOffsetSeconds: window.maximumHistoryOffset(); onSelectedChannelRequested: index => window.setSelectedChannel(index); onVoltsPerDivRequested: value => window.setVoltsPerDiv(value); onTimePerDivRequested: value => window.setTimePerDiv(value); onVerticalOffsetRequested: value => window.setVerticalOffset(value); onDisplayModeRequested: mode => window.changeDisplayMode(mode); onGridVisibleRequested: value => window.setGridVisible(value); onMoveHistoryLeftRequested: window.moveHistoryLeft(); onMoveHistoryRightRequested: window.moveHistoryRight(); onResetHistoryPositionRequested: window.resetPositions() }
        }
    }
}
