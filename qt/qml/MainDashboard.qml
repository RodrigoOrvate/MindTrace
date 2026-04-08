// qml/MainDashboard.qml
// Dashboard principal: sidebar de experimentos + planilha de dados.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
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

    Rectangle { anchors.fill: parent; color: "#0f0f1a" }

    Connections {
        target: ExperimentManager
        
        onErrorOccurred: errorToast.show(message)
        
        onExperimentCreated: {
            createPopup.close()
            successToast.show("Experimento \"" + name + "\" criado!")

            // 1. Seleciona automaticamente na lista lateral
            experimentList.selectExperimentByName(name)

            // 2. Carrega a configuração da arena do novo local em Documentos
            // Passamos o contexto atual e o nome para bater com o C++
            ArenaConfigModel.loadConfig(root.context, name)

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
                successToast.show("Sessão registrada — 3 campos inseridos.")
                innerTabs.currentIndex = 1 // Garante que a aba Dados fica visível
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── Barra superior ───────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 56; color: "#1a1a2e"

            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 1; color: "#2d2d4a"
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
                    color: "#e8e8f0"; font.pixelSize: 16; font.weight: Font.Bold
                }

                Rectangle {
                    visible: root.context !== ""
                    radius: 4; color: "#1f0d10"
                    border.color: "#ab3d4c"; border.width: 1
                    implicitWidth: ctxLabel.implicitWidth + 16; implicitHeight: 24
                    Text {
                        id: ctxLabel
                        anchors.centerIn: parent
                        text: "NOR " + root.context
                        color: "#ab3d4c"; font.pixelSize: 11; font.weight: Font.Bold
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
                color: "#1a1a2e"

                Rectangle {
                    anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
                    width: 1; color: "#2d2d4a"
                }

                ColumnLayout {
                    anchors { fill: parent; margins: 12 }
                    spacing: 8

                    Text {
                        text: "Experimentos"
                        color: "#e8e8f0"; font.pixelSize: 12; font.weight: Font.Bold
                    }

                    TextField {
                        id: searchField
                        Layout.fillWidth: true
                        placeholderText: "Pesquisar…"
                        color: "#e8e8f0"; placeholderTextColor: "#8888aa"; font.pixelSize: 13
                        leftPadding: 10; rightPadding: 10; topPadding: 6; bottomPadding: 6
                        background: Rectangle {
                            radius: 6; color: "#12122a"
                            border.color: searchField.activeFocus ? "#ab3d4c" : "#3a3a5c"; border.width: 1
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
                            contentItem: Rectangle { implicitWidth: 4; radius: 2; color: "#3a3a5c" }
                        }

                        delegate: Rectangle {
                            id: expDelegate
                            width: experimentList.width; height: 36
                            property bool isSelected: experimentList.currentIndex === index
                            property bool isHovered: mainArea.containsMouse || trashArea.containsMouse
                            color: isSelected ? "#ab3d4c" : (isHovered ? "#16162e" : "transparent")
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Text {
                                anchors {
                                    left: parent.left; leftMargin: 10
                                    right: trashItem.left; rightMargin: 4
                                    top: parent.top; bottom: parent.bottom
                                }
                                text: model.name
                                color: expDelegate.isSelected ? "#e8e8f0" : "#8888aa"
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
                                    color: trashArea.containsMouse ? "#e84c5a" : "#cc4455"
                                }
                                MouseArea {
                                    id: trashArea; anchors.fill: parent
                                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        // Extrai e avisa o C++ qual é o contexto ANTES de tentar deletar
                                        if (root.searchMode) {
                                            var parts = model.path.replace(/\\/g, "/").split("/")
                                            var ctx = parts.length >= 2 ? parts[parts.length - 2] : ""
                                            ExperimentManager.setActiveContext(ctx)
                                        }
                                        
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
                                height: 1; color: "#2d2d4a"; opacity: 0.5
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: experimentList.count === 0
                            text: "Nenhum experimento\nencontrado"
                            color: "#8888aa"; font.pixelSize: 12
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
                            color: parent.hovered ? "#8a2e3b" : "#ab3d4c"
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                        contentItem: Text {
                            text: parent.text; color: "#e8e8f0"
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
                    // Em search mode extrai o contexto do path para que
                    // insertSessionResult e readMetadata usem o contexto correto.
                    if (root.searchMode) {
                        var parts = path.replace(/\\/g, "/").split("/")
                        var ctx = parts.length >= 2 ? parts[parts.length - 2] : ""
                        ExperimentManager.setActiveContext(ctx)
                    }

                    selectedName = name
                    selectedPath = path
                    tableModel.loadCsv(path + "/tracking_data.csv")
                    workStack.currentIndex = 1

                    // Carrega pares e flag droga a partir do path completo
                    var meta = ExperimentManager.readMetadataFromPath(path)
                    pair1       = meta.pair1 || ""
                    pair2       = meta.pair2 || ""
                    pair3       = meta.pair3 || ""
                    includeDrug = meta.includeDrug !== false

                    // Carrega configuração da arena (extrai context/expName do path)
                    var parts = path.replace(/\\/g, "/").split("/")
                    var ctx  = parts.length >= 2 ? parts[parts.length - 2] : ""
                    var expN = parts[parts.length - 1]
                    ArenaConfigModel.loadConfig(ctx, expN)
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
                                color: "#8888aa"; font.pixelSize: 14
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }

                    // 1: Experimento (tab bar + conteúdo)
                    ColumnLayout {
                        spacing: 0

                        Rectangle {
                            Layout.fillWidth: true; height: 40; color: "#1a1a2e"
                            Rectangle {
                                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                height: 1; color: "#2d2d4a"
                            }

                            Row {
                                anchors { left: parent.left; leftMargin: 16; top: parent.top; bottom: parent.bottom }
                                spacing: 0

                                Repeater {
                                    id: innerTabs
                                    property int currentIndex: 0
                                    model: ["🗺 Arena", "🎬 Gravação", "📊 Dados"]

                                    delegate: Item {
                                        width: tabLabel.implicitWidth + 28; height: parent.height
                                        property bool isActive: innerTabs.currentIndex === index

                                        Rectangle {
                                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                            height: 2
                                            color: parent.isActive ? "#ab3d4c" : "transparent"
                                            Behavior on color { ColorAnimation { duration: 150 } }
                                        }

                                        Text {
                                            id: tabLabel; anchors.centerIn: parent
                                            text: modelData
                                            color: parent.isActive ? "#e8e8f0" : "#8888aa"
                                            font.pixelSize: 12
                                            font.weight: parent.isActive ? Font.Bold : Font.Normal
                                            Behavior on color { ColorAnimation { duration: 150 } }
                                        }

                                        MouseArea {
                                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            onClicked: innerTabs.currentIndex = index
                                        }
                                    }
                                }
                            }

                            Text {
                                anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                                text: workArea.selectedName
                                color: "#555577"; font.pixelSize: 12; elide: Text.ElideRight
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

                                sessionType: workArea.sessionType
                                onSessionTypeChanged: workArea.sessionType = sessionType

                                zones:       tabArenaSetup.zones
                                arenaPoints: tabArenaSetup.arenaPoints
                                floorPoints: tabArenaSetup.floorPoints

                                // Timer de 300 s zerou → abre o diálogo de resultado
                                onSessionEnded: resultDialog.open()
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
                                        Item { Layout.fillWidth: true }
                                        GhostButton { text: "＋ Linha"; onClicked: tableModel.addRow() }
                                        Button {
                                            text: "💾 Salvar"
                                            onClicked: { if (tableModel.saveCsv()) savedFeedback.show("Salvo!") }
                                            background: Rectangle {
                                                radius: 7
                                                color: parent.hovered ? "#8a2e3b" : "#ab3d4c"
                                                Behavior on color { ColorAnimation { duration: 150 } }
                                            }
                                            contentItem: Text {
                                                text: parent.text; color: "#e8e8f0"
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
                                                height: 32; color: "#12122a"
                                                border.color: "#2d2d4a"; border.width: 1
                                                Text {
                                                    anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                                                    text: tableModel.headerData(index, Qt.Horizontal, Qt.DisplayRole) || ""
                                                    color: "#8888aa"; font.pixelSize: 12; font.weight: Font.Bold
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
                                            contentItem: Rectangle { implicitWidth: 6; radius: 3; color: "#3a3a5c" }
                                        }
                                        ScrollBar.horizontal: ScrollBar {
                                            policy: ScrollBar.AsNeeded
                                            contentItem: Rectangle { implicitHeight: 6; radius: 3; color: "#3a3a5c" }
                                        }
                                        delegate: Rectangle {
                                            implicitWidth: 120; implicitHeight: 32
                                            color: (row % 2 === 0) ? "#1a1a2e" : "#16162e"
                                            border.color: "#2d2d4a"; border.width: 1
                                            TextInput {
                                                anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                                                text: model.display !== undefined ? model.display : ""
                                                color: "#e8e8f0"; font.pixelSize: 13
                                                verticalAlignment: Text.AlignVCenter
                                                clip: true; selectByMouse: true
                                                onEditingFinished: {
                                                    tableModel.setData(tableModel.index(row, column), text, Qt.EditRole)
                                                }
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
            radius: 14; color: "#1a1a2e"
            border.color: "#3a3a5c"; border.width: 1
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
                    color: "#e8e8f0"; font.pixelSize: 17; font.weight: Font.Bold
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: "✕"; color: "#8888aa"; font.pixelSize: 14
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: createPopup.close() }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: "#2d2d4a" }

            ColumnLayout {
                Layout.fillWidth: true; spacing: 6
                Text { text: "Nome do experimento"; color: "#8888aa"; font.pixelSize: 12 }
                TextField {
                    id: createNameField
                    Layout.fillWidth: true
                    placeholderText: "Ex.: Grupo_Controle_Dia1"
                    color: "#e8e8f0"; placeholderTextColor: "#8888aa"; font.pixelSize: 13
                    leftPadding: 10; rightPadding: 10; topPadding: 8; bottomPadding: 8
                    background: Rectangle {
                        radius: 6; color: "#12122a"
                        border.color: createNameField.activeFocus ? "#ab3d4c" : "#3a3a5c"; border.width: 1
                        Behavior on border.color { ColorAnimation { duration: 150 } }
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
                        color: parent.enabled ? (parent.hovered ? "#8a2e3b" : "#ab3d4c") : "#2d2d4a"
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                    contentItem: Text {
                        text: parent.text; color: "#e8e8f0"
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
        width: 400; height: 190
        modal: true; focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle { radius: 14; color: "#1a1a2e"; border.color: "#3a3a5c"; border.width: 1 }

        ColumnLayout {
            anchors { fill: parent; margins: 24 }
            spacing: 14

            Text { text: "Excluir Experimento"; color: "#e8e8f0"; font.pixelSize: 16; font.weight: Font.Bold }

            Text {
                Layout.fillWidth: true
                text: "Tem certeza que deseja excluir\n\"" + root.pendingDeleteName + "\"?\n\nEsta ação é irreversível."
                color: "#8888aa"; font.pixelSize: 13; wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true; spacing: 10
                Item { Layout.fillWidth: true }
                GhostButton { text: "Cancelar"; onClicked: deleteStep1Popup.close() }
                Button {
                    text: "Continuar"
                    onClicked: { deleteStep1Popup.close(); deleteNameField.text = ""; deleteStep2Popup.open() }
                    background: Rectangle {
                        radius: 7; color: parent.hovered ? "#8a2e3b" : "#ab3d4c"
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                    contentItem: Text {
                        text: parent.text; color: "#e8e8f0"; font.pixelSize: 12; font.weight: Font.Bold
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
        width: 420; height: 230
        modal: true; focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onOpened: deleteNameField.forceActiveFocus()

        background: Rectangle { radius: 14; color: "#1a1a2e"; border.color: "#ab3d4c"; border.width: 1 }

        ColumnLayout {
            anchors { fill: parent; margins: 24 }
            spacing: 14

            Text { text: "Confirmação Final"; color: "#e8e8f0"; font.pixelSize: 16; font.weight: Font.Bold }

            Text {
                Layout.fillWidth: true
                text: "Digite o nome do experimento para confirmar a exclusão:"
                color: "#8888aa"; font.pixelSize: 13; wrapMode: Text.WordWrap
            }

            TextField {
                id: deleteNameField
                Layout.fillWidth: true
                placeholderText: root.pendingDeleteName
                color: "#e8e8f0"; placeholderTextColor: "#444466"; font.pixelSize: 13
                leftPadding: 10; rightPadding: 10; topPadding: 8; bottomPadding: 8
                background: Rectangle {
                    radius: 6; color: "#12122a"
                    border.color: deleteNameField.activeFocus ? "#ab3d4c" : "#3a3a5c"; border.width: 1
                    Behavior on border.color { ColorAnimation { duration: 150 } }
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
                        color: parent.enabled ? (parent.hovered ? "#8a2e3b" : "#ab3d4c") : "#2d2d4a"
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                    contentItem: Text {
                        text: parent.text; color: "#e8e8f0"; font.pixelSize: 12; font.weight: Font.Bold
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
        sessionTypeLabel: workArea.sessionType
        dia:              workArea.sessionDia
        includeDrug:      workArea.includeDrug
        analysisMode:     workArea.analysisMode
        saveDirectory:    workArea.saveDirectory
    }

    Toast { id: successToast; successMode: true;  anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 16 } }
    Toast { id: errorToast;   successMode: false; anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 16 } }
}
