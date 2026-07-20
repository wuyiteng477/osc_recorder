import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Rectangle {
    color: "#101922"
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 16
        Label { text: qsTr("\u901a\u9053\u8bbe\u7f6e"); color: "#d9e4ec"; font.pixelSize: 22; font.bold: true }
        Label { text: qsTr("\u540e\u7eed\u5c06\u5728\u8fd9\u91cc\u914d\u7f6e\u901a\u9053\u540d\u79f0\u3001\u91cf\u7a0b\u3001\u504f\u79fb\u548c\u542f\u7528\u72b6\u6001\u3002"); color: "#8fa3b4"; font.pixelSize: 14 }
        GridLayout {
            columns: 2
            columnSpacing: 14
            rowSpacing: 14
            Repeater {
                model: ["CH1: \u5f00\u542f", "CH2: \u5f00\u542f", "CH3: \u5173\u95ed", "CH4: \u5173\u95ed"]
                delegate: Rectangle { id: channelCard; required property string modelData; implicitWidth: 230; implicitHeight: 88; radius: 5; color: "#182b38"; border.color: "#314b5c"; Label { anchors.centerIn: parent; text: channelCard.modelData; color: "#d9e4ec"; font.pixelSize: 17; font.bold: true } }
            }
        }
        Item { Layout.fillHeight: true }
    }
}
