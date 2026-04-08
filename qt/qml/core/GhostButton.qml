import QtQuick
import QtQuick.Controls
import QtQuick.Effects

Button {
    id: control
    scale: pressed ? 0.95 : (hovered ? 1.04 : 1.0)
    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

    background: Item {
        Rectangle {
            id: bgRect
            anchors.fill: parent
            radius: 7
            color: control.hovered ? "#16162e" : "transparent"
            border.color: control.hovered ? "#ab3d4c" : "#2d2d4a"
            border.width: 1
            Behavior on color { ColorAnimation { duration: 150 } }
            Behavior on border.color { ColorAnimation { duration: 150 } }
        }
        
        MultiEffect {
            source: bgRect
            anchors.fill: bgRect
            shadowEnabled: control.hovered
            shadowColor: "#ab3d4c"
            shadowBlur: 0.5
            opacity: control.hovered ? 0.5 : 0.0
            Behavior on opacity { NumberAnimation { duration: 200 } }
        }
    }
    contentItem: Text {
        text: control.text
        color: control.hovered ? "#ffffff" : "#8888aa"
        font.pixelSize: 12
        verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter
        Behavior on color { ColorAnimation { duration: 150 } }
    }
    leftPadding: 18; rightPadding: 18; topPadding: 7; bottomPadding: 7
}
