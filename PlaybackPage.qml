import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import QtQuick.Layouts

Rectangle {
    id: root
    required property var playback
    color: "#101922"

    function duration(value) { const seconds = Math.floor(value); return String(Math.floor(seconds / 3600)).padStart(2, "0") + ":" + String(Math.floor(seconds / 60) % 60).padStart(2, "0") + ":" + String(seconds % 60).padStart(2, "0") }
    function bytes(value) { const units = ["B", "KiB", "MiB", "GiB"]; let n = Number(value), i = 0; while (n >= 1024 && i < 3) { n /= 1024; ++i } return n.toFixed(i ? 1 : 0) + " " + units[i] }
    function color(index) { return ["#39e6bb", "#f2d05c", "#72d18c", "#c58bea", "#f0a35e", "#63b3ed", "#ef7aa8", "#a6d96a"][index % 8] }

    FolderDialog { id: folderDialog; title: qsTr("选择录制会话目录"); onAccepted: root.playback.loadSessionUrl(selectedFolder) }
    FileDialog { id: sessionDialog; title: qsTr("选择 session.json"); nameFilters: ["session.json (session.json)", "JSON files (*.json)"]; onAccepted: root.playback.loadSessionUrl(selectedFile) }

    component ButtonStyle: Button {
        id: control
        property bool primary: false
        implicitHeight: 34
        contentItem: Text { text: control.text; color: control.enabled ? "#d9e4ec" : "#71818d"; font.pixelSize: 13; font.bold: control.primary; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
        background: Rectangle { radius: 4; color: control.primary && control.enabled ? "#168b7c" : "#223542"; border.color: control.primary ? "#39a99e" : "#365467" }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 10
        RowLayout {
            Layout.fillWidth: true
            Label { text: qsTr("历史回放"); color: "#d9e4ec"; font.pixelSize: 21; font.bold: true }
            Item { Layout.fillWidth: true }
            Label { text: playback.status === "ready" ? qsTr("校验完成") : playback.status === "error" ? qsTr("文件错误") : qsTr("未加载"); color: playback.status === "ready" ? "#35d19b" : playback.status === "error" ? "#f07d72" : "#8fa3b4"; font.bold: true }
        }
        Rectangle {
            Layout.fillWidth: true; implicitHeight: 66; radius: 5; color: "#172b37"; border.color: "#365467"
            RowLayout { anchors.fill: parent; anchors.margins: 12; spacing: 8
                Label { text: playback.sessionDirectory.length ? playback.sessionDirectory : qsTr("请选择已完成的录制会话"); color: "#d9e4ec"; elide: Text.ElideMiddle; Layout.fillWidth: true }
                ButtonStyle { text: qsTr("选择目录"); onClicked: folderDialog.open() }
                ButtonStyle { text: qsTr("选择 session.json"); onClicked: sessionDialog.open() }
            }
        }
        Label { visible: playback.detail.length; text: playback.detail; color: playback.status === "error" ? "#f07d72" : "#8fa3b4"; font.pixelSize: 12; Layout.fillWidth: true; elide: Text.ElideMiddle }
        Label { visible: playback.startedAt.length > 0; text: qsTr("录制时间：") + playback.startedAt + "  /  " + (playback.finishedAt.length ? playback.finishedAt : "-"); color: "#8fa3b4"; font.pixelSize: 12; Layout.fillWidth: true; elide: Text.ElideMiddle }
        GridLayout {
            Layout.fillWidth: true; columns: 6; columnSpacing: 8
            Repeater { model: [[qsTr("录制开始"), playback.startedAt], [qsTr("采样率"), playback.sampleRate + " S/s"], [qsTr("通道"), playback.channels.length + qsTr(" 路")], [qsTr("数据时长"), root.duration(playback.durationSeconds)], [qsTr("文件大小"), root.bytes(playback.dataBytes)], [qsTr("断层"), playback.gapCount]]
                delegate: Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 58
                    radius: 4
                    color: "#182b38"
                    border.color: "#314252"
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 1
                        Label { text: modelData[0]; color: "#8fa3b4"; font.pixelSize: 11 }
                        Label { text: modelData[1]; color: "#e6f0f5"; font.pixelSize: 14; font.bold: true; elide: Text.ElideMiddle; Layout.fillWidth: true }
                    }
                }
            }
        }
        Flickable {
            Layout.fillWidth: true; Layout.preferredHeight: 30; contentWidth: channelsRow.width; clip: true
            Row { id: channelsRow; spacing: 6
                Repeater { model: playback.channels
                    delegate: CheckBox { required property var modelData; text: modelData.name; checked: modelData.enabled; onToggled: { const ids = []; for (let i = 0; i < playback.channels.length; ++i) if (i !== index ? playback.channels[i].enabled : checked) ids.push(playback.channels[i].id); playback.setDisplayChannels(ids) } }
                }
            }
        }
        Rectangle {
            Layout.fillWidth: true; Layout.fillHeight: true; color: "#10242f"; border.color: "#365467"; clip: true
            Canvas {
                id: canvas; anchors.fill: parent; anchors.margins: 1
                Connections { target: playback; function onChanged() { canvas.requestPaint() } }
                onPaint: {
                    const ctx = getContext("2d"), w = width, h = height, frames = playback.frames
                    ctx.fillStyle = "#10242f"; ctx.fillRect(0, 0, w, h)
                    const count = Math.max(1, frames.length), viewH = h / count
                    for (let i = 0; i < frames.length; ++i) {
                        const top = i * viewH, frame = frames[i], points = frame.points, lineColor = root.color(i)
                        ctx.strokeStyle = "#1e4350"; ctx.lineWidth = 1
                        for (let x = 0; x <= 10; ++x) { ctx.beginPath(); ctx.moveTo(x * w / 10, top); ctx.lineTo(x * w / 10, top + viewH); ctx.stroke() }
                        ctx.strokeStyle = "#4a8290"; ctx.setLineDash([3, 3]); ctx.beginPath(); ctx.moveTo(0, top + viewH / 2); ctx.lineTo(w, top + viewH / 2); ctx.stroke(); ctx.setLineDash([])
                        ctx.fillStyle = lineColor; ctx.fillText(frame.name, 8, top + 14); ctx.strokeStyle = lineColor; ctx.lineWidth = 1.2; ctx.beginPath(); let drawn = false
                        for (let p = 0; p < points.length; ++p) { const point = points[p], x = (point.t - playback.viewStartSeconds) / playback.viewDurationSeconds * w, y = top + viewH / 2 - point.v * viewH / 3; if (!drawn) { ctx.moveTo(x, y); drawn = true } else ctx.lineTo(x, y) }
                        if (drawn) ctx.stroke()
                    }
                }
            }
        }
        RowLayout { Layout.fillWidth: true
            ButtonStyle { text: qsTr("左移"); enabled: playback.status === "ready"; onClicked: playback.moveView(-playback.viewDurationSeconds * .5) }
            ButtonStyle { text: qsTr("右移"); enabled: playback.status === "ready"; onClicked: playback.moveView(playback.viewDurationSeconds * .5) }
            ButtonStyle { text: qsTr("复位"); enabled: playback.status === "ready"; onClicked: playback.resetView() }
            Label { text: qsTr("窗口：") + root.duration(playback.viewDurationSeconds) + "  @  " + root.duration(playback.viewStartSeconds); color: "#8fa3b4"; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter }
            ButtonStyle { text: qsTr("缩小"); enabled: playback.status === "ready"; onClicked: playback.setView(playback.viewStartSeconds - playback.viewDurationSeconds * .5, playback.viewDurationSeconds * 2) }
            ButtonStyle { text: qsTr("放大"); enabled: playback.status === "ready"; onClicked: playback.setView(playback.viewStartSeconds + playback.viewDurationSeconds * .25, playback.viewDurationSeconds * .5) }
        }
    }
}
