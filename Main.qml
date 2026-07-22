pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

ApplicationWindow {
    id: window
    width: 1280
    height: 800
    minimumWidth: 980
    minimumHeight: 620
    visible: true
    title: qsTr("\u5de5\u4e1a\u591a\u901a\u9053\u793a\u6ce2\u8bb0\u5f55\u8f6f\u4ef6")
    color: "#101820"

    property string currentPage: "realtime"
    property bool simulationRunning: false
    property int selectedChannelIndex: 0
    property string displayMode: "update"
    property string interpolationMode: "auto"
    property bool gridVisible: true
    // Controls the language used for new runtime-log entries.  Acquisition and
    // waveform state are deliberately independent of this presentation option.
    property string logLanguage: "zh"
    property real timePerDivMs: 1.0
    property real sharedHistoryOffset: 0
    property bool followLatest: true
    property real sampleTimeSeconds: 0
    property real latestSampleTime: 0
    // The only applied acquisition configuration; the settings page keeps only a draft.
    // Board rates express hardware configuration. Simulation rate is separate.
    property var acquisitionConfig: ({
        mode: "continuous",
        boardEnabled: [true, false, false, false, false, false, false, false],
        channelEnabled: [true].concat(new Array(63).fill(false)),
        boardSampleRates: [5000, 5000, 5000, 5000, 5000, 5000, 5000, 5000],
        simulationStressRate: 5000
    })

    property int acquisitionConfigRevision: 0
    readonly property int simulationGenerationRate: acquisitionConfig.simulationStressRate
    readonly property int displayRefreshRate: acquisitionBackend.displayRefreshRate
    readonly property int enabledAcquisitionChannels: dataStore.enabledCount()
    property int simulationTick: 0
    // Monotonic wall-clock marker for batching.  It controls only how many
    // fixed-dt samples are appended in a display frame; signal time itself is
    // always advanced by exactly sampleCount / simulationGenerationRate.
    property double lastSimulationTickMs: 0
    // Carries fractional samples between timer ticks so every supported rate
    // has the correct long-term virtual sample count.
    property real simulationSampleRemainder: 0
    readonly property real visibleTimeSeconds: timePerDivMs * 10 / 1000
    readonly property real horizontalStepSeconds: timePerDivMs / 1000
    readonly property real sharedLatestTime: latestSampleTime
    readonly property real sharedWindowEnd: sharedLatestTime - sharedHistoryOffset
    readonly property real sharedWindowStart: sharedWindowEnd - visibleTimeSeconds
    // ChannelStore fills its ListModel during Component.onCompleted.  Depend on
    // its revision as well as the index so CH1 is refreshed after that first
    // initialization; otherwise it can remain an undefined stale value until
    // the user switches to a different channel.
    readonly property var selectedChannel: {
        const storeRevision = dataStore.revision
        return dataStore.channel(selectedChannelIndex)
    }
    readonly property bool hasSimulationData: realtimeData.historyCount > 0
    readonly property real historyStartTime: realtimeData.historyStartTime
    ChannelStore { id: dataStore }
    AcquisitionBackend { id: acquisitionBackend }
    RealtimeDataBackend { id: realtimeData }
    RecorderBackend {
        id: recorderBackend
        onEventLogged: (message, level) => window.appendLog(message, message, level)
    }
    PlaybackBackend {
        id: playbackBackend
        onEventLogged: (message, level) => window.appendLog(message, message, level)
    }

    function formatNumber(value) {
        return Number(value).toFixed(1).replace(/\.0$/, "")
    }

    function formatDuration(value) {
        return Math.abs(value) < 1 ? formatNumber(value * 1000) + " ms" : formatNumber(value) + " s"
    }

    function appendLog(chineseMessage, englishMessage, level) {
        const now = new Date()
        const stamp = [now.getHours(), now.getMinutes(), now.getSeconds()].map(value => String(value).padStart(2, "0")).join(":")
        const message = logLanguage === "en" ? (englishMessage || chineseMessage) : chineseMessage

        logModel.append({ message: "[" + stamp + "] [" + (level || "INFO") + "] " + message })
        if (logModel.count > 100)
            logModel.remove(0)
        logView.positionViewAtEnd()
    }

    function maximumHistoryOffset() {
        return Math.max(0, latestSampleTime - historyStartTime - visibleTimeSeconds)
    }

    function clampOffset() {
        // Horizontal position is a sample-grid coordinate.  This makes one
        // left/right action land on exactly one time division for every view,
        // rather than accumulating floating-point time offsets.
        const maximumSamples = Math.max(0, Math.floor(maximumHistoryOffset() * simulationGenerationRate + 1e-9))
        const requestedSamples = Math.round(sharedHistoryOffset * simulationGenerationRate)
        sharedHistoryOffset = Math.max(0, Math.min(requestedSamples, maximumSamples)) / simulationGenerationRate
        if (sharedHistoryOffset < 1e-9)
            sharedHistoryOffset = 0
        followLatest = sharedHistoryOffset === 0
    }

    function appendSimulationSamples(count) {
        if (count <= 0)
            return

        const interval = 1 / simulationGenerationRate
        realtimeData.appendSimulatedSamples(sampleTimeSeconds, interval, count, enabledChannelIds())
        if (recorderBackend.recording)
            recorderBackend.enqueueSimulatedBlock(sampleTimeSeconds, count)
        latestSampleTime = sampleTimeSeconds + (count - 1) * interval
        sampleTimeSeconds += count * interval

        if (followLatest)
            sharedHistoryOffset = 0
        else {
            sharedHistoryOffset = Math.min(maximumHistoryOffset(), sharedHistoryOffset + count * interval)
            clampOffset()
        }
    }

    function samplesForDuration(milliseconds) {
        const exactSamples = simulationGenerationRate * milliseconds / 1000 + simulationSampleRemainder
        const wholeSamples = Math.floor(exactSamples + 1e-12)
        simulationSampleRemainder = exactSamples - wholeSamples
        return wholeSamples
    }

    function enabledChannelIds() {
        const ids = []
        for (let index = 0; index < dataStore.channelCount; ++index)
            if (dataStore.channel(index).enabled)
                ids.push(index)
        return ids
    }

    function boardEnabledChannelCount(board) {
        let count = 0
        for (let local = 0; local < 8; ++local)
            if (dataStore.channel(board * 8 + local).enabled)
                ++count
        return count
    }

    function estimatedHardwareThroughput() {
        let bytes = 0
        for (let board = 0; board < 8; ++board)
            bytes += boardEnabledChannelCount(board) * acquisitionConfig.boardSampleRates[board] * 4
        return bytes
    }
    function estimatedSimulationThroughput() { return enabledAcquisitionChannels * simulationGenerationRate * 4 }

    function startRecording() {
        const channels = enabledChannelIds()
        if (!simulationRunning) {
            appendLog("录制未开始：请先开始采集。", "Recording did not start: start acquisition first.", "NOTICE")
            return
        }
        if (!recorderBackend.startRecording(simulationGenerationRate, channels, acquisitionConfig.mode, simulationRunning))
            appendLog("录制未开始：" + recorderBackend.statusDetail, "Recording did not start: " + recorderBackend.statusDetail, "ERROR")
    }

    function runSimulationTick() {
        const nowMs = Date.now()
        const elapsedMs = lastSimulationTickMs > 0
                ? Math.max(1, Math.min(100, nowMs - lastSimulationTickMs))
                : 1
        lastSimulationTickMs = nowMs
        ++simulationTick

        if (acquisitionConfig.mode === "burst") {
            if (simulationTick % 5 === 0)
                appendSimulationSamples(samplesForDuration(100))
        } else {
            // Do not manufacture a 20 ms acquisition block for every paint.
            // That made the 50 Hz UI cadence sample CH1…CH8 at a deterministic
            // phase relationship and produced a channel-number-dependent
            // display alias.  Batch size follows elapsed time only; every
            // stored sample still uses the same fixed dt = 1 / sampleRate.
            appendSimulationSamples(samplesForDuration(elapsedMs))
        }
    }

    function validateAcquisitionConfiguration(config) {
        if (config.mode !== "continuous" && config.mode !== "burst")
            return "请选择有效的采集模式。"
        if (!config.boardEnabled.some(value => value))
            return "请至少启用一张采集板卡。"
        if (!config.channelEnabled.some(value => value))
            return "请至少启用一个采集通道。"

        for (let i = 0; i < config.channelEnabled.length; ++i) {
            if (config.channelEnabled[i] && !config.boardEnabled[Math.floor(i / 8)])
                return "CH" + (i + 1) + " 已启用，但所属板卡 " + (Math.floor(i / 8) + 1) + " 未启用。"
        }

        if (!Array.isArray(config.boardSampleRates) || config.boardSampleRates.length !== 8)
            return "板卡采样率配置无效。"
        for (let board = 0; board < 8; ++board) {
            if (!acquisitionBackend.supportsHardwareRate(board, config.boardSampleRates[board]))
                return "板卡 " + (board + 1) + " 的采样率不在后端能力表中。"
        }
        if (!acquisitionBackend.supportsSimulationStressRate(config.simulationStressRate))
            return "模拟压力测试采样率不在后端允许档位中。"

        return ""
    }

    function applyAcquisitionConfiguration(config) {
        if (simulationRunning || recorderBackend.recording) {
            appendLog("采集运行中，不能修改采样率、模式、板卡或采集通道；请先停止采集。", "Acquisition is running. Stop it before changing key configuration.", "NOTICE")
            return false
        }

        const error = validateAcquisitionConfiguration(config)
        if (error.length) {
            appendLog("配置校验失败：" + error, "Configuration validation failed: " + error, "ERROR")
            return false
        }

        acquisitionConfig = {
            mode: config.mode,
            boardEnabled: config.boardEnabled.slice(),
            channelEnabled: config.channelEnabled.slice(),
            boardSampleRates: config.boardSampleRates.slice(),
            simulationStressRate: config.simulationStressRate
        }
        ++acquisitionConfigRevision
        // Board selection is a sampling gate as well as a UI choice.  A channel
        // can never remain active in the simulator when its board is disabled.
        for (let i = 0; i < dataStore.channelCount; ++i)
            dataStore.setRole(i, "enabled", acquisitionConfig.channelEnabled[i] && acquisitionConfig.boardEnabled[Math.floor(i / 8)])

        if (!dataStore.channel(selectedChannelIndex).enabled) {
            for (let i = 0; i < dataStore.channelCount; ++i) {
                if (dataStore.channel(i).enabled) {
                    setSelectedChannel(i)
                    break
                }
            }
        }

        appendLog("采集配置已应用：" + enabledAcquisitionChannels + " 路，模拟生成 " + simulationGenerationRate + " S/s，硬件预计吞吐 " + estimatedHardwareThroughput() + " B/s。", "Acquisition configuration applied: " + enabledAcquisitionChannels + " channels, simulation " + simulationGenerationRate + " S/s, hardware throughput " + estimatedHardwareThroughput() + " B/s.")
        return true
    }
    function setSelectedChannel(index) {
        if (index !== selectedChannelIndex) {
            selectedChannelIndex = index
            dataStore.selectChannel(index)
            const name = dataStore.channel(index).name
            appendLog(name + " 已选中", name + " selected")
        }
    }

    function setChannelEnabled(index, enabled) {
        if (simulationRunning) {
            appendLog("采集运行中，不能修改采集通道；请先停止采集。", "Acquisition is running. Stop it before changing acquisition channels.", "NOTICE")
            return
        }

        const next = {
            mode: acquisitionConfig.mode,
            boardEnabled: acquisitionConfig.boardEnabled.slice(),
            channelEnabled: acquisitionConfig.channelEnabled.slice(),
            boardSampleRates: acquisitionConfig.boardSampleRates.slice(),
            simulationStressRate: acquisitionConfig.simulationStressRate
        }
        next.channelEnabled[index] = enabled
        if (enabled)
            next.boardEnabled[Math.floor(index / 8)] = true
        applyAcquisitionConfiguration(next)
    }

    function setChannelVisible(index, visible) {
        const data = dataStore.channel(index)

        if (visible && !data.visible && dataStore.visibleCount() >= 8) {
            appendLog("实时页面最多显示 8 路波形；请先隐藏一个显示通道。", "Real-time page can show at most 8 waveforms; hide one first.", "NOTICE")
            return
        }

        if (dataStore.setRole(index, "visible", visible))
            appendLog(data.name + (visible ? " 已显示" : " 已隐藏"), data.name + (visible ? " shown" : " hidden"))
    }

    function toggleChannelVisible(index) {
        const visible = dataStore.channel(index).visible
        setChannelVisible(index, !visible)

        if (!visible) {
            setSelectedChannel(index)
        } else if (selectedChannelIndex === index) {
            for (let i = 0; i < dataStore.channelModel.count; ++i) {
                if (dataStore.channel(i).visible) {
                    setSelectedChannel(i)
                    break
                }
            }
        }
    }

    function setChannelName(index, name) {
        const clean = name.trim()

        if (clean.length && dataStore.setRole(index, "name", clean))
            appendLog("CH" + dataStore.channel(index).channelId + " 已重命名为 " + clean, "CH" + dataStore.channel(index).channelId + " renamed to " + clean)
    }

    function setChannelColor(index, color) {
        if (dataStore.setRole(index, "color", color)) {
            const name = dataStore.channel(index).name
            appendLog(name + " 颜色已更改", name + " color changed")
        }
    }

    function setVoltsPerDiv(value) {
        const data = selectedChannel

        if (!data)
            return

        if (dataStore.setRole(selectedChannelIndex, "voltsPerDiv", value))
            appendLog(data.name + " 量程 " + formatNumber(value) + " V/div", data.name + " range " + formatNumber(value) + " V/div")
    }

    function setVerticalOffset(value) {
        const data = selectedChannel

        if (!data)
            return

        const bounded = Math.max(-5, Math.min(5, value))

        if (dataStore.setRole(selectedChannelIndex, "verticalOffsetV", bounded))
            appendLog(data.name + " 垂直偏移 " + formatNumber(bounded) + " V", data.name + " vertical offset " + formatNumber(bounded) + " V")
    }
    function logFrequencyVerification() { if (realtimeData.historyCount < 3) return; const entries = []; for (let index = 0; index < dataStore.channelCount && entries.length < 8; ++index) if (dataStore.channel(index).enabled) entries.push(dataStore.channel(index).name + "=" + formatNumber(realtimeData.zeroCrossingFrequency(index, latestSampleTime, .1)) + " Hz"); if (entries.length) appendLog("频率校验（固定 100 ms）：" + entries.join("，"), "Frequency check (fixed 100 ms): " + entries.join(", ")) }
    function setTimePerDiv(value) { if (timePerDivMs === value) return; const oldVisible = visibleTimeSeconds, center = sharedLatestTime - sharedHistoryOffset - oldVisible / 2, wasFollowing = followLatest; timePerDivMs = value; if (wasFollowing) sharedHistoryOffset = 0; else { sharedHistoryOffset = sharedLatestTime - (center + visibleTimeSeconds / 2); clampOffset() } appendLog("时基 " + formatNumber(value) + " ms/div", "Timebase " + formatNumber(value) + " ms/div"); logFrequencyVerification() }
    function moveHistoryLeft() { const before = sharedHistoryOffset, stepSamples = Math.max(1, Math.round(horizontalStepSeconds * simulationGenerationRate)); sharedHistoryOffset += stepSamples / simulationGenerationRate; clampOffset(); if (before !== sharedHistoryOffset) appendLog("历史位置移动至 " + formatDuration(sharedHistoryOffset) + "（" + stepSamples + " 样本 / 1 div）", "History moved to " + formatDuration(sharedHistoryOffset) + " (" + stepSamples + " samples / 1 div)") }
    function moveHistoryRight() { if (sharedHistoryOffset <= 1e-9) return; const stepSamples = Math.max(1, Math.round(horizontalStepSeconds * simulationGenerationRate)); sharedHistoryOffset -= stepSamples / simulationGenerationRate; clampOffset(); appendLog(followLatest ? "已回到最新采样" : "历史位置移动至 " + formatDuration(sharedHistoryOffset) + "（" + stepSamples + " 样本 / 1 div）", followLatest ? "Returned to latest samples" : "History moved to " + formatDuration(sharedHistoryOffset) + " (" + stepSamples + " samples / 1 div)") }
    function changeDisplayMode(mode) { if (displayMode !== mode) { displayMode = mode; appendLog(mode === "roll" ? "滚动模式已启用" : "更新模式已启用", mode === "roll" ? "Scroll mode enabled" : "Update mode enabled") } }
    function setGridVisible(value) { if (gridVisible !== value) { gridVisible = value; appendLog(value ? "网格已显示" : "网格已隐藏", value ? "Grid shown" : "Grid hidden") } }
    function startSimulation() { if (!simulationRunning) { const error = validateAcquisitionConfiguration(acquisitionConfig); if (error.length) { appendLog("配置校验失败：" + error, "Configuration validation failed: " + error, "ERROR"); return } simulationTick = 0; simulationSampleRemainder = 0; lastSimulationTickMs = Date.now(); simulationRunning = true; appendSimulationSamples(samplesForDuration(acquisitionConfig.mode === "burst" ? 100 : 1)); appendLog("模拟采集已启动：模拟生成 " + simulationGenerationRate + " S/s，" + enabledAcquisitionChannels + " 路，" + (acquisitionConfig.mode === "burst" ? "突发模式" : "连续模式") + "。", "Simulation started: " + simulationGenerationRate + " S/s, " + enabledAcquisitionChannels + " channels, " + acquisitionConfig.mode + " mode.") } }
    function stopSimulation() { if (simulationRunning) { simulationRunning = false; lastSimulationTickMs = 0; if (recorderBackend.recording) { appendLog("采集已停止，正在安全停止录制。", "Acquisition stopped; safely stopping recording.", "NOTICE"); recorderBackend.stopRecording() } appendLog("模拟采集已停止。", "Simulation stopped.") } }
    function clearHistory() { realtimeData.clearHistory(); sharedHistoryOffset = 0; followLatest = true; appendLog("64 通道历史缓存已清除", "64-channel history cleared") }
    function verticalFit() { const data = selectedChannel, rangeData = realtimeData.channelRange(selectedChannelIndex, sharedWindowStart, sharedWindowEnd); const min = rangeData.minimum, max = rangeData.maximum; if (!rangeData.valid) { appendLog(data.name + " 没有可用于垂直拟合的采样", data.name + " has no samples for vertical fit", "NOTICE"); return } const p2p = Math.max(.001, max - min), ranges = [.2, .5, 1, 2, 5]; let range = 5; for (let i = 0; i < ranges.length; ++i) if (p2p <= ranges[i] * 3.2) { range = ranges[i]; break } dataStore.setRole(selectedChannelIndex, "voltsPerDiv", range); dataStore.setRole(selectedChannelIndex, "verticalOffsetV", Math.max(-5, Math.min(5, -(max + min) / 2))); appendLog(data.name + " 已应用垂直拟合（保留边界）", data.name + " vertical fit applied with viewport margin") }
    function resetPositions() { const data = selectedChannel; if (!data) return; const changed = data.verticalOffsetV !== data.defaultOffsetV || !followLatest; dataStore.setRole(selectedChannelIndex, "verticalOffsetV", data.defaultOffsetV); sharedHistoryOffset = 0; followLatest = true; if (changed) appendLog(data.name + " 位置已重置", data.name + " position reset") }

    ListModel { id: logModel }
    // Display refresh stays independent from generated sample rate and time/div.
    Timer { interval: Math.round(1000 / window.displayRefreshRate); running: window.simulationRunning; repeat: true; onTriggered: window.runSimulationTick() }
    Component.onCompleted: appendLog("软件已就绪，64 通道模拟模式", "Application ready in 64-channel simulation mode")

    ColumnLayout {
        anchors.fill: parent; spacing: 0
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 54; color: "#15212c"; border.color: "#314252"
            RowLayout { anchors.fill: parent; anchors.margins: 18; Label { text: window.title; color: "#f0f6f8"; font.pixelSize: 18; font.bold: true } Item { Layout.fillWidth: true } Label { text: (window.currentPage === "playback" ? qsTr("\u5b9e\u65f6\u91c7\u96c6\uff1a") : qsTr("\u91c7\u96c6: ")) + (window.simulationRunning ? qsTr("\u8fd0\u884c\u4e2d") : qsTr("\u5df2\u505c\u6b62")); color: window.simulationRunning ? "#35d19b" : "#8fa3b4"; opacity: window.currentPage === "playback" ? 0.7 : 1.0; font.bold: true } Label { text: qsTr("\u6a21\u62df\u751f\u6210\uff1a") + window.simulationGenerationRate + " S/s · " + qsTr("\u91c7\u96c6\u901a\u9053\uff1a") + window.enabledAcquisitionChannels + qsTr(" \u8def"); color: "#d9e4ec"; opacity: window.currentPage === "playback" ? 0.7 : 1.0; font.bold: true } Label { text: window.acquisitionConfig.mode === "burst" ? "Burst" : "Continuous"; color: "#19b4a5"; opacity: window.currentPage === "playback" ? 0.7 : 1.0; font.bold: true } }
        }
        RowLayout { Layout.fillWidth: true; Layout.fillHeight: true; spacing: 0
            // The navigation is intentionally a column of its own, including
            // alongside the log, so it remains stable while pages change.
            NavigationPanel { Layout.preferredWidth: 176; Layout.fillHeight: true; currentPage: window.currentPage; onPageRequested: page => { if (window.currentPage !== page) { window.currentPage = page; window.appendLog("已打开 " + page + " 页面", "Opened " + page + " page") } } }
            ColumnLayout { Layout.fillWidth: true; Layout.fillHeight: true; spacing: 0
                StackLayout { Layout.fillWidth: true; Layout.fillHeight: true; currentIndex: ["realtime", "playback", "channels", "acquisition", "recording", "system"].indexOf(window.currentPage)
                WaveformPanel { id: realtimeWaveform; activePage: window.currentPage === "realtime"; channelStore: dataStore; realtimeData: realtimeData; selectedChannelIndex: window.selectedChannelIndex; simulationRunning: window.simulationRunning; displayMode: window.displayMode; gridVisible: window.gridVisible; timePerDivMs: window.timePerDivMs; sharedWindowStart: window.sharedWindowStart; sharedWindowEnd: window.sharedWindowEnd; sharedLatestTime: window.sharedLatestTime; sharedHistoryOffset: window.sharedHistoryOffset; samplePeriodSeconds: 1 / window.simulationGenerationRate; interpolationMode: window.interpolationMode; onSelectedChannelRequested: index => window.setSelectedChannel(index); onStartRequested: window.startSimulation(); onStopRequested: window.stopSimulation(); onVerticalFitRequested: window.verticalFit(); onResetPositionsRequested: window.resetPositions(); onClearHistoryRequested: window.clearHistory() }
                PlaybackPage { playback: playbackBackend }
                ChannelSettingsPage { channelStore: dataStore; onChannelNameRequested: (index, name) => window.setChannelName(index, name); onChannelVisibleRequested: (index, value) => window.setChannelVisible(index, value); onChannelColorRequested: (index, color) => window.setChannelColor(index, color) }
                AcquisitionSettingsPage { acquisitionConfig: window.acquisitionConfig; capabilityBackend: acquisitionBackend; configurationRevision: window.acquisitionConfigRevision; simulationRunning: window.simulationRunning || recorderBackend.recording; onApplyRequested: config => window.applyAcquisitionConfiguration(config); onStopAndApplyRequested: config => { if (window.simulationRunning) window.stopSimulation(); window.applyAcquisitionConfiguration(config) } }
                RecordingPage { recorder: recorderBackend; sampleRate: window.simulationGenerationRate; enabledChannelCount: window.enabledAcquisitionChannels; acquisitionMode: window.acquisitionConfig.mode; simulationRunning: window.simulationRunning; channelIds: window.enabledChannelIds(); onStartRecordingRequested: window.startRecording() }
                SystemStatusPage { simulationRunning: window.simulationRunning; simulationGenerationRate: window.simulationGenerationRate; displayRefreshRate: window.displayRefreshRate; estimatedHardwareThroughput: window.estimatedHardwareThroughput(); estimatedSimulationThroughput: window.estimatedSimulationThroughput(); acquisitionMode: window.acquisitionConfig.mode; enabledChannelCount: window.enabledAcquisitionChannels; enabledBoardCount: window.acquisitionConfig.boardEnabled.filter(value => value).length }
                }
                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 94; color: "#121d27"; border.color: "#314252"
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
            ParameterPanel { visible: window.currentPage === "realtime"; Layout.preferredWidth: visible ? 270 : 0; Layout.fillHeight: true; channelStore: dataStore; selectedChannelIndex: window.selectedChannelIndex; timePerDivMs: window.timePerDivMs; horizontalStepSeconds: window.horizontalStepSeconds; displayMode: window.displayMode; interpolationMode: window.interpolationMode; interpolationAvailable: realtimeWaveform.interpolationAvailable; gridVisible: window.gridVisible; hasSimulationData: window.hasSimulationData; historyOffsetSeconds: window.sharedHistoryOffset; maximumHistoryOffsetSeconds: window.maximumHistoryOffset(); onSelectedChannelRequested: index => window.setSelectedChannel(index); onVoltsPerDivRequested: value => window.setVoltsPerDiv(value); onTimePerDivRequested: value => window.setTimePerDiv(value); onVerticalOffsetRequested: value => window.setVerticalOffset(value); onDisplayModeRequested: mode => window.changeDisplayMode(mode); onInterpolationModeRequested: mode => window.interpolationMode = mode; onGridVisibleRequested: value => window.setGridVisible(value); onMoveHistoryLeftRequested: window.moveHistoryLeft(); onMoveHistoryRightRequested: window.moveHistoryRight(); onResetHistoryPositionRequested: window.resetPositions() }
        }
    }
}
