import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Rectangle {
    id: root
    required property bool channelEnabled
    required property real voltsPerDiv
    required property real timePerDivMs
    required property real verticalOffsetV
    signal channelEnabledRequested(bool enabled)
    signal voltsPerDivRequested(real value)
    signal timePerDivRequested(real value)
    signal verticalOffsetRequested(real value)
    color: "#15212c"
    border.color: "#314252"

    function formatNumber(value) { return Number(value).toFixed(1).replace(/\.0$/, "") }
    function indexOfValue(values, value) {
        for (let i = 0; i < values.length; ++i) if (values[i] === value) return i
        return 0
    }
    component PanelButton: Button {
        id: control
        implicitHeight: 30
        contentItem: Text { text: control.text; color: control.enabled ? "#d9e4ec" : "#71818d"; font.pixelSize: 12; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
        background: Rectangle { radius: 3; color: control.down ? "#285b73" : "#223542"; border.color: "#365467" }
    }
    component SectionTitle: Label { color: "#8fa3b4"; font.pixelSize: 12; font.bold: true; Layout.topMargin: 6 }

    ColumnLayout {
        anchors.fill: parent; anchors.margins: 16; spacing: 8
        Label { text: qsTr("\u901a\u9053\u53c2\u6570"); color: "#d9e4ec"; font.pixelSize: 16; font.bold: true; Layout.bottomMargin: 6 }
        SectionTitle { text: qsTr("\u5f53\u524d\u901a\u9053") }
        Label { text: "CH1"; color: "#d9e4ec"; font.pixelSize: 15; font.bold: true }
        SectionTitle { text: qsTr("\u901a\u9053\u72b6\u6001") }
        PanelButton { text: root.channelEnabled ? qsTr("\u5df2\u5f00\u542f") : qsTr("\u5df2\u5173\u95ed"); Layout.fillWidth: true; onClicked: root.channelEnabledRequested(!root.channelEnabled) }
        SectionTitle { text: qsTr("\u91cf\u7a0b") }
        ComboBox {
            id: voltsBox
            Layout.fillWidth: true
            model: [0.2, 0.5, 1.0, 2.0, 5.0]
            currentIndex: root.indexOfValue(model, root.voltsPerDiv)
            onActivated: root.voltsPerDivRequested(Number(currentValue))
            contentItem: Text { leftPadding: 10; text: root.formatNumber(voltsBox.currentValue) + " V/div"; color: "#d9e4ec"; font.pixelSize: 13; verticalAlignment: Text.AlignVCenter }
            background: Rectangle { radius: 3; color: "#223542"; border.color: "#365467" }
            indicator: Text { text: "\u25be"; color: "#8fa3b4"; anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter }
            popup: Popup {
                y: voltsBox.height; width: voltsBox.width; padding: 2
                contentItem: ListView { implicitHeight: contentHeight; model: voltsBox.popup.visible ? voltsBox.delegateModel : null; clip: true }
                background: Rectangle { color: "#1b2a35"; border.color: "#365467" }
            }
        }
        SectionTitle { text: qsTr("\u5782\u76f4\u504f\u79fb") }
        Label { text: root.formatNumber(root.verticalOffsetV) + " V"; color: "#d9e4ec"; font.pixelSize: 15; font.bold: true; Layout.alignment: Qt.AlignHCenter }
        RowLayout {
            Layout.fillWidth: true; spacing: 5
            PanelButton { text: qsTr("\u4e0a\u79fb"); Layout.fillWidth: true; onClicked: root.verticalOffsetRequested(root.verticalOffsetV + 0.2) }
            PanelButton { text: qsTr("\u4e0b\u79fb"); Layout.fillWidth: true; onClicked: root.verticalOffsetRequested(root.verticalOffsetV - 0.2) }
            PanelButton { text: qsTr("\u5f52\u96f6"); Layout.fillWidth: true; onClicked: root.verticalOffsetRequested(0) }
        }
        SectionTitle { text: qsTr("\u65f6\u57fa") }
        ComboBox {
            id: timeBox
            Layout.fillWidth: true
            model: [0.1, 0.2, 0.5, 1.0, 2.0, 5.0, 10.0]
            currentIndex: root.indexOfValue(model, root.timePerDivMs)
            onActivated: root.timePerDivRequested(Number(currentValue))
            contentItem: Text { leftPadding: 10; text: root.formatNumber(timeBox.currentValue) + " ms/div"; color: "#d9e4ec"; font.pixelSize: 13; verticalAlignment: Text.AlignVCenter }
            background: Rectangle { radius: 3; color: "#223542"; border.color: "#365467" }
            indicator: Text { text: "\u25be"; color: "#8fa3b4"; anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter }
            popup: Popup {
                y: timeBox.height; width: timeBox.width; padding: 2
                contentItem: ListView { implicitHeight: contentHeight; model: timeBox.popup.visible ? timeBox.delegateModel : null; clip: true }
                background: Rectangle { color: "#1b2a35"; border.color: "#365467" }
            }
        }
        Item { Layout.fillHeight: true }
        Label { text: qsTr("\u4ec5\u8c03\u6574\u6a21\u62df CH1 \u663e\u793a\u3002"); color: "#8fa3b4"; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
    }
}
