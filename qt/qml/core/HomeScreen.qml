import QtQuick
import QtQuick.Layouts
import "../nor"
import "Theme"

Item {
    id: root

    signal norSelected()
    signal caSelected()
    signal ccSelected()
    signal eiSelected()
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

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            GhostButton {
                text: LanguageManager.tr3("<- Voltar", "<- Back", "<- Volver")
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
                text: LanguageManager.tr3("Aparatos", "Apparatus", "Aparatos")
                color: ThemeManager.textPrimary
                font.pixelSize: 30
                font.weight: Font.Bold
                Behavior on color { ColorAnimation { duration: 150 } }
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: LanguageManager.tr3(
                    "Selecione o paradigma experimental",
                    "Select the experimental paradigm",
                    "Seleccione el paradigma experimental"
                )
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

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 14

            NORCard {
                width: 160; height: 250
                icon: "🧠"
                title: LanguageManager.tr3("Reconhecimento\nde Objetos", "Object\nRecognition", "Reconocimiento\nde Objetos")
                description: LanguageManager.tr3(
                    "Paradigma NOR dependente ou\nindependente de contexto",
                    "NOR paradigm with context\ndependent or independent mode",
                    "Paradigma NOR dependiente\no independiente del contexto"
                )
                onClicked: root.norSelected()
            }

            NORCard {
                width: 160; height: 250
                icon: "🐁"
                title: LanguageManager.tr3("Campo\nAberto", "Open\nField", "Campo\nAbierto")
                description: LanguageManager.tr3(
                    "Exploracao em campo aberto\ne habituacao ao aparato",
                    "Open field exploration\nand habituation",
                    "Exploracion en campo abierto\ny habituacion al aparato"
                )
                onClicked: root.caSelected()
            }

            NORCard {
                width: 160; height: 250
                icon: "🧩"
                title: LanguageManager.tr3("Comportamento\nComplexo", "Complex\nBehavior", "Comportamiento\nComplejo")
                description: LanguageManager.tr3(
                    "Labirinto, sociabilidade\ne paradigmas avancados",
                    "Maze, sociability\nand advanced paradigms",
                    "Laberinto, sociabilidad\ny paradigmas avanzados"
                )
                onClicked: root.ccSelected()
            }

            NORCard {
                width: 160; height: 250
                icon: "⚡"
                title: LanguageManager.tr3("Esquiva\nInibitoria", "Inhibitory\nAvoidance", "Evitacion\nInhibitoria")
                description: LanguageManager.tr3(
                    "Memoria aversiva passiva\n(step-through)",
                    "Passive aversive memory\n(step-through)",
                    "Memoria aversiva pasiva\n(step-through)"
                )
                onClicked: root.eiSelected()
            }

            NORCard {
                width: 160; height: 250
                icon: "📡"
                title: LanguageManager.tr3("Registro\nEletrofisiologico", "Electrophysiology\nRecording", "Registro\nElectrofisiologico")
                description: LanguageManager.tr3(
                    "Canais, taxa de amostragem\ne sincronizacao com video",
                    "Channels, sampling rate\nand video synchronization",
                    "Canales, tasa de muestreo\ny sincronizacion con video"
                )
                locked: true
            }
        }

        Item { Layout.fillHeight: true; Layout.minimumHeight: 20 }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: LanguageManager.tr3("Passo 1  -  Escolha do Aparato", "Step 1  -  Choose Apparatus", "Paso 1  -  Elegir Aparato")
            color: "#8888aa"
            font.pixelSize: 11
        }
    }
}
