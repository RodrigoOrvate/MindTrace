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
    
    property string context:   ""
    property string arenaId:   ""
    property int    numCampos: 3
    property bool   searchMode: false

    property int    currentTabIndex: 0

    // Propriedade para o novo experimento
    property string initialExperimentName: ""

    Component.onCompleted: {
        if (root.searchMode) {
            ExperimentManager.loadAllContexts("nor")
        }

        // Nova lÃ³gica para abrir o experimento recÃ©m-criado
        if (initialExperimentName !== "") {
            experimentList.selectExperimentByName(initialExperimentName)
            
            // searchMode â†’ abre na aba Dados (Ã­ndice 2), criaÃ§Ã£o â†’ abre na Arena (Ã­ndice 0)
            innerTabs.currentIndex = root.currentTabIndex || 0
        }
    }

    // true  â†’ dashboard aberto via "Criar" (experimento jÃ¡ foi criado externamente)
    // false â†’ dashboard aberto via "Procurar" (sÃ³ browsing)

    property string pendingDeleteName: ""

    signal backRequested()

    // Em modo Criar: context muda de "" para "PadrÃ£o"/"Contextual" â†’ dispara scan.
    // Em modo Procurar: context permanece "" â†’ loadAllContexts Ã© chamado em onCompleted.
    onContextChanged: {
        if (!root.searchMode && context !== "")
            ExperimentManager.loadContext(context, "nor")
    }

    Rectangle { anchors.fill: parent; color: ThemeManager.background; Behavior on color { ColorAnimation { duration: 200 } } }

    Connections {
        target: ExperimentManager
        
        onErrorOccurred: errorToast.show(message)
        
        onExperimentCreated: {
            createPopup.close()
            successToast.show(LanguageManager.tr3("Experimento \"", "Experiment \"", "Experimento \"") + name + LanguageManager.tr3("\" criado!", "\" created!", "\" creado!"))

            // 1. Seleciona automaticamente na lista lateral
            experimentList.selectExperimentByName(name)

            // 2. Carrega a configuraÃ§Ã£o da arena do novo local
            ArenaConfigModel.loadConfigFromPath(path)

            // 3. Pula direto para a aba 0 (Arena)
            innerTabs.currentIndex = 0 
        }

        onExperimentDeleted: {
            successToast.show(LanguageManager.tr3("Experimento \"", "Experiment \"", "Experimento \"") + name + LanguageManager.tr3("\" excluido.", "\" deleted.", "\" eliminado."))
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
                successToast.show(LanguageManager.tr3("Sessao registrada! Carregue o proximo video ou consulte a aba Dados.", "Session saved! Load the next video or check the Data tab.", "Sesion guardada! Cargue el siguiente video o revise la pestana Datos."))
                innerTabs.currentIndex = 1 // Volta para GravaÃ§Ã£o â€” prontos para prÃ³xima sessÃ£o
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

                Text { text: "ðŸ§ "; font.pixelSize: 20 }

                Text {
                    text: root.searchMode
                          ? LanguageManager.tr3("Reconhecimento de Objetos - Experimentos", "Object Recognition - Experiments", "Reconocimiento de Objetos - Experimentos")
                          : LanguageManager.tr3("Reconhecimento de Objetos - Dashboard", "Object Recognition - Dashboard", "Reconocimiento de Objetos - Panel")
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
                                    // Carrega os dados para a Ã¡rea de trabalho
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
                                    anchors.centerIn: parent; text: "\uD83D\uDDD1"
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
                        text: LanguageManager.tr3("Nenhum experimento\nencontrado", "No experiment\nfound", "Ningun experimento\nencontrado")
                            color: ThemeManager.textSecondary; font.pixelSize: 12; Behavior on color { ColorAnimation { duration: 150 } }
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

                // â”€â”€ Dados do experimento carregados do metadata.json â”€â”€â”€â”€â”€â”€
                property int    activeNumCampos: root.numCampos
                property string pair1:       ""
                property string pair2:       ""
                property string pair3:       ""
                property bool   includeDrug: true
                property bool   hasReactivation: false
                property var    dayNames:        []
                property bool   hasObjectZones: true
                property string analysisMode: "offline"
                property string saveDirectory: ""

                // â”€â”€ SessÃ£o de gravaÃ§Ã£o â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                // Persistem entre rodadas (nÃ£o pedem ao usuÃ¡rio novamente)
                property string sessionType: LanguageManager.tr3("Treino", "Training", "Entrenamiento")
                readonly property bool isReactivationPhase: (sessionType === "ReativaÃ§Ã£o") || (sessionType === "Reactivation") || (sessionType === "Teste D2") || (sessionType === "Test D2") || (sessionType === "Teste D3") || (sessionType === "Test D3")
                readonly property string sessionDia: {
                    if (sessionType === "ReativaÃ§Ã£o" || sessionType === "Reactivation") return "2"
                    if (sessionType === "Teste D2" || sessionType === "Test D2") return "2"
                    if (sessionType === "Teste D3" || sessionType === "Test D3") return "3"
                    return "1"
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
                    // Se estivermos em searchMode, a sidebar NÃƒO serÃ¡ limpa (graÃ§as ao m_inSearchMode no C++)
                    ExperimentManager.setActiveContext(ctx)

                    pair1          = meta.pair1 || ""
                    pair2          = meta.pair2 || ""
                    pair3          = meta.pair3 || ""
                    includeDrug     = meta.includeDrug !== false
                    hasReactivation = meta.hasReactivation === true
                    dayNames        = meta.dayNames || (meta.hasReactivation
                                      ? [LanguageManager.tr3("Treino", "Training", "Entrenamiento"), LanguageManager.tr3("Reativacao", "Reactivation", "Reactivacion"), LanguageManager.tr3("Teste", "Test", "Prueba")]
                                      : [LanguageManager.tr3("Treino", "Training", "Entrenamiento"), LanguageManager.tr3("Teste", "Test", "Prueba")])
                    activeNumCampos = meta.numCampos || 3

                    // Carrega configuraÃ§Ã£o da arena usando o path direto (jÃ¡ atualizado no C++)
                    ArenaConfigModel.loadConfigFromPath(path)

                    // Se a arena jÃ¡ foi configurada (tem parId), pula para aba GravaÃ§Ã£o
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
                                text: "ðŸ“‹"; font.pixelSize: 48; opacity: 0.3
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                        text: LanguageManager.tr3("Selecione um experimento\nna barra lateral", "Select an experiment\nin the sidebar", "Seleccione un experimento\nen la barra lateral")
                                color: ThemeManager.textSecondary; font.pixelSize: 14
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }

                    // 1: Experimento (tab bar + conteÃºdo)
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
                                    model: ["🗺 " + LanguageManager.tr3("Arena", "Arena", "Arena"), "🎬 " + LanguageManager.tr3("Gravacao", "Recording", "Grabacion"), "📊 " + LanguageManager.tr3("Dados", "Data", "Datos")]

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
                                onZonasEditadas: {
                                    // Atualiza zonas em tempo real na aba GravaÃ§Ã£o (sem salvar)
                                    var z = tabArenaSetup.zones
                                    liveRecordingTab.zones = z
                                }
                                numCampos: workArea.activeNumCampos
                                aparato: "nor"
                            }

                            // Tab 1: GravaÃ§Ã£o
                            LiveRecording {
                                id: liveRecordingTab
                                videoPath: tabArenaSetup.videoPath
                                analysisMode: workArea.analysisMode
                                numCampos: workArea.activeNumCampos
                                aparato: "nor"
                                isReactivation: workArea.isReactivationPhase

                                zones: (function() {
                                    var src = ArenaConfigModel.zones || []
                                    if (!src.length) return []
                                    var converted = []
                                    for (var i = 0; i < src.length; i++) {
                                        var z = src[i]
                                        converted.push({
                                            x: z.xRatio !== undefined ? z.xRatio : 0.3,
                                            y: z.yRatio !== undefined ? z.yRatio : 0.5,
                                            r: z.radiusRatio !== undefined ? z.radiusRatio : 0.12
                                        })
                                    }
                                    return converted
                                })()

                                arenaPoints: (function() {
                                    var arr = JSON.parse(ArenaConfigModel.getArenaPoints() || "[]")
                                    return arr
                                })()

                                floorPoints: (function() {
                                    var arr = JSON.parse(ArenaConfigModel.getFloorPoints() || "[]")
                                    return arr
                                })()

                                Connections {
                                    target: ArenaConfigModel
                                    function onConfigChanged() {
                                        var srcZ = ArenaConfigModel.zones || []
                                        if (!srcZ.length) return
                                        var converted = []
                                        for (var i = 0; i < srcZ.length; i++) {
                                            var z = srcZ[i]
                                            converted.push({
                                                x: z.xRatio !== undefined ? z.xRatio : 0.3,
                                                y: z.yRatio !== undefined ? z.yRatio : 0.5,
                                                r: z.radiusRatio !== undefined ? z.radiusRatio : 0.12
                                            })
                                        }
                                        liveRecordingTab.zones = converted

                                        var srcAP = JSON.parse(ArenaConfigModel.getArenaPoints() || "[]")
                                        var srcFP = JSON.parse(ArenaConfigModel.getFloorPoints() || "[]")
                                        liveRecordingTab.arenaPoints = srcAP
                                        liveRecordingTab.floorPoints = srcFP
                                    }
                                }

                                pair1: workArea.pair1
                                pair2: workArea.pair2
                                pair3: workArea.pair3

                                // Timer de 300 s zerou â†’ injeta dados de tracking e abre o diÃ¡logo
                                onSessionEnded: {
                                    resultDialog.sessionExplorationBouts = liveRecordingTab.explorationBouts
                                    resultDialog.sessionExplorationTimes = liveRecordingTab.explorationTimes
                                    resultDialog.sessionTotalDistance    = liveRecordingTab.totalDistance
                                    resultDialog.sessionAvgVelocity      = liveRecordingTab.avgVelocityMeans
                                    resultDialog.sessionPerMinuteData    = liveRecordingTab.perMinuteData
                                    resultDialog.open()
                                }

                                // BotÃ£o "Carregar VÃ­deo" na aba GravaÃ§Ã£o â†’ abre o seletor de vÃ­deo
                                onRequestVideoLoad: {
                                    innerTabs.currentIndex = 0  // vai para Arena
                                    tabArenaSetup.openVideoLoader()
                                }
                            }

                            // Tab 2: Dados â€” Layout aparato-especÃ­fico
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

    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    // Popup: criar experimento NOR (colunas fixas, usado apenas na sidebar)
    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
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
                Text { text: "ðŸ“‹"; font.pixelSize: 20 }
                Text {
                    text: "Novo Experimento NOR"
                    color: ThemeManager.textPrimary; font.pixelSize: 17; font.weight: Font.Bold; Behavior on color { ColorAnimation { duration: 150 } }
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: "âœ•"; color: ThemeManager.textSecondary; font.pixelSize: 14; Behavior on color { ColorAnimation { duration: 150 } }
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
                        placeholderText: LanguageManager.tr3("Ex.: Control_Group_Day1", "Ex.: Control_Group_Day1", "Ej.: Grupo_Control_Dia1")
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
                        // Colunas padrÃ£o NOR (sem droga por simplicidade neste atalho)
                        ExperimentManager.createExperimentWithConfig(
                            createNameField.text.trim(), 0,
                            [LanguageManager.tr3("Diretorio do Video", "Video Directory", "Directorio del Video"),
                             LanguageManager.tr3("Animal", "Animal", "Animal"),
                             LanguageManager.tr3("Campo", "Field", "Campo"),
                             LanguageManager.tr3("Dia", "Day", "Dia"),
                             LanguageManager.tr3("Par de Objetos", "Object Pair", "Par de Objetos"),
                             LanguageManager.tr3("Exploracao Obj1 (s)", "Obj1 Exploration (s)", "Exploracion Obj1 (s)"),
                             LanguageManager.tr3("Bouts Obj1", "Obj1 Bouts", "Bouts Obj1"),
                             LanguageManager.tr3("Exploracao Obj2 (s)", "Obj2 Exploration (s)", "Exploracion Obj2 (s)"),
                             LanguageManager.tr3("Bouts Obj2", "Obj2 Bouts", "Bouts Obj2"),
                             LanguageManager.tr3("Exploracao Total (s)", "Total Exploration (s)", "Exploracion Total (s)"),
                             "DI",
                             LanguageManager.tr3("Distancia (m)", "Distance (m)", "Distancia (m)"),
                             LanguageManager.tr3("Velocidade (m/s)", "Speed (m/s)", "Velocidad (m/s)")])
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

    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    // Popup: confirmar exclusÃ£o â€” passo 1
    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
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
                text: "Tem certeza que deseja excluir\n\"" + root.pendingDeleteName + "\"?\n\nEsta aÃ§Ã£o Ã© irreversÃ­vel."
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

    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    // Popup: confirmar exclusÃ£o â€” passo 2
    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
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

            Text { text: "ConfirmaÃ§Ã£o Final"; color: ThemeManager.textPrimary; font.pixelSize: 16; font.weight: Font.Bold; Behavior on color { ColorAnimation { duration: 150 } } }

            Text {
                Layout.fillWidth: true
                text: "Para confirmar, digite o nome do experimento:"
                color: ThemeManager.textSecondary; font.pixelSize: 13; wrapMode: Text.WordWrap; Behavior on color { ColorAnimation { duration: 150 } }
            }

            // Nome em destaque â€” igual ao GitHub: "Digite exatamente: NomeDoExperimento"
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

    // â”€â”€ Dialog pÃ³s-sessÃ£o: inserÃ§Ã£o dos dados dos animais â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    SessionResultDialog {
        id: resultDialog
        experimentName:   workArea.selectedName
        pair1:            workArea.pair1
        pair2:            workArea.pair2
        pair3:            workArea.pair3
        hasReactivation:  workArea.hasReactivation
        dayNames:         workArea.dayNames
        includeDrug:      workArea.includeDrug
        analysisMode:     workArea.analysisMode
        saveDirectory:    workArea.saveDirectory
        videoPath:        liveRecordingTab.videoPath
        numCampos:        workArea.activeNumCampos
    }

    Toast { id: successToast; successMode: true;  anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 16 } }
    Toast { id: errorToast;   successMode: false; anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 16 } }
}

