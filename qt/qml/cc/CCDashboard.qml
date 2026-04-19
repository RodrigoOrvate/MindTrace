// qml/cc/CCDashboard.qml
// Dashboard Comportamento Complexo: sidebar + Arena + Gravação + Classificação + Dados.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtMultimedia
import "../core"
import "../core/Theme"
import "../shared"
import "../nor"
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

    // ── B-SOiD ────────────────────────────────────────────────────────────
    property bool   bsoidRunning:   false
    property int    bsoidProgress:  0
    property var    bsoidGroups:    []   // lista de {clusterId, frameCount, percentage, ...}
    property var    bsoidGroupNames: []  // nomes personalizados dos clusters (editáveis)
    property string bsoidError:     ""
    property bool   bsoidDone:      false
    property double bsoidFps:       30.0
    property string bsoidVideoPath: ""
    property int    bsoidCampo:     0    // campo selecionado para análise (0=C1, 1=C2, 2=C3)

    // ── Estatísticas de comportamento (computadas após B-SOiD) ────────────
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

    // ── Snippets ──────────────────────────────────────────────────────────
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
            // Computa estatísticas por comportamento
            root.behaviorStats = root.computeBehaviorStats(root.bsoidFps)
            // Preenche timeline dupla a partir de C++ (mais eficiente que iterar em JS)
            Qt.callLater(function() {
                ruleTimeline.clear()
                clusterTimeline.clear()
                // Cores para regras nativas — alinhadas com badges e legenda
                ruleTimeline.setLabelColor(0, "#8b5cf6")  // Walking  → violeta
                ruleTimeline.setLabelColor(1, "#f97316")  // Zonas de objetos → laranja
                ruleTimeline.setLabelColor(2, "#eab308")  // Grooming → amarelo
                ruleTimeline.setLabelColor(3, "#3b82f6")  // Resting  → azul
                ruleTimeline.setLabelColor(4, "#10b981")  // Rearing  → verde
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

    // Cores dos clusters B-SOiD — família vermelhos/amarelos/violetas,
    // deliberadamente distintas das regras nativas:
    // Walking=#10b981(verde), Sniffing=#3b82f6(azul), Grooming=#ec4899(rosa),
    // Resting=#6b7280(cinza), Rearing=#f97316(laranja)
    readonly property var bsoidColors: [
        "#ef4444",  // vermelho      G1
        "#eab308",  // amarelo       G2
        "#8b5cf6",  // violeta       G3
        "#d946ef",  // fúcsia        G4
        "#6366f1",  // índigo        G5
        "#dc2626",  // vermelho esc  G6
        "#ca8a04",  // ouro          G7
        "#7c3aed",  // violeta esc   G8
        "#c026d3",  // magenta       G9
        "#be123c",  // carmim        G10
        "#a21caf",  // magenta esc   G11
        "#4f46e5"   // índigo esc    G12
    ]

    function bsoidRuleName(ruleId) {
        var names = ["Walking","Zonas de objetos","Grooming","Resting","Rearing"]
        return (ruleId >= 0 && ruleId < names.length) ? names[ruleId] : "?"
    }

    function startBsoidAnalysis() {
        if (root.bsoidRunning) return
        var campo = root.bsoidCampo
        var sessionPath = workArea.selectedPath  // pasta do experimento
        if (!sessionPath) { root.bsoidError = "Nenhum experimento selecionado."; return }
        var csvPath = sessionPath + "/bsoid_features_campo" + (campo + 1) + "_tmp.csv"
        var ok = liveRecordingTab.exportBehaviorFeatures(csvPath, campo)
        if (!ok) { root.bsoidError = "Nenhum dado de features disponível. Execute uma análise primeiro."; return }
        // Captura FPS e caminho do vídeo para timeline e snippets
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
            successToast.show("Experimento \"" + name + "\" criado!")
            experimentList.selectExperimentByName(name)
            innerTabs.currentIndex = 0
        }

        onExperimentDeleted: {
            successToast.show("Experimento \"" + name + "\" excluído.")
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
                successToast.show("Sessão registrada!")
                innerTabs.currentIndex = 2  // aba Classificação
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── Barra superior ───────────────────────────────────────────────
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

                GhostButton { text: "← Voltar"; onClicked: root.backRequested() }

                Text { text: "🧩"; font.pixelSize: 20 }

                Text {
                    text: root.searchMode
                          ? "Comportamento Complexo — Experimentos"
                          : "Comportamento Complexo — Dashboard"
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
                        text: root.numCampos + " campo" + (root.numCampos > 1 ? "s" : "")
                        color: "#7a3dab"; font.pixelSize: 11; font.weight: Font.Bold
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                }

                Item { Layout.fillWidth: true }
            }
        }

        // ── Corpo ────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // ── Sidebar ──────────────────────────────────────────────────
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
                        text: "Experimentos"
                        color: ThemeManager.textPrimary; font.pixelSize: 12; font.weight: Font.Bold
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    TextField {
                        id: searchField
                        Layout.fillWidth: true
                        placeholderText: "Pesquisar…"
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
                                    anchors.centerIn: parent; text: "🗑"; font.pixelSize: 13
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
                            text: "Nenhum experimento\nencontrado"
                            color: ThemeManager.textSecondary; font.pixelSize: 12
                            Behavior on color { ColorAnimation { duration: 150 } }
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }
            }

            // ── Área de trabalho ─────────────────────────────────────────
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

                    ArenaConfigModel.loadConfigFromPath(path)

                    var meta = ExperimentManager.readMetadataFromPath(path)
                    var ctx  = meta.context || ""
                    ExperimentManager.setActiveContext(ctx)

                    includeDrug     = meta.includeDrug !== false
                    hasObjectZones  = meta.hasObjectZones !== false
                    activeNumCampos = meta.numCampos || root.numCampos
                    sessionMinutes  = meta.sessionMinutes || 5
                    dayNames        = meta.dayNames || Array.from({length: meta.sessionDays || 5}, function(_, i) { return "Dia " + (i+1) })

                    // Propaga pontos de arena para aba Gravação
                    liveRecordingTab.arenaPoints = JSON.parse(ArenaConfigModel.getArenaPoints() || "[]")
                    liveRecordingTab.floorPoints = JSON.parse(ArenaConfigModel.getFloorPoints() || "[]")
                    
                    // Propaga zonas se hasObjectZones; limpa explicitamente se não
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

                    // Índice 0: placeholder "selecione um experimento"
                    Item {
                        ColumnLayout {
                            anchors.centerIn: parent; spacing: 14
                            Text { text: "🧩"; font.pixelSize: 48; opacity: 0.15; Layout.alignment: Qt.AlignHCenter }
                            Text {
                                text: "Selecione um experimento"
                                color: ThemeManager.textSecondary; font.pixelSize: 16
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }
                    }

                    // Índice 1: painel com abas
                    ColumnLayout {
                        spacing: 0

                        // ── Barra de abas interna ─────────────────────────
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
                                    model: ["Arena", "Gravação", "Classificação", "Dados"]

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

                            // ── Tab 0: Arena ──────────────────────────────
                            ArenaSetup {
                                id: tabArenaSetup
                                experimentPath: workArea.selectedPath
                                context: root.context
                                numCampos: workArea.activeNumCampos
                                aparato: "comportamento_complexo"
                                caMode: true   // sem objetos NOR
                                ccMode: true   // sem centro
                                showObjectZones: workArea.hasObjectZones

                                onAnalysisModeChangedExternally: mode => {
                                    workArea.analysisMode  = mode
                                    innerTabs.currentIndex = 1
                                }

                                // Propagação ao vivo Arena → Gravação
                                onZonasEditadas: {
                                    liveRecordingTab.zones        = workArea.hasObjectZones ? tabArenaSetup.zones : []
                                    liveRecordingTab.arenaPoints = tabArenaSetup.arenaPoints
                                    liveRecordingTab.floorPoints = tabArenaSetup.floorPoints
                                }
                            }

                            // ── Tab 1: Gravação ───────────────────────────
                            LiveRecording {
                                id: liveRecordingTab
                                videoPath:    tabArenaSetup.videoPath
                                analysisMode: workArea.analysisMode
                                numCampos:    workArea.activeNumCampos
                                aparato:      "comportamento_complexo"
                                sessionDurationMinutes: workArea.sessionMinutes

                                zones:        workArea.hasObjectZones ? tabArenaSetup.zones : []
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
                                    ccResultDialog.includeDrug    = workArea.includeDrug
                                    ccResultDialog.experimentName = workArea.selectedName
                                    ccResultDialog.experimentPath = workArea.selectedPath
                                    ccResultDialog.numCampos      = workArea.activeNumCampos
                                    ccResultDialog.videoPath      = tabArenaSetup.videoPath
                                    ccResultDialog.dayNames       = workArea.dayNames
                                    ccResultDialog.open()
                                }

                                onRequestVideoLoad: {
                                    innerTabs.currentIndex = 0
                                }
                            }

                            // ── Tab 2: Classificação ──────────────────────
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

                                            // Título
                                            RowLayout {
                                                Layout.alignment: Qt.AlignHCenter
                                                spacing: 12
                                                Text { text: "🧠"; font.pixelSize: 30 }
                                                ColumnLayout {
                                                    spacing: 2
                                                    Text {
                                                        text: "Análise Comportamental Nativa"
                                                        color: ThemeManager.textPrimary
                                                        font.pixelSize: 20; font.weight: Font.Bold
                                                        Behavior on color { ColorAnimation { duration: 150 } }
                                                    }
                                                    Text {
                                                        text: "Classificação por regras em tempo real · B-SOiD disponível pós-sessão"
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
                                                    Text { text: "⚙️"; font.pixelSize: 20 }
                                                    ColumnLayout {
                                                        spacing: 2
                                                        Text {
                                                            text: "Motor de Regras Nativo (C++)"
                                                            color: ThemeManager.textPrimary; font.weight: Font.Bold; font.pixelSize: 13
                                                            Behavior on color { ColorAnimation { duration: 150 } }
                                                        }
                                                        Text {
                                                            text: "Zonas de objetos · Rearing · Resting · Grooming · Walking — sem modelo ONNX"
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
                                                            text: "✅ ATIVO"
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
                                                                text: "Campo " + (index + 1)
                                                                color: ThemeManager.textSecondary
                                                                font.pixelSize: 13; font.weight: Font.Bold
                                                                Behavior on color { ColorAnimation { duration: 150 } }
                                                            }
                                                            Rectangle {
                                                                Layout.alignment: Qt.AlignHCenter
                                                                radius: 6; implicitHeight: 36; implicitWidth: bhvTxt.implicitWidth + 36
                                                                property string bhvName: liveRecordingTab.currentBehaviorString[index] || "Detectando..."
                                                                property color badgeColor: {
                                                                    if (bhvName === "Walking")  return "#8b5cf6"
                                                                    if (bhvName === "Resting")  return "#3b82f6"
                                                                    if (bhvName === "Rearing")  return "#10b981"
                                                                    if (bhvName === "Grooming") return "#eab308"
                                                                    if (bhvName === "Zonas de objetos") return "#f97316"
                                                                    return ThemeManager.surfaceAlt
                                                                }
                                                                color: badgeColor
                                                                Behavior on color { ColorAnimation { duration: 250 } }
                                                                Text {
                                                                    id: bhvTxt
                                                                    anchors.centerIn: parent
                                                                    text: parent.bhvName
                                                                    color: parent.bhvName === "Detectando..." ? ThemeManager.textSecondary : "#ffffff"
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
                                                        model: ["Walking|#8b5cf6", "Zonas de objetos|#f97316", "Grooming|#eab308", "Resting|#3b82f6", "Rearing|#10b981"]
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
                                                    text: "🔬  B-SOiD"
                                                    color: ThemeManager.textSecondary; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.2
                                                    Behavior on color { ColorAnimation { duration: 150 } }
                                                }
                                                Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } } }
                                            }

                                            // Card B-SOiD (pós-sessão — interativo)
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

                                                    // Header: título + status + botão
                                                    RowLayout {
                                                        spacing: 10
                                                        Text { text: "🔬"; font.pixelSize: 18 }
                                                        ColumnLayout {
                                                            spacing: 2
                                                            Text {
                                                                text: "Análise B-SOiD (Pós-Sessão)"
                                                                color: ThemeManager.textPrimary; font.weight: Font.Bold; font.pixelSize: 13
                                                                Behavior on color { ColorAnimation { duration: 150 } }
                                                            }
                                                            Text {
                                                                text: "Agrupa frames por padrão de movimento via PCA + K-Means"
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
                                                                text: root.bsoidDone    ? "✅ Concluído"
                                                                    : root.bsoidRunning ? "⏳ " + root.bsoidProgress + "%"
                                                                    : "⏳ Aguarda"
                                                                color: root.bsoidDone ? ThemeManager.success : "#8888cc"
                                                                font.pixelSize: 11; font.weight: Font.Bold
                                                                Behavior on color { ColorAnimation { duration: 200 } }
                                                            }
                                                        }

                                                        // Seletor de campo
                                                        RowLayout {
                                                            spacing: 4
                                                            Text {
                                                                text: "Campo:"
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

                                                        // Botão Analisar
                                                        Button {
                                                            visible: !root.bsoidRunning
                                                            text: root.bsoidDone ? "↻ Re-analisar" : "▶ Analisar"
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

                                                        // Spinner durante análise
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
                                                        text: "⚠️ " + root.bsoidError
                                                        color: "#ef4444"; font.pixelSize: 11
                                                        wrapMode: Text.WordWrap; Layout.fillWidth: true
                                                    }

                                                    // Texto de ajuda (apenas antes da análise)
                                                    Text {
                                                        visible: !root.bsoidDone && !root.bsoidRunning && root.bsoidError === ""
                                                        text: "Clique em Analisar após finalizar a gravação. O algoritmo analisa os dados de trajetória\ncoletados e descobre grupos comportamentais adicionais às regras nativas."
                                                        color: ThemeManager.textTertiary; font.pixelSize: 11
                                                        wrapMode: Text.WordWrap; Layout.fillWidth: true
                                                        Behavior on color { ColorAnimation { duration: 150 } }
                                                    }

                                                    // ── Estatísticas por comportamento (pós B-SOiD) ─────────────────────
                                                    ColumnLayout {
                                                        visible: root.bsoidDone && root.behaviorStats.length > 0
                                                        Layout.fillWidth: true; spacing: 6

                                                        Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } } }

                                                        Text {
                                                            text: "COMPORTAMENTOS — DURAÇÃO E BOUTS  ·  C" + (root.bsoidCampo + 1)
                                                            color: ThemeManager.textSecondary
                                                            font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 1.2
                                                            Behavior on color { ColorAnimation { duration: 150 } }
                                                        }

                                                        // Cabeçalho tabela
                                                        RowLayout {
                                                            Layout.fillWidth: true; spacing: 0
                                                            Text { text: "Comportamento"; width: 100; color: ThemeManager.textTertiary; font.pixelSize: 10; font.weight: Font.Bold }
                                                            Text { text: "Tempo (s)";     width: 80;  color: ThemeManager.textTertiary; font.pixelSize: 10; font.weight: Font.Bold; horizontalAlignment: Text.AlignRight }
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
                                                                text: "GRUPOS DESCOBERTOS — " + root.bsoidGroups.length + " clusters  ·  C" + (root.bsoidCampo + 1)
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
                                                                Text { text: "💡"; font.pixelSize: 13 }
                                                                Text {
                                                                    Layout.fillWidth: true
                                                                    text: "Extraia os clips abaixo, assista a cada grupo e nomeie o comportamento que está vendo."
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
                                                                            text: "Grupo " + (grp.clusterId + 1)
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
                                                                            text: "≈ " + root.bsoidRuleName(grp.dominantRule)
                                                                            color: ThemeManager.textTertiary; font.pixelSize: 10
                                                                            Behavior on color { ColorAnimation { duration: 150 } }
                                                                        }
                                                                    }

                                                                    // Campo de nomeação do grupo
                                                                    RowLayout {
                                                                        spacing: 6
                                                                        Text {
                                                                            text: "Nome:"
                                                                            color: ThemeManager.textTertiary; font.pixelSize: 10
                                                                            Behavior on color { ColorAnimation { duration: 150 } }
                                                                        }
                                                                        TextField {
                                                                            id: groupNameField
                                                                            Layout.fillWidth: true; height: 26
                                                                            // Sem binding reativo — inicializa uma vez; onTextEdited atualiza o array
                                                                            Component.onCompleted: {
                                                                                text = (root.bsoidGroupNames && root.bsoidGroupNames.length > grpIdx)
                                                                                       ? (root.bsoidGroupNames[grpIdx] || "") : ""
                                                                            }
                                                                            placeholderText: "Ex.: Exploração, Repouso, Grooming…"
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

                                                    // ── Timeline Dupla ──────────────────────────────────────────────────
                                                    ColumnLayout {
                                                        visible: root.bsoidDone
                                                        Layout.fillWidth: true; spacing: 6

                                                        Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } } }

                                                        Text {
                                                            text: "TIMELINE — REGRAS vs B-SOiD"
                                                            color: ThemeManager.textSecondary
                                                            font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 1.2
                                                            Behavior on color { ColorAnimation { duration: 150 } }
                                                        }

                                                        // Linha 1 — Regras nativas
                                                        RowLayout {
                                                            Layout.fillWidth: true; spacing: 6
                                                            Text {
                                                                text: "Regras"
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

                                                        // Linha 2 — Clusters B-SOiD
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

                                                    // ── Extração de Clips de Vídeo ──────────────────────────────────────
                                                    ColumnLayout {
                                                        visible: root.bsoidDone
                                                        Layout.fillWidth: true; spacing: 6

                                                        Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } } }

                                                        Text {
                                                            text: "CLIPS DE VÍDEO POR GRUPO"
                                                            color: ThemeManager.textSecondary
                                                            font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 1.2
                                                            Behavior on color { ColorAnimation { duration: 150 } }
                                                        }

                                                        RowLayout {
                                                            Layout.fillWidth: true; spacing: 8

                                                            Text {
                                                                Layout.fillWidth: true
                                                                text: root.snippetsComplete
                                                                    ? "📁 Clips salvos em: " + root.snippetsOutDir
                                                                    : root.snippetsRunning
                                                                        ? "⏳ Extraindo... " + root.snippetsProgress + "%"
                                                                        : root.snippetsError !== ""
                                                                            ? "⚠️ " + root.snippetsError
                                                                            : "Extrai até 3 clips .mp4 por grupo. Requer ffmpeg.exe no PATH ou na pasta do app. Sem FFmpeg, salva apenas timestamps.csv."
                                                                color: root.snippetsComplete ? ThemeManager.success
                                                                     : root.snippetsError !== "" ? "#ef4444"
                                                                     : ThemeManager.textTertiary
                                                                font.pixelSize: 10; wrapMode: Text.WordWrap
                                                                Behavior on color { ColorAnimation { duration: 200 } }
                                                            }

                                                            // Abre pasta no Explorer
                                                            Button {
                                                                visible: root.snippetsComplete && !root.snippetsRunning
                                                                text: "📂 Abrir"
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
                                                                text: root.snippetsComplete ? "↻ Re-extrair" : "🎬 Extrair Clips"
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

                            // ── Tab 3: Dados ──────────────────────────────
                            Item {
                                ColumnLayout {
                                    anchors { fill: parent; margins: 24 }
                                    spacing: 12

                                    RowLayout {
                                        spacing: 8
                                        BusyIndicator {
                                            visible: tableModel.fetchingMore; running: tableModel.fetchingMore
                                            implicitWidth: 20; implicitHeight: 20
                                        }
                                        Text {
                                            text: tableView.rows > 0 ? tableView.rows + " linha(s)" : ""
                                            color: ThemeManager.textTertiary; font.pixelSize: 11
                                            Behavior on color { ColorAnimation { duration: 150 } }
                                        }
                                        Item { Layout.fillWidth: true }
                                        GhostButton { text: "＋ Linha"; onClicked: tableModel.addRow() }
                                        Button {
                                            text: "📤 Exportar"
                                            onClicked: {
                                                if (tableModel.exportCsv(workArea.selectedPath + "/export_" +
                                                    new Date().toISOString().substring(0, 10) + ".csv"))
                                                    savedFeedback.show("Exportado!")
                                            }
                                            background: Rectangle {
                                                radius: 7
                                                color: parent.hovered ? ThemeManager.successLight : ThemeManager.success
                                                border.color: ThemeManager.successLight; border.width: 1
                                                Behavior on color { ColorAnimation { duration: 150 } }
                                            }
                                            contentItem: Text {
                                                text: parent.text; color: ThemeManager.buttonText
                                                font.pixelSize: 12; font.weight: Font.Bold
                                                verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter
                                            }
                                            leftPadding: 14; rightPadding: 14; topPadding: 6; bottomPadding: 6
                                        }
                                        Button {
                                            text: "💾 Salvar"
                                            onClicked: { if (tableModel.saveCsv()) savedFeedback.show("Salvo!") }
                                            background: Rectangle {
                                                radius: 7; color: parent.hovered ? "#6a2d9a" : "#7a3dab"
                                                Behavior on color { ColorAnimation { duration: 200 } }
                                            }
                                            contentItem: Text {
                                                text: parent.text; color: ThemeManager.buttonText
                                                font.pixelSize: 12; font.weight: Font.Bold
                                                verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter
                                            }
                                            leftPadding: 14; rightPadding: 14; topPadding: 6; bottomPadding: 6
                                        }
                                    }

                                    Row {
                                        Layout.fillWidth: true
                                        Repeater {
                                            model: workArea.colCount
                                            delegate: Rectangle {
                                                width: Math.max(100, tableView.width / Math.max(1, workArea.colCount))
                                                height: 32; color: ThemeManager.surfaceDim; Behavior on color { ColorAnimation { duration: 200 } }
                                                border.color: ThemeManager.border; border.width: 1; Behavior on border.color { ColorAnimation { duration: 200 } }
                                                Text {
                                                    anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                                                    text: tableModel.headerData(index, Qt.Horizontal, Qt.DisplayRole) || ""
                                                    color: ThemeManager.textSecondary; font.pixelSize: 12; font.weight: Font.Bold
                                                    Behavior on color { ColorAnimation { duration: 150 } }
                                                    verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                                                }
                                            }
                                        }
                                    }

                                    TableView {
                                        id: tableView
                                        Layout.fillWidth: true; Layout.fillHeight: true
                                        clip: true; model: tableModel; reuseItems: true
                                        onWidthChanged: forceLayout()
                                        columnWidthProvider: function(col) {
                                            return Math.max(100, tableView.width / Math.max(1, tableModel.columnCount()))
                                        }
                                        rowHeightProvider: function() { return 32 }
                                        ScrollBar.vertical:   ScrollBar { policy: ScrollBar.AsNeeded; contentItem: Rectangle { implicitWidth: 6; radius: 3; color: ThemeManager.borderLight } }
                                        ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded; contentItem: Rectangle { implicitHeight: 6; radius: 3; color: ThemeManager.borderLight } }

                                        delegate: Rectangle {
                                            implicitWidth: 120; implicitHeight: 32
                                            color: rowDelMa.containsMouse ? ThemeManager.surfaceHover
                                                 : (row % 2 === 0) ? ThemeManager.surface : ThemeManager.surfaceAlt
                                            Behavior on color { ColorAnimation { duration: 200 } }
                                            border.color: ThemeManager.border; border.width: 1; Behavior on border.color { ColorAnimation { duration: 200 } }

                                            Rectangle {
                                                anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 4 }
                                                visible: column === 0 && rowDelMa.containsMouse
                                                width: 20; height: 20; radius: 4
                                                color: rowDelBtnMa.containsMouse ? "#3d2d6a" : "#1a0d2e"; Behavior on color { ColorAnimation { duration: 200 } }
                                                border.color: "#7a3dab"; border.width: 1
                                                Text { anchors.centerIn: parent; text: "✕"; color: "#7a3dab"; font.pixelSize: 9; font.weight: Font.Bold }
                                                MouseArea {
                                                    id: rowDelBtnMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                    onClicked: { tableModel.removeRow(row); tableModel.saveCsv() }
                                                }
                                            }

                                            TextInput {
                                                anchors { fill: parent; leftMargin: 8; rightMargin: (column === 0 && rowDelMa.containsMouse) ? 28 : 8 }
                                                text: model.display !== undefined ? model.display : ""
                                                color: ThemeManager.textPrimary; font.pixelSize: 13; Behavior on color { ColorAnimation { duration: 150 } }
                                                verticalAlignment: Text.AlignVCenter; clip: true; selectByMouse: true
                                                onEditingFinished: tableModel.setData(tableModel.index(row, column), text, Qt.EditRole)
                                            }

                                            MouseArea { id: rowDelMa; anchors.fill: parent; hoverEnabled: true; onPressed: mouse.accepted = false }
                                        }
                                    }
                                }

                                Toast { id: savedFeedback; successMode: true; anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 12 } }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Diálogo de resultado CC ──────────────────────────────────────────
    CCMetadataDialog {
        id: ccResultDialog
        parent: Overlay.overlay
        anchors.centerIn: parent
    }

    // ── Toasts ────────────────────────────────────────────────────────────
    Toast { id: successToast; anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 16 } }
    Toast { id: errorToast;   anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 16 } }

    // ── Popup delete — Passo 1 ────────────────────────────────────────────
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
            Text { text: "Excluir Experimento"; color: ThemeManager.textPrimary; font.pixelSize: 16; font.weight: Font.Bold }
            Text {
                Layout.fillWidth: true
                text: "Tem certeza que deseja excluir\n\"" + root.pendingDeleteName + "\"?\n\nEsta ação é irreversível."
                color: ThemeManager.textSecondary; font.pixelSize: 13; wrapMode: Text.WordWrap
            }
            RowLayout {
                Layout.fillWidth: true; spacing: 10; Item { Layout.fillWidth: true }
                GhostButton { text: "Cancelar"; onClicked: deleteStep1Popup.close() }
                Button {
                    text: "Continuar"
                    onClicked: { deleteStep1Popup.close(); deleteNameField.text = ""; deleteStep2Popup.open() }
                    background: Rectangle { radius: 7; color: parent.hovered ? ThemeManager.accentHover : ThemeManager.accent; Behavior on color { ColorAnimation { duration: 150 } } }
                    contentItem: Text { text: parent.text; color: ThemeManager.buttonText; font.pixelSize: 12; font.weight: Font.Bold; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    leftPadding: 16; rightPadding: 16; topPadding: 8; bottomPadding: 8
                }
            }
        }
    }

    // ── Popup delete — Passo 2 ─────────────────────────────────────────
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
            Text { text: "Confirmação Final"; color: ThemeManager.textPrimary; font.pixelSize: 16; font.weight: Font.Bold }
            Text { Layout.fillWidth: true; text: "Para confirmar, digite o nome do experimento:"; color: ThemeManager.textSecondary; font.pixelSize: 13; wrapMode: Text.WordWrap }
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
                GhostButton { text: "Cancelar"; onClicked: deleteStep2Popup.close() }
                Button {
                    text: "Excluir Definitivamente"
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
