pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Rectangle {
    id: root
    required property var acquisitionConfig
    required property int configurationRevision
    required property bool simulationRunning
    signal applyRequested(var config)
    color: "#101922"

    property int draftSampleRate: 5000
    property string draftMode: "continuous"
    property var draftBoards: []
    property var draftChannels: []
    property string validationMessage: ""
    readonly property int draftChannelCount: draftChannels.filter(value => value).length

    function loadAppliedConfiguration() {
        draftSampleRate = acquisitionConfig.sampleRate
        draftMode = acquisitionConfig.mode
        draftBoards = acquisitionConfig.boardEnabled.slice()
        draftChannels = acquisitionConfig.channelEnabled.slice()
        validationMessage = ""
    }

    function boardChannelCount(board) {
        return draftChannels.slice(board * 8, board * 8 + 8).filter(value => value).length
    }

    function commitSelection(boards, channels) {
        if (!channels.some(value => value)) {
            validationMessage = qsTr("\u8bf7\u81f3\u5c11\u9009\u4e2d\u4e00\u4e2a\u91c7\u96c6\u901a\u9053\u3002")
            return
        }

        draftBoards = boards; draftChannels = channels; validationMessage = ""
        applyRequested({ sampleRate: draftSampleRate, mode: draftMode, boardEnabled: boards, channelEnabled: channels })
    }

    // Board checkbox is only a convenient select-all / clear-all control.
    // Individual channels remain selectable even when the board is not all selected.
    function setBoard(index, selectAll) {
        const boards = draftBoards.slice()
        const channels = draftChannels.slice()

        for (let local = 0; local < 8; ++local)
            channels[index * 8 + local] = selectAll
        boards[index] = selectAll

        commitSelection(boards, channels)
    }

    function setChannel(index, enabled) {
        const boards = draftBoards.slice()
        const channels = draftChannels.slice()
        channels[index] = enabled
        const board = Math.floor(index / 8)
        boards[board] = channels.slice(board * 8, board * 8 + 8).some(value => value)
        commitSelection(boards, channels)
    }

    function commitSampleRate() {
        const value = Number(sampleRateField.text)

        if (!Number.isInteger(value) || value < 100 || value > 1000000) {
            validationMessage = qsTr("\u91c7\u6837\u7387\u5fc5\u987b\u662f 100 \u81f3 1,000,000 S/s \u7684\u6574\u6570\u3002")
            return
        }

        draftSampleRate = value
        validationMessage = ""
        applyRequested({ sampleRate: value, mode: draftMode, boardEnabled: draftBoards.slice(), channelEnabled: draftChannels.slice() })
    }

    function commitMode(mode) {
        draftMode = mode
        applyRequested({ sampleRate: draftSampleRate, mode: mode, boardEnabled: draftBoards.slice(), channelEnabled: draftChannels.slice() })
    }

    onConfigurationRevisionChanged: loadAppliedConfiguration()
    Component.onCompleted: loadAppliedConfiguration()

    ScrollView {
        anchors.fill: parent
        clip: true
        contentWidth: availableWidth

        ColumnLayout {
            width: parent.width
            anchors.margins: 24
            spacing: 14

            Label {
                text: qsTr("\u91c7\u96c6\u8bbe\u7f6e")
                color: "#d9e4ec"
                font.pixelSize: 22
                font.bold: true
            }

            Label {
                text: qsTr("\u677f\u5361\u590d\u9009\u6846\u7528\u4e8e\u4e00\u952e\u5168\u9009/\u53d6\u6d88\u8be5\u677f 8 \u8def\u3002\u5355\u4e2a\u901a\u9053\u53ef\u72ec\u7acb\u542f\u7528\uff0c\u52fe\u9009\u540e\u7acb\u5373\u751f\u6548\u3002\u5b9e\u65f6\u9875\u9762\u6700\u591a\u663e\u793a 8 \u8def\u6ce2\u5f62\u3002")
                color: "#8fa3b4"
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 74
                radius: 5
                color: root.simulationRunning ? "#302822" : "#182b38"
                border.color: root.simulationRunning ? "#e8a94b" : "#365467"

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 14

                    Label {
                        text: qsTr("\u91c7\u6837\u7387 (S/s)")
                        color: "#d9e4ec"
                        font.pixelSize: 15
                    }

                    TextField {
                        id: sampleRateField
                        Layout.preferredWidth: 140
                        text: String(root.draftSampleRate)
                        enabled: !root.simulationRunning
                        selectByMouse: true
                        validator: IntValidator { bottom: 100; top: 1000000 }
                        onEditingFinished: root.commitSampleRate()
                        color: "#d9e4ec"

                        background: Rectangle {
                            radius: 3
                            color: "#14232e"
                            border.color: "#365467"
                        }
                    }

                    Label {
                        text: qsTr("\u91c7\u96c6\u6a21\u5f0f")
                        color: "#d9e4ec"
                        font.pixelSize: 15
                    }

                    ComboBox {
                        id: modeBox
                        Layout.preferredWidth: 160
                        enabled: !root.simulationRunning
                        model: [qsTr("\u8fde\u7eed\u91c7\u96c6"), qsTr("\u7a81\u53d1\u91c7\u96c6\uff08100 ms\uff09")]
                        currentIndex: root.draftMode === "burst" ? 1 : 0

                        onActivated: root.commitMode(currentIndex === 1 ? "burst" : "continuous")

                        contentItem: Text {
                            leftPadding: 8
                            text: modeBox.displayText
                            color: "#d9e4ec"
                            verticalAlignment: Text.AlignVCenter
                        }

                        background: Rectangle {
                            radius: 3
                            color: "#14232e"
                            border.color: "#365467"
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    Label {
                        text: root.draftChannelCount + qsTr(" \u8def\u5df2\u542f\u7528")
                        color: "#35d19b"
                        font.bold: true
                        font.pixelSize: 15
                    }
                }
            }

            Label {
                visible: root.simulationRunning
                text: qsTr("\u91c7\u96c6\u8fd0\u884c\u4e2d\uff1a\u91c7\u6837\u7387\u3001\u6a21\u5f0f\u3001\u677f\u5361\u548c\u91c7\u96c6\u901a\u9053\u5df2\u9501\u5b9a\u3002\u8bf7\u5148\u505c\u6b62\u91c7\u96c6\u540e\u518d\u4fee\u6539\u3002")
                color: "#e8a94b"
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            Label {
                visible: root.validationMessage.length > 0
                text: root.validationMessage
                color: "#f07d72"
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            Repeater {
                model: 8

                delegate: Rectangle {
                    id: boardCard
                    required property int index
                    Layout.fillWidth: true
                    implicitHeight: 92
                    radius: 5
                    color: "#182b38"
                    border.color: root.boardChannelCount(index) > 0 ? "#3b7380" : "#314252"

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true

                            CheckBox {
                                id: boardBox
                                text: qsTr("\u677f\u5361 ") + (boardCard.index + 1) + qsTr("\uff08\u5168\u9009\uff09")
                                checked: root.boardChannelCount(boardCard.index) === 8
                                enabled: !root.simulationRunning
                                onClicked: root.setBoard(boardCard.index, root.boardChannelCount(boardCard.index) !== 8)

                                contentItem: Text {
                                    text: boardBox.text
                                    leftPadding: boardBox.indicator.width + 7
                                    color: "#d9e4ec"
                                    font.bold: true
                                    font.pixelSize: 15
                                    verticalAlignment: Text.AlignVCenter
                                }

                                indicator: Rectangle {
                                    implicitWidth: 18
                                    implicitHeight: 18
                                    x: 0
                                    y: (parent.height - height) / 2
                                    radius: 2
                                    color: boardBox.checked ? "#35a9a0" : "#14232e"
                                    border.color: "#7292a4"
                                }
                            }

                            Item {
                                Layout.fillWidth: true
                            }

                            Label {
                                text: root.boardChannelCount(boardCard.index) + " / 8"
                                color: "#8fa3b4"
                                font.pixelSize: 14
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 9

                            Repeater {
                                model: 8

                                delegate: CheckBox {
                                    id: channelBox
                                    required property int index
                                    readonly property int channel: (boardCard.index * 8) + index
                                    text: "CH" + (channel + 1)
                                    checked: root.draftChannels[channel]
                                    enabled: !root.simulationRunning

                                    onClicked: root.setChannel(channel, checked)

                                    contentItem: Text {
                                        text: channelBox.text
                                        leftPadding: channelBox.indicator.width + 5
                                        color: channelBox.enabled ? "#d9e4ec" : "#61717c"
                                        font.pixelSize: 14
                                        verticalAlignment: Text.AlignVCenter
                                    }

                                    indicator: Rectangle {
                                        implicitWidth: 16
                                        implicitHeight: 16
                                        x: 0
                                        y: (parent.height - height) / 2
                                        radius: 2
                                        color: channelBox.checked ? "#35a9a0" : "#14232e"
                                        border.color: "#7292a4"
                                    }
                                }
                            }

                            Item {
                                Layout.fillWidth: true
                            }
                        }
                    }
                }
            }
        }
    }
}
