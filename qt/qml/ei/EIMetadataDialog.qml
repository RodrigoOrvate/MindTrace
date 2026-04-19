// qml/ei/EIMetadataDialog.qml
// Diálogo pós-sessão para Esquiva Inibitória — seleção de dia via ComboBox.

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
    height: 560
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape

    property string experimentName: ""
    property string videoPath: ""
    property int    numCampos: 1
    property bool   includeDrug: true
    property var    dayNames: []

    // Métricas recebidas da sessão
    property real   latencia: 0
    property real   tempoPlataf: 0
    property real   tempoGrade: 0
    property int    boutsPlataf: 0
    property int    boutsGrade: 0
    property real   totalDistance: 0
    property real   avgVelocity: 0

    onOpened: { dayCombo.currentIndex = 0 }

    function doInsert() {
        var animalText = animalField.text.trim()
        if (!animalText) {
            Toast.show("Digite o ID do animal.")
            return
        }

        var fase = dayCombo.currentText
        var dia  = String(dayCombo.currentIndex + 1)

        var row = [
            videoPath,
            animalText,
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

        var sessionMeta = {
            "timestamp": new Date().toISOString(),
            "fase":      fase,
            "dia":       dia,
            "videoPath": videoPath.replace("file:///", ""),
            "aparato":   "esquiva_inibitoria",
            "animal":    animalText,
            "latencia_s":          parseFloat(latencia.toFixed(2)),
            "tempo_plataforma_s":  parseFloat(tempoPlataf.toFixed(2)),
            "tempo_grade_s":       parseFloat(tempoGrade.toFixed(2)),
            "bouts_plataforma":    boutsPlataf,
            "bouts_grade":         boutsGrade,
            "distancia_total_m":   parseFloat(totalDistance.toFixed(2)),
            "velocidade_media_ms": parseFloat(avgVelocity.toFixed(2)),
            "droga":               root.includeDrug ? drugField.text.trim() : ""
        }
        ExperimentManager.saveSessionMetadata(
            root.experimentName, JSON.stringify(sessionMeta), fase + "_" + animalText)

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
        RowLayout {
            spacing: 10
            Text { text: "🪤"; font.pixelSize: 20 }
            ColumnLayout {
                spacing: 2
                Text {
                    text: "Sessão Concluída"
                    color: ThemeManager.textPrimary; font.pixelSize: 16; font.weight: Font.Bold
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
                Text {
                    text: "Esquiva Inibitória — informe o dia e o animal"
                    color: "#3d7aab"; font.pixelSize: 11
                }
            }
            Item { Layout.fillWidth: true }
            Text {
                text: "✕"; color: ThemeManager.textSecondary; font.pixelSize: 14
                Behavior on color { ColorAnimation { duration: 150 } }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.close(); root.closed() } }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } } }

        // ── Scroll Area com campos ────────────────────────────────────
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                width: root.width - 48
                spacing: 14

                // ── Dia da sessão ─────────────────────────────────────
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 6

                    Text {
                        text: "DIA DA SESSÃO"
                        color: ThemeManager.textSecondary
                        font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 1.4
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    RowLayout {
                        spacing: 10

                        ComboBox {
                            id: dayCombo
                            model: root.dayNames.length > 0 ? root.dayNames : ["Dia 1"]
                            Layout.fillWidth: true
                            font.pixelSize: 13; font.weight: Font.Bold

                            contentItem: Text {
                                leftPadding: 12
                                text: dayCombo.displayText
                                color: ThemeManager.textPrimary; font: dayCombo.font
                                verticalAlignment: Text.AlignVCenter
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }
                            background: Rectangle {
                                radius: 8; color: ThemeManager.surfaceDim
                                Behavior on color { ColorAnimation { duration: 200 } }
                                border.color: dayCombo.activeFocus ? "#3d7aab" : ThemeManager.border; border.width: 1
                                Behavior on border.color { ColorAnimation { duration: 150 } }
                            }
                            delegate: ItemDelegate {
                                width: dayCombo.width
                                contentItem: Text {
                                    text: modelData
                                    color: dayCombo.currentIndex === index ? "#3d7aab" : ThemeManager.textPrimary
                                    font.pixelSize: 13; font.weight: Font.Bold
                                    verticalAlignment: Text.AlignVCenter
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }
                                background: Rectangle {
                                    color: hovered ? ThemeManager.surfaceAlt : ThemeManager.surfaceDim
                                    Behavior on color { ColorAnimation { duration: 100 } }
                                }
                            }
                            popup: Popup {
                                y: dayCombo.height; width: dayCombo.width; padding: 0
                                background: Rectangle { color: ThemeManager.surfaceDim; border.color: "#3d7aab"; radius: 8; Behavior on color { ColorAnimation { duration: 200 } } }
                                contentItem: ListView { implicitHeight: contentHeight; model: dayCombo.delegateModel; clip: true }
                            }
                        }

                        Rectangle {
                            radius: 6; color: ThemeManager.surfaceDim
                            border.color: "#3d7aab"; border.width: 1
                            implicitWidth: diaLbl.implicitWidth + 16; height: 34
                            Text {
                                id: diaLbl; anchors.centerIn: parent
                                text: "Dia " + (dayCombo.currentIndex + 1)
                                color: "#3d7aab"; font.pixelSize: 13; font.weight: Font.Bold
                            }
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } } }

                // Animal ID
                ColumnLayout {
                    spacing: 6
                    Text {
                        text: "ID DO ANIMAL"
                        color: ThemeManager.textSecondary; font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 1
                        Behavior on color { ColorAnimation { duration: 150 } }
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

                Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } } }

                // ── Métricas (display only) ──────────────────────────────
                Text {
                    text: "MÉTRICAS"
                    color: ThemeManager.textSecondary; font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 1
                    Behavior on color { ColorAnimation { duration: 150 } }
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: 12
                    rowSpacing: 10

                    Text { text: "Latência (s):"; color: ThemeManager.textSecondary; font.pixelSize: 11 }
                    Text { text: root.latencia.toFixed(2); color: ThemeManager.textPrimary; font.weight: Font.Bold; Behavior on color { ColorAnimation { duration: 150 } } }

                    Text { text: "Tempo Plataforma (s):"; color: ThemeManager.textSecondary; font.pixelSize: 11 }
                    Text { text: root.tempoPlataf.toFixed(2); color: ThemeManager.textPrimary; font.weight: Font.Bold; Behavior on color { ColorAnimation { duration: 150 } } }

                    Text { text: "Tempo Grade (s):"; color: ThemeManager.textSecondary; font.pixelSize: 11 }
                    Text { text: root.tempoGrade.toFixed(2); color: ThemeManager.textPrimary; font.weight: Font.Bold; Behavior on color { ColorAnimation { duration: 150 } } }

                    Text { text: "Bouts Plataforma:"; color: ThemeManager.textSecondary; font.pixelSize: 11 }
                    Text { text: root.boutsPlataf; color: ThemeManager.textPrimary; font.weight: Font.Bold; Behavior on color { ColorAnimation { duration: 150 } } }

                    Text { text: "Bouts Grade:"; color: ThemeManager.textSecondary; font.pixelSize: 11 }
                    Text { text: root.boutsGrade; color: ThemeManager.textPrimary; font.weight: Font.Bold; Behavior on color { ColorAnimation { duration: 150 } } }

                    Text { text: "Distância (m):"; color: ThemeManager.textSecondary; font.pixelSize: 11 }
                    Text { text: root.totalDistance.toFixed(2); color: ThemeManager.textPrimary; font.weight: Font.Bold; Behavior on color { ColorAnimation { duration: 150 } } }

                    Text { text: "Velocidade (m/s):"; color: ThemeManager.textSecondary; font.pixelSize: 11 }
                    Text { text: root.avgVelocity.toFixed(2); color: ThemeManager.textPrimary; font.weight: Font.Bold; Behavior on color { ColorAnimation { duration: 150 } } }
                }

                // Tratamento (se aplicável)
                ColumnLayout {
                    visible: root.includeDrug
                    spacing: 6
                    Text {
                        text: "TRATAMENTO"
                        color: ThemeManager.textSecondary; font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 1
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                    TextField {
                        id: drugField
                        Layout.fillWidth: true
                        placeholderText: "Ex.: Salina, Midazolam…"
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

        // ── Botões ───────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            GhostButton {
                text: "Cancelar"
                onClicked: { root.close(); root.closed() }
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
