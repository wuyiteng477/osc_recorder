import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Rectangle {
    id: root
    required property var channelStore
    signal channelNameRequested(int index, string name)
    signal channelVisibleRequested(int index, bool visible)
    signal channelColorRequested(int index, string color)
    color: "#101922"
    property var expandedBoards: [true, false, false, false, false, false, false, false]
    function boardExpanded(index) { return expandedBoards[index] === true }
    function toggleBoard(index) { const next = expandedBoards.slice(); next[index] = !next[index]; expandedBoards = next }
    component ButtonStyle: Button { id: button; implicitHeight: 38; contentItem: Text { text: button.text; color: button.enabled ? "#d9e4ec" : "#71818d"; font.pixelSize: 14; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter } background: Rectangle { radius: 4; color: "#223542"; border.color: "#365467" } }
    component FieldStyle: TextField { color: "#d9e4ec"; selectByMouse: true; background: Rectangle { radius: 3; color: "#14232e"; border.color: "#365467" } }

    ColumnLayout {
        anchors.fill: parent; anchors.margins: 24; spacing: 12
        Label { text: qsTr("\u901a\u9053\u8bbe\u7f6e"); color: "#d9e4ec"; font.pixelSize: 22; font.bold: true }
        Label { text: qsTr("8 \u5361 x 8 \u901a\u9053 (CH1-CH64)\uff1a\u70b9\u51fb\u677f\u5361\u6807\u9898\u5c55\u5f00\u6216\u6536\u8d77\u8be5\u677f\u7684 8 \u8def\u3002\u91c7\u96c6\u542f\u7528\u7531\u201c\u91c7\u96c6\u8bbe\u7f6e\u201d\u9875\u7edf\u4e00\u7ba1\u7406\uff1b\u6b64\u5904\u4ec5\u8bbe\u7f6e\u6ce2\u5f62\u663e\u793a\u548c\u989c\u8272\u3002"); color: "#8fa3b4"; font.pixelSize: 14 }
        ListView {
            Layout.fillWidth: true; Layout.fillHeight: true; spacing: 10; clip: true; model: 8
            delegate: Item {
                id: boardSection
                required property int index
                readonly property int boardIndex: index
                readonly property bool expanded: root.boardExpanded(boardIndex)
                width: ListView.view.width
                height: boardHeader.height + (expanded ? channelRows.height + 8 : 0)
                Rectangle {
                    id: boardHeader
                    width: parent.width; height: 46; radius: 5; color: boardSection.expanded ? "#1b3441" : "#172a35"; border.color: "#3b7380"
                    Button {
                        anchors.fill: parent; anchors.margins: 1; text: (boardSection.expanded ? "▼  " : "▶  ") + qsTr("\u677f\u5361 ") + (boardSection.boardIndex + 1) + "   CH" + (boardSection.boardIndex * 8 + 1) + "-CH" + (boardSection.boardIndex * 8 + 8)
                        contentItem: Text { leftPadding: 14; text: parent.text; color: "#d9e4ec"; font.pixelSize: 16; font.bold: true; verticalAlignment: Text.AlignVCenter }
                        background: Rectangle { radius: 4; color: "transparent" }
                        onClicked: root.toggleBoard(boardSection.boardIndex)
                    }
                    Label { anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter; text: root.channelStore.channel(boardSection.boardIndex * 8).enabled || root.channelStore.channel(boardSection.boardIndex * 8 + 1).enabled || root.channelStore.channel(boardSection.boardIndex * 8 + 2).enabled || root.channelStore.channel(boardSection.boardIndex * 8 + 3).enabled || root.channelStore.channel(boardSection.boardIndex * 8 + 4).enabled || root.channelStore.channel(boardSection.boardIndex * 8 + 5).enabled || root.channelStore.channel(boardSection.boardIndex * 8 + 6).enabled || root.channelStore.channel(boardSection.boardIndex * 8 + 7).enabled ? qsTr("\u91c7\u96c6\u5df2\u542f\u7528") : qsTr("\u672a\u91c7\u96c6"); color: "#8fa3b4"; font.pixelSize: 13 }
                }
                Column {
                    id: channelRows
                    visible: boardSection.expanded; width: parent.width; y: boardHeader.height + 8; spacing: 6
                    Repeater { model: 8
                        delegate: Rectangle {
                            id: card
                            required property int index
                            readonly property int channelIndex: boardSection.boardIndex * 8 + index
                            readonly property var info: root.channelStore.channel(channelIndex)
                            width: channelRows.width; height: 70; radius: 5; color: "#182b38"; border.color: info.color
                            RowLayout { anchors.fill: parent; anchors.margins: 10; spacing: 10
                                ColumnLayout { Layout.preferredWidth: 210; Layout.fillHeight: true; spacing: 2
                                    Label { text: card.info.name; color: card.info.color; font.pixelSize: 18; font.bold: true }
                                    Label { text: qsTr("\u677f\u5361 ") + (card.info.boardIndex + 1) + " / " + qsTr("\u901a\u9053 ") + (card.info.channelIndex + 1); color: "#8fa3b4"; font.pixelSize: 14 }
                                }
                                Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: "#365467" }
                                FieldStyle { id: nameField; Layout.preferredWidth: 220; implicitHeight: 38; text: card.info.name; maximumLength: 20; font.pixelSize: 15; onEditingFinished: { if (text.trim().length) root.channelNameRequested(card.channelIndex, text) } }
                                ButtonStyle { Layout.preferredWidth: 118; text: card.info.visible ? qsTr("\u9690\u85cf\u6ce2\u5f62") : qsTr("\u663e\u793a\u6ce2\u5f62"); onClicked: root.channelVisibleRequested(card.channelIndex, !card.info.visible) }
                                ComboBox { id: colorBox; Layout.preferredWidth: 120; implicitHeight: 38; model: ["Cyan", "Yellow", "Green", "Purple", "Orange", "Blue", "Pink", "Lime"]; currentIndex: ["#39e6bb", "#f2d05c", "#72d18c", "#c58bea", "#f0a35e", "#63b3ed", "#ef7aa8", "#a6d96a"].indexOf(card.info.color); onActivated: root.channelColorRequested(card.channelIndex, ["#39e6bb", "#f2d05c", "#72d18c", "#c58bea", "#f0a35e", "#63b3ed", "#ef7aa8", "#a6d96a"][currentIndex]); contentItem: Text { leftPadding: 8; text: colorBox.currentText; color: card.info.color; font.pixelSize: 14; verticalAlignment: Text.AlignVCenter } background: Rectangle { radius: 4; color: "#223542"; border.color: "#365467" } }
                                Item { Layout.fillWidth: true }
                                Label { text: Number(card.info.voltsPerDiv).toFixed(1) + " V/div   " + Number(card.info.verticalOffsetV).toFixed(1) + " V"; color: "#d9e4ec"; font.pixelSize: 14 }
                            }
                        }
                    }
                }
            }
        }
    }
}
