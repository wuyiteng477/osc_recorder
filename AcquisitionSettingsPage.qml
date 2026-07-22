pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Rectangle {
    id: root
    required property var acquisitionConfig
    required property var capabilityBackend
    required property int configurationRevision
    required property bool simulationRunning
    signal applyRequested(var config)
    signal stopAndApplyRequested(var config)
    color: "#101922"

    property string draftMode: "continuous"
    property var draftBoards: []
    property var draftChannels: []
    property var draftBoardRates: []
    property int draftSimulationStressRate: 5000
    property string draftSimulationEventMode: "off"
    property string validationMessage: ""
    readonly property int draftChannelCount: draftChannels.filter(value => value).length
    readonly property real estimatedThroughput: {
        let bytes = 0
        for (let board = 0; board < 8; ++board) {
            const count = boardChannelCount(board)
            bytes += count * Number(draftBoardRates[board] || 0) * 4
        }
        return bytes
    }
    // This is intentionally separate from estimatedThroughput: simulation
    // generates every enabled channel at one stress-test rate, while hardware
    // throughput uses each board's independently configured rate.
    readonly property real simulatedThroughput: draftChannelCount * draftSimulationStressRate * 4

    function formatRate(value) { return Number(value).toLocaleString(Qt.locale(), 'f', 0) + " S/s" }
    function formatBytesPerSecond(value) {
        if (value >= 1024 * 1024) return (value / (1024 * 1024)).toFixed(2) + " MiB/s"
        if (value >= 1024) return (value / 1024).toFixed(1) + " KiB/s"
        return value.toFixed(0) + " B/s"
    }

    function loadAppliedConfiguration() {
        draftMode = acquisitionConfig.mode
        draftBoards = acquisitionConfig.boardEnabled.slice()
        draftChannels = acquisitionConfig.channelEnabled.slice()
        draftBoardRates = acquisitionConfig.boardSampleRates.slice()
        draftSimulationStressRate = acquisitionConfig.simulationStressRate
        draftSimulationEventMode = acquisitionConfig.simulationEventMode || "off"
        validationMessage = ""
    }

    function boardChannelCount(board) { return draftChannels.slice(board * 8, board * 8 + 8).filter(value => value).length }
    function draftConfig() {
        return {
            mode: draftMode,
            boardEnabled: draftBoards.slice(),
            channelEnabled: draftChannels.slice(),
            boardSampleRates: draftBoardRates.slice(),
            simulationStressRate: draftSimulationStressRate,
            simulationEventMode: draftSimulationEventMode
        }
    }
    function stageOrApply() {
        const config = draftConfig()
        if (root.simulationRunning) {
            validationMessage = qsTr("配置已暂存。点击“停止并应用”后才会影响采集。")
            return
        }
        validationMessage = ""
        root.applyRequested(config)
    }
    function setBoard(index, selectAll) {
        const boards = draftBoards.slice(), channels = draftChannels.slice()
        for (let local = 0; local < 8; ++local) channels[index * 8 + local] = selectAll
        boards[index] = selectAll
        draftBoards = boards; draftChannels = channels
        stageOrApply()
    }
    function setChannel(index, enabled) {
        const boards = draftBoards.slice(), channels = draftChannels.slice()
        channels[index] = enabled
        const board = Math.floor(index / 8)
        boards[board] = channels.slice(board * 8, board * 8 + 8).some(value => value)
        draftBoards = boards; draftChannels = channels
        stageOrApply()
    }
    function setBoardRate(board, rate) {
        const rates = draftBoardRates.slice()
        rates[board] = rate
        draftBoardRates = rates
        stageOrApply()
    }

    onConfigurationRevisionChanged: loadAppliedConfiguration()
    Component.onCompleted: loadAppliedConfiguration()

    component SelectionCheckBox: CheckBox {
        id: control
        hoverEnabled: true
        indicator: Rectangle {
            implicitWidth: 18; implicitHeight: 18; x: 0; y: (parent.height - height) / 2; radius: 2
            color: control.checked ? "#35a9a0" : control.hovered ? "#193441" : "#14232e"
            border.color: control.down ? "#d9f6f2" : "#7292a4"
            scale: control.down ? .88 : 1
            Behavior on color { ColorAnimation { duration: 120 } }
            Behavior on scale { NumberAnimation { duration: 120 } }
        }
    }

    ScrollView {
        anchors.fill: parent; clip: true; contentWidth: availableWidth
        ColumnLayout {
            width: parent.width; anchors.margins: 24; spacing: 14
            Label { text: qsTr("采集设置"); color: "#d9e4ec"; font.pixelSize: 22; font.bold: true }
            Rectangle {
                Layout.fillWidth: true; implicitHeight: 98; radius: 5
                color: root.simulationRunning ? "#302822" : "#182b38"; border.color: root.simulationRunning ? "#e8a94b" : "#365467"
                RowLayout {
                    anchors.fill: parent; anchors.margins: 12; spacing: 14
                    ColumnLayout {
                        spacing: 3
                        Label { text: qsTr("模拟压力测试采样率"); color: "#d9e4ec"; font.pixelSize: 14 }
                        ComboBox {
                            id: stressRateBox; Layout.preferredWidth: 210
                            model: root.capabilityBackend.simulationStressRates
                            currentIndex: model.indexOf(root.draftSimulationStressRate)
                            onActivated: { root.draftSimulationStressRate = Number(currentText); root.stageOrApply() }
                            contentItem: Text { leftPadding: 8; text: root.formatRate(Number(stressRateBox.currentText)); color: "#d9e4ec"; verticalAlignment: Text.AlignVCenter }
                            background: Rectangle { radius: 3; color: "#14232e"; border.color: "#365467" }
                        }
                    }
                    ColumnLayout {
                        spacing: 3
                        Label { text: qsTr("已启用通道"); color: "#8fa3b4"; font.pixelSize: 13 }
                        Label { text: root.draftChannelCount + qsTr(" 路"); color: "#35d19b"; font.pixelSize: 18; font.bold: true }
                    }
                    ColumnLayout {
                        spacing: 3
                        Label { text: qsTr("硬件预计吞吐量"); color: "#8fa3b4"; font.pixelSize: 13 }
                        Label { text: root.formatBytesPerSecond(root.estimatedThroughput); color: "#d9e4ec"; font.pixelSize: 18; font.bold: true }
                    }
                    ColumnLayout {
                        spacing: 3
                        Label { text: qsTr("模拟生成吞吐量"); color: "#8fa3b4"; font.pixelSize: 13 }
                        Label { text: root.formatBytesPerSecond(root.simulatedThroughput); color: "#35d19b"; font.pixelSize: 18; font.bold: true }
                    }
                    Item { Layout.fillWidth: true }
                    AppButton {
                        visible: root.simulationRunning; text: qsTr("停止并应用"); primary: true; implicitHeight: 36
                        onClicked: root.stopAndApplyRequested(root.draftConfig())
                    }
                }
            }
            Rectangle {
                Layout.fillWidth: true; implicitHeight: 52; radius: 5; color: "#14232e"; border.color: "#30495a"
                RowLayout {
                    anchors.fill: parent; anchors.margins: 10; spacing: 12
                    Label { text: qsTr("模拟测试事件"); color: "#d9e4ec"; font.bold: true }
                    ComboBox {
                        id: eventModeBox; Layout.preferredWidth: 150
                        model: [qsTr("关闭"), qsTr("自动随机")]
                        currentIndex: root.draftSimulationEventMode === "automatic" ? 1 : 0
                        onActivated: { root.draftSimulationEventMode = currentIndex === 1 ? "automatic" : "off"; root.stageOrApply() }
                    }
                    Item { Layout.fillWidth: true }
                }
            }
            Label { visible: root.simulationRunning; text: qsTr("采集运行中：当前硬件采样率保持锁定；页面修改仅暂存，需“停止并应用”后生效。"); color: "#e8a94b"; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            Label { visible: root.validationMessage.length > 0; text: root.validationMessage; color: root.simulationRunning ? "#e8a94b" : "#f07d72"; Layout.fillWidth: true; wrapMode: Text.WordWrap }

            Repeater {
                model: 8
                delegate: Rectangle {
                    id: boardCard; required property int index
                    Layout.fillWidth: true; implicitHeight: 118; radius: 5; color: "#182b38"
                    border.color: root.boardChannelCount(index) > 0 ? "#3b7380" : "#314252"
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 10; spacing: 6
                        RowLayout {
                            Layout.fillWidth: true
                            SelectionCheckBox {
                                id: boardBox; text: qsTr("板卡 ") + (boardCard.index + 1) + qsTr("（全选）")
                                checked: root.boardChannelCount(boardCard.index) === 8
                                onClicked: root.setBoard(boardCard.index, root.boardChannelCount(boardCard.index) !== 8)
                                contentItem: Text { text: boardBox.text; leftPadding: boardBox.indicator.width + 7; color: "#d9e4ec"; font.bold: true; font.pixelSize: 15; verticalAlignment: Text.AlignVCenter }
                            }
                            Label { text: root.boardChannelCount(boardCard.index) + " / 8"; color: "#8fa3b4" }
                            Item { Layout.fillWidth: true }
                            Label { text: qsTr("单通道采样率"); color: "#8fa3b4"; font.pixelSize: 13 }
                            ComboBox {
                                id: boardRateBox; Layout.preferredWidth: 150
                                model: root.capabilityBackend.ratesForBoard(boardCard.index)
                                currentIndex: model.indexOf(root.draftBoardRates[boardCard.index])
                                onActivated: root.setBoardRate(boardCard.index, Number(currentText))
                                contentItem: Text { leftPadding: 8; text: root.formatRate(Number(boardRateBox.currentText)); color: "#d9e4ec"; verticalAlignment: Text.AlignVCenter }
                                background: Rectangle { radius: 3; color: "#14232e"; border.color: "#365467" }
                            }
                            Label { text: qsTr("能力表（待确认）"); color: "#6f8b9c"; font.pixelSize: 12 }
                        }
                        RowLayout {
                            Layout.fillWidth: true; spacing: 9
                            Repeater {
                                model: 8
                                delegate: SelectionCheckBox {
                                    id: channelBox; required property int index
                                    readonly property int channel: boardCard.index * 8 + index
                                    text: "CH" + (channel + 1); checked: root.draftChannels[channel]
                                    onClicked: root.setChannel(channel, checked)
                                    contentItem: Text { text: channelBox.text; leftPadding: channelBox.indicator.width + 5; color: "#d9e4ec"; font.pixelSize: 14; verticalAlignment: Text.AlignVCenter }
                                }
                            }
                            Item { Layout.fillWidth: true }
                        }
                    }
                }
            }
        }
    }
}
