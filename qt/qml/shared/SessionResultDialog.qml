// qml/SessionResultDialog.qml
// Post-recording NOR popup: user confirms animal IDs for each field.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../core"
import "../core/Theme"
import MindTrace.Backend 1.0

Popup {
    id: root

    // ── Data provided by the Dashboard ──────────────────────────────────
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
    property var    contextPatterns:  []

    // ── Session tracking data ──────────────────────────────────────────────
    property var sessionExplorationBouts: [[], [], [], [], [], []]
    property var sessionExplorationTimes: [0, 0, 0, 0, 0, 0]
    property var sessionTotalDistance:    [0.0, 0.0, 0.0]
    property var sessionAvgVelocity:      [0.0, 0.0, 0.0]
    property var sessionPerMinuteData:    [{}, {}, {}]

    function localizedDayName(dayName, index) {
        var normalized = String(dayName || "").trim().toLowerCase()
        if (normalized === "treino" || normalized === "training" || normalized === "entrenamiento")
            return LanguageManager.tr3("Treino", "Training", "Entrenamiento")
        if (normalized === "teste" || normalized === "test" || normalized === "prueba")
            return LanguageManager.tr3("Teste", "Test", "Prueba")
        return String(dayName || (LanguageManager.tr3("Dia ", "Day ", "Dia ") + (index + 1)))
    }

    function localizedDayNames() {
        var out = []
        if (root.dayNames && root.dayNames.length > 0) {
            for (var dayIdx = 0; dayIdx < root.dayNames.length; dayIdx++)
                out.push(localizedDayName(root.dayNames[dayIdx], dayIdx))
            return out
        }
        return [LanguageManager.tr3("Day 1", "Day 1", "Dia 1")]
    }

    function contextDisplayName(patternKey) {
        var key = String(patternKey || "").toLowerCase().trim()
        if (key === "horizontal") return LanguageManager.tr3("Listras horizontais", "Horizontal stripes", "Franjas horizontales")
        if (key === "vertical")   return LanguageManager.tr3("Listras verticais", "Vertical stripes", "Franjas verticales")
        if (key === "dots")       return LanguageManager.tr3("Bolinhas", "Dots", "Puntos")
        if (key === "triangles")  return LanguageManager.tr3("Triângulos", "Triangles", "Triângulos")
        if (key === "squares")    return LanguageManager.tr3("Quadrados", "Squares", "Cuadrados")
        return LanguageManager.tr3("Sem contexto", "No context", "Sin contexto")
    }

    property var _animalTexts:  ["", "", ""]
    property var _drogaTexts:   ["", "", ""]
    property var _animalDbIds:  [-1, -1, -1]

    function _postEvent(dbId, title, payload) {
        return
    }

    // ── Geometry ──────────────────────────────────────────────────────────
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

    // ── Insert function ───────────────────────────────────────────────────
    function doInsert() {
        var videoPathClean = root.videoPath.replace("file:///", "")
        var fase = dayCombo.currentText
        var dia  = String(dayCombo.currentIndex + 1)
        var includeContext = root.contextPatterns && root.contextPatterns.length > 0
        var rows = []
        var pares = [root.pair1, root.pair2, root.pair3]

        for (var campoIdx = 0; campoIdx < root.numCampos; campoIdx++) {
            var aText = root._animalTexts[campoIdx] || ""
            if (!aText) continue
            var contexto = root.contextDisplayName(root.contextPatterns[campoIdx] || "")
            var zoneIdx0 = campoIdx * 2, zoneIdx1 = campoIdx * 2 + 1
            var timeObjA = root.sessionExplorationTimes[zoneIdx0] || 0
            var timeObjB = pares[campoIdx].length > 1 ? (root.sessionExplorationTimes[zoneIdx1] || 0) : 0
            var totalTime = timeObjA + timeObjB
            var di = pares[campoIdx].length <= 1 ? "N/A" : (totalTime > 0 ? ((timeObjB - timeObjA) / totalTime).toFixed(3) : "0.000")
            var boutsObjA = (root.sessionExplorationBouts[zoneIdx0] || []).length
            var boutsObjB = pares[campoIdx].length > 1 ? (root.sessionExplorationBouts[zoneIdx1] || []).length : 0
            var row = [videoPathClean, aText, String(campoIdx + 1), dia]
            if (includeContext) row.push(contexto)
            row.push(pares[campoIdx],
                     timeObjA.toFixed(2), boutsObjA,
                     timeObjB.toFixed(2), boutsObjB,
                     totalTime.toFixed(2), di,
                     (root.sessionTotalDistance[campoIdx] || 0).toFixed(3),
                     (root.sessionAvgVelocity[campoIdx]   || 0).toFixed(3))
            if (root.includeDrug) row.push(root._drogaTexts[campoIdx] || "")
            rows.push(row)
        }

        ExperimentManager.insertSessionResult(root.experimentName, rows)

        var sessionMeta = {
            "timestamp": new Date().toISOString(),
            "fase": fase, "dia": dia, "videoPath": videoPathClean, "campos": []
        }
        var paresArr = [root.pair1, root.pair2, root.pair3]
        for (var metaIdx = 0; metaIdx < root.numCampos; metaIdx++) {
            if (!root._animalTexts[metaIdx]) continue
            var mZone0 = metaIdx * 2, mZone1 = metaIdx * 2 + 1
            var mBoutsA = root.sessionExplorationBouts[mZone0] || []
            var mBoutsB = root.sessionExplorationBouts[mZone1] || []
            var mTimeA  = root.sessionExplorationTimes[mZone0] || 0
            var mTimeB  = root.sessionExplorationTimes[mZone1] || 0
            sessionMeta.campos.push({
                "animal": root._animalTexts[metaIdx], "campo": metaIdx + 1,
                "contexto": root.contextDisplayName(root.contextPatterns[metaIdx] || ""),
                "par": paresArr[metaIdx], "droga": root._drogaTexts[metaIdx],
                "exploração": {
                    "objA_total_s": mTimeA.toFixed(1), "objB_total_s": mTimeB.toFixed(1),
                    "objA_bouts": mBoutsA, "objB_bouts": mBoutsB,
                    "objA_n_bouts": mBoutsA.length, "objB_n_bouts": mBoutsB.length,
                    "DI": (mTimeA + mTimeB > 0) ? ((mTimeB - mTimeA) / (mTimeA + mTimeB)).toFixed(3) : "NaN"
                },
                "movimento": {
                    "distância_total_m":   (root.sessionTotalDistance[metaIdx] || 0).toFixed(3),
                    "velocidade_media_ms": (root.sessionAvgVelocity[metaIdx]   || 0).toFixed(3)
                },
                "porMinuto": root.sessionPerMinuteData[metaIdx] || []
            })
        }
        var animaisStr = root._animalTexts.slice(0, root.numCampos)
            .filter(function(a) { return a.length > 0 }).join("-")
        ExperimentManager.saveSessionMetadata(
            root.experimentName, JSON.stringify(sessionMeta), fase + "_" + animaisStr)

        // Post to animal lifecycle API (fire-and-forget)
        for (var apiIdx = 0; apiIdx < root.numCampos; apiIdx++) {
            var dbId = root._animalDbIds[apiIdx]
            if (dbId <= 0 || !root._animalTexts[apiIdx]) continue
            var aZone0 = apiIdx * 2, aZone1 = apiIdx * 2 + 1
            var aTimeA = root.sessionExplorationTimes[aZone0] || 0
            var aTimeB = root.sessionExplorationTimes[aZone1] || 0
            var aTotalTime = aTimeA + aTimeB
            var aDist   = parseFloat((root.sessionTotalDistance[apiIdx] || 0).toFixed(3))
            var aAvgVel = parseFloat((root.sessionAvgVelocity[apiIdx]  || 0).toFixed(3))
            _postEvent(dbId, "nor_session", {
                apparatus: "nor", day: fase,
                day_index: parseInt(dia, 10),
                experiment_name: root.experimentName,
                field: apiIdx + 1,
                context: root.contextDisplayName(root.contextPatterns[apiIdx] || ""),
                pair: pares[apiIdx],
                treatment: root.includeDrug ? (root._drogaTexts[apiIdx] || "") : "",
                exploration_a_s: parseFloat(aTimeA.toFixed(2)),
                exploration_b_s: parseFloat(aTimeB.toFixed(2)),
                exploration_total_s: parseFloat(aTotalTime.toFixed(2)),
                bouts_b: (root.sessionExplorationBouts[aZone1] || []).length,
                di: aTotalTime > 0 ? parseFloat(((aTimeB - aTimeA) / aTotalTime).toFixed(3)) : 0,
                distance_m: aDist,
                avg_speed_ms: aAvgVel,
                video_path: videoPathClean
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
                    text: LanguageManager.tr3("Sessão Concluida", "Session Completed", "Sesion Completada")
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

        // ── Session day ───────────────────────────────────────────────────
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

        // ── Fields ────────────────────────────────────────────────────────
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

        // ── Buttons ───────────────────────────────────────────────────────
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

    // ── Component: per-field block ────────────────────────────────────────
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
