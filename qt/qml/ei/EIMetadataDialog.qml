// qml/ei/EIMetadataDialog.qml
// Diálogo pós-sessão para Esquiva Inibitória — dia + animal + tratamento.

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../core"
import "../core/Theme"
import MindTrace.Backend 1.0

Popup {
    id: root

    anchors.centerIn: parent
    width: 540
    height: mainLayout.implicitHeight + 48
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape

    property string experimentName: ""
    property string videoPath: ""
    property int    numCampos: 1
    property bool   includeDrug: true
    property var    dayNames: []

    property real   latencia: 0
    property real   tempoPlataf: 0
    property real   tempoGrade: 0
    property int    boutsPlataf: 0
    property int    boutsGrade: 0
    property real   totalDistance: 0
    property real   avgVelocity: 0

    property var _animalText: ""
    property var _drogaText:  ""

    onOpened: {
        dayCombo.currentIndex = 0
        _animalText = ""
        _drogaText  = ""
    }

    function doInsert() {
        try {
            var animalText = root._animalText.trim()
            if (!animalText) return

            var fase = dayCombo.currentText
            var dia  = String(dayCombo.currentIndex + 1)
            var tTotalJ    = tempoPlataf + tempoGrade
            var vMediaReal = tTotalJ > 0.5 ? (totalDistance / tTotalJ) : 0.0

            var row = [videoPath, animalText, dia,
                latencia.toFixed(2), tempoPlataf.toFixed(2), tempoGrade.toFixed(2),
                boutsGrade, totalDistance.toFixed(2), vMediaReal.toFixed(2)]
            if (root.includeDrug) row.push(root._drogaText.trim())

            ExperimentManager.insertSessionResult(root.experimentName, [row])

            var sessionMeta = {
                "timestamp": new Date().toISOString(),
                "fase": fase, "dia": dia,
                "videoPath": videoPath.replace("file:///", ""),
                "aparato": "esquiva_inibitoria", "animal": animalText,
                "latencia_s":          parseFloat(latencia.toFixed(2)),
                "tempo_plataforma_s":  parseFloat(tempoPlataf.toFixed(2)),
                "tempo_grade_s":       parseFloat(tempoGrade.toFixed(2)),
                "bouts_plataforma":    boutsPlataf,
                "bouts_grade":         boutsGrade,
                "distancia_total_m":   parseFloat(totalDistance.toFixed(2)),
                "velocidade_media_ms": parseFloat(vMediaReal.toFixed(2)),
                "droga": root.includeDrug ? root._drogaText.trim() : ""
            }
            ExperimentManager.saveSessionMetadata(
                root.experimentName, JSON.stringify(sessionMeta), fase + "_" + animalText)
        } catch (e) {
            console.log("Erro ao salvar sessão EI:", e)
        } finally {
            root.close()
            root.visible = false
        }
    }

    background: Rectangle {
        radius: 14; color: ThemeManager.surface
        Behavior on color { ColorAnimation { duration: 200 } }
        border.color: "#c8a000"; border.width: 1.5
    }

    ColumnLayout {
        id: mainLayout
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
        spacing: 14

        // ── Header ────────────────────────────────────────────────────────
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
                    color: "#c8a000"; font.pixelSize: 11
                }
            }
            Item { Layout.fillWidth: true }
            Text {
                text: "✕"; color: ThemeManager.textSecondary; font.pixelSize: 14
                Behavior on color { ColorAnimation { duration: 150 } }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.close() }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } } }

        // ── Dia da sessão ─────────────────────────────────────────────────
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
                        leftPadding: 12; text: dayCombo.displayText
                        color: ThemeManager.textPrimary; font: dayCombo.font
                        verticalAlignment: Text.AlignVCenter
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                    background: Rectangle {
                        radius: 8; color: ThemeManager.surfaceDim
                        Behavior on color { ColorAnimation { duration: 200 } }
                        border.color: dayCombo.activeFocus ? "#c8a000" : ThemeManager.border; border.width: 1
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                    }
                    delegate: ItemDelegate {
                        width: dayCombo.width
                        contentItem: Text {
                            text: modelData
                            color: dayCombo.currentIndex === index ? "#e0b800" : ThemeManager.textPrimary
                            font.pixelSize: 13; font.weight: Font.Bold; verticalAlignment: Text.AlignVCenter
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                        background: Rectangle {
                            color: hovered ? ThemeManager.surfaceAlt : ThemeManager.surfaceDim
                            Behavior on color { ColorAnimation { duration: 100 } }
                        }
                    }
                    popup: Popup {
                        y: dayCombo.height; width: dayCombo.width; padding: 0
                        background: Rectangle { color: ThemeManager.surfaceDim; border.color: "#c8a000"; radius: 8; Behavior on color { ColorAnimation { duration: 200 } } }
                        contentItem: ListView { implicitHeight: contentHeight; model: dayCombo.delegateModel; clip: true }
                    }
                }

                Rectangle {
                    radius: 6; color: ThemeManager.surfaceDim
                    border.color: "#c8a000"; border.width: 1
                    implicitWidth: diaLbl.implicitWidth + 16; height: 34
                    Text {
                        id: diaLbl; anchors.centerIn: parent
                        text: "Dia " + (dayCombo.currentIndex + 1)
                        color: "#e0b800"; font.pixelSize: 13; font.weight: Font.Bold
                    }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } } }

        // ── Campo único ───────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            radius: 10
            color: ThemeManager.surfaceDim
            border.color: ThemeManager.border; border.width: 1
            implicitHeight: animalCol.implicitHeight + 24
            Behavior on color { ColorAnimation { duration: 200 } }

            ColumnLayout {
                id: animalCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                spacing: 10

                RowLayout {
                    spacing: 12

                    Rectangle {
                        width: 32; height: 22; radius: 5
                        color: "#1a1600"; border.color: "#c8a000"; border.width: 1.5
                        Text {
                            anchors.centerIn: parent
                            text: "C1"
                            color: "#e0b800"; font.pixelSize: 11; font.weight: Font.Bold
                        }
                    }

                    ColumnLayout {
                        spacing: 1
                        Text {
                            text: root.totalDistance.toFixed(2) + " m"
                            color: ThemeManager.textPrimary; font.pixelSize: 15; font.weight: Font.Bold
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                        Text {
                            text: root.avgVelocity.toFixed(3) + " m/s média"
                            color: ThemeManager.textSecondary; font.pixelSize: 10
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    ColumnLayout {
                        spacing: 3
                        Text {
                            text: "ANIMAL"
                            color: ThemeManager.textSecondary
                            font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 1.2
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                        TextField {
                            id: animalField
                            width: 130; height: 30
                            placeholderText: "ID ou nome"
                            color: ThemeManager.textPrimary
                            placeholderTextColor: ThemeManager.textTertiary
                            font.pixelSize: 12
                            leftPadding: 10; rightPadding: 10; topPadding: 6; bottomPadding: 6
                            background: Rectangle {
                                radius: 7; color: ThemeManager.surface
                                Behavior on color { ColorAnimation { duration: 200 } }
                                border.color: animalField.activeFocus ? "#c8a000" : ThemeManager.border; border.width: 1
                                Behavior on border.color { ColorAnimation { duration: 150 } }
                            }
                            onTextChanged: root._animalText = text
                        }
                    }
                }

                RowLayout {
                    visible: root.includeDrug; spacing: 12
                    Item { width: 44 }
                    ColumnLayout {
                        spacing: 3
                        Text {
                            text: "TRATAMENTO"
                            color: ThemeManager.textSecondary
                            font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 1.2
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                        TextField {
                            id: drogaField
                            width: 260; height: 30
                            placeholderText: "Ex.: Salina, Midazolam…"
                            color: ThemeManager.textPrimary
                            placeholderTextColor: ThemeManager.textTertiary
                            font.pixelSize: 12
                            leftPadding: 10; rightPadding: 10; topPadding: 6; bottomPadding: 6
                            background: Rectangle {
                                radius: 7; color: ThemeManager.surface
                                Behavior on color { ColorAnimation { duration: 200 } }
                                border.color: drogaField.activeFocus ? "#c8a000" : ThemeManager.border; border.width: 1
                                Behavior on border.color { ColorAnimation { duration: 150 } }
                            }
                            onTextChanged: root._drogaText = text
                        }
                    }
                }

                Item { height: 2 }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } } }

        // ── Botões ────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true; spacing: 10
            Item { Layout.fillWidth: true }
            GhostButton { text: "Cancelar"; onClicked: root.close() }
            Button {
                text: "Salvar Sessão"
                enabled: root._animalText.trim().length > 0
                onClicked: root.doInsert()
                background: Rectangle {
                    radius: 8
                    color: parent.enabled ? (parent.hovered ? "#9a7800" : "#c8a000") : ThemeManager.border
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
                contentItem: Text {
                    text: parent.text; color: "#ffffff"
                    font.pixelSize: 13; font.weight: Font.Bold
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                }
                leftPadding: 20; rightPadding: 20; topPadding: 10; bottomPadding: 10
            }
        }

        Item { height: 4 }
    }
}
