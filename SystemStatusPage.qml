import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Rectangle {
    id: root
    required property bool simulationRunning
    color: "#101922"
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 14
        Label { text: qsTr("\u7cfb\u7edf\u72b6\u6001"); color: "#d9e4ec"; font.pixelSize: 22; font.bold: true }
        Label { text: qsTr("\u8bbe\u5907\u8fde\u63a5: \u672a\u8fde\u63a5"); color: "#d9e4ec"; font.pixelSize: 16 }
        Label { text: qsTr("\u91c7\u96c6\u72b6\u6001: ") + (root.simulationRunning ? qsTr("\u8fd0\u884c\u4e2d") : qsTr("\u5df2\u505c\u6b62")); color: root.simulationRunning ? "#35d19b" : "#d9e4ec"; font.pixelSize: 16 }
        Repeater {
            model: [qsTr("CPU \u72b6\u6001: \u6b63\u5e38"), qsTr("\u5185\u5b58\u72b6\u6001: \u6b63\u5e38"), qsTr("\u78c1\u76d8\u72b6\u6001: \u672a\u77e5"), qsTr("\u5f53\u524d\u5e73\u53f0: \u5f00\u53d1\u73af\u5883"), qsTr("\u5f53\u524d\u6a21\u5f0f: \u6a21\u62df\u6a21\u5f0f")]
            delegate: Label { required property string modelData; text: modelData; color: "#d9e4ec"; font.pixelSize: 16 }
        }
        Item { Layout.fillHeight: true }
    }
}
