import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Rectangle {
    id: root
    required property var channelStore
    signal channelNameRequested(int index, string name)
    signal channelEnabledRequested(int index, bool enabled)
    signal channelVisibleRequested(int index, bool visible)
    signal channelColorRequested(int index, string color)
    color: "#101922"
    component ButtonStyle: Button { id: button; implicitHeight: 30; contentItem: Text { text: button.text; color: button.enabled ? "#d9e4ec" : "#71818d"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter } background: Rectangle { radius: 3; color: "#223542"; border.color: "#365467" } }
    component FieldStyle: TextField { color: "#d9e4ec"; selectByMouse: true; background: Rectangle { radius: 3; color: "#14232e"; border.color: "#365467" } }
    ColumnLayout {
        anchors.fill: parent; anchors.margins: 24; spacing: 12
        Label { text: qsTr("\u901a\u9053\u8bbe\u7f6e"); color: "#d9e4ec"; font.pixelSize: 22; font.bold: true }
        Label { text: qsTr("8 \u5361 x 8 \u901a\u9053 (CH1-CH64) \u6a21\u62df\u914d\u7f6e\uff1a\u542f\u7528\u63a7\u5236\u91c7\u96c6\uff0c\u663e\u793a\u63a7\u5236\u6ce2\u5f62\u7ed8\u5236\u3002"); color: "#8fa3b4" }
        ListView { Layout.fillWidth: true; Layout.fillHeight: true; spacing: 10; clip: true; model: root.channelStore.channelModel
            delegate: Rectangle {
                id: card; required property int index; readonly property var info: root.channelStore.channel(index); width: ListView.view.width; height: 112; radius: 5; color: "#182b38"; border.color: info.color
                ColumnLayout { anchors.fill: parent; anchors.margins: 10; spacing: 5
                    RowLayout { Layout.fillWidth: true; Label { text: info.name; color: info.color; font.pixelSize: 16; font.bold: true } Label { text: qsTr("\u5361 ") + (info.boardIndex + 1) + " / " + qsTr("\u901a\u9053 ") + (info.channelIndex + 1); color: "#8fa3b4"; font.pixelSize: 12 } Item { Layout.fillWidth: true } Label { text: info.enabled ? qsTr("\u5df2\u542f\u7528") : qsTr("\u5df2\u505c\u7528"); color: info.enabled ? "#35d19b" : "#e8a94b" } Label { text: info.visible ? qsTr("\u663e\u793a") : qsTr("\u9690\u85cf"); color: info.visible ? info.color : "#8fa3b4" } }
                    RowLayout { Layout.fillWidth: true; FieldStyle { id: nameField; Layout.preferredWidth: 180; text: card.info.name; maximumLength: 20; onEditingFinished: { if (text.trim().length) root.channelNameRequested(card.index, text) } } ButtonStyle { text: card.info.enabled ? qsTr("\u505c\u7528") : qsTr("\u542f\u7528"); onClicked: root.channelEnabledRequested(card.index, !card.info.enabled) } ButtonStyle { text: card.info.visible ? qsTr("\u9690\u85cf\u6ce2\u5f62") : qsTr("\u663e\u793a\u6ce2\u5f62"); onClicked: root.channelVisibleRequested(card.index, !card.info.visible) } ComboBox { id: colorBox; Layout.preferredWidth: 100; model: ["Cyan", "Yellow", "Green", "Purple", "Orange", "Blue", "Pink", "Lime"]; currentIndex: ["#39e6bb", "#f2d05c", "#72d18c", "#c58bea", "#f0a35e", "#63b3ed", "#ef7aa8", "#a6d96a"].indexOf(card.info.color); onActivated: root.channelColorRequested(card.index, ["#39e6bb", "#f2d05c", "#72d18c", "#c58bea", "#f0a35e", "#63b3ed", "#ef7aa8", "#a6d96a"][currentIndex]); contentItem: Text { leftPadding: 8; text: colorBox.currentText; color: card.info.color; verticalAlignment: Text.AlignVCenter } background: Rectangle { radius: 3; color: "#223542"; border.color: "#365467" } } Item { Layout.fillWidth: true } Label { text: Number(card.info.voltsPerDiv).toFixed(1) + " V/div   " + Number(card.info.verticalOffsetV).toFixed(1) + " V"; color: "#d9e4ec" } }
                }
            }
        }
    }
}
