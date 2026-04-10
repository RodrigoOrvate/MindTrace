// qml/ca/CAMetadataDialog.qml
// Popup pós-sessão CA: coleta metadados (fase, animais, droga)
// e persiste CSV (UTF-8 BOM) + JSON rico na pasta /sessions/.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../core"
import "../core/Theme"
import MindTrace.Backend 1.0

Popup {
    id: root

    // ── Dados injetados pelo CADashboard ──────────────────────────────────
    property string experimentName:  ""
    property string experimentPath:  ""
    property string videoPath:       ""
    property int    numCampos:       3
    property bool   includeDrug:     true
    property bool   hasReactivation: false

    // Resultados da sessão (vindos do LiveRecording)
    property var totalDistance: [0.0, 0.0, 0.0]
    property var avgVelocity:   [0.0, 0.0, 0.0]
    property var perMinuteData: [[], [], []]

    // Acesso direto aos campos via propriedades (sem id em Repeater)
    property var _animalTexts: ["", "", ""]
    property var _drogaTexts:  ["", "", ""]

    // ── Geometria ─────────────────────────────────────────────────────────
    width:  520
    modal:  true
    focus:  true
    closePolicy: Popup.CloseOnEscape

    background: Rectangle {
        radius: 16; color: ThemeManager.surface
        Behavior on color { ColorAnimation { duration: 200 } }
        border.color: "#3d7aab"; border.width: 1.5
    }

    // ── Função de inserção ────────────────────────────────────────────────
    function doInsert() {
        var v    = root.videoPath.replace("file:///", "")
        var fase = phaseField.text.toUpperCase().trim()

        function parseDay(p) {
            if (p === "TR") return "1"
            if (p === "RA") return "2"
            if (p === "TT") return root.hasReactivation ? "3" : "2"
            return ""
        }
        var dia = parseDay(fase)

        var rows = []
        for (var ci = 0; ci < root.numCampos; ci++) {
            var aText = root._animalTexts[ci] || ""
            if (!aText) continue
            var row = [
                v,
                aText,
                String(ci + 1),
                dia,
                parseFloat((root.totalDistance[ci] || 0).toFixed(3)),
                parseFloat((root.avgVelocity[ci]   || 0).toFixed(3))
            ]
            if (root.includeDrug) row.push(root._drogaTexts[ci] || "")
            rows.push(row)
        }

        ExperimentManager.insertSessionResult(root.experimentName, rows)

        // JSON rico
        var sessionMeta = {
            "timestamp": new Date().toISOString(),
            "fase":      fase,
            "dia":       dia,
            "videoPath": v,
            "aparato":   "campo_aberto",
            "campos":    []
        }
        for (var cj = 0; cj < root.numCampos; cj++) {
            var a = root._animalTexts[cj] || ""
            if (!a) continue
            sessionMeta["campos"].push({
                "animal": a,
                "campo":  cj + 1,
                "droga":  root.includeDrug ? (root._drogaTexts[cj] || "") : "",
                "movimento": {
                    "distancia_total_m":   parseFloat((root.totalDistance[cj] || 0).toFixed(3)),
                    "velocidade_media_ms": parseFloat((root.avgVelocity[cj]   || 0).toFixed(3))
                },
                "porMinuto": root.perMinuteData[cj] || []
            })
        }

        var animaisStr = root._animalTexts
            .slice(0, root.numCampos)
            .filter(function(a) { return a.length > 0 })
            .join("-")
        ExperimentManager.saveSessionMetadata(
            root.experimentName, JSON.stringify(sessionMeta), fase + "_" + animaisStr)

        root.close()
    }

    // ── UI ────────────────────────────────────────────────────────────────
    ColumnLayout {
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
        spacing: 16

        // Cabeçalho
        RowLayout {
            spacing: 10
            Text { text: "🐀"; font.pixelSize: 22 }
            Text {
                text: "Sessão Concluída — Campo Aberto"
                color: ThemeManager.textPrimary; font.pixelSize: 17; font.weight: Font.Bold
                Behavior on color { ColorAnimation { duration: 150 } }
            }
            Item { Layout.fillWidth: true }
            Text {
                text: "✕"; color: ThemeManager.textSecondary; font.pixelSize: 14
                Behavior on color { ColorAnimation { duration: 150 } }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.close() }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } } }

        // ── Fase ─────────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true; spacing: 6

            Text {
                text: "FASE DA SESSÃO"
                color: ThemeManager.textSecondary; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.5
            }

            RowLayout {
                spacing: 8

                Repeater {
                    model: ["TR", "RA", "TT"]
                    delegate: Rectangle {
                        height: 34; width: 54; radius: 8
                        property bool isSelected: phaseField.text.toUpperCase() === modelData
                        property bool isAvailable: modelData !== "RA" || root.hasReactivation
                        color:        (!isAvailable) ? ThemeManager.surfaceDim
                                    : isSelected ? ThemeManager.accentDim
                                    : (phaseBtnMa.containsMouse ? ThemeManager.surfaceHover : ThemeManager.surfaceDim)
                        border.color: (!isAvailable) ? ThemeManager.border
                                    : isSelected ? "#3d7aab" : ThemeManager.border
                        border.width: isSelected ? 2 : 1
                        opacity: isAvailable ? 1.0 : 0.4
                        Behavior on color        { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        Text {
                            anchors.centerIn: parent; text: modelData
                            color: isSelected ? "#3d7aab" : ThemeManager.textSecondary; font.pixelSize: 13; font.weight: Font.Bold
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                        MouseArea {
                            id: phaseBtnMa; anchors.fill: parent; hoverEnabled: true
                            enabled: parent.isAvailable; cursorShape: Qt.PointingHandCursor
                            onClicked: phaseField.text = modelData
                        }
                    }
                }

                TextField {
                    id: phaseField
                    width: 60; height: 34
                    text: "TR"
                    color: ThemeManager.textPrimary; font.pixelSize: 13; font.weight: Font.Bold
                    leftPadding: 10; rightPadding: 10; topPadding: 8; bottomPadding: 8
                    background: Rectangle {
                        radius: 8; color: ThemeManager.surfaceDim; Behavior on color { ColorAnimation { duration: 200 } }
                        border.color: phaseField.activeFocus ? "#3d7aab" : ThemeManager.border; border.width: 1
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                    }
                }

                Text {
                    text: {
                        var f = phaseField.text.toUpperCase()
                        if (f === "TR") return "Treino · Dia 1"
                        if (f === "RA") return root.hasReactivation ? "Reativação · Dia 2" : "⚠ RA não habilitado"
                        if (f === "TT") return root.hasReactivation ? "Teste · Dia 3" : "Teste · Dia 2"
                        return ""
                    }
                    color: (phaseField.text.toUpperCase() === "RA" && !root.hasReactivation)
                           ? "#ff5566" : ThemeManager.textTertiary
                    font.pixelSize: 11
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } } }

        // ── Campo 1 ───────────────────────────────────────────────────────
        CampoDataRow {
            Layout.fillWidth: true
            visible: root.numCampos >= 1
            campoIndex: 0
            dist: root.totalDistance[0] || 0
            vel:  root.avgVelocity[0]   || 0
            includeDrug: root.includeDrug
            onAnimalChanged: function(txt) {
                var a = root._animalTexts.slice(); a[0] = txt; root._animalTexts = a
            }
            onDrogaChanged: function(txt) {
                var d = root._drogaTexts.slice(); d[0] = txt; root._drogaTexts = d
            }
        }

        // ── Campo 2 ───────────────────────────────────────────────────────
        CampoDataRow {
            Layout.fillWidth: true
            visible: root.numCampos >= 2
            campoIndex: 1
            dist: root.totalDistance[1] || 0
            vel:  root.avgVelocity[1]   || 0
            includeDrug: root.includeDrug
            onAnimalChanged: function(txt) {
                var a = root._animalTexts.slice(); a[1] = txt; root._animalTexts = a
            }
            onDrogaChanged: function(txt) {
                var d = root._drogaTexts.slice(); d[1] = txt; root._drogaTexts = d
            }
        }

        // ── Campo 3 ───────────────────────────────────────────────────────
        CampoDataRow {
            Layout.fillWidth: true
            visible: root.numCampos >= 3
            campoIndex: 2
            dist: root.totalDistance[2] || 0
            vel:  root.avgVelocity[2]   || 0
            includeDrug: root.includeDrug
            onAnimalChanged: function(txt) {
                var a = root._animalTexts.slice(); a[2] = txt; root._animalTexts = a
            }
            onDrogaChanged: function(txt) {
                var d = root._drogaTexts.slice(); d[2] = txt; root._drogaTexts = d
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
                onClicked: {
                    var f = phaseField.text.toUpperCase().trim()
                    if (f !== "TR" && f !== "RA" && f !== "TT") { errorPhasePopup.open(); return }
                    if (f === "RA" && !root.hasReactivation)   { errorPhasePopup.open(); return }
                    root.doInsert()
                }

                background: Rectangle {
                    radius: 8; color: parent.hovered ? "#2d5f8a" : "#3d7aab"
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
                contentItem: Text {
                    text: parent.text; color: ThemeManager.buttonText
                    font.pixelSize: 13; font.weight: Font.Bold
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                }
                leftPadding: 18; rightPadding: 18; topPadding: 9; bottomPadding: 9
            }
        }

        Item { height: 4 }
    }

    // ── Componente interno: linha por campo ───────────────────────────────
    component CampoDataRow: Rectangle {
        id: rowRect
        height: includeDrug ? 80 : 54; radius: 10
        color: ThemeManager.surfaceDim
        border.color: ThemeManager.border; border.width: 1
        Behavior on color { ColorAnimation { duration: 200 } }

        property int    campoIndex:  0
        property real   dist:        0.0
        property real   vel:         0.0
        property bool   includeDrug: true

        signal animalChanged(string txt)
        signal drogaChanged(string txt)

        ColumnLayout {
            anchors { fill: parent; leftMargin: 14; rightMargin: 14; topMargin: 10; bottomMargin: 10 }
            spacing: 6

            RowLayout {
                spacing: 10

                Rectangle {
                    width: 28; height: 20; radius: 4
                    color: "#0d1a30"; border.color: "#3d7aab"; border.width: 1
                    Text { anchors.centerIn: parent; text: "C" + (rowRect.campoIndex + 1); color: "#3d7aab"; font.pixelSize: 10; font.weight: Font.Bold }
                }

                Text {
                    text: rowRect.dist.toFixed(2) + " m  ·  " + rowRect.vel.toFixed(3) + " m/s"
                    color: ThemeManager.textTertiary; font.pixelSize: 11
                }

                Item { Layout.fillWidth: true }

                ColumnLayout {
                    spacing: 2
                    Text { text: "ANIMAL"; color: ThemeManager.textSecondary; font.pixelSize: 9; font.letterSpacing: 1 }
                    TextField {
                        id: animalField
                        width: 120; height: 26
                        placeholderText: "ID ou nome"
                        color: ThemeManager.textPrimary; placeholderTextColor: ThemeManager.textSecondary; font.pixelSize: 12
                        leftPadding: 8; rightPadding: 8; topPadding: 4; bottomPadding: 4
                        background: Rectangle {
                            radius: 6; color: ThemeManager.surface
                            border.color: animalField.activeFocus ? "#3d7aab" : ThemeManager.border; border.width: 1
                            Behavior on border.color { ColorAnimation { duration: 150 } }
                        }
                        onTextChanged: rowRect.animalChanged(text)
                    }
                }
            }

            RowLayout {
                visible: rowRect.includeDrug; spacing: 10

                Item { width: 38 }

                ColumnLayout {
                    spacing: 2
                    Text { text: "DROGA"; color: ThemeManager.textSecondary; font.pixelSize: 9; font.letterSpacing: 1 }
                    TextField {
                        id: drogaField
                        width: 200; height: 26
                        placeholderText: "Ex.: Salina, Midazolam…"
                        color: ThemeManager.textPrimary; placeholderTextColor: ThemeManager.textSecondary; font.pixelSize: 12
                        leftPadding: 8; rightPadding: 8; topPadding: 4; bottomPadding: 4
                        background: Rectangle {
                            radius: 6; color: ThemeManager.surface
                            border.color: drogaField.activeFocus ? "#3d7aab" : ThemeManager.border; border.width: 1
                            Behavior on border.color { ColorAnimation { duration: 150 } }
                        }
                        onTextChanged: rowRect.drogaChanged(text)
                    }
                }
            }
        }
    }

    // ── Popup erro de fase ────────────────────────────────────────────────
    Popup {
        id: errorPhasePopup
        anchors.centerIn: parent; width: 280; height: 110
        modal: true; closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle { radius: 10; color: "#1a1a2e"; border.color: "#ab3d4c" }
        ColumnLayout {
            anchors.centerIn: parent; spacing: 8
            Text { text: "Fase inválida"; color: "#ff5566"; font.pixelSize: 14; font.weight: Font.Bold; Layout.alignment: Qt.AlignHCenter }
            Text { text: "Use TR, RA ou TT."; color: "#aaaacc"; font.pixelSize: 12; Layout.alignment: Qt.AlignHCenter }
            Button {
                Layout.alignment: Qt.AlignHCenter; text: "OK"
                onClicked: errorPhasePopup.close()
                background: Rectangle { radius: 6; color: "#ab3d4c" }
                contentItem: Text { text: parent.text; color: "white"; font.pixelSize: 12; font.weight: Font.Bold; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                leftPadding: 20; rightPadding: 20; topPadding: 6; bottomPadding: 6
            }
        }
    }
}
