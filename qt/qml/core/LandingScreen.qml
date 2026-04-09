// qml/LandingScreen.qml
// Tela inicial do MindTrace: dois botões gigantes — Criar e Procurar.

import QtQuick
import QtQuick.Layouts
import "Theme"

Item {
    id: root

    signal createSelected()
    signal searchSelected()

    Rectangle { 
        anchors.fill: parent
        color: ThemeManager.background
        Behavior on color { ColorAnimation { duration: 200 } }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 48
        spacing: 0

        // ── Header ───────────────────────────────────────────────────────
        ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 8

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "MindTrace"
                color: ThemeManager.textPrimary
                font.pixelSize: 36
                font.weight: Font.Bold
                Behavior on color { ColorAnimation { duration: 150 } }
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "Sistema de análise comportamental"
                color: ThemeManager.textSecondary
                font.pixelSize: 13
                Behavior on color { ColorAnimation { duration: 150 } }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 24
            height: 1
            color: ThemeManager.border
            Behavior on color { ColorAnimation { duration: 200 } }
        }

        Item { Layout.fillHeight: true; Layout.minimumHeight: 32 }

        // ── Dois botões gigantes ─────────────────────────────────────────
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 32

            // ── Card Criar ───────────────────────────────────────────────
            LandingCard {
                icon:        "＋"
                title:       "Criar"
                description: "Configure um novo experimento:\nescolha o aparato, a arena e defina\nos animais e pares de objetos."
                accentColor: "#ab3d4c"
                onClicked:   root.createSelected()
            }

            // ── Card Procurar ────────────────────────────────────────────
            LandingCard {
                icon:        "🔍"
                title:       "Procurar"
                description: "Acesse experimentos já cadastrados:\npesquise pelo nome e abra\na planilha associada."
                accentColor: "#3d7aab"
                onClicked:   root.searchSelected()
            }
        }

        Item { Layout.fillHeight: true; Layout.minimumHeight: 32 }

        // ── Footer ───────────────────────────────────────────────────────
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "UFRN — Laboratório de Neurobiologia da Memória"
            color: ThemeManager.textTertiary
            font.pixelSize: 11
            Behavior on color { ColorAnimation { duration: 150 } }
        }
    }
}
