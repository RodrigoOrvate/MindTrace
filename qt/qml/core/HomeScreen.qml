// qml/HomeScreen.qml
// Tela de seleção de aparato — intermediária após LandingScreen.

import QtQuick
import QtQuick.Layouts
import "../nor"

Item {
    id: root

    signal norSelected()
    signal backRequested()

    Rectangle { anchors.fill: parent; color: "#0f0f1a" }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 40
        spacing: 0

        // ── Header ───────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            GhostButton {
                text: "← Voltar"
                onClicked: root.backRequested()
            }

            Item { Layout.fillWidth: true }
        }

        Item { Layout.preferredHeight: 12 }

        ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 6

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "Aparatos"
                color: "#e8e8f0"
                font.pixelSize: 30
                font.weight: Font.Bold
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "Selecione o paradigma experimental"
                color: "#8888aa"
                font.pixelSize: 13
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 16
            height: 1
            color: "#2d2d4a"
        }

        Item { Layout.fillHeight: true; Layout.minimumHeight: 20 }

        // ── Cards ────────────────────────────────────────────────────────
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 20

            NORCard {
                width: 210; height: 270
                icon: "🧠"
                title: "Reconhecimento\nde Objetos"
                description: "Paradigma NOR dependente ou\nindependente de contexto"
                onClicked: root.norSelected()
            }

            NORCard {
                width: 210; height: 270
                icon: "🐀"
                title: "Campo Aberto\n/ Habituação"
                description: "Exploração em campo aberto\ne habituação ao aparato"
                locked: true
            }

            NORCard {
                width: 210; height: 270
                icon: "⚡"
                title: "Esquiva\nInibitória"
                description: "Memória aversiva passiva\n(step-through)"
                locked: true
            }

            NORCard {
                width: 210; height: 270
                icon: "📡"
                title: "Registro\nEletrofisiológico"
                description: "Canais, taxa de amostragem\ne sincronização com vídeo"
                locked: true
            }
        }

        Item { Layout.fillHeight: true; Layout.minimumHeight: 20 }

        // ── Footer ───────────────────────────────────────────────────────
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "Passo 1  —  Escolha do Aparato"
            color: "#8888aa"
            font.pixelSize: 11
        }
    }
}
