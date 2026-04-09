// qml/MainDashboard.qml
// Dashboard principal: sidebar de experimentos + planilha de dados.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../core"
import "../core/Theme"
import "../shared"
import MindTrace.Backend 1.0

Item {
    id: root
    
    property string context: ""
    property string arenaId: ""
    property bool   searchMode: false
    
    property int    currentTabIndex: 0 
    
    // Propriedade para o novo experimento
    property string initialExperimentName: ""

    Component.onCompleted: {
        if (root.searchMode) {
            ExperimentManager.loadAllContexts()
        }

        // Nova lógica para abrir o experimento recém-criado
        if (initialExperimentName !== "") {
            // Agora usamos o id correto do ListView
            experimentList.selectExperimentByName(initialExperimentName)
            
            // Garante que a aba da Arena seja a primeira vista
            innerTabs.currentIndex = 0 
        }
    }

    // true  → dashboard aberto via "Criar" (experimento já foi criado externamente)
    // false → dashboard aberto via "Procurar" (só browsing)

    property string pendingDeleteName: ""

    signal backRequested()

    // Em modo Criar: context muda de "" para "Padrão"/"Contextual" → dispara scan.
    // Em modo Procurar: context permanece "" → loadAllContexts é chamado em onCompleted.
    onContextChanged: {
        if (!root.searchMode && context !== "")
            ExperimentManager.loadContext(context)
    }

    Rectangle { anchors.fill: parent; color: ThemeManager.background; Behavior on color { ColorAnimation { duration: 200 } } }

    Connections {
        target: ExperimentManager
        
        onErrorOccurred: errorToast.show(message)
        
        onExperimentCreated: {
            createPopup.close()
            successToast.show("Experimento \"" + name + "\" criado!")

            // 1. Seleciona automaticamente na lista lateral
            experimentList.selectExperimentByName(name)

            // 2. Carrega a configuração da arena do novo local
            ArenaConfigModel.loadConfigFromPath(path)

            // 3. Pula direto para a aba 0 (Arena)
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
                successToast.show("Sessão registrada! Carregue o próximo vídeo ou consulte a aba Dados.")
                innerTabs.currentIndex = 1 // Volta para Gravação — prontos para próxima sessão
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

                Text { text: "🧠"; font.pixelSize: 20 }

                Text {
                    text: root.searchMode
                          ? "Reconhecimento de Objetos — Experimentos"
                          : "Reconhecimento de Objetos — Dashboard"
                    color: ThemeManager.textPrimary; font.pixelSize: 16; font.weight: Font.Bold; Behavior on color { ColorAnimation { duration: 150 } }
                }

                Rectangle {
                    visible: root.context !== ""
                    radius: 4; color: ThemeManager.surfaceHover
                    border.color: ThemeManager.accent; border.width: 1; Behavior on color { ColorAnimation { duration: 200 } }
                    implicitWidth: ctxLabel.implicitWidth + 16; implicitHeight: 24
                    Text {
                        id: ctxLabel
                        anchors.centerIn: parent
                        text: "NOR " + root.context
                        color: ThemeManager.accent; font.pixelSize: 11; font.weight: Font.Bold; Behavior on color { ColorAnimation { duration: 150 } }
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
                            border.color: searchField.activeFocus ? ThemeManager.accent : ThemeManager.borderLight; border.width: 1; Behavior on border.color { ColorAnimation { duration: 150 } }
                        }
                        onTextChanged: ExperimentManager.setFilter(text)
                    }

                    ListView {
                        id: experimentList
                        Layout.fillWidth: true; Layout.fillHeight: true
                        clip: true; model: ExperimentManager.model; currentIndex: -1

                        function selectExperimentByName(name) {
                            for (var i = 0; i < model.count; ++i) {
                                // Compara o nome com o NameRole (Qt.UserRole + 1)
                                if (model.data(model.index(i, 0), Qt.UserRole + 1) === name) {
                                    currentIndex = i; 
                                    // Carrega os dados para a área de trabalho
                                    var path = model.data(model.index(i, 0), Qt.UserRole + 2);
                                    workArea.loadExperiment(name, path);
                                    return;
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
                            color: isSelected ? ThemeManager.accent : (isHovered ? ThemeManager.surfaceAlt : "transparent"); Behavior on color { ColorAnimation { duration: 200 } }
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Text {
                                anchors {
                                    left: parent.left; leftMargin: 10
                                    right: trashItem.left; rightMargin: 4
                                    top: parent.top; bottom: parent.bottom
                                }
                                text: model.name
                                color: expDelegate.isSelected ? ThemeManager.textPrimary : ThemeManager.textSecondary; Behavior on color { ColorAnimation { duration: 150 } }
                                font.pixelSize: 13; elide: Text.ElideRight
                                verticalAlignment: Text.AlignVCenter
                            }

                            Item {
                                id: trashItem
                                anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                                width: 30
                                opacity: expDelegate.isHovered ? 1.0 : 0.0
                                Behavior on opacity { NumberAnimation { duration: 150 } }
                                Text {
                                    anchors.centerIn: parent; text: "🗑"
                                    font.pixelSize: 13
                                    color: trashArea.containsMouse ? ThemeManager.accentHover : ThemeManager.accent; Behavior on color { ColorAnimation { duration: 150 } }
                                }
                                MouseArea {
                                    id: trashArea; anchors.fill: parent
                                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        // Usa o contexto real vinculado ao item (sem precisar "adivinhar" pelo path)
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
                                height: 1; color: ThemeManager.border; opacity: 0.5; Behavior on color { ColorAnimation { duration: 200 } }
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: experimentList.count === 0
                            text: "Nenhum experimento\nencontrado"
                            color: ThemeManager.textSecondary; font.pixelSize: 12; Behavior on color { ColorAnimation { duration: 150 } }
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }

                    // Botão "Novo" atualizado para abrir o Setup completo
                    Button {
                        Layout.fillWidth: true
                        text: "＋ Novo Experimento"
                        visible: !root.searchMode
                        
                        // CORREÇÃO: Sintaxe limpa para disparar a tela de configuração
                        onClicked: {
                            // Busca o componente definido no main.qml através do stack
                            stack.push(norSetupComponent, {
                                "context": root.context, 
                                "arenaId": root.arenaId
                            })
                        }

                        background: Rectangle {
                            radius: 8
                            color: parent.hovered ? ThemeManager.accentHover : ThemeManager.accent; Behavior on color { ColorAnimation { duration: 200 } }
                        }
                        contentItem: Text {
                            text: parent.text; color: ThemeManager.textPrimary; Behavior on color { ColorAnimation { duration: 150 } }
                            font.pixelSize: 12; font.weight: Font.Bold
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        }
                        topPadding: 9; bottomPadding: 9
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

                // ── Dados do experimento carregados do metadata.json ──────
                property string pair1:       ""
                property string pair2:       ""
                property string pair3:       ""
                property bool   includeDrug: true
                property bool   hasReactivation: false
                property string analysisMode: "offline"
                property string saveDirectory: ""

                // ── Sessão de gravação ────────────────────────────────────
                // Persistem entre rodadas (não pedem ao usuário novamente)
                property string sessionType: "Treino"
                readonly property string sessionDia: {
                    if (sessionType === "Reativação") return "2"
                    if (sessionType === "Teste D2")   return "2"
                    if (sessionType === "Teste D3")   return "3"
                    return "1"  // Treino
                }

                function loadExperiment(name, path) {
                    selectedName = name
                    selectedPath = path
                    tableModel.loadCsv(path + "/tracking_data.csv")
                    workStack.currentIndex = 1

                    // Carrega metadata primeiro para saber o CONTEXTO real
                    var meta = ExperimentManager.readMetadataFromPath(path)
                    var ctx = meta.context || ""

                    // Define o contexto ativo (usado pelo tracker/sessions)
                    // Se estivermos em searchMode, a sidebar NÃO será limpa (graças ao m_inSearchMode no C++)
                    ExperimentManager.setActiveContext(ctx)

                    pair1       = meta.pair1 || ""
                    pair2       = meta.pair2 || ""
                    pair3       = meta.pair3 || ""
                    includeDrug = meta.includeDrug !== false
                    hasReactivation = meta.hasReactivation === true

                    // Carrega configuração da arena usando o path direto (já atualizado no C++)
                    ArenaConfigModel.loadConfigFromPath(path)

                    // Se a arena já foi configurada (tem parId), pula para aba Gravação
                    innerTabs.currentIndex = ArenaConfigModel.configured ? 1 : 0
                }

                ExperimentTableModel { id: tableModel }

                Connections {
                    target: tableModel
                    onModelReset: workArea.colCount = tableModel.columnCount()
                }

                StackLayout {
                    id: workStack
                    anchors.fill: parent
                    currentIndex: 0

                    // 0: Placeholder
                    Item {
                        ColumnLayout {
                            anchors.centerIn: parent; spacing: 12
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "📋"; font.pixelSize: 48; opacity: 0.3
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "Selecione um experimento\nna barra lateral"
                                color: ThemeManager.textSecondary; font.pixelSize: 14
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }

                    // 1: Experimento (tab bar + conteúdo)
                    ColumnLayout {
                        spacing: 0

                        Rectangle {
                            Layout.fillWidth: true; height: 40
                            color: ThemeManager.surface
                            Behavior on color { ColorAnimation { duration: 200 } }
                            Rectangle {
                                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                height: 1; color: ThemeManager.border
                                Behavior on color { ColorAnimation { duration: 200 } }
                            }

                            Row {
                                anchors { left: parent.left; leftMargin: 16; top: parent.top; bottom: parent.bottom }
                                spacing: 0

                                Repeater {
                                    id: innerTabs
                                    property int currentIndex: 0
                                    model: ["🗺 Arena", "🎬 Gravação", "📊 Dados"]

                                    delegate: Item {
                                        id: tabItem
                                        width: tabLabel.implicitWidth + 28; height: parent.height
                                        property bool isActive: innerTabs.currentIndex === index
                                        property bool isHovered: tabMouseArea.containsMouse

                                        scale: tabMouseArea.pressed ? 0.95 : (isHovered ? 1.05 : 1.0)
                                        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

                                        Rectangle {
                                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                            height: parent.isActive ? 2 : (parent.isHovered ? 1 : 0)
                                            color: parent.isActive ? ThemeManager.accent : (parent.isHovered ? ThemeManager.accentHover : "transparent"); Behavior on color { ColorAnimation { duration: 200 } }
                                            Behavior on color { ColorAnimation { duration: 150 } }
                                            Behavior on height { NumberAnimation { duration: 150 } }
                                        }

                                        Text {
                                            id: tabLabel; anchors.centerIn: parent
                                            text: modelData
                                            color: tabItem.isActive ? ThemeManager.textPrimary : (tabItem.isHovered ? ThemeManager.textSecondary : ThemeManager.textTertiary); Behavior on color { ColorAnimation { duration: 150 } }
                                            font.pixelSize: 12
                                            font.weight: tabItem.isActive ? Font.Bold : Font.Normal
                                            Behavior on color { ColorAnimation { duration: 150 } }
                                        }

                                        MouseArea {
                                            id: tabMouseArea
                                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            hoverEnabled: true
                                            onClicked: innerTabs.currentIndex = index
                                        }
                                    }
                                }
                            }

                            Text {
                                anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                                text: workArea.selectedName
                                color: ThemeManager.textTertiary; font.pixelSize: 12; elide: Text.ElideRight; Behavior on color { ColorAnimation { duration: 150 } }
                            }
                        }

                        StackLayout {
                            id: innerStack
                            Layout.fillWidth: true; Layout.fillHeight: true
                            currentIndex: innerTabs.currentIndex

                            // Tab 0: Arena
                            ArenaSetup {
                                id: tabArenaSetup 
                                experimentPath: workArea.selectedPath
                                context: root.context

                                pair1: workArea.pair1
                                pair2: workArea.pair2
                                pair3: workArea.pair3

                                onPairsEdited: {
                                    workArea.pair1 = p1
                                    workArea.pair2 = p2
                                    workArea.pair3 = p3
                                    ExperimentManager.updatePairs(workArea.selectedPath, p1, p2, p3)
                                }
                            }

                            // Tab 1: Gravação
                            LiveRecording {
                                id: liveRecordingTab
                                videoPath: tabArenaSetup.videoPath
                                analysisMode: workArea.analysisMode

                                pair1: workArea.pair1
                                pair2: workArea.pair2
                                pair3: workArea.pair3

                                zones:       tabArenaSetup.zones
                                arenaPoints: tabArenaSetup.arenaPoints
                                floorPoints: tabArenaSetup.floorPoints

                                // Timer de 300 s zerou → injeta dados de tracking e abre o diálogo
                                onSessionEnded: {
                                    resultDialog.sessionExplorationBouts = liveRecordingTab.explorationBouts
                                    resultDialog.sessionExplorationTimes = liveRecordingTab.explorationTimes
                                    resultDialog.sessionTotalDistance    = liveRecordingTab.totalDistance
                                    resultDialog.sessionAvgVelocity      = liveRecordingTab.currentVelocity
                                    resultDialog.sessionPerMinuteData    = liveRecordingTab.perMinuteData
                                    resultDialog.open()
                                }

                                // Botão "Carregar Vídeo" na aba Gravação → abre o seletor de vídeo
                                onRequestVideoLoad: {
                                    innerTabs.currentIndex = 0  // vai para Arena
                                    tabArenaSetup.openVideoLoader()
                                }
                            }

                            // Tab 2: Dados
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
                                            color: ThemeManager.textTertiary; font.pixelSize: 11; Behavior on color { ColorAnimation { duration: 150 } }
                                        }
                                        Item { Layout.fillWidth: true }
                                        GhostButton { text: "＋ Linha"; onClicked: tableModel.addRow() }
                                        Button {
                                            text: "📤 Exportar"
                                            onClicked: {
                                                if (tableModel.exportCsv(workArea.selectedPath + "/export_" +
                                                    new Date().toISOString().substring(0,10) + ".csv"))
                                                    savedFeedback.show("Exportado!")
                                            }
                                            background: Rectangle {
                                                radius: 7
                                                color: parent.hovered ? ThemeManager.successLight : ThemeManager.success
                                                border.color: ThemeManager.successLight; border.width: 1
                                                Behavior on color { ColorAnimation { duration: 150 } }
                                                Behavior on border.color { ColorAnimation { duration: 150 } }
                                            }
                                            contentItem: Text {
                                                text: parent.text; color: ThemeManager.buttonText
                                                font.pixelSize: 12; font.weight: Font.Bold
                                                verticalAlignment: Text.AlignVCenter
                                                horizontalAlignment: Text.AlignHCenter
                                            }
                                            leftPadding: 14; rightPadding: 14; topPadding: 6; bottomPadding: 6
                                        }
                                        Button {
                                            text: "💾 Salvar"
                                            onClicked: { if (tableModel.saveCsv()) savedFeedback.show("Salvo!") }
                                            background: Rectangle {
                                                radius: 7
                                                color: parent.hovered ? ThemeManager.accentHover : ThemeManager.accent; Behavior on color { ColorAnimation { duration: 200 } }
                                            }
                                            contentItem: Text {
                                                text: parent.text; color: ThemeManager.buttonText
                                                font.pixelSize: 12; font.weight: Font.Bold
                                                verticalAlignment: Text.AlignVCenter
                                                horizontalAlignment: Text.AlignHCenter
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
                                                    color: ThemeManager.textSecondary; font.pixelSize: 12; font.weight: Font.Bold; Behavior on color { ColorAnimation { duration: 150 } }
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
                                        ScrollBar.vertical: ScrollBar {
                                            policy: ScrollBar.AsNeeded
                                            contentItem: Rectangle { implicitWidth: 6; radius: 3; color: ThemeManager.borderLight; Behavior on color { ColorAnimation { duration: 200 } } }
                                        }
                                        ScrollBar.horizontal: ScrollBar {
                                            policy: ScrollBar.AsNeeded
                                            contentItem: Rectangle { implicitHeight: 6; radius: 3; color: ThemeManager.borderLight; Behavior on color { ColorAnimation { duration: 200 } } }
                                        }
                                        delegate: Rectangle {
                                            implicitWidth: 120; implicitHeight: 32
                                            color: rowDelMa.containsMouse ? ThemeManager.surfaceHover
                                                 : (row % 2 === 0) ? ThemeManager.surface : ThemeManager.surfaceAlt; Behavior on color { ColorAnimation { duration: 200 } }
                                            border.color: ThemeManager.border; border.width: 1; Behavior on border.color { ColorAnimation { duration: 200 } }

                                            // Botão deletar linha (aparece ao hover na primeira célula)
                                            Rectangle {
                                                id: rowDelBtn
                                                anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 4 }
                                                visible: column === 0 && rowDelMa.containsMouse
                                                width: 20; height: 20; radius: 4
                                                color: rowDelBtnMa.containsMouse ? ThemeManager.accentHover : "#3a1020"; Behavior on color { ColorAnimation { duration: 200 } }
                                                border.color: ThemeManager.accent; border.width: 1; Behavior on border.color { ColorAnimation { duration: 200 } }
                                                Text {
                                                    anchors.centerIn: parent; text: "✕"
                                                    color: ThemeManager.error; font.pixelSize: 9; font.weight: Font.Bold; Behavior on color { ColorAnimation { duration: 150 } }
                                                }
                                                MouseArea {
                                                    id: rowDelBtnMa; anchors.fill: parent
                                                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        tableModel.removeRow(row)
                                                        tableModel.saveCsv()
                                                    }
                                                }
                                            }

                                            TextInput {
                                                anchors {
                                                    fill: parent; leftMargin: 8
                                                    rightMargin: (column === 0 && rowDelMa.containsMouse) ? 28 : 8
                                                }
                                                text: model.display !== undefined ? model.display : ""
                                                color: ThemeManager.textPrimary; font.pixelSize: 13; Behavior on color { ColorAnimation { duration: 150 } }
                                                verticalAlignment: Text.AlignVCenter
                                                clip: true; selectByMouse: true
                                                onEditingFinished: {
                                                    tableModel.setData(tableModel.index(row, column), text, Qt.EditRole)
                                                }
                                            }

                                            // HoverEnabled na linha inteira (para mostrar botão delete)
                                            MouseArea {
                                                id: rowDelMa; anchors.fill: parent; hoverEnabled: true
                                                // Propaga clique para o TextInput
                                                onPressed: mouse.accepted = false
                                            }
                                        }
                                    }
                                }

                                Toast {
                                    id: savedFeedback; successMode: true
                                    anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 12 }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════
    // Popup: criar experimento NOR (colunas fixas, usado apenas na sidebar)
    // ════════════════════════════════════════════════════════════════════
    Popup {
        id: createPopup
        anchors.centerIn: parent
        width: 420; height: 240
        modal: true; focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle {
            radius: 14; color: ThemeManager.surface; Behavior on color { ColorAnimation { duration: 200 } }
            border.color: ThemeManager.borderLight; border.width: 1; Behavior on border.color { ColorAnimation { duration: 200 } }
        }

        onOpened: { createNameField.text = ""; createNameField.forceActiveFocus() }

        ColumnLayout {
            anchors { fill: parent; margins: 24 }
            spacing: 16

            RowLayout {
                spacing: 8
                Text { text: "📋"; font.pixelSize: 20 }
                Text {
                    text: "Novo Experimento NOR"
                    color: ThemeManager.textPrimary; font.pixelSize: 17; font.weight: Font.Bold; Behavior on color { ColorAnimation { duration: 150 } }
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: "✕"; color: ThemeManager.textSecondary; font.pixelSize: 14; Behavior on color { ColorAnimation { duration: 150 } }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: createPopup.close() }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } } }

            ColumnLayout {
                Layout.fillWidth: true; spacing: 6
                Text { text: "Nome do experimento"; color: ThemeManager.textSecondary; font.pixelSize: 12; Behavior on color { ColorAnimation { duration: 150 } } }
                TextField {
                    id: createNameField
                    Layout.fillWidth: true
                    placeholderText: "Ex.: Grupo_Controle_Dia1"
                    color: ThemeManager.textPrimary; placeholderTextColor: ThemeManager.textSecondary; font.pixelSize: 13
                    leftPadding: 10; rightPadding: 10; topPadding: 8; bottomPadding: 8
                    background: Rectangle {
                        radius: 6; color: ThemeManager.surfaceDim; Behavior on color { ColorAnimation { duration: 200 } }
                        border.color: createNameField.activeFocus ? ThemeManager.accent : ThemeManager.borderLight; border.width: 1; Behavior on border.color { ColorAnimation { duration: 150 } }
                    }
                    Keys.onReturnPressed: {
                        if (createNameField.text.trim().length > 0) createBtn.clicked()
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true; spacing: 10
                Item { Layout.fillWidth: true }
                GhostButton { text: "Cancelar"; onClicked: createPopup.close() }
                Button {
                    id: createBtn
                    text: "Criar"
                    enabled: createNameField.text.trim().length > 0
                    onClicked: {
                        // Colunas padrão NOR (sem droga por simplicidade neste atalho)
                        ExperimentManager.createExperimentWithConfig(
                            createNameField.text.trim(), 0,
                            ["Diretório do Vídeo", "Animal", "Campo", "Dia", "Par de Objetos"])
                    }
                    background: Rectangle {
                        radius: 8
                        color: parent.enabled ? (parent.hovered ? ThemeManager.accentHover : ThemeManager.accent) : ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } }
                    }
                    contentItem: Text {
                        text: parent.text; color: ThemeManager.textPrimary; Behavior on color { ColorAnimation { duration: 150 } }
                        font.pixelSize: 13; font.weight: Font.Bold
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                    leftPadding: 18; rightPadding: 18; topPadding: 9; bottomPadding: 9
                }
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════
    // Popup: confirmar exclusão — passo 1
    // ════════════════════════════════════════════════════════════════════
    Popup {
        id: deleteStep1Popup
        anchors.centerIn: parent
        width: 400
        height: step1Layout.implicitHeight + 56
        modal: true; focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle {
            radius: 14
            color: ThemeManager.surface
            border.color: ThemeManager.borderLight
            border.width: 1
            Behavior on color { ColorAnimation { duration: 200 } }
            Behavior on border.color { ColorAnimation { duration: 200 } }
        }

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
                Layout.fillWidth: true; spacing: 10
                Item { Layout.fillWidth: true }
                GhostButton { text: "Cancelar"; onClicked: deleteStep1Popup.close() }
                Button {
                    text: "Continuar"
                    onClicked: { deleteStep1Popup.close(); deleteNameField.text = ""; deleteStep2Popup.open() }
                    background: Rectangle {
                        radius: 7; color: parent.hovered ? ThemeManager.accentHover : ThemeManager.accent; Behavior on color { ColorAnimation { duration: 200 } }
                    }
                    contentItem: Text {
                        text: parent.text; color: ThemeManager.buttonText; font.pixelSize: 12; font.weight: Font.Bold
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                    leftPadding: 16; rightPadding: 16; topPadding: 8; bottomPadding: 8
                }
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════
    // Popup: confirmar exclusão — passo 2
    // ════════════════════════════════════════════════════════════════════
    Popup {
        id: deleteStep2Popup
        anchors.centerIn: parent
        width: 420
        height: step2Layout.implicitHeight + 56
        modal: true; focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onOpened: deleteNameField.forceActiveFocus()

        background: Rectangle {
            radius: 14
            color: ThemeManager.surface
            border.color: ThemeManager.accent
            border.width: 1
            Behavior on color { ColorAnimation { duration: 200 } }
            Behavior on border.color { ColorAnimation { duration: 200 } }
        }

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

            // Nome em destaque — igual ao GitHub: "Digite exatamente: NomeDoExperimento"
            Rectangle {
                Layout.fillWidth: true
                height: nameLabel.implicitHeight + 10
                radius: 5
                color: ThemeManager.surfaceDim
                border.color: ThemeManager.borderLight; border.width: 1
                Behavior on color { ColorAnimation { duration: 200 } }

                Text {
                    id: nameLabel
                    anchors { verticalCenter: parent.verticalCenter; left: parent.left; right: parent.right; margins: 10 }
                    text: root.pendingDeleteName
                    color: ThemeManager.textPrimary
                    font.pixelSize: 13
                    font.family: "Consolas, monospace"
                    font.weight: Font.Medium
                    wrapMode: Text.WrapAnywhere
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
            }

            TextField {
                id: deleteNameField
                Layout.fillWidth: true
                placeholderText: root.pendingDeleteName
                color: ThemeManager.textPrimary; placeholderTextColor: ThemeManager.textPlaceholder; font.pixelSize: 13
                leftPadding: 10; rightPadding: 10; topPadding: 8; bottomPadding: 8
                background: Rectangle {
                    radius: 6; color: ThemeManager.surfaceDim; Behavior on color { ColorAnimation { duration: 200 } }
                    border.color: deleteNameField.activeFocus ? ThemeManager.accent : ThemeManager.borderLight; border.width: 1; Behavior on border.color { ColorAnimation { duration: 150 } }
                }
                Keys.onReturnPressed: {
                    if (text === root.pendingDeleteName) {
                        deleteStep2Popup.close()
                        ExperimentManager.deleteExperiment(root.pendingDeleteName)
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true; spacing: 10
                Item { Layout.fillWidth: true }
                GhostButton { text: "Cancelar"; onClicked: deleteStep2Popup.close() }
                Button {
                    text: "Excluir Definitivamente"
                    enabled: deleteNameField.text === root.pendingDeleteName
                    onClicked: { deleteStep2Popup.close(); ExperimentManager.deleteExperiment(root.pendingDeleteName) }
                    background: Rectangle {
                        radius: 7
                        color: parent.enabled ? (parent.hovered ? ThemeManager.accentHover : ThemeManager.accent) : ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } }
                    }
                    contentItem: Text {
                        text: parent.text; color: ThemeManager.buttonText; font.pixelSize: 12; font.weight: Font.Bold
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                    leftPadding: 16; rightPadding: 16; topPadding: 8; bottomPadding: 8
                }
            }
        }
    }

    // ── Dialog pós-sessão: inserção dos dados dos animais ────────────────
    SessionResultDialog {
        id: resultDialog
        experimentName:   workArea.selectedName
        pair1:            workArea.pair1
        pair2:            workArea.pair2
        pair3:            workArea.pair3
        hasReactivation:  workArea.hasReactivation
        includeDrug:      workArea.includeDrug
        analysisMode:     workArea.analysisMode
        saveDirectory:    workArea.saveDirectory
        videoPath:        liveRecordingTab.videoPath
    }

    Toast { id: successToast; successMode: true;  anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 16 } }
    Toast { id: errorToast;   successMode: false; anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 16 } }
}
