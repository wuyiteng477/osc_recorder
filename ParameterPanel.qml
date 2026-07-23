import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Rectangle {
    id: root
    required property var channelStore
    required property int selectedChannelIndex
    required property real timePerDivMs
    required property real horizontalStepSeconds
    required property string displayMode
    required property string interpolationMode
    required property bool interpolationAvailable
    required property bool gridVisible
    required property bool hasSimulationData
    required property real historyOffsetSeconds
    required property real maximumHistoryOffsetSeconds
    required property bool historyLeftAvailable
    required property bool historyRightAvailable
    required property int triggerChannelIndex
    required property string triggerEdge
    required property real triggerLevel
    required property real triggerHysteresis
    required property string triggerMode
    required property int triggerSampleIndex
    required property bool triggerEnabled
    required property real triggerPosition
    required property string cursorMode
    required property real timeCursor1
    required property real timeCursor2
    required property real voltageCursor1
    required property real voltageCursor2
    signal selectedChannelRequested(int index)
    signal voltsPerDivRequested(real value)
    signal timePerDivRequested(real value)
    signal verticalOffsetRequested(real value)
    signal displayModeRequested(string value)
    signal interpolationModeRequested(string value)
    signal cursorModeRequested(string value)
    signal measurementPanelRequested()
    signal gridVisibleRequested(bool value)
    signal moveHistoryLeftRequested()
    signal moveHistoryRightRequested()
    signal resetHistoryPositionRequested()
    signal edgeTriggerRequested(int channelIndex, string edge, real level, real hysteresis, string mode)
    signal edgeTriggerRearmRequested()
    signal edgeTriggerEnabledRequested(bool enabled)
    signal triggerPositionRequested(real value)
    // The model is populated after this panel is constructed.  Include the
    // store revision in the binding so initial CH1 is refreshed automatically,
    // rather than requiring a temporary switch to another channel.
    readonly property var channel: {
        const storeRevision = channelStore.revision
        if (channelStore.channelModel.count <= selectedChannelIndex)
            return ({ name: "CH" + (selectedChannelIndex + 1), color: "#71818d", voltsPerDiv: 1, verticalOffsetV: 0, defaultOffsetV: 0 })
        return channelStore.channel(selectedChannelIndex)
    }
    // The parameter panel edits waveform presentation, so it should expose
    // only channels that currently own a real-time waveform view (maximum 8).
    readonly property var editableChannelIndexes: {
        const storeRevision = channelStore.revision
        return channelStore.activeViewChannels()
    }
    readonly property var triggerableChannelIndexes: {
        const storeRevision = channelStore.revision
        const indexes = []
        for (let index = 0; index < channelStore.channelModel.count; ++index)
            if (channelStore.channel(index).enabled)
                indexes.push(index)
        return indexes
    }
    color: "#15212c"
    border.color: "#314252"

    function num(value) { return Number(value).toFixed(1).replace(/\.0$/, "") }
    function cursorTime(value) { return Math.abs(value) < 1 ? Number(value * 1000).toFixed(3) + " ms" : Number(value).toFixed(6) + " s" }
    function cursorFrequency(value) { return Math.abs(value) < 1000 ? Math.abs(value).toFixed(3) + " Hz" : (Math.abs(value) / 1000).toFixed(3) + " kHz" }

    // 各分区标题样式统一，方便后续增减设置项。
    component Section: Label {
        color: "#8fa3b4"
        font.pixelSize: 12
        font.bold: true
        Layout.topMargin: 5
    }

    component Btn: AppButton { implicitHeight: 32 }

    component Separator: Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: "#314252"
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 7

        Label {
            text: qsTr("\u901a\u9053\u53c2\u6570")
            color: "#d9e4ec"
            font.pixelSize: 16
            font.bold: true
        }

        Section { text: qsTr("\u5f53\u524d\u7f16\u8f91\u901a\u9053") }

        ComboBox {
            id: channels
            Layout.fillWidth: true
            implicitHeight: 32
            model: root.editableChannelIndexes
            enabled: root.editableChannelIndexes.length > 0
            currentIndex: Math.max(0, root.editableChannelIndexes.indexOf(root.selectedChannelIndex))

            onActivated: root.selectedChannelRequested(root.editableChannelIndexes[currentIndex])

            delegate: ItemDelegate {
                required property var modelData
                width: channels.width
                text: root.channelStore.channel(modelData).name
            }

            contentItem: Text {
                leftPadding: 10
                text: root.channel.name
                color: root.channel.color
                verticalAlignment: Text.AlignVCenter
            }

            background: Rectangle {
                color: "#223542"
                radius: 3
                border.color: root.channel.color
            }
        }

        Separator { }

        Section { text: qsTr("\u5782\u76f4\u63a7\u5236") }

        ComboBox {
            id: volts
            Layout.fillWidth: true
            implicitHeight: 32
            model: [.2, .5, 1, 2, 5]
            currentIndex: model.indexOf(root.channel.voltsPerDiv)

            onActivated: root.voltsPerDivRequested(Number(currentValue))

            contentItem: Text {
                leftPadding: 10
                text: root.num(volts.currentValue) + " V/div"
                color: "#d9e4ec"
                verticalAlignment: Text.AlignVCenter
            }

            background: Rectangle {
                color: "#223542"
                radius: 3
                border.color: "#365467"
            }
        }

        Label {
            text: qsTr("\u5782\u76f4\u504f\u79fb  ") + root.num(root.channel.verticalOffsetV) + " V"
            color: root.channel.color
        }

        RowLayout {
            Layout.fillWidth: true

            Btn {
                text: qsTr("\u4e0a\u79fb")
                Layout.fillWidth: true
                onClicked: root.verticalOffsetRequested(root.channel.verticalOffsetV + .2)
            }

            Btn {
                text: qsTr("\u4e0b\u79fb")
                Layout.fillWidth: true
                onClicked: root.verticalOffsetRequested(root.channel.verticalOffsetV - .2)
            }

            Btn {
                text: qsTr("\u5f52\u96f6")
                Layout.fillWidth: true
                onClicked: root.verticalOffsetRequested(root.channel.defaultOffsetV)
            }
        }

        Separator { }

        Section { text: qsTr("\u6c34\u5e73\u63a7\u5236") }

        ComboBox {
            id: times
            Layout.fillWidth: true
            implicitHeight: 32
            model: [.1, .2, .5, 1, 2, 5, 10, 20, 50, 100, 200]
            currentIndex: model.indexOf(root.timePerDivMs)

            onActivated: root.timePerDivRequested(Number(currentValue))

            contentItem: Text {
                leftPadding: 10
                text: root.num(times.currentValue) + " ms/div"
                color: "#d9e4ec"
                verticalAlignment: Text.AlignVCenter
            }

            background: Rectangle {
                color: "#223542"
                radius: 3
                border.color: "#365467"
            }
        }

        Label {
            text: qsTr("\u5386\u53f2\u4f4d\u7f6e  ") + (root.historyOffsetSeconds < 1e-9 ? qsTr("\u6700\u65b0") : root.num(root.historyOffsetSeconds * 1000) + " ms")
            color: "#8fa3b4"
        }

        RowLayout {
            Layout.fillWidth: true

            Btn {
                text: qsTr("\u5de6\u79fb")
                Layout.fillWidth: true
                enabled: root.historyLeftAvailable
                onClicked: root.moveHistoryLeftRequested()
            }

            Btn {
                text: qsTr("\u53f3\u79fb")
                Layout.fillWidth: true
                enabled: root.historyRightAvailable
                onClicked: root.moveHistoryRightRequested()
            }

            Btn {
                text: qsTr("\u5f52\u96f6")
                Layout.fillWidth: true
                enabled: root.historyRightAvailable || root.historyLeftAvailable
                onClicked: root.resetHistoryPositionRequested()
            }
        }

        Separator { }

        RowLayout {
            Layout.fillWidth: true
            Btn {
                text: qsTr("边沿触发设置")
                selected: root.triggerEnabled
                Layout.fillWidth: true
                onClicked: triggerDialog.open()
            }
            Rectangle {
                implicitWidth: 52; implicitHeight: 26; radius: 13
                color: root.triggerEnabled ? (root.triggerSampleIndex >= 0 ? "#163b35" : "#26372b") : "#27313a"
                border.color: root.triggerEnabled ? "#35a990" : "#526372"
                Label { anchors.centerIn: parent; text: !root.triggerEnabled ? qsTr("关闭") : root.triggerSampleIndex >= 0 ? qsTr("已触发") : qsTr("等待"); color: root.triggerEnabled ? "#c9f3e5" : "#9aaab5"; font.pixelSize: 11; font.bold: true }
            }
        }

        Section { visible: false; Layout.preferredHeight: 0; text: qsTr("\u8fb9\u6cbf\u89e6\u53d1") }

        Btn {
            visible: false; Layout.preferredHeight: 0; Layout.maximumHeight: 0
            Layout.fillWidth: true
            text: root.triggerEnabled ? qsTr("\u5173\u95ed\u89e6\u53d1") : qsTr("\u5f00\u542f\u89e6\u53d1")
            selected: root.triggerEnabled
            primary: root.triggerEnabled
            onClicked: root.edgeTriggerEnabledRequested(!root.triggerEnabled)
        }

        ComboBox {
            id: triggerChannelBox
            visible: false; Layout.preferredHeight: 0; Layout.maximumHeight: 0
            Layout.fillWidth: true; implicitHeight: 30
            model: root.triggerableChannelIndexes
            currentIndex: Math.max(0, root.triggerableChannelIndexes.indexOf(root.triggerChannelIndex))
            onActivated: root.edgeTriggerRequested(root.triggerableChannelIndexes[currentIndex], root.triggerEdge, root.triggerLevel, root.triggerHysteresis, root.triggerMode)
            contentItem: Text { leftPadding: 10; text: qsTr("\u89e6\u53d1\u901a\u9053\uff1a") + (root.triggerableChannelIndexes.length ? root.channelStore.channel(root.triggerableChannelIndexes[triggerChannelBox.currentIndex]).name : "-"); color: "#d9e4ec"; verticalAlignment: Text.AlignVCenter }
            background: Rectangle { color: "#223542"; radius: 3; border.color: "#365467" }
        }

        RowLayout {
            visible: false; Layout.preferredHeight: 0; Layout.maximumHeight: 0
            Layout.fillWidth: true
            ComboBox {
                id: triggerEdgeBox; Layout.fillWidth: true; implicitHeight: 30
                model: [qsTr("\u4e0a\u5347\u6cbf"), qsTr("\u4e0b\u964d\u6cbf")]
                currentIndex: root.triggerEdge === "falling" ? 1 : 0
                onActivated: root.edgeTriggerRequested(root.triggerChannelIndex, currentIndex === 1 ? "falling" : "rising", root.triggerLevel, root.triggerHysteresis, root.triggerMode)
                contentItem: Text { leftPadding: 8; text: triggerEdgeBox.currentText; color: "#d9e4ec"; verticalAlignment: Text.AlignVCenter }
                background: Rectangle { color: "#223542"; radius: 3; border.color: "#365467" }
            }
            ComboBox {
                id: triggerModeBox; Layout.fillWidth: true; implicitHeight: 30
                model: [qsTr("\u81ea\u52a8"), qsTr("\u6b63\u5e38"), qsTr("\u5355\u6b21")]
                currentIndex: ({ auto: 0, normal: 1, single: 2 })[root.triggerMode]
                onActivated: root.edgeTriggerRequested(root.triggerChannelIndex, root.triggerEdge, root.triggerLevel, root.triggerHysteresis, ["auto", "normal", "single"][currentIndex])
                contentItem: Text { leftPadding: 8; text: triggerModeBox.currentText; color: "#d9e4ec"; verticalAlignment: Text.AlignVCenter }
                background: Rectangle { color: "#223542"; radius: 3; border.color: "#365467" }
            }
        }

        RowLayout {
            visible: false; Layout.preferredHeight: 0; Layout.maximumHeight: 0
            Layout.fillWidth: true
            ComboBox {
                id: triggerLevelBox; Layout.fillWidth: true; implicitHeight: 30
                model: [-1, -.5, 0, .5, 1]
                currentIndex: model.indexOf(root.triggerLevel)
                onActivated: root.edgeTriggerRequested(root.triggerChannelIndex, root.triggerEdge, Number(currentValue), root.triggerHysteresis, root.triggerMode)
                contentItem: Text { leftPadding: 8; text: qsTr("\u7535\u5e73\uff1a") + root.num(triggerLevelBox.currentValue) + " V"; color: "#d9e4ec"; verticalAlignment: Text.AlignVCenter }
                background: Rectangle { color: "#223542"; radius: 3; border.color: "#365467" }
            }
            ComboBox {
                id: hysteresisBox; Layout.fillWidth: true; implicitHeight: 30
                model: [.05, .1, .2, .5]
                currentIndex: model.indexOf(root.triggerHysteresis)
                onActivated: root.edgeTriggerRequested(root.triggerChannelIndex, root.triggerEdge, root.triggerLevel, Number(currentValue), root.triggerMode)
                contentItem: Text { leftPadding: 8; text: qsTr("\u8fdf\u6ede\uff1a") + root.num(hysteresisBox.currentValue) + " V"; color: "#d9e4ec"; verticalAlignment: Text.AlignVCenter }
                background: Rectangle { color: "#223542"; radius: 3; border.color: "#365467" }
            }
        }

        ComboBox {
            id: triggerPositionBox; Layout.fillWidth: true; implicitHeight: 30
            visible: false; Layout.preferredHeight: 0; Layout.maximumHeight: 0
            model: [.2, .4, .5, .6, .8]
            currentIndex: model.indexOf(root.triggerPosition)
            onActivated: root.triggerPositionRequested(Number(currentValue))
            contentItem: Text { leftPadding: 8; text: qsTr("\u89e6\u53d1\u4f4d\u7f6e\uff1a") + Math.round(triggerPositionBox.currentValue * 100) + "%"; color: "#d9e4ec"; verticalAlignment: Text.AlignVCenter }
            background: Rectangle { color: "#223542"; radius: 3; border.color: "#365467" }
        }

        RowLayout {
            visible: false; Layout.preferredHeight: 0; Layout.maximumHeight: 0
            Layout.fillWidth: true
            Rectangle { radius: 10; implicitHeight: 22; Layout.fillWidth: true; color: root.triggerEnabled ? (root.triggerSampleIndex >= 0 ? "#163b35" : "#26372b") : "#27313a"; border.color: root.triggerEnabled ? "#35a990" : "#526372"; Label { anchors.centerIn: parent; text: !root.triggerEnabled ? qsTr("\u89e6\u53d1\u5df2\u5173\u95ed") : root.triggerSampleIndex >= 0 ? qsTr("\u5df2\u89e6\u53d1") : qsTr("\u7b49\u5f85\u89e6\u53d1"); color: root.triggerEnabled ? "#c9f3e5" : "#9aaab5"; font.pixelSize: 12; font.bold: true } }
            Btn { text: qsTr("\u91cd\u65b0\u5e03\u9632"); enabled: root.triggerEnabled; onClicked: root.edgeTriggerRearmRequested() }
        }

        Separator { visible: false; Layout.preferredHeight: 0 }

        Section { text: qsTr("\u663e\u793a\u63a7\u5236") }

        RowLayout {
            Layout.fillWidth: true

            Btn {
                text: qsTr("\u66f4\u65b0")
                selected: root.displayMode === "update"
                Layout.fillWidth: true
                enabled: root.displayMode !== "update"
                onClicked: root.displayModeRequested("update")
            }

            Btn {
                text: qsTr("\u6eda\u52a8")
                selected: root.displayMode === "roll"
                Layout.fillWidth: true
                enabled: root.displayMode !== "roll"
                onClicked: root.displayModeRequested("roll")
            }

            Btn {
                text: root.gridVisible ? qsTr("\u5173\u95ed\u6805\u683c") : qsTr("\u663e\u793a\u6805\u683c")
                selected: root.gridVisible
                Layout.fillWidth: true
                onClicked: root.gridVisibleRequested(!root.gridVisible)
            }
        }

        ComboBox {
            id: interpolationBox
            Layout.fillWidth: true
            implicitHeight: 32
            model: [qsTr("自动"), qsTr("无"), qsTr("线性"), qsTr("方波"), qsTr("正弦")]
            currentIndex: ({ auto: 0, none: 1, linear: 2, step: 3, sine: 4 })[root.interpolationMode]
            enabled: root.interpolationAvailable
            onActivated: root.interpolationModeRequested(["auto", "none", "linear", "step", "sine"][currentIndex])
            contentItem: Text {
                // ComboBox reserves space for its indicator on the right.
                // Compensate half of that reserve so the caption is centred
                // against the complete control rather than only its content area.
                leftPadding: 20
                rightPadding: 0
                text: qsTr("插值：") + interpolationBox.currentText
                color: interpolationBox.enabled ? "#d9e4ec" : "#71818d"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            background: Rectangle { color: interpolationBox.enabled ? "#223542" : "#18242d"; radius: 3; border.color: interpolationBox.enabled ? "#365467" : "#314252" }
        }

        ComboBox {
            id: cursorModeBox
            Layout.fillWidth: true
            implicitHeight: 32
            model: [qsTr("关闭"), qsTr("垂直光标"), qsTr("水平光标"), qsTr("水平-垂直光标")]
            currentIndex: ({ off: 0, time: 1, voltage: 2, both: 3 })[root.cursorMode]
            onActivated: root.cursorModeRequested(["off", "time", "voltage", "both"][currentIndex])
            contentItem: Text {
                leftPadding: 20
                rightPadding: 0
                text: qsTr("光标：") + cursorModeBox.currentText
                color: "#d9e4ec"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            background: Rectangle { color: "#223542"; radius: 3; border.color: "#365467" }
        }

        AppButton {
            Layout.fillWidth: true
            implicitHeight: 32
            text: qsTr("测量任务")
            onClicked: root.measurementPanelRequested()
        }

        Item { Layout.fillHeight: true }

    }

    Dialog {
        id: triggerDialog
        parent: Overlay.overlay
        anchors.centerIn: Overlay.overlay
        width: Math.min(360, Overlay.overlay.width - 48)
        height: 360
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        padding: 0
        background: Rectangle { color: "#15212c"; radius: 6; border.color: "#3b6172" }
        header: Rectangle {
            implicitHeight: 42; color: "#1b303d"; radius: 6
            Label { anchors.left: parent.left; anchors.leftMargin: 14; anchors.verticalCenter: parent.verticalCenter; text: qsTr("边沿触发设置"); color: "#d9e4ec"; font.bold: true; font.pixelSize: 15 }
            AppButton { anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; text: "×"; implicitWidth: 28; implicitHeight: 26; onClicked: triggerDialog.close() }
        }
        contentItem: Rectangle {
            color: "transparent"
            ColumnLayout {
                anchors.fill: parent; anchors.margins: 14; spacing: 10
                AppButton {
                Layout.fillWidth: true; implicitHeight: 34
                text: root.triggerEnabled ? qsTr("关闭触发") : qsTr("开启触发")
                selected: root.triggerEnabled; primary: root.triggerEnabled
                onClicked: root.edgeTriggerEnabledRequested(!root.triggerEnabled)
            }
                Label { text: qsTr("触发源"); color: "#8fa3b4"; font.pixelSize: 12 }
                ComboBox {
                id: popupChannel; Layout.fillWidth: true; implicitHeight: 32
                model: root.triggerableChannelIndexes
                currentIndex: Math.max(0, root.triggerableChannelIndexes.indexOf(root.triggerChannelIndex))
                onActivated: root.edgeTriggerRequested(root.triggerableChannelIndexes[currentIndex], root.triggerEdge, root.triggerLevel, root.triggerHysteresis, root.triggerMode)
                delegate: ItemDelegate { required property var modelData; width: popupChannel.width; text: "CH" + (modelData + 1) }
                contentItem: Text { leftPadding: 10; text: root.triggerableChannelIndexes.length ? root.channelStore.channel(root.triggerableChannelIndexes[popupChannel.currentIndex]).name : "-"; color: "#d9e4ec"; verticalAlignment: Text.AlignVCenter }
                background: Rectangle { color: "#223542"; radius: 3; border.color: "#365467" }
            }
                RowLayout {
                Layout.fillWidth: true
                ComboBox {
                    id: popupEdge; Layout.fillWidth: true; implicitHeight: 32; model: [qsTr("上升沿"), qsTr("下降沿"), qsTr("双边沿")]; currentIndex: ({ rising: 0, falling: 1, both: 2 })[root.triggerEdge]
                    onActivated: root.edgeTriggerRequested(root.triggerChannelIndex, ["rising", "falling", "both"][currentIndex], root.triggerLevel, root.triggerHysteresis, root.triggerMode)
                    contentItem: Text { leftPadding: 8; text: popupEdge.currentText; color: "#d9e4ec"; verticalAlignment: Text.AlignVCenter }
                    background: Rectangle { color: "#223542"; radius: 3; border.color: "#365467" }
                }
                ComboBox {
                    id: popupMode; Layout.fillWidth: true; implicitHeight: 32; model: [qsTr("自动"), qsTr("正常"), qsTr("单次")]; currentIndex: ({ auto: 0, normal: 1, single: 2 })[root.triggerMode]
                    onActivated: root.edgeTriggerRequested(root.triggerChannelIndex, root.triggerEdge, root.triggerLevel, root.triggerHysteresis, ["auto", "normal", "single"][currentIndex])
                    contentItem: Text { leftPadding: 8; text: popupMode.currentText; color: "#d9e4ec"; verticalAlignment: Text.AlignVCenter }
                    background: Rectangle { color: "#223542"; radius: 3; border.color: "#365467" }
                }
            }
                Label { text: qsTr("电平、迟滞与位置"); color: "#8fa3b4"; font.pixelSize: 12 }
                RowLayout {
                Layout.fillWidth: true
                TextField {
                    id: popupLevel; Layout.fillWidth: true; implicitHeight: 32
                    text: root.num(root.triggerLevel); selectByMouse: true; validator: DoubleValidator { bottom: -10; top: 10; decimals: 4 }
                    onEditingFinished: { const value = Number(text); if (isFinite(value)) root.edgeTriggerRequested(root.triggerChannelIndex, root.triggerEdge, value, root.triggerHysteresis, root.triggerMode) }
                    color: "#d9e4ec"; horizontalAlignment: Text.AlignHCenter
                    background: Rectangle { color: "#223542"; radius: 3; border.color: popupLevel.activeFocus ? "#35a990" : "#365467" }
                }
                TextField {
                    id: popupHysteresis; Layout.fillWidth: true; implicitHeight: 32
                    text: root.num(root.triggerHysteresis); selectByMouse: true; validator: DoubleValidator { bottom: .001; top: 10; decimals: 4 }
                    onEditingFinished: { const value = Number(text); if (isFinite(value) && value > 0) root.edgeTriggerRequested(root.triggerChannelIndex, root.triggerEdge, root.triggerLevel, value, root.triggerMode) }
                    color: "#d9e4ec"; horizontalAlignment: Text.AlignHCenter
                    background: Rectangle { color: "#223542"; radius: 3; border.color: popupHysteresis.activeFocus ? "#35a990" : "#365467" }
                }
                ComboBox {
                    id: popupPosition; Layout.fillWidth: true; implicitHeight: 32; model: [.2, .4, .5, .6, .8]; currentIndex: model.indexOf(root.triggerPosition)
                    onActivated: root.triggerPositionRequested(Number(currentValue))
                    contentItem: Text { leftPadding: 7; text: Math.round(popupPosition.currentValue * 100) + "%"; color: "#d9e4ec"; verticalAlignment: Text.AlignVCenter }
                    background: Rectangle { color: "#223542"; radius: 3; border.color: "#365467" }
                }
            }
                RowLayout {
                Layout.fillWidth: true
                Rectangle { implicitHeight: 24; Layout.fillWidth: true; radius: 12; color: root.triggerEnabled ? (root.triggerSampleIndex >= 0 ? "#163b35" : "#26372b") : "#27313a"; border.color: root.triggerEnabled ? "#35a990" : "#526372"; Label { anchors.centerIn: parent; text: !root.triggerEnabled ? qsTr("触发已关闭") : root.triggerSampleIndex >= 0 ? qsTr("已触发") : qsTr("等待触发"); color: root.triggerEnabled ? "#c9f3e5" : "#9aaab5"; font.pixelSize: 12; font.bold: true } }
                AppButton { text: qsTr("重新布防"); enabled: root.triggerEnabled; implicitHeight: 30; onClicked: root.edgeTriggerRearmRequested() }
                }
            }
        }
    }
}
