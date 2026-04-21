// qml/cc/CCDashboard.qml
// Dashboard Comportamento Complexo: sidebar + Arena + GravaÃ§Ã£o + ClassificaÃ§Ã£o + Dados.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtMultimedia
import "../core"
import "../core/Theme"
import "../shared"
import "../nor"
import "../ei"
import MindTrace.Backend 1.0
import MindTrace.Analysis 1.0
import MindTrace.Tracking 1.0

Item {
    id: root

    property string context:   ""
    property string arenaId:   ""
    property int    numCampos: 3
    property bool   searchMode: false
    property int    currentTabIndex: 0
    property string initialExperimentName: ""

    signal backRequested()

    Component.onCompleted: {
        if (root.searchMode) {
            ExperimentManager.loadAllContexts("comportamento_complexo")
        }
        if (initialExperimentName !== "") {
            experimentList.selectExperimentByName(initialExperimentName)
            innerTabs.currentIndex = 0
        }
    }

    property string pendingDeleteName: ""

    // â”€â”€ B-SOiD â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    property bool   bsoidRunning:   false
    property int    bsoidProgress:  0
    property var    bsoidGroups:    []   // lista de {clusterId, frameCount, percentage, ...}
    property var    bsoidGroupNames: []  // nomes personalizados dos clusters (editÃ¡veis)
    property string bsoidError:     ""
    property bool   bsoidDone:      false
    property double bsoidFps:       30.0
    property string bsoidVideoPath: ""
    property int    bsoidCampo:     0    // campo selecionado para anÃ¡lise (0=C1, 1=C2, 2=C3)

    // â”€â”€ EstatÃ­sticas de comportamento (computadas apÃ³s B-SOiD) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    property var    behaviorStats:    []   // [{name, seconds, bouts, color}]

    function computeBehaviorStats(fps) {
        var mapping = bsoidAnalyzer.getFrameMapping()
        var counts  = [0,0,0,0,0]
        var bouts   = [0,0,0,0,0]
        var prev    = -1
        for (var i = 0; i < mapping.length; i++) {
            var lbl = mapping[i].ruleLabel
            if (lbl >= 0 && lbl < 5) {
                counts[lbl]++
                if (lbl !== prev) bouts[lbl]++
            }
            prev = (lbl >= 0 && lbl < 5) ? lbl : prev
        }
        var names  = ["Walking","Zonas de objetos","Grooming","Resting","Rearing"]
        var colors = ["#8b5cf6","#f97316","#eab308","#3b82f6","#10b981"]
        var result = []
        var safeFps = fps > 0 ? fps : 30.0
        for (var j = 0; j < 5; j++) {
            result.push({ name: names[j], seconds: (counts[j] / safeFps).toFixed(1),
                          bouts: bouts[j], color: colors[j] })
        }
        return result
    }

    // â”€â”€ Snippets â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    property bool   snippetsRunning:  false
    property int    snippetsProgress: 0
    property bool   snippetsComplete: false
    property string snippetsOutDir:   ""
    property string snippetsError:    ""

    BSoidAnalyzer {
        id: bsoidAnalyzer
        onProgress: function(pct) { root.bsoidProgress = pct }
        onAnalysisReady: function(groups) {
            root.bsoidRunning  = false
            root.bsoidDone     = true
            root.bsoidGroups   = groups
            root.bsoidError    = ""
            root.bsoidProgress = 100
            // Inicializa nomes em branco para cada cluster
            var names = []
            for (var n = 0; n < groups.length; n++) names.push("")
            root.bsoidGroupNames = names
            // Computa estatÃ­sticas por comportamento
            root.behaviorStats = root.computeBehaviorStats(root.bsoidFps)
            // Preenche timeline dupla a partir de C++ (mais eficiente que iterar em JS)
            Qt.callLater(function() {
                ruleTimeline.clear()
                clusterTimeline.clear()
                // Cores para regras nativas â€” alinhadas com badges e legenda
                ruleTimeline.setLabelColor(0, "#8b5cf6")  // Walking  â†’ violeta
                ruleTimeline.setLabelColor(1, "#f97316")  // Zonas de objetos â†’ laranja
                ruleTimeline.setLabelColor(2, "#eab308")  // Grooming â†’ amarelo
                ruleTimeline.setLabelColor(3, "#3b82f6")  // Resting  â†’ azul
                ruleTimeline.setLabelColor(4, "#10b981")  // Rearing  â†’ verde
                // Cores para clusters B-SOiD
                var colors = root.bsoidColors
                for (var i = 0; i < colors.length; i++)
                    clusterTimeline.setLabelColor(i, colors[i])
                bsoidAnalyzer.populateTimelines(ruleTimeline, clusterTimeline, root.bsoidFps)
            })
        }
        onErrorOccurred: function(msg) {
            root.bsoidRunning = false
            root.bsoidError   = msg
        }
        onSnippetsProgress: function(pct) { root.snippetsProgress = pct }
        onSnippetsDone: function(ok, outDir, msg) {
            root.snippetsRunning  = false
            root.snippetsComplete = ok
            root.snippetsOutDir   = ok ? outDir : ""
            root.snippetsError    = ok ? "" : msg
        }
    }

    // Cores dos clusters B-SOiD â€” famÃ­lia vermelhos/amarelos/violetas,
    // deliberadamente distintas das regras nativas:
    // Walking=#10b981(verde), Sniffing=#3b82f6(azul), Grooming=#ec4899(rosa),
    // Resting=#6b7280(cinza), Rearing=#f97316(laranja)
    readonly property var bsoidColors: [
        "#ef4444",  // vermelho      G1
        "#eab308",  // amarelo       G2
        "#8b5cf6",  // violeta       G3
        "#d946ef",  // fÃºcsia        G4
        "#6366f1",  // Ã­ndigo        G5
        "#dc2626",  // vermelho esc  G6
        "#ca8a04",  // ouro          G7
        "#7c3aed",  // violeta esc   G8
        "#c026d3",  // magenta       G9
        "#be123c",  // carmim        G10
        "#a21caf",  // magenta esc   G11
        "#4f46e5"   // Ã­ndigo esc    G12
    ]

    function bsoidRuleName(ruleId) {
        var names = ["Walking","Object Zones","Grooming","Resting","Rearing"]
        return (ruleId >= 0 && ruleId < names.length) ? names[ruleId] : "?"
    }

    function startBsoidAnalysis() {
        if (root.bsoidRunning) return
        var campo = root.bsoidCampo
        var sessionPath = workArea.selectedPath  // pasta do experimento
        if (!sessionPath) { root.bsoidError = LanguageManager.tr3("Nenhum experimento selecionado.", "No experiment selected.", "Ningun experimento seleccionado."); return }
        var csvPath = sessionPath + "/bsoid_features_campo" + (campo + 1) + "_tmp.csv"
        var ok = liveRecordingTab.exportBehaviorFeatures(csvPath, campo)
        if (!ok) { root.bsoidError = LanguageManager.tr3("Nenhum dado de features disponivel. Execute uma analise primeiro.", "No feature data available. Run an analysis first.", "No hay datos de features disponibles. Ejecute un analisis primero."); return }
        // Captura FPS e caminho do vÃ­deo para timeline e snippets
        root.bsoidFps       = (liveRecordingTab.dlcFps > 0) ? liveRecordingTab.dlcFps : 30.0
        root.bsoidVideoPath = liveRecordingTab.videoPath
        root.bsoidRunning    = true
        root.bsoidDone       = false
        root.bsoidGroups     = []
        root.bsoidGroupNames = []
        root.behaviorStats   = []
        root.bsoidError      = ""
        root.bsoidProgress   = 0
        root.snippetsComplete = false
        root.snippetsOutDir   = ""
        root.snippetsError    = ""
        bsoidAnalyzer.analyze(csvPath, 7)
    }

    onContextChanged: {
        if (!root.searchMode && context !== "")
            ExperimentManager.loadContext(context, "comportamento_complexo")
    }

    Rectangle { anchors.fill: parent; color: ThemeManager.background; Behavior on color { ColorAnimation { duration: 200 } } }

    Connections {
        target: ExperimentManager

        onErrorOccurred: errorToast.show(message)

        onExperimentCreated: {
            successToast.show(LanguageManager.tr3("Experiment \"", "Experiment \"", "Experimento \"") + name + LanguageManager.tr3("\" created!", "\" created!", "\" creado!"))
            experimentList.selectExperimentByName(name)
            innerTabs.currentIndex = 0
        }

        onExperimentDeleted: {
            successToast.show(LanguageManager.tr3("Experiment \"", "Experiment \"", "Experimento \"") + name + LanguageManager.tr3("\" deleted.", "\" deleted.", "\" eliminado."))
            if (workArea.selectedName === name) {
                workArea.selectedName = ""
                workArea.selectedPath = ""
                workStack.currentIndex = 0
                experimentList.currentIndex = -1
            }
        }

        onSessionDataInserted: {
            if (workArea.selectedName === experimentName) {
                tableModel.loadCsv(workArea.selectedPath + "/tracking_data.csv")
                successToast.show(LanguageManager.tr3("Session saved!", "Session saved!", "Sesion guardada!"))
                innerTabs.currentIndex = 2  // aba ClassificaÃ§Ã£o
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // â”€â”€ Barra superior â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        Rectangle {
            Layout.fillWidth: true
            height: 56; color: ThemeManager.surface; Behavior on color { ColorAnimation { duration: 200 } }

            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 1; color: ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } }
            }

            RowLayout {
                anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                spacing: 14

                GhostButton { text: LanguageManager.tr3("<- Voltar", "<- Back", "<- Volver"); onClicked: root.backRequested() }

                Text { text: "\u2699"; font.pixelSize: 20 }

                Text {
                    text: root.searchMode
                          ? LanguageManager.tr3("Comportamento Complexo - Experimentos", "Complex Behavior - Experiments", "Comportamiento Complejo - Experimentos")
                          : LanguageManager.tr3("Comportamento Complexo - Dashboard", "Complex Behavior - Dashboard", "Comportamiento Complejo - Panel")
                    color: ThemeManager.textPrimary; font.pixelSize: 16; font.weight: Font.Bold
                    Behavior on color { ColorAnimation { duration: 150 } }
                }

                Rectangle {
                    visible: root.numCampos > 0 && !root.searchMode
                    radius: 4; color: ThemeManager.surfaceHover
                    border.color: "#7a3dab"; border.width: 1
                    Behavior on color { ColorAnimation { duration: 200 } }
                    implicitWidth: numLabel.implicitWidth + 16; implicitHeight: 24
                    Text {
                        id: numLabel
                        anchors.centerIn: parent
                        text: root.numCampos + " " + LanguageManager.tr3("campo", "field", "campo") + (root.numCampos > 1 ? "s" : "")
                        color: "#7a3dab"; font.pixelSize: 11; font.weight: Font.Bold
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                }

                Item { Layout.fillWidth: true }
            }
        }

        // â”€â”€ Corpo â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // â”€â”€ Sidebar â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            Rectangle {
                width: 250; Layout.fillHeight: true
                color: ThemeManager.surface; Behavior on color { ColorAnimation { duration: 200 } }

                Rectangle {
                    anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
                    width: 1; color: ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } }
                }

                ColumnLayout {
                    anchors { fill: parent; margins: 12 }
                    spacing: 8

                    Text {
                        text: LanguageManager.tr3("Experimentos", "Experiments", "Experimentos")
                        color: ThemeManager.textPrimary; font.pixelSize: 12; font.weight: Font.Bold
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    TextField {
                        id: searchField
                        Layout.fillWidth: true
                        placeholderText: LanguageManager.tr3("Pesquisar...", "Search...", "Buscar...")
                        color: ThemeManager.textPrimary; placeholderTextColor: ThemeManager.textSecondary; font.pixelSize: 13
                        leftPadding: 10; rightPadding: 10; topPadding: 6; bottomPadding: 6
                        background: Rectangle {
                            radius: 6; color: ThemeManager.surfaceDim; Behavior on color { ColorAnimation { duration: 200 } }
                            border.color: searchField.activeFocus ? "#7a3dab" : ThemeManager.borderLight; border.width: 1
                            Behavior on border.color { ColorAnimation { duration: 150 } }
                        }
                        onTextChanged: ExperimentManager.setFilter(text)
                    }

                    ListView {
                        id: experimentList
                        Layout.fillWidth: true; Layout.fillHeight: true
                        clip: true; model: ExperimentManager.model; currentIndex: -1

                        function selectExperimentByName(name) {
                            for (var i = 0; i < model.count; ++i) {
                                if (model.data(model.index(i, 0), Qt.UserRole + 1) === name) {
                                    currentIndex = i
                                    var path = model.data(model.index(i, 0), Qt.UserRole + 2)
                                    workArea.loadExperiment(name, path)
                                    return
                                }
                            }
                        }

                        ScrollBar.vertical: ScrollBar {
                            policy: ScrollBar.AsNeeded
                            contentItem: Rectangle { implicitWidth: 4; radius: 2; color: ThemeManager.borderLight; Behavior on color { ColorAnimation { duration: 200 } } }
                        }

                        delegate: Rectangle {
                            id: expDelegate
                            width: experimentList.width; height: 36
                            property bool isSelected: experimentList.currentIndex === index
                            property bool isHovered: mainArea.containsMouse || trashArea.containsMouse
                            color: isSelected ? "#7a3dab" : (isHovered ? ThemeManager.surfaceAlt : "transparent")
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Text {
                                anchors { left: parent.left; leftMargin: 10; right: trashItem.left; rightMargin: 4; top: parent.top; bottom: parent.bottom }
                                text: model.name
                                color: expDelegate.isSelected ? ThemeManager.textPrimary : ThemeManager.textSecondary
                                Behavior on color { ColorAnimation { duration: 150 } }
                                font.pixelSize: 13; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter
                            }

                            Item {
                                id: trashItem
                                anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                                width: 30; opacity: expDelegate.isHovered ? 1.0 : 0.0
                                Behavior on opacity { NumberAnimation { duration: 150 } }
                                Text {
                                    anchors.centerIn: parent; text: "\uD83D\uDDD1"; font.pixelSize: 13
                                    color: trashArea.containsMouse ? "#9a5ddb" : "#7a3dab"
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }
                                MouseArea {
                                    id: trashArea; anchors.fill: parent
                                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        ExperimentManager.setActiveContext(model.context)
                                        root.pendingDeleteName = model.name
                                        deleteStep1Popup.open()
                                    }
                                }
                            }

                            MouseArea {
                                id: mainArea
                                anchors { fill: parent; rightMargin: trashItem.width }
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    experimentList.currentIndex = index
                                    workArea.loadExperiment(model.name, model.path)
                                }
                            }

                            Rectangle {
                                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                height: 1; color: ThemeManager.border; opacity: 0.5
                                Behavior on color { ColorAnimation { duration: 200 } }
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: experimentList.count === 0
                        text: LanguageManager.tr3("Nenhum experimento\nencontrado", "No experiment\nfound", "Ningun experimento\nencontrado")
                            color: ThemeManager.textSecondary; font.pixelSize: 12
                            Behavior on color { ColorAnimation { duration: 150 } }
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }
            }

            // â”€â”€ Ãrea de trabalho â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            Item {
                id: workArea
                Layout.fillWidth: true; Layout.fillHeight: true

                property string selectedName: ""
                property string selectedPath: ""
                property int    colCount:     0
                property bool   includeDrug:      true
                property bool   hasObjectZones:   true
                property string analysisMode:     "offline"
                property int    activeNumCampos:  root.numCampos
                property int    sessionMinutes:   5
                property var    dayNames:         []

                function loadExperiment(name, path) {
                    selectedName = name
                    selectedPath = path
                    tableModel.loadCsv(path + "/tracking_data.csv")
                    workStack.currentIndex = 1

                    var meta = ExperimentManager.readMetadataFromPath(path)
                    var ctx  = meta.context || ""
                    ExperimentManager.setActiveContext(ctx)

                    includeDrug     = meta.includeDrug !== false
                    hasObjectZones  = meta.hasObjectZones !== false
                    activeNumCampos = meta.numCampos || root.numCampos
                    sessionMinutes  = meta.sessionMinutes || 5
                    dayNames        = meta.dayNames || Array.from({length: meta.sessionDays || 5}, function(_, i) { return LanguageManager.tr3("Day ", "Day ", "Dia ") + (i+1) })

                    if (activeNumCampos === 1) {
                        ArenaConfigModel.loadConfigFromPath(path, ":/arena_config_ei_referencia.json")
                        Qt.callLater(function() {
                            var fp = JSON.parse(ArenaConfigModel.getFloorPoints() || "[]")
                            var pts = (fp.length > 0 && Array.isArray(fp[0])) ? fp[0] : fp
                            if (!Array.isArray(pts) || pts.length < 8)
                                ArenaConfigModel.loadConfigFromPath("", ":/arena_config_ei_referencia.json")
                        })
                    } else {
                        ArenaConfigModel.loadConfigFromPath(path)
                    }

                    // Propaga pontos de arena para aba GravaÃ§Ã£o
                    liveRecordingTab.arenaPoints = JSON.parse(ArenaConfigModel.getArenaPoints() || "[]")
                    liveRecordingTab.floorPoints = JSON.parse(ArenaConfigModel.getFloorPoints() || "[]")
                    
                    // Propaga zonas se hasObjectZones; limpa explicitamente se nÃ£o
                    if (workArea.hasObjectZones) {
                        var src = ArenaConfigModel.zones || []
                        if (src.length > 0) {
                            var converted = []
                            for (var i = 0; i < src.length; i++) {
                                var z = src[i]
                                converted.push({
                                    x: z.xRatio !== undefined ? z.xRatio : 0.3,
                                    y: z.yRatio !== undefined ? z.yRatio : 0.5,
                                    r: z.radiusRatio !== undefined ? z.radiusRatio : 0.12
                                })
                            }
                            liveRecordingTab.zones = converted
                        }
                    } else {
                        liveRecordingTab.zones = []
                    }

                    colCount = tableModel.columnCount()
                }

                ExperimentTableModel { id: tableModel }
                Connections { target: tableModel; onModelReset: workArea.colCount = tableModel.columnCount() }

                StackLayout {
                    id: workStack
                    anchors.fill: parent
                    currentIndex: 0

                    // Ãndice 0: placeholder "selecione um experimento"
                    Item {
                        ColumnLayout {
                            anchors.centerIn: parent; spacing: 14
                                        Text { text: "\u2699"; font.pixelSize: 48; opacity: 0.15; Layout.alignment: Qt.AlignHCenter }
                            Text {
                                text: LanguageManager.tr3("Selecione um experimento", "Select an experiment", "Seleccione un experimento")
                                color: ThemeManager.textSecondary; font.pixelSize: 16
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }
                    }

                    // Ãndice 1: painel com abas
                    ColumnLayout {
                        spacing: 0

                        // â”€â”€ Barra de abas interna â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                        Rectangle {
                            Layout.fillWidth: true; height: 42
                            color: ThemeManager.surface; Behavior on color { ColorAnimation { duration: 200 } }
                            border.color: ThemeManager.border; border.width: 0

                            Rectangle {
                                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                height: 1; color: ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } }
                            }

                            RowLayout {
                                anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                                spacing: 0

                                Repeater {
                                    id: innerTabs
                                    property int currentIndex: 0
                                    model: ["🗺 " + LanguageManager.tr3("Arena", "Arena", "Arena"), "🎬 " + LanguageManager.tr3("Gravacao", "Recording", "Grabacion"), "🧠 " + LanguageManager.tr3("Classificacao", "Behavior", "Clasificacion"), "📊 " + LanguageManager.tr3("Dados", "Data", "Datos")]

                                    delegate: Item {
                                        id: tabItem
                                        width: tabLabel.implicitWidth + 28; height: parent.height
                                        property bool isActive:  innerTabs.currentIndex === index
                                        property bool isHovered: tabMouseArea.containsMouse

                                        scale: tabMouseArea.pressed ? 0.95 : (isHovered ? 1.05 : 1.0)
                                        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

                                        Rectangle {
                                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                            height: parent.isActive ? 2 : (parent.isHovered ? 1 : 0)
                                            color: parent.isActive ? "#7a3dab" : (parent.isHovered ? "#9a5ddb" : "transparent")
                                            Behavior on color  { ColorAnimation { duration: 150 } }
                                            Behavior on height { NumberAnimation { duration: 150 } }
                                        }

                                        Text {
                                            id: tabLabel; anchors.centerIn: parent
                                            text: modelData
                                            color: tabItem.isActive ? ThemeManager.textPrimary : (tabItem.isHovered ? ThemeManager.textSecondary : ThemeManager.textTertiary)
                                            Behavior on color { ColorAnimation { duration: 150 } }
                                            font.pixelSize: 12; font.weight: tabItem.isActive ? Font.Bold : Font.Normal
                                        }

                                        MouseArea {
                                            id: tabMouseArea; anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                            onClicked: innerTabs.currentIndex = index
                                        }
                                    }
                                }

                                Item { Layout.fillWidth: true }

                                Text {
                                    text: workArea.selectedName
                                    color: ThemeManager.textTertiary; font.pixelSize: 12; elide: Text.ElideRight
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }
                            }
                        }

                        StackLayout {
                            id: innerStack
                            Layout.fillWidth: true; Layout.fillHeight: true
                            currentIndex: innerTabs.currentIndex

                            // â”€â”€ Tab 0: Arena â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                            Item {
                                // ArenaSetup padrÃ£o â€” 2 ou 3 campos
                                ArenaSetup {
                                    id: tabArenaSetup
                                    anchors.fill: parent
                                    visible: workArea.activeNumCampos > 1
                                    experimentPath: workArea.activeNumCampos > 1 ? workArea.selectedPath : ""
                                    context: root.context
                                    numCampos: workArea.activeNumCampos
                                    aparato: "comportamento_complexo"
                                    caMode: true
                                    ccMode: true
                                    showObjectZones: workArea.hasObjectZones

                                    onAnalysisModeChangedExternally: mode => {
                                        workArea.analysisMode = mode
                                    }
                                    onZonasEditadas: {
                                        if (workArea.activeNumCampos === 1) return
                                        liveRecordingTab.zones       = workArea.hasObjectZones ? tabArenaSetup.zones : []
                                        liveRecordingTab.arenaPoints = tabArenaSetup.arenaPoints
                                        liveRecordingTab.floorPoints = tabArenaSetup.floorPoints
                                    }
                                }

                                // EIArenaSetup â€” 1 campo (arena EI adaptada para CC)
                                EIArenaSetup {
                                    id: eiArenaSetupCC
                                    anchors.fill: parent
                                    visible: workArea.activeNumCampos === 1
                                    experimentPath: workArea.activeNumCampos === 1 ? workArea.selectedPath : ""
                                    numCampos: 1
                                    primaryColor:   "#7a3dab"
                                    secondaryColor: "#6a2d9a"

                                    onAnalysisModeChangedExternally: mode => {
                                        workArea.analysisMode = mode
                                    }
                                    onZonasEditadas: {
                                        liveRecordingTab.zones       = []
                                        liveRecordingTab.arenaPoints = eiArenaSetupCC.arenaPoints
                                        liveRecordingTab.floorPoints = eiArenaSetupCC.floorPoints
                                    }
                                }
                            }

                            // â”€â”€ Tab 1: GravaÃ§Ã£o â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                            LiveRecording {
                                id: liveRecordingTab
                                videoPath: workArea.activeNumCampos === 1 ? eiArenaSetupCC.videoPath : tabArenaSetup.videoPath
                                analysisMode: workArea.analysisMode
                                numCampos:    workArea.activeNumCampos
                                aparato:      workArea.activeNumCampos === 1 ? "esquiva_inibitoria" : "comportamento_complexo"
                                ccMode:       true
                                sessionDurationMinutes: workArea.sessionMinutes

                                zones:        workArea.activeNumCampos === 1 ? [] : (workArea.hasObjectZones ? tabArenaSetup.zones : [])
                                arenaPoints:  JSON.parse(ArenaConfigModel.getArenaPoints() || "[]")
                                floorPoints:  JSON.parse(ArenaConfigModel.getFloorPoints() || "[]")

                                Connections {
                                    target: ArenaConfigModel
                                    function onConfigChanged() {
                                        liveRecordingTab.arenaPoints = JSON.parse(ArenaConfigModel.getArenaPoints() || "[]")
                                        liveRecordingTab.floorPoints = JSON.parse(ArenaConfigModel.getFloorPoints() || "[]")
                                    }
                                }

                                onSessionEnded: {
                                    ccResultDialog.totalDistance  = liveRecordingTab.totalDistance
                                    ccResultDialog.avgVelocity    = liveRecordingTab.avgVelocityMeans
                                    ccResultDialog.perMinuteData  = liveRecordingTab.perMinuteData
                                    ccResultDialog.behaviorCounts = liveRecordingTab.behaviorCounts
                                    ccResultDialog.includeDrug    = workArea.includeDrug
                                    ccResultDialog.experimentName = workArea.selectedName
                                    ccResultDialog.experimentPath = workArea.selectedPath
                                    ccResultDialog.numCampos      = workArea.activeNumCampos
                                    ccResultDialog.videoPath      = workArea.activeNumCampos === 1 ? eiArenaSetupCC.videoPath : tabArenaSetup.videoPath
                                    ccResultDialog.dayNames       = workArea.dayNames
                                    ccResultDialog.sessionMinutes = workArea.sessionMinutes || 5
                                    ccResultDialog.open()
                                }

                                onRequestVideoLoad: {
                                    innerTabs.currentIndex = 0
                                }
                            }

                            // â”€â”€ Tab 2: ClassificaÃ§Ã£o â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                            Item {
                                id: classificationTab

                                Rectangle {
                                    anchors.fill: parent
                                    color: ThemeManager.background
                                    Behavior on color { ColorAnimation { duration: 200 } }

                                    ScrollView {
                                        anchors.fill: parent
                                        contentWidth: availableWidth
                                        clip: true

                                        ColumnLayout {
                                            width: Math.min(820, parent.width - 80)
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            anchors.top: parent.top
                                            anchors.topMargin: 28
                                            spacing: 20

                                            // TÃ­tulo
                                            RowLayout {
                                                Layout.alignment: Qt.AlignHCenter
                                                spacing: 12
                                                Text { text: "\u2699"; font.pixelSize: 30 }
                                                ColumnLayout {
                                                    spacing: 2
                                                    Text {
                                                        text: LanguageManager.tr3("Analise Comportamental Nativa", "Native Behavioral Analysis", "Analisis Conductual Nativo")
                                                        color: ThemeManager.textPrimary
                                                        font.pixelSize: 20; font.weight: Font.Bold
                                                        Behavior on color { ColorAnimation { duration: 150 } }
                                                    }
                                                    Text {
                                                        text: LanguageManager.tr3(
                                                                  "Classificacao por regras em tempo real · B-SOiD disponivel pos-sessao",
                                                                  "Real-time rule-based classification · B-SOiD available after session",
                                                                  "Clasificacion por reglas en tiempo real · B-SOiD disponible despues de la sesion"
                                                              )
                                                        color: ThemeManager.textSecondary; font.pixelSize: 11
                                                        Behavior on color { ColorAnimation { duration: 150 } }
                                                    }
                                                }
                                            }

                                            // Card: motor de regras ativo
                                            Rectangle {
                                                Layout.fillWidth: true; radius: 12
                                                color: ThemeManager.surfaceDim
                                                border.color: ThemeManager.borderLight; border.width: 1
                                                implicitHeight: ruleRow.implicitHeight + 24
                                                Behavior on color { ColorAnimation { duration: 150 } }
                                                Behavior on border.color { ColorAnimation { duration: 150 } }
                                                RowLayout {
                                                    id: ruleRow
                                                    anchors { fill: parent; margins: 12 }
                                                    spacing: 12
                                                    Text { text: "\u2699"; font.pixelSize: 20 }
                                                    ColumnLayout {
                                                        spacing: 2
                                                        Text {
                                                            text: LanguageManager.tr3("Motor de Regras Nativo (C++)", "Native Rules Engine (C++)", "Motor de Reglas Nativo (C++)")
                                                            color: ThemeManager.textPrimary; font.weight: Font.Bold; font.pixelSize: 13
                                                            Behavior on color { ColorAnimation { duration: 150 } }
                                                        }
                                                        Text {
                                                            text: LanguageManager.tr3(
                                                                      "Zonas de objetos · Rearing · Resting · Grooming · Walking - sem modelo ONNX",
                                                                      "Object zones · Rearing · Resting · Grooming · Walking - no ONNX model",
                                                                      "Zonas de objetos · Rearing · Resting · Grooming · Walking - sin modelo ONNX"
                                                                  )
                                                            color: ThemeManager.textSecondary; font.pixelSize: 11
                                                            Behavior on color { ColorAnimation { duration: 150 } }
                                                        }
                                                    }
                                                    Item { Layout.fillWidth: true }
                                                    Rectangle {
                                                        color: ThemeManager.successLight; radius: 6
                                                        implicitWidth: ruleStatusTxt.implicitWidth + 16
                                                        implicitHeight: ruleStatusTxt.implicitHeight + 8
                                                        Text {
                                                            id: ruleStatusTxt
                                                            anchors.centerIn: parent
                                                            text: LanguageManager.tr3("ACTIVE", "ACTIVE", "ACTIVO")
                                                            color: ThemeManager.success
                                                            font.pixelSize: 12; font.weight: Font.Bold
                                                        }
                                                    }
                                                }
                                            }

                                            // Badges em tempo real por campo
                                            RowLayout {
                                                Layout.fillWidth: true; spacing: 16
                                                Repeater {
                                                    model: workArea.activeNumCampos
                                                    delegate: Rectangle {
                                                        Layout.fillWidth: true; Layout.minimumHeight: 120; radius: 12
                                                        color: ThemeManager.surface
                                                        border.color: ThemeManager.border; border.width: 1
                                                        Behavior on color { ColorAnimation { duration: 150 } }
                                                        Behavior on border.color { ColorAnimation { duration: 150 } }
                                                        ColumnLayout {
                                                            anchors.centerIn: parent; spacing: 12
                                                            Text {
                                                                Layout.alignment: Qt.AlignHCenter
                                                                text: LanguageManager.tr3("Campo ", "Field ", "Campo ") + (index + 1)
                                                                color: ThemeManager.textSecondary
                                                                font.pixelSize: 13; font.weight: Font.Bold
                                                                Behavior on color { ColorAnimation { duration: 150 } }
                                                            }
                                                            Rectangle {
                                                                Layout.alignment: Qt.AlignHCenter
                                                                radius: 6; implicitHeight: 36; implicitWidth: bhvTxt.implicitWidth + 36
                                                                property string bhvName: liveRecordingTab.currentBehaviorString[index] || LanguageManager.tr3("Detectando...", "Detecting...", "Detectando...")
                                                                property color badgeColor: {
                                                                    if (bhvName === "Walking")  return "#8b5cf6"
                                                                    if (bhvName === "Resting")  return "#3b82f6"
                                                                    if (bhvName === "Rearing")  return "#10b981"
                                                                    if (bhvName === "Grooming") return "#eab308"
                                                                    if (bhvName === "Zonas de objetos" || bhvName === "Object Zones") return "#f97316"
                                                                    return ThemeManager.surfaceAlt
                                                                }
                                                                color: badgeColor
                                                                Behavior on color { ColorAnimation { duration: 250 } }
                                                                Text {
                                                                    id: bhvTxt
                                                                    anchors.centerIn: parent
                                                                    text: parent.bhvName
                                                                    color: parent.bhvName === LanguageManager.tr3("Detectando...", "Detecting...", "Detectando...") ? ThemeManager.textSecondary : "#ffffff"
                                                                    font.pixelSize: 14; font.weight: Font.Bold
                                                                    Behavior on color { ColorAnimation { duration: 250 } }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }

                                            // Legenda
                                            Rectangle {
                                                Layout.fillWidth: true; radius: 8
                                                color: "transparent"
                                                border.color: ThemeManager.borderLight; border.width: 1
                                                Behavior on border.color { ColorAnimation { duration: 150 } }
                                                implicitHeight: legendRow.implicitHeight + 20
                                                RowLayout {
                                                    id: legendRow
                                                    anchors { fill: parent; margins: 10 }
                                                    spacing: 16
                                                    Item { Layout.fillWidth: true }
                                                    Repeater {
                                                        model: ["Walking|#8b5cf6", "Object Zones|#f97316", "Grooming|#eab308", "Resting|#3b82f6", "Rearing|#10b981"]
                                                        delegate: RowLayout {
                                                            spacing: 6
                                                            Rectangle { width: 14; height: 14; radius: 7; color: modelData.split("|")[1] }
                                                            Text {
                                                                text: modelData.split("|")[0]
                                                                color: ThemeManager.textSecondary; font.pixelSize: 12
                                                                Behavior on color { ColorAnimation { duration: 150 } }
                                                            }
                                                        }
                                                    }
                                                    Item { Layout.fillWidth: true }
                                                }
                                            }

                                            // Separador B-SOiD
                                            RowLayout {
                                                Layout.fillWidth: true; spacing: 12
                                                Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } } }
                                                Text {
                                                    text: "B-SOiD"
                                                    color: ThemeManager.textSecondary; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.2
                                                    Behavior on color { ColorAnimation { duration: 150 } }
                                                }
                                                Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } } }
                                            }

                                            // Card B-SOiD (pÃ³s-sessÃ£o â€” interativo)
                                            Rectangle {
                                                Layout.fillWidth: true; radius: 12
                                                color: ThemeManager.surfaceDim
                                                border.color: ThemeManager.borderLight; border.width: 1
                                                implicitHeight: bsoidMainCol.implicitHeight + 28
                                                Behavior on color { ColorAnimation { duration: 150 } }
                                                Behavior on border.color { ColorAnimation { duration: 150 } }

                                                ColumnLayout {
                                                    id: bsoidMainCol
                                                    anchors { fill: parent; margins: 14 }
                                                    spacing: 12

                                                    // Header: tÃ­tulo + status + botÃ£o
                                                    RowLayout {
                                                        spacing: 10
                                                        Text { text: "\uD83D\uDD2C"; font.pixelSize: 18 }
                                                        ColumnLayout {
                                                            spacing: 2
                                                            Text {
                                                                text: LanguageManager.tr3("Analise B-SOiD (Pos-Sessao)", "B-SOiD Analysis (Post-Session)", "Analisis B-SOiD (Post-Sesion)")
                                                                color: ThemeManager.textPrimary; font.weight: Font.Bold; font.pixelSize: 13
                                                                Behavior on color { ColorAnimation { duration: 150 } }
                                                            }
                                                            Text {
                                                                text: LanguageManager.tr3(
                                                                          "Agrupa frames por padrao de movimento via PCA + K-Means",
                                                                          "Groups frames by movement pattern with PCA + K-Means",
                                                                          "Agrupa fotogramas por patron de movimiento con PCA + K-Means"
                                                                      )
                                                                color: ThemeManager.textSecondary; font.pixelSize: 11
                                                                Behavior on color { ColorAnimation { duration: 150 } }
                                                            }
                                                        }
                                                        Item { Layout.fillWidth: true }

                                                        // Badge de status
                                                        Rectangle {
                                                            radius: 6
                                                            color: root.bsoidDone ? ThemeManager.successLight
                                                                 : root.bsoidRunning ? "#1a1a3a"
                                                                 : "#1a1a3a"
                                                            border.color: root.bsoidDone ? ThemeManager.success
                                                                        : root.bsoidRunning ? "#4a4a8c"
                                                                        : "#4a4a8c"
                                                            border.width: 1
                                                            implicitWidth: bsoidBadgeTxt.implicitWidth + 16
                                                            implicitHeight: bsoidBadgeTxt.implicitHeight + 8
                                                            Behavior on color { ColorAnimation { duration: 200 } }
                                                            Text {
                                                                id: bsoidBadgeTxt
                                                                anchors.centerIn: parent
                                                                text: root.bsoidDone ? LanguageManager.tr3("Concluido", "Done", "Completado") : root.bsoidRunning ? ("" + root.bsoidProgress + "%") : LanguageManager.tr3("Aguardando", "Waiting", "Esperando")
                                                                color: root.bsoidDone ? ThemeManager.success : "#8888cc"
                                                                font.pixelSize: 11; font.weight: Font.Bold
                                                                Behavior on color { ColorAnimation { duration: 200 } }
                                                            }
                                                        }

                                                        // Seletor de campo
                                                        RowLayout {
                                                            spacing: 4
                                                            Text {
                                                                text: LanguageManager.tr3("Campo:", "Field:", "Campo:")
                                                                color: ThemeManager.textSecondary; font.pixelSize: 11
                                                                Behavior on color { ColorAnimation { duration: 150 } }
                                                            }
                                                            Repeater {
                                                                model: workArea.activeNumCampos
                                                                delegate: Rectangle {
                                                                    width: 36; height: 26; radius: 6
                                                                    property bool sel: root.bsoidCampo === index
                                                                    color:        sel ? "#1a0d2e" : (cma.containsMouse ? ThemeManager.surfaceHover : ThemeManager.surfaceDim)
                                                                    border.color: sel ? "#7c3aed" : ThemeManager.border; border.width: sel ? 2 : 1
                                                                    Behavior on color        { ColorAnimation { duration: 150 } }
                                                                    Behavior on border.color { ColorAnimation { duration: 150 } }
                                                                    Text {
                                                                        anchors.centerIn: parent
                                                                        text: "C" + (index + 1)
                                                                        color: sel ? "#a78bfa" : ThemeManager.textSecondary
                                                                        font.pixelSize: 11; font.weight: Font.Bold
                                                                        Behavior on color { ColorAnimation { duration: 150 } }
                                                                    }
                                                                    MouseArea {
                                                                        id: cma; anchors.fill: parent
                                                                        cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                                                        onClicked: {
                                                                            if (root.bsoidCampo !== index) {
                                                                                root.bsoidCampo   = index
                                                                                root.bsoidDone    = false
                                                                                root.bsoidGroups  = []
                                                                                root.bsoidGroupNames = []
                                                                                root.behaviorStats   = []
                                                                                root.bsoidError   = ""
                                                                            }
                                                                        }
                                                                    }
                                                                }
                                                            }
                                                        }

                                                        // BotÃ£o Analisar
                                                        Button {
                                                            visible: !root.bsoidRunning
                                                            text: root.bsoidDone ? LanguageManager.tr3("Reanalisar", "Re-analyze", "Reanalizar") : LanguageManager.tr3("Analisar", "Analyze", "Analizar")
                                                            onClicked: root.startBsoidAnalysis()
                                                            background: Rectangle {
                                                                radius: 7
                                                                color: parent.hovered ? "#5b21b6" : "#7c3aed"
                                                                Behavior on color { ColorAnimation { duration: 150 } }
                                                            }
                                                            contentItem: Text {
                                                                text: parent.text; color: "#ffffff"
                                                                font.pixelSize: 12; font.weight: Font.Bold
                                                                horizontalAlignment: Text.AlignHCenter
                                                                verticalAlignment:   Text.AlignVCenter
                                                            }
                                                            leftPadding: 14; rightPadding: 14; topPadding: 7; bottomPadding: 7
                                                        }

                                                        // Spinner durante anÃ¡lise
                                                        BusyIndicator {
                                                            visible: root.bsoidRunning
                                                            width: 28; height: 28
                                                            running: root.bsoidRunning
                                                        }
                                                    }

                                                    // Barra de progresso
                                                    Rectangle {
                                                        visible: root.bsoidRunning
                                                        Layout.fillWidth: true; height: 4; radius: 2
                                                        color: ThemeManager.border
                                                        Behavior on color { ColorAnimation { duration: 200 } }
                                                        Rectangle {
                                                            width: parent.width * (root.bsoidProgress / 100)
                                                            height: parent.height; radius: parent.radius
                                                            color: "#7c3aed"
                                                            Behavior on width { NumberAnimation { duration: 200 } }
                                                        }
                                                    }

                                                    // Mensagem de erro
                                                    Text {
                                                        visible: root.bsoidError !== ""
                                                        text: LanguageManager.tr3("Warning: ", "Warning: ", "Aviso: ") + root.bsoidError
                                                        color: "#ef4444"; font.pixelSize: 11
                                                        wrapMode: Text.WordWrap; Layout.fillWidth: true
                                                    }

                                                    // Texto de ajuda (apenas antes da anÃ¡lise)
                                                    Text {
                                                        visible: !root.bsoidDone && !root.bsoidRunning && root.bsoidError === ""
                                                        text: LanguageManager.tr3("Clique em Analisar apos finalizar a gravacao. O algoritmo analisa os dados de trajetoria coletados e descobre grupos comportamentais adicionais as regras nativas.", "Click Analyze after recording ends. The algorithm analyzes trajectory data and discovers behavioral groups in addition to native rules.", "Haga clic en Analizar despues de finalizar la grabacion. El algoritmo analiza los datos de trayectoria y descubre grupos conductuales adicionales a las reglas nativas.")
                                                        color: ThemeManager.textTertiary; font.pixelSize: 11
                                                        wrapMode: Text.WordWrap; Layout.fillWidth: true
                                                        Behavior on color { ColorAnimation { duration: 150 } }
                                                    }

                                                    // â”€â”€ EstatÃ­sticas por comportamento (pÃ³s B-SOiD) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                                                    ColumnLayout {
                                                        visible: root.bsoidDone && root.behaviorStats.length > 0
                                                        Layout.fillWidth: true; spacing: 6

                                                        Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } } }

                                                        Text {
                                                            text: LanguageManager.tr3("BEHAVIORS - DURATION AND BOUTS · C", "BEHAVIORS - DURATION AND BOUTS · C", "COMPORTAMIENTOS - DURACION Y BOUTS · C") + (root.bsoidCampo + 1)
                                                            color: ThemeManager.textSecondary
                                                            font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 1.2
                                                            Behavior on color { ColorAnimation { duration: 150 } }
                                                        }

                                                        // CabeÃ§alho tabela
                                                        RowLayout {
                                                            Layout.fillWidth: true; spacing: 0
                                                            Text { text: LanguageManager.tr3("Comportamento", "Behavior", "Comportamiento"); width: 100; color: ThemeManager.textTertiary; font.pixelSize: 10; font.weight: Font.Bold }
                                                            Text { text: LanguageManager.tr3("Tempo (s)", "Time (s)", "Tiempo (s)"); width: 80; color: ThemeManager.textTertiary; font.pixelSize: 10; font.weight: Font.Bold; horizontalAlignment: Text.AlignRight }
                                                            Text { text: "Bouts";         width: 60;  color: ThemeManager.textTertiary; font.pixelSize: 10; font.weight: Font.Bold; horizontalAlignment: Text.AlignRight }
                                                            Item { Layout.fillWidth: true }
                                                        }

                                                        Repeater {
                                                            model: root.behaviorStats
                                                            delegate: RowLayout {
                                                                Layout.fillWidth: true; spacing: 0
                                                                Rectangle { width: 10; height: 10; radius: 5; color: modelData.color }
                                                                Item { width: 6 }
                                                                Text { text: modelData.name;    width: 88; color: ThemeManager.textPrimary; font.pixelSize: 11 }
                                                                Text { text: modelData.seconds + " s"; width: 80; color: ThemeManager.textSecondary; font.pixelSize: 11; horizontalAlignment: Text.AlignRight }
                                                                Text { text: modelData.bouts;   width: 60; color: ThemeManager.textSecondary; font.pixelSize: 11; horizontalAlignment: Text.AlignRight }
                                                                Item { Layout.fillWidth: true }
                                                            }
                                                        }
                                                    }

                                                    // Resultados: grupos descobertos
                                                    ColumnLayout {
                                                        visible: root.bsoidDone && root.bsoidGroups.length > 0
                                                        Layout.fillWidth: true; spacing: 6

                                                        RowLayout {
                                                            Layout.fillWidth: true
                                                            Text {
                                                            text: LanguageManager.tr3("DISCOVERED GROUPS - ", "DISCOVERED GROUPS - ", "GRUPOS DESCUBIERTOS - ") + root.bsoidGroups.length + " clusters · C" + (root.bsoidCampo + 1)
                                                                color: ThemeManager.textSecondary
                                                                font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 1.2
                                                                Behavior on color { ColorAnimation { duration: 150 } }
                                                            }
                                                        }

                                                        // Dica: ver clips antes de nomear
                                                        Rectangle {
                                                            Layout.fillWidth: true; radius: 7
                                                            color: "#120a1e"; border.color: "#4c1d95"; border.width: 1
                                                            implicitHeight: hintRow.implicitHeight + 12
                                                            RowLayout {
                                                                id: hintRow
                                                                anchors { left: parent.left; right: parent.right; margins: 10; verticalCenter: parent.verticalCenter }
                                                                spacing: 8
                                                                Text { text: "\u2139"; font.pixelSize: 13 }
                                                                Text {
                                                                    Layout.fillWidth: true
                                                                    text: LanguageManager.tr3("Extraia os clipes abaixo, assista a cada grupo e nomeie o comportamento observado.", "Extract the clips below, watch each group, and name the observed behavior.", "Extraiga los clips de abajo, observe cada grupo y nombre el comportamiento observado.")
                                                                    color: "#c4b5fd"; font.pixelSize: 10; wrapMode: Text.WordWrap
                                                                }
                                                            }
                                                        }

                                                        Repeater {
                                                            id: groupsRepeater
                                                            model: root.bsoidGroups
                                                            delegate: Rectangle {
                                                                Layout.fillWidth: true; radius: 8
                                                                implicitHeight: grpCol.implicitHeight + 14
                                                                color: ThemeManager.surface
                                                                border.color: ThemeManager.border; border.width: 1
                                                                Behavior on color { ColorAnimation { duration: 150 } }

                                                                property var grp: modelData
                                                                property color clusterColor: root.bsoidColors[grp.clusterId % root.bsoidColors.length]
                                                                property int grpIdx: index

                                                                ColumnLayout {
                                                                    id: grpCol
                                                                    anchors { left: parent.left; right: parent.right; margins: 10; top: parent.top; topMargin: 7 }
                                                                    spacing: 6

                                                                    RowLayout {
                                                                        spacing: 10
                                                                        Rectangle {
                                                                            width: 12; height: 12; radius: 6
                                                                            color: parent.parent.parent.clusterColor
                                                                        }
                                                                        Text {
                                                                text: LanguageManager.tr3("Grupo ", "Group ", "Grupo ") + (grp.clusterId + 1)
                                                                            color: ThemeManager.textPrimary; font.pixelSize: 12; font.weight: Font.Bold
                                                                            Behavior on color { ColorAnimation { duration: 150 } }
                                                                        }
                                                                        Rectangle {
                                                                            Layout.fillWidth: true; height: 6; radius: 3
                                                                            color: ThemeManager.border
                                                                            Behavior on color { ColorAnimation { duration: 150 } }
                                                                            Rectangle {
                                                                                width: parent.width * (grp.percentage / 100)
                                                                                height: parent.height; radius: parent.radius
                                                                                color: parent.parent.parent.parent.parent.clusterColor
                                                                                Behavior on width { NumberAnimation { duration: 300 } }
                                                                            }
                                                                        }
                                                                        Text {
                                                                            text: grp.percentage.toFixed(1) + "%"
                                                                            color: ThemeManager.textSecondary; font.pixelSize: 12; font.weight: Font.Bold
                                                                            Behavior on color { ColorAnimation { duration: 150 } }
                                                                        }
                                                                        Text {
                                                                text: "~ " + root.bsoidRuleName(grp.dominantRule)
                                                                            color: ThemeManager.textTertiary; font.pixelSize: 10
                                                                            Behavior on color { ColorAnimation { duration: 150 } }
                                                                        }
                                                                    }

                                                                    // Campo de nomeaÃ§Ã£o do grupo
                                                                    RowLayout {
                                                                        spacing: 6
                                                                        Text {
                                                                            text: LanguageManager.tr3("Nome:", "Name:", "Nombre:")
                                                                            color: ThemeManager.textTertiary; font.pixelSize: 10
                                                                            Behavior on color { ColorAnimation { duration: 150 } }
                                                                        }
                                                                        TextField {
                                                                            id: groupNameField
                                                                            Layout.fillWidth: true; height: 26
                                                                            // Sem binding reativo â€” inicializa uma vez; onTextEdited atualiza o array
                                                                            Component.onCompleted: {
                                                                                text = (root.bsoidGroupNames && root.bsoidGroupNames.length > grpIdx)
                                                                                       ? (root.bsoidGroupNames[grpIdx] || "") : ""
                                                                            }
                                                                            placeholderText: LanguageManager.tr3("Ex.: Exploracao, Repouso, Grooming...", "Ex.: Exploration, Resting, Grooming...", "Ej.: Exploracion, Reposo, Grooming...")
                                                                            color: ThemeManager.textPrimary
                                                                            placeholderTextColor: ThemeManager.textTertiary
                                                                            font.pixelSize: 11
                                                                            leftPadding: 8; rightPadding: 8; topPadding: 4; bottomPadding: 4
                                                                            background: Rectangle {
                                                                                radius: 6; color: ThemeManager.surfaceDim
                                                                                Behavior on color { ColorAnimation { duration: 200 } }
                                                                                border.color: groupNameField.activeFocus ? "#7c3aed" : ThemeManager.border; border.width: 1
                                                                                Behavior on border.color { ColorAnimation { duration: 150 } }
                                                                            }
                                                                            onTextEdited: {
                                                                                if (root.bsoidGroupNames && root.bsoidGroupNames.length > grpIdx) {
                                                                                    var names = root.bsoidGroupNames.slice()
                                                                                    names[grpIdx] = text
                                                                                    root.bsoidGroupNames = names
                                                                                }
                                                                            }
                                                                        }
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }

                                                    // â”€â”€ Timeline Dupla â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                                                    ColumnLayout {
                                                        visible: root.bsoidDone
                                                        Layout.fillWidth: true; spacing: 6

                                                        Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } } }

                                                        Text {
                                                            text: LanguageManager.tr3("TIMELINE - RULES vs B-SOiD", "TIMELINE - RULES vs B-SOiD", "LINEA DE TIEMPO - REGLAS vs B-SOiD")
                                                            color: ThemeManager.textSecondary
                                                            font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 1.2
                                                            Behavior on color { ColorAnimation { duration: 150 } }
                                                        }

                                                        // Linha 1 â€” Regras nativas
                                                        RowLayout {
                                                            Layout.fillWidth: true; spacing: 6
                                                            Text {
                                                                text: LanguageManager.tr3("Regras", "Rules", "Reglas")
                                                                width: 46; color: ThemeManager.textTertiary
                                                                font.pixelSize: 10; verticalAlignment: Text.AlignVCenter
                                                                Behavior on color { ColorAnimation { duration: 150 } }
                                                            }
                                                            BehaviorTimeline {
                                                                id: ruleTimeline
                                                                Layout.fillWidth: true; height: 20
                                                                defaultColor: ThemeManager.border
                                                            }
                                                        }

                                                        // Linha 2 â€” Clusters B-SOiD
                                                        RowLayout {
                                                            Layout.fillWidth: true; spacing: 6
                                                            Text {
                                                                text: "B-SOiD"
                                                                width: 46; color: ThemeManager.textTertiary
                                                                font.pixelSize: 10; verticalAlignment: Text.AlignVCenter
                                                                Behavior on color { ColorAnimation { duration: 150 } }
                                                            }
                                                            BehaviorTimeline {
                                                                id: clusterTimeline
                                                                Layout.fillWidth: true; height: 20
                                                                defaultColor: ThemeManager.border
                                                            }
                                                        }

                                                        // Legenda de cores dos clusters
                                                        Flow {
                                                            Layout.fillWidth: true; spacing: 8
                                                            Repeater {
                                                                model: root.bsoidGroups
                                                                delegate: RowLayout {
                                                                    spacing: 4
                                                                    Rectangle {
                                                                        width: 8; height: 8; radius: 4
                                                                        color: root.bsoidColors[modelData.clusterId % root.bsoidColors.length]
                                                                    }
                                                                    Text {
                                                                        text: "G" + (modelData.clusterId + 1)
                                                                        color: ThemeManager.textTertiary; font.pixelSize: 9
                                                                        Behavior on color { ColorAnimation { duration: 150 } }
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }

                                                    // â”€â”€ ExtraÃ§Ã£o de Clips de VÃ­deo â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                                                    ColumnLayout {
                                                        visible: root.bsoidDone
                                                        Layout.fillWidth: true; spacing: 6

                                                        Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } } }

                                                        Text {
                                                            text: LanguageManager.tr3("VIDEO CLIPS PER GROUP", "VIDEO CLIPS PER GROUP", "CLIPS DE VIDEO POR GRUPO")
                                                            color: ThemeManager.textSecondary
                                                            font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 1.2
                                                            Behavior on color { ColorAnimation { duration: 150 } }
                                                        }

                                                        RowLayout {
                                                            Layout.fillWidth: true; spacing: 8

                                                            Text {
                                                                Layout.fillWidth: true
                                                                text: root.snippetsComplete
                                                                    ? (LanguageManager.tr3("Clipes salvos em: ", "Clips saved at: ", "Clips guardados en: ") + root.snippetsOutDir)
                                                                    : root.snippetsRunning
                                                                        ? (LanguageManager.tr3("Extracting... ", "Extracting... ", "Extrayendo... ") + root.snippetsProgress + "%")
                                                                        : root.snippetsError !== ""
                                                                            ? (LanguageManager.tr3("Warning: ", "Warning: ", "Aviso: ") + root.snippetsError)
                                                                            : LanguageManager.tr3("Extrai ate 3 clipes .mp4 por grupo. Requer ffmpeg.exe no PATH ou na pasta do app. Sem FFmpeg, salva apenas timestamps.csv.", "Extracts up to 3 .mp4 clips per group. Requires ffmpeg.exe in PATH or app folder. Without FFmpeg, only timestamps.csv is saved.", "Extrae hasta 3 clips .mp4 por grupo. Requiere ffmpeg.exe en PATH o en la carpeta de la app. Sin FFmpeg, solo guarda timestamps.csv.")
                                                                color: root.snippetsComplete ? ThemeManager.success
                                                                     : root.snippetsError !== "" ? "#ef4444"
                                                                     : ThemeManager.textTertiary
                                                                font.pixelSize: 10; wrapMode: Text.WordWrap
                                                                Behavior on color { ColorAnimation { duration: 200 } }
                                                            }

                                                            // Abre pasta no Explorer
                                                            Button {
                                                                visible: root.snippetsComplete && !root.snippetsRunning
                                                                text: LanguageManager.tr3("Abrir", "Open", "Abrir")
                                                                onClicked: Qt.openUrlExternally("file:///" + root.snippetsOutDir)
                                                                background: Rectangle {
                                                                    radius: 7
                                                                    color: parent.hovered ? ThemeManager.surfaceHover : ThemeManager.surfaceDim
                                                                    border.color: ThemeManager.border; border.width: 1
                                                                    Behavior on color { ColorAnimation { duration: 150 } }
                                                                }
                                                                contentItem: Text {
                                                                    text: parent.text; color: ThemeManager.textPrimary
                                                                    font.pixelSize: 11; font.weight: Font.Bold
                                                                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                                                                }
                                                                leftPadding: 10; rightPadding: 10; topPadding: 6; bottomPadding: 6
                                                            }

                                                            Button {
                                                                visible: !root.snippetsRunning
                                                                text: root.snippetsComplete ? LanguageManager.tr3("Reextrair", "Re-extract", "Reextraer") : LanguageManager.tr3("Extrair Clipes", "Extract Clips", "Extraer Clips")
                                                                enabled: root.bsoidDone
                                                                onClicked: {
                                                                    var outDir = workArea.selectedPath + "/bsoid_snippets"
                                                                    root.snippetsRunning  = true
                                                                    root.snippetsComplete = false
                                                                    root.snippetsError    = ""
                                                                    root.snippetsProgress = 0
                                                                    bsoidAnalyzer.extractSnippets(root.bsoidVideoPath, outDir, root.bsoidFps, 3)
                                                                }
                                                                background: Rectangle {
                                                                    radius: 7
                                                                    color: parent.enabled
                                                                        ? (parent.hovered ? "#1d4ed8" : "#2563eb")
                                                                        : ThemeManager.border
                                                                    Behavior on color { ColorAnimation { duration: 150 } }
                                                                }
                                                                contentItem: Text {
                                                                    text: parent.text; color: parent.enabled ? "#ffffff" : ThemeManager.textTertiary
                                                                    font.pixelSize: 11; font.weight: Font.Bold
                                                                    horizontalAlignment: Text.AlignHCenter
                                                                    verticalAlignment:   Text.AlignVCenter
                                                                }
                                                                leftPadding: 12; rightPadding: 12; topPadding: 6; bottomPadding: 6
                                                            }

                                                            BusyIndicator {
                                                                visible: root.snippetsRunning
                                                                width: 24; height: 24; running: root.snippetsRunning
                                                            }

                                                            // Barra de progresso dos snippets
                                                            Rectangle {
                                                                visible: root.snippetsRunning
                                                                width: 80; height: 4; radius: 2
                                                                color: ThemeManager.border
                                                                Behavior on color { ColorAnimation { duration: 200 } }
                                                                Rectangle {
                                                                    width: parent.width * (root.snippetsProgress / 100)
                                                                    height: parent.height; radius: parent.radius
                                                                    color: "#2563eb"
                                                                    Behavior on width { NumberAnimation { duration: 200 } }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }

                                            Item { height: 20 }
                                        }
                                    }
                                }
                            }

                            // â”€â”€ Tab 3: Dados â€” Layout aparato-especÃ­fico
                            DataView {
                                anchors.fill: parent
                                tableModel: tableModel
                                workArea: workArea
                            }
                        }
                    }
                }
            }
        }
    }

    // â”€â”€ DiÃ¡logo de resultado CC â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    CCMetadataDialog {
        id: ccResultDialog
        parent: Overlay.overlay
        anchors.centerIn: parent
    }

    // â”€â”€ Toasts â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    Toast { id: successToast; anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 16 } }
    Toast { id: errorToast;   anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 16 } }

    // â”€â”€ Popup delete â€” Passo 1 â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    Popup {
        id: deleteStep1Popup
        anchors.centerIn: parent; width: 400
        height: step1Layout.implicitHeight + 56
        modal: true; focus: true; closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle { radius: 14; color: ThemeManager.surface; Behavior on color { ColorAnimation { duration: 200 } } border.color: ThemeManager.borderLight; border.width: 1 }

        ColumnLayout {
            id: step1Layout
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
            spacing: 14
            Text { text: LanguageManager.tr3("Excluir Experimento", "Delete Experiment", "Eliminar Experimento"); color: ThemeManager.textPrimary; font.pixelSize: 16; font.weight: Font.Bold }
            Text {
                Layout.fillWidth: true
                text: LanguageManager.tr3(
                          "Tem certeza que deseja excluir\n\"",
                          "Are you sure you want to delete\n\"",
                          "Seguro que desea eliminar\n\""
                      ) + root.pendingDeleteName + LanguageManager.tr3(
                          "\"?\n\nEsta acao e irreversivel.",
                          "\"?\n\nThis action is irreversible.",
                          "\"?\n\nEsta accion es irreversible."
                      )
                color: ThemeManager.textSecondary; font.pixelSize: 13; wrapMode: Text.WordWrap
            }
            RowLayout {
                Layout.fillWidth: true; spacing: 10; Item { Layout.fillWidth: true }
                GhostButton { text: LanguageManager.tr3("Cancelar", "Cancel", "Cancelar"); onClicked: deleteStep1Popup.close() }
                Button {
                    text: LanguageManager.tr3("Continuar", "Continue", "Continuar")
                    onClicked: { deleteStep1Popup.close(); deleteNameField.text = ""; deleteStep2Popup.open() }
                    background: Rectangle { radius: 7; color: parent.hovered ? ThemeManager.accentHover : ThemeManager.accent; Behavior on color { ColorAnimation { duration: 150 } } }
                    contentItem: Text { text: parent.text; color: ThemeManager.buttonText; font.pixelSize: 12; font.weight: Font.Bold; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    leftPadding: 16; rightPadding: 16; topPadding: 8; bottomPadding: 8
                }
            }
        }
    }

    // â”€â”€ Popup delete â€” Passo 2 â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    Popup {
        id: deleteStep2Popup
        anchors.centerIn: parent; width: 420
        height: step2Layout.implicitHeight + 56
        modal: true; focus: true; closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onOpened: deleteNameField.forceActiveFocus()
        background: Rectangle { radius: 14; color: ThemeManager.surface; Behavior on color { ColorAnimation { duration: 200 } } border.color: ThemeManager.accent; border.width: 1 }

        ColumnLayout {
            id: step2Layout
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
            spacing: 14
            Text { text: LanguageManager.tr3("Confirmacao Final", "Final Confirmation", "Confirmacion Final"); color: ThemeManager.textPrimary; font.pixelSize: 16; font.weight: Font.Bold }
            Text { Layout.fillWidth: true; text: LanguageManager.tr3("Para confirmar, digite o nome do experimento:", "To confirm, type the experiment name:", "Para confirmar, escriba el nombre del experimento:"); color: ThemeManager.textSecondary; font.pixelSize: 13; wrapMode: Text.WordWrap }
            Rectangle {
                Layout.fillWidth: true; height: nameLabel.implicitHeight + 10; radius: 5
                color: ThemeManager.surfaceDim; border.color: ThemeManager.borderLight; border.width: 1
                Text {
                    id: nameLabel
                    anchors { verticalCenter: parent.verticalCenter; left: parent.left; right: parent.right; margins: 10 }
                    text: root.pendingDeleteName; color: ThemeManager.textPrimary; font.pixelSize: 13; wrapMode: Text.WrapAnywhere
                }
            }
            TextField {
                id: deleteNameField; Layout.fillWidth: true; placeholderText: root.pendingDeleteName
                color: ThemeManager.textPrimary; placeholderTextColor: ThemeManager.textPlaceholder; font.pixelSize: 13
                leftPadding: 10; rightPadding: 10; topPadding: 8; bottomPadding: 8
                background: Rectangle {
                    radius: 6; color: ThemeManager.surfaceDim; Behavior on color { ColorAnimation { duration: 200 } }
                    border.color: deleteNameField.activeFocus ? ThemeManager.accent : ThemeManager.borderLight; border.width: 1
                }
                Keys.onReturnPressed: {
                    if (text === root.pendingDeleteName) { deleteStep2Popup.close(); ExperimentManager.deleteExperiment(root.pendingDeleteName) }
                }
            }
            RowLayout {
                Layout.fillWidth: true; spacing: 10; Item { Layout.fillWidth: true }
                GhostButton { text: LanguageManager.tr3("Cancelar", "Cancel", "Cancelar"); onClicked: deleteStep2Popup.close() }
                Button {
                    text: LanguageManager.tr3("Excluir Definitivamente", "Delete Permanently", "Eliminar Definitivamente")
                    enabled: deleteNameField.text === root.pendingDeleteName
                    onClicked: { deleteStep2Popup.close(); ExperimentManager.deleteExperiment(root.pendingDeleteName) }
                    background: Rectangle {
                        radius: 7; color: parent.enabled ? (parent.hovered ? ThemeManager.accentHover : ThemeManager.accent) : ThemeManager.surfaceDim
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                    contentItem: Text { text: parent.text; color: ThemeManager.buttonText; font.pixelSize: 12; font.weight: Font.Bold; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    leftPadding: 16; rightPadding: 16; topPadding: 8; bottomPadding: 8
                }
            }
        }
    }
}


