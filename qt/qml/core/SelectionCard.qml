// qml/SelectionCard.qml
// Card de seleção reutilizável (arenas, pares de objetos, etc.)
// Menor que NORCard; indica seleção com borda accent + check.

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

Item {
    id: cardRoot

    property string icon:        ""
    property string title:       ""
    property string description: ""
    property string badge:       ""       // label de badge opcional (ex.: "Treino")
    property color  badgeColor:  "#2d2d4a"
    property color  badgeText:   "#8888aa"
    property string events:      ""       // linha de eventos (ex.: "OBJA  •  OBJB")
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
        shadowColor:            cardRoot.selected ? "#80ab3d4c" : "#50000000"
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
        color:        cardRoot.selected ? "#222240"
                    : hoverArea.containsMouse ? "#1e1e38" : "#1a1a2e"
        border.color: cardRoot.selected ? "#ab3d4c" : "#2d2d4a"
        border.width: cardRoot.selected ? 2 : 1

        Behavior on color        { ColorAnimation { duration: 180 } }
        Behavior on border.color { ColorAnimation { duration: 180 } }

        ColumnLayout {
            anchors { fill: parent; margins: 18 }
            spacing: 0

            // Ícone
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: cardRoot.icon
                font.pixelSize: 32
            }

            Item { Layout.preferredHeight: 10 }

            // Título
            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true
                text: cardRoot.title
                color: "#e8e8f0"
                font.pixelSize: 13
                font.weight: Font.Bold
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }

            Item { Layout.preferredHeight: 6 }

            // Descrição
            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true
                text: cardRoot.description
                color: "#8888aa"
                font.pixelSize: 10
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }

            Item { Layout.fillHeight: true }

            // Badge de fase (opcional)
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                visible: cardRoot.badge !== ""
                radius: 4
                color: cardRoot.badgeColor
                implicitWidth: badgeLabel.implicitWidth + 12
                implicitHeight: 18
                Text {
                    id: badgeLabel
                    anchors.centerIn: parent
                    text: cardRoot.badge
                    color: cardRoot.badgeText
                    font.pixelSize: 10
                    font.weight: Font.Bold
                }
            }

            // Linha de eventos (opcional)
            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true
                visible: cardRoot.events !== ""
                text: cardRoot.events
                color: cardRoot.selected ? "#ab3d4c" : "#555577"
                font.pixelSize: 10
                font.weight: Font.Bold
                horizontalAlignment: Text.AlignHCenter
                Behavior on color { ColorAnimation { duration: 180 } }
            }

            Item { Layout.preferredHeight: 4 }
        }

        // Check de seleção (canto superior direito)
        Rectangle {
            anchors { top: parent.top; right: parent.right; margins: 8 }
            width: 18; height: 18; radius: 9
            color: cardRoot.selected ? "#ab3d4c" : "transparent"
            border.color: cardRoot.selected ? "#ab3d4c" : "#3a3a5c"
            border.width: 1.5
            opacity: (cardRoot.selected || hoverArea.containsMouse) ? 1.0 : 0.0
            Behavior on color   { ColorAnimation { duration: 150 } }
            Behavior on opacity { NumberAnimation { duration: 150 } }

            Text {
                anchors.centerIn: parent
                text: "✓"
                color: "#e8e8f0"
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
