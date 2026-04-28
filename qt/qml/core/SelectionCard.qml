// qml/SelectionCard.qml
// Reusable selection card (arenas, object pairs, etc.)
// Smaller than NORCard; indicates selection with accent border + check mark.

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import "Theme"

Item {
    id: cardRoot

    property string icon:        ""
    property string title:       ""
    property string description: ""
    property string badge:       ""       // optional badge label (e.g. "Training")
    property color  badgeColor:  ThemeManager.border
    property color  badgeText:   ThemeManager.textSecondary
    property string events:      ""       // event row text (e.g. "OBJA  u2022  OBJB")
    property bool   selected:    false

    signal clicked()

    width:  180
    height: 200

    layer.enabled: true
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowHorizontalOffset: 0
        shadowVerticalOffset:   (cardRoot.selected || hoverArea.containsMouse) ? 8 : 4
        shadowBlur:             (cardRoot.selected || hoverArea.containsMouse) ? 0.7 : 0.35
        shadowColor:            cardRoot.selected ? Qt.rgba(171, 61, 76, 0.5) : Qt.rgba(0, 0, 0, 0.3125)
        Behavior on shadowBlur          { NumberAnimation { duration: 200 } }
        Behavior on shadowVerticalOffset { NumberAnimation { duration: 200 } }
    }

    transform: Scale {
        origin.x: cardRoot.width  / 2
        origin.y: cardRoot.height / 2
        xScale: (cardRoot.selected || hoverArea.containsMouse) ? 1.03 : 1.0
        yScale: (cardRoot.selected || hoverArea.containsMouse) ? 1.03 : 1.0
        Behavior on xScale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on yScale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    }

    Rectangle {
        anchors.fill: parent
        radius: 14
        color:        cardRoot.selected ? ThemeManager.surfaceAlt
                    : hoverArea.containsMouse ? ThemeManager.surface : ThemeManager.surface
        border.color: cardRoot.selected ? ThemeManager.accent : ThemeManager.border
        border.width: cardRoot.selected ? 2 : 1

        Behavior on color        { ColorAnimation { duration: 180 } }
        Behavior on border.color { ColorAnimation { duration: 180 } }

        ColumnLayout {
            anchors { fill: parent; margins: 18 }
            spacing: 0

            // Icon
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: cardRoot.icon
                font.pixelSize: 32
            }

            Item { Layout.preferredHeight: 10 }

            // Title
            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true
                text: cardRoot.title
                color: ThemeManager.textPrimary
                font.pixelSize: 13
                font.weight: Font.Bold
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            Item { Layout.preferredHeight: 6 }

            // Description
            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true
                text: cardRoot.description
                color: ThemeManager.textSecondary
                font.pixelSize: 10
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            Item { Layout.fillHeight: true }

            // Phase badge (optional)
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                visible: cardRoot.badge !== ""
                radius: 4
                color: cardRoot.badgeColor
                implicitWidth: badgeLabel.implicitWidth + 12
                implicitHeight: 18
                Behavior on color { ColorAnimation { duration: 150 } }
                Text {
                    id: badgeLabel
                    anchors.centerIn: parent
                    text: cardRoot.badge
                    color: cardRoot.badgeText
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
            }

            // Event row (optional)
            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true
                visible: cardRoot.events !== ""
                text: cardRoot.events
                color: cardRoot.selected ? ThemeManager.accent : ThemeManager.textTertiary
                font.pixelSize: 10
                font.weight: Font.Bold
                horizontalAlignment: Text.AlignHCenter
                Behavior on color { ColorAnimation { duration: 180 } }
            }

            Item { Layout.preferredHeight: 4 }
        }

        // Selection check mark (top-right corner)
        Rectangle {
            anchors { top: parent.top; right: parent.right; margins: 8 }
            width: 18; height: 18; radius: 9
            color: cardRoot.selected ? ThemeManager.accent : "transparent"
            border.color: cardRoot.selected ? ThemeManager.accent : ThemeManager.textTertiary
            border.width: 1.5
            opacity: (cardRoot.selected || hoverArea.containsMouse) ? 1.0 : 0.0
            Behavior on color   { ColorAnimation { duration: 150 } }
            Behavior on border.color { ColorAnimation { duration: 150 } }
            Behavior on opacity { NumberAnimation { duration: 150 } }

            Text {
                anchors.centerIn: parent
                text: "✓"
                color: "#ffffff"
                font.pixelSize: 10
                font.weight: Font.Bold
                visible: cardRoot.selected
            }
        }
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: cardRoot.clicked()
    }
}
