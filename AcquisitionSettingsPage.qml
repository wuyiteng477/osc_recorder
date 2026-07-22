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
    property var expandedBoards: [true, false, false, false, false, false, false, false]
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
        const expanded = []
        for (let board = 0; board < 8; ++board)
            expanded.push(draftChannels.slice(board * 8, board * 8 + 8).some(enabled => enabled))
        expandedBoards = expanded
        validationMessage = ""
    }

    function boardChannelCount(board) { return draftChannels.slice(board * 8, board * 8 + 8).filter(value => value).length }
    function boardExpanded(board) { return expandedBoards[board] === true }
    function toggleBoard(board) { const next = expandedBoards.slice(); next[board] = !next[board]; expandedBoards = next }
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
            color: control.hovered ? "#193441" : "#14232e"
            border.color: control.checked ? "#48c5b6" : control.down ? "#d9f6f2" : "#7292a4"
            scale: control.down ? .88 : 1
            Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 1; visible: control.checked; color: "#48c5b6" }
            Behavior on color { ColorAnimation { duration: 120 } }
            Behavior on scale { NumberAnimation { duration: 120 } }
        }
    }

    // The page-level wrapper owns the common content gutter, matching the
    // root layouts of ChannelSettingsPage and RecordingPage.
    Item {
        anchors.fill: parent
        anchors.margins: 24

        ScrollView {
            anchors.fill: parent
            clip: true
            contentWidth: availableWidth
            ColumnLayout {
            width: parent.width
            spacing: 12
            Label { text: qsTr("采集设置"); color: "#d9e4ec"; font.pixelSize: 22; font.bold: true }
            Rectangle {
                Layout.fillWidth: true; implicitHeight: 62; radius: 5; color: "#182b38"; border.color: "#365467"
                RowLayout {
                    anchors.fill: parent; anchors.margins: 10; spacing: 18
                    ColumnLayout { spacing: 1; Label { text: qsTr("\u6a21\u62df\u91c7\u6837\u7387"); color: "#8fa3b4"; font.pixelSize: 12 } Label { text: root.formatRate(root.draftSimulationStressRate); color: "#d9e4ec"; font.pixelSize: 17; font.bold: true } }
                    ColumnLayout { spacing: 1; Label { text: qsTr("\u542f\u7528\u901a\u9053"); color: "#8fa3b4"; font.pixelSize: 12 } Label { text: root.draftChannelCount + qsTr(" \u8def"); color: "#35d19b"; font.pixelSize: 17; font.bold: true } }
                    ColumnLayout { spacing: 1; Label { text: qsTr("\u9884\u8ba1\u6570\u636e\u7387"); color: "#8fa3b4"; font.pixelSize: 12 } Label { text: root.formatBytesPerSecond(root.simulatedThroughput); color: "#35d19b"; font.pixelSize: 17; font.bold: true } }
                    Item { Layout.fillWidth: true }
                    AppButton { visible: root.simulationRunning; text: qsTr("\u505c\u6b62\u5e76\u5e94\u7528"); primary: true; implicitHeight: 32; onClicked: root.stopAndApplyRequested(root.draftConfig()) }
                    /* Legacy malformed text retained only to keep this patch narrowly scoped.
                    ColumnLayout { spacing: 1; Label { text: qsTr("模拟采样率"); color: "#8fa3b4"; font.pixelSize: 12 }; Label { text: root.formatRate(root.draftSimulationStressRate); color: "#d9e4ec"; font.pixelSize: 17; font.bold: true } }
                    ColumnLayout { spacing: 1; Label { text: qsTr("启用通道"); color: "#8fa3b4"; font.pixelSize: 12 }; Label { text: root.draftChannelCount + qsTr(" 路"); color: "#35d19b"; font.pixelSize: 17; font.bold: true } }
                    ColumnLayout { spacing: 1; Label { text: qsTr("预计数据率"); color: "#8fa3b4"; font.pixelSize: 12 }; Label { text: root.formatBytesPerSecond(root.simulatedThroughput); color: "#35d19b"; font.pixelSize: 17; font.bold: true } }
                    Item { Layout.fillWidth: true }
                    AppButton { visible: root.simulationRunning; text: qsTr("停止并应用"); primary: true; implicitHeight: 32; onClicked: root.stopAndApplyRequested(root.draftConfig()) }
                    */
                }
            }
            Rectangle {
                Layout.fillWidth: true; implicitHeight: 54; radius: 5; color: "#14232e"; border.color: "#30495a"
                RowLayout {
                    anchors.fill: parent; anchors.margins: 10; spacing: 12
                    Label { text: qsTr("模拟源设置"); color: "#d9e4ec"; font.bold: true }
                    Label { text: qsTr("压力采样率"); color: "#8fa3b4"; font.pixelSize: 12 }
                    ComboBox {
                        id: stressRateBox; Layout.preferredWidth: 150; implicitHeight: 32; model: root.capabilityBackend.simulationStressRates; currentIndex: model.indexOf(root.draftSimulationStressRate)
                        onActivated: { root.draftSimulationStressRate = Number(currentText); root.stageOrApply() }
                        contentItem: Text { leftPadding: 8; text: root.formatRate(Number(stressRateBox.currentText)); color: "#d9e4ec"; verticalAlignment: Text.AlignVCenter }
                        background: Rectangle { radius: 3; color: "#223542"; border.color: "#365467" }
                    }
                    Label { text: qsTr("随机事件"); color: "#8fa3b4"; font.pixelSize: 12 }
                    ComboBox {
                        id: eventModeBox; Layout.preferredWidth: 130; implicitHeight: 32; model: [qsTr("关闭"), qsTr("自动随机")]; currentIndex: root.draftSimulationEventMode === "automatic" ? 1 : 0
                        onActivated: { root.draftSimulationEventMode = currentIndex === 1 ? "automatic" : "off"; root.stageOrApply() }
                        contentItem: Text { leftPadding: 8; text: eventModeBox.currentText; color: "#d9e4ec"; verticalAlignment: Text.AlignVCenter }
                        background: Rectangle { radius: 3; color: "#223542"; border.color: "#365467" }
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
                    readonly property bool expanded: root.boardExpanded(index)
                    Layout.fillWidth: true; implicitHeight: expanded ? 86 : 44; radius: 5; color: "#182b38"
                    border.color: root.boardChannelCount(index) > 0 ? "#3b7380" : "#314252"
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 7; spacing: 5
                        RowLayout {
                            Layout.fillWidth: true
                            AppButton { text: boardCard.expanded ? "⌄" : "›"; implicitWidth: 26; implicitHeight: 28; fillColor: "transparent"; borderColor: "transparent"; textColor: "#8fa3b4"; font.pixelSize: 20; onClicked: root.toggleBoard(boardCard.index) }
                            SelectionCheckBox {
                                id: boardBox; text: qsTr("板卡 ") + (boardCard.index + 1)
                                checked: root.boardChannelCount(boardCard.index) === 8
                                onClicked: root.setBoard(boardCard.index, root.boardChannelCount(boardCard.index) !== 8)
                                contentItem: Text { text: boardBox.text; leftPadding: boardBox.indicator.width + 7; color: "#d9e4ec"; font.bold: true; font.pixelSize: 15; verticalAlignment: Text.AlignVCenter }
                            }
                            Label { text: root.boardChannelCount(boardCard.index) + " / 8"; color: root.boardChannelCount(boardCard.index) > 0 ? "#35d19b" : "#8fa3b4"; font.pixelSize: 12 }
                            Item { Layout.fillWidth: true }
                            ComboBox {
                                id: boardRateBox; Layout.preferredWidth: 132; implicitHeight: 28
                                model: root.capabilityBackend.ratesForBoard(boardCard.index)
                                currentIndex: model.indexOf(root.draftBoardRates[boardCard.index])
                                onActivated: root.setBoardRate(boardCard.index, Number(currentText))
                                contentItem: Text { leftPadding: 8; text: root.formatRate(Number(boardRateBox.currentText)); color: "#d9e4ec"; verticalAlignment: Text.AlignVCenter }
                                background: Rectangle { radius: 3; color: "#223542"; border.color: "#365467" }
                            }
                            Rectangle { implicitWidth: 58; implicitHeight: 20; radius: 10; color: "#26313b"; border.color: "#485b69"; Label { anchors.centerIn: parent; text: qsTr("待确认"); color: "#8fa3b4"; font.pixelSize: 10 } }
                        }
                        RowLayout {
                            visible: boardCard.expanded; Layout.fillWidth: true; spacing: 8
                            Repeater {
                                model: 8
                                delegate: SelectionCheckBox {
                                    id: channelBox; required property int index
                                    readonly property int channel: boardCard.index * 8 + index
                                    text: "CH" + (channel + 1); checked: root.draftChannels[channel]
                                    onClicked: root.setChannel(channel, checked)
                                    contentItem: Text { text: channelBox.text; leftPadding: channelBox.indicator.width + 5; color: channelBox.checked ? "#d9e4ec" : "#8fa3b4"; font.pixelSize: 13; verticalAlignment: Text.AlignVCenter }
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
}
