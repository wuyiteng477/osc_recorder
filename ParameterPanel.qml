import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Rectangle {
    id: root
    required property bool channelEnabled
    required property real voltsPerDiv
    required property real timePerDivMs
    required property real horizontalStepSeconds
    required property real verticalOffsetV
    required property string displayMode
    required property bool gridVisible
    required property bool hasSimulationData
    required property real historyOffsetSeconds
    required property real maximumHistoryOffsetSeconds
    signal channelEnabledRequested(bool enabled)
    signal voltsPerDivRequested(real value)
    signal timePerDivRequested(real value)
    signal verticalOffsetRequested(real value)
    signal displayModeRequested(string mode)
    signal gridVisibleRequested(bool visible)
    signal moveHistoryLeftRequested()
    signal moveHistoryRightRequested()
    signal resetHistoryPositionRequested()
    color: "#15212c"; border.color: "#314252"
    function formatNumber(value) { return Number(value).toFixed(1).replace(/\.0$/, "") }
    function formatDuration(value) { return Math.abs(value) < 1 ? formatNumber(value * 1000) + " ms" : formatNumber(value) + " s" }
    function indexOfValue(values, value) { for (let i = 0; i < values.length; ++i) if (values[i] === value) return i; return 0 }
    component PanelButton: Button {
        id: control
        implicitHeight: 30
        contentItem: Text { text: control.text; color: control.enabled ? "#d9e4ec" : "#71818d"; font.pixelSize: 12; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
        background: Rectangle { radius: 3; color: control.down ? "#285b73" : "#223542"; border.color: "#365467" }
    }
    component SectionTitle: Label { color: "#8fa3b4"; font.pixelSize: 12; font.bold: true; Layout.topMargin: 6 }
    component DarkCombo: ComboBox {
        id: box
        Layout.fillWidth: true
        contentItem: Text { leftPadding: 10; text: box.displayText; color: "#d9e4ec"; font.pixelSize: 13; verticalAlignment: Text.AlignVCenter }
        background: Rectangle { radius: 3; color: "#223542"; border.color: "#365467" }
        indicator: Text { text: "▾"; color: "#8fa3b4"; anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter }
    }
    ColumnLayout {
        anchors.fill: parent; anchors.margins: 16; spacing: 8
        Label { text: qsTr("通道参数"); color: "#d9e4ec"; font.pixelSize: 16; font.bold: true; Layout.bottomMargin: 6 }
        SectionTitle { text: qsTr("当前通道") }
        Label { text: "CH1"; color: "#d9e4ec"; font.pixelSize: 15; font.bold: true }
        SectionTitle { text: qsTr("通道状态") }
        PanelButton { text: root.channelEnabled ? qsTr("已开启") : qsTr("已关闭"); Layout.fillWidth: true; onClicked: root.channelEnabledRequested(!root.channelEnabled) }
        SectionTitle { text: qsTr("显示模式") }
        RowLayout {
            Layout.fillWidth: true; spacing: 5
            PanelButton { text: qsTr("更新"); Layout.fillWidth: true; enabled: root.displayMode !== "update"; onClicked: root.displayModeRequested("update") }
            PanelButton { text: qsTr("滚动"); Layout.fillWidth: true; enabled: root.displayMode !== "roll"; onClicked: root.displayModeRequested("roll") }
        }
        SectionTitle { text: qsTr("栅格显示") }
        RowLayout {
            Layout.fillWidth: true; spacing: 5
            PanelButton { text: qsTr("开启"); Layout.fillWidth: true; enabled: !root.gridVisible; onClicked: root.gridVisibleRequested(true) }
            PanelButton { text: qsTr("关闭"); Layout.fillWidth: true; enabled: root.gridVisible; onClicked: root.gridVisibleRequested(false) }
        }
        SectionTitle { text: qsTr("量程") }
        DarkCombo { id: voltsBox; model: [0.2, 0.5, 1.0, 2.0, 5.0]; currentIndex: root.indexOfValue(model, root.voltsPerDiv); displayText: root.formatNumber(currentValue) + " V/div"; onActivated: root.voltsPerDivRequested(Number(currentValue)) }
        SectionTitle { text: qsTr("垂直偏移") }
        Label { text: root.formatNumber(root.verticalOffsetV) + " V"; color: "#d9e4ec"; font.pixelSize: 15; font.bold: true; Layout.alignment: Qt.AlignHCenter }
        RowLayout {
            Layout.fillWidth: true; spacing: 5
            PanelButton { text: qsTr("上移"); Layout.fillWidth: true; onClicked: root.verticalOffsetRequested(root.verticalOffsetV + 0.2) }
            PanelButton { text: qsTr("下移"); Layout.fillWidth: true; onClicked: root.verticalOffsetRequested(root.verticalOffsetV - 0.2) }
            PanelButton { text: qsTr("归零"); Layout.fillWidth: true; onClicked: root.verticalOffsetRequested(0) }
        }
        SectionTitle { text: qsTr("时基") }
        DarkCombo { id: timeBox; model: [0.1, 0.2, 0.5, 1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0, 200.0]; currentIndex: root.indexOfValue(model, root.timePerDivMs); displayText: root.formatNumber(currentValue) + " ms/div"; onActivated: root.timePerDivRequested(Number(currentValue)) }
        SectionTitle { text: qsTr("水平位置") }
        Label { text: root.historyOffsetSeconds <= 0.000001 ? qsTr("最新") : qsTr("距最新 ") + root.formatDuration(root.historyOffsetSeconds); color: "#d9e4ec"; font.pixelSize: 14; font.bold: true; Layout.alignment: Qt.AlignHCenter }
        Label { text: qsTr("移动步长：") + root.formatDuration(root.horizontalStepSeconds); color: "#8fa3b4"; font.pixelSize: 12; Layout.alignment: Qt.AlignHCenter }
        RowLayout {
            Layout.fillWidth: true; spacing: 5
            PanelButton { text: qsTr("左移"); Layout.fillWidth: true; enabled: root.hasSimulationData && root.historyOffsetSeconds < root.maximumHistoryOffsetSeconds - 0.000001; onClicked: root.moveHistoryLeftRequested() }
            PanelButton { text: qsTr("右移"); Layout.fillWidth: true; enabled: root.hasSimulationData && root.historyOffsetSeconds > 0.000001; onClicked: root.moveHistoryRightRequested() }
            PanelButton { text: qsTr("归零"); Layout.fillWidth: true; enabled: root.hasSimulationData && root.historyOffsetSeconds > 0.000001; onClicked: root.resetHistoryPositionRequested() }
        }
        Item { Layout.fillHeight: true }
        Label { text: qsTr("仅调整模拟 CH1 显示。"); color: "#8fa3b4"; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
    }
}
