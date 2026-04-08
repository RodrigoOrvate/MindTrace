// qml/NORCard.qml
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

Item {
    id: cardRoot

    property string icon: ""
    property string title: ""
    property string description: ""
    property bool   locked: false
    signal clicked()

    width: 230
    height: 290

    // Sombra dinâmica — apagada quando locked
    layer.enabled: true
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowHorizontalOffset: 0
        shadowVerticalOffset:   (!cardRoot.locked && cardRoot.hovered) ? 10 : 5
        shadowBlur:             (!cardRoot.locked && cardRoot.hovered) ? 0.8 : 0.45
        shadowColor:            (!cardRoot.locked && cardRoot.hovered) ? "#80ab3d4c" : "#60000000"
        Behavior on shadowBlur          { NumberAnimation { duration: 220 } }
        Behavior on shadowVerticalOffset { NumberAnimation { duration: 220 } }
    }

    property bool hovered: false

    // Crescimento suave ao hover (desativado quando locked)
    transform: Scale {
        origin.x: cardRoot.width  / 2
        origin.y: cardRoot.height / 2
        xScale: (!cardRoot.locked && cardRoot.hovered) ? 1.04 : 1.0
        yScale: (!cardRoot.locked && cardRoot.hovered) ? 1.04 : 1.0

        Behavior on xScale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on yScale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    }

    // Card body
    Rectangle {
        anchors.fill: parent
        radius: 18
        color: (!cardRoot.locked && cardRoot.hovered) ? "#222240" : "#1a1a2e"
        border.color: (!cardRoot.locked && cardRoot.hovered) ? "#ab3d4c" : "#2d2d4a"
        border.width: 1.5

        Behavior on color        { ColorAnimation { duration: 200 } }
        Behavior on border.color { ColorAnimation { duration: 200 } }

        ColumnLayout {
            anchors { fill: parent; margins: 26 }
            spacing: 0

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: cardRoot.icon
                font.pixelSize: 44
                color: cardRoot.locked ? "#555577" : "#ab3d4c"
            }

            Item { Layout.preferredHeight: 18 }

            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true
                text: cardRoot.title
                color: cardRoot.locked ? "#555577" : "#e8e8f0"
                font.pixelSize: 15
                font.weight: Font.Bold
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }

            Item { Layout.preferredHeight: 12 }

            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true
                text: cardRoot.description
                color: cardRoot.locked ? "#444466" : "#8888aa"
                font.pixelSize: 11
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }

            Item { Layout.fillHeight: true }

            Rectangle {
                Layout.fillWidth: true
                height: 3
                radius: 2
                color: cardRoot.locked ? "#2d2d4a" : "#8a2e3b"
            }
        }

        // Overlay "Em breve"
        Rectangle {
            anchors.fill: parent
            radius: 18
            color: "#b20f0f1a"
            visible: cardRoot.locked

            Column {
                anchors.centerIn: parent
                spacing: 6

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "🔒"
                    font.pixelSize: 20
                    opacity: 0.5
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Em breve"
                    color: "#666688"
                    font.pixelSize: 11
                }
            }
        }
    }

    // Área de interação — desativada quando locked
    MouseArea {
        anchors.fill: parent
        enabled: !cardRoot.locked
        hoverEnabled: !cardRoot.locked
        cursorShape: cardRoot.locked ? Qt.ArrowCursor : Qt.PointingHandCursor

        onEntered: cardRoot.hovered = true
        onExited:  cardRoot.hovered = false
        onClicked: cardRoot.clicked()
    }
}
