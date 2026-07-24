import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Dialog {
    id: root
    required property var systemInfo
    signal diagnosticRequested()
    modal: true
    focus: true
    closePolicy: Popup.NoAutoClose
    width: Math.min(760, parent ? parent.width - 72 : 760)
    height: Math.min(520, parent ? parent.height - 72 : 520)
    anchors.centerIn: Overlay.overlay
    padding: 0

    background: Rectangle { color: "#101922"; border.color: "#3c7180"; border.width: 1; radius: 6 }
    contentItem: Rectangle {
        id: dialogContent
        color: "transparent"
        property string exportResult: ""
        ColumnLayout {
            anchors.fill: parent; anchors.margins: 20; spacing: 13
            RowLayout {
                Layout.fillWidth: true
                Label { text: qsTr("系统信息与诊断"); color: "#d9e4ec"; font.pixelSize: 21; font.bold: true }
                Item { Layout.fillWidth: true }
                AppButton { text: "×"; implicitWidth: 32; implicitHeight: 30; fillColor: "transparent"; borderColor: "#365467"; textColor: "#d9e4ec"; font.pixelSize: 20; onClicked: root.close() }
            }
            Label { text: qsTr("当前可用的软件与诊断信息；RK3588 温度、设备状态、升级和硬件诊断接口预留在后端。"); color: "#8fa3b4"; font.pixelSize: 13; wrapMode: Text.WordWrap; Layout.fillWidth: true }
            Rectangle {
                Layout.fillWidth: true; implicitHeight: details.implicitHeight + 24; radius: 5; color: "#182b38"; border.color: "#365467"
                ColumnLayout {
                    id: details
                    anchors.fill: parent; anchors.margins: 12; spacing: 8
                    Repeater {
                        model: [[qsTr("软件版本"), root.systemInfo.softwareVersion], [qsTr("构建信息"), root.systemInfo.buildInfo], [qsTr("运行平台"), root.systemInfo.platformName], [qsTr("当前数据源"), root.systemInfo.dataSourceType], [qsTr("配置文件"), root.systemInfo.configurationPath], [qsTr("日志路径"), root.systemInfo.logFilePath]]
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true; spacing: 14
                            Label { text: modelData[0]; color: "#8fa3b4"; font.pixelSize: 14; Layout.preferredWidth: 112 }
                            Label { text: modelData[1]; color: "#d9e4ec"; font.pixelSize: 14; Layout.fillWidth: true; elide: Text.ElideMiddle }
                        }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true; spacing: 10
                AppButton { text: qsTr("打开日志目录"); implicitHeight: 36; onClicked: root.systemInfo.openLogDirectory() }
                AppButton { text: qsTr("导出诊断信息"); primary: true; implicitHeight: 36; onClicked: root.diagnosticRequested() }
                Item { Layout.fillWidth: true }
            }
            Label { visible: dialogContent.exportResult.length > 0; text: dialogContent.exportResult; color: "#35d19b"; font.pixelSize: 13; Layout.fillWidth: true; elide: Text.ElideMiddle }
            Item { Layout.fillHeight: true }
        }
    }
    Connections { target: root.systemInfo; function onDiagnosticExported(path) { dialogContent.exportResult = qsTr("诊断信息已导出：") + path } }
}
