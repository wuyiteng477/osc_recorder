import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Rectangle {
    id: root
    required property bool simulationRunning
    required property int sampleRate
    required property string acquisitionMode
    required property int enabledChannelCount
    required property int enabledBoardCount
    color: "#101922"
    ColumnLayout {
        anchors.fill: parent; anchors.margins: 24; spacing: 14
        Label { text: qsTr("系统状态"); color: "#d9e4ec"; font.pixelSize: 22; font.bold: true }
        Label { text: qsTr("设备连接: 未连接（模拟数据源）"); color: "#d9e4ec"; font.pixelSize: 16 }
        Label { text: qsTr("采集状态: ") + (root.simulationRunning ? qsTr("运行中") : qsTr("已停止")); color: root.simulationRunning ? "#35d19b" : "#d9e4ec"; font.pixelSize: 16 }
        Label { text: qsTr("已应用采样率: ") + root.sampleRate + qsTr(" S/s"); color: "#d9e4ec"; font.pixelSize: 16 }
        Label { text: qsTr("已应用模式: ") + (root.acquisitionMode === "burst" ? qsTr("突发采集") : qsTr("连续采集")); color: "#d9e4ec"; font.pixelSize: 16 }
        Label { text: qsTr("已启用板卡 / 采集通道: ") + root.enabledBoardCount + qsTr(" / ") + root.enabledChannelCount; color: "#d9e4ec"; font.pixelSize: 16 }
        Repeater { model: [qsTr("CPU 状态: 正常"), qsTr("内存状态: 正常"), qsTr("磁盘状态: 未知"), qsTr("当前平台: 开发环境"), qsTr("当前模式: 模拟模式")]; delegate: Label { required property string modelData; text: modelData; color: "#d9e4ec"; font.pixelSize: 16 } }
        Item { Layout.fillHeight: true }
    }
}
