import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import QtQuick.Layouts

Rectangle {
    id: root
    required property var playback
    property int selectedBoard: 0
    property var draftChannelIds: []
    property string selectionMessage: ""
    property int selectedPlaybackChannelId: -1
    property var channelViewSettings: ({})
    property bool waveformLabelsVisible: true
    property bool exportWholeRecord: false
    property bool exportAllRecordedChannels: false
    property string exportFormat: "csv"
    property url exportTargetUrl
    // 5,000 S/s 时相邻样本间隔为 0.2 ms；默认步长不应粗于一个样本。
    property int navigationStepIndex: 0
    readonly property real samplePeriodSeconds: playback.sampleRate > 0 ? 1 / playback.sampleRate : 0.0002
    readonly property var navigationSteps: [
        { "text": (samplePeriodSeconds * 1000).toFixed(4).replace(/0+$/, "").replace(/\.$/, "") + " ms", "seconds": samplePeriodSeconds },
        { "text": "1 ms", "seconds": 0.001 },
        { "text": "10 ms", "seconds": 0.01 },
        { "text": "100 ms", "seconds": 0.1 },
        { "text": "1 s", "seconds": 1.0 },
        { "text": "10 s", "seconds": 10.0 }
    ]
    readonly property real navigationStepSeconds: navigationSteps[navigationStepIndex].seconds
    readonly property var verticalRangeValues: [.1, .2, .5, 1, 2, 5]
    color: "#101922"

    function duration(value) {
        const tenthMilliseconds = Math.max(0, Math.round(Number(value || 0) * 10000))
        const wholeSeconds = Math.floor(tenthMilliseconds / 10000)
        const fraction = String(tenthMilliseconds % 10000).padStart(4, "0")
        return String(Math.floor(wholeSeconds / 3600)).padStart(2, "0")
                + ":" + String(Math.floor(wholeSeconds / 60) % 60).padStart(2, "0")
                + ":" + String(wholeSeconds % 60).padStart(2, "0") + "." + fraction
    }
    function bytes(value) { const units = ["B", "KiB", "MiB", "GiB"]; let n = Number(value), i = 0; while (n >= 1024 && i < 3) { n /= 1024; ++i } return n.toFixed(i ? 1 : 0) + " " + units[i] }
    function timePerDivText(seconds) {
        if (seconds >= 1)
            return seconds.toFixed(seconds < 10 ? 3 : 1).replace(/0+$/, "").replace(/\.$/, "") + " s/div"
        const milliseconds = seconds * 1000
        return (milliseconds < 1 ? milliseconds.toFixed(4) : milliseconds.toFixed(milliseconds < 10 ? 1 : 0)).replace(/\.0$/, "") + " ms/div"
    }
    function channelColor(index) { return ["#39e6bb", "#f2d05c", "#72d18c", "#c58bea", "#f0a35e", "#63b3ed", "#ef7aa8", "#a6d96a"][index % 8] }
    readonly property int boardCount: 8
    function recordedChannel(id) { for (let index = 0; index < playback.channels.length; ++index) if (playback.channels[index].id === id) return playback.channels[index]; return null }
    function draftContains(id) { return draftChannelIds.indexOf(id) >= 0 }
    function openChannelSelector() { draftChannelIds = playback.channels.filter(channel => channel.enabled).map(channel => channel.id); selectionMessage = ""; selectedBoard = 0; channelSelector.open() }
    function toggleDraft(id) { const position = draftChannelIds.indexOf(id); if (position >= 0) { const next = draftChannelIds.slice(); next.splice(position, 1); draftChannelIds = next; selectionMessage = "" } else if (draftChannelIds.length >= 8) { selectionMessage = qsTr("\u6700\u591a\u540c\u65f6\u663e\u793a8\u4e2a\u901a\u9053\u3002") } else { draftChannelIds = draftChannelIds.concat([id]); selectionMessage = "" } }
    function viewSettings(id) { return channelViewSettings[id] || { voltsPerDiv: 1.0, verticalOffsetV: 0.0 } }
    function setViewSettings(id, voltsPerDiv, verticalOffsetV) { const next = Object.assign({}, channelViewSettings); next[id] = { voltsPerDiv: voltsPerDiv, verticalOffsetV: verticalOffsetV }; channelViewSettings = next; canvas.requestPaint() }
    function selectPlaybackChannel(id) { selectedPlaybackChannelId = id; canvas.requestPaint() }
    function selectedSettings() { return viewSettings(selectedPlaybackChannelId) }
    function resetSelectedVertical() { if (selectedPlaybackChannelId >= 0) setViewSettings(selectedPlaybackChannelId, 1.0, 0.0) }
    function moveSelectedVertical(delta) { if (selectedPlaybackChannelId >= 0) { const settings = selectedSettings(); setViewSettings(selectedPlaybackChannelId, settings.voltsPerDiv, settings.verticalOffsetV + delta) } }
    function setSelectedVoltsPerDiv(value) { if (selectedPlaybackChannelId >= 0) { const settings = selectedSettings(); setViewSettings(selectedPlaybackChannelId, value, settings.verticalOffsetV) } }
    function selectedRangeIndex() { return Math.max(0, verticalRangeValues.indexOf(selectedSettings().voltsPerDiv)) }
    function fitSelectedVertical() {
        if (selectedPlaybackChannelId < 0) return
        const frame = playback.frames.find(item => item.id === selectedPlaybackChannelId)
        if (!frame || !frame.points.length) return
        let minimum = Infinity, maximum = -Infinity
        for (let index = 0; index < frame.points.length; ++index) { minimum = Math.min(minimum, frame.points[index].v); maximum = Math.max(maximum, frame.points[index].v) }
        const peakToPeak = Math.max(.001, maximum - minimum), ranges = [.1, .2, .5, 1, 2, 5]
        let voltsPerDiv = ranges[ranges.length - 1]
        // Each playback view has four vertical divisions.  Keep 20% headroom
        // instead of using the real-time page's larger division count.
        for (let index = 0; index < ranges.length; ++index) if (peakToPeak <= ranges[index] * 3.2) { voltsPerDiv = ranges[index]; break }
        setViewSettings(selectedPlaybackChannelId, voltsPerDiv, -(maximum + minimum) / 2)
    }
    readonly property var timePerDivOptions: [
        { "text": root.timePerDivText(samplePeriodSeconds), "seconds": samplePeriodSeconds },
        { "text": "0.5 ms/div", "seconds": .0005 }, { "text": "1 ms/div", "seconds": .001 },
        { "text": "2 ms/div", "seconds": .002 }, { "text": "5 ms/div", "seconds": .005 },
        { "text": "10 ms/div", "seconds": .01 }, { "text": "20 ms/div", "seconds": .02 },
        { "text": "50 ms/div", "seconds": .05 }, { "text": "100 ms/div", "seconds": .1 },
        { "text": "200 ms/div", "seconds": .2 }, { "text": "500 ms/div", "seconds": .5 }, { "text": "1 s/div", "seconds": 1 }
    ]
    function closestTimePerDivIndex() { const current = playback.viewDurationSeconds / 10; let closest = 0, distance = Infinity; for (let index = 0; index < timePerDivOptions.length; ++index) { const candidate = Math.abs(timePerDivOptions[index].seconds - current); if (candidate < distance) { closest = index; distance = candidate } } return closest }
    function setTimePerDiv(seconds) { const centre = playback.viewStartSeconds + playback.viewDurationSeconds / 2; const durationSeconds = seconds * 10; playback.setView(centre - durationSeconds / 2, durationSeconds) }
    function exportRangeTag() {
        const start = exportWholeRecord ? 0 : playback.viewStartSeconds
        const end = exportWholeRecord ? playback.durationSeconds : Math.min(playback.durationSeconds, playback.viewStartSeconds + playback.viewDurationSeconds)
        return "t_" + start.toFixed(4).replace(".", "_") + "s_to_" + end.toFixed(4).replace(".", "_") + "s"
    }
    function openExportSettings() { exportTargetUrl = playback.suggestedExportUrl(exportRangeTag(), exportFormat); exportSettings.open() }

    FolderDialog { id: folderDialog; title: qsTr("\u9009\u62e9\u5f55\u5236\u4f1a\u8bdd\u76ee\u5f55"); onAccepted: root.playback.loadSessionUrl(selectedFolder) }
    FileDialog {
        id: exportFileDialog
        title: root.exportFormat === "mat" ? qsTr("保存 MAT 数据") : qsTr("保存导出数据")
        fileMode: FileDialog.SaveFile
        nameFilters: [root.exportFormat === "float32" ? "Float32 files (*.f32)"
            : root.exportFormat === "mat" ? "MATLAB MAT files (*.mat)" : "CSV files (*.csv)"]
        onAccepted: root.exportTargetUrl = selectedFile
    }

    component ActionButton: AppButton { fillColor: primary ? "#168b7c" : "#223542" }
    component SummaryCard: Rectangle {
        required property string title
        required property string value
        Layout.fillWidth: true; implicitHeight: 58; radius: 4; color: "#182b38"; border.color: "#314252"
        ColumnLayout { anchors.fill: parent; anchors.margins: 8; spacing: 1
            Label { text: parent.parent.title; color: "#8fa3b4"; font.pixelSize: 11 }
            Label { text: parent.parent.value; color: "#e6f0f5"; font.pixelSize: 14; font.bold: true; wrapMode: Text.WordWrap; maximumLineCount: 2; Layout.fillWidth: true }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 10
        RowLayout {
            Layout.fillWidth: true
            Label { text: qsTr("\u5386\u53f2\u56de\u653e"); color: "#d9e4ec"; font.pixelSize: 21; font.bold: true }
            Item { Layout.fillWidth: true }
            Label { text: playback.status === "ready" ? qsTr("\u6821\u9a8c\u5b8c\u6210") : playback.status === "error" ? qsTr("\u6587\u4ef6\u9519\u8bef") : qsTr("\u672a\u52a0\u8f7d"); color: playback.status === "ready" ? "#35d19b" : playback.status === "error" ? "#f07d72" : "#8fa3b4"; font.bold: true }
        }
        Rectangle {
            Layout.fillWidth: true; implicitHeight: 58; radius: 5; color: "#172b37"; border.color: "#365467"
            RowLayout { anchors.fill: parent; anchors.margins: 12; spacing: 10
                Label { text: playback.sessionDirectory.length ? playback.sessionDirectory : qsTr("\u8bf7\u9009\u62e9\u5df2\u5b8c\u6210\u7684\u5f55\u5236\u4f1a\u8bdd"); color: "#d9e4ec"; font.pixelSize: 13; elide: Text.ElideMiddle; Layout.fillWidth: true }
                ActionButton { text: qsTr("\u6253\u5f00\u8bb0\u5f55"); primary: true; onClicked: folderDialog.open() }
            }
        }
        // “校验完成”由右上角状态标签表达；这里只保留需要用户处理的错误详情。
        Label { visible: playback.status === "error" && playback.detail.length > 0; text: playback.detail; color: "#f07d72"; font.pixelSize: 12; Layout.fillWidth: true; elide: Text.ElideMiddle }
        GridLayout {
            Layout.fillWidth: true; columns: 4; columnSpacing: 8
            SummaryCard { title: qsTr("\u91c7\u6837\u7387"); value: playback.sampleRate + " S/s" }
            SummaryCard { title: qsTr("\u5f55\u5236\u901a\u9053\u603b\u6570"); value: playback.channels.length + qsTr(" \u8def") }
            SummaryCard { title: qsTr("\u6570\u636e\u65f6\u957f"); value: root.duration(playback.durationSeconds) }
            SummaryCard { title: qsTr("\u6587\u4ef6\u5927\u5c0f / \u65ad\u5c42"); value: root.bytes(playback.dataBytes) + " / " + playback.gapCount }
        }
        RowLayout {
            Layout.fillWidth: true; Layout.preferredHeight: 34
            AppButton {
                id: channelSelectionTool
                enabled: playback.status === "ready"
                implicitWidth: 142
                implicitHeight: 34
                onClicked: root.openChannelSelector()
                contentItem: Row {
                    anchors.centerIn: parent
                    spacing: 8
                    Text {
                        text: qsTr("\u9009\u62e9\u901a\u9053")
                        color: channelSelectionTool.enabled ? "#d9f6f2" : "#71818d"
                        font.pixelSize: 13
                        font.bold: true
                        verticalAlignment: Text.AlignVCenter
                    }
                    Rectangle {
                        width: 32
                        height: 20
                        radius: 10
                        color: channelSelectionTool.enabled ? "#168b7c" : "#2d3d47"
                        Text {
                            anchors.centerIn: parent
                            text: playback.displayedChannelCount + "/8"
                            color: channelSelectionTool.enabled ? "#ffffff" : "#8fa3b4"
                            font.pixelSize: 11
                            font.bold: true
                        }
                    }
                }
                fillColor: "#1b313d"
                selectedBorderColor: "#2b8990"
            }
            Rectangle { visible: root.selectedPlaybackChannelId >= 0; Layout.preferredWidth: visible ? 1 : 0; Layout.preferredHeight: 24; Layout.alignment: Qt.AlignVCenter; color: "#365467" }
            Label {
                visible: root.selectedPlaybackChannelId >= 0
                text: root.selectedPlaybackChannelId >= 0 ? "CH" + (root.selectedPlaybackChannelId + 1) : qsTr("未选中")
                color: root.selectedPlaybackChannelId >= 0 ? root.channelColor(root.selectedPlaybackChannelId) : "#71818d"
                font.pixelSize: 12
                font.bold: true
            }
            ComboBox {
                id: playbackVoltsPerDiv
                visible: root.selectedPlaybackChannelId >= 0
                enabled: visible
                Layout.preferredWidth: visible ? 92 : 0
                implicitHeight: 30
                model: root.verticalRangeValues
                currentIndex: root.selectedRangeIndex()
                onActivated: root.setSelectedVoltsPerDiv(currentValue)
                contentItem: Text { leftPadding: 8; rightPadding: 18; text: playbackVoltsPerDiv.currentValue + " V/div"; color: playbackVoltsPerDiv.enabled ? "#d9e4ec" : "#71818d"; font.pixelSize: 12; verticalAlignment: Text.AlignVCenter; elide: Text.ElideNone }
                background: Rectangle { radius: 3; color: "#1a2a36"; border.color: playbackVoltsPerDiv.enabled ? "#3a6574" : "#365467" }
            }
            ActionButton { visible: root.selectedPlaybackChannelId >= 0; text: qsTr("上移"); enabled: visible; onClicked: root.moveSelectedVertical(root.selectedSettings().voltsPerDiv) }
            ActionButton { visible: root.selectedPlaybackChannelId >= 0; text: qsTr("下移"); enabled: visible; onClicked: root.moveSelectedVertical(-root.selectedSettings().voltsPerDiv) }
            ActionButton { visible: root.selectedPlaybackChannelId >= 0; text: qsTr("归零"); enabled: visible; onClicked: root.resetSelectedVertical() }
            ActionButton { visible: root.selectedPlaybackChannelId >= 0; text: qsTr("自动适配"); enabled: visible; onClicked: root.fitSelectedVertical() }
            ActionButton { text: root.waveformLabelsVisible ? qsTr("隐藏标注") : qsTr("显示标注"); enabled: playback.status === "ready"; onClicked: { root.waveformLabelsVisible = !root.waveformLabelsVisible; canvas.requestPaint() } }
            ActionButton { text: qsTr("导出数据"); enabled: playback.status === "ready" && !playback.exportingData; onClicked: root.openExportSettings() }
            Item { Layout.fillWidth: true }
        }
        Label { visible: playback.status === "ready" && playback.displayedChannelCount === 0; text: qsTr("\u8bf7\u9009\u62e9\u81f3\u5c11\u4e00\u4e2a\u56de\u653e\u901a\u9053\u3002"); color: "#e8a94b"; font.pixelSize: 12 }
        Rectangle {
            Layout.fillWidth: true; Layout.fillHeight: true; color: "#10242f"; border.color: "#365467"; clip: true
            Canvas {
                id: canvas; anchors.fill: parent; anchors.margins: 1
                Connections {
                    target: playback
                    function onChanged() {
                        if (!playback.frames.some(frame => frame.id === root.selectedPlaybackChannelId) && playback.frames.length)
                            root.selectedPlaybackChannelId = playback.frames[0].id
                        canvas.requestPaint()
                    }
                }
                onPaint: {
                    const ctx = getContext("2d"), w = width, h = height, frames = playback.frames
                    ctx.fillStyle = "#10242f"; ctx.fillRect(0, 0, w, h)
                    if (!frames.length) return
                    const viewH = h / frames.length
                    for (let i = 0; i < frames.length; ++i) {
                        const top = i * viewH, frame = frames[i], points = frame.points, lineColor = root.channelColor(i), settings = root.viewSettings(frame.id), divisionHeight = viewH / 4
                        ctx.fillStyle = i % 2 ? "#112833" : "#10242f"; ctx.fillRect(0, top, w, viewH)
                        // A manual offset or an out-of-range value must never draw into
                        // another channel's viewport.
                        ctx.save(); ctx.beginPath(); ctx.rect(0, top, w, viewH); ctx.clip()
                        ctx.strokeStyle = "#1e4350"; ctx.lineWidth = 1
                        for (let x = 0; x <= 10; ++x) { ctx.beginPath(); ctx.moveTo(x * w / 10, top); ctx.lineTo(x * w / 10, top + viewH); ctx.stroke() }
                        ctx.strokeStyle = "#4a8290"; ctx.setLineDash([3, 3]); ctx.beginPath(); ctx.moveTo(0, top + viewH / 2); ctx.lineTo(w, top + viewH / 2); ctx.stroke(); ctx.setLineDash([])
                        if (frame.id === root.selectedPlaybackChannelId) { ctx.strokeStyle = lineColor; ctx.lineWidth = 1; ctx.strokeRect(.5, top + .5, w - 1, viewH - 1) }
                        if (root.waveformLabelsVisible) { ctx.fillStyle = lineColor; ctx.fillText(frame.name + " \u00b7 " + settings.voltsPerDiv + " V/div", 8, top + 14) }
                        ctx.strokeStyle = lineColor; ctx.lineWidth = 1.2; ctx.beginPath(); let drawn = false
                        function point(value, x) { const y = top + viewH / 2 - (value + settings.verticalOffsetV) * divisionHeight / settings.voltsPerDiv; if (!drawn) { ctx.moveTo(x, y); drawn = true } else ctx.lineTo(x, y) }
                        if (points.length <= Math.max(1, Math.floor(w))) {
                            for (let p = 0; p < points.length; ++p) {
                                const sample = points[p]
                                point(sample.v, (sample.t - playback.viewStartSeconds) / playback.viewDurationSeconds * w)
                            }
                        } else {
                            // Preserve high-frequency content without fixed-stride aliasing.
                            const columns = Math.max(1, Math.floor(w)), minimums = new Array(columns), maximums = new Array(columns)
                            for (let p = 0; p < points.length; ++p) {
                                const sample = points[p]
                                const x = (sample.t - playback.viewStartSeconds) / playback.viewDurationSeconds * w
                                const column = Math.max(0, Math.min(columns - 1, Math.floor(x)))
                                if (minimums[column] === undefined || sample.v < minimums[column]) minimums[column] = sample.v
                                if (maximums[column] === undefined || sample.v > maximums[column]) maximums[column] = sample.v
                            }
                            for (let column = 0; column < columns; ++column) {
                                if (minimums[column] !== undefined)
                                    point((minimums[column] + maximums[column]) / 2, (column + .5) / columns * w)
                            }
                            if (drawn) ctx.stroke()
                            // With many samples per pixel, the min/max vertical envelope is
                            // intentional: it preserves the complete amplitude range and avoids
                            // false gaps caused by connecting unrelated extrema across columns.
                            ctx.globalAlpha = .46; ctx.lineWidth = 1; ctx.beginPath()
                            for (let column = 0; column < columns; ++column) {
                                if (minimums[column] !== undefined) {
                                    const x = (column + .5) / columns * w
                                    const minimumY = top + viewH / 2 - (minimums[column] + settings.verticalOffsetV) * divisionHeight / settings.voltsPerDiv
                                    const maximumY = top + viewH / 2 - (maximums[column] + settings.verticalOffsetV) * divisionHeight / settings.voltsPerDiv
                                    ctx.moveTo(x, minimumY)
                                    ctx.lineTo(x, maximumY)
                                }
                            }
                            ctx.stroke(); ctx.globalAlpha = 1; drawn = false
                        }
                        if (drawn) ctx.stroke()
                        ctx.restore()
                    }
                }
            }
            MouseArea {
                anchors.fill: parent
                enabled: playback.frames.length > 0
                onPressed: mouse => {
                    const viewHeight = height / playback.frames.length
                    const index = Math.max(0, Math.min(playback.frames.length - 1, Math.floor(mouse.y / viewHeight)))
                    root.selectPlaybackChannel(playback.frames[index].id)
                }
            }
            Label {
                anchors.centerIn: parent
                visible: playback.status !== "ready"
                text: qsTr("打开记录后，可在此选择通道并回放波形")
                color: "#718b9a"
                font.pixelSize: 15
            }
        }
        RowLayout { visible: playback.status === "ready"; Layout.fillWidth: true
            ActionButton { text: qsTr("\u5de6\u79fb"); enabled: playback.status === "ready" && playback.viewStartSeconds > root.samplePeriodSeconds * .5; onClicked: playback.moveView(-root.navigationStepSeconds) }
            ActionButton { text: qsTr("\u53f3\u79fb"); enabled: playback.status === "ready" && playback.viewStartSeconds + playback.viewDurationSeconds < playback.durationSeconds - root.samplePeriodSeconds * .5; onClicked: playback.moveView(root.navigationStepSeconds) }
            ActionButton { text: qsTr("\u590d\u4f4d"); enabled: playback.status === "ready"; onClicked: playback.resetView() }
            Label { text: qsTr("\u7a97\u53e3\uff1a\u5f53\u524d ") + root.duration(playback.viewStartSeconds) + " ～ " + qsTr("\u6700\u5927 ") + root.duration(playback.durationSeconds); color: "#8fa3b4"; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter }
            Label { text: qsTr("\u6b65\u957f"); color: "#8fa3b4"; font.pixelSize: 12 }
            ComboBox {
                id: navigationStepSelector
                Layout.preferredWidth: 78
                implicitHeight: 30
                model: root.navigationSteps
                textRole: "text"
                valueRole: "seconds"
                currentIndex: root.navigationStepIndex
                onActivated: root.navigationStepIndex = currentIndex
                contentItem: Text { leftPadding: 8; rightPadding: 20; text: navigationStepSelector.displayText; color: "#d9e4ec"; font.pixelSize: 12; verticalAlignment: Text.AlignVCenter; elide: Text.ElideNone }
                background: Rectangle { radius: 3; color: "#1a2a36"; border.color: "#3a5263" }
            }
            Label { text: qsTr("time/div"); color: "#8fa3b4"; font.pixelSize: 12 }
            ComboBox {
                id: timePerDivSelector
                enabled: playback.status === "ready"
                Layout.preferredWidth: 106
                implicitHeight: 30
                model: root.timePerDivOptions
                textRole: "text"
                valueRole: "seconds"
                currentIndex: root.closestTimePerDivIndex()
                onActivated: root.setTimePerDiv(currentValue)
                contentItem: Text { leftPadding: 8; rightPadding: 18; text: timePerDivSelector.displayText; color: timePerDivSelector.enabled ? "#d9e4ec" : "#71818d"; font.pixelSize: 12; verticalAlignment: Text.AlignVCenter; elide: Text.ElideNone }
                background: Rectangle { radius: 3; color: "#1a2a36"; border.color: timePerDivSelector.enabled ? "#3a6574" : "#365467" }
            }
        }
        Rectangle {
            visible: playback.status === "ready"
            Layout.fillWidth: true
            implicitHeight: 32
            radius: 4
            color: "#152733"
            border.color: "#314252"
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 8
                Label { text: qsTr("\u65f6\u95f4\u5b9a\u4f4d"); color: "#8fa3b4"; font.pixelSize: 12 }
                Slider {
                    id: timeNavigator
                    Layout.fillWidth: true
                    enabled: playback.status === "ready" && playback.durationSeconds > playback.viewDurationSeconds
                    from: 0
                    to: Math.max(0, playback.durationSeconds - playback.viewDurationSeconds)
                    value: playback.viewStartSeconds
                    stepSize: root.navigationStepSeconds
                    onMoved: playback.setView(value, playback.viewDurationSeconds)
                    background: Rectangle { x: timeNavigator.leftPadding; y: timeNavigator.topPadding + timeNavigator.availableHeight / 2 - height / 2; width: timeNavigator.availableWidth; height: 4; radius: 2; color: "#294250" }
                    handle: Rectangle { x: timeNavigator.leftPadding + timeNavigator.visualPosition * (timeNavigator.availableWidth - width); y: timeNavigator.topPadding + timeNavigator.availableHeight / 2 - height / 2; width: 12; height: 12; radius: 6; color: timeNavigator.pressed ? "#39e6bb" : "#79bfc1" }
                }
                Label { text: root.duration(playback.durationSeconds); color: "#8fa3b4"; font.pixelSize: 12; Layout.preferredWidth: 64; horizontalAlignment: Text.AlignRight }
            }
        }
    }

    Popup {
        id: exportSettings
        parent: Overlay.overlay
        modal: true
        focus: true
        width: Math.min(480, parent.width - 48)
        height: 294
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        padding: 0
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle { color: "#142631"; border.color: "#3a6574"; radius: 6 }
        contentItem: ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10
            Label { text: qsTr("导出数据"); color: "#d9e4ec"; font.pixelSize: 17; font.bold: true }
            RowLayout {
                Layout.fillWidth: true
                Label { text: qsTr("导出格式"); color: "#8fa3b4"; Layout.preferredWidth: 72 }
                ComboBox {
                    id: exportFormatSelector
                    Layout.fillWidth: true
                    model: ["CSV", "Float32 + JSON", "MAT"]
                    currentIndex: root.exportFormat === "float32" ? 1 : root.exportFormat === "mat" ? 2 : 0
                    onActivated: {
                        root.exportFormat = currentIndex === 1 ? "float32" : currentIndex === 2 ? "mat" : "csv"
                        root.exportTargetUrl = playback.suggestedExportUrl(root.exportRangeTag(), root.exportFormat)
                    }
                    contentItem: Text { leftPadding: 8; text: exportFormatSelector.displayText; color: "#d9e4ec"; font.pixelSize: 13; verticalAlignment: Text.AlignVCenter }
                    background: Rectangle { radius: 3; color: "#1a2a36"; border.color: "#3a5263" }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Label { text: qsTr("导出范围"); color: "#8fa3b4"; Layout.preferredWidth: 72 }
                ComboBox {
                    id: exportRangeSelector
                    Layout.fillWidth: true
                    model: [qsTr("当前时间窗口"), qsTr("全部记录")]
                    currentIndex: root.exportWholeRecord ? 1 : 0
                    onActivated: { root.exportWholeRecord = currentIndex === 1; root.exportTargetUrl = playback.suggestedExportUrl(root.exportRangeTag(), root.exportFormat) }
                    contentItem: Text { leftPadding: 8; text: exportRangeSelector.displayText; color: "#d9e4ec"; font.pixelSize: 13; verticalAlignment: Text.AlignVCenter }
                    background: Rectangle { radius: 3; color: "#1a2a36"; border.color: "#3a5263" }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Label { text: qsTr("导出通道"); color: "#8fa3b4"; Layout.preferredWidth: 72 }
                ComboBox {
                    id: exportChannelSelector
                    Layout.fillWidth: true
                    model: [qsTr("当前显示的通道"), qsTr("全部录制通道")]
                    currentIndex: root.exportAllRecordedChannels ? 1 : 0
                    onActivated: root.exportAllRecordedChannels = currentIndex === 1
                    contentItem: Text { leftPadding: 8; text: exportChannelSelector.displayText; color: "#d9e4ec"; font.pixelSize: 13; verticalAlignment: Text.AlignVCenter }
                    background: Rectangle { radius: 3; color: "#1a2a36"; border.color: "#3a5263" }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Label { text: qsTr("保存文件"); color: "#8fa3b4"; Layout.preferredWidth: 72 }
                Label { text: root.exportTargetUrl.toString(); color: "#d9e4ec"; font.pixelSize: 12; elide: Text.ElideMiddle; Layout.fillWidth: true }
                ActionButton { text: qsTr("选择位置"); onClicked: { exportFileDialog.currentFile = root.exportTargetUrl; exportFileDialog.open() } }
            }
            Item { Layout.fillHeight: true }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                ActionButton { text: qsTr("取消"); onClicked: exportSettings.close() }
                ActionButton {
                    text: qsTr("开始导出")
                    primary: true
                    enabled: root.exportTargetUrl.toString().length > 0
                    onClicked: { if (playback.beginDataExport(root.exportTargetUrl, root.exportWholeRecord, root.exportAllRecordedChannels, root.exportFormat)) exportSettings.close() }
                }
            }
        }
    }

    Popup {
        id: channelSelector
        parent: Overlay.overlay
        modal: true
        focus: true
        width: Math.min(620, parent.width - 48)
        height: 318
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        padding: 0
        closePolicy: Popup.NoAutoClose
        background: Rectangle { color: "#142631"; border.color: "#3a6574"; radius: 6 }
        contentItem: ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10
            RowLayout {
                Layout.fillWidth: true
                Label { text: qsTr("\u9009\u62e9\u56de\u653e\u901a\u9053"); color: "#d9e4ec"; font.pixelSize: 17; font.bold: true }
                Item { Layout.fillWidth: true }
                Label { text: root.draftChannelIds.length + "/8"; color: root.draftChannelIds.length >= 8 ? "#e8a94b" : "#35d19b"; font.bold: true }
            }
            RowLayout {
                Layout.fillWidth: true
                Repeater {
                    model: root.boardCount
                    delegate: AppButton {
                        id: boardButton
                        readonly property bool available: root.playback.channels.some(channel => Math.floor(channel.id / 8) === index)
                        text: qsTr("\u677f\u5361") + (index + 1)
                        enabled: available
                        implicitHeight: 28
                        selected: root.selectedBoard === index
                        fillColor: "#162630"
                        selectedFillColor: "#235d67"
                        textColor: "#8fa3b4"
                        selectedTextColor: "#d9f6f2"
                        onClicked: root.selectedBoard = index
                    }
                }
            }
            GridLayout {
                Layout.fillWidth: true
                columns: 4
                rowSpacing: 8
                columnSpacing: 8
                Repeater {
                    model: 8
                    delegate: AppButton {
                        id: channelButton
                        readonly property int channelId: root.selectedBoard * 8 + index
                        readonly property var channel: root.recordedChannel(channelId)
                        readonly property color buttonColor: root.channelColor(index)
                        text: channel ? channel.name : "CH" + (channelId + 1)
                        enabled: channel !== null
                        Layout.fillWidth: true
                        implicitHeight: 34
                        selected: channelButton.enabled && root.draftContains(channelButton.channelId)
                        fillColor: "#162630"
                        selectedFillColor: "#17313a"
                        borderColor: "#365467"
                        selectedBorderColor: channelButton.buttonColor
                        textColor: "#8fa3b4"
                        selectedTextColor: channelButton.buttonColor
                        onClicked: root.toggleDraft(channelId)
                    }
                }
            }
            Label { Layout.fillWidth: true; Layout.preferredHeight: 18; text: root.selectionMessage; color: "#f0a35e"; font.pixelSize: 12; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter }
            RowLayout {
                Layout.fillWidth: true
                ActionButton { text: qsTr("\u6e05\u7a7a"); onClicked: { root.draftChannelIds = []; root.selectionMessage = "" } }
                Item { Layout.fillWidth: true }
                ActionButton { text: qsTr("\u53d6\u6d88"); onClicked: channelSelector.close() }
                ActionButton { text: qsTr("\u5e94\u7528\u5e76\u5173\u95ed"); primary: true; onClicked: { root.playback.setDisplayChannels(root.draftChannelIds); root.selectedPlaybackChannelId = root.draftChannelIds.length ? root.draftChannelIds[0] : -1; channelSelector.close() } }
            }
        }
    }
}
