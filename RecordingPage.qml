import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import QtQuick.Layouts

Rectangle {
    id: root
    required property var recorder
    required property int sampleRate
    required property int enabledChannelCount
    required property string acquisitionMode
    required property bool simulationRunning
    required property var channelIds
    signal startRecordingRequested()

    color: "#101922"

    function bytes(value) {
        const units = ["B", "KiB", "MiB", "GiB", "TiB"]
        let number = Number(value)
        let unit = 0
        while (number >= 1024 && unit < units.length - 1) {
            number /= 1024
            ++unit
        }
        return number.toFixed(unit === 0 ? 0 : 1) + " " + units[unit]
    }
    function duration(milliseconds) {
        const seconds = Math.floor(milliseconds / 1000)
        const hours = Math.floor(seconds / 3600)
        const minutes = Math.floor((seconds % 3600) / 60)
        return String(hours).padStart(2, "0") + ":"
                + String(minutes).padStart(2, "0") + ":"
                + String(seconds % 60).padStart(2, "0")
    }
    function stateText(state) {
        const names = {
            not_ready: qsTr("\u672a\u5c31\u7eea"), ready: qsTr("\u5c31\u7eea"),
            recording: qsTr("\u5f55\u5236\u4e2d"), stopping: qsTr("\u6b63\u5728\u505c\u6b62"),
            completed: qsTr("\u5df2\u5b8c\u6210"), insufficient_space: qsTr("\u7a7a\u95f4\u4e0d\u8db3"),
            path_not_writable: qsTr("\u8def\u5f84\u4e0d\u53ef\u5199"), write_error: qsTr("\u5199\u5165\u9519\u8bef")
        }
        return names[state] || state
    }
    function stateColor(state) {
        if (state === "recording") return "#35d19b"
        if (state === "completed") return "#5eb4ec"
        if (state === "insufficient_space" || state === "path_not_writable" || state === "write_error") return "#f07d72"
        if (state === "ready") return "#19b4a5"
        return "#8fa3b4"
    }

    readonly property real estimatedSeconds: recorder.theoreticalBytesPerSecond > 0
                                           ? recorder.availableBytes / recorder.theoreticalBytesPerSecond : 0

    Component.onCompleted: recorder.setRecordingParameters(sampleRate, enabledChannelCount)
    onSampleRateChanged: recorder.setRecordingParameters(sampleRate, enabledChannelCount)
    onEnabledChannelCountChanged: recorder.setRecordingParameters(sampleRate, enabledChannelCount)

    component ActionButton: Button {
        id: button
        property color fillColor: "#223542"
        property bool primary: false
        implicitHeight: 36
        contentItem: Text {
            text: button.text
            color: button.enabled ? "#e7f1f5" : "#71818d"
            font.pixelSize: 14
            font.bold: button.primary
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: 4
            color: button.enabled ? button.fillColor : "#182630"
            border.color: button.primary ? "#39a99e" : "#365467"
        }
    }

    component MetricCard: Rectangle {
        id: metricCard
        required property string title
        required property string value
        Layout.fillWidth: true
        implicitHeight: 68
        radius: 4
        color: "#182b38"
        border.color: "#314252"
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 3
            Label { text: metricCard.title; color: "#8fa3b4"; font.pixelSize: 12 }
            Label { text: metricCard.value; color: "#e6f0f5"; font.pixelSize: 16; font.bold: true; elide: Text.ElideMiddle; Layout.fillWidth: true }
        }
    }

    FolderDialog {
        id: folderDialog
        title: qsTr("\u9009\u62e9\u5f55\u5236\u4fdd\u5b58\u76ee\u5f55")
        currentFolder: root.recorder.saveDirectoryUrl
        onAccepted: root.recorder.setSaveDirectoryUrl(selectedFolder)
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            ColumnLayout {
                spacing: 1
                Label { text: qsTr("\u6570\u636e\u5f55\u5236"); color: "#d9e4ec"; font.pixelSize: 21; font.bold: true }
                Label { text: qsTr("\u4f4e\u901f\u6a21\u62df\u5199\u5165\uff0c\u5bb9\u91cf\u6309\u7406\u8bba\u91c7\u96c6\u541e\u5410\u7edf\u8ba1"); color: "#8fa3b4"; font.pixelSize: 12 }
            }
            Item { Layout.fillWidth: true }
            Rectangle {
                implicitWidth: statusLabel.implicitWidth + 20
                implicitHeight: 28
                radius: 14
                color: root.recorder.status === "recording" ? "#173c38" : root.recorder.status === "completed" ? "#17313f" : root.recorder.status === "write_error" || root.recorder.status === "insufficient_space" || root.recorder.status === "path_not_writable" ? "#3a2529" : "#1a2d38"
                border.color: root.stateColor(root.recorder.status)
                Label { id: statusLabel; anchors.centerIn: parent; text: root.stateText(root.recorder.status); color: root.stateColor(root.recorder.status); font.pixelSize: 13; font.bold: true }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 94
            radius: 5
            color: "#172b37"
            border.color: "#365467"
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 6
                RowLayout {
                    Layout.fillWidth: true
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Label { text: qsTr("\u4fdd\u5b58\u76ee\u5f55"); color: "#8fa3b4"; font.pixelSize: 12 }
                        Label { text: root.recorder.saveDirectory; color: "#e6f0f5"; font.pixelSize: 14; elide: Text.ElideMiddle; Layout.fillWidth: true }
                    }
                    ActionButton { text: qsTr("\u9009\u62e9\u76ee\u5f55"); enabled: !root.recorder.recording; onClicked: folderDialog.open() }
                    ActionButton { text: qsTr("\u5237\u65b0\u5bb9\u91cf"); enabled: !root.recorder.recording; onClicked: root.recorder.refreshStorage() }
                    ActionButton { text: qsTr("\u5f00\u59cb\u5f55\u5236"); primary: true; fillColor: "#168b7c"; enabled: !root.recorder.recording; onClicked: root.startRecordingRequested() }
                    ActionButton { text: qsTr("\u505c\u6b62\u5f55\u5236"); fillColor: root.recorder.recording ? "#a1514d" : "#223542"; enabled: root.recorder.recording; onClicked: root.recorder.stopRecording() }
                }
                Label { text: root.recorder.statusDetail.length ? root.recorder.statusDetail : qsTr("\u5df2\u5c31\u7eea\uff0c\u5f55\u5236\u65f6\u5c06\u81ea\u52a8\u521b\u5efa\u72ec\u7acb\u4f1a\u8bdd\u3002"); color: root.recorder.statusDetail.length ? "#e8a94b" : "#8fa3b4"; font.pixelSize: 11; elide: Text.ElideMiddle; Layout.fillWidth: true }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 5
            columnSpacing: 10
            rowSpacing: 0
            MetricCard { title: qsTr("\u7406\u8bba\u6570\u636e\u901f\u7387"); value: root.bytes(root.recorder.theoreticalBytesPerSecond) + "/s" }
            MetricCard { title: qsTr("\u5f53\u524d\u53ef\u7528\u7a7a\u95f4"); value: root.bytes(root.recorder.availableBytes) }
            MetricCard { title: qsTr("\u9884\u8ba1\u53ef\u5f55\u5236\u65f6\u957f"); value: root.duration(root.estimatedSeconds * 1000) }
            MetricCard { title: qsTr("\u5df2\u5f55\u5236\u65f6\u957f"); value: root.duration(root.recorder.recordedMilliseconds) }
            MetricCard { title: qsTr("\u5f53\u524d\u6587\u4ef6\u5927\u5c0f"); value: root.bytes(root.recorder.simulatedFileBytes) }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 152
            radius: 5
            color: "#142631"
            border.color: "#314252"
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 7
                RowLayout {
                    Layout.fillWidth: true
                    Label { text: qsTr("\u5f55\u5236\u6458\u8981"); color: "#d9e4ec"; font.bold: true; font.pixelSize: 14; Layout.preferredHeight: 18; verticalAlignment: Text.AlignVCenter }
                    Item { Layout.fillWidth: true }
                }
                Label { text: qsTr("\u4f1a\u8bdd\u76ee\u5f55\uff1a") + (root.recorder.sessionDirectory.length ? root.recorder.sessionDirectory : qsTr("\u5c1a\u672a\u521b\u5efa")); color: "#d9e4ec"; font.pixelSize: 12; elide: Text.ElideMiddle; Layout.fillWidth: true; Layout.preferredHeight: 18; verticalAlignment: Text.AlignVCenter }
                Label { text: qsTr("\u5f00\u59cb / \u7ed3\u675f\uff1a") + (root.recorder.createdAt.length ? root.recorder.createdAt : "-") + " / " + (root.recorder.finishedAt.length ? root.recorder.finishedAt : "-"); color: "#8fa3b4"; font.pixelSize: 12; elide: Text.ElideMiddle; Layout.fillWidth: true; Layout.preferredHeight: 18; verticalAlignment: Text.AlignVCenter }
                Label { text: "session.json  \u00b7  waveform.part/bin  \u00b7  index.csv  \u00b7  recording.log"; color: "#8fa3b4"; font.pixelSize: 12; Layout.preferredHeight: 18; verticalAlignment: Text.AlignVCenter }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 24
                    Item { Layout.fillWidth: true }
                    CheckBox {
                        id: timeColumnOption
                        visible: false // Reserved for later CSV export; no current UI action.
                        text: qsTr("CSV \u5305\u542b\u65f6\u95f4\u5217\uff08\u9884\u7559\uff09")
                        enabled: false
                        checked: true
                        scale: .82
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        contentItem: Text { text: timeColumnOption.text; leftPadding: timeColumnOption.indicator.width + 4; color: "#71818d"; font.pixelSize: 11; verticalAlignment: Text.AlignVCenter }
                    }
                }
            }
        }
        Item { Layout.fillHeight: true }
    }
}
