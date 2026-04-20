// qml/ca/CAMetadataDialog.qml
// Popup pós-sessão CA: coleta metadados (fase, animais, droga) e persiste CSV + JSON.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../core"
import "../core/Theme"
import MindTrace.Backend 1.0

Popup {
    id: root

    property string experimentName:  ""
    property string experimentPath:  ""
    property string videoPath:       ""
    property int    numCampos:       3
    property bool   includeDrug:     true
    property bool   hasReactivation: false
    property var    dayNames:        []

    property var totalDistance: [0.0, 0.0, 0.0]
    property var avgVelocity:   [0.0, 0.0, 0.0]
    property var perMinuteData: [[], [], []]
    property var explorationTimes: []
    property var explorationBouts: []

    property var _animalTexts: ["", "", ""]
    property var _drogaTexts:  ["", "", ""]

    anchors.centerIn: parent
    width:  540
    height: mainLayout.implicitHeight + 48
    modal:  true
    focus:  true
    closePolicy: Popup.CloseOnEscape

    onOpened: {
        dayCombo.currentIndex = 0
        root._animalTexts = ["", "", ""]
        root._drogaTexts  = ["", "", ""]
    }

    background: Rectangle {
        radius: 14; color: ThemeManager.surface
        Behavior on color { ColorAnimation { duration: 200 } }
        border.color: "#3d7aab"; border.width: 1.5
    }

    function doInsert() {
        var v    = root.videoPath.replace("file:///", "")
        var fase = dayCombo.currentText
        var dia  = String(dayCombo.currentIndex + 1)

        var rows = []
        for (var ci = 0; ci < root.numCampos; ci++) {
            var aText = root._animalTexts[ci] || ""
            if (!aText) continue
            var tCentro = 0, tBorda = 0, vCentro = 0
            if (root.explorationTimes.length >= (ci + 1) * 2) {
                tCentro = parseFloat(root.explorationTimes[ci * 2]) || 0
                tBorda  = parseFloat(root.explorationTimes[ci * 2 + 1]) || 0
            }
            if (root.explorationBouts.length >= (ci + 1) * 2) {
                vCentro = (root.explorationBouts[ci * 2] || []).length
            }
            var tTotal = tCentro + tBorda
            var distReal = parseFloat(root.totalDistance[ci]) || 0.0
            var vMedia   = tTotal > 0.5 ? (distReal / tTotal) : 0.0

            var row = [v, aText, String(ci + 1), dia,
                       tCentro.toFixed(2), tBorda.toFixed(2),
                       String(vCentro), distReal.toFixed(3), vMedia.toFixed(3)]
            if (root.includeDrug) row.push(root._drogaTexts[ci] || "")
            rows.push(row)
        }

        ExperimentManager.insertSessionResult(root.experimentName, rows)

        var sessionMeta = {
            "timestamp": new Date().toISOString(),
            "fase": fase, "dia": dia, "videoPath": v,
            "aparato": "campo_aberto", "campos": []
        }
        for (var cj = 0; cj < root.numCampos; cj++) {
            var a = root._animalTexts[cj] || ""
            if (!a) continue
            var tCentroJ = 0, tBordaJ = 0, vCentroJ = 0
            if (root.explorationTimes.length >= (cj + 1) * 2) {
                tCentroJ = parseFloat(root.explorationTimes[cj * 2]) || 0
                tBordaJ  = parseFloat(root.explorationTimes[cj * 2 + 1]) || 0
            }
            if (root.explorationBouts.length >= (cj + 1) * 2)
                vCentroJ = (root.explorationBouts[cj * 2] || []).length
            var tTotalJ = tCentroJ + tBordaJ
            var distRealJ = parseFloat(root.totalDistance[cj]) || 0.0
            sessionMeta["campos"].push({
                "animal": a, "campo": cj + 1,
                "droga": root.includeDrug ? (root._drogaTexts[cj] || "") : "",
                "movimento": {
                    "tempo_centro_s": tCentroJ, "tempo_borda_s": tBordaJ,
                    "visitas_centro": vCentroJ,
                    "distancia_total_m":   distRealJ,
                    "velocidade_media_ms": tTotalJ > 0.5 ? (distRealJ / tTotalJ) : 0.0
                },
                "porMinuto": root.perMinuteData[cj] || []
            })
        }
        var animaisStr = root._animalTexts.slice(0, root.numCampos)
            .filter(function(am) { return am.length > 0 }).join("-")
        ExperimentManager.saveSessionMetadata(
            root.experimentName, JSON.stringify(sessionMeta), fase + "_" + animaisStr)
        root.close()
    }

    // ── UI ────────────────────────────────────────────────────────────────
    ColumnLayout {
        id: mainLayout
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
        spacing: 14

        // ── Header ────────────────────────────────────────────────────────
        RowLayout {
            spacing: 10
            Text { text: "🐀"; font.pixelSize: 20 }
            ColumnLayout {
                spacing: 2
                Text {
                    text: "Sessão Concluída"
                    color: ThemeManager.textPrimary; font.pixelSize: 16; font.weight: Font.Bold
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
                Text {
                    text: "Campo Aberto — informe o dia e os animais"
                    color: "#3d7aab"; font.pixelSize: 11
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
                        border.color: dayCombo.activeFocus ? "#3d7aab" : ThemeManager.border; border.width: 1
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                    }
                    delegate: ItemDelegate {
                        width: dayCombo.width
                        contentItem: Text {
                            text: modelData
                            color: dayCombo.currentIndex === index ? "#5b9fd4" : ThemeManager.textPrimary
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
                        color: "#5b9fd4"; font.pixelSize: 13; font.weight: Font.Bold
                    }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } } }

        // ── Campos ────────────────────────────────────────────────────────
        CampoBlock {
            Layout.fillWidth: true; visible: root.numCampos >= 1; campoIndex: 0
            dist: root.totalDistance[0] || 0; vel: root.avgVelocity[0] || 0
            includeDrug: root.includeDrug
            onAnimalChanged: function(txt) { var a = root._animalTexts.slice(); a[0] = txt; root._animalTexts = a }
            onDrogaChanged:  function(txt) { var d = root._drogaTexts.slice();  d[0] = txt; root._drogaTexts  = d }
        }
        CampoBlock {
            Layout.fillWidth: true; visible: root.numCampos >= 2; campoIndex: 1
            dist: root.totalDistance[1] || 0; vel: root.avgVelocity[1] || 0
            includeDrug: root.includeDrug
            onAnimalChanged: function(txt) { var a = root._animalTexts.slice(); a[1] = txt; root._animalTexts = a }
            onDrogaChanged:  function(txt) { var d = root._drogaTexts.slice();  d[1] = txt; root._drogaTexts  = d }
        }
        CampoBlock {
            Layout.fillWidth: true; visible: root.numCampos >= 3; campoIndex: 2
            dist: root.totalDistance[2] || 0; vel: root.avgVelocity[2] || 0
            includeDrug: root.includeDrug
            onAnimalChanged: function(txt) { var a = root._animalTexts.slice(); a[2] = txt; root._animalTexts = a }
            onDrogaChanged:  function(txt) { var d = root._drogaTexts.slice();  d[2] = txt; root._drogaTexts  = d }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } } }

        // ── Botões ────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true; spacing: 10
            Item { Layout.fillWidth: true }
            GhostButton { text: "Cancelar"; onClicked: root.close() }
            Button {
                text: "Salvar Sessão"
                onClicked: root.doInsert()
                background: Rectangle {
                    radius: 8; color: parent.hovered ? "#2d5f8a" : "#3d7aab"
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

    // ── Componente: bloco por campo ───────────────────────────────────────
    component CampoBlock: Rectangle {
        id: blk
        radius: 10
        color: ThemeManager.surfaceDim
        border.color: ThemeManager.border; border.width: 1
        implicitHeight: blkCol.implicitHeight + 24
        Behavior on color { ColorAnimation { duration: 200 } }

        property int  campoIndex:  0
        property real dist:        0.0
        property real vel:         0.0
        property bool includeDrug: true

        signal animalChanged(string txt)
        signal drogaChanged(string txt)

        ColumnLayout {
            id: blkCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
            spacing: 10

            RowLayout {
                spacing: 12

                Rectangle {
                    width: 32; height: 22; radius: 5
                    color: "#0d1a30"; border.color: "#3d7aab"; border.width: 1.5
                    Text {
                        anchors.centerIn: parent
                        text: "C" + (blk.campoIndex + 1)
                        color: "#5b9fd4"; font.pixelSize: 11; font.weight: Font.Bold
                    }
                }

                ColumnLayout {
                    spacing: 1
                    Text {
                        text: blk.dist.toFixed(2) + " m"
                        color: ThemeManager.textPrimary; font.pixelSize: 15; font.weight: Font.Bold
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                    Text {
                        text: blk.vel.toFixed(3) + " m/s média"
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
                            border.color: animalField.activeFocus ? "#3d7aab" : ThemeManager.border; border.width: 1
                            Behavior on border.color { ColorAnimation { duration: 150 } }
                        }
                        onTextChanged: blk.animalChanged(text)
                    }
                }
            }

            RowLayout {
                visible: blk.includeDrug; spacing: 12
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
                            border.color: drogaField.activeFocus ? "#3d7aab" : ThemeManager.border; border.width: 1
                            Behavior on border.color { ColorAnimation { duration: 150 } }
                        }
                        onTextChanged: blk.drogaChanged(text)
                    }
                }
            }

            Item { height: 2 }
        }
    }
}
