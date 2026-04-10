// qml/HomeScreen.qml
// Tela de seleção de aparato — intermediária após LandingScreen.

import QtQuick
import QtQuick.Layouts
import "../nor"
import "Theme"

Item {
    id: root

    signal norSelected()
    signal caSelected()
    signal backRequested()

    Rectangle { 
        anchors.fill: parent
        color: ThemeManager.background
        Behavior on color { ColorAnimation { duration: 200 } }
    }

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
                color: ThemeManager.textPrimary
                font.pixelSize: 30
                font.weight: Font.Bold
                Behavior on color { ColorAnimation { duration: 150 } }
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "Selecione o paradigma experimental"
                color: ThemeManager.textSecondary
                font.pixelSize: 13
                Behavior on color { ColorAnimation { duration: 150 } }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 16
            height: 1
            color: ThemeManager.border
            Behavior on color { ColorAnimation { duration: 200 } }
        }

        Item { Layout.fillHeight: true; Layout.minimumHeight: 20 }

        // ── Cards ────────────────────────────────────────────────────────
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 14

            NORCard {
                width: 160; height: 250
                icon: "🧠"
                title: "Reconhecimento\nde Objetos"
                description: "Paradigma NOR dependente ou\nindependente de contexto"
                onClicked: root.norSelected()
            }

            NORCard {
                width: 160; height: 250
                icon: "🐀"
                title: "Campo\nAberto"
                description: "Exploração em campo aberto\ne habituação ao aparato"
                onClicked: root.caSelected()
            }

            NORCard {
                width: 160; height: 250
                icon: "🧩"
                title: "Comportamento\nComplexo"
                description: "Labirinto, sociabilidade\ne paradigmas avançados"
                locked: true
            }

            NORCard {
                width: 160; height: 250
                icon: "⚡"
                title: "Esquiva\nInibitória"
                description: "Memória aversiva passiva\n(step-through)"
                locked: true
            }

            NORCard {
                width: 160; height: 250
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
