import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Rectangle {
    id: root
    required property var channelStore
    required property int selectedChannelIndex
    required property real timePerDivMs
    required property real horizontalStepSeconds
    required property string displayMode
    required property bool gridVisible
    required property bool hasSimulationData
    required property real historyOffsetSeconds
    required property real maximumHistoryOffsetSeconds
    signal selectedChannelRequested(int index)
    signal voltsPerDivRequested(real value)
    signal timePerDivRequested(real value)
    signal verticalOffsetRequested(real value)
    signal displayModeRequested(string value)
    signal gridVisibleRequested(bool value)
    signal moveHistoryLeftRequested()
    signal moveHistoryRightRequested()
    signal resetHistoryPositionRequested()
    // The model is populated after this panel is constructed.  Include the
    // store revision in the binding so initial CH1 is refreshed automatically,
    // rather than requiring a temporary switch to another channel.
    readonly property var channel: {
        const storeRevision = channelStore.revision
        if (channelStore.channelModel.count <= selectedChannelIndex)
            return ({ name: "CH" + (selectedChannelIndex + 1), color: "#71818d", voltsPerDiv: 1, verticalOffsetV: 0, defaultOffsetV: 0 })
        return channelStore.channel(selectedChannelIndex)
    }
    // The parameter panel edits waveform presentation, so it should expose
    // only channels that currently own a real-time waveform view (maximum 8).
    readonly property var editableChannelIndexes: {
        const storeRevision = channelStore.revision
        return channelStore.activeViewChannels()
    }
    color: "#15212c"
    border.color: "#314252"

    function num(value) { return Number(value).toFixed(1).replace(/\.0$/, "") }

    // 各分区标题样式统一，方便后续增减设置项。
    component Section: Label {
        color: "#8fa3b4"
        font.pixelSize: 12
        font.bold: true
        Layout.topMargin: 5
    }

    component Btn: AppButton { implicitHeight: 32 }

    component Separator: Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: "#314252"
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 7

        Label {
            text: qsTr("\u901a\u9053\u53c2\u6570")
            color: "#d9e4ec"
            font.pixelSize: 16
            font.bold: true
        }

        Section { text: qsTr("\u5f53\u524d\u7f16\u8f91\u901a\u9053") }

        ComboBox {
            id: channels
            Layout.fillWidth: true
            implicitHeight: 32
            model: root.editableChannelIndexes
            enabled: root.editableChannelIndexes.length > 0
            currentIndex: Math.max(0, root.editableChannelIndexes.indexOf(root.selectedChannelIndex))

            onActivated: root.selectedChannelRequested(root.editableChannelIndexes[currentIndex])

            delegate: ItemDelegate {
                required property var modelData
                width: channels.width
                text: root.channelStore.channel(modelData).name
            }

            contentItem: Text {
                leftPadding: 10
                text: root.channel.name
                color: root.channel.color
                verticalAlignment: Text.AlignVCenter
            }

            background: Rectangle {
                color: "#223542"
                radius: 3
                border.color: root.channel.color
            }
        }

        Separator { }

        Section { text: qsTr("\u5782\u76f4\u63a7\u5236") }

        ComboBox {
            id: volts
            Layout.fillWidth: true
            implicitHeight: 32
            model: [.2, .5, 1, 2, 5]
            currentIndex: model.indexOf(root.channel.voltsPerDiv)

            onActivated: root.voltsPerDivRequested(Number(currentValue))

            contentItem: Text {
                leftPadding: 10
                text: root.num(volts.currentValue) + " V/div"
                color: "#d9e4ec"
                verticalAlignment: Text.AlignVCenter
            }

            background: Rectangle {
                color: "#223542"
                radius: 3
                border.color: "#365467"
            }
        }

        Label {
            text: qsTr("\u5782\u76f4\u504f\u79fb  ") + root.num(root.channel.verticalOffsetV) + " V"
            color: root.channel.color
        }

        RowLayout {
            Layout.fillWidth: true

            Btn {
                text: qsTr("\u4e0a\u79fb")
                Layout.fillWidth: true
                onClicked: root.verticalOffsetRequested(root.channel.verticalOffsetV + .2)
            }

            Btn {
                text: qsTr("\u4e0b\u79fb")
                Layout.fillWidth: true
                onClicked: root.verticalOffsetRequested(root.channel.verticalOffsetV - .2)
            }

            Btn {
                text: qsTr("\u5f52\u96f6")
                Layout.fillWidth: true
                onClicked: root.verticalOffsetRequested(root.channel.defaultOffsetV)
            }
        }

        Separator { }

        Section { text: qsTr("\u6c34\u5e73\u63a7\u5236") }

        ComboBox {
            id: times
            Layout.fillWidth: true
            implicitHeight: 32
            model: [.1, .2, .5, 1, 2, 5, 10, 20, 50, 100, 200]
            currentIndex: model.indexOf(root.timePerDivMs)

            onActivated: root.timePerDivRequested(Number(currentValue))

            contentItem: Text {
                leftPadding: 10
                text: root.num(times.currentValue) + " ms/div"
                color: "#d9e4ec"
                verticalAlignment: Text.AlignVCenter
            }

            background: Rectangle {
                color: "#223542"
                radius: 3
                border.color: "#365467"
            }
        }

        Label {
            text: qsTr("\u5386\u53f2\u4f4d\u7f6e  ") + (root.historyOffsetSeconds < 1e-9 ? qsTr("\u6700\u65b0") : root.num(root.historyOffsetSeconds * 1000) + " ms")
            color: "#8fa3b4"
        }

        RowLayout {
            Layout.fillWidth: true

            Btn {
                text: qsTr("\u5de6\u79fb")
                Layout.fillWidth: true
                enabled: root.hasSimulationData && root.historyOffsetSeconds < root.maximumHistoryOffsetSeconds - 1e-9
                onClicked: root.moveHistoryLeftRequested()
            }

            Btn {
                text: qsTr("\u53f3\u79fb")
                Layout.fillWidth: true
                enabled: root.historyOffsetSeconds > 1e-9
                onClicked: root.moveHistoryRightRequested()
            }

            Btn {
                text: qsTr("\u5f52\u96f6")
                Layout.fillWidth: true
                enabled: root.historyOffsetSeconds > 1e-9
                onClicked: root.resetHistoryPositionRequested()
            }
        }

        Separator { }

        Section { text: qsTr("\u663e\u793a\u63a7\u5236") }

        RowLayout {
            Layout.fillWidth: true

            Btn {
                text: qsTr("\u66f4\u65b0")
                selected: root.displayMode === "update"
                Layout.fillWidth: true
                enabled: root.displayMode !== "update"
                onClicked: root.displayModeRequested("update")
            }

            Btn {
                text: qsTr("\u6eda\u52a8")
                selected: root.displayMode === "roll"
                Layout.fillWidth: true
                enabled: root.displayMode !== "roll"
                onClicked: root.displayModeRequested("roll")
            }

            Btn {
                text: root.gridVisible ? qsTr("\u5173\u95ed\u6805\u683c") : qsTr("\u663e\u793a\u6805\u683c")
                selected: root.gridVisible
                Layout.fillWidth: true
                onClicked: root.gridVisibleRequested(!root.gridVisible)
            }
        }

        Item {
            Layout.fillHeight: true
        }
    }
}
