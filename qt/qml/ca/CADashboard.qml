// qml/ca/CADashboard.qml
// Dashboard Campo Aberto: sidebar de experimentos + análise de habituação.

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
            ExperimentManager.loadAllContexts("campo_aberto")
        }
        if (initialExperimentName !== "") {
            experimentList.selectExperimentByName(initialExperimentName)
            innerTabs.currentIndex = 0
        }
    }

    property string pendingDeleteName: ""

    function _isCurrentSelectionStillInModel() {
        if (!workArea.selectedName || !workArea.selectedPath)
            return false
        var m = ExperimentManager.model
        if (!m) return false
        for (var i = 0; i < m.count; ++i) {
            var idx = m.index(i, 0)
            var name = m.data(idx, Qt.UserRole + 1)
            var path = m.data(idx, Qt.UserRole + 2)
            if (name === workArea.selectedName && path === workArea.selectedPath)
                return true
        }
        return false
    }

    function _resetSelectionState() {
        try {
            if (liveRecordingTab && liveRecordingTab.isAnalyzing)
                liveRecordingTab.stopSession()
        } catch (e) {}
        try {
            if (tabArenaSetup && tabArenaSetup.stopCameraPreview)
                tabArenaSetup.stopCameraPreview()
        } catch (e2) {}
        try {
            if (eiArenaSetupCA && eiArenaSetupCA.stopCameraPreview)
                eiArenaSetupCA.stopCameraPreview()
        } catch (e3) {}

        workArea.selectedName = ""
        workArea.selectedPath = ""
        workArea.analysisMode = "offline"
        workArea.saveDirectory = ""
        workArea.cameraId = ""
        workStack.currentIndex = 0
        innerTabs.currentIndex = 0
        experimentList.currentIndex = -1
    }

    function _syncSelectionWithModel() {
        if (!workArea.selectedName && !workArea.selectedPath)
            return
        if (!_isCurrentSelectionStillInModel())
            _resetSelectionState()
    }

    onContextChanged: {
        if (!root.searchMode && context !== "")
            ExperimentManager.loadContext(context, "campo_aberto")
    }

    Rectangle { anchors.fill: parent; color: ThemeManager.background; Behavior on color { ColorAnimation { duration: 200 } } }

    Connections {
        target: ExperimentManager

        function onErrorOccurred(message) { errorToast.show(message) }

        function onExperimentCreated(name, path) {
            successToast.show(LanguageManager.tr3("Experimento \"", "Experiment \"", "Experimento \"") + name + LanguageManager.tr3("\" criado!", "\" created!", "\" creado!"))
            experimentList.selectExperimentByName(name)
            innerTabs.currentIndex = 0
        }

        function onExperimentDeleted(name) {
            successToast.show(LanguageManager.tr3("Experimento \"", "Experiment \"", "Experimento \"") + name + LanguageManager.tr3("\" excluido.", "\" deleted.", "\" eliminado."))
            root._syncSelectionWithModel()
        }

        function onSessionDataInserted(experimentName, sessionPath) {
            if (workArea.selectedName === experimentName) {
                tableModel.loadCsv(workArea.selectedPath + "/tracking_data.csv")
                successToast.show(LanguageManager.tr3("Sessao registrada!", "Session saved!", "Sesion guardada!"))
                innerTabs.currentIndex = 1
            }
        }
    }

    Connections {
        target: ExperimentManager.model
        function onRowsRemoved() { root._syncSelectionWithModel() }
        function onModelReset() { root._syncSelectionWithModel() }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // â"€â"€ Barra superior â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€
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

                Text { text: "🐁"; font.pixelSize: 20 }

                Text {
                    text: root.searchMode
                          ? LanguageManager.tr3("Campo Aberto - Experimentos", "Open Field - Experiments", "Campo Abierto - Experimentos")
                          : LanguageManager.tr3("Campo Aberto - Dashboard", "Open Field - Dashboard", "Campo Abierto - Panel")
                    color: ThemeManager.textPrimary; font.pixelSize: 16; font.weight: Font.Bold
                    Behavior on color { ColorAnimation { duration: 150 } }
                }

                Rectangle {
                    visible: root.numCampos > 0 && !root.searchMode
                    radius: 4; color: ThemeManager.surfaceHover
                    border.color: "#3d7aab"; border.width: 1
                    Behavior on color { ColorAnimation { duration: 200 } }
                    implicitWidth: numLabel.implicitWidth + 16; implicitHeight: 24
                    Text {
                        id: numLabel
                        anchors.centerIn: parent
                        text: root.numCampos + " campo" + (root.numCampos > 1 ? "s" : "")
                        color: "#3d7aab"; font.pixelSize: 11; font.weight: Font.Bold
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                }

                Item { Layout.fillWidth: true }
            }
        }

        // â"€â"€ Corpo â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // â"€â"€ Sidebar â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€
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
                            border.color: searchField.activeFocus ? "#3d7aab" : ThemeManager.borderLight; border.width: 1
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
                            color: isSelected ? "#3d7aab" : (isHovered ? ThemeManager.surfaceAlt : "transparent")
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
                                    color: trashArea.containsMouse ? "#5590cc" : "#3d7aab"
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

            // â"€â"€ Área de trabalho â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€
            Item {
                id: workArea
                Layout.fillWidth: true; Layout.fillHeight: true

                property string selectedName: ""
                property string selectedPath: ""
                property int    colCount:     0
                property bool   includeDrug:      true
                property bool   hasReactivation:  false
                property var    dayNames:         []
                property string analysisMode:     "offline"
                property string cameraId:         ""
                property int    activeNumCampos:  root.numCampos

                function loadExperiment(name, path) {
                    selectedName = name
                    selectedPath = path
                    tableModel.loadCsv(path + "/tracking_data.csv")
                    workStack.currentIndex = 1

                    var meta = ExperimentManager.readMetadataFromPath(path)
                    var ctx  = meta.context || ""
                    ExperimentManager.setActiveContext(ctx)

                    includeDrug     = meta.includeDrug !== false
                    hasReactivation = meta.hasReactivation === true
                    dayNames        = meta.dayNames || (meta.hasReactivation
                                      ? [LanguageManager.tr3("Treino", "Training", "Entrenamiento"), LanguageManager.tr3("Reativacao", "Reactivation", "Reactivacion"), LanguageManager.tr3("Teste", "Test", "Prueba")]
                                      : [LanguageManager.tr3("Treino", "Training", "Entrenamiento"), LanguageManager.tr3("Teste", "Test", "Prueba")])
                    activeNumCampos = meta.numCampos || root.numCampos

                    if (activeNumCampos === 1) {
                        ArenaConfigModel.loadConfigFromPath(path, ":/arena_config_ei_referencia.json")
                        // If stored config has NOR-format floorPoints (4 pts), EIArenaSetup pads
                        // missing pts with {x:0.5,y:0.5}, creating bugged walls. Reset to EI ref.
                        Qt.callLater(function() {
                            var fp = JSON.parse(ArenaConfigModel.getFloorPoints() || "[]")
                            var pts = (fp.length > 0 && Array.isArray(fp[0])) ? fp[0] : fp
                            if (!Array.isArray(pts) || pts.length < 8)
                                ArenaConfigModel.loadConfigFromPath("", ":/arena_config_ei_referencia.json")
                        })
                    } else {
                        ArenaConfigModel.loadConfigFromPath(path)
                    }

                    innerTabs.currentIndex = 0
                }

                ExperimentTableModel { id: tableModel }
                Connections { target: tableModel; function onModelReset() { workArea.colCount = tableModel.columnCount() } }

                StackLayout {
                    id: workStack
                    anchors.fill: parent
                    currentIndex: 0

                    // 0: Placeholder
                    Item {
                        ColumnLayout {
                            anchors.centerIn: parent; spacing: 12
                            Text { Layout.alignment: Qt.AlignHCenter; text: "🐁"; font.pixelSize: 48; opacity: 0.3 }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                        text: LanguageManager.tr3("Selecione um experimento\nna barra lateral", "Select an experiment\nin the sidebar", "Seleccione un experimento\nen la barra lateral")
                                color: ThemeManager.textSecondary; font.pixelSize: 14
                                Behavior on color { ColorAnimation { duration: 150 } }
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }

                    // 1: Experimento (tab bar + conteúdo)
                    ColumnLayout {
                        spacing: 0

                        Rectangle {
                            Layout.fillWidth: true; height: 40
                            color: ThemeManager.surface; Behavior on color { ColorAnimation { duration: 200 } }
                            Rectangle {
                                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                height: 1; color: ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } }
                            }

                            Row {
                                anchors { left: parent.left; leftMargin: 16; top: parent.top; bottom: parent.bottom }
                                spacing: 0

                                Repeater {
                                    id: innerTabs
                                    property int currentIndex: 0
                                    model: ["🗺 " + LanguageManager.tr3("Arena", "Arena", "Arena"), "🎬 " + LanguageManager.tr3("Gravacao", "Recording", "Grabacion"), "📊 " + LanguageManager.tr3("Dados", "Data", "Datos")]

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
                                            color: parent.isActive ? "#3d7aab" : (parent.isHovered ? "#5590cc" : "transparent")
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
                            }

                            Text {
                                anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                                text: workArea.selectedName
                                color: ThemeManager.textTertiary; font.pixelSize: 12; elide: Text.ElideRight
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }
                        }

                        StackLayout {
                            id: innerStack
                            Layout.fillWidth: true; Layout.fillHeight: true
                            currentIndex: innerTabs.currentIndex

                            // â"€â"€ Tab 0: Arena â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€
                            Item {
                                // ArenaSetup padrão â€" 2 ou 3 campos
                                ArenaSetup {
                                    id: tabArenaSetup
                                    anchors.fill: parent
                                    visible: workArea.activeNumCampos > 1
                                    experimentPath: workArea.activeNumCampos > 1 ? workArea.selectedPath : ""
                                    context: root.context
                                    numCampos: workArea.activeNumCampos
                                    aparato: "campo_aberto"
                                    caMode: true

                                    onAnalysisModeChangedExternally: function(mode) {
                                        workArea.analysisMode = mode
                                        workArea.cameraId     = tabArenaSetup.cameraId
                                        if (mode !== "offline") workArea.saveDirectory = tabArenaSetup.saveDirectory
                                    }
                                    onZonasEditadas: {
                                        if (workArea.activeNumCampos === 1) return
                                        liveRecordingTab.arenaPoints = tabArenaSetup.arenaPoints
                                        liveRecordingTab.floorPoints = tabArenaSetup.floorPoints
                                        liveRecordingTab.centroRatio = tabArenaSetup.centroRatio
                                    }
                                    onCentroRatioChanged: {
                                        if (workArea.activeNumCampos > 1)
                                            liveRecordingTab.centroRatio = tabArenaSetup.centroRatio
                                    }
                                }

                                // EIArenaSetup â€" 1 campo (arena EI adaptada para CA)
                                EIArenaSetup {
                                    id: eiArenaSetupCA
                                    anchors.fill: parent
                                    visible: workArea.activeNumCampos === 1
                                    experimentPath: workArea.activeNumCampos === 1 ? workArea.selectedPath : ""
                                    numCampos: 1
                                    primaryColor:   "#3d7aab"
                                    secondaryColor: "#2d5f8a"

                                    onAnalysisModeChangedExternally: function(mode) {
                                        workArea.analysisMode = mode
                                        workArea.cameraId     = eiArenaSetupCA.cameraId
                                        if (mode !== "offline") workArea.saveDirectory = eiArenaSetupCA.saveDirectory
                                    }
                                    onZonasEditadas: {
                                        liveRecordingTab.zones       = []
                                        liveRecordingTab.centroRatio = 0
                                        liveRecordingTab.arenaPoints = eiArenaSetupCA.arenaPoints
                                        liveRecordingTab.floorPoints = eiArenaSetupCA.floorPoints
                                    }
                                }
                            }

                            // â"€â"€ Tab 1: Gravação â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€
                            LiveRecording {
                                id: liveRecordingTab
                                videoPath:    workArea.activeNumCampos === 1 ? eiArenaSetupCA.videoPath : tabArenaSetup.videoPath
                                analysisMode: workArea.analysisMode
                                saveDirectory: workArea.saveDirectory
                                liveOutputName: workArea.activeNumCampos === 1 ? eiArenaSetupCA.liveOutputName : tabArenaSetup.liveOutputName
                                cameraId:     workArea.cameraId
                                numCampos:    workArea.activeNumCampos
                                aparato: workArea.activeNumCampos === 1 ? "esquiva_inibitoria" : "campo_aberto"

                                // CA usa pontos para desenhar Centro/Borda
                                zones:       ArenaConfigModel.zones
                                arenaPoints: JSON.parse(ArenaConfigModel.getArenaPoints() || "[]")
                                floorPoints: JSON.parse(ArenaConfigModel.getFloorPoints() || "[]")
                                centroRatio: workArea.activeNumCampos === 1 ? 0 : (function() {
                                    var m = ExperimentManager.readMetadataFromPath(workArea.selectedPath)
                                    return m.centroRatio || 0.5
                                })()

                                // Atualiza zonas, arena e chão ao vivo quando a config é salva
                                Connections {
                                    target: ArenaConfigModel
                                    function onConfigChanged() {
                                        liveRecordingTab.arenaPoints = JSON.parse(ArenaConfigModel.getArenaPoints() || "[]")
                                        liveRecordingTab.floorPoints = JSON.parse(ArenaConfigModel.getFloorPoints() || "[]")
                                        if (workArea.activeNumCampos > 1) {
                                            var m = ExperimentManager.readMetadataFromPath(workArea.selectedPath)
                                            liveRecordingTab.centroRatio = m.centroRatio || 0.5
                                        } else {
                                            liveRecordingTab.centroRatio = 0
                                        }
                                    }
                                }

                                onSessionEnded: {
                                    caResultDialog.totalDistance    = liveRecordingTab.totalDistance
                                    caResultDialog.avgVelocity      = liveRecordingTab.avgVelocityMeans
                                    caResultDialog.perMinuteData    = liveRecordingTab.perMinuteData
                                    caResultDialog.explorationTimes = liveRecordingTab.explorationTimes
                                    caResultDialog.explorationBouts = liveRecordingTab.explorationBouts
                                    caResultDialog.includeDrug      = workArea.includeDrug
                                    caResultDialog.hasReactivation  = workArea.hasReactivation
                                    caResultDialog.dayNames         = workArea.dayNames
                                    caResultDialog.experimentName   = workArea.selectedName
                                    caResultDialog.experimentPath   = workArea.selectedPath
                                    caResultDialog.numCampos        = workArea.activeNumCampos
                                    caResultDialog.videoPath        = workArea.analysisMode === "ao_vivo"
                                                                      ? ((liveRecordingTab.liveRecordedVideoPath && liveRecordingTab.liveRecordedVideoPath !== "")
                                                                         ? liveRecordingTab.liveRecordedVideoPath
                                                                         : ("camera://" + workArea.cameraId))
                                                                      : (workArea.activeNumCampos === 1 ? eiArenaSetupCA.videoPath : tabArenaSetup.videoPath)
                                    caResultDialog.open()
                                }

                                onLiveAnalysisStarting: {
                                    tabArenaSetup.stopCameraPreview()
                                    eiArenaSetupCA.stopCameraPreview()
                                }

                                onRequestVideoLoad: {
                                    innerTabs.currentIndex = 0
                                }
                            }

                            // â"€â"€ Tab 2: Dados â€" Layout aparato-específico
                            DataView {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                tableModel: tableModel
                                workArea: workArea
                            }
                        }
                    }
                }
            }
        }
    }

    // â"€â"€ Diálogo de resultado CA â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€
    CAMetadataDialog {
        id: caResultDialog
        parent: Overlay.overlay
        anchors.centerIn: parent
    }

    // â"€â"€ Toasts â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€
    Toast { id: successToast; anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 16 } }
    Toast { id: errorToast;   anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 16 } }

    // â"€â"€ Popup delete â€" Passo 1 â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€
    Popup {
        id: deleteStep1Popup
        anchors.centerIn: parent
        width: 400
        height: step1Layout.implicitHeight + 56
        modal: true; focus: true; closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle { radius: 14; color: ThemeManager.surface; Behavior on color { ColorAnimation { duration: 200 } } border.color: ThemeManager.borderLight; border.width: 1 }

        ColumnLayout {
            id: step1Layout
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
            spacing: 14
            Text { text: "Excluir Experimento"; color: ThemeManager.textPrimary; font.pixelSize: 16; font.weight: Font.Bold; Behavior on color { ColorAnimation { duration: 150 } } }
            Text {
                Layout.fillWidth: true
                text: "Tem certeza que deseja excluir\n\"" + root.pendingDeleteName + "\"?\n\nEsta ação é irreversível."
                color: ThemeManager.textSecondary; font.pixelSize: 13; wrapMode: Text.WordWrap; Behavior on color { ColorAnimation { duration: 150 } }
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

    // â"€â"€ Popup delete â€" Passo 2 (Confirmar digitando o nome) â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€
    Popup {
        id: deleteStep2Popup
        anchors.centerIn: parent
        width: 420
        height: step2Layout.implicitHeight + 56
        modal: true; focus: true; closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onOpened: deleteNameField.forceActiveFocus()
        background: Rectangle { radius: 14; color: ThemeManager.surface; Behavior on color { ColorAnimation { duration: 200 } } border.color: ThemeManager.accent; border.width: 1 }

        ColumnLayout {
            id: step2Layout
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
            spacing: 14
            Text { text: "Confirmação Final"; color: ThemeManager.textPrimary; font.pixelSize: 16; font.weight: Font.Bold; Behavior on color { ColorAnimation { duration: 150 } } }
            Text {
                Layout.fillWidth: true
                text: "Para confirmar, digite o nome do experimento:"
                color: ThemeManager.textSecondary; font.pixelSize: 13; wrapMode: Text.WordWrap; Behavior on color { ColorAnimation { duration: 150 } }
            }
            Rectangle {
                Layout.fillWidth: true; height: nameLabel.implicitHeight + 10; radius: 5
                color: ThemeManager.surfaceDim; border.color: ThemeManager.borderLight; border.width: 1
                Text {
                    id: nameLabel
                    anchors { verticalCenter: parent.verticalCenter; left: parent.left; right: parent.right; margins: 10 }
                    text: root.pendingDeleteName; color: ThemeManager.textPrimary; font.pixelSize: 13; font.family: "Consolas, monospace"; font.weight: Font.Medium; wrapMode: Text.WrapAnywhere
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
                    if (text === root.pendingDeleteName) {
                        deleteStep2Popup.close()
                        if (workArea.selectedName === root.pendingDeleteName)
                            root._resetSelectionState()
                        ExperimentManager.deleteExperiment(root.pendingDeleteName)
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true; spacing: 10; Item { Layout.fillWidth: true }
                GhostButton { text: "Cancelar"; onClicked: deleteStep2Popup.close() }
                Button {
                    text: "Excluir Definitivamente"
                    enabled: deleteNameField.text === root.pendingDeleteName
                    onClicked: {
                        deleteStep2Popup.close()
                        if (workArea.selectedName === root.pendingDeleteName)
                            root._resetSelectionState()
                        ExperimentManager.deleteExperiment(root.pendingDeleteName)
                    }
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
