import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Rectangle {
    // 当前仅提供录制状态展示，后续接入真实写盘逻辑时可在此扩展。
    color: "#101922"

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 14

        Label {
            text: qsTr("\u6570\u636e\u5f55\u5236")
            color: "#d9e4ec"
            font.pixelSize: 22
            font.bold: true
        }

        Repeater {
            model: [
                qsTr("\u4fdd\u5b58\u8def\u5f84: \u672a\u8bbe\u7f6e"),
                qsTr("\u5f55\u5236\u72b6\u6001: \u672a\u5f55\u5236"),
                qsTr("\u5f53\u524d\u6587\u4ef6\u5927\u5c0f: 0 B"),
                qsTr("\u5269\u4f59\u78c1\u76d8\u7a7a\u95f4: \u672a\u77e5")
            ]

            delegate: Label {
                required property string modelData
                text: modelData
                color: "#d9e4ec"
                font.pixelSize: 16
            }
        }

        Label {
            text: qsTr("\u5f53\u524d\u7248\u672c\u5c1a\u672a\u5b9e\u73b0\u771f\u5b9e\u6587\u4ef6\u5199\u5165\u3002")
            color: "#e8a94b"
            font.pixelSize: 14
            Layout.topMargin: 10
        }

        Item {
            Layout.fillHeight: true
        }
    }
}
