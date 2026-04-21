import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import "../core"
import "../core/Theme"

// ── BoutEditorPanel ───────────────────────────────────────────────────────────
// Painel de revisão e auditoria de bouts comportamentais.
// Recebe frameData (array de {frameIdx, ruleLabel, movNose, movBody, movMean})
// e fps, computa bouts, permite filtrar, editar labels, deletar, split/merge e
// exportar CSV/JSON com histórico original vs editado.
Rectangle {
    id: root

    property var    frameData:      []      // [{frameIdx, ruleLabel, movNose, movBody, movMean}]
    property double fps:            30.0
    property int    campo:          0
    property string experimentPath: ""
    property string sessionLabel:   ""      // ex: "session_20260421_143000"

    color: "transparent"

    // ── Nomenclatura ──────────────────────────────────────────────────────────
    readonly property var behaviorNames:  ["Walking", "Sniffing", "Grooming", "Resting", "Rearing"]
    readonly property var behaviorColors: ["#4caf50", "#2196f3", "#ff9800", "#9c27b0", "#f44336"]
    readonly property int labelDeleted: 99

    // ── Estado interno ────────────────────────────────────────────────────────
    property var _bouts:         []   // array de bout objects (estado atual)
    property var _originalBouts: []   // snapshot imutável ao carregar
    property var _undoStack:     []   // array de snapshots para undo
    property int _selectedIdx:   -1   // índice do bout selecionado na lista filtrada
    property var _filteredBouts: []   // subconjunto de _bouts após filtros

    // Filtros
    property int    _filterLabel:     -1   // -1 = todos
    property double _filterTimeStart: -1
    property double _filterTimeEnd:   -1
    property string _filterText:      ""

    // ── Carrega e computa bouts ao receber frameData ──────────────────────────
    onFrameDataChanged: {
        if (frameData && frameData.length > 0)
            _loadBouts()
    }

    function _loadBouts() {
        var computed = _computeBouts(frameData)
        _bouts = computed
        // Deep copy para preservar original
        _originalBouts = JSON.parse(JSON.stringify(computed))
        _undoStack = []
        _selectedIdx = -1
        _applyFilters()
    }

    function _computeBouts(frames) {
        if (!frames || frames.length === 0) return []
        var bouts = []
        var id = 0
        var f0 = frames[0]
        var cur = { label: f0.ruleLabel, startFrame: f0.frameIdx,
                    endFrame: f0.frameIdx, movNoseSum: f0.movNose,
                    movBodySum: f0.movBody, movMeanSum: f0.movMean, count: 1 }

        for (var i = 1; i < frames.length; i++) {
            var f = frames[i]
            if (f.ruleLabel !== cur.label) {
                bouts.push(_makeBout(id++, cur))
                cur = { label: f.ruleLabel, startFrame: f.frameIdx,
                        endFrame: f.frameIdx, movNoseSum: f.movNose,
                        movBodySum: f.movBody, movMeanSum: f.movMean, count: 1 }
            } else {
                cur.endFrame    = f.frameIdx
                cur.movNoseSum += f.movNose
                cur.movBodySum += f.movBody
                cur.movMeanSum += f.movMean
                cur.count++
            }
        }
        bouts.push(_makeBout(id, cur))
        return bouts
    }

    function _makeBout(id, cur) {
        var startSec = cur.startFrame / fps
        var endSec   = (cur.endFrame + 1) / fps
        return {
            id:            id,
            originalLabel: cur.label,
            currentLabel:  cur.label,
            startFrame:    cur.startFrame,
            endFrame:      cur.endFrame,
            startSec:      startSec,
            endSec:        endSec,
            durationSec:   endSec - startSec,
            avgMovNose:    cur.count > 0 ? (cur.movNoseSum / cur.count) : 0,
            avgMovBody:    cur.count > 0 ? (cur.movBodySum / cur.count) : 0,
            avgMovMean:    cur.count > 0 ? (cur.movMeanSum / cur.count) : 0,
            editedAt:      "",
            deleted:       false
        }
    }

    function _applyFilters() {
        var result = []
        for (var i = 0; i < _bouts.length; i++) {
            var b = _bouts[i]
            if (b.deleted) continue
            if (_filterLabel !== -1 && b.currentLabel !== _filterLabel) continue
            if (_filterTimeStart >= 0 && b.endSec < _filterTimeStart) continue
            if (_filterTimeEnd >= 0 && b.startSec > _filterTimeEnd) continue
            if (_filterText !== "") {
                var name = _labelName(b.currentLabel).toLowerCase()
                if (name.indexOf(_filterText.toLowerCase()) < 0) continue
            }
            result.push(b)
        }
        _filteredBouts = result
        _selectedIdx = -1
    }

    function _labelName(label) {
        if (label === labelDeleted) return "Deletado"
        if (label >= 0 && label < behaviorNames.length) return behaviorNames[label]
        return "?"
    }
    function _labelColor(label) {
        if (label >= 0 && label < behaviorColors.length) return behaviorColors[label]
        return "#888"
    }

    // ── Operações de edição ───────────────────────────────────────────────────

    function _pushUndo() {
        var stack = _undoStack.slice()
        stack.push(JSON.parse(JSON.stringify(_bouts)))
        if (stack.length > 30) stack.shift()
        _undoStack = stack
    }

    function editLabel(boutId, newLabel) {
        _pushUndo()
        var arr = _bouts.slice()
        for (var i = 0; i < arr.length; i++) {
            if (arr[i].id === boutId) {
                var b = Object.assign({}, arr[i])
                b.currentLabel = newLabel
                b.editedAt     = new Date().toISOString()
                arr[i] = b
                break
            }
        }
        _bouts = arr
        _applyFilters()
    }

    function deleteBout(boutId) {
        _pushUndo()
        var arr = _bouts.slice()
        for (var i = 0; i < arr.length; i++) {
            if (arr[i].id === boutId) {
                var b = Object.assign({}, arr[i])
                b.deleted  = true
                b.editedAt = new Date().toISOString()
                arr[i] = b
                break
            }
        }
        _bouts = arr
        _applyFilters()
    }

    function splitBout(boutId) {
        _pushUndo()
        var arr   = _bouts.slice()
        var idx   = -1
        for (var i = 0; i < arr.length; i++) { if (arr[i].id === boutId) { idx = i; break } }
        if (idx < 0) return
        var b = arr[idx]
        if (b.endFrame - b.startFrame < 2) return   // muito curto para dividir

        var midFrame = Math.floor((b.startFrame + b.endFrame) / 2)
        var midSec   = (midFrame + 1) / fps
        var maxId    = 0
        for (var j = 0; j < arr.length; j++) maxId = Math.max(maxId, arr[j].id)

        var b1 = Object.assign({}, b, {
            endFrame: midFrame, endSec: midSec,
            durationSec: midSec - b.startSec, editedAt: new Date().toISOString()
        })
        var b2 = Object.assign({}, b, {
            id: maxId + 1, startFrame: midFrame + 1,
            startSec: midSec, durationSec: b.endSec - midSec, editedAt: new Date().toISOString()
        })
        arr.splice(idx, 1, b1, b2)
        _bouts = arr
        _applyFilters()
    }

    function mergeWithNext(boutId) {
        _pushUndo()
        var arr = _bouts.slice()
        // Encontra bout e o próximo não-deletado
        var idxA = -1, idxB = -1
        for (var i = 0; i < arr.length; i++) {
            if (arr[i].id === boutId && !arr[i].deleted) { idxA = i; break }
        }
        if (idxA < 0) return
        for (var j = idxA + 1; j < arr.length; j++) {
            if (!arr[j].deleted) { idxB = j; break }
        }
        if (idxB < 0) return

        var a = arr[idxA], bv = arr[idxB]
        var totalFrames = (a.endFrame - a.startFrame + 1) + (bv.endFrame - bv.startFrame + 1)
        var merged = Object.assign({}, a, {
            endFrame:   bv.endFrame,
            endSec:     bv.endSec,
            durationSec: bv.endSec - a.startSec,
            avgMovBody: (a.avgMovBody * (a.endFrame - a.startFrame + 1)
                         + bv.avgMovBody * (bv.endFrame - bv.startFrame + 1)) / totalFrames,
            avgMovNose: (a.avgMovNose * (a.endFrame - a.startFrame + 1)
                         + bv.avgMovNose * (bv.endFrame - bv.startFrame + 1)) / totalFrames,
            editedAt: new Date().toISOString()
        })
        arr.splice(idxA, 1, merged)
        arr.splice(idxB > idxA ? idxB : idxB, 1)  // remove o segundo
        _bouts = arr
        _applyFilters()
    }

    function undo() {
        if (_undoStack.length === 0) return
        var stack = _undoStack.slice()
        var prev  = stack.pop()
        _undoStack = stack
        _bouts     = prev
        _applyFilters()
    }

    // ── Exportação ────────────────────────────────────────────────────────────

    function exportReviewCsv(path) {
        var lines = ["\xEF\xBB\xBF" +
            "bout_id,start_frame,end_frame,start_s,end_s,duration_s," +
            "original_label,edited_label,edited_at,avg_mov_body,avg_mov_nose"]
        for (var i = 0; i < _bouts.length; i++) {
            var b = _bouts[i]
            var origName = b.originalLabel >= 0 && b.originalLabel < behaviorNames.length
                           ? behaviorNames[b.originalLabel] : "?"
            var curName  = b.deleted ? "Deleted"
                           : (b.currentLabel >= 0 && b.currentLabel < behaviorNames.length
                              ? behaviorNames[b.currentLabel] : "?")
            lines.push([
                b.id, b.startFrame, b.endFrame,
                b.startSec.toFixed(3), b.endSec.toFixed(3), b.durationSec.toFixed(3),
                origName, curName, b.editedAt,
                b.avgMovBody.toFixed(3), b.avgMovNose.toFixed(3)
            ].join(","))
        }
        return lines.join("\n")
    }

    function exportReviewJson() {
        var bouts = []
        for (var i = 0; i < _bouts.length; i++) {
            var b = _bouts[i]
            bouts.push({
                bout_id:        b.id,
                start_frame:    b.startFrame,
                end_frame:      b.endFrame,
                start_s:        parseFloat(b.startSec.toFixed(3)),
                end_s:          parseFloat(b.endSec.toFixed(3)),
                duration_s:     parseFloat(b.durationSec.toFixed(3)),
                original_label: b.originalLabel >= 0 && b.originalLabel < behaviorNames.length
                                 ? behaviorNames[b.originalLabel] : "?",
                edited_label:   b.deleted ? "Deleted"
                                 : (b.currentLabel >= 0 && b.currentLabel < behaviorNames.length
                                    ? behaviorNames[b.currentLabel] : "?"),
                edited:         b.editedAt !== "" || b.deleted,
                edited_at:      b.editedAt || null,
                avg_mov_body:   parseFloat(b.avgMovBody.toFixed(3)),
                avg_mov_nose:   parseFloat(b.avgMovNose.toFixed(3))
            })
        }
        return JSON.stringify({
            session:     sessionLabel,
            campo:       campo,
            fps:         fps,
            exported_at: new Date().toISOString(),
            bouts:       bouts
        }, null, 2)
    }

    // Salva string em arquivo via FileDialog path
    function _saveText(path, content) {
        var xhr = new XMLHttpRequest()
        // Usa Qt.openUrlExternally como fallback; escrita real precisa de ExperimentManager
        // Emite sinal para o Dashboard lidar com a escrita
        exportReady(path, content)
    }

    signal exportReady(string path, string content)

    // ── UI ────────────────────────────────────────────────────────────────────

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        // ── Barra de filtros ─────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 44
            color: ThemeManager.surfaceDim
            radius: 8
            border.color: ThemeManager.border; border.width: 1

            RowLayout {
                anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                spacing: 6

                Text {
                    text: LanguageManager.tr3("Filtrar:", "Filter:", "Filtrar:")
                    color: ThemeManager.textSecondary; font.pixelSize: 11
                }

                // Botões de label
                Repeater {
                    model: behaviorNames.length + 1   // +1 para "Todos"
                    delegate: Rectangle {
                        height: 26; width: labelFilterText.implicitWidth + 16; radius: 5
                        property bool active: index === 0
                            ? root._filterLabel === -1
                            : root._filterLabel === (index - 1)
                        color: active ? behaviorColors[index - 1] || ThemeManager.accent
                                      : ThemeManager.surfaceAlt
                        border.color: active ? "transparent" : ThemeManager.border; border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            id: labelFilterText
                            anchors.centerIn: parent
                            text: index === 0 ? LanguageManager.tr3("Todos", "All", "Todos")
                                              : behaviorNames[index - 1]
                            color: active ? "white" : ThemeManager.textSecondary
                            font.pixelSize: 10; font.weight: active ? Font.Bold : Font.Normal
                        }
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root._filterLabel = index === 0 ? -1 : (index - 1)
                                root._applyFilters()
                            }
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                // Contador
                Text {
                    text: root._filteredBouts.length + " bouts"
                    color: ThemeManager.textSecondary; font.pixelSize: 11
                }

                // Undo
                Rectangle {
                    width: 28; height: 28; radius: 6
                    color: undoMa.containsMouse && root._undoStack.length > 0
                           ? ThemeManager.surfaceAlt : "transparent"
                    border.color: ThemeManager.border; border.width: 1
                    enabled: root._undoStack.length > 0
                    opacity: enabled ? 1.0 : 0.4
                    Text {
                        anchors.centerIn: parent; text: "↶"
                        color: ThemeManager.textPrimary; font.pixelSize: 14
                    }
                    MouseArea {
                        id: undoMa; anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.undo()
                    }
                }
            }
        }

        // ── Layout principal: tabela + detalhe ───────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 8

            // ── Tabela de bouts ──────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: ThemeManager.surfaceDim
                radius: 8
                border.color: ThemeManager.border; border.width: 1
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    // Cabeçalho
                    Rectangle {
                        Layout.fillWidth: true; height: 32
                        color: ThemeManager.surface
                        radius: 8
                        // Cobre parte inferior do radius
                        Rectangle {
                            anchors {
                                bottom: parent.bottom
                                left: parent.left
                                right: parent.right
                            }
                            height: 8
                            color: ThemeManager.surface
                        }

                        RowLayout {
                            anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                            spacing: 0
                            Text { text: "#";       color: ThemeManager.textSecondary; font.pixelSize: 10; Layout.preferredWidth: 28 }
                            Text { text: LanguageManager.tr3("Comportamento", "Behavior", "Comportamiento"); color: ThemeManager.textSecondary; font.pixelSize: 10; Layout.fillWidth: true }
                            Text { text: LanguageManager.tr3("Início (s)", "Start (s)", "Inicio (s)"); color: ThemeManager.textSecondary; font.pixelSize: 10; Layout.preferredWidth: 62; horizontalAlignment: Text.AlignRight }
                            Text { text: LanguageManager.tr3("Duração (s)", "Duration (s)", "Duración (s)"); color: ThemeManager.textSecondary; font.pixelSize: 10; Layout.preferredWidth: 68; horizontalAlignment: Text.AlignRight }
                            Text { text: LanguageManager.tr3("Mov Body", "Mov Body", "Mov Body"); color: ThemeManager.textSecondary; font.pixelSize: 10; Layout.preferredWidth: 60; horizontalAlignment: Text.AlignRight }
                            Text { text: LanguageManager.tr3("Ações", "Actions", "Acciones"); color: ThemeManager.textSecondary; font.pixelSize: 10; Layout.preferredWidth: 80; horizontalAlignment: Text.AlignHCenter }
                        }
                    }

                    // Lista
                    ListView {
                        id: boutList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: root._filteredBouts
                        ScrollBar.vertical: ScrollBar {}

                        // Mensagem vazia
                        Text {
                            anchors.centerIn: parent
                            visible: boutList.count === 0
                            text: root._bouts.length === 0
                                ? LanguageManager.tr3("Execute a análise para revisar bouts.", "Run analysis to review bouts.", "Ejecute el análisis para revisar bouts.")
                                : LanguageManager.tr3("Nenhum bout corresponde ao filtro.", "No bouts match the filter.", "Ningun bout coincide con el filtro.")
                            color: ThemeManager.textSecondary; font.pixelSize: 12
                        }

                        delegate: Rectangle {
                            id: boutDelegate
                            width: boutList.width; height: 38
                            property var bout: modelData
                            property bool isSelected: root._selectedIdx === index
                            color: isSelected
                                   ? Qt.rgba(0.15, 0.55, 0.25, 0.18)
                                   : (rowMa.containsMouse ? ThemeManager.surfaceAlt : "transparent")
                            border.color: isSelected ? ThemeManager.success : "transparent"
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 100 } }

                            RowLayout {
                                anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                                spacing: 0

                                // #
                                Text {
                                    text: bout.id
                                    color: ThemeManager.textSecondary; font.pixelSize: 10
                                    Layout.preferredWidth: 28
                                }

                                // Label colorido
                                RowLayout {
                                    Layout.fillWidth: true; spacing: 5
                                    Rectangle {
                                        width: 8; height: 8; radius: 4
                                        color: root._labelColor(bout.currentLabel)
                                    }
                                    Text {
                                        text: root._labelName(bout.currentLabel)
                                              + (bout.editedAt !== "" ? " *" : "")
                                        color: bout.editedAt !== ""
                                               ? "#d8c26a" : ThemeManager.textPrimary
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                    }
                                }

                                // Início
                                Text {
                                    text: bout.startSec.toFixed(1)
                                    color: ThemeManager.textSecondary; font.pixelSize: 10
                                    Layout.preferredWidth: 62; horizontalAlignment: Text.AlignRight
                                }

                                // Duração
                                Text {
                                    text: bout.durationSec.toFixed(2)
                                    color: ThemeManager.textSecondary; font.pixelSize: 10
                                    Layout.preferredWidth: 68; horizontalAlignment: Text.AlignRight
                                }

                                // AvgMovBody
                                Text {
                                    text: bout.avgMovBody.toFixed(1)
                                    color: ThemeManager.textSecondary; font.pixelSize: 10
                                    Layout.preferredWidth: 60; horizontalAlignment: Text.AlignRight
                                }

                                // Ações
                                RowLayout {
                                    Layout.preferredWidth: 80; spacing: 3

                                    // Editar label
                                    Rectangle {
                                        width: 22; height: 22; radius: 4
                                        color: editMa.containsMouse ? ThemeManager.surfaceAlt : "transparent"
                                        border.color: ThemeManager.border; border.width: 1
                                        Text { anchors.centerIn: parent; text: "✎"; color: ThemeManager.textSecondary; font.pixelSize: 12 }
                                        MouseArea {
                                            id: editMa; anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root._selectedIdx = index
                                                labelPopup.boutRef = bout
                                                labelPopup.open()
                                            }
                                        }
                                    }

                                    // Split
                                    Rectangle {
                                        width: 22; height: 22; radius: 4
                                        color: splitMa.containsMouse ? ThemeManager.surfaceAlt : "transparent"
                                        border.color: ThemeManager.border; border.width: 1
                                        enabled: bout.endFrame - bout.startFrame >= 2
                                        opacity: enabled ? 1.0 : 0.3
                                        Text { anchors.centerIn: parent; text: "✂"; color: ThemeManager.textSecondary; font.pixelSize: 12 }
                                        MouseArea {
                                            id: splitMa; anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            onClicked: root.splitBout(bout.id)
                                        }
                                    }

                                    // Merge com próximo
                                    Rectangle {
                                        width: 22; height: 22; radius: 4
                                        color: mergeMa.containsMouse ? ThemeManager.surfaceAlt : "transparent"
                                        border.color: ThemeManager.border; border.width: 1
                                        Text { anchors.centerIn: parent; text: "⇒"; color: ThemeManager.textSecondary; font.pixelSize: 12 }
                                        MouseArea {
                                            id: mergeMa; anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            onClicked: root.mergeWithNext(bout.id)
                                        }
                                    }

                                    // Deletar
                                    Rectangle {
                                        width: 22; height: 22; radius: 4
                                        color: delMa.containsMouse ? "#3d1515" : "transparent"
                                        border.color: ThemeManager.border; border.width: 1
                                        Text { anchors.centerIn: parent; text: "✕"; color: "#e57373"; font.pixelSize: 11; font.weight: Font.Bold }
                                        MouseArea {
                                            id: delMa; anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            onClicked: root.deleteBout(bout.id)
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                id: rowMa
                                anchors.fill: parent; hoverEnabled: true
                                onClicked: root._selectedIdx = index
                            }
                        }
                    }
                }
            }

            // ── Painel de detalhe ────────────────────────────────────────────
            Rectangle {
                Layout.preferredWidth: 190
                Layout.fillHeight: true
                color: ThemeManager.surfaceDim
                radius: 8
                border.color: ThemeManager.border; border.width: 1

                property var selBout: root._selectedIdx >= 0 && root._selectedIdx < root._filteredBouts.length
                                      ? root._filteredBouts[root._selectedIdx] : null

                ColumnLayout {
                    anchors { fill: parent; margins: 12 }
                    spacing: 10

                    Text {
                        text: LanguageManager.tr3("Detalhe", "Detail", "Detalle")
                        color: ThemeManager.textSecondary; font.pixelSize: 11; font.weight: Font.Bold
                    }

                    // Nenhum selecionado
                    Text {
                        visible: parent.parent.selBout === null
                        Layout.fillWidth: true
                        text: LanguageManager.tr3("Selecione um bout\nna tabela.", "Select a bout\nfrom the table.", "Seleccione un bout\nen la tabla.")
                        color: ThemeManager.textSecondary; font.pixelSize: 11
                        wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter
                    }

                    // Conteúdo do bout selecionado
                    ColumnLayout {
                        id: detailColumn
                        visible: parent.parent.selBout !== null
                        Layout.fillWidth: true
                        spacing: 7

                        property var selectedBout: parent.parent.selBout

                        // Label colorida
                        Rectangle {
                            Layout.fillWidth: true; height: 32; radius: 6
                            color: detailColumn.selectedBout ? root._labelColor(detailColumn.selectedBout.currentLabel) : "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: detailColumn.selectedBout ? root._labelName(detailColumn.selectedBout.currentLabel) : ""
                                color: "white"; font.pixelSize: 13; font.weight: Font.Bold
                            }
                        }

                        // Label original
                        RowLayout {
                            visible: detailColumn.selectedBout && detailColumn.selectedBout.currentLabel !== detailColumn.selectedBout.originalLabel
                            Layout.fillWidth: true
                            Text { text: LanguageManager.tr3("Original:", "Original:", "Original:"); color: ThemeManager.textSecondary; font.pixelSize: 10 }
                            Text {
                                text: detailColumn.selectedBout ? root._labelName(detailColumn.selectedBout.originalLabel) : ""
                                color: "#d8c26a"; font.pixelSize: 10; Layout.fillWidth: true
                                horizontalAlignment: Text.AlignRight
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border }

                        // Métricas
                        Repeater {
                            model: [
                                { label: LanguageManager.tr3("Início", "Start", "Inicio"),   value: detailColumn.selectedBout ? detailColumn.selectedBout.startSec.toFixed(2) + " s" : "" },
                                { label: LanguageManager.tr3("Fim",    "End",   "Fin"),      value: detailColumn.selectedBout ? detailColumn.selectedBout.endSec.toFixed(2)   + " s" : "" },
                                { label: LanguageManager.tr3("Duração","Duration","Duración"),value: detailColumn.selectedBout ? detailColumn.selectedBout.durationSec.toFixed(2)+" s" : "" },
                                { label: LanguageManager.tr3("Frames", "Frames", "Frames"),  value: detailColumn.selectedBout ? (detailColumn.selectedBout.endFrame - detailColumn.selectedBout.startFrame + 1) : "" },
                                { label: "Avg Mov Body", value: detailColumn.selectedBout ? detailColumn.selectedBout.avgMovBody.toFixed(2) : "" },
                                { label: "Avg Mov Nose", value: detailColumn.selectedBout ? detailColumn.selectedBout.avgMovNose.toFixed(2) : "" }
                            ]
                            delegate: RowLayout {
                                Layout.fillWidth: true
                                Text { text: modelData.label; color: ThemeManager.textSecondary; font.pixelSize: 10; Layout.fillWidth: true }
                                Text { text: modelData.value; color: ThemeManager.textPrimary;   font.pixelSize: 10; font.weight: Font.Medium }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border }

                        // Regra disparada
                        Text {
                            text: LanguageManager.tr3("Regra disparada:", "Rule fired:", "Regla disparada:")
                            color: ThemeManager.textSecondary; font.pixelSize: 10
                        }
                        Text {
                            visible: detailColumn.selectedBout !== null
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            font.pixelSize: 10
                            color: ThemeManager.textPrimary
                            text: {
                                if (!detailColumn.selectedBout) return ""
                                var lbl = detailColumn.selectedBout.originalLabel
                                if (lbl === 0) return LanguageManager.tr3("movBody > 2.0 px/frame\nou roll2s > 3.0", "movBody > 2.0 px/frame\nor roll2s > 3.0", "movBody > 2.0 px/frame\no roll2s > 3.0")
                                if (lbl === 1) return LanguageManager.tr3("Focinho dentro\nda zona do objeto", "Nose inside\nobject zone", "Nariz dentro\nde la zona del objeto")
                                if (lbl === 2) return LanguageManager.tr3("movBody < 1.5 e\nmovNose > 5.0", "movBody < 1.5 and\nmovNose > 5.0", "movBody < 1.5 y\nmovNose > 5.0")
                                if (lbl === 3) return LanguageManager.tr3("Velocidade\n< 0.05 m/s", "Velocity\n< 0.05 m/s", "Velocidad\n< 0.05 m/s")
                                if (lbl === 4) return LanguageManager.tr3("Focinho fora do\npolígono do chão", "Nose outside\nfloor polygon", "Nariz fuera del\npolígono del piso")
                                return "?"
                            }
                        }

                        // Editado em
                        Text {
                            visible: detailColumn.selectedBout && detailColumn.selectedBout.editedAt !== ""
                            Layout.fillWidth: true
                            text: detailColumn.selectedBout && detailColumn.selectedBout.editedAt !== ""
                                ? LanguageManager.tr3("Editado: ", "Edited: ", "Editado: ") + detailColumn.selectedBout.editedAt.substring(0, 10)
                                : ""
                            color: "#d8c26a"; font.pixelSize: 9
                            wrapMode: Text.Wrap
                        }
                    }

                    Item { Layout.fillHeight: true }

                    // Botões de exportação
                    Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border }

                    Text {
                        text: LanguageManager.tr3("Exportar revisão:", "Export review:", "Exportar revisión:")
                        color: ThemeManager.textSecondary; font.pixelSize: 10
                    }

                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 5

                        Rectangle {
                            Layout.fillWidth: true; height: 28; radius: 6
                            color: csvMa.containsMouse ? "#1a4d2e" : "#0e3320"
                            border.color: ThemeManager.success; border.width: 1
                            Text { anchors.centerIn: parent; text: "CSV"; color: ThemeManager.success; font.pixelSize: 11; font.weight: Font.Bold }
                            MouseArea {
                                id: csvMa; anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: csvSaveDialog.open()
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true; height: 28; radius: 6
                            color: jsonMa.containsMouse ? "#1a3a4d" : "#0e2633"
                            border.color: "#2196f3"; border.width: 1
                            Text { anchors.centerIn: parent; text: "JSON"; color: "#2196f3"; font.pixelSize: 11; font.weight: Font.Bold }
                            MouseArea {
                                id: jsonMa; anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: jsonSaveDialog.open()
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Popup de seleção de novo label ────────────────────────────────────────
    Popup {
        id: labelPopup
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: 240; modal: true; focus: true; closePolicy: Popup.CloseOnEscape

        property var boutRef: null

        background: Rectangle {
            radius: 10; color: ThemeManager.surface
            border.color: ThemeManager.border; border.width: 1
        }

        ColumnLayout {
            anchors { fill: parent; margins: 16 }
            spacing: 10

            Text {
                text: LanguageManager.tr3("Alterar classificação", "Change classification", "Cambiar clasificación")
                color: ThemeManager.textPrimary; font.pixelSize: 13; font.weight: Font.Bold
            }

            Repeater {
                model: behaviorNames
                delegate: Rectangle {
                    Layout.fillWidth: true; height: 34; radius: 6
                    color: lbMa.containsMouse ? Qt.rgba(0.15, 0.55, 0.25, 0.15) : ThemeManager.surfaceAlt
                    border.color: ThemeManager.border; border.width: 1
                    Behavior on color { ColorAnimation { duration: 100 } }

                    RowLayout {
                        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                        Rectangle { width: 10; height: 10; radius: 5; color: behaviorColors[index] }
                        Text { text: modelData; color: ThemeManager.textPrimary; font.pixelSize: 12; Layout.fillWidth: true }
                    }
                    MouseArea {
                        id: lbMa; anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (labelPopup.boutRef !== null)
                                root.editLabel(labelPopup.boutRef.id, index)
                            labelPopup.close()
                        }
                    }
                }
            }

            GhostButton {
                Layout.fillWidth: true
                text: LanguageManager.tr3("Cancelar", "Cancel", "Cancelar")
                onClicked: labelPopup.close()
            }
        }
    }

    // ── Diálogos de salvar ────────────────────────────────────────────────────
    FileDialog {
        id: csvSaveDialog
        title: LanguageManager.tr3("Salvar revisão CSV", "Save review CSV", "Guardar revisión CSV")
        fileMode: FileDialog.SaveFile
        nameFilters: ["CSV (*.csv)"]
        defaultSuffix: "csv"
        currentFolder: root.experimentPath !== "" ? "file:///" + root.experimentPath : ""
        onAccepted: root.exportReady(selectedFile.toString().replace("file:///",""), root.exportReviewCsv(""))
    }

    FileDialog {
        id: jsonSaveDialog
        title: LanguageManager.tr3("Salvar revisão JSON", "Save review JSON", "Guardar revisión JSON")
        fileMode: FileDialog.SaveFile
        nameFilters: ["JSON (*.json)"]
        defaultSuffix: "json"
        currentFolder: root.experimentPath !== "" ? "file:///" + root.experimentPath : ""
        onAccepted: root.exportReady(selectedFile.toString().replace("file:///",""), root.exportReviewJson())
    }
}
