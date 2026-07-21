pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Rectangle {
    id: root
    required property string currentPage
    signal pageRequested(string page)
    color: "#15212c"
    border.color: "#314252"

    function pageTitle(page) {
        // 保持与主页面一致的页签标题映射。
        const titles = {
            "realtime": qsTr("\u5b9e\u65f6\u6ce2\u5f62"),
            "playback": qsTr("\u5386\u53f2\u56de\u653e"),
            "channels": qsTr("\u901a\u9053\u8bbe\u7f6e"),
            "acquisition": qsTr("\u91c7\u96c6\u8bbe\u7f6e"),
            "recording": qsTr("\u6570\u636e\u5f55\u5236"),
            "system": qsTr("\u7cfb\u7edf\u72b6\u6001")
        }
        return titles[page] || page
    }

    component NavigationButton: AppButton {
        id: button
        required property string page
        required property string title
        text: title
        implicitHeight: 42
        Layout.fillWidth: true
        leftPadding: 18
        selected: root.currentPage === button.page
        fillColor: "transparent"
        selectedFillColor: "#235d67"
        borderColor: "transparent"
        selectedBorderColor: "#2b8990"
        textColor: "#8fa3b4"
        selectedTextColor: "#ffffff"
        textAlignment: Text.AlignLeft

        onClicked: root.pageRequested(button.page)
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 7
        Label {
            text: qsTr("\u529f\u80fd\u5bfc\u822a")
            color: "#8fa3b4"
            font.pixelSize: 12
            font.bold: true
            Layout.leftMargin: 8
            Layout.bottomMargin: 7
        }

        NavigationButton { page: "realtime"; title: qsTr("\u5b9e\u65f6\u6ce2\u5f62") }
        NavigationButton { page: "playback"; title: qsTr("\u5386\u53f2\u56de\u653e") }
        NavigationButton { page: "channels"; title: qsTr("\u901a\u9053\u8bbe\u7f6e") }
        NavigationButton { page: "acquisition"; title: qsTr("\u91c7\u96c6\u8bbe\u7f6e") }
        NavigationButton { page: "recording"; title: qsTr("\u6570\u636e\u5f55\u5236") }
        NavigationButton { page: "system"; title: qsTr("\u7cfb\u7edf\u72b6\u6001") }

        Item {
            Layout.fillHeight: true
        }

        Label {
            text: qsTr("\u5f53\u524d\u9875\u9762:") + root.pageTitle(root.currentPage)
            color: "#8fa3b4"
            font.pixelSize: 12
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            Layout.margins: 8
        }
    }
}
