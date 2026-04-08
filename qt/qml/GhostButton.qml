// qml/GhostButton.qml
import QtQuick
import QtQuick.Controls

Button {
    background: Rectangle {
        radius: 7; color: parent.hovered ? "#16162e" : "transparent"
        border.color: parent.hovered ? "#ab3d4c" : "#2d2d4a"; border.width: 1
        Behavior on color        { ColorAnimation { duration: 150 } }
        Behavior on border.color { ColorAnimation { duration: 150 } }
    }
    contentItem: Text {
        text: parent.text
        color: parent.hovered ? "#e8e8f0" : "#8888aa"
        font.pixelSize: 12
        verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter
        Behavior on color { ColorAnimation { duration: 150 } }
    }
    leftPadding: 18; rightPadding: 18; topPadding: 7; bottomPadding: 7
}
