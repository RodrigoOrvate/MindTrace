// qml/LandingCard.qml
// Card gigante da tela inicial (Criar / Procurar).

import QtQuick 2.12
import QtQuick.Layouts 1.3
import QtGraphicalEffects 1.0

Item {
    id: cardRoot

    property string icon:        ""
    property string title:       ""
    property string description: ""
    property color  accentColor: "#ab3d4c"

    signal clicked()

    width:  300
    height: 340

    layer.enabled: true
    layer.effect: DropShadow {
        horizontalOffset: 0
        verticalOffset:   hoverArea.containsMouse ? 14 : 6
        radius:           hoverArea.containsMouse ? 40 : 16
        samples: 33
        color:   hoverArea.containsMouse ? Qt.rgba(
                     cardRoot.accentColor.r,
                     cardRoot.accentColor.g,
                     cardRoot.accentColor.b, 0.45) : "#60000000"
        Behavior on radius        { NumberAnimation { duration: 220 } }
        Behavior on verticalOffset { NumberAnimation { duration: 220 } }
    }

    transform: Scale {
        origin.x: cardRoot.width  / 2
        origin.y: cardRoot.height / 2
        xScale: hoverArea.containsMouse ? 1.04 : 1.0
        yScale: hoverArea.containsMouse ? 1.04 : 1.0
        Behavior on xScale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on yScale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    }

    Rectangle {
        anchors.fill: parent
        radius: 22
        color:        hoverArea.containsMouse ? "#1e1e38" : "#1a1a2e"
        border.color: hoverArea.containsMouse ? cardRoot.accentColor : "#2d2d4a"
        border.width: hoverArea.containsMouse ? 2 : 1

        Behavior on color        { ColorAnimation { duration: 200 } }
        Behavior on border.color { ColorAnimation { duration: 200 } }

        ColumnLayout {
            anchors { fill: parent; margins: 36 }
            spacing: 0

            // Ícone grande
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: cardRoot.icon
                font.pixelSize: 64
                color: cardRoot.accentColor

                Behavior on font.pixelSize { NumberAnimation { duration: 180 } }
            }

            Item { Layout.preferredHeight: 24 }

            // Título
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: cardRoot.title
                color: "#e8e8f0"
                font.pixelSize: 24
                font.weight: Font.Bold
                horizontalAlignment: Text.AlignHCenter
            }

            Item { Layout.preferredHeight: 16 }

            // Descrição
            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true
                text: cardRoot.description
                color: "#8888aa"
                font.pixelSize: 12
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }

            Item { Layout.fillHeight: true }

            // Barra de destaque na base
            Rectangle {
                Layout.fillWidth: true
                height: 4
                radius: 2
                color: hoverArea.containsMouse ? cardRoot.accentColor : "#2d2d4a"
                Behavior on color { ColorAnimation { duration: 200 } }
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
