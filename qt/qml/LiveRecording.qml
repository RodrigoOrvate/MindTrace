// qml/LiveRecording.qml
// Placeholder para o módulo de gravação e análise (DeepLabCut).

import QtQuick 2.12
import QtQuick.Controls 2.12

Item {
    id: root

    Rectangle { anchors.fill: parent; color: "#0f0f1a" }

    Column {
        anchors.centerIn: parent
        spacing: 16

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "🎬"
            font.pixelSize: 48
            opacity: 0.25
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Módulo de Gravação e Análise (DeepLabCut) — Em breve"
            color: "#555577"
            font.pixelSize: 14
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
