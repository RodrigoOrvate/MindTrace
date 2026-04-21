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
                text: LanguageManager.tr3(
                    "Sistema de analise comportamental",
                    "Behavioral analysis system",
                    "Sistema de analisis conductual"
                )
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

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 32

            LandingCard {
                icon: "+"
                title: LanguageManager.tr3("Criar", "Create", "Crear")
                description: LanguageManager.tr3(
                    "Configure um novo experimento:\nescolha o aparato, a arena e defina\nos animais e pares de objetos.",
                    "Set up a new experiment:\nchoose apparatus and arena,\nthen define animals and object pairs.",
                    "Configure un nuevo experimento:\nelija aparato y arena,\ny defina animales y pares de objetos."
                )
                accentColor: "#ab3d4c"
                onClicked: root.createSelected()
            }

            LandingCard {
                icon: "🔍"
                title: LanguageManager.tr3("Procurar", "Search", "Buscar")
                description: LanguageManager.tr3(
                    "Acesse experimentos ja cadastrados:\npesquise pelo nome e abra\na planilha associada.",
                    "Open existing experiments:\nsearch by name and open\nthe related spreadsheet.",
                    "Acceda a experimentos ya creados:\nbusque por nombre y abra\nla hoja asociada."
                )
                accentColor: "#3d7aab"
                onClicked: root.searchSelected()
            }
        }

        Item { Layout.fillHeight: true; Layout.minimumHeight: 32 }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: LanguageManager.tr3(
                "UFRN - Laboratorio de Neurobiologia da Memoria",
                "UFRN - Memory Neurobiology Laboratory",
                "UFRN - Laboratorio de Neurobiologia de la Memoria"
            )
            color: ThemeManager.textTertiary
            font.pixelSize: 11
            Behavior on color { ColorAnimation { duration: 150 } }
        }
    }
}
