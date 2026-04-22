// qml/SessionResultDialog.qml
// Popup pós-gravação NOR: usuário confirma os dados dos animais de cada campo.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../core"
import "../core/Theme"
import MindTrace.Backend 1.0

Popup {
    id: root

    // ── Dados fornecidos pelo Dashboard ──────────────────────────────────
    property string experimentName:   ""
    property string pair1:            ""
    property string pair2:            ""
    property string pair3:            ""
    property string sessionTypeLabel: ""
    property string dia:              ""
    property bool   includeDrug:      true
    property bool   hasReactivation:  false
    property var    dayNames:         []
    property string analysisMode:     "offline"
    property string saveDirectory:    ""
    property string videoPath:        ""
    property int    numCampos:        3

    // ── Dados de tracking da sessão ───────────────────────────────────────
    property var sessionExplorationBouts: [[], [], [], [], [], []]
    property var sessionExplorationTimes: [0, 0, 0, 0, 0, 0]
    property var sessionTotalDistance:    [0.0, 0.0, 0.0]
    property var sessionAvgVelocity:      [0.0, 0.0, 0.0]
    property var sessionPerMinuteData:    [{}, {}, {}]

    function localizedDayName(dayName, index) {
        var t = String(dayName || "").trim().toLowerCase()
        if (t === "treino" || t === "training" || t === "entrenamiento")
            return LanguageManager.tr3("Treino", "Training", "Entrenamiento")
        if (t === "teste" || t === "test" || t === "prueba")
            return LanguageManager.tr3("Teste", "Test", "Prueba")
        return String(dayName || (LanguageManager.tr3("Dia ", "Day ", "Dia ") + (index + 1)))
    }

    function localizedDayNames() {
        var out = []
        if (root.dayNames && root.dayNames.length > 0) {
            for (var i = 0; i < root.dayNames.length; i++)
                out.push(localizedDayName(root.dayNames[i], i))
            return out
        }
        return [LanguageManager.tr3("Day 1", "Day 1", "Dia 1")]
    }

    property var _animalTexts:  ["", "", ""]
    property var _drogaTexts:   ["", "", ""]
    property var _animalDbIds:  [-1, -1, -1]

    function _postEvent(dbId, title, payload) {
        if (dbId <= 0) return
        var xhr = new XMLHttpRequest()
        xhr.open("POST", "http://localhost:8000/animals/" + dbId + "/events")
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.send(JSON.stringify({ event_type: "experiment_session", title: title, payload: payload, source: "mindtrace" }))
    }

    // ── Geometria ─────────────────────────────────────────────────────────
    anchors.centerIn: parent
    width: 540
    height: mainLayout.implicitHeight + 48
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape

    onOpened: {
        dayCombo.currentIndex = 0
        root._animalTexts = ["", "", ""]
        root._drogaTexts  = ["", "", ""]
        root._animalDbIds = [-1, -1, -1]
        c1.picker.clear(); c2.picker.clear(); c3.picker.clear()
    }

    background: Rectangle {
        radius: 14; color: ThemeManager.surface
        Behavior on color { ColorAnimation { duration: 200 } }
        border.color: "#ab3d4c"; border.width: 1.5
    }

    // ── Função de inserção ────────────────────────────────────────────────
    function doInsert() {
        var v    = root.videoPath.replace("file:///", "")
        var fase = dayCombo.currentText
        var dia  = String(dayCombo.currentIndex + 1)
        var rows = []
        var pares = [root.pair1, root.pair2, root.pair3]

        for (var i = 0; i < root.numCampos; i++) {
            var aText = root._animalTexts[i] || ""
            if (!aText) continue
            var zi0 = i * 2, zi1 = i * 2 + 1
            var tA = root.sessionExplorationTimes[zi0] || 0
            var tB = root.sessionExplorationTimes[zi1] || 0
            var tot = tA + tB
            var di = tot > 0 ? ((tB - tA) / tot).toFixed(3) : "0.000"
            var bA = (root.sessionExplorationBouts[zi0] || []).length
            var bB = (root.sessionExplorationBouts[zi1] || []).length
            var row = [v, aText, String(i + 1), dia, pares[i],
                       tA.toFixed(2), bA,
                       tB.toFixed(2), bB,
                       tot.toFixed(2), di,
                       (root.sessionTotalDistance[i] || 0).toFixed(3),
                       (root.sessionAvgVelocity[i]   || 0).toFixed(3)]
            if (root.includeDrug) row.push(root._drogaTexts[i] || "")
            rows.push(row)
        }

        ExperimentManager.insertSessionResult(root.experimentName, rows)

        var sessionMeta = {
            "timestamp": new Date().toISOString(),
            "fase": fase, "dia": dia, "videoPath": v, "campos": []
        }
        var paresArr = [root.pair1, root.pair2, root.pair3]
        for (var j = 0; j < root.numCampos; j++) {
            if (!root._animalTexts[j]) continue
            var z0 = j * 2, z1 = j * 2 + 1
            var b0 = root.sessionExplorationBouts[z0] || []
            var b1 = root.sessionExplorationBouts[z1] || []
            var t0 = root.sessionExplorationTimes[z0] || 0
            var t1 = root.sessionExplorationTimes[z1] || 0
            sessionMeta["campos"].push({
                "animal": root._animalTexts[j], "campo": j + 1,
                "par": paresArr[j], "droga": root._drogaTexts[j],
                "exploração": {
                    "objA_total_s": t0.toFixed(1), "objB_total_s": t1.toFixed(1),
                    "objA_bouts": b0, "objB_bouts": b1,
                    "objA_n_bouts": b0.length, "objB_n_bouts": b1.length,
                    "DI": (t0 + t1 > 0) ? ((t1 - t0) / (t0 + t1)).toFixed(3) : "NaN"
                },
                "movimento": {
                    "distancia_total_m":   (root.sessionTotalDistance[j] || 0).toFixed(3),
                    "velocidade_media_ms": (root.sessionAvgVelocity[j]   || 0).toFixed(3)
                },
                "porMinuto": root.sessionPerMinuteData[j] || []
            })
        }
        var animaisStr = root._animalTexts.slice(0, root.numCampos)
            .filter(function(a) { return a.length > 0 }).join("-")
        ExperimentManager.saveSessionMetadata(
            root.experimentName, JSON.stringify(sessionMeta), fase + "_" + animaisStr)

        // Post to animal lifecycle API (fire-and-forget)
        for (var k = 0; k < root.numCampos; k++) {
            var dbId = root._animalDbIds[k]
            if (dbId <= 0 || !root._animalTexts[k]) continue
            var zk0 = k * 2, zk1 = k * 2 + 1
            var tkA = root.sessionExplorationTimes[zk0] || 0
            var tkB = root.sessionExplorationTimes[zk1] || 0
            var boutsA = (root.sessionExplorationBouts[zk0] || []).length
            var boutsB = (root.sessionExplorationBouts[zk1] || []).length
            var tot = tkA + tkB
            var dist = parseFloat((root.sessionTotalDistance[k] || 0).toFixed(3))
            var vel = parseFloat((root.sessionAvgVelocity[k] || 0).toFixed(3))
            root._postEvent(dbId, "NOR — " + fase, {
                apparatus: "nor", day: fase,
                day_index: parseInt(dia, 10),
                experiment_name: root.experimentName,
                field: k + 1,
                pair: pares[k],
                treatment: root.includeDrug ? (root._drogaTexts[k] || "") : "",
                exploration_a_s: parseFloat(tkA.toFixed(2)),
                exploration_b_s: parseFloat(tkB.toFixed(2)),
                exploration_total_s: parseFloat(tot.toFixed(2)),
                bouts_a: boutsA,
                bouts_b: boutsB,
                di: tot > 0 ? parseFloat(((tkB - tkA) / tot).toFixed(3)) : 0,
                distance_m: dist,
                avg_speed_ms: vel,
                video_path: v
            })
        }

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
            Text { text: "🎬"; font.pixelSize: 20 }
            ColumnLayout {
                spacing: 2
                Text {
                    text: LanguageManager.tr3("Sessao Concluida", "Session Completed", "Sesion Completada")
                    color: ThemeManager.textPrimary; font.pixelSize: 16; font.weight: Font.Bold
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
                Text {
                    text: LanguageManager.tr3("Object Recognition - set day and animals", "Object Recognition - set day and animals", "Reconocimiento de Objetos - defina dia y animales")
                    color: "#ab3d4c"; font.pixelSize: 11
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
                text: LanguageManager.tr3("SESSION DAY", "SESSION DAY", "DIA DE SESION")
                color: ThemeManager.textSecondary
                font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 1.4
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            RowLayout {
                spacing: 10

                ComboBox {
                    id: dayCombo
                    model: root.localizedDayNames()
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
                        border.color: dayCombo.activeFocus ? "#ab3d4c" : ThemeManager.border; border.width: 1
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                    }
                    delegate: ItemDelegate {
                        width: dayCombo.width
                        contentItem: Text {
                            text: modelData
                            color: dayCombo.currentIndex === index ? "#e05060" : ThemeManager.textPrimary
                            font.pixelSize: 13; font.weight: Font.Bold
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            color: hovered ? ThemeManager.surfaceAlt : ThemeManager.surfaceDim
                            Behavior on color { ColorAnimation { duration: 100 } }
                        }
                    }
                    popup: Popup {
                        y: dayCombo.height; width: dayCombo.width; padding: 0
                        background: Rectangle { color: ThemeManager.surfaceDim; border.color: "#ab3d4c"; radius: 8; Behavior on color { ColorAnimation { duration: 200 } } }
                        contentItem: ListView { implicitHeight: contentHeight; model: dayCombo.delegateModel; clip: true }
                    }
                }

                Rectangle {
                    radius: 6; color: "#1f0d10"
                    border.color: "#ab3d4c"; border.width: 1
                    implicitWidth: diaLbl.implicitWidth + 16; height: 34
                    Text {
                        id: diaLbl; anchors.centerIn: parent
                        text: LanguageManager.tr3("Day ", "Day ", "Dia ") + (dayCombo.currentIndex + 1)
                        color: "#e05060"; font.pixelSize: 13; font.weight: Font.Bold
                    }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } } }

        // ── Campos ────────────────────────────────────────────────────────
        CampoBlock {
            id: c1
            Layout.fillWidth: true; visible: root.numCampos >= 1; campoIndex: 0
            pairLabel: root.pair1; includeDrug: root.includeDrug
            onAnimalChanged: function(txt)       { var a = root._animalTexts.slice(); a[0] = txt;  root._animalTexts = a }
            onAnimalPicked:  function(txt, dbId) { var a = root._animalTexts.slice(); a[0] = txt;  root._animalTexts = a
                                                   var d = root._animalDbIds.slice();  d[0] = dbId; root._animalDbIds  = d }
            onDrogaChanged:  function(txt)       { var d = root._drogaTexts.slice();  d[0] = txt;  root._drogaTexts  = d }
        }
        CampoBlock {
            id: c2
            Layout.fillWidth: true; visible: root.numCampos >= 2; campoIndex: 1
            pairLabel: root.pair2; includeDrug: root.includeDrug
            onAnimalChanged: function(txt)       { var a = root._animalTexts.slice(); a[1] = txt;  root._animalTexts = a }
            onAnimalPicked:  function(txt, dbId) { var a = root._animalTexts.slice(); a[1] = txt;  root._animalTexts = a
                                                   var d = root._animalDbIds.slice();  d[1] = dbId; root._animalDbIds  = d }
            onDrogaChanged:  function(txt)       { var d = root._drogaTexts.slice();  d[1] = txt;  root._drogaTexts  = d }
        }
        CampoBlock {
            id: c3
            Layout.fillWidth: true; visible: root.numCampos >= 3; campoIndex: 2
            pairLabel: root.pair3; includeDrug: root.includeDrug
            onAnimalChanged: function(txt)       { var a = root._animalTexts.slice(); a[2] = txt;  root._animalTexts = a }
            onAnimalPicked:  function(txt, dbId) { var a = root._animalTexts.slice(); a[2] = txt;  root._animalTexts = a
                                                   var d = root._animalDbIds.slice();  d[2] = dbId; root._animalDbIds  = d }
            onDrogaChanged:  function(txt)       { var d = root._drogaTexts.slice();  d[2] = txt;  root._drogaTexts  = d }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } } }

        // ── Botões ────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true; spacing: 10
            Item { Layout.fillWidth: true }
            GhostButton { text: LanguageManager.tr3("Cancelar", "Cancel", "Cancelar"); onClicked: root.close() }
            Button {
                text: LanguageManager.tr3("Salvar Sessao", "Save Session", "Guardar Sesion")
                onClicked: root.doInsert()
                background: Rectangle {
                    radius: 8; color: parent.hovered ? "#8a2e3b" : "#ab3d4c"
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

        property int    campoIndex:  0
        property string pairLabel:   ""
        property bool   includeDrug: true

        // Exposes the AnimalSearchField so parent can call picker.clear() on reopen
        readonly property alias picker: animalPicker

        signal animalChanged(string txt)
        signal animalPicked(string txt, int dbId)
        signal drogaChanged(string txt)

        ColumnLayout {
            id: blkCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
            spacing: 10

            RowLayout {
                spacing: 12

                Rectangle {
                    width: 32; height: 22; radius: 5
                    color: "#1f0d10"; border.color: "#ab3d4c"; border.width: 1.5
                    Text {
                        anchors.centerIn: parent
                        text: "C" + (blk.campoIndex + 1)
                        color: "#e05060"; font.pixelSize: 11; font.weight: Font.Bold
                    }
                }

                ColumnLayout {
                    spacing: 1
                    Text {
                        text: blk.pairLabel !== ""
                              ? (LanguageManager.tr3("Par ", "Pair ", "Par ") + blk.pairLabel)
                              : (LanguageManager.tr3("Campo ", "Field ", "Campo ") + (blk.campoIndex + 1))
                        color: ThemeManager.textPrimary
                        font.pixelSize: 15; font.weight: Font.Bold
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                    Text {
                        text: LanguageManager.tr3("Par de objetos", "Object pair", "Par de objetos")
                        color: ThemeManager.textSecondary; font.pixelSize: 10
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                }

                Item { Layout.fillWidth: true }

                ColumnLayout {
                    spacing: 3
                    Text {
                        text: LanguageManager.tr3("ANIMAL", "ANIMAL", "ANIMAL")
                        color: ThemeManager.textSecondary
                        font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 1.2
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                    AnimalSearchField {
                        id: animalPicker
                        width: 170; height: 30
                        accentColor: "#ab3d4c"
                        onPicked:     function(internalId, dbId) { blk.animalChanged(internalId); blk.animalPicked(internalId, dbId) }
                        onTextEdited: function(text)              { blk.animalChanged(text) }
                    }
                }
            }

            RowLayout {
                visible: blk.includeDrug; spacing: 12
                Item { width: 44 }
                ColumnLayout {
                    spacing: 3
                    Text {
                        text: LanguageManager.tr3("TRATAMENTO", "TREATMENT", "TRATAMIENTO")
                        color: ThemeManager.textSecondary
                        font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 1.2
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                    TextField {
                        id: drogaField
                        width: 260; height: 30
                        placeholderText: LanguageManager.tr3("Ex.: Salina, Midazolam...", "Ex.: Saline, Midazolam...", "Ej.: Salina, Midazolam...")
                        color: ThemeManager.textPrimary
                        placeholderTextColor: ThemeManager.textTertiary
                        font.pixelSize: 12
                        leftPadding: 10; rightPadding: 10; topPadding: 6; bottomPadding: 6
                        background: Rectangle {
                            radius: 7; color: ThemeManager.surface
                            Behavior on color { ColorAnimation { duration: 200 } }
                            border.color: drogaField.activeFocus ? "#ab3d4c" : ThemeManager.border; border.width: 1
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
