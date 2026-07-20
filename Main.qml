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
    // The only applied acquisition configuration; the settings page keeps only a draft.
    property var acquisitionConfig: ({ sampleRate: 5000, mode: "continuous", boardEnabled: [true, false, false, false, false, false, false, false], channelEnabled: [true].concat(new Array(63).fill(false)) })
    property int acquisitionConfigRevision: 0
    readonly property int simulationSampleRate: acquisitionConfig.sampleRate
    readonly property int enabledAcquisitionChannels: channelStore.enabledCount()
    property int simulationTick: 0
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
    function appendSimulationSamples(count) { if (count <= 0) return; const interval = 1 / simulationSampleRate; channelStore.appendSamples(sampleTimeSeconds, interval, count); latestSampleTime = sampleTimeSeconds + (count - 1) * interval; sampleTimeSeconds += count * interval; if (followLatest) historyOffsetSeconds = 0; else historyOffsetSeconds = Math.min(maximumHistoryOffset(), historyOffsetSeconds + count * interval) }
    function samplesForDuration(milliseconds) { return Math.max(1, Math.round(simulationSampleRate * milliseconds / 1000)) }
    function runSimulationTick() { ++simulationTick; if (acquisitionConfig.mode === "burst") { if (simulationTick % 5 === 0) appendSimulationSamples(samplesForDuration(100)) } else appendSimulationSamples(samplesForDuration(20)) }
    function validateAcquisitionConfiguration(config) {
        if (!Number.isInteger(config.sampleRate) || config.sampleRate < 100 || config.sampleRate > 1000000) return "采样率必须是 100 至 1,000,000 S/s 的整数。"
        if (config.mode !== "continuous" && config.mode !== "burst") return "请选择有效的采集模式。"
        if (!config.boardEnabled.some(value => value)) return "请至少启用一张采集板卡。"
        if (!config.channelEnabled.some(value => value)) return "请至少启用一个采集通道。"
        for (let i = 0; i < config.channelEnabled.length; ++i) if (config.channelEnabled[i] && !config.boardEnabled[Math.floor(i / 8)]) return "CH" + (i + 1) + " 已启用，但所属板卡 " + (Math.floor(i / 8) + 1) + " 未启用。"
        return ""
    }
    function applyAcquisitionConfiguration(config) {
        if (simulationRunning) { appendLog("采集运行中，不能修改采样率、模式、板卡或采集通道；请先停止采集。", "Acquisition is running. Stop it before changing key configuration.", "NOTICE"); return false }
        const error = validateAcquisitionConfiguration(config)
        if (error.length) { appendLog("配置校验失败：" + error, "Configuration validation failed: " + error, "ERROR"); return false }
        acquisitionConfig = { sampleRate: config.sampleRate, mode: config.mode, boardEnabled: config.boardEnabled.slice(), channelEnabled: config.channelEnabled.slice() }; ++acquisitionConfigRevision
        // Board selection is a sampling gate as well as a UI choice.  A channel
        // can never remain active in the simulator when its board is disabled.
        for (let i = 0; i < channelStore.channelCount; ++i) channelStore.setRole(i, "enabled", acquisitionConfig.channelEnabled[i] && acquisitionConfig.boardEnabled[Math.floor(i / 8)])
        if (!channelStore.channel(selectedChannelIndex).enabled) for (let i = 0; i < channelStore.channelCount; ++i) if (channelStore.channel(i).enabled) { setSelectedChannel(i); break }
        appendLog("采集配置已应用：" + simulationSampleRate + " S/s，" + (acquisitionConfig.mode === "burst" ? "突发采集" : "连续采集") + "，" + enabledAcquisitionChannels + " 路通道。", "Acquisition configuration applied: " + simulationSampleRate + " S/s, " + acquisitionConfig.mode + ", " + enabledAcquisitionChannels + " channels.")
        return true
    }
    function setSelectedChannel(index) { if (index !== selectedChannelIndex) { selectedChannelIndex = index; channelStore.selectChannel(index); const name = channelStore.channel(index).name; appendLog(name + " 已选中", name + " selected") } }
    function setChannelEnabled(index, enabled) { if (simulationRunning) { appendLog("采集运行中，不能修改采集通道；请先停止采集。", "Acquisition is running. Stop it before changing acquisition channels.", "NOTICE"); return } const next = { sampleRate: acquisitionConfig.sampleRate, mode: acquisitionConfig.mode, boardEnabled: acquisitionConfig.boardEnabled.slice(), channelEnabled: acquisitionConfig.channelEnabled.slice() }; next.channelEnabled[index] = enabled; if (enabled) next.boardEnabled[Math.floor(index / 8)] = true; applyAcquisitionConfiguration(next) }
    function setChannelVisible(index, visible) { const data = channelStore.channel(index); if (visible && !data.visible && channelStore.visibleCount() >= 8) { appendLog("实时页面最多显示 8 路波形；请先隐藏一个显示通道。", "Real-time page can show at most 8 waveforms; hide one first.", "NOTICE"); return } if (channelStore.setRole(index, "visible", visible)) appendLog(data.name + (visible ? " 已显示" : " 已隐藏"), data.name + (visible ? " shown" : " hidden")) }
    function toggleChannelVisible(index) { const visible = channelStore.channel(index).visible; setChannelVisible(index, !visible); if (!visible) setSelectedChannel(index); else if (selectedChannelIndex === index) { for (let i = 0; i < channelStore.channelModel.count; ++i) if (channelStore.channel(i).visible) { setSelectedChannel(i); break } } }
    function setChannelName(index, name) { const clean = name.trim(); if (clean.length && channelStore.setRole(index, "name", clean)) appendLog("CH" + channelStore.channel(index).channelId + " 已重命名为 " + clean, "CH" + channelStore.channel(index).channelId + " renamed to " + clean) }
    function setChannelColor(index, color) { if (channelStore.setRole(index, "color", color)) { const name = channelStore.channel(index).name; appendLog(name + " 颜色已更改", name + " color changed") } }
    function setVoltsPerDiv(value) { const data = selectedChannel; if (channelStore.setRole(selectedChannelIndex, "voltsPerDiv", value)) appendLog(data.name + " 量程 " + formatNumber(value) + " V/div", data.name + " range " + formatNumber(value) + " V/div") }
    function setVerticalOffset(value) { const data = selectedChannel, bounded = Math.max(-5, Math.min(5, value)); if (channelStore.setRole(selectedChannelIndex, "verticalOffsetV", bounded)) appendLog(data.name + " 垂直偏移 " + formatNumber(bounded) + " V", data.name + " vertical offset " + formatNumber(bounded) + " V") }
    function logFrequencyVerification() { if (channelStore.historyCount < 3) return; const entries = []; for (let index = 0; index < channelStore.channelCount && entries.length < 8; ++index) if (channelStore.channel(index).enabled) entries.push(channelStore.channel(index).name + "=" + formatNumber(channelStore.zeroCrossingFrequency(index, latestSampleTime, .1)) + " Hz"); if (entries.length) appendLog("频率校验（固定 100 ms）：" + entries.join("，"), "Frequency check (fixed 100 ms): " + entries.join(", ")) }
    function setTimePerDiv(value) { if (timePerDivMs === value) return; const oldVisible = visibleTimeSeconds, center = latestSampleTime - historyOffsetSeconds - oldVisible / 2, wasFollowing = followLatest; timePerDivMs = value; if (wasFollowing) historyOffsetSeconds = 0; else { historyOffsetSeconds = latestSampleTime - (center + visibleTimeSeconds / 2); clampOffset() } appendLog("时基 " + formatNumber(value) + " ms/div", "Timebase " + formatNumber(value) + " ms/div"); logFrequencyVerification() }
    function moveHistoryLeft() { const before = historyOffsetSeconds; historyOffsetSeconds += horizontalStepSeconds; clampOffset(); if (before !== historyOffsetSeconds) appendLog("历史位置移动至 " + formatDuration(historyOffsetSeconds), "History moved to " + formatDuration(historyOffsetSeconds)) }
    function moveHistoryRight() { if (historyOffsetSeconds <= 1e-9) return; historyOffsetSeconds -= horizontalStepSeconds; clampOffset(); appendLog(followLatest ? "已回到最新采样" : "历史位置移动至 " + formatDuration(historyOffsetSeconds), followLatest ? "Returned to latest samples" : "History moved to " + formatDuration(historyOffsetSeconds)) }
    function changeDisplayMode(mode) { if (displayMode !== mode) { displayMode = mode; appendLog(mode === "roll" ? "滚动模式已启用" : "更新模式已启用", mode === "roll" ? "Scroll mode enabled" : "Update mode enabled") } }
    function setGridVisible(value) { if (gridVisible !== value) { gridVisible = value; appendLog(value ? "网格已显示" : "网格已隐藏", value ? "Grid shown" : "Grid hidden") } }
    function startSimulation() { if (!simulationRunning) { const error = validateAcquisitionConfiguration(acquisitionConfig); if (error.length) { appendLog("配置校验失败：" + error, "Configuration validation failed: " + error, "ERROR"); return } simulationTick = 0; simulationRunning = true; appendSimulationSamples(samplesForDuration(acquisitionConfig.mode === "burst" ? 100 : 20)); appendLog("模拟采集已启动：" + simulationSampleRate + " S/s，" + enabledAcquisitionChannels + " 路，" + (acquisitionConfig.mode === "burst" ? "突发模式" : "连续模式") + "。", "Simulation started: " + simulationSampleRate + " S/s, " + enabledAcquisitionChannels + " channels, " + acquisitionConfig.mode + " mode.") } }
    function stopSimulation() { if (simulationRunning) { simulationRunning = false; appendLog("模拟采集已停止。", "Simulation stopped.") } }
    function clearHistory() { channelStore.clearHistory(); historyOffsetSeconds = 0; followLatest = true; appendLog("64 通道历史缓存已清除", "64-channel history cleared") }
    function verticalFit() { const data = selectedChannel, end = latestSampleTime - historyOffsetSeconds, start = end - visibleTimeSeconds; let min = Infinity, max = -Infinity; const first = channelStore.firstLogicalIndexAtOrAfter(start), last = channelStore.lastLogicalIndexAtOrBefore(end); for (let i = first; i <= last; ++i) { const value = channelStore.historyValue(selectedChannelIndex, (channelStore.historyStartIndex + i) % channelStore.historyCapacity); if (value !== undefined) { min = Math.min(min, value); max = Math.max(max, value) } } if (!isFinite(min)) { appendLog(data.name + " 没有可用于垂直拟合的采样", data.name + " has no samples for vertical fit", "NOTICE"); return } const p2p = Math.max(.001, max - min), ranges = [.2, .5, 1, 2, 5]; let range = 5; for (let i = 0; i < ranges.length; ++i) if (p2p <= ranges[i] * 6.4) { range = ranges[i]; break } channelStore.setRole(selectedChannelIndex, "voltsPerDiv", range); channelStore.setRole(selectedChannelIndex, "verticalOffsetV", Math.max(-5, Math.min(5, -(max + min) / 2))); appendLog(data.name + " 已应用垂直拟合", data.name + " vertical fit applied") }
    function resetPositions() { const data = selectedChannel; const changed = data.verticalOffsetV !== data.defaultOffsetV || !followLatest; channelStore.setRole(selectedChannelIndex, "verticalOffsetV", data.defaultOffsetV); historyOffsetSeconds = 0; followLatest = true; if (changed) appendLog(data.name + " 位置已重置", data.name + " position reset") }

    ListModel { id: logModel }
    Timer { interval: 20; running: window.simulationRunning; repeat: true; onTriggered: window.runSimulationTick() }
    Component.onCompleted: appendLog("软件已就绪，64 通道模拟模式", "Application ready in 64-channel simulation mode")

    ColumnLayout {
        anchors.fill: parent; spacing: 0
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 54; color: "#15212c"; border.color: "#314252"
            RowLayout { anchors.fill: parent; anchors.margins: 18; Label { text: window.title; color: "#f0f6f8"; font.pixelSize: 18; font.bold: true } Item { Layout.fillWidth: true } Label { text: window.simulationRunning ? qsTr("\u91c7\u96c6: \u8fd0\u884c\u4e2d") : qsTr("\u91c7\u96c6: \u5df2\u505c\u6b62"); color: window.simulationRunning ? "#35d19b" : "#8fa3b4"; font.bold: true } Label { text: window.simulationSampleRate + " S/s · " + window.enabledAcquisitionChannels + " CH"; color: "#d9e4ec"; font.bold: true } Label { text: window.acquisitionConfig.mode === "burst" ? "Burst" : "Continuous"; color: "#19b4a5"; font.bold: true } }
        }
        RowLayout { Layout.fillWidth: true; Layout.fillHeight: true; spacing: 0
            // The navigation is intentionally a column of its own, including
            // alongside the log, so it remains stable while pages change.
            NavigationPanel { Layout.preferredWidth: 176; Layout.fillHeight: true; currentPage: window.currentPage; onPageRequested: page => { if (window.currentPage !== page) { window.currentPage = page; window.appendLog("已打开 " + page + " 页面", "Opened " + page + " page") } } }
            ColumnLayout { Layout.fillWidth: true; Layout.fillHeight: true; spacing: 0
                StackLayout { Layout.fillWidth: true; Layout.fillHeight: true; currentIndex: ["realtime", "channels", "acquisition", "recording", "system"].indexOf(window.currentPage)
                WaveformPanel { activePage: window.currentPage === "realtime"; channelStore: channelStore; selectedChannelIndex: window.selectedChannelIndex; simulationRunning: window.simulationRunning; displayMode: window.displayMode; gridVisible: window.gridVisible; timePerDivMs: window.timePerDivMs; latestSampleTime: window.latestSampleTime; historyOffsetSeconds: window.historyOffsetSeconds; samplePeriodSeconds: 1 / window.simulationSampleRate; onSelectedChannelRequested: index => window.setSelectedChannel(index); onStartRequested: window.startSimulation(); onStopRequested: window.stopSimulation(); onVerticalFitRequested: window.verticalFit(); onResetPositionsRequested: window.resetPositions(); onClearHistoryRequested: window.clearHistory() }
                ChannelSettingsPage { channelStore: channelStore; onChannelNameRequested: (index, name) => window.setChannelName(index, name); onChannelVisibleRequested: (index, value) => window.setChannelVisible(index, value); onChannelColorRequested: (index, color) => window.setChannelColor(index, color) }
                AcquisitionSettingsPage { acquisitionConfig: window.acquisitionConfig; configurationRevision: window.acquisitionConfigRevision; simulationRunning: window.simulationRunning; onApplyRequested: config => window.applyAcquisitionConfiguration(config) }
                RecordingPage { }
                SystemStatusPage { simulationRunning: window.simulationRunning; sampleRate: window.simulationSampleRate; acquisitionMode: window.acquisitionConfig.mode; enabledChannelCount: window.enabledAcquisitionChannels; enabledBoardCount: window.acquisitionConfig.boardEnabled.filter(value => value).length }
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
