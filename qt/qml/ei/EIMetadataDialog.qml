// qml/ei/EIMetadataDialog.qml
// Diálogo pós-sessão para Esquiva Inibitória com fases dinâmicas e métricas específicas.

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../core"
import "../core/Theme"
import MindTrace.Backend 1.0

Popup {
    id: root

    anchors.centerIn: parent
    width: 500
    height: 580
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape

    property string experimentName: ""
    property string videoPath: ""
    property int    numCampos: 1
    property bool   includeDrug: true
    property int    extincaoDays: 5
    property bool   hasReactivation: false

    // Métricas recebidas da sessão
    property real   latencia: 0
    property real   tempoPlataf: 0
    property real   tempoGrade: 0
    property int    boutsPlataf: 0
    property int    boutsGrade: 0
    property real   totalDistance: 0
    property real   avgVelocity: 0

    // Gera lista de fases dinamicamente
    readonly property var allPhases: {
        var p = ["TR"]
        for (var i = 1; i <= root.extincaoDays; i++) p.push("E" + i)
        if (root.hasReactivation) p.push("RA")
        p.push("TT")
        return p
    }

    function parseDay(fase) {
        if (fase === "TR") return "1"
        var n = parseInt(fase.substring(1))
        if (!isNaN(n)) return String(1 + n)  // E1→2, E2→3
        if (fase === "RA") return String(1 + root.extincaoDays + 1)
        if (fase === "TT") return root.hasReactivation
            ? String(1 + root.extincaoDays + 2)
            : String(1 + root.extincaoDays + 1)
        return fase
    }

    function getPhaseDescription(fase) {
        if (fase === "TR") return "Treino · Dia 1"
        var n = parseInt(fase.substring(1))
        if (!isNaN(n)) return "Extinção " + n + " · Dia " + (1 + n)
        if (fase === "RA") return "Reativação · Dia " + (1 + root.extincaoDays + 1)
        if (fase === "TT") {
            var dia = root.hasReactivation ? (1 + root.extincaoDays + 2) : (1 + root.extincaoDays + 1)
            return "Teste · Dia " + dia
        }
        return ""
    }

    function doInsert() {
        var animalText = animalField.text.trim()
        if (!animalText) {
            Toast.show("Digite o ID do animal.")
            return
        }

        var fase = phaseField.text.toUpperCase()
        var dia = parseDay(fase)

        var row = [
            videoPath,
            animalText,
            fase,
            dia,
            latencia.toFixed(2),
            tempoPlataf.toFixed(2),
            tempoGrade.toFixed(2),
            boutsPlataf,
            boutsGrade,
            totalDistance.toFixed(2),
            avgVelocity.toFixed(2)
        ]
        if (root.includeDrug) row.push(drugField.text.trim())

        ExperimentManager.insertSessionResult(root.experimentName, [row])
        Toast.show("Sessão salva com sucesso.")
        root.close()
        root.closed()
    }

    background: Rectangle {
        radius: 14
        color: ThemeManager.surface
        Behavior on color { ColorAnimation { duration: 200 } }
        border.color: "#3d7aab"
        border.width: 1
    }

    ColumnLayout {
        anchors { fill: parent; margins: 24 }
        spacing: 12

        // ── Título ───────────────────────────────────────────────────
        Text {
            text: "Dados da Sessão"
            color: ThemeManager.textPrimary
            font.pixelSize: 18
            font.weight: Font.Bold
            Behavior on color { ColorAnimation { duration: 150 } }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } } }

        // ── Scroll Area com campos ────────────────────────────────────
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                width: root.width - 48
                spacing: 14

                // Animal ID
                ColumnLayout {
                    spacing: 6
                    Text {
                        text: "ID DO ANIMAL"
                        color: ThemeManager.textSecondary; font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 1
                    }
                    TextField {
                        id: animalField
                        Layout.fillWidth: true
                        placeholderText: "Ex.: Rato_01"
                        color: ThemeManager.textPrimary; placeholderTextColor: ThemeManager.textSecondary; font.pixelSize: 13
                        leftPadding: 10; rightPadding: 10; topPadding: 8; bottomPadding: 8
                        background: Rectangle {
                            radius: 6; color: ThemeManager.surfaceDim
                            Behavior on color { ColorAnimation { duration: 200 } }
                            border.color: animalField.activeFocus ? "#3d7aab" : ThemeManager.border; border.width: 1
                            Behavior on border.color { ColorAnimation { duration: 150 } }
                        }
                    }
                }

                // Fase (botões dinâmicos)
                ColumnLayout {
                    spacing: 6
                    Text {
                        text: "FASE"
                        color: ThemeManager.textSecondary; font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 1
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Repeater {
                            model: root.allPhases
                            Button {
                                id: phaseBtn
                                text: modelData
                                width: 50
                                height: 32
                                flat: true

                                property bool isSelected: phaseField.text.toUpperCase() === modelData

                                background: Rectangle {
                                    radius: 6
                                    color: phaseBtn.isSelected
                                        ? "#3d7aab"
                                        : (phaseBtn.hovered ? ThemeManager.surfaceAlt : ThemeManager.surfaceDim)
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }
                                contentItem: Text {
                                    text: phaseBtn.text
                                    color: phaseBtn.isSelected ? ThemeManager.buttonText : ThemeManager.textPrimary
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }
                                onClicked: phaseField.text = modelData
                            }
                        }
                        Item { Layout.fillWidth: true }
                    }

                    // Hidden phase field
                    TextField {
                        id: phaseField
                        visible: false
                        text: "TR"
                    }

                    // Phase description
                    Text {
                        text: root.getPhaseDescription(phaseField.text)
                        color: ThemeManager.textSecondary
                        font.pixelSize: 11
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } } }

                // ── Métricas (display only) ──────────────────────────────
                Text {
                    text: "MÉTRICAS"
                    color: ThemeManager.textSecondary; font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 1
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: 12
                    rowSpacing: 10

                    Text { text: "Latência (s):"; color: ThemeManager.textSecondary; font.pixelSize: 11 }
                    Text { text: root.latencia.toFixed(2); color: ThemeManager.textPrimary; font.weight: Font.Bold }

                    Text { text: "Tempo Plataforma (s):"; color: ThemeManager.textSecondary; font.pixelSize: 11 }
                    Text { text: root.tempoPlataf.toFixed(2); color: ThemeManager.textPrimary; font.weight: Font.Bold }

                    Text { text: "Tempo Grade (s):"; color: ThemeManager.textSecondary; font.pixelSize: 11 }
                    Text { text: root.tempoGrade.toFixed(2); color: ThemeManager.textPrimary; font.weight: Font.Bold }

                    Text { text: "Bouts Plataforma:"; color: ThemeManager.textSecondary; font.pixelSize: 11 }
                    Text { text: root.boutsPlataf; color: ThemeManager.textPrimary; font.weight: Font.Bold }

                    Text { text: "Bouts Grade:"; color: ThemeManager.textSecondary; font.pixelSize: 11 }
                    Text { text: root.boutsGrade; color: ThemeManager.textPrimary; font.weight: Font.Bold }

                    Text { text: "Distância (m):"; color: ThemeManager.textSecondary; font.pixelSize: 11 }
                    Text { text: root.totalDistance.toFixed(2); color: ThemeManager.textPrimary; font.weight: Font.Bold }

                    Text { text: "Velocidade (m/s):"; color: ThemeManager.textSecondary; font.pixelSize: 11 }
                    Text { text: root.avgVelocity.toFixed(2); color: ThemeManager.textPrimary; font.weight: Font.Bold }
                }

                // Droga (se aplicável)
                Rectangle {
                    Layout.fillWidth: true
                    height: root.includeDrug ? 50 : 0
                    visible: root.includeDrug
                    color: "transparent"

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 6
                        Text {
                            text: "DROGA"
                            color: ThemeManager.textSecondary; font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 1
                        }
                        TextField {
                            id: drugField
                            Layout.fillWidth: true
                            placeholderText: "Ex.: Saline, AMPH, etc."
                            color: ThemeManager.textPrimary; placeholderTextColor: ThemeManager.textSecondary; font.pixelSize: 12
                            leftPadding: 10; rightPadding: 10; topPadding: 8; bottomPadding: 8
                            background: Rectangle {
                                radius: 6; color: ThemeManager.surfaceDim
                                Behavior on color { ColorAnimation { duration: 200 } }
                                border.color: drugField.activeFocus ? "#3d7aab" : ThemeManager.border; border.width: 1
                                Behavior on border.color { ColorAnimation { duration: 150 } }
                            }
                        }
                    }
                }
            }
        }

        // ── Botões ───────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            GhostButton {
                text: "Cancelar"
                onClicked: {
                    root.close()
                    root.closed()
                }
            }

            Item { Layout.fillWidth: true }

            Button {
                text: "Salvar Sessão"
                enabled: animalField.text.trim().length > 0

                background: Rectangle {
                    radius: 7
                    color: parent.enabled ? (parent.hovered ? "#2d5f8a" : "#3d7aab") : "#2d2d4a"
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
                contentItem: Text {
                    text: parent.text; color: ThemeManager.buttonText
                    font.pixelSize: 12; font.weight: Font.Bold
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                }
                leftPadding: 16; rightPadding: 16; topPadding: 8; bottomPadding: 8

                onClicked: root.doInsert()
            }
        }
    }
}
