import QtQuick
import QtQuick.Controls.Basic

Button {
    id: control

    property color fillColor: "#223542"
    property color selectedFillColor: "#235d67"
    property color borderColor: "#365467"
    property color selectedBorderColor: "#2b8990"
    property color textColor: "#d9e4ec"
    property color selectedTextColor: "#ffffff"
    property bool primary: false
    property bool selected: false
    property int feedbackDuration: 120
    property int textAlignment: Text.AlignHCenter

    implicitHeight: 34
    hoverEnabled: true
    transformOrigin: Item.Center
    scale: enabled && down ? 0.975 : 1.0

    Behavior on scale {
        NumberAnimation { duration: control.feedbackDuration; easing.type: Easing.OutQuad }
    }

    contentItem: Text {
        leftPadding: control.leftPadding
        rightPadding: control.rightPadding
        text: control.text
        color: control.selected ? control.selectedTextColor : !control.enabled ? "#71818d" : control.textColor
        font.pixelSize: 13
        font.bold: control.primary || control.selected
        horizontalAlignment: control.textAlignment
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideNone
    }

    background: Rectangle {
        radius: 4
        color: control.selected ? control.selectedFillColor : !control.enabled ? "#29333a" : control.fillColor
        border.color: control.selected || control.primary ? control.selectedBorderColor : !control.enabled ? "#3a4650" : control.borderColor
        border.width: 1

        Behavior on color {
            ColorAnimation { duration: control.feedbackDuration }
        }
        Behavior on border.color {
            ColorAnimation { duration: control.feedbackDuration }
        }

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "#ffffff"
            opacity: !control.enabled ? 0 : control.down ? 0.14 : control.hovered ? 0.07 : 0

            Behavior on opacity {
                NumberAnimation { duration: control.feedbackDuration }
            }
        }
    }
}
