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
    required property bool manualDisplayPaused
    required property bool singleTriggerFrozen
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
    property string cursorMode: "off" // off, time, voltage, both
    property real timeCursor1: 0
    property real timeCursor2: 0
    property real liveTimeCursor1Position: 1 / 3
    property real liveTimeCursor2Position: 2 / 3
    property real frozenTimeCursor1Position: 1 / 3
    property real frozenTimeCursor2Position: 2 / 3
    property real voltageCursor1: 0
    property real voltageCursor2: 0
    property int nextMeasurementTaskId: 1
    property string draftMeasurementCategory: "amplitude"
    property string draftMeasurementRange: "visible"
    property real draftLatestWindowSeconds: 0.1
    property var draftMeasurementChannels: []
    property var draftMeasurementItems: []
    property var draftMeasurementItemsByCategory: ({ amplitude: [], time: [], count: [] })
    property string draftMeasurementStatisticsMode: "full" // current or full
    property string measurementSearch: ""
    property int measurementChannelBoard: 0
    property bool timeAdvancedExpanded: false
    property string timeThresholdMode: "auto"
    property real timeManualThreshold: 0
    property real timeManualLowThreshold: -0.5
    property real timeManualHighThreshold: 0.5
    property real timeHysteresis: 0.05
    property string timeEdge: "rising"
    property real timeAutoThreshold: Number.NaN
    property real timeAutoHysteresis: Number.NaN
    property real timeAutoLowThreshold: Number.NaN
    property real timeAutoHighThreshold: Number.NaN
    readonly property bool timeCursorsFollowLiveWindow: simulationRunning && !manualDisplayPaused && !singleTriggerFrozen
    readonly property bool hasTimeCursors: cursorMode === "time" || cursorMode === "both"
    readonly property bool hasVoltageCursors: cursorMode === "voltage" || cursorMode === "both"
    readonly property real displayedTimeCursor1: timeCursorsFollowLiveWindow ? sharedWindowStart + liveTimeCursor1Position * visibleTimeSeconds : timeCursor1
    readonly property real displayedTimeCursor2: timeCursorsFollowLiveWindow ? sharedWindowStart + liveTimeCursor2Position * visibleTimeSeconds : timeCursor2
    property var displaySnapshot: ({ channels: [], mode: "raw", sampleCount: 0, samplesPerPixel: 0 })
    readonly property bool interpolationAvailable: displaySnapshot.mode === "raw" && Number(displaySnapshot.samplesPerPixel) < 0.5
    signal selectedChannelRequested(int index)
    signal startRequested(); signal stopRequested(); signal manualDisplayPauseRequested(); signal verticalFitRequested(); signal clearHistoryRequested()
    readonly property real visibleTimeSeconds: sharedWindowEnd - sharedWindowStart
    readonly property bool reviewingHistory: sharedHistoryOffset > 1e-9
    readonly property bool usesHistory: reviewingHistory || displayMode === "roll"
    readonly property var activeChannels: channelStore.activeViewChannels()
    readonly property int activeViewCount: Math.max(1, activeChannels.length)
    readonly property int cursorReadoutViewIndex: Math.max(0, activeChannels.indexOf(selectedChannelIndex))
    property alias measurementTaskModel: measurementTasks

    function formatNumber(value) { return Number(value).toFixed(1).replace(/\.0$/, "") }
    function formatTime(value) { return Math.abs(value) < 1 ? formatNumber(value * 1000) + " ms" : formatNumber(value) + " s" }
    function formatCursorTime(value) { return Math.abs(value) < 1 ? Number(value * 1000).toFixed(3) + " ms" : Number(value).toFixed(6) + " s" }
    function formatCursorFrequency(value) { return Math.abs(value) < 1000 ? Math.abs(value).toFixed(3) + " Hz" : (Math.abs(value) / 1000).toFixed(3) + " kHz" }
    function resetCursorPlacement() {
        if (hasTimeCursors) {
            if (timeCursorsFollowLiveWindow) {
                liveTimeCursor1Position = 1 / 3
                liveTimeCursor2Position = 2 / 3
            } else {
                timeCursor1 = sharedWindowStart + visibleTimeSeconds / 3
                timeCursor2 = sharedWindowStart + visibleTimeSeconds * 2 / 3
                frozenTimeCursor1Position = 1 / 3
                frozenTimeCursor2Position = 2 / 3
            }
        }
        if (hasVoltageCursors) {
            const data = channelStore.channel(selectedChannelIndex)
            const center = -data.verticalOffsetV
            voltageCursor1 = center + data.voltsPerDiv
            voltageCursor2 = center - data.voltsPerDiv
        }
        schedulePaint()
    }
    function setCursorMode(mode) { cursorMode = mode; if (mode !== "off") resetCursorPlacement(); else schedulePaint() }
    function updateFrozenCursorPositions() {
        if (!hasTimeCursors || timeCursorsFollowLiveWindow || visibleTimeSeconds <= 0) return
        frozenTimeCursor1Position = Math.max(0, Math.min(1, (timeCursor1 - sharedWindowStart) / visibleTimeSeconds))
        frozenTimeCursor2Position = Math.max(0, Math.min(1, (timeCursor2 - sharedWindowStart) / visibleTimeSeconds))
    }
    function engineeringUnit(channelIndex) {
        const channel = channelStore.channel(channelIndex)
        return channel && channel.engineeringUnit ? channel.engineeringUnit : "V"
    }
    function timeMeasurementUnit(item) {
        if (item === "frequency") return "Hz"
        if (item === "positiveDutyCycle" || item === "negativeDutyCycle") return "%"
        if (item === "period" || item === "positivePulseWidth" || item === "negativePulseWidth"
                || item === "riseTime" || item === "fallTime") return "s"
        return ""
    }
    function countMeasurementUnit(item) {
        return ["risingEdgeCount", "fallingEdgeCount", "totalEdgeCount",
                "positivePulseCount", "negativePulseCount"].indexOf(item) >= 0 ? qsTr("\u6b21") : ""
    }
    function measurementItemOptions(category) {
        if (category === "amplitude") return [
            { key: "maximum", text: qsTr("最大值") }, { key: "minimum", text: qsTr("最小值") },
            { key: "peakToPeak", text: qsTr("峰峰值") }, { key: "mean", text: qsTr("平均值") }, { key: "rms", text: qsTr("RMS") }
        ]
        if (category === "time") return [{ key: "period", text: qsTr("边沿周期") }, { key: "frequency", text: qsTr("边沿频率") }]
        return [{ key: "reserved", text: qsTr("本轮预留") }]
    }
    function measurementCatalogue(category) {
        const amplitude = [
            { key: "maximum", name: qsTr("最大值"), symbol: "Max", unit: "channel", description: qsTr("窗口内原始样本最大值"), implemented: true },
            { key: "minimum", name: qsTr("最小值"), symbol: "Min", unit: "channel", description: qsTr("窗口内原始样本最小值"), implemented: true },
            { key: "peakToPeak", name: qsTr("峰峰值"), symbol: "Vpp", unit: "channel", description: qsTr("最大值减最小值"), implemented: true },
            { key: "mean", name: qsTr("平均值"), symbol: "Avg", unit: "channel", description: qsTr("窗口内原始样本平均值"), implemented: true },
            { key: "rms", name: qsTr("RMS"), symbol: "RMS", unit: "channel", description: qsTr("窗口内原始样本均方根"), implemented: true }
        ]
        const time = [
            { key: "period", name: qsTr("边沿周期"), symbol: "Tedge", unit: "s", description: qsTr("相邻同向阈值边沿之间的周期"), implemented: true },
            { key: "frequency", name: qsTr("边沿频率"), symbol: "fedge", unit: "Hz", description: qsTr("由同向边沿周期换算的频率"), implemented: true },
            { key: "mainFrequency", name: qsTr("主频"), symbol: "f0", unit: "Hz", description: qsTr("频谱主峰测量"), implemented: false },
            { key: "repetitionPeriod", name: qsTr("重复周期"), symbol: "Trep", unit: "s", description: qsTr("重复结构的时间间隔"), implemented: false },
            { key: "envelopeFrequency", name: qsTr("包络频率"), symbol: "fenv", unit: "Hz", description: qsTr("调制包络频率"), implemented: false }
        ]
        const timeExtensions = [
            { key: "positivePulseWidth", name: qsTr("\u6b63\u8109\u5bbd"), symbol: "T+", unit: "s", description: qsTr("\u4e2d\u9608\u503c\u4e4b\u95f4\u7684\u9ad8\u7535\u5e73\u6301\u7eed\u65f6\u95f4"), implemented: true },
            { key: "negativePulseWidth", name: qsTr("\u8d1f\u8109\u5bbd"), symbol: "T-", unit: "s", description: qsTr("\u4e2d\u9608\u503c\u4e4b\u95f4\u7684\u4f4e\u7535\u5e73\u6301\u7eed\u65f6\u95f4"), implemented: true },
            { key: "positiveDutyCycle", name: qsTr("\u6b63\u5360\u7a7a\u6bd4"), symbol: "D+", unit: "%", description: qsTr("\u9ad8\u7535\u5e73\u8109\u5bbd\u5360\u5b8c\u6574\u5468\u671f\u7684\u6bd4\u4f8b"), implemented: true },
            { key: "negativeDutyCycle", name: qsTr("\u8d1f\u5360\u7a7a\u6bd4"), symbol: "D-", unit: "%", description: qsTr("\u4f4e\u7535\u5e73\u8109\u5bbd\u5360\u5b8c\u6574\u5468\u671f\u7684\u6bd4\u4f8b"), implemented: true },
            { key: "riseTime", name: qsTr("\u4e0a\u5347\u65f6\u95f4"), symbol: "Tr", unit: "s", description: qsTr("\u4f4e\u9608\u503c\u5230\u9ad8\u9608\u503c\u7684\u4e0a\u5347\u8fc7\u6e21\u65f6\u95f4"), implemented: true },
            { key: "fallTime", name: qsTr("\u4e0b\u964d\u65f6\u95f4"), symbol: "Tf", unit: "s", description: qsTr("\u9ad8\u9608\u503c\u5230\u4f4e\u9608\u503c\u7684\u4e0b\u964d\u8fc7\u6e21\u65f6\u95f4"), implemented: true }
        ]
        const count = [
            { key: "risingEdgeCount", name: qsTr("\u4e0a\u5347\u6cbf\u6570"), symbol: "N+", unit: qsTr("\u6b21"), description: qsTr("\u5e26\u8fdf\u6ede\u72b6\u6001\u673a\u8bc6\u522b\u7684\u4e0a\u5347\u9608\u503c\u8de8\u8d8a\u6b21\u6570"), implemented: true },
            { key: "fallingEdgeCount", name: qsTr("\u4e0b\u964d\u6cbf\u6570"), symbol: "N-", unit: qsTr("\u6b21"), description: qsTr("\u5e26\u8fdf\u6ede\u72b6\u6001\u673a\u8bc6\u522b\u7684\u4e0b\u964d\u9608\u503c\u8de8\u8d8a\u6b21\u6570"), implemented: true },
            { key: "totalEdgeCount", name: qsTr("\u603b\u8fb9\u6cbf\u6570"), symbol: "Nall", unit: qsTr("\u6b21"), description: qsTr("\u4e0a\u5347\u6cbf\u4e0e\u4e0b\u964d\u6cbf\u7684\u603b\u6b21\u6570"), implemented: true },
            { key: "positivePulseCount", name: qsTr("\u6b63\u8109\u51b2\u6570"), symbol: "P+", unit: qsTr("\u6b21"), description: qsTr("\u7a97\u53e3\u5185\u5b8c\u6574\u4e0a\u5347\u540e\u4e0b\u964d\u7684\u9ad8\u7535\u5e73\u8109\u51b2\u6570"), implemented: true },
            { key: "negativePulseCount", name: qsTr("\u8d1f\u8109\u51b2\u6570"), symbol: "P-", unit: qsTr("\u6b21"), description: qsTr("\u7a97\u53e3\u5185\u5b8c\u6574\u4e0b\u964d\u540e\u4e0a\u5347\u7684\u4f4e\u7535\u5e73\u8109\u51b2\u6570"), implemented: true }
        ]
        const reserved = {
            count: [{ key: "edgeCount", name: qsTr("边沿计数"), symbol: "N", unit: "count", description: qsTr("待实现"), implemented: false }],
            area: [{ key: "integral", name: qsTr("积分面积"), symbol: "∫", unit: "channel·s", description: qsTr("待实现"), implemented: false }],
            dual: [{ key: "phase", name: qsTr("相位差"), symbol: "Δφ", unit: "°", description: qsTr("待实现"), implemented: false }]
        }
        return category === "amplitude" ? amplitude
                : category === "time" ? time.concat(timeExtensions)
                : category === "count" ? count : reserved[category] || []
    }
    function filteredMeasurementCatalogue() {
        const search = measurementSearch.trim().toLowerCase()
        return measurementCatalogue(draftMeasurementCategory).filter(entry => !search.length || entry.name.toLowerCase().indexOf(search) >= 0 || entry.symbol.toLowerCase().indexOf(search) >= 0 || entry.description.toLowerCase().indexOf(search) >= 0)
    }
    function setMeasurementCategory(category) {
        const selections = Object.assign({}, draftMeasurementItemsByCategory)
        selections[draftMeasurementCategory] = draftMeasurementItems.slice()
        draftMeasurementItemsByCategory = selections
        draftMeasurementCategory = category
        draftMeasurementItems = (selections[category] || []).slice()
        timeAdvancedExpanded = false
    }
    function setDraftMeasurementItems(items) {
        draftMeasurementItems = items.slice()
        const selections = Object.assign({}, draftMeasurementItemsByCategory)
        selections[draftMeasurementCategory] = draftMeasurementItems.slice()
        draftMeasurementItemsByCategory = selections
    }
    function toggleDraftMeasurementItem(key) {
        const next = draftMeasurementItems.slice(), position = next.indexOf(key)
        if (position >= 0) next.splice(position, 1); else next.push(key)
        draftMeasurementItems = next
        const selections = Object.assign({}, draftMeasurementItemsByCategory)
        selections[draftMeasurementCategory] = next
        draftMeasurementItemsByCategory = selections
    }
    function removeDraftMeasurementItem(category, key) {
        const selections = Object.assign({}, draftMeasurementItemsByCategory)
        selections[category] = (selections[category] || []).filter(item => item !== key)
        draftMeasurementItemsByCategory = selections
        if (draftMeasurementCategory === category)
            draftMeasurementItems = selections[category].slice()
    }
    function selectedMeasurementItemSummary() {
        const categories = ["amplitude", "time", "count"]
        const summary = []
        for (let categoryIndex = 0; categoryIndex < categories.length; ++categoryIndex) {
            const category = categories[categoryIndex]
            const selected = draftMeasurementItemsByCategory[category] || []
            const catalogue = measurementCatalogue(category)
            for (let itemIndex = 0; itemIndex < selected.length; ++itemIndex) {
                const entry = catalogue.find(candidate => candidate.key === selected[itemIndex])
                if (entry) summary.push({ category: category, key: entry.key, text: entry.name })
            }
        }
        return summary
    }
    function toggleDraftMeasurementChannel(channel) {
        const next = draftMeasurementChannels.slice(), position = next.indexOf(channel)
        if (position >= 0) next.splice(position, 1); else next.push(channel)
        draftMeasurementChannels = next
    }
    function selectAllMeasurementChannels() { draftMeasurementChannels = selectableMeasurementChannels().slice() }
    function invertMeasurementChannels() {
        const enabled = selectableMeasurementChannels()
        draftMeasurementChannels = enabled.filter(channel => draftMeasurementChannels.indexOf(channel) < 0)
    }
    function selectableMeasurementChannels() {
        const channels = []
        for (let index = 0; index < channelStore.channelModel.count; ++index)
            if (channelStore.channel(index).enabled) channels.push(index)
        return channels
    }
    function measurementChannelsForBoard(boardIndex) {
        return selectableMeasurementChannels().filter(channelIndex => Math.floor(channelIndex / 8) === boardIndex)
    }
    function measurementBoardSelectedCount(boardIndex) {
        return draftMeasurementChannels.filter(channelIndex => Math.floor(channelIndex / 8) === boardIndex).length
    }
    function measurementItemText(category, item) {
        const catalogueEntry = measurementCatalogue(category).find(entry => entry.key === item)
        if (catalogueEntry) return catalogueEntry.name
        const options = measurementItemOptions(category)
        for (let index = 0; index < options.length; ++index) if (options[index].key === item) return options[index].text
        return qsTr("本轮预留")
    }
    function measurementValueText(value, unit) {
        if (!isFinite(value)) return "--"
        const numeric = Number(value)
        if (unit === "s") {
            if (Math.abs(numeric) < .001)
                return (numeric * 1000000).toFixed(3).replace(/\.0+$/, "") + " µs"
            if (Math.abs(numeric) < 1)
                return (numeric * 1000).toFixed(3).replace(/\.0+$/, "") + " ms"
        }
        return numeric.toFixed(4).replace(/\.0+$/, "") + (unit.length ? " " + unit : "")
    }
    function measurementInvalidReason(reason) {
        if (reason === "gap") return qsTr("\u7a97\u53e3\u5185\u5b58\u5728\u6570\u636e\u65ad\u5c42")
        if (reason === "insufficient-edges") return qsTr("\u81f3\u5c11\u9700\u8981 3 \u4e2a\u540c\u5411\u8fb9\u6cbf")
        if (reason === "insufficient-transitions") return qsTr("\u7f3a\u5c11\u5b8c\u6574\u7684\u9608\u503c\u8fc7\u6e21\u6216\u9ad8\u4f4e\u7535\u5e73\u533a\u95f4")
        if (reason === "invalid-threshold-relation") return qsTr("\u4f4e\u9608\u503c\u3001\u4e2d\u9608\u503c\u3001\u9ad8\u9608\u503c\u5173\u7cfb\u65e0\u6548")
        if (reason === "threshold-not-crossed") return qsTr("\u672a\u68c0\u6d4b\u5230\u8db3\u591f\u7684\u540c\u5411\u9608\u503c\u8fb9\u6cbf")
        if (reason === "invalid-threshold") return qsTr("\u9608\u503c\u548c\u8fdf\u6ede\u5fc5\u987b\u843d\u5728\u5f53\u524d\u6ce2\u5f62\u5e45\u503c\u8303\u56f4\u5185")
        if (reason === "period-inconsistent" || reason === "period-unstable") return qsTr("\u76f8\u90bb\u8fb9\u6cbf\u5468\u671f\u4e0d\u4e00\u81f4")
        return qsTr("\u6570\u636e\u4e0d\u8db3")
    }
    function evaluateMeasurement(task) {
        const taskItem = task.measurementItem !== undefined ? task.measurementItem : task.item
        if (taskItem === "reserved") return { valid: false, status: qsTr("预留"), unit: "" }
        let start = sharedWindowStart
        let end = sharedWindowEnd
        // Live visible-window tasks must use the backend's source clock too.
        // Main.qml mirrors that clock after the append call returns, while this
        // function can run directly from the C++ historyChanged signal.
        if (task.range !== "latest" && !manualDisplayPaused && !triggerFrameVisible) {
            end = realtimeData.latestSampleTime - sharedHistoryOffset
            start = end - visibleTimeSeconds
        }
        if (task.range === "latest") {
            // historyChanged is emitted during the C++ append call.  Main's
            // mirrored time can still be one block behind at that point.
            end = realtimeData.latestSampleTime
            start = Math.max(0, end - Math.max(samplePeriodSeconds * 8, Number(task.latestWindowSeconds || .1)))
        }
        if (task.range === "latest100ms") start = Math.max(start, end - .1)
        const raw = realtimeData.measureWindow(task.channelIndex, start, end,
                                               timeThresholdMode, timeManualThreshold,
                                               timeHysteresis, timeEdge,
                                               timeManualLowThreshold, timeManualHighThreshold)
        const timeUnit = timeMeasurementUnit(taskItem)
        const countUnit = countMeasurementUnit(taskItem)
        const timeItem = timeUnit.length > 0
        const countItem = countUnit.length > 0
        const edgePeriodItem = taskItem === "period" || taskItem === "frequency"
        if (edgePeriodItem) {
            if (isFinite(Number(raw.threshold))) timeAutoThreshold = Number(raw.threshold)
            if (isFinite(Number(raw.thresholdHysteresis))) timeAutoHysteresis = Number(raw.thresholdHysteresis)
        }
        if (timeItem) {
            if (isFinite(Number(raw.lowThreshold))) timeAutoLowThreshold = Number(raw.lowThreshold)
            if (isFinite(Number(raw.highThreshold))) timeAutoHighThreshold = Number(raw.highThreshold)
        }
        if (!raw.valid || (edgePeriodItem && !raw.periodValid)) {
            if (timeItem)
                return { valid: false, status: measurementInvalidReason(raw.reason), unit: timeUnit }
            if (countItem)
                return { valid: false, status: measurementInvalidReason(raw.reason), unit: countUnit }
            return { valid: false, status: qsTr("数据不足或存在断层"), unit: timeItem ? (taskItem === "period" ? "s" : "Hz") : engineeringUnit(task.channelIndex) }
        }
        const value = Number(raw[taskItem])
        if (!isFinite(value) && timeItem)
            return { valid: false, status: measurementInvalidReason(edgePeriodItem ? raw.reason : (raw.transitionReason || raw.reason)), unit: timeUnit }
        if (isFinite(value) && timeItem && !edgePeriodItem)
            return { valid: true, value: value, status: qsTr("\u6709\u6548"), unit: timeUnit }
        if (isFinite(value) && countItem)
            return { valid: true, value: value, status: qsTr("\u6709\u6548"), unit: countUnit }
        if (!isFinite(value)) return { valid: false, status: qsTr("无效"), unit: "" }
        return { valid: true, value: value, status: qsTr("有效"), unit: timeItem ? (taskItem === "period" ? "s" : "Hz") : engineeringUnit(task.channelIndex) }
    }
    function refreshMeasurementTasks() {
        for (let index = 0; index < measurementTasks.count; ++index) {
            const task = measurementTasks.get(index)
            if (task.paused) continue
            // A visible-window task measures the displayed capture and must
            // freeze with it.  A latest-window task is deliberately separate:
            // it measures the continuing raw acquisition stream.
            const followsLatestSource = task.range === "latest"
            if (!followsLatestSource && (manualDisplayPaused || singleTriggerFrozen))
                continue
            const result = evaluateMeasurement(task)
            measurementTasks.setProperty(index, "status", result.status)
            measurementTasks.setProperty(index, "unit", result.unit)
            if (!result.valid) {
                measurementTasks.setProperty(index, "currentText", "--")
                continue
            }
            measurementTasks.setProperty(index, "currentText", measurementValueText(result.value, result.unit))
            // Statistics must be driven by the raw source clock, not by a
            // display frame, a time/div setting, or a page-state flag.  The
            // latest raw sample time advances exactly once per acquired block;
            // it therefore works for both the visible and latest-window
            // ranges, including a delayed live viewport.  It also prevents
            // stopped data from being sampled repeatedly by this UI timer.
            const sourceLatestTime = realtimeData.latestSampleTime
            const lastAccumulatedTime = Number(task.lastAccumulatedLatestTime)
            const sourceAdvanced = !isFinite(lastAccumulatedTime)
                    || sourceLatestTime > lastAccumulatedTime + samplePeriodSeconds * .25
            const canAccumulate = sourceAdvanced
                    && (followsLatestSource || (!manualDisplayPaused && !singleTriggerFrozen))
            const statisticsMode = task.statisticsMode === "current" ? "current" : "full"
            if (statisticsMode === "current" || !canAccumulate)
                continue
            const count = task.measurementCount + 1
            const delta = result.value - task.runningMean
            const mean = task.runningMean + delta / count
            const m2 = task.runningM2 + delta * (result.value - mean)
            measurementTasks.setProperty(index, "measurementCount", count)
            measurementTasks.setProperty(index, "runningMean", mean)
            measurementTasks.setProperty(index, "runningM2", m2)
            measurementTasks.setProperty(index, "lastAccumulatedLatestTime", sourceLatestTime)
            measurementTasks.setProperty(index, "minimumText", measurementValueText(count === 1 ? result.value : Math.min(task.minimumValue, result.value), result.unit))
            measurementTasks.setProperty(index, "maximumText", measurementValueText(count === 1 ? result.value : Math.max(task.maximumValue, result.value), result.unit))
            measurementTasks.setProperty(index, "averageText", measurementValueText(mean, result.unit))
            measurementTasks.setProperty(index, "deviationText", measurementValueText(count > 1 ? Math.sqrt(m2 / (count - 1)) : 0, result.unit))
            measurementTasks.setProperty(index, "minimumValue", count === 1 ? result.value : Math.min(task.minimumValue, result.value))
            measurementTasks.setProperty(index, "maximumValue", count === 1 ? result.value : Math.max(task.maximumValue, result.value))
        }
    }
    function hasMeasurementTask(channelIndex, measurementItem, range) {
        for (let taskIndex = 0; taskIndex < measurementTasks.count; ++taskIndex) {
            const task = measurementTasks.get(taskIndex)
            if (task.channelIndex === channelIndex
                    && (task.measurementItem === measurementItem || task.item === measurementItem)
                    && task.range === range)
                return true
        }
        return false
    }
    function pendingMeasurementTaskCount() {
        const entries = measurementCatalogue(draftMeasurementCategory).filter(entry => entry.implemented && draftMeasurementItems.indexOf(entry.key) >= 0)
        let pending = 0
        for (let channelPosition = 0; channelPosition < draftMeasurementChannels.length; ++channelPosition)
            for (let itemPosition = 0; itemPosition < entries.length; ++itemPosition)
                if (!hasMeasurementTask(draftMeasurementChannels[channelPosition], entries[itemPosition].key, draftMeasurementRange))
                    ++pending
        return pending
    }
    function measurementTaskAddReason() {
        if (!draftMeasurementChannels.length) return qsTr("\u8bf7\u9009\u62e9\u81f3\u5c11\u4e00\u4e2a\u901a\u9053")
        if (!draftMeasurementItems.length) return qsTr("\u8bf7\u9009\u62e9\u81f3\u5c11\u4e00\u4e2a\u5df2\u5b9e\u73b0\u6d4b\u91cf\u9879")
        const pending = pendingMeasurementTaskCount()
        if (!pending) return qsTr("\u5df2\u9009\u4efb\u52a1\u5747\u5df2\u5b58\u5728")
        if (measurementTasks.count + pending > 64)
            return qsTr("\u6dfb\u52a0\u540e\u5c06\u8d85\u8fc7 64 \u4e2a\u6d4b\u91cf\u4efb\u52a1")
        return ""
    }
    function addSelectedMeasurementTasks() {
        const entries = measurementCatalogue(draftMeasurementCategory).filter(entry => entry.implemented && draftMeasurementItems.indexOf(entry.key) >= 0)
        if (measurementTaskAddReason().length) return
        for (let channelPosition = 0; channelPosition < draftMeasurementChannels.length; ++channelPosition) {
            for (let itemPosition = 0; itemPosition < entries.length; ++itemPosition) {
                const channel = draftMeasurementChannels[channelPosition], entry = entries[itemPosition]
                if (hasMeasurementTask(channel, entry.key, draftMeasurementRange))
                    continue
                measurementTasks.append({ taskId: nextMeasurementTaskId++, channelIndex: channel, category: draftMeasurementCategory,
                    measurementItem: entry.key, item: entry.key, range: draftMeasurementRange, latestWindowSeconds: draftLatestWindowSeconds, paused: false, currentText: "--", minimumText: "--", maximumText: "--",
                    averageText: "--", deviationText: "--", measurementCount: 0, runningMean: 0, runningM2: 0, minimumValue: 0, maximumValue: 0,
                    // -1 is outside the non-negative simulator clock and
                    // guarantees exactly one initial snapshot for a new task.
                    lastAccumulatedLatestTime: -1,
                    statisticsMode: draftMeasurementStatisticsMode,
                    unit: entry.unit === "channel" ? engineeringUnit(channel) : entry.unit, status: qsTr("等待数据") })
            }
        }
        refreshMeasurementTasks()
    }
    function clearMeasurementStatistics(index) {
        measurementTasks.setProperty(index, "measurementCount", 0)
        measurementTasks.setProperty(index, "runningMean", 0)
        measurementTasks.setProperty(index, "runningM2", 0)
        measurementTasks.setProperty(index, "lastAccumulatedLatestTime", -1)
        measurementTasks.setProperty(index, "minimumValue", 0)
        measurementTasks.setProperty(index, "maximumValue", 0)
        measurementTasks.setProperty(index, "minimumText", "--")
        measurementTasks.setProperty(index, "maximumText", "--")
        measurementTasks.setProperty(index, "averageText", "--")
        measurementTasks.setProperty(index, "deviationText", "--")
    }
    function taskUsesThresholdRules(task) {
        return task.category === "time" || task.category === "count"
                || timeMeasurementUnit(task.measurementItem || task.item).length > 0
                || countMeasurementUnit(task.measurementItem || task.item).length > 0
    }
    function resetFullMeasurementStatistics(predicate) {
        for (let index = 0; index < measurementTasks.count; ++index) {
            const task = measurementTasks.get(index)
            if (task.statisticsMode === "full" && predicate(task))
                clearMeasurementStatistics(index)
        }
    }
    function resetVisibleWindowStatisticsForTimebase() {
        // A timebase change changes the actual source span of a visible-window
        // task.  Its accumulated values are therefore no longer comparable.
        // Normal live scrolling and horizontal panning intentionally do not
        // call this function.
        resetFullMeasurementStatistics(task => task.range === "visible")
        refreshMeasurementTasks()
    }
    function resetThresholdRuleStatistics() {
        // Threshold mode, value, hysteresis and direction define the event
        // detector itself.  Preserve amplitude task history, but start a new
        // complete-statistics series for edge, pulse and count tasks.
        resetFullMeasurementStatistics(task => taskUsesThresholdRules(task))
        refreshMeasurementTasks()
    }
    function toggleMeasurementTask(index) { measurementTasks.setProperty(index, "paused", !measurementTasks.get(index).paused) }
    function deleteMeasurementTask(index) { measurementTasks.remove(index) }
    function clearAllMeasurementTasks() {
        measurementTasks.clear()
        if (measurementCanvasRows)
            measurementCanvasRows.scrollOffset = 0
    }
    function measurementTaskIndexById(taskId) {
        for (let taskIndex = 0; taskIndex < measurementTasks.count; ++taskIndex)
            if (measurementTasks.get(taskIndex).taskId === taskId) return taskIndex
        return -1
    }
    function toggleMeasurementTaskById(taskId) {
        const taskIndex = measurementTaskIndexById(taskId)
        if (taskIndex >= 0) toggleMeasurementTask(taskIndex)
    }
    function clearMeasurementStatisticsById(taskId) {
        const taskIndex = measurementTaskIndexById(taskId)
        if (taskIndex >= 0) clearMeasurementStatistics(taskIndex)
    }
    function deleteMeasurementTaskById(taskId) {
        const taskIndex = measurementTaskIndexById(taskId)
        if (taskIndex >= 0) deleteMeasurementTask(taskIndex)
    }
    function openMeasurementPanel() {
        draftMeasurementCategory = "amplitude"
        draftMeasurementRange = "visible"
        draftMeasurementChannels = [selectedChannelIndex]
        draftMeasurementItems = []
        draftMeasurementItemsByCategory = ({ amplitude: [], time: [], count: [] })
        draftMeasurementStatisticsMode = "full"
        measurementChannelBoard = Math.floor(selectedChannelIndex / 8)
        measurementSearch = ""
        timeAdvancedExpanded = false
        measurementConfigDialog.open()
    }
    function schedulePaint() {
        if (!activePage || waveformCanvas.width <= 0 || waveformCanvas.height <= 0)
            return
        updateFrozenCursorPositions()
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
    onTimePerDivMsChanged: {
        schedulePaint()
        resetVisibleWindowStatisticsForTimebase()
    }
    onDisplayModeChanged: schedulePaint()
    onGridVisibleChanged: schedulePaint()
    onSelectedChannelIndexChanged: schedulePaint()
    onManualDisplayPausedChanged: {
        // Resuming returns to a new live snapshot immediately; no stale
        // latest-window value is kept until the next timer tick.
        if (!manualDisplayPaused)
            refreshMeasurementTasks()
    }
    onActivePageChanged: { if (activePage) schedulePaint() }
    onTimeCursorsFollowLiveWindowChanged: {
        if (!hasTimeCursors || visibleTimeSeconds <= 0) { schedulePaint(); return }
        if (timeCursorsFollowLiveWindow) {
            // Resume uses the last on-screen frozen positions, rather than an
            // old absolute timestamp that may have scrolled out of view.
            liveTimeCursor1Position = frozenTimeCursor1Position
            liveTimeCursor2Position = frozenTimeCursor2Position
        } else {
            // Freeze captures the currently visible live positions as absolute
            // sample time so history pan and timebase zoom remain meaningful.
            timeCursor1 = sharedWindowStart + liveTimeCursor1Position * visibleTimeSeconds
            timeCursor2 = sharedWindowStart + liveTimeCursor2Position * visibleTimeSeconds
            frozenTimeCursor1Position = liveTimeCursor1Position
            frozenTimeCursor2Position = liveTimeCursor2Position
        }
        schedulePaint()
    }

    Connections {
        target: root.channelStore

        function onRevisionChanged() { root.schedulePaint() }
    }

    Connections {
        target: root.realtimeData
        function onHistoryChanged() {
            root.schedulePaint()
            // Measurement sampling is source-driven: every retained raw block
            // is considered once, regardless of time/div or QML timer cadence.
            if (root.activePage)
                root.refreshMeasurementTasks()
        }
    }

    component ActionButton: AppButton { implicitHeight: 30 }
    component MeasurementOperationButton: AppButton {
        id: operationButton
        implicitWidth: 26
        implicitHeight: 22
        leftPadding: 0
        rightPadding: 0
        topPadding: 0
        bottomPadding: 0
        // Do not rely on glyph bearings in the generic button text item.
        // These compact operation icons need a fixed, true centre point.
        contentItem: Text {
            anchors.fill: parent
            text: operationButton.text
            color: operationButton.selected ? operationButton.selectedTextColor
                                             : !operationButton.enabled ? "#71818d" : operationButton.textColor
            font.pixelSize: 14
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }
    component MeasurementScrollBar: ScrollBar {
        implicitWidth: 8
        implicitHeight: 8
        policy: ScrollBar.AsNeeded
        contentItem: Rectangle {
            implicitWidth: 8
            implicitHeight: 8
            radius: 4
            color: parent.pressed ? "#39a99e" : "#39717c"
        }
        background: Rectangle {
            implicitWidth: 8
            implicitHeight: 8
            color: "#10212b"
            radius: 4
        }
    }

    ListModel { id: measurementTasks }

    // Short visible windows must be measured before a one-sample event ages out.
    // This timer requests C++ raw-data measurements only; it never inspects
    // display-decimated points.
    Timer {
        interval: simulationRunning
                  ? Math.max(10, Math.min(100, Math.round(Math.max(0.02, visibleTimeSeconds) * 500)))
                  : 250
        repeat: true
        running: root.activePage && measurementTasks.count > 0
        onTriggered: root.refreshMeasurementTasks()
    }

    Popup {
        id: cursorMenu
        parent: Overlay.overlay
        anchors.centerIn: Overlay.overlay
        padding: 0
        modal: false
        closePolicy: Popup.NoAutoClose
        background: Rectangle { color: "#142631"; border.color: "#3a6574"; radius: 5 }
        contentItem: ColumnLayout {
            anchors.margins: 10
            spacing: 6
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                AppButton { text: "×"; implicitWidth: 28; implicitHeight: 24; onClicked: cursorMenu.close() }
            }
            Label { text: qsTr("光标"); color: "#d9e4ec"; font.bold: true; font.pixelSize: 14 }
            AppButton { text: qsTr("关闭"); Layout.fillWidth: true; checkable: true; checked: root.cursorMode === "off"; onClicked: { root.setCursorMode("off"); cursorMenu.close() } }
            AppButton { text: qsTr("时间光标"); Layout.fillWidth: true; checkable: true; checked: root.cursorMode === "time"; onClicked: { root.setCursorMode("time"); cursorMenu.close() } }
            AppButton { text: qsTr("电压光标"); Layout.fillWidth: true; checkable: true; checked: root.cursorMode === "voltage"; onClicked: { root.setCursorMode("voltage"); cursorMenu.close() } }
        }
    }

    Dialog {
        id: measurementDialog
        parent: Overlay.overlay
        anchors.centerIn: Overlay.overlay
        width: Math.min(980, Overlay.overlay.width - 40)
        height: Math.min(570, Overlay.overlay.height - 40)
        modal: true
        focus: true
        closePolicy: Popup.NoAutoClose
        padding: 0
        background: Rectangle { color: "#15212c"; radius: 6; border.color: "#3b6172" }
        header: Rectangle {
            implicitHeight: 44; color: "#1b303d"; radius: 6
            Label { anchors.left: parent.left; anchors.leftMargin: 16; anchors.verticalCenter: parent.verticalCenter; text: qsTr("新增测量任务"); color: "#d9e4ec"; font.bold: true; font.pixelSize: 16 }
            AppButton { anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; text: "×"; implicitWidth: 28; implicitHeight: 26; onClicked: measurementDialog.close() }
        }
        contentItem: ColumnLayout {
            anchors.fill: parent; anchors.margins: 14; spacing: 10
            RowLayout {
                Layout.fillWidth: true; Layout.fillHeight: true; spacing: 12
                Rectangle { Layout.preferredWidth: 155; Layout.fillHeight: true; color: "#132633"; border.color: "#314b5b"; radius: 4
                    ColumnLayout { anchors.fill: parent; anchors.margins: 9; spacing: 6
                        Label { text: qsTr("测量类别"); color: "#8fa3b4"; font.pixelSize: 12; font.bold: true }
                        Repeater { model: [
                            { key: "amplitude", text: qsTr("幅值") }, { key: "time", text: qsTr("时间") }, { key: "count", text: qsTr("计数"), reserved: true },
                            { key: "area", text: qsTr("面积"), reserved: true }, { key: "dual", text: qsTr("双通道"), reserved: true }
                        ]
                            delegate: AppButton { required property var modelData; Layout.fillWidth: true; text: modelData.text + (modelData.reserved ? qsTr(" · 待实现") : ""); checkable: true; checked: root.draftMeasurementCategory === modelData.key; selected: checked; onClicked: { root.draftMeasurementCategory = modelData.key; root.draftMeasurementItems = [] } }
                        }
                        Item { Layout.fillHeight: true }
                        /* Summary is rendered by the fixed footer below. 
                        */
                        /*
                    }
                }
                Rectangle { Layout.preferredWidth: 310; Layout.fillHeight: true; color: "#132633"; border.color: "#314b5b"; radius: 4
                    ColumnLayout { anchors.fill: parent; anchors.margins: 9; spacing: 7
                        RowLayout { Layout.fillWidth: true
                            Label { text: qsTr("测量项"); color: "#8fa3b4"; font.pixelSize: 12; font.bold: true; Layout.fillWidth: true }
                            AppButton { text: qsTr("全选"); implicitHeight: 24; onClicked: root.draftMeasurementItems = root.measurementCatalogue(root.draftMeasurementCategory).filter(entry => entry.implemented).map(entry => entry.key) }
                            AppButton { text: qsTr("清空"); implicitHeight: 24; onClicked: root.draftMeasurementItems = [] }
                        }
                        TextField { Layout.fillWidth: true; implicitHeight: 30; placeholderText: qsTr("搜索名称、符号或说明"); text: root.measurementSearch; onTextEdited: root.measurementSearch = text; color: "#d9e4ec"; background: Rectangle { color: "#1a2a36"; border.color: "#365467"; radius: 3 } }
                        ListView { Layout.fillWidth: true; Layout.fillHeight: true; clip: true; model: root.filteredMeasurementCatalogue()
                            delegate: Rectangle { required property var modelData; width: ListView.view.width; height: 52; color: modelData.implemented ? (root.draftMeasurementItems.indexOf(modelData.key) >= 0 ? "#214651" : "transparent") : "#18242d"; border.color: "#314252"
                                MouseArea { anchors.fill: parent; enabled: modelData.implemented; onClicked: root.toggleDraftMeasurementItem(modelData.key) }
                                RowLayout { anchors.fill: parent; anchors.margins: 7; spacing: 8
                                    Rectangle { Layout.preferredWidth: 14; Layout.preferredHeight: 14; radius: 2; color: root.draftMeasurementItems.indexOf(modelData.key) >= 0 ? "#22a89a" : "transparent"; border.color: modelData.implemented ? "#6c9eaa" : "#465761" }
                                    ColumnLayout { Layout.fillWidth: true; spacing: 1
                                        Label { text: modelData.name + " · " + modelData.symbol; color: modelData.implemented ? "#d9e4ec" : "#71818d"; font.pixelSize: 12; font.bold: true }
                                        Label { text: modelData.description + " · " + (modelData.implemented ? modelData.unit : qsTr("待实现")); color: "#8fa3b4"; font.pixelSize: 10; elide: Text.ElideRight; Layout.fillWidth: true }
                                    }
                                }
                            }
                        }
                    }
                }
                Rectangle { Layout.fillWidth: true; Layout.fillHeight: true; color: "#132633"; border.color: "#314b5b"; radius: 4
                    ColumnLayout { anchors.fill: parent; anchors.margins: 9; spacing: 7
                        Label { text: qsTr("任务配置"); color: "#8fa3b4"; font.pixelSize: 12; font.bold: true }
                        Label { text: qsTr("数据源通道（可多选）"); color: "#8fa3b4"; font.pixelSize: 11 }
                        Flow { Layout.fillWidth: true; spacing: 5
                            /*
                            Repeater { model: root.selectableMeasurementChannels()
                                delegate: AppButton { required property int modelData; text: root.channelStore.channel(modelData).name; checkable: true; checked: root.draftMeasurementChannels.indexOf(modelData) >= 0; selected: checked; implicitHeight: 26; onClicked: root.toggleDraftMeasurementChannel(modelData) }
                            }
                        }
                        Label { visible: root.draftMeasurementCategory === "dual"; text: qsTr("参考通道：双通道测量待实现"); color: "#71818d"; font.pixelSize: 11 }
                        Label { text: qsTr("测量范围"); color: "#8fa3b4"; font.pixelSize: 11 }
                        RowLayout { Layout.fillWidth: true; spacing: 5
                            AppButton { text: qsTr("当前可见窗口"); checkable: true; checked: root.draftMeasurementRange === "visible"; selected: checked; onClicked: root.draftMeasurementRange = "visible" }
                            AppButton { text: qsTr("光标区间"); enabled: false; ToolTip.visible: hovered; ToolTip.text: qsTr("光标区间测量将在后续接入"); ToolTip.delay: 400 }
                            AppButton { text: qsTr("指定范围"); enabled: false; ToolTip.visible: hovered; ToolTip.text: qsTr("指定时间范围将在后续接入"); ToolTip.delay: 400 }
                        }
                        Label { text: qsTr("统计项目"); color: "#8fa3b4"; font.pixelSize: 11 }
                        Flow { Layout.fillWidth: true; spacing: 5
                            Repeater { model: [qsTr("当前值"), qsTr("最小"), qsTr("最大"), qsTr("平均"), qsTr("标准差"), qsTr("次数")]
                            */
                            Repeater { model: [qsTr("\u5f53\u524d\u503c"), qsTr("\u6700\u5c0f"), qsTr("\u6700\u5927"), qsTr("\u5e73\u5747"), qsTr("\u6807\u51c6\u5dee"), qsTr("\u6b21\u6570")]
                                delegate: AppButton { required property string modelData; text: modelData; checkable: true; checked: true; selected: checked; implicitHeight: 24; enabled: false }
                            }
                        }
                        Rectangle { visible: root.draftMeasurementCategory === "time"; Layout.fillWidth: true; implicitHeight: visible ? (root.timeAdvancedExpanded ? 136 : 28) : 0; color: "#182b38"; border.color: "#365467"; radius: 3
                            ColumnLayout { anchors.fill: parent; anchors.margins: 6; spacing: 5
                                AppButton { Layout.fillWidth: true; text: root.timeAdvancedExpanded ? qsTr("\u9ad8\u7ea7\u8bbe\u7f6e\u00b7\u6536\u8d77") : qsTr("\u9ad8\u7ea7\u8bbe\u7f6e"); onClicked: root.timeAdvancedExpanded = !root.timeAdvancedExpanded }
                                /* Legacy inline fields replaced by the advanced-settings framework.
                                RowLayout { visible: root.timeAdvancedExpanded; Layout.fillWidth: true; Label { text: qsTr("阈值模式"); color: "#8fa3b4"; font.pixelSize: 11 }; ComboBox { Layout.fillWidth: true; model: [qsTr("自动"), qsTr("手动")]; currentIndex: root.timeThresholdMode === "auto" ? 0 : 1; onActivated: root.timeThresholdMode = currentIndex === 0 ? "auto" : "manual"; contentItem: Text { leftPadding: 8; text: parent.displayText; color: "#d9e4ec"; verticalAlignment: Text.AlignVCenter }; background: Rectangle { color: "#223542"; border.color: "#365467"; radius: 3 } } }
                                RowLayout { visible: root.timeAdvancedExpanded; Layout.fillWidth: true; Label { text: qsTr("低/中/高阈值、迟滞、边沿判定"); color: "#8fa3b4"; font.pixelSize: 10; Layout.fillWidth: true }; Label { text: qsTr("高级参数框架"); color: "#71818d"; font.pixelSize: 10 } }
                            }
                        }
                                */
                            }
                        }
                        Item { Layout.fillHeight: true }
                        /*
                        Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; color: "#8fa3b4"; font.pixelSize: 11; text: qsTr("已选通道：") + root.draftMeasurementChannels.length + qsTr("；已选测量项：") + root.draftMeasurementItems.length + qsTr("；将创建任务：") + Math.min(16 - measurementTasks.count, root.draftMeasurementChannels.length * root.draftMeasurementItems.length) }
                        */
                        Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; color: "#8fa3b4"; font.pixelSize: 11; text: qsTr("\u5df2\u9009\u901a\u9053\uff1a") + root.draftMeasurementChannels.length + qsTr("\uff1b\u5df2\u9009\u6d4b\u91cf\u9879\uff1a") + root.draftMeasurementItems.length + qsTr("\uff1b\u5c06\u521b\u5efa\u4efb\u52a1\uff1a") + Math.min(16 - measurementTasks.count, root.draftMeasurementChannels.length * root.draftMeasurementItems.length) }
                    }
            }
            RowLayout { Layout.fillWidth: true
                /*
                Label { Layout.fillWidth: true; color: "#e8a94b"; font.pixelSize: 11; text: !root.draftMeasurementChannels.length ? qsTr("请选择至少一个通道") : !root.draftMeasurementItems.length ? qsTr("请选择至少一个已实现测量项") : measurementTasks.count >= 16 ? qsTr("最多保留 16 个测量任务") : "" }
                */
                Label { Layout.fillWidth: true; color: "#e8a94b"; font.pixelSize: 11; text: !root.draftMeasurementChannels.length ? qsTr("\u8bf7\u9009\u62e9\u81f3\u5c11\u4e00\u4e2a\u901a\u9053") : !root.draftMeasurementItems.length ? qsTr("\u8bf7\u9009\u62e9\u81f3\u5c11\u4e00\u4e2a\u5df2\u5b9e\u73b0\u6d4b\u91cf\u9879") : measurementTasks.count >= 16 ? qsTr("\u6700\u591a\u4fdd\u7559 16 \u4e2a\u6d4b\u91cf\u4efb\u52a1") : "" }
                AppButton { text: qsTr("\u53d6\u6d88"); onClicked: measurementDialog.close() }
                AppButton { text: qsTr("\u6dfb\u52a0\u4efb\u52a1"); fillColor: "#168b7c"; enabled: root.draftMeasurementChannels.length > 0 && root.draftMeasurementItems.length > 0 && measurementTasks.count < 16; onClicked: { root.addSelectedMeasurementTasks(); measurementDialog.close() } }
            }
        }
    }

    Dialog {
        id: measurementConfigDialog
        parent: Overlay.overlay
        anchors.centerIn: Overlay.overlay
        width: Math.min(1000, Overlay.overlay.width - 32)
        height: Math.min(600, Overlay.overlay.height - 32)
        modal: true
        focus: true
        // Configuration is only dismissed by an explicit dialog action.
        // Clicking the dimmed overlay or pressing Escape must not discard it.
        closePolicy: Popup.NoAutoClose
        padding: 0
        background: Rectangle { color: "#15212c"; border.color: "#3b6172"; radius: 7 }
        header: Rectangle {
            implicitHeight: 48
            color: "#1b303d"
            radius: 7
            Label { anchors.left: parent.left; anchors.leftMargin: 16; anchors.verticalCenter: parent.verticalCenter; text: qsTr("\u65b0\u589e\u6d4b\u91cf\u4efb\u52a1"); color: "#d9e4ec"; font.pixelSize: 17; font.bold: true }
            AppButton { anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; text: "\u00d7"; implicitWidth: 30; implicitHeight: 28; onClicked: measurementConfigDialog.close() }
        }
        // Dialog lays out header, contentItem and footer in separate regions.
        // Keeping the three-column editor in contentItem prevents it from
        // starting underneath the title bar on smaller Qt Quick windows.
        contentItem: Item {
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                anchors.topMargin: 14
                anchors.bottomMargin: 8
                spacing: 10
                Rectangle {
                    Layout.preferredWidth: 154
                    Layout.fillHeight: true
                    color: "#132633"; border.color: "#314b5b"; radius: 4
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 9; spacing: 6
                        Label { text: qsTr("\u6d4b\u91cf\u7c7b\u522b"); color: "#8fa3b4"; font.pixelSize: 12; font.bold: true }
                        Repeater {
                            model: [
                                { key: "amplitude", label: qsTr("\u5e45\u503c"), available: true },
                                { key: "time", label: qsTr("\u65f6\u95f4"), available: true },
                                { key: "count", label: qsTr("\u8ba1\u6570"), available: true },
                                { key: "area", label: qsTr("\u9762\u79ef"), available: false },
                                { key: "dual", label: qsTr("\u53cc\u901a\u9053"), available: false }
                            ]
                            delegate: AppButton {
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 30
                                text: modelData.label + (modelData.available ? "" : qsTr("  \u5f85\u5b9e\u73b0"))
                                enabled: modelData.available
                                checkable: true
                                checked: root.draftMeasurementCategory === modelData.key
                                selected: checked
                                onClicked: root.setMeasurementCategory(modelData.key)
                            }
                        }
                        Item { Layout.fillHeight: true }
                    }
                }
                Rectangle {
                    Layout.preferredWidth: 345
                    Layout.fillHeight: true
                    color: "#132633"; border.color: "#314b5b"; radius: 4
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 9; spacing: 7
                        RowLayout {
                            Layout.fillWidth: true
                            Label { Layout.fillWidth: true; text: qsTr("\u6d4b\u91cf\u9879"); color: "#8fa3b4"; font.pixelSize: 12; font.bold: true }
                            AppButton { text: qsTr("\u5168\u9009\u672c\u7c7b"); implicitHeight: 25; onClicked: root.setDraftMeasurementItems(root.measurementCatalogue(root.draftMeasurementCategory).filter(entry => entry.implemented).map(entry => entry.key)) }
                            AppButton { text: qsTr("\u6e05\u7a7a"); implicitHeight: 25; onClicked: root.setDraftMeasurementItems([]) }
                        }
                        TextField {
                            Layout.fillWidth: true; implicitHeight: 31
                            placeholderText: qsTr("\u641c\u7d22\u6d4b\u91cf\u9879")
                            text: root.measurementSearch
                            onTextEdited: root.measurementSearch = text
                            color: "#d9e4ec"
                            background: Rectangle { color: "#1a2a36"; border.color: "#365467"; radius: 3 }
                        }
                        ListView {
                            Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 3
                            model: root.filteredMeasurementCatalogue()
                            delegate: Rectangle {
                                required property var modelData
                                width: ListView.view.width; height: 48
                                radius: 3
                                color: root.draftMeasurementItems.indexOf(modelData.key) >= 0 ? "#214651" : "#172934"
                                border.color: root.draftMeasurementItems.indexOf(modelData.key) >= 0 ? "#278b92" : "#314b5b"
                                MouseArea { anchors.fill: parent; enabled: modelData.implemented; onClicked: root.toggleDraftMeasurementItem(modelData.key) }
                                RowLayout {
                                    anchors.fill: parent; anchors.margins: 7; spacing: 8
                                    Rectangle { Layout.preferredWidth: 14; Layout.preferredHeight: 14; radius: 2; color: root.draftMeasurementItems.indexOf(modelData.key) >= 0 ? "#22a89a" : "transparent"; border.color: modelData.implemented ? "#6c9eaa" : "#52626c" }
                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: 1
                                        Label { text: modelData.name + "  " + modelData.symbol; color: modelData.implemented ? "#d9e4ec" : "#71818d"; font.pixelSize: 12; font.bold: true }
                                        Label { Layout.fillWidth: true; text: modelData.implemented ? modelData.description : qsTr("\u5f85\u5b9e\u73b0"); color: "#8fa3b4"; font.pixelSize: 10; elide: Text.ElideRight }
                                    }
                                    Label { text: modelData.unit === "channel" ? qsTr("\u8ddf\u968f\u901a\u9053") : modelData.unit; color: "#7eb8c2"; font.pixelSize: 10 }
                                }
                            }
                        }
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: "#132633"; border.color: "#314b5b"; radius: 4
                    ScrollView {
                        id: taskConfigScroll
                        anchors.fill: parent
                        anchors.margins: 9
                        clip: true
                        contentWidth: availableWidth
                        contentHeight: taskConfigColumn.implicitHeight + 22
                        ScrollBar.vertical: MeasurementScrollBar { }
                        // ScrollView's wheel handling is retained, and this adds the
                        // familiar mouse-drag gesture for the task configuration pane.
                        // A DragHandler only becomes active after its drag threshold, so
                        // normal button clicks inside the pane still behave as clicks.
                        DragHandler {
                            id: taskConfigDragHandler
                            target: null
                            property real startContentY: 0
                            onActiveChanged: {
                                if (active)
                                    startContentY = taskConfigScroll.contentItem.contentY
                            }
                            onTranslationChanged: {
                                if (!active)
                                    return
                                const flickable = taskConfigScroll.contentItem
                                const maximumY = Math.max(0, flickable.contentHeight - flickable.height)
                                flickable.contentY = Math.max(0, Math.min(maximumY,
                                                                          startContentY - translation.y))
                            }
                        }
                        ColumnLayout {
                            id: taskConfigColumn
                            width: taskConfigScroll.availableWidth
                            spacing: 7
                        Label { text: qsTr("\u4efb\u52a1\u914d\u7f6e"); color: "#8fa3b4"; font.pixelSize: 12; font.bold: true }
                        RowLayout {
                            Layout.fillWidth: true
                            Label { Layout.fillWidth: true; text: qsTr("\u6570\u636e\u6e90\u901a\u9053\uff08\u53ef\u591a\u9009\uff09  \u5df2\u9009 ") + root.draftMeasurementChannels.length + qsTr(" \u8def"); color: "#8fa3b4"; font.pixelSize: 11 }
                            AppButton { text: qsTr("\u5168\u9009\u5df2\u542f\u7528"); implicitHeight: 24; enabled: root.selectableMeasurementChannels().length > 0; onClicked: root.selectAllMeasurementChannels() }
                            AppButton { text: qsTr("\u53cd\u9009"); implicitHeight: 24; enabled: root.selectableMeasurementChannels().length > 0; onClicked: root.invertMeasurementChannels() }
                            AppButton { text: qsTr("\u6e05\u7a7a"); implicitHeight: 24; enabled: root.draftMeasurementChannels.length > 0; onClicked: root.draftMeasurementChannels = [] }
                        }
                        Flow {
                            Layout.fillWidth: true
                            spacing: 5
                            Repeater {
                                model: 8
                                delegate: AppButton {
                                    required property int index
                                    readonly property var boardChannels: root.measurementChannelsForBoard(index)
                                    readonly property int selectedCount: root.measurementBoardSelectedCount(index)
                                    text: qsTr("\u677f\u5361 ") + (index + 1) + (selectedCount > 0 ? "  " + selectedCount + "/" + boardChannels.length : "")
                                    implicitHeight: 25
                                    enabled: boardChannels.length > 0
                                    checkable: true
                                    checked: root.measurementChannelBoard === index
                                    selected: checked
                                    onClicked: root.measurementChannelBoard = index
                                }
                            }
                        }
                        Label { text: qsTr("\u7edf\u8ba1\u8bbe\u7f6e"); color: "#8fa3b4"; font.pixelSize: 11 }
                        RowLayout {
                            Layout.fillWidth: true; spacing: 5
                            AppButton { text: qsTr("\u4ec5\u5f53\u524d\u7ed3\u679c"); checkable: true; checked: root.draftMeasurementStatisticsMode === "current"; selected: checked; onClicked: root.draftMeasurementStatisticsMode = "current" }
                            AppButton { text: qsTr("\u5b8c\u6574\u7edf\u8ba1"); checkable: true; checked: root.draftMeasurementStatisticsMode === "full"; selected: checked; onClicked: root.draftMeasurementStatisticsMode = "full" }
                            Label { Layout.fillWidth: true; text: root.draftMeasurementStatisticsMode === "current" ? qsTr("\u6bcf\u4e2a\u6d4b\u91cf\u9879\u53ea\u663e\u793a\u5f53\u524d\u8ba1\u7b97\u7ed3\u679c\uff0c\u4e0d\u7d2f\u8ba1\u7edf\u8ba1\u503c") : qsTr("\u542b\u6700\u5c0f/\u6700\u5927/\u5e73\u5747/\u6807\u51c6\u5dee/\u6b21\u6570"); color: "#71818d"; font.pixelSize: 10; elide: Text.ElideRight }
                        }
                        Label { Layout.fillWidth: true; text: qsTr("\u6e05\u96f6\u53ea\u6e05\u9664\u7edf\u8ba1\u5386\u53f2\uff0c\u4e0d\u5f71\u54cd\u5f53\u524d\u6d4b\u91cf\u503c\u6216\u4efb\u52a1\u914d\u7f6e\u3002"); color: "#71818d"; font.pixelSize: 10; wrapMode: Text.WordWrap }
                        Flow {
                            Layout.fillWidth: true
                            spacing: 5
                            Repeater {
                                model: root.measurementChannelsForBoard(root.measurementChannelBoard)
                                delegate: AppButton {
                                    required property int modelData
                                    text: root.channelStore.channel(modelData).name
                                    checkable: true
                                    checked: root.draftMeasurementChannels.indexOf(modelData) >= 0
                                    selected: checked
                                    implicitHeight: 27
                                    onClicked: root.toggleDraftMeasurementChannel(modelData)
                                }
                            }
                            Label {
                                visible: root.measurementChannelsForBoard(root.measurementChannelBoard).length === 0
                                text: qsTr("\u5f53\u524d\u677f\u5361\u6ca1\u6709\u5df2\u542f\u7528\u7684\u91c7\u96c6\u901a\u9053")
                                color: "#71818d"
                                font.pixelSize: 11
                            }
                        }
                        Label { text: qsTr("\u6d4b\u91cf\u8303\u56f4"); color: "#8fa3b4"; font.pixelSize: 11 }
                        RowLayout {
                            Layout.fillWidth: true; spacing: 5
                            AppButton { text: qsTr("\u5f53\u524d\u53ef\u89c1\u7a97\u53e3"); checkable: true; checked: root.draftMeasurementRange === "visible"; selected: checked; onClicked: root.draftMeasurementRange = "visible" }
                            AppButton { text: qsTr("\u6700\u65b0\u91c7\u6837\u7a97\u53e3"); checkable: true; checked: root.draftMeasurementRange === "latest"; selected: checked; onClicked: root.draftMeasurementRange = "latest" }
                            AppButton { text: qsTr("\u5149\u6807\u533a\u95f4"); enabled: false; implicitHeight: 24 }
                            AppButton { text: qsTr("\u6307\u5b9a\u65f6\u95f4"); enabled: false; implicitHeight: 24 }
                        }
                        RowLayout {
                            visible: root.draftMeasurementRange === "latest"
                            Layout.fillWidth: true
                            Label { text: qsTr("\u7a97\u53e3\u65f6\u957f"); color: "#8fa3b4"; font.pixelSize: 10 }
                            AppButton { text: "100 ms"; checkable: true; checked: root.draftLatestWindowSeconds === .1; selected: checked; implicitHeight: 24; onClicked: root.draftLatestWindowSeconds = .1 }
                            AppButton { text: "1 s"; checkable: true; checked: root.draftLatestWindowSeconds === 1; selected: checked; implicitHeight: 24; onClicked: root.draftLatestWindowSeconds = 1 }
                            AppButton { text: "5 s"; checkable: true; checked: root.draftLatestWindowSeconds === 5; selected: checked; implicitHeight: 24; onClicked: root.draftLatestWindowSeconds = 5 }
                            Item { Layout.fillWidth: true }
                        }
                        Rectangle {
                            visible: root.draftMeasurementCategory === "time"
                            Layout.fillWidth: true
                            // Keep this section self-contained: the outer task panel can
                            // scroll as a whole, while exceptionally long advanced content
                            // scrolls here instead of overlapping the dialog footer.
                            Layout.preferredHeight: visible ? (root.timeAdvancedExpanded ? Math.min(248, edgeSettingsColumn.implicitHeight + 38) : 29) : 0
                            Layout.minimumHeight: Layout.preferredHeight
                            Layout.maximumHeight: Layout.preferredHeight
                            color: root.timeAdvancedExpanded ? "#182b38" : "transparent"
                            border.color: root.timeAdvancedExpanded ? "#365467" : "transparent"
                            radius: 3
                            ColumnLayout {
                                anchors.fill: parent; anchors.margins: root.timeAdvancedExpanded ? 5 : 0; spacing: 4
                                AppButton { Layout.fillWidth: true; text: root.timeAdvancedExpanded ? qsTr("\u9ad8\u7ea7\u8bbe\u7f6e  \u6536\u8d77") : qsTr("\u9ad8\u7ea7\u8bbe\u7f6e"); onClicked: root.timeAdvancedExpanded = !root.timeAdvancedExpanded }
                                Flickable {
                                    visible: root.timeAdvancedExpanded
                                    Layout.fillWidth: true; Layout.fillHeight: true
                                    clip: true; contentWidth: width; contentHeight: edgeSettingsColumn.implicitHeight
                                    flickableDirection: Flickable.VerticalFlick
                                    ColumnLayout {
                                        id: edgeSettingsColumn
                                        width: parent.width; spacing: 7
                                        Label { text: qsTr("\u9608\u503c\u6a21\u5f0f"); color: "#8fa3b4"; font.pixelSize: 11; font.bold: true }
                                        RowLayout {
                                            Layout.fillWidth: true; spacing: 5
                                            AppButton { text: qsTr("\u81ea\u52a8"); checkable: true; checked: root.timeThresholdMode === "auto"; selected: checked; implicitHeight: 25; onClicked: { if (root.timeThresholdMode !== "auto") { root.timeThresholdMode = "auto"; root.resetThresholdRuleStatistics() } } }
                                            AppButton { text: qsTr("\u624b\u52a8"); checkable: true; checked: root.timeThresholdMode === "manual"; selected: checked; implicitHeight: 25; onClicked: { if (root.timeThresholdMode !== "manual") { root.timeThresholdMode = "manual"; root.resetThresholdRuleStatistics() } } }
                                            Item { Layout.fillWidth: true }
                                        }
                                        Label { text: qsTr("\u6d4b\u91cf\u8fb9\u6cbf"); color: "#8fa3b4"; font.pixelSize: 11; font.bold: true }
                                        RowLayout {
                                            Layout.fillWidth: true; spacing: 5
                                            AppButton { text: qsTr("\u4e0a\u5347\u6cbf"); checkable: true; checked: root.timeEdge === "rising"; selected: checked; implicitHeight: 25; onClicked: { if (root.timeEdge !== "rising") { root.timeEdge = "rising"; root.resetThresholdRuleStatistics() } } }
                                            AppButton { text: qsTr("\u4e0b\u964d\u6cbf"); checkable: true; checked: root.timeEdge === "falling"; selected: checked; implicitHeight: 25; onClicked: { if (root.timeEdge !== "falling") { root.timeEdge = "falling"; root.resetThresholdRuleStatistics() } } }
                                            Item { Layout.fillWidth: true }
                                        }
                                        Label {
                                            Layout.fillWidth: true
                                            text: root.timeThresholdMode === "auto"
                                                ? qsTr("\u5f53\u524d\u81ea\u52a8\u9608\u503c: ") + (isFinite(root.timeAutoThreshold) ? Number(root.timeAutoThreshold).toFixed(4) : "--") + qsTr("  \u00b7  \u8fdf\u6ede: ") + (isFinite(root.timeAutoHysteresis) ? Number(root.timeAutoHysteresis).toFixed(4) : "--")
                                                : qsTr("\u624b\u52a8\u9608\u503c\u548c\u8fdf\u6ede\u4f1a\u7acb\u5373\u53c2\u4e0e\u8fb9\u6cbf\u5224\u5b9a")
                                            color: "#71818d"; font.pixelSize: 10; wrapMode: Text.WordWrap
                                        }
                                        Label {
                                            visible: root.timeThresholdMode === "auto"
                                            Layout.fillWidth: true
                                            text: qsTr("\u81ea\u52a8\u4f4e/\u9ad8\u9608\u503c\uff0810%/90%\uff09: ")
                                                + (isFinite(root.timeAutoLowThreshold) ? Number(root.timeAutoLowThreshold).toFixed(4) : "--")
                                                + " / " + (isFinite(root.timeAutoHighThreshold) ? Number(root.timeAutoHighThreshold).toFixed(4) : "--")
                                            color: "#71818d"; font.pixelSize: 10
                                        }
                                        RowLayout {
                                            visible: root.timeThresholdMode === "manual"
                                            Layout.fillWidth: true; spacing: 6
                                            Label { text: qsTr("\u9608\u503c"); color: "#8fa3b4"; font.pixelSize: 11 }
                                            TextField {
                                                Layout.fillWidth: true; implicitHeight: 25; text: Number(root.timeManualThreshold).toString(); color: "#d9e4ec"
                                                validator: DoubleValidator { bottom: -1000000; top: 1000000; decimals: 6 }
                                                onEditingFinished: { const value = Number(text); if (isFinite(value) && root.timeManualThreshold !== value) { root.timeManualThreshold = value; root.resetThresholdRuleStatistics() } }
                                                background: Rectangle { color: "#1a2a36"; border.color: "#365467"; radius: 3 }
                                            }
                                        }
                                        RowLayout {
                                            visible: root.timeThresholdMode === "manual"
                                            Layout.fillWidth: true; spacing: 6
                                            Label { text: qsTr("\u4f4e\u9608\u503c"); color: "#8fa3b4"; font.pixelSize: 11 }
                                            TextField {
                                                Layout.fillWidth: true; implicitHeight: 25; text: Number(root.timeManualLowThreshold).toString(); color: "#d9e4ec"
                                                validator: DoubleValidator { bottom: -1000000; top: 1000000; decimals: 6 }
                                                onEditingFinished: { const value = Number(text); if (isFinite(value) && root.timeManualLowThreshold !== value) { root.timeManualLowThreshold = value; root.resetThresholdRuleStatistics() } }
                                                background: Rectangle { color: "#1a2a36"; border.color: "#365467"; radius: 3 }
                                            }
                                            Label { text: qsTr("\u9ad8\u9608\u503c"); color: "#8fa3b4"; font.pixelSize: 11 }
                                            TextField {
                                                Layout.fillWidth: true; implicitHeight: 25; text: Number(root.timeManualHighThreshold).toString(); color: "#d9e4ec"
                                                validator: DoubleValidator { bottom: -1000000; top: 1000000; decimals: 6 }
                                                onEditingFinished: { const value = Number(text); if (isFinite(value) && root.timeManualHighThreshold !== value) { root.timeManualHighThreshold = value; root.resetThresholdRuleStatistics() } }
                                                background: Rectangle { color: "#1a2a36"; border.color: "#365467"; radius: 3 }
                                            }
                                        }
                                        Label { text: qsTr("\u8fdf\u6ede"); color: "#8fa3b4"; font.pixelSize: 11; font.bold: true }
                                        TextField {
                                            Layout.fillWidth: true; implicitHeight: 25; text: Number(root.timeHysteresis).toString(); color: "#d9e4ec"
                                            validator: DoubleValidator { bottom: 0; top: 1000000; decimals: 6 }
                                            onEditingFinished: { const value = Number(text); if (isFinite(value) && root.timeHysteresis !== value) { root.timeHysteresis = value; root.resetThresholdRuleStatistics() } }
                                            background: Rectangle { color: "#1a2a36"; border.color: "#365467"; radius: 3 }
                                        }
                                    }
                                }
                            }
                        }
                        // Do not consume the remaining height here: this is a ScrollView
                        // content column and the summary must stay reachable at the bottom.
                        Item { Layout.preferredHeight: 12 }
                        Label { text: qsTr("\u5df2\u9009\u6d4b\u91cf\u9879\u76ee"); color: "#8fa3b4"; font.pixelSize: 11 }
                        Flickable {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 28
                            Layout.minimumHeight: 28
                            clip: true
                            contentWidth: selectedItemsFlow.width
                            contentHeight: height
                            flickableDirection: Flickable.HorizontalFlick
                            Flow {
                                id: selectedItemsFlow
                                height: parent.height
                                spacing: 4
                                Repeater {
                                    model: root.selectedMeasurementItemSummary()
                                    delegate: AppButton {
                                        required property var modelData
                                        text: modelData.text + "  \u00d7"
                                        implicitHeight: 24
                                        onClicked: root.removeDraftMeasurementItem(modelData.category, modelData.key)
                                    }
                                }
                                Label { visible: root.selectedMeasurementItemSummary().length === 0; text: qsTr("\u672a\u9009\u62e9"); color: "#71818d"; font.pixelSize: 10; height: parent.height; verticalAlignment: Text.AlignVCenter }
                            }
                        }
                        Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: qsTr("\u5df2\u9009\u901a\u9053 ") + root.draftMeasurementChannels.length + qsTr(" \u8def  \u00b7  \u5f53\u7c7b\u5df2\u9009\u9879 ") + root.draftMeasurementItems.length + qsTr(" \u9879  \u00b7  \u5c06\u521b\u5efa ") + root.pendingMeasurementTaskCount() + qsTr(" \u4e2a\u4efb\u52a1"); color: "#8fa3b4"; font.pixelSize: 11 }
                    }
                    }
                }
            }
        }
        footer: Rectangle {
                implicitHeight: 50
                color: "#1b303d"
                border.color: "#314b5b"
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 8
                    Label { Layout.fillWidth: true; text: root.measurementTaskAddReason(); color: "#e8a94b"; font.pixelSize: 11; elide: Text.ElideRight }
                    AppButton { text: qsTr("\u53d6\u6d88"); onClicked: measurementConfigDialog.close() }
                    AppButton { text: qsTr("\u6dfb\u52a0\u4efb\u52a1"); fillColor: "#168b7c"; enabled: root.measurementTaskAddReason().length === 0; onClicked: { root.addSelectedMeasurementTasks(); measurementConfigDialog.close() } }
                }
            }
    }

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
                text: root.manualDisplayPaused ? qsTr("\u663e\u793a\u5df2\u6682\u505c") : root.simulationRunning ? qsTr("\u91c7\u96c6\u4e2d") : qsTr("\u5df2\u505c\u6b62")
                color: root.manualDisplayPaused ? "#e8a94b" : root.simulationRunning ? "#35d19b" : "#8fa3b4"
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

                    if (root.hasTimeCursors) {
                        const cursorX1 = (root.displayedTimeCursor1 - root.sharedWindowStart) / windowDuration * width
                        const cursorX2 = (root.displayedTimeCursor2 - root.sharedWindowStart) / windowDuration * width
                        context.strokeStyle = "#f3c56b"
                        context.lineWidth = 1
                        context.setLineDash([5, 3])
                        for (const cursor of [{ x: cursorX1, name: "X1" }, { x: cursorX2, name: "X2" }]) {
                            if (cursor.x < 0 || cursor.x > width) continue
                            context.beginPath(); context.moveTo(cursor.x, 0); context.lineTo(cursor.x, height); context.stroke()
                            context.fillStyle = "#f3c56b"; context.font = "12px sans-serif"; context.fillText(cursor.name, cursor.x + 4, 14)
                        }
                        context.setLineDash([])
                    }
                    if (root.hasVoltageCursors) {
                        const selectedView = root.activeChannels.indexOf(root.selectedChannelIndex)
                        if (selectedView >= 0) {
                            const data = root.channelStore.channel(root.selectedChannelIndex)
                            const top = selectedView * viewHeight
                            const divisionHeight = viewHeight / 4
                            const yForCursor = value => top + viewHeight / 2 - (value + data.verticalOffsetV) * (divisionHeight / data.voltsPerDiv)
                            const y1 = yForCursor(root.voltageCursor1), y2 = yForCursor(root.voltageCursor2)
                            context.save(); context.beginPath(); context.rect(0, top + 1, width, Math.max(0, viewHeight - 2)); context.clip()
                            context.strokeStyle = "#f3c56b"; context.lineWidth = 1; context.setLineDash([5, 3])
                            for (const cursor of [{ y: y1, name: "Y1" }, { y: y2, name: "Y2" }]) {
                                context.beginPath(); context.moveTo(0, cursor.y); context.lineTo(width, cursor.y); context.stroke()
                                context.fillStyle = "#f3c56b"; context.font = "12px sans-serif"; context.fillText(cursor.name, 5, cursor.y - 4)
                            }
                            context.restore(); context.setLineDash([])
                        }
                    }
                }
            }

            MouseArea {
                id: plotPointer
                anchors.fill: parent
                enabled: root.activeChannels.length > 0
                hoverEnabled: true
                cursorShape: containsMouse ? Qt.PointingHandCursor : Qt.ArrowCursor
                property string draggingCursor: ""
                function viewIndexFor(mouseY) {
                    const viewHeight = waveformCanvas.height / root.activeChannels.length
                    return Math.max(0, Math.min(root.activeChannels.length - 1, Math.floor((mouseY - waveformCanvas.y) / viewHeight)))
                }
                onPressed: mouse => {
                    const x = mouse.x - waveformCanvas.x
                    const viewIndex = viewIndexFor(mouse.y)
                    const channelIndex = root.activeChannels[viewIndex]
                    const wasSelected = channelIndex === root.selectedChannelIndex
                    // Channel selection is independent of cursor interaction:
                    // a click in any view switches the editor immediately.
                    root.selectedChannelRequested(channelIndex)
                    if (root.hasTimeCursors) {
                        const x1 = (root.displayedTimeCursor1 - root.sharedWindowStart) / root.visibleTimeSeconds * waveformCanvas.width
                        const x2 = (root.displayedTimeCursor2 - root.sharedWindowStart) / root.visibleTimeSeconds * waveformCanvas.width
                        const distance1 = Math.abs(x - x1), distance2 = Math.abs(x - x2)
                        if (Math.min(distance1, distance2) <= 10) {
                            draggingCursor = distance1 <= distance2 ? "time1" : "time2"
                            return
                        }
                    }
                    if (root.hasVoltageCursors && wasSelected) {
                        const data = root.channelStore.channel(root.selectedChannelIndex)
                        const viewHeight = waveformCanvas.height / root.activeChannels.length
                        const top = viewIndex * viewHeight
                        const divisionHeight = viewHeight / 4
                        const yFor = value => top + viewHeight / 2 - (value + data.verticalOffsetV) * (divisionHeight / data.voltsPerDiv)
                        const distance1 = Math.abs(mouse.y - yFor(root.voltageCursor1)), distance2 = Math.abs(mouse.y - yFor(root.voltageCursor2))
                        draggingCursor = Math.min(distance1, distance2) <= 10 ? (distance1 <= distance2 ? "voltage1" : "voltage2") : ""
                        return
                    }
                }
                onPositionChanged: mouse => {
                    if (!pressed || !draggingCursor.length) return
                    if (draggingCursor === "time1" || draggingCursor === "time2") {
                        const boundedX = Math.max(0, Math.min(waveformCanvas.width, mouse.x - waveformCanvas.x))
                        const value = root.sharedWindowStart + boundedX / waveformCanvas.width * root.visibleTimeSeconds
                        if (root.timeCursorsFollowLiveWindow) {
                            if (draggingCursor === "time1") root.liveTimeCursor1Position = boundedX / waveformCanvas.width
                            else root.liveTimeCursor2Position = boundedX / waveformCanvas.width
                        } else if (draggingCursor === "time1") {
                            root.timeCursor1 = value
                        } else {
                            root.timeCursor2 = value
                        }
                    } else {
                        const selectedView = root.activeChannels.indexOf(root.selectedChannelIndex)
                        if (selectedView < 0) return
                        const data = root.channelStore.channel(root.selectedChannelIndex)
                        const viewHeight = waveformCanvas.height / root.activeChannels.length
                        const top = selectedView * viewHeight
                        const divisionHeight = viewHeight / 4
                        const value = (top + viewHeight / 2 - mouse.y) * data.voltsPerDiv / divisionHeight - data.verticalOffsetV
                        if (draggingCursor === "voltage1") root.voltageCursor1 = value
                        else root.voltageCursor2 = value
                    }
                    root.schedulePaint()
                }
                onReleased: draggingCursor = ""
            }

            // A plain text readout, aligned like the timebase marker below.
            // It deliberately has no card background or border.
            RowLayout {
                id: cursorReadout
                visible: root.cursorMode !== "off"
                anchors.horizontalCenter: parent.horizontalCenter
                y: waveformCanvas.y + root.cursorReadoutViewIndex * waveformCanvas.height / root.activeViewCount + 7
                z: 3
                spacing: 14

                Label { visible: root.hasTimeCursors; text: "X1 " + root.formatCursorTime(root.displayedTimeCursor1); color: "#d9e4ec"; font.pixelSize: 12 }
                Label { visible: root.hasTimeCursors; text: "X2 " + root.formatCursorTime(root.displayedTimeCursor2); color: "#d9e4ec"; font.pixelSize: 12 }
                Label { visible: root.hasTimeCursors; readonly property real delta: root.displayedTimeCursor2 - root.displayedTimeCursor1; text: "\u0394t " + root.formatCursorTime(delta); color: "#d9e4ec"; font.pixelSize: 12 }
                Label { visible: root.hasTimeCursors; readonly property real delta: root.displayedTimeCursor2 - root.displayedTimeCursor1; text: "1/\u0394t " + (Math.abs(delta) < 1e-12 ? "--" : root.formatCursorFrequency(1 / delta)); color: "#d9e4ec"; font.pixelSize: 12 }
                Label { visible: root.hasVoltageCursors; text: "Y1 " + root.formatNumber(root.voltageCursor1) + " V"; color: "#d9e4ec"; font.pixelSize: 12 }
                Label { visible: root.hasVoltageCursors; text: "Y2 " + root.formatNumber(root.voltageCursor2) + " V"; color: "#d9e4ec"; font.pixelSize: 12 }
                Label { visible: root.hasVoltageCursors; text: "\u0394V " + root.formatNumber(root.voltageCursor2 - root.voltageCursor1) + " V"; color: "#d9e4ec"; font.pixelSize: 12 }
            }

            Label {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 10
                visible: root.manualDisplayPaused
                text: qsTr("\u663e\u793a\u5df2\u6682\u505c")
                color: "#f3c56b"
                font.pixelSize: 12
                font.bold: true
                z: 2
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

        Rectangle {
            id: measurementTable
            visible: false // Replaced by the single-list table below; retain legacy layout temporarily.
            Layout.fillWidth: true
            implicitHeight: visible ? Math.min(190, 30 + measurementTasks.count * 27) : 0
            color: "#10212b"
            border.color: "#315363"
            radius: 5
            clip: true
            property real syncedContentY: 0
            ColumnLayout { anchors.fill: parent; spacing: 0
                RowLayout { Layout.fillWidth: true; Layout.preferredHeight: 28; spacing: 0
                    /*
                    Rectangle { Layout.preferredWidth: 116; Layout.fillHeight: true; color: "#1b303d"; RowLayout { anchors.fill: parent; anchors.margins: 6; Label { text: qsTr("通道"); Layout.preferredWidth: 42; color: "#8fa3b4"; font.pixelSize: 10 }; Label { text: qsTr("测量项"); color: "#8fa3b4"; font.pixelSize: 10 } } }
                    */
                    /*
                    Rectangle { Layout.preferredWidth: 116; Layout.fillHeight: true; color: "#1b303d"; RowLayout { anchors.fill: parent; anchors.margins: 6; Label { text: qsTr("\u901a\u9053"); Layout.preferredWidth: 42; color: "#8fa3b4"; font.pixelSize: 10 }; Label { text: qsTr("\u6d4b\u91cf\u9879"); color: "#8fa3b4"; font.pixelSize: 10 } } }
                    */
                    Rectangle {
                        Layout.preferredWidth: 116
                        Layout.fillHeight: true
                        color: "#18313e"
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 6
                            Label { text: qsTr("\u901a\u9053"); Layout.preferredWidth: 42; color: "#8fa3b4"; font.pixelSize: 10 }
                            Label { text: qsTr("\u6d4b\u91cf\u9879"); color: "#8fa3b4"; font.pixelSize: 10 }
                        }
                    }
                    Flickable { id: statisticsHeader; Layout.fillWidth: true; Layout.fillHeight: true; clip: true; contentWidth: 560; contentHeight: height; flickableDirection: Flickable.HorizontalFlick
                        Row { width: 560; height: parent.height; spacing: 0
                            /*
                            Repeater { model: [qsTr("当前值"), qsTr("最小值"), qsTr("最大值"), qsTr("平均值"), qsTr("标准差"), qsTr("次数"), qsTr("单位"), qsTr("状态")]
                            */
                            Repeater { model: [qsTr("\u5f53\u524d\u503c"), qsTr("\u6700\u5c0f\u503c"), qsTr("\u6700\u5927\u503c"), qsTr("\u5e73\u5747\u503c"), qsTr("\u6807\u51c6\u5dee"), qsTr("\u6b21\u6570"), qsTr("\u5355\u4f4d"), qsTr("\u72b6\u6001")]
                                delegate: Label { required property string modelData; width: index < 5 ? 84 : index === 5 ? 44 : index === 6 ? 44 : 52; height: 28; text: modelData; color: "#8fa3b4"; font.pixelSize: 10; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter; background: Rectangle { color: "#1b303d" } }
                            }
                        }
                    }
                    Rectangle { Layout.preferredWidth: 112; Layout.fillHeight: true; color: "#1b303d"; Label { anchors.centerIn: parent; text: qsTr("操作"); color: "#8fa3b4"; font.pixelSize: 10 } }
                }
                RowLayout { Layout.fillWidth: true; Layout.fillHeight: true; spacing: 0
                    ListView { Layout.preferredWidth: 116; Layout.fillHeight: true; model: measurementTasks; interactive: false; contentY: measurementTable.syncedContentY; clip: true
                        /*
                        delegate: Rectangle { required property int channelIndex; required property string category; required property string item; width: ListView.view.width; height: 27; color: index % 2 ? "#142a36" : "#10242f"; RowLayout { anchors.fill: parent; anchors.margins: 6; Label { text: root.channelStore.channel(channelIndex).name; Layout.preferredWidth: 42; color: root.channelStore.channel(channelIndex).color; font.pixelSize: 10 }; Label { text: root.measurementItemText(category, item); color: "#d9e4ec"; font.pixelSize: 10; elide: Text.ElideRight; Layout.fillWidth: true } } }
                        */
                        delegate: Rectangle {
                            required property int channelIndex
                            required property string category
                            required property string item
                            width: ListView.view.width
                            height: 27
                            color: index % 2 ? "#142a36" : "#10242f"
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 6
                                Label { text: root.channelStore.channel(channelIndex).name; Layout.preferredWidth: 42; color: root.channelStore.channel(channelIndex).color; font.pixelSize: 10 }
                                Label { text: root.measurementItemText(category, item); color: "#d9e4ec"; font.pixelSize: 10; elide: Text.ElideRight; Layout.fillWidth: true }
                            }
                        }
                    }
                    Flickable { id: statisticsBody; Layout.fillWidth: true; Layout.fillHeight: true; clip: true; contentWidth: 560; contentHeight: height; flickableDirection: Flickable.HorizontalFlick
                        ListView { id: statisticsList; width: 560; height: statisticsBody.height; model: measurementTasks; clip: true; onContentYChanged: measurementTable.syncedContentY = contentY
                            delegate: Rectangle { required property string currentText; required property string minimumText; required property string maximumText; required property string averageText; required property string deviationText; required property int measurementCount; required property string unit; required property string status; required property bool paused; width: 560; height: 27; color: index % 2 ? "#142a36" : "#10242f"
                                Row { anchors.fill: parent; Repeater { model: [currentText, minimumText, maximumText, averageText, deviationText, measurementCount, unit, paused ? qsTr("已暂停") : (status === qsTr("有效") ? qsTr("有效") : qsTr("无效"))]
                                    delegate: Label { required property var modelData; width: index < 5 ? 84 : index === 5 ? 44 : index === 6 ? 44 : 52; height: 27; text: modelData; color: index === 7 && modelData === qsTr("无效") ? "#f0a35e" : "#d9e4ec"; font.pixelSize: 10; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; ToolTip.visible: hovered && index === 7; ToolTip.text: status; ToolTip.delay: 400 }
                                } }
                            }
                        }
                        ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
                    }
                    ListView { Layout.preferredWidth: 112; Layout.fillHeight: true; model: measurementTasks; interactive: false; contentY: measurementTable.syncedContentY; clip: true
                        delegate: Rectangle { required property int index; required property bool paused; width: ListView.view.width; height: 27; color: index % 2 ? "#142a36" : "#10242f"; Row { anchors.centerIn: parent; spacing: 3
                            AppButton { text: paused ? "▶" : "Ⅱ"; implicitWidth: 27; implicitHeight: 21; onClicked: root.toggleMeasurementTask(index) }
                            AppButton { text: "↺"; implicitWidth: 27; implicitHeight: 21; onClicked: root.clearMeasurementStatistics(index) }
                            AppButton { text: "×"; implicitWidth: 24; implicitHeight: 21; fillColor: "#493b3a"; onClicked: root.deleteMeasurementTask(index) }
                        } }
                    }
                }
            }
        }

        Rectangle {
            id: measurementResultsTable
            visible: measurementTasks.count > 0
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(188, 31 + Math.max(1, measurementTasks.count) * 30)
            Layout.minimumHeight: Layout.preferredHeight
            Layout.maximumHeight: Layout.preferredHeight
            color: "#10212b"
            border.color: "#315363"
            radius: 5
            clip: true
            property real statisticsScrollX: 0

            ColumnLayout {
                anchors.fill: parent
                spacing: 0
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 30
                    Layout.minimumHeight: 30
                    Layout.maximumHeight: 30
                    spacing: 0
                    Rectangle {
                        Layout.preferredWidth: 154
                        Layout.fillHeight: true
                        color: "#18313e"
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 7
                            anchors.rightMargin: 7
                            Label { text: qsTr("\u901a\u9053"); Layout.preferredWidth: 48; color: "#8fa3b4"; font.pixelSize: 10; background: Rectangle { color: "transparent" } }
                            Label { text: qsTr("\u6d4b\u91cf\u9879"); Layout.fillWidth: true; color: "#8fa3b4"; font.pixelSize: 10; background: Rectangle { color: "transparent" } }
                        }
                    }
                    Flickable {
                        id: measurementHeaderFlickable
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        contentWidth: 500
                        contentHeight: height
                        flickableDirection: Flickable.HorizontalFlick
                        contentX: measurementResultsTable.statisticsScrollX
                        onContentXChanged: measurementResultsTable.statisticsScrollX = contentX
                        Item {
                            width: 500; height: parent.height
                            // Explicit cells avoid a Qt/MinGW delegate rendering edge case
                            // that could leave this header visually empty.
                            Label { x: 0; width: 72; anchors.verticalCenter: parent.verticalCenter; text: qsTr("\u5f53\u524d\u503c"); color: "#8fa3b4"; font.pixelSize: 10; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            Label { x: 72; width: 72; anchors.verticalCenter: parent.verticalCenter; text: qsTr("\u6700\u5c0f\u503c"); color: "#8fa3b4"; font.pixelSize: 10; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            Label { x: 144; width: 72; anchors.verticalCenter: parent.verticalCenter; text: qsTr("\u6700\u5927\u503c"); color: "#8fa3b4"; font.pixelSize: 10; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            Label { x: 216; width: 72; anchors.verticalCenter: parent.verticalCenter; text: qsTr("\u5e73\u5747\u503c"); color: "#8fa3b4"; font.pixelSize: 10; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            Label { x: 288; width: 72; anchors.verticalCenter: parent.verticalCenter; text: qsTr("\u6807\u51c6\u5dee"); color: "#8fa3b4"; font.pixelSize: 10; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            Label { x: 360; width: 42; anchors.verticalCenter: parent.verticalCenter; text: qsTr("\u6b21\u6570"); color: "#8fa3b4"; font.pixelSize: 10; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            Label { x: 402; width: 42; anchors.verticalCenter: parent.verticalCenter; text: qsTr("\u5355\u4f4d"); color: "#8fa3b4"; font.pixelSize: 10; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            Label { x: 444; width: 56; anchors.verticalCenter: parent.verticalCenter; text: qsTr("\u72b6\u6001"); color: "#8fa3b4"; font.pixelSize: 10; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                        }
                    }
                    Rectangle {
                        // The shared Flickable above is the only statistics header.
                        // Keep this legacy fixed header out of the layout so the body
                        // and header use the same horizontal scroll position.
                        Layout.preferredWidth: 0
                        Layout.maximumWidth: 0
                        Layout.fillHeight: true
                        visible: false
                        color: "#18313e"
                        Row {
                            anchors.fill: parent
                            Label { width: 72; height: parent.height; text: qsTr("\u5f53\u524d\u503c"); color: "#8fa3b4"; font.pixelSize: 10; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; background: Rectangle { color: "transparent" } }
                            Label { width: 72; height: parent.height; text: qsTr("\u6700\u5c0f\u503c"); color: "#8fa3b4"; font.pixelSize: 10; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; background: Rectangle { color: "transparent" } }
                            Label { width: 72; height: parent.height; text: qsTr("\u6700\u5927\u503c"); color: "#8fa3b4"; font.pixelSize: 10; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; background: Rectangle { color: "transparent" } }
                            Label { width: 72; height: parent.height; text: qsTr("\u5e73\u5747\u503c"); color: "#8fa3b4"; font.pixelSize: 10; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; background: Rectangle { color: "transparent" } }
                            Label { width: 72; height: parent.height; text: qsTr("\u6807\u51c6\u5dee"); color: "#8fa3b4"; font.pixelSize: 10; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; background: Rectangle { color: "transparent" } }
                            Label { width: 42; height: parent.height; text: qsTr("\u6b21\u6570"); color: "#8fa3b4"; font.pixelSize: 10; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; background: Rectangle { color: "transparent" } }
                            Label { width: 42; height: parent.height; text: qsTr("\u5355\u4f4d"); color: "#8fa3b4"; font.pixelSize: 10; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; background: Rectangle { color: "transparent" } }
                            Label { width: 56; height: parent.height; text: qsTr("\u72b6\u6001"); color: "#8fa3b4"; font.pixelSize: 10; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; background: Rectangle { color: "transparent" } }
                        }
                    }
                    Rectangle {
                        Layout.preferredWidth: 106
                        Layout.fillHeight: true
                        color: "#18313e"
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 5
                            anchors.rightMargin: 5
                            spacing: 4
                            Label { Layout.fillWidth: true; text: qsTr("\u64cd\u4f5c"); color: "#8fa3b4"; font.pixelSize: 10; horizontalAlignment: Text.AlignHCenter }
                            AppButton {
                                text: qsTr("\u6e05\u7a7a")
                                implicitWidth: 42
                                implicitHeight: 22
                                enabled: measurementTasks.count > 0
                                fillColor: "#493b3a"
                                onClicked: root.clearAllMeasurementTasks()
                            }
                        }
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 30
                    Layout.preferredHeight: 0
                    Layout.maximumHeight: 0
                    visible: false
                    color: "#10212b"
                    ListView {
                    id: measurementResultRows
                    anchors.fill: parent
                    clip: true
                    model: measurementTasks
                    ScrollBar.vertical: MeasurementScrollBar { }
                    delegate: Rectangle {
                        required property int channelIndex
                        required property string category
                        required property string measurementItem
                        required property string currentText
                        required property string minimumText
                        required property string maximumText
                        required property string averageText
                        required property string deviationText
                        required property int measurementCount
                        required property string unit
                        required property string status
                        required property bool paused
                        width: ListView.view.width
                        height: 30
                        color: "transparent"
                        Rectangle {
                            anchors.fill: parent
                            z: -1
                            color: index % 2 ? "#132936" : "#10242f"
                        }
                        RowLayout {
                            anchors.fill: parent
                            spacing: 0
                            Rectangle {
                                Layout.preferredWidth: 154
                                Layout.fillHeight: true
                                color: "transparent"
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 7
                                    anchors.rightMargin: 7
                                    Label { text: root.channelStore.channel(channelIndex).name; Layout.preferredWidth: 48; color: root.channelStore.channel(channelIndex).color; font.pixelSize: 10 }
                                    Label { text: root.measurementItemText(category, measurementItem); Layout.fillWidth: true; color: "#d9e4ec"; font.pixelSize: 10; elide: Text.ElideRight }
                                }
                            }
                            Flickable {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true
                                contentWidth: 610
                                contentHeight: height
                                flickableDirection: Flickable.HorizontalFlick
                                contentX: measurementResultsTable.statisticsScrollX
                                onContentXChanged: measurementResultsTable.statisticsScrollX = contentX
                                Row {
                                    width: 610; height: parent.height
                                    Repeater {
                                        model: [currentText, minimumText, maximumText, averageText, deviationText, measurementCount, unit, paused ? qsTr("\u5df2\u6682\u505c") : (currentText === "--" ? qsTr("\u65e0\u6548") : qsTr("\u6709\u6548"))]
                                        delegate: Label {
                                            required property var modelData
                                            width: index < 5 ? 88 : index === 5 ? 48 : index === 6 ? 48 : 74
                                            height: 30
                                            text: modelData
                                            color: index === 7 && modelData === qsTr("\u65e0\u6548") ? "#e8a94b" : "#d9e4ec"
                                            font.pixelSize: 10
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                            elide: Text.ElideRight
                                            ToolTip.visible: hovered && index === 7
                                            ToolTip.text: status
                                            ToolTip.delay: 400
                                        }
                                    }
                                }
                            }
                            Rectangle {
                                Layout.preferredWidth: 106
                                Layout.fillHeight: true
                                color: "transparent"
                                Row {
                                    anchors.centerIn: parent
                                    spacing: 3
                                    AppButton { text: paused ? "\u25b6" : "\u23f8"; implicitWidth: 27; implicitHeight: 22; onClicked: root.toggleMeasurementTask(index) }
                                    AppButton { text: "\u21ba"; implicitWidth: 27; implicitHeight: 22; onClicked: root.clearMeasurementStatistics(index) }
                                    AppButton { text: "\u00d7"; implicitWidth: 24; implicitHeight: 22; fillColor: "#493b3a"; onClicked: root.deleteMeasurementTask(index) }
                                }
                            }
                        }
                    }
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 30
                    color: "#10212b"
                    Item {
                        id: measurementRowsFlickable
                        // Retained only while loading an older cached scene.  The active result
                        // rows below are painted by one Canvas to avoid the Windows white backing
                        // surface produced by nested Controls delegates.
                        visible: false
                        anchors.fill: parent
                        anchors.margins: 1
                        clip: true
                        property real scrollOffset: 0
                        readonly property real maximumScrollOffset: Math.max(0, measurementRowsColumn.height - height)
                        WheelHandler {
                            onWheel: event => {
                                measurementRowsFlickable.scrollOffset = Math.max(0, Math.min(measurementRowsFlickable.maximumScrollOffset,
                                                                                                 measurementRowsFlickable.scrollOffset - event.angleDelta.y / 2))
                            }
                        }
                        Rectangle {
                            width: measurementRowsFlickable.width
                            height: measurementRowsFlickable.height
                            color: "#10212b"
                            z: 0
                        }
                        Column {
                            id: measurementRowsColumn
                            width: measurementRowsFlickable.width
                            y: -measurementRowsFlickable.scrollOffset
                            z: 1
                            Repeater {
                                model: measurementTasks
                                delegate: Rectangle {
                                    required property int taskId
                                    required property int channelIndex
                                    required property string category
                                    required property string measurementItem
                                    required property string currentText
                                    required property string minimumText
                                    required property string maximumText
                                    required property string averageText
                                    required property string deviationText
                                    required property int measurementCount
                                    required property string unit
                                    required property string status
                                    required property bool paused
                                    width: measurementRowsColumn.width
                                    height: 30
                                    color: index % 2 ? "#132936" : "#10242f"
                                    // Keep every cell as a directly painted Rectangle.  The former
                                    // RowLayout/transparent-item mix could leave native white backing
                                    // surfaces visible on the MinGW/Windows scene graph backend.
                                    Rectangle {
                                        id: measurementLeftCell
                                        x: 0
                                        width: 154
                                        height: parent.height
                                        color: index % 2 ? "#132936" : "#10242f"
                                        clip: true
                                        Text {
                                            x: 7
                                            width: 48
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: root.channelStore.channel(channelIndex).name
                                            color: root.channelStore.channel(channelIndex).color
                                            font.pixelSize: 10
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                        Text {
                                            x: 55
                                            width: parent.width - x - 7
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: root.measurementItemText(category, measurementItem)
                                            color: "#d9e4ec"
                                            font.pixelSize: 10
                                            elide: Text.ElideRight
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                    }
                                    Rectangle {
                                        id: measurementStatisticsCell
                                        x: measurementLeftCell.width
                                        width: Math.max(0, parent.width - measurementLeftCell.width - measurementOperationCell.width)
                                        height: parent.height
                                        color: index % 2 ? "#132936" : "#10242f"
                                        clip: true
                                        Row {
                                            anchors.fill: parent
                                            Label { width: 72; height: 30; text: currentText; color: "#d9e4ec"; font.pixelSize: 10; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; background: Rectangle { color: "transparent" } }
                                            Label { width: 72; height: 30; text: minimumText; color: "#d9e4ec"; font.pixelSize: 10; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; background: Rectangle { color: "transparent" } }
                                            Label { width: 72; height: 30; text: maximumText; color: "#d9e4ec"; font.pixelSize: 10; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; background: Rectangle { color: "transparent" } }
                                            Label { width: 72; height: 30; text: averageText; color: "#d9e4ec"; font.pixelSize: 10; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; background: Rectangle { color: "transparent" } }
                                            Label { width: 72; height: 30; text: deviationText; color: "#d9e4ec"; font.pixelSize: 10; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; background: Rectangle { color: "transparent" } }
                                            Label { width: 42; height: 30; text: measurementCount; color: "#d9e4ec"; font.pixelSize: 10; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; background: Rectangle { color: "transparent" } }
                                            Label { width: 42; height: 30; text: unit; color: "#d9e4ec"; font.pixelSize: 10; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; background: Rectangle { color: "transparent" } }
                                            Label {
                                                width: 56; height: 30
                                                text: paused ? qsTr("\u5df2\u6682\u505c") : (currentText === "--" ? qsTr("\u65e0\u6548") : qsTr("\u6709\u6548"))
                                                color: currentText === "--" ? "#e8a94b" : "#7ed2c9"
                                                font.pixelSize: 10
                                                horizontalAlignment: Text.AlignHCenter
                                                verticalAlignment: Text.AlignVCenter
                                                elide: Text.ElideRight
                                                background: Rectangle { color: "transparent" }
                                                ToolTip.visible: hovered
                                                ToolTip.text: status
                                            }
                                        }
                                    }
                                    Rectangle {
                                        id: measurementOperationCell
                                        x: parent.width - width
                                        width: 106
                                        height: parent.height
                                        color: index % 2 ? "#132936" : "#10242f"
                                        Row {
                                            anchors.centerIn: parent
                                            spacing: 3
                                            AppButton { text: paused ? "\u25b6" : "\u23f8"; implicitWidth: 27; implicitHeight: 22; onClicked: root.toggleMeasurementTaskById(taskId) }
                                            AppButton { text: "\u21ba"; implicitWidth: 27; implicitHeight: 22; onClicked: root.clearMeasurementStatisticsById(taskId) }
                                            AppButton { text: "\u00d7"; implicitWidth: 24; implicitHeight: 22; fillColor: "#493b3a"; onClicked: root.deleteMeasurementTaskById(taskId) }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Item {
                        id: measurementCanvasRows
                        anchors.fill: parent
                        anchors.margins: 1
                        clip: true
                        property real scrollOffset: 0
                        readonly property real maximumScrollOffset: Math.max(0, measurementTasks.count * 30 - height)

                        function clampScroll(value) {
                            return Math.max(0, Math.min(maximumScrollOffset, value))
                        }

                        WheelHandler {
                            onWheel: event => {
                                measurementCanvasRows.scrollOffset = measurementCanvasRows.clampScroll(
                                            measurementCanvasRows.scrollOffset - event.angleDelta.y / 2)
                                measurementRowsCanvas.requestPaint()
                            }
                        }
                        MouseArea {
                            id: measurementBodyDragArea
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.rightMargin: 106
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            z: 1
                            cursorShape: measurementCanvasRows.maximumScrollOffset > 0 ? Qt.SizeVerCursor : Qt.ArrowCursor
                            property real pressY: 0
                            property real pressOffset: 0
                            onPressed: mouse => {
                                pressY = mouse.y
                                pressOffset = measurementCanvasRows.scrollOffset
                            }
                            onPositionChanged: mouse => {
                                if (pressed && measurementCanvasRows.maximumScrollOffset > 0) {
                                    measurementCanvasRows.scrollOffset = measurementCanvasRows.clampScroll(pressOffset - (mouse.y - pressY))
                                    measurementRowsCanvas.requestPaint()
                                }
                            }
                        }

                        Canvas {
                            id: measurementRowsCanvas
                            anchors.fill: parent
                            renderTarget: Canvas.Image
                            antialiasing: false
                            onWidthChanged: requestPaint()
                            onHeightChanged: requestPaint()
                            onPaint: {
                                const context = getContext("2d")
                                const rowHeight = 30
                                const leftWidth = 154
                                const operationWidth = 106
                                const statisticsWidths = [72, 72, 72, 72, 72, 42, 42, 56]
                                const statisticsOffset = leftWidth
                                const firstRow = Math.max(0, Math.floor(measurementCanvasRows.scrollOffset / rowHeight))
                                const lastRow = Math.min(measurementTasks.count, Math.ceil((measurementCanvasRows.scrollOffset + height) / rowHeight))

                                context.fillStyle = "#10212b"
                                context.fillRect(0, 0, width, height)
                                // Canvas has unreliable CJK fallback on some Windows Qt builds.
                                // Chinese labels are rendered by the QML Text overlays below.
                                for (let row = firstRow; row < lastRow; ++row) {
                                    const top = row * rowHeight - measurementCanvasRows.scrollOffset
                                    const rowColor = row % 2 ? "#132936" : "#10242f"
                                    context.fillStyle = rowColor
                                    context.fillRect(0, top, width, rowHeight)
                                    context.fillStyle = "#203b48"
                                    context.fillRect(0, top + rowHeight - 1, width, 1)
                                }
                            }
                        }
                        Timer {
                            interval: 250
                            repeat: true
                            running: measurementCanvasRows.visible
                            onTriggered: measurementRowsCanvas.requestPaint()
                        }
                        Repeater {
                            model: measurementTasks
                            delegate: Item {
                                required property int taskId
                                required property int channelIndex
                                required property string category
                                required property string measurementItem
                                required property string currentText
                                required property string minimumText
                                required property string maximumText
                                required property string averageText
                                required property string deviationText
                                required property int measurementCount
                                required property string unit
                                required property bool paused
                                required property string statisticsMode
                                x: 0
                                y: root.measurementTaskIndexById(taskId) * 30 - measurementCanvasRows.scrollOffset
                                width: measurementCanvasRows.width - 106
                                height: 30
                                z: 2
                                layer.enabled: true
                                layer.smooth: false
                                visible: y + height > 0 && y < measurementCanvasRows.height
                                Text {
                                    x: 7
                                    width: 48
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.channelStore.channel(channelIndex).name
                                    color: root.channelStore.channel(channelIndex).color
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                }
                                Text {
                                    x: 55
                                    width: 99
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.measurementItemText(category, measurementItem)
                                    color: "#d9e4ec"
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                }
                                Item {
                                    x: 154
                                    width: Math.max(0, parent.width - x)
                                    height: parent.height
                                    clip: true
                                    Text { x: 0 - measurementResultsTable.statisticsScrollX; width: 72; anchors.verticalCenter: parent.verticalCenter; text: currentText; color: "#d9e4ec"; font.pixelSize: 10; horizontalAlignment: Text.AlignHCenter }
                                    Text { x: 72 - measurementResultsTable.statisticsScrollX; width: 72; anchors.verticalCenter: parent.verticalCenter; text: statisticsMode === "current" ? "—" : minimumText; color: "#d9e4ec"; font.pixelSize: 10; horizontalAlignment: Text.AlignHCenter }
                                    Text { x: 144 - measurementResultsTable.statisticsScrollX; width: 72; anchors.verticalCenter: parent.verticalCenter; text: statisticsMode === "current" ? "—" : maximumText; color: "#d9e4ec"; font.pixelSize: 10; horizontalAlignment: Text.AlignHCenter }
                                    Text { x: 216 - measurementResultsTable.statisticsScrollX; width: 72; anchors.verticalCenter: parent.verticalCenter; text: statisticsMode === "current" ? "—" : averageText; color: "#d9e4ec"; font.pixelSize: 10; horizontalAlignment: Text.AlignHCenter }
                                    Text { x: 288 - measurementResultsTable.statisticsScrollX; width: 72; anchors.verticalCenter: parent.verticalCenter; text: statisticsMode === "current" ? "—" : deviationText; color: "#d9e4ec"; font.pixelSize: 10; horizontalAlignment: Text.AlignHCenter }
                                    Text { x: 360 - measurementResultsTable.statisticsScrollX; width: 42; anchors.verticalCenter: parent.verticalCenter; text: statisticsMode === "current" ? "—" : measurementCount; color: "#d9e4ec"; font.pixelSize: 10; horizontalAlignment: Text.AlignHCenter }
                                    Text { x: 402 - measurementResultsTable.statisticsScrollX; width: 42; anchors.verticalCenter: parent.verticalCenter; text: unit; color: "#d9e4ec"; font.pixelSize: 10; horizontalAlignment: Text.AlignHCenter }
                                    Text {
                                        x: 444 - measurementResultsTable.statisticsScrollX
                                        width: 56
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: paused ? qsTr("\u5df2\u6682\u505c") : (currentText === "--" ? qsTr("\u65e0\u6548") : (statisticsMode === "current" ? qsTr("\u5b9e\u65f6") : qsTr("\u6709\u6548")))
                                        color: currentText === "--" ? "#e8a94b" : "#7ed2c9"
                                        font.pixelSize: 10
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                        Repeater {
                            model: measurementTasks
                            delegate: Item {
                                required property int taskId
                                required property bool paused
                                width: 106
                                height: 30
                                x: measurementCanvasRows.width - width
                                y: root.measurementTaskIndexById(taskId) * 30 - measurementCanvasRows.scrollOffset
                                z: 3
                                layer.enabled: true
                                layer.smooth: false
                                visible: y + height > 0 && y < measurementCanvasRows.height
                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 4
                                    MeasurementOperationButton {
                                        text: paused ? "\u25b6" : "\u23f8"
                                        onClicked: root.toggleMeasurementTaskById(taskId)
                                    }
                                    MeasurementOperationButton {
                                        text: "\u21ba"
                                        onClicked: root.clearMeasurementStatisticsById(taskId)
                                    }
                                    MeasurementOperationButton {
                                        text: "\u00d7"; fillColor: "#493b3a"
                                        onClicked: root.deleteMeasurementTaskById(taskId)
                                    }
                                }
                            }
                        }
                        Rectangle {
                            id: measurementScrollTrack
                            width: 5
                            x: parent.width - width
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            color: "#18313e"
                            visible: measurementCanvasRows.maximumScrollOffset > 0
                            radius: 2
                            z: 4
                            Rectangle {
                                id: measurementScrollHandle
                                width: parent.width
                                height: Math.max(24, parent.height * parent.height / Math.max(parent.height, measurementTasks.count * 30))
                                y: (parent.height - height) * measurementCanvasRows.scrollOffset / Math.max(1, measurementCanvasRows.maximumScrollOffset)
                                color: "#4b8692"
                                radius: 2
                            }
                            MouseArea {
                                anchors.fill: parent
                                onPressed: mouse => {
                                    measurementCanvasRows.scrollOffset = measurementCanvasRows.clampScroll(mouse.y / height * measurementCanvasRows.maximumScrollOffset)
                                    measurementRowsCanvas.requestPaint()
                                }
                                onPositionChanged: mouse => {
                                    if (pressed) {
                                        measurementCanvasRows.scrollOffset = measurementCanvasRows.clampScroll(mouse.y / height * measurementCanvasRows.maximumScrollOffset)
                                        measurementRowsCanvas.requestPaint()
                                    }
                                }
                            }
                        }
                    }
                }
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

            Item { Layout.preferredWidth: 8 }

            ActionButton {
                text: root.manualDisplayPaused ? qsTr("\u7ee7\u7eed\u663e\u793a") : qsTr("\u6682\u505c\u663e\u793a")
                enabled: root.simulationRunning && !root.singleTriggerFrozen
                fillColor: root.manualDisplayPaused ? "#168b7c" : "#294556"
                onClicked: root.manualDisplayPauseRequested()
            }

            ActionButton {
                text: qsTr("\u5782\u76f4\u9002\u914d")
                onClicked: root.verticalFitRequested()
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
