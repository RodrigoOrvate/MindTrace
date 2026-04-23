// qml/cc/CCMetadataDialog.qml
// Popup pós-sessão CC: coleta metadados (animal, dia, droga) e persiste CSV + JSON.
// Sem fase TR/RA/TT — CC tem sessões numeradas (Dia 1, Dia 2…).

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../core"
import "../core/Theme"
import "../shared"
import MindTrace.Backend 1.0

Popup {
    id: root

    // ── Dados injetados pelo CCDashboard ─────────────────────────────────
    property string experimentName:  ""
    property string experimentPath:  ""
    property string videoPath:       ""
    property int    numCampos:       3
    property bool   includeDrug:     true

    // Resultados da sessão (vindos do LiveRecording)
    property var totalDistance: [0.0, 0.0, 0.0]
    property var avgVelocity:   [0.0, 0.0, 0.0]
    property var perMinuteData: [[], [], []]
    property var behaviorCounts: [{}, {}, {}]
    property int sessionMinutes: 5   // duração real da sessão em minutos

    // Textos dos campos (preenchidos pelos CampoBlock via onAnimalChanged / onDrogaChanged)
    property var _animalTexts:  ["", "", ""]
    property var _drogaTexts:   ["", "", ""]
    property var _animalDbIds:  [-1, -1, -1]

    function _postEvent(dbId, title, payload) {
        return
    }

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

    // ── Geometria ─────────────────────────────────────────────────────────
    anchors.centerIn: parent
    width:  540
    height: mainLayout.implicitHeight + 48
    modal:  true
    focus:  true
    closePolicy: Popup.CloseOnEscape

    property var dayNames:    []

    onOpened: {
        dayCombo.currentIndex = 0
        root._animalTexts = ["", "", ""]
        root._drogaTexts  = ["", "", ""]
        root._animalDbIds = [-1, -1, -1]
        cc1.picker.clear(); cc2.picker.clear(); cc3.picker.clear()
    }

    background: Rectangle {
        radius: 14
        color: ThemeManager.surface
        Behavior on color { ColorAnimation { duration: 200 } }
        border.color: "#7a3dab"
        border.width: 1.5
    }

    // ── Função de inserção ────────────────────────────────────────────────
    function doInsert() {
        var v    = root.videoPath.replace("file:///", "")
        var fase = dayCombo.currentText
        var dia  = String(dayCombo.currentIndex + 1)

        var rows = []
        for (var ci = 0; ci < root.numCampos; ci++) {
            var aText = root._animalTexts[ci] || ""
            if (!aText) continue
            var bc = root.behaviorCounts[ci] || {}
            var cWalk  = bc["Walking"] || 0
            var cSniff = bc["Sniffing"] || 0
            var cGroom = bc["Grooming"] || 0
            var cRest  = bc["Resting"] || 0
            var cRear  = bc["Rearing"] || 0

            var row = [
                v,
                aText,
                String(ci + 1),
                dia,
                String(root.sessionMinutes),
                parseFloat((root.totalDistance[ci] || 0).toFixed(3)),
                parseFloat((root.avgVelocity[ci]   || 0).toFixed(3)),
                String(cWalk),
                String(cSniff),
                String(cGroom),
                String(cRest),
                String(cRear)
            ]
            if (root.includeDrug) row.push(root._drogaTexts[ci] || "")
            rows.push(row)
        }

        ExperimentManager.insertSessionResult(root.experimentName, rows)

        // JSON rico de sessão
        var sessionMeta = {
            "timestamp": new Date().toISOString(),
            "fase":      fase,
            "dia":       dia,
            "videoPath": v,
            "aparato":   "comportamento_complexo",
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
                "comportamentos_bouts": root.behaviorCounts[cj] || {},
                "porMinuto": root.perMinuteData[cj] || []
            })
        }

        var animaisStr = root._animalTexts
            .slice(0, root.numCampos)
            .filter(function(a) { return a.length > 0 })
            .join("-")
        ExperimentManager.saveSessionMetadata(
            root.experimentName, JSON.stringify(sessionMeta), "Dia" + dia + "_" + animaisStr)

        // Post to animal lifecycle API (fire-and-forget)
        for (var ck = 0; ck < root.numCampos; ck++) {
            var dbId = root._animalDbIds[ck]
            if (dbId <= 0 || !root._animalTexts[ck]) continue
            var bcK = root.behaviorCounts[ck] || {}
            var dist = parseFloat((root.totalDistance[ck] || 0).toFixed(3))
            var vel  = parseFloat((root.avgVelocity[ck]   || 0).toFixed(3))
            root._postEvent(dbId, "CC — " + fase, {
                apparatus: "comportamento_complexo", day: fase,
                day_index: parseInt(dia, 10),
                experiment_name: root.experimentName,
                field: ck + 1,
                treatment: root.includeDrug ? (root._drogaTexts[ck] || "") : "",
                session_minutes: root.sessionMinutes,
                distance_m:      dist,
                avg_speed_ms:    vel,
                velocity_ms:     vel,
                behavior_walking:  bcK["Walking"] || 0,
                behavior_sniffing: bcK["Sniffing"] || 0,
                behavior_grooming: bcK["Grooming"] || 0,
                behavior_resting:  bcK["Resting"] || 0,
                behavior_rearing:  bcK["Rearing"] || 0,
                behaviors:       bcK,
                video_path:      v
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
            Text { text: "🧩"; font.pixelSize: 20 }
            ColumnLayout {
                spacing: 2
                Text {
                    text: LanguageManager.tr3("Sessao Concluida", "Session Completed", "Sesion Completada")
                    color: ThemeManager.textPrimary
                    font.pixelSize: 16; font.weight: Font.Bold
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
                Text {
                    text: LanguageManager.tr3("Complex Behavior - set day and animals", "Complex Behavior - set day and animals", "Comportamiento Complejo - defina dia y animales")
                    color: "#7a3dab"; font.pixelSize: 11
                }
            }
            Item { Layout.fillWidth: true }
            Text {
                text: "✕"
                color: ThemeManager.textSecondary; font.pixelSize: 14
                Behavior on color { ColorAnimation { duration: 150 } }
                MouseArea {
                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: root.close()
                }
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
                        border.color: dayCombo.activeFocus ? "#7a3dab" : ThemeManager.border; border.width: 1
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                    }
                    delegate: ItemDelegate {
                        width: dayCombo.width
                        contentItem: Text {
                            text: modelData
                            color: dayCombo.currentIndex === index ? "#a855f7" : ThemeManager.textPrimary
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
                        background: Rectangle { color: ThemeManager.surfaceDim; border.color: "#7a3dab"; radius: 8; Behavior on color { ColorAnimation { duration: 200 } } }
                        contentItem: ListView { implicitHeight: contentHeight; model: dayCombo.delegateModel; clip: true }
                    }
                }

                Rectangle {
                    radius: 6; color: "#1a0d2e"
                    border.color: "#7a3dab"; border.width: 1
                    implicitWidth: diaLbl.implicitWidth + 16; height: 34
                    Text {
                        id: diaLbl; anchors.centerIn: parent
                        text: LanguageManager.tr3("Day ", "Day ", "Dia ") + (dayCombo.currentIndex + 1)
                        color: "#a855f7"; font.pixelSize: 13; font.weight: Font.Bold
                    }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } } }

        // ── Campos ────────────────────────────────────────────────────────
        CampoBlock {
            id: cc1
            Layout.fillWidth: true; visible: root.numCampos >= 1; campoIndex: 0
            dist: root.totalDistance[0] || 0; vel: root.avgVelocity[0] || 0; includeDrug: root.includeDrug
            onAnimalChanged: function(txt)       { var a = root._animalTexts.slice(); a[0] = txt;  root._animalTexts = a }
            onAnimalPicked:  function(txt, dbId) { var a = root._animalTexts.slice(); a[0] = txt;  root._animalTexts = a
                                                   var d = root._animalDbIds.slice();  d[0] = dbId; root._animalDbIds  = d }
            onDrogaChanged:  function(txt)       { var d = root._drogaTexts.slice();  d[0] = txt;  root._drogaTexts  = d }
        }
        CampoBlock {
            id: cc2
            Layout.fillWidth: true; visible: root.numCampos >= 2; campoIndex: 1
            dist: root.totalDistance[1] || 0; vel: root.avgVelocity[1] || 0; includeDrug: root.includeDrug
            onAnimalChanged: function(txt)       { var a = root._animalTexts.slice(); a[1] = txt;  root._animalTexts = a }
            onAnimalPicked:  function(txt, dbId) { var a = root._animalTexts.slice(); a[1] = txt;  root._animalTexts = a
                                                   var d = root._animalDbIds.slice();  d[1] = dbId; root._animalDbIds  = d }
            onDrogaChanged:  function(txt)       { var d = root._drogaTexts.slice();  d[1] = txt;  root._drogaTexts  = d }
        }
        CampoBlock {
            id: cc3
            Layout.fillWidth: true; visible: root.numCampos >= 3; campoIndex: 2
            dist: root.totalDistance[2] || 0; vel: root.avgVelocity[2] || 0; includeDrug: root.includeDrug
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
                    radius: 8; color: parent.hovered ? "#6a2d9a" : "#7a3dab"
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
                contentItem: Text {
                    text: parent.text; color: "#ffffff"
                    font.pixelSize: 13; font.weight: Font.Bold
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment:   Text.AlignVCenter
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

        readonly property alias picker: ccPicker

        signal animalChanged(string txt)
        signal animalPicked(string txt, int dbId)
        signal drogaChanged(string txt)

        ColumnLayout {
            id: blkCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
            spacing: 10

            // Linha principal: badge + stats + campo animal
            RowLayout {
                spacing: 12

                // Badge campo
                Rectangle {
                    width: 32; height: 22; radius: 5
                    color: "#1a0d2e"; border.color: "#7a3dab"; border.width: 1.5
                    Text {
                        anchors.centerIn: parent
                        text: "C" + (blk.campoIndex + 1)
                        color: "#a855f7"; font.pixelSize: 11; font.weight: Font.Bold
                    }
                }

                // Stats em destaque
                ColumnLayout {
                    spacing: 1
                    Text {
                        text: blk.dist.toFixed(2) + " m"
                        color: ThemeManager.textPrimary
                        font.pixelSize: 15; font.weight: Font.Bold
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                    Text {
                        text: blk.vel.toFixed(3) + " " + LanguageManager.tr3("m/s media", "m/s avg", "m/s media")
                        color: ThemeManager.textSecondary; font.pixelSize: 10
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                }

                Item { Layout.fillWidth: true }

                // Campo animal
                ColumnLayout {
                    spacing: 3
                    Text {
                        text: LanguageManager.tr3("ANIMAL", "ANIMAL", "ANIMAL")
                        color: ThemeManager.textSecondary
                        font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 1.2
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                    AnimalSearchField {
                        id: ccPicker
                        width: 170; height: 30
                        accentColor: "#7a3dab"
                        onPicked:     function(internalId, dbId) { blk.animalChanged(internalId); blk.animalPicked(internalId, dbId) }
                        onTextEdited: function(text)              { blk.animalChanged(text) }
                    }
                }
            }

            // Linha droga (opcional)
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
                            border.color: drogaField.activeFocus ? "#7a3dab" : ThemeManager.border; border.width: 1
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

