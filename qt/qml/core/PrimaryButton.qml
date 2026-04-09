import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import "Theme"

Button {
    id: control
    scale: pressed ? 0.95 : (hovered ? 1.03 : 1.0)
    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

    background: Item {
        Rectangle {
            id: bgRect
            anchors.fill: parent
            radius: 8
            color: control.enabled ? (control.hovered ? ThemeManager.accentHover : ThemeManager.accent) : ThemeManager.border
            border.color: control.hovered ? ThemeManager.accentHover : "transparent"
            border.width: control.hovered ? 1 : 0
            Behavior on color { ColorAnimation { duration: 150 } }
            Behavior on border.color { ColorAnimation { duration: 150 } }
        }
        
        MultiEffect {
            source: bgRect
            anchors.fill: bgRect
            shadowEnabled: control.hovered && control.enabled
            shadowColor: ThemeManager.accentHover
            shadowBlur: 0.6
            opacity: control.hovered && control.enabled ? 0.7 : 0.0
            Behavior on opacity { NumberAnimation { duration: 200 } }
        }
    }
    
    contentItem: Text {
        text: control.text
        color: control.enabled ? ThemeManager.buttonText : ThemeManager.textSecondary
        font.pixelSize: 13
        font.weight: Font.Bold
        verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter
        Behavior on color { ColorAnimation { duration: 150 } }
    }
    
    leftPadding: 16; rightPadding: 16; topPadding: 8; bottomPadding: 8
}
