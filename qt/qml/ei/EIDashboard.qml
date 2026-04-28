// qml/ei/EIDashboard.qml
// Inhibitory Avoidance dashboard: sidebar + Arena + Recording + Data.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtMultimedia
import "../core"
import "../core/Theme"
import "../shared"
import MindTrace.Backend 1.0
import MindTrace.Tracking 1.0

Item {
    id: root

    property string context:   ""
    property string arenaId:   ""
    property int    numCampos: 1
    property bool   searchMode: false
    property int    currentTabIndex: 0
    property string initialExperimentName: ""
    property string pendingInitialSelection: ""

    signal backRequested()

    Component.onCompleted: {
        if (root.searchMode) {
            ExperimentManager.loadAllContexts("esquiva_inibitoria")
        } else {
            ExperimentManager.loadContext("Padrão", "esquiva_inibitoria")
        }
        if (initialExperimentName !== "") {
            pendingInitialSelection = initialExperimentName
            initialSelectTimer.start()
        }
    }

    Timer {
        id: initialSelectTimer
        interval: 250
        repeat: true
        running: false
        onTriggered: {
            if (pendingInitialSelection === "") {
                stop()
                return
            }
            if (experimentList.selectExperimentByName(pendingInitialSelection)) {
                innerTabs.currentIndex = 0
                pendingInitialSelection = ""
                stop()
            }
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
                successToast.show(LanguageManager.tr3("Sessão registrada!", "Session saved!", "Sesion guardada!"))
                innerTabs.currentIndex = 2  // aba Dados
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

        // ── Top bar ──────────────────────────────────────────────────────────
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

                Text { text: "⚡"; font.pixelSize: 20 }

                Text {
                    text: root.searchMode
                          ? LanguageManager.tr3("Esquiva Inibitoria - Experimentos", "Inhibitory Avoidance - Experiments", "Evitacion Inhibitoria - Experimentos")
                          : LanguageManager.tr3("Esquiva Inibitoria - Dashboard", "Inhibitory Avoidance - Dashboard", "Evitacion Inhibitoria - Panel")
                    color: ThemeManager.textPrimary; font.pixelSize: 16; font.weight: Font.Bold
                    Behavior on color { ColorAnimation { duration: 150 } }
                }

                Item { Layout.fillWidth: true }
            }
        }

        // ── Body ─────────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // ── Sidebar ──────────────────────────────────────────────────────
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
                            border.color: searchField.activeFocus ? "#c8a000" : ThemeManager.borderLight; border.width: 1
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
                                    return true
                                }
                            }
                            return false
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
                            color: isSelected ? "#c8a000" : (isHovered ? ThemeManager.surfaceAlt : "transparent")
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
                                    color: trashArea.containsMouse ? "#e0b800" : "#c8a000"
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

            // ── Work area ────────────────────────────────────────────────────
            Item {
                id: workArea
                Layout.fillWidth: true; Layout.fillHeight: true

                property string selectedName: ""
                property string selectedPath: ""
                property int    colCount:     0
                property bool   includeDrug:      true
                property string analysisMode:     "offline"
                property string saveDirectory:    ""
                property string cameraId:         ""
                property int    activeNumCampos:  1
                property var    dayNames:         []

                function loadExperiment(name, path) {
                    selectedName = name
                    selectedPath = path
                    tableModel.loadCsv(path + "/tracking_data.csv")
                    workStack.currentIndex = 1

                    ArenaConfigModel.loadConfigFromPath(path, ":/arena_config_ei_referencia.json")

                    var meta = ExperimentManager.readMetadataFromPath(path)
                    var ctx  = meta.context || ""
                    ExperimentManager.setActiveContext(ctx)

                    includeDrug = meta.includeDrug !== false

                    if (meta.dayNames && meta.dayNames.length > 0) {
                        dayNames = meta.dayNames
                    } else {
                        var ext = meta.extincaoDays || 5
                        var names = [LanguageManager.tr3("Treino", "Training", "Entrenamiento")]
                        for (var i = 1; i <= ext; i++) names.push("E" + i)
                        if (meta.hasReactivation) names.push(LanguageManager.tr3("Reativação", "Reactivation", "Reactivacion"))
                        names.push(LanguageManager.tr3("Teste", "Test", "Prueba"))
                        dayNames = names
                    }

                    colCount = tableModel.columnCount()
                }

                ExperimentTableModel { id: tableModel }
                Connections { target: tableModel; function onModelReset() { workArea.colCount = tableModel.columnCount() } }

                StackLayout {
                    id: workStack
                    anchors.fill: parent
                    currentIndex: 0

                    // Index 0: placeholder "select an experiment"
                    Item {
                        ColumnLayout {
                            anchors.centerIn: parent; spacing: 14
                            Text { text: "⚡"; font.pixelSize: 48; opacity: 0.15; Layout.alignment: Qt.AlignHCenter }
                            Text {
                                text: LanguageManager.tr3("Selecione um experimento", "Select an experiment", "Seleccione un experimento")
                                color: ThemeManager.textSecondary; font.pixelSize: 16
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }
                    }

                    // Index 1: panel with tabs
                    ColumnLayout {
                        spacing: 0

                        // ── Inner tab bar ─────────────────────────────────────────────────
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
                                    model: ["🗺 " + LanguageManager.tr3("Arena", "Arena", "Arena"), "🎬 " + LanguageManager.tr3("Gravação", "Recording", "Grabacion"), "📊 " + LanguageManager.tr3("Dados", "Data", "Datos")]

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
                                            color: parent.isActive ? "#c8a000" : (parent.isHovered ? "#e0b800" : "transparent")
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

                            // ── Tab 0: Arena ──────────────────────────────────────────────
                            EIArenaSetup {
                                id: tabArenaSetup
                                experimentPath: workArea.selectedPath
                                numCampos: 1

                                onZonasEditadas: {
                                    liveRecordingTab.zones        = tabArenaSetup.zones
                                    liveRecordingTab.arenaPoints  = tabArenaSetup.arenaPoints
                                    liveRecordingTab.floorPoints  = tabArenaSetup.floorPoints
                                }

                                onAnalysisModeChangedExternally: function(mode) {
                                    workArea.analysisMode = mode
                                    workArea.cameraId     = tabArenaSetup.cameraId
                                    if (mode !== "offline") workArea.saveDirectory = tabArenaSetup.saveDirectory
                                }
                            }

                            // ── Tab 1: Recording ──────────────────────────────────────────
                            LiveRecording {
                                id: liveRecordingTab
                                videoPath:    tabArenaSetup.videoPath
                                analysisMode: workArea.analysisMode
                                context: root.context
                                saveDirectory: workArea.saveDirectory
                                liveOutputName: tabArenaSetup.liveOutputName
                                cameraId:     workArea.cameraId
                                numCampos:    1
                                aparato:      "esquiva_inibitoria"
                                sessionDurationMinutes: 5

                                zones:       tabArenaSetup.zones
                                arenaPoints: tabArenaSetup.arenaPoints
                                floorPoints: tabArenaSetup.floorPoints

                                onSessionEnded: {
                                    // Latency = elapsed time until first entry into the grid zone
                                    var latencia = eiLatencySeconds >= 0 ? eiLatencySeconds : 0

                                    eiResultDialog.latencia        = latencia
                                    eiResultDialog.tempoPlataf     = explorationTimes[0] || 0
                                    eiResultDialog.tempoGrade      = explorationTimes[1] || 0
                                    eiResultDialog.boutsPlataf     = (explorationBouts[0] || []).length
                                    eiResultDialog.boutsGrade      = (explorationBouts[1] || []).length
                                    eiResultDialog.totalDistance   = totalDistance[0] || 0
                                    eiResultDialog.avgVelocity     = avgVelocityMeans[0] || 0
                                    eiResultDialog.includeDrug    = workArea.includeDrug
                                    eiResultDialog.experimentName = workArea.selectedName
                                    eiResultDialog.videoPath      = workArea.analysisMode === "ao_vivo"
                                                                     ? ((liveRecordingTab.liveRecordedVideoPath && liveRecordingTab.liveRecordedVideoPath !== "")
                                                                        ? liveRecordingTab.liveRecordedVideoPath
                                                                        : ("camera://" + workArea.cameraId))
                                                                     : tabArenaSetup.videoPath
                                    eiResultDialog.dayNames       = workArea.dayNames
                                    eiResultDialog.open()
                                }

                                onLiveAnalysisStarting: tabArenaSetup.stopCameraPreview()

                                onRequestVideoLoad: {
                                    innerTabs.currentIndex = 0
                                }
                            }

                            // ── Tab 2: Data — apparatus-specific layout
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

    // ── Post-session metadata dialog ───────────────────────────────────────────────────
    EIMetadataDialog {
        id: eiResultDialog
        parent: Overlay.overlay
        anchors.centerIn: parent
        onClosed: {
            ExperimentManager.refreshModel()
        }
    }

    // ── Delete popups ─────────────────────────────────────────────────────────────────
    Popup {
        id: deleteStep1Popup
        anchors.centerIn: parent; width: 400; height: 200
        modal: true; focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle { radius: 14; color: ThemeManager.surface; Behavior on color { ColorAnimation { duration: 200 } } border.color: "#c8a000"; border.width: 1 }

        ColumnLayout {
            anchors { fill: parent; margins: 24 }
            spacing: 14
            Text { text: "Excluir experimento?"; color: ThemeManager.textPrimary; font.pixelSize: 16; font.weight: Font.Bold }
            Text {
                Layout.fillWidth: true
                text: "\"" + root.pendingDeleteName + "\" será permanentemente excluído.\n\nEsta ação não pode ser desfeita."
                color: ThemeManager.textSecondary; font.pixelSize: 13; wrapMode: Text.WordWrap
            }
            RowLayout {
                Layout.fillWidth: true; spacing: 10; Item { Layout.fillWidth: true }
                GhostButton { text: "Cancelar"; onClicked: deleteStep1Popup.close() }
                Button {
                    text: "Continuar"
                    onClicked: { deleteStep1Popup.close(); delConfirmField.text = ""; deleteStep2Popup.open() }
                    background: Rectangle { radius: 7; color: parent.hovered ? "#9a7800" : "#c8a000"; Behavior on color { ColorAnimation { duration: 150 } } }
                    contentItem: Text { text: parent.text; color: ThemeManager.buttonText; font.pixelSize: 12; font.weight: Font.Bold; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    leftPadding: 16; rightPadding: 16; topPadding: 8; bottomPadding: 8
                }
            }
        }
    }

    Popup {
        id: deleteStep2Popup
        anchors.centerIn: parent; width: 420; height: 230
        modal: true; focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onOpened: delConfirmField.forceActiveFocus()
        background: Rectangle { radius: 14; color: ThemeManager.surface; Behavior on color { ColorAnimation { duration: 200 } } border.color: "#c8a000"; border.width: 1 }

        ColumnLayout {
            anchors { fill: parent; margins: 24 }
            spacing: 14
            Text { text: "Confirmar Exclusão"; color: ThemeManager.textPrimary; font.pixelSize: 16; font.weight: Font.Bold }
            Text { Layout.fillWidth: true; text: "Digite o nome do experimento para confirmar:"; color: ThemeManager.textSecondary; font.pixelSize: 13; wrapMode: Text.WordWrap }
            TextField {
                id: delConfirmField; Layout.fillWidth: true
                placeholderText: root.pendingDeleteName
                color: ThemeManager.textPrimary; placeholderTextColor: ThemeManager.textSecondary; font.pixelSize: 13
                leftPadding: 10; rightPadding: 10; topPadding: 8; bottomPadding: 8
                background: Rectangle { radius: 6; color: ThemeManager.surfaceDim; Behavior on color { ColorAnimation { duration: 200 } } border.color: delConfirmField.activeFocus ? "#c8a000" : ThemeManager.border; border.width: 1; Behavior on border.color { ColorAnimation { duration: 150 } } }
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
                    text: "Excluir"; enabled: delConfirmField.text === root.pendingDeleteName
                    onClicked: {
                        deleteStep2Popup.close()
                        if (workArea.selectedName === root.pendingDeleteName)
                            root._resetSelectionState()
                        ExperimentManager.deleteExperiment(root.pendingDeleteName)
                    }
                    background: Rectangle { radius: 7; color: parent.enabled ? (parent.hovered ? "#9a7800" : "#c8a000") : ThemeManager.surfaceDim; Behavior on color { ColorAnimation { duration: 150 } } }
                    contentItem: Text { text: parent.text; color: ThemeManager.buttonText; font.pixelSize: 12; font.weight: Font.Bold; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    leftPadding: 16; rightPadding: 16; topPadding: 8; bottomPadding: 8
                }
            }
        }
    }

    // ── Toasts ─────────────────────────────────────────────────────────────────────────
    Toast { id: successToast }
    Toast { id: errorToast }
}
