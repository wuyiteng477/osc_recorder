import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Rectangle {
    color: "#101922"
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 14
        Label { text: qsTr("\u91c7\u96c6\u8bbe\u7f6e"); color: "#d9e4ec"; font.pixelSize: 22; font.bold: true }
        Repeater {
            model: [qsTr("\u91c7\u6837\u7387: 2 MS/s"), qsTr("\u89c4\u5212\u901a\u9053\u6570: 64"), qsTr("\u5f53\u524d\u6a21\u5f0f: \u6a21\u62df\u6a21\u5f0f"), qsTr("\u8bbe\u5907\u540c\u6b65: \u672a\u8fde\u63a5")]
            delegate: Label { required property string modelData; text: modelData; color: "#d9e4ec"; font.pixelSize: 16 }
        }
        Label { text: qsTr("\u5f53\u524d\u53c2\u6570\u5c1a\u672a\u4e0b\u53d1\u5230\u771f\u5b9e\u8bbe\u5907\u3002"); color: "#e8a94b"; font.pixelSize: 14; Layout.topMargin: 10 }
        Item { Layout.fillHeight: true }
    }
}
