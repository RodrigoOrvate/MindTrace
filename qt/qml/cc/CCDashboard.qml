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
                innerTabs.currentIndex = 3  // aba Dados
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
                property string analysisMode:     "offline"
                property int    activeNumCampos:  root.numCampos
                property int    sessionMinutes:   5

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
                    activeNumCampos = meta.numCampos || root.numCampos
                    sessionMinutes  = meta.sessionMinutes || 5

                    // Propaga pontos de arena para aba Gravação
                    liveRecordingTab.arenaPoints = JSON.parse(ArenaConfigModel.getArenaPoints() || "[]")
                    liveRecordingTab.floorPoints = JSON.parse(ArenaConfigModel.getFloorPoints() || "[]")

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

                                onAnalysisModeChangedExternally: mode => {
                                    workArea.analysisMode  = mode
                                    innerTabs.currentIndex = 1
                                }

                                // Propagação ao vivo Arena → Gravação
                                onZonasEditadas: {
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

                                arenaPoints: JSON.parse(ArenaConfigModel.getArenaPoints() || "[]")
                                floorPoints: JSON.parse(ArenaConfigModel.getFloorPoints() || "[]")

                                Connections {
                                    target: ArenaConfigModel
                                    function onConfigChanged() {
                                        liveRecordingTab.arenaPoints = JSON.parse(ArenaConfigModel.getArenaPoints() || "[]")
                                        liveRecordingTab.floorPoints = JSON.parse(ArenaConfigModel.getFloorPoints() || "[]")
                                    }
                                }

                                onSessionEnded: {
                                    ccResultDialog.totalDistance  = liveRecordingTab.totalDistance
                                    ccResultDialog.avgVelocity    = liveRecordingTab.currentVelocity
                                    ccResultDialog.perMinuteData  = liveRecordingTab.perMinuteData
                                    ccResultDialog.includeDrug    = workArea.includeDrug
                                    ccResultDialog.experimentName = workArea.selectedName
                                    ccResultDialog.experimentPath = workArea.selectedPath
                                    ccResultDialog.numCampos      = workArea.activeNumCampos
                                    ccResultDialog.videoPath      = tabArenaSetup.videoPath
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

                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        width: Math.min(560, parent.width - 80)
                                        spacing: 24

                                        // Ícone
                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: "🧠"
                                            font.pixelSize: 52
                                            opacity: 0.6
                                        }

                                        // Título
                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: "Classificação de Comportamento"
                                            color: ThemeManager.textPrimary
                                            font.pixelSize: 20; font.weight: Font.Bold
                                            Behavior on color { ColorAnimation { duration: 150 } }
                                        }

                                        // Descrição
                                        Text {
                                            Layout.fillWidth: true
                                            text: "Esta aba permitirá aplicar algoritmos de classificação automatizada sobre os vídeos e trajetórias gravados, identificando padrões comportamentais como grooming, exploração, imobilidade, sociabilidade e outros."
                                            color: ThemeManager.textSecondary
                                            font.pixelSize: 13
                                            wrapMode: Text.WordWrap
                                            horizontalAlignment: Text.AlignHCenter
                                            Behavior on color { ColorAnimation { duration: 150 } }
                                        }

                                        // Opções de algoritmo (informativo)
                                        Rectangle {
                                            Layout.fillWidth: true; radius: 12
                                            color: ThemeManager.surfaceDim
                                            border.color: "#7a3dab"; border.width: 1
                                            implicitHeight: algoCol.implicitHeight + 24

                                            ColumnLayout {
                                                id: algoCol
                                                anchors { fill: parent; margins: 16 }
                                                spacing: 12

                                                Text {
                                                    text: "ALGORITMOS EM AVALIAÇÃO"
                                                    color: ThemeManager.textSecondary
                                                    font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 1.5
                                                }

                                                Repeater {
                                                    model: [
                                                        { name: "B-SOiD",     desc: "Pose-based unsupervised behavior segmentation (scikit-learn + UMAP)" },
                                                        { name: "YOLO Pose",  desc: "Detecção de posturas em tempo real via keypoints" },
                                                        { name: "Rede Custom",desc: "Modelo treinado sobre keypoints do MindTrace (a definir)" }
                                                    ]
                                                    delegate: RowLayout {
                                                        spacing: 12
                                                        Rectangle {
                                                            width: 6; height: 6; radius: 3
                                                            color: "#7a3dab"
                                                            anchors.verticalCenter: parent.verticalCenter
                                                        }
                                                        ColumnLayout {
                                                            spacing: 1
                                                            Text { text: modelData.name; color: ThemeManager.textPrimary; font.pixelSize: 13; font.weight: Font.Bold }
                                                            Text { text: modelData.desc;  color: ThemeManager.textTertiary; font.pixelSize: 11; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        // Botão desabilitado
                                        Rectangle {
                                            Layout.alignment: Qt.AlignHCenter
                                            height: 40; radius: 8
                                            implicitWidth: classifyLbl.implicitWidth + 32
                                            color: ThemeManager.surfaceDim
                                            border.color: ThemeManager.border; border.width: 1

                                            Text {
                                                id: classifyLbl
                                                anchors.centerIn: parent
                                                text: "🔒  Classificar  (em breve)"
                                                color: ThemeManager.textTertiary
                                                font.pixelSize: 13; font.weight: Font.Bold
                                            }
                                        }

                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: "O algoritmo será definido em uma conversa separada antes da implementação."
                                            color: ThemeManager.textTertiary; font.pixelSize: 11
                                            horizontalAlignment: Text.AlignHCenter
                                            Behavior on color { ColorAnimation { duration: 150 } }
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
