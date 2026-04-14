// qml/main.qml
// Janela raiz e roteador de telas.
//
// Fluxo "Criar":
//   LandingScreen → HomeScreen (aparatos) → ArenaSelection → NORSetupScreen → MainDashboard
//
// Fluxo "Procurar":
//   LandingScreen → MainDashboard (searchMode)

import QtQuick
import QtQuick.Controls
import MindTrace.Backend 1.0
import "../nor"
import "../shared"
import "../ca"
import "../cc"
import "../ei"
import "Theme"

ApplicationWindow {
    id: root
    visible: true
    visibility: Window.Maximized
    width:  980
    height: 700
    minimumWidth:  820
    minimumHeight: 580
    title: "MindTrace"
    color: ThemeManager.background
    
    Behavior on color { ColorAnimation { duration: 200 } }

    // ── Estado acumulado durante o fluxo de criação NOR ──────────────────
    property string pendingContext:     ""
    property string pendingArenaId:     ""
    property int    pendingNorNumCampos: 3
    property string pendingPair1:       ""
    property string pendingPair2:       ""
    property string pendingPair3:       ""
    property bool   pendingIncludeDrug: true

    // ── Estado acumulado durante o fluxo de criação CA ──────────────────────────────────
    property int    pendingCaNumCampos: 3
    property string pendingCaContext:   "Padrão"
    property string pendingCaArenaId:   "ca_3campos"
    property bool   pendingCaFlow:      false   // distingue NOR vs CA no onExperimentCreated

    // ── Estado acumulado durante o fluxo de criação CC ──────────────────────────────────
    property int    pendingCcNumCampos:    3
    property string pendingCcContext:      "Padrão"
    property string pendingCcArenaId:      "cc_3campos"
    property int    pendingCcSessionMin:   5
    property bool   pendingCcFlow:         false   // distingue CC no onExperimentCreated
    property bool   pendingCcHasObjectZones: true  // zonas de objetos para sniffing vs resting

    // ── Estado acumulado durante o fluxo de criação IA ──────────────────────────────────
    property bool   pendingEiFlow:         false
    property int    pendingEiExtincaoDays: 5
    property bool   pendingEiHasReactivation: false

    // ── Auto-refresh da sidebar ao recuperar foco (detecta exclusões externas) ──
    onActiveChanged: {
        if (active)
            ExperimentManager.refreshModel()
    }

    // ── Conexão global: quando ExperimentManager cria um experimento
    //    via NORSetupScreen, navega para o dashboard.
    //    (Criações vindas do botão interno do dashboard são geridas lá.)
    property bool awaitingCreation: false

    // Qt 6: Connections requer sintaxe "function onSignal(params)" para acessar parâmetros
    Connections {
        target: ExperimentManager
        function onExperimentCreated(name, path) {
            if (!root.awaitingCreation) return
            root.awaitingCreation = false

            if (root.pendingEiFlow) {
                root.pendingEiFlow = false
                stack.push(eiDashboardComponent, {
                    "searchMode":            false,
                    "initialExperimentName": name,
                    "extincaoDays":          root.pendingEiExtincaoDays,
                    "hasReactivation":       root.pendingEiHasReactivation
                })
            } else if (root.pendingCcFlow) {
                root.pendingCcFlow = false
                stack.push(ccDashboardComponent, {
                    "context":               root.pendingCcContext,
                    "arenaId":               root.pendingCcArenaId,
                    "numCampos":             root.pendingCcNumCampos,
                    "searchMode":            false,
                    "initialExperimentName": name
                })
            } else if (root.pendingCaFlow) {
                root.pendingCaFlow = false
                stack.push(caDashboardComponent, {
                    "context":               root.pendingCaContext,
                    "arenaId":               root.pendingCaArenaId,
                    "numCampos":             root.pendingCaNumCampos,
                    "searchMode":            false,
                    "initialExperimentName": name
                })
            } else {
                stack.push(dashboardComponent, {
                    "context":               root.pendingContext,
                    "arenaId":               root.pendingArenaId,
                    "numCampos":             root.pendingNorNumCampos,
                    "searchMode":            false,
                    "currentTabIndex":       0,
                    "initialExperimentName": name
                })
            }
        }
    }

    // ── StackView ─────────────────────────────────────────────────────────
    StackView {
        id: stack
        anchors.fill: parent

        initialItem: landingComponent

        pushEnter: Transition {
            NumberAnimation { property: "x"; from: root.width; to: 0; duration: 220; easing.type: Easing.OutCubic }
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 180 }
        }
        pushExit: Transition {
            NumberAnimation { property: "x"; from: 0; to: -root.width * 0.2; duration: 220; easing.type: Easing.OutCubic }
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 180 }
        }
        popEnter: Transition {
            NumberAnimation { property: "x"; from: -root.width * 0.2; to: 0; duration: 220; easing.type: Easing.OutCubic }
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 180 }
        }
        popExit: Transition {
            NumberAnimation { property: "x"; from: 0; to: root.width; duration: 220; easing.type: Easing.OutCubic }
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 180 }
        }
    }

    // ── Home Button (antes da engrenagem) ───────────────────────────────────
    Button {
        id: homeButton
        anchors { top: parent.top; right: settingsButton.left; margins: 12 }
        width: 40
        height: 40
        text: "🏠"
        font.pixelSize: 16
        flat: true
        visible: stack.currentItem !== landingComponent

        background: Rectangle {
            color: homeButton.hovered ? ThemeManager.surfaceAlt : "transparent"
            radius: 6
            Behavior on color { ColorAnimation { duration: 150 } }
        }

        onClicked: {
            stack.clear()
            stack.push(landingComponent)
            ExperimentManager.clearFilter()
        }
    }

    // ── Settings Button (top-right) ────────────────────────────────────────
    Button {
        id: settingsButton
        anchors { top: parent.top; right: parent.right; margins: 12 }
        width: 40
        height: 40
        text: "⚙️"
        font.pixelSize: 18
        flat: true

        background: Rectangle {
            color: settingsButton.hovered ? ThemeManager.surfaceAlt : "transparent"
            radius: 6
            Behavior on color { ColorAnimation { duration: 150 } }
        }

        onClicked: settingsOverlay.open()
    }

    // ── Settings Modal Overlay ─────────────────────────────────────────────
    SettingsScreen {
        id: settingsOverlay
        parent: root.contentItem
    }

    // ── Componentes de tela ───────────────────────────────────────────────

    Component {
        id: landingComponent
        LandingScreen {
            onCreateSelected: stack.push(homeScreenComponent)
            onSearchSelected: stack.push(searchBrowserComponent)
        }
    }

    Component {
        id: homeScreenComponent
        HomeScreen {
            onNorSelected:    stack.push(arenaSelectionComponent)
            onCaSelected:     stack.push(caArenaSelectionComponent)
            onCcSelected:     stack.push(ccArenaSelectionComponent)
            onEiSelected:     stack.push(eiSetupComponent)
            onBackRequested:  stack.pop()
        }
    }

    Component {
        id: arenaSelectionComponent
        ArenaSelection {
            onSelectionConfirmed: function(numCampos, context, arenaId) {
                root.pendingNorNumCampos = numCampos
                root.pendingContext = context
                root.pendingArenaId = arenaId
                stack.push(norSetupComponent, {
                    "context":   context,
                    "arenaId":   arenaId,
                    "numCampos": numCampos
                })
            }
            onBackRequested: stack.pop()
        }
    }

    Component {
        id: norSetupComponent
        NORSetupScreen {
            onExperimentReady: function(name, cols, pair1, pair2, pair3, includeDrug, hasReactivation, savePath) {
                ExperimentManager.loadContext(root.pendingContext)
                root.pendingPair1       = pair1
                root.pendingPair2       = pair2
                root.pendingPair3       = pair3
                root.pendingIncludeDrug = includeDrug
                root.awaitingCreation   = true
                ExperimentManager.createExperimentFull(
                    name, cols, pair1, pair2, pair3, includeDrug, hasReactivation, savePath,
                    "nor", root.pendingNorNumCampos)
            }
            onBackRequested: stack.pop()
        }
    }

    Component {
        id: dashboardComponent
        NORDashboard {
            onBackRequested: {
                ExperimentManager.clearFilter()
                stack.pop()
            }
        }
    }

    // ── Fluxo CA ─────────────────────────────────────────────────────────

    Component {
        id: caArenaSelectionComponent
        CAArenaSelection {
            onSelectionConfirmed: function(numCampos, context, arenaId) {
                root.pendingCaNumCampos = numCampos
                root.pendingCaContext   = context
                root.pendingCaArenaId   = arenaId
                stack.push(caSetupComponent, {
                    "numCampos": numCampos,
                    "context":   context,
                    "arenaId":   arenaId
                })
            }
            onBackRequested: stack.pop()
        }
    }

    Component {
        id: caSetupComponent
        CASetup {
            onExperimentReady: function(name, cols, includeDrug, hasReactivation, savePath) {
                ExperimentManager.loadContext(root.pendingCaContext)
                root.awaitingCreation = true
                root.pendingCaFlow    = true
                ExperimentManager.createExperimentFull(
                    name, cols, "", "", "", includeDrug, hasReactivation, savePath,
                    "campo_aberto", root.pendingCaNumCampos)
            }
            onBackRequested: stack.pop()
        }
    }

    Component {
        id: caDashboardComponent
        CADashboard {
            onBackRequested: {
                ExperimentManager.clearFilter()
                stack.pop()
            }
        }
    }

    // ── Fluxo CC ──────────────────────────────────────────────────────────────────

    Component {
        id: ccArenaSelectionComponent
        CCArenaSelection {
            onSelectionConfirmed: function(numCampos, context, arenaId) {
                root.pendingCcNumCampos = numCampos
                root.pendingCcContext   = context
                root.pendingCcArenaId   = arenaId
                stack.push(ccSetupComponent, {
                    "numCampos": numCampos,
                    "context":   context,
                    "arenaId":   arenaId
                })
            }
            onBackRequested: stack.pop()
        }
    }

    Component {
        id: ccSetupComponent
        CCSetup {
            onExperimentReady: function(name, cols, includeDrug, sessionMinutes, hasObjectZones, savePath) {
                ExperimentManager.loadContext(root.pendingCcContext)
                root.pendingCcSessionMin = sessionMinutes
                root.pendingCcHasObjectZones = hasObjectZones
                root.awaitingCreation    = true
                root.pendingCcFlow       = true
                ExperimentManager.createExperimentFull(
                    name, cols, "", "", "", includeDrug, false, savePath,
                    "comportamento_complexo", root.pendingCcNumCampos, 0.5, hasObjectZones)
            }
            onBackRequested: stack.pop()
        }
    }

    Component {
        id: ccDashboardComponent
        CCDashboard {
            onBackRequested: {
                ExperimentManager.clearFilter()
                stack.pop()
            }
        }
    }

    // ── Fluxo IA ───────────────────────────────────────────────────────────────────

    Component {
        id: eiSetupComponent
        EISetup {
            onExperimentReady: function(name, cols, includeDrug, hasReactivation, extincaoDays, savePath) {
                root.pendingEiExtincaoDays = extincaoDays
                root.pendingEiHasReactivation = hasReactivation
                ExperimentManager.loadContext("Padrão")
                root.awaitingCreation = true
                root.pendingEiFlow = true
                ExperimentManager.createExperimentFull(
                    name, cols, "", "", "", includeDrug, false, savePath,
                    "esquiva_inibitoria", 1)
            }
            onBackRequested: {
                root.pendingEiFlow = false
                root.awaitingCreation = false
                stack.pop()
            }
        }
    }

    Component {
        id: eiDashboardComponent
        EIDashboard {
            onBackRequested: {
                ExperimentManager.clearFilter()
                stack.pop()
            }
        }
    }

    // ── SearchBrowser ────────────────────────────────────────────────────────────

    Component {
        id: searchBrowserComponent
        SearchBrowser {
            onBackRequested: {
                ExperimentManager.clearFilter()
                stack.pop()
            }
            aparatoFilter: "" // Mostra todos por padrão no browser universal
            onOpenExperiment: function(aparato, numCampos, expName, expPath) {
                var meta = ExperimentManager.readMetadataFromPath(expPath)
                if (aparato === "comportamento_complexo" || meta.aparato === "comportamento_complexo") {
                    stack.push(ccDashboardComponent, {
                        "searchMode":            true,
                        "numCampos":             numCampos,
                        "initialExperimentName": expName,
                        "currentTabIndex":       0
                    })
                } else if (aparato === "campo_aberto" || meta.aparato === "campo_aberto") {
                    stack.push(caDashboardComponent, {
                        "searchMode":            true,
                        "numCampos":             numCampos,
                        "initialExperimentName": expName,
                        "currentTabIndex":       0
                    })
                } else if (aparato === "esquiva_inibitoria" || meta.aparato === "esquiva_inibitoria") {
                    stack.push(eiDashboardComponent, {
                        "searchMode":            true,
                        "initialExperimentName": expName,
                        "currentTabIndex":       0
                    })
                } else {
                    stack.push(dashboardComponent, {
                        "searchMode":            true,
                        "numCampos":             numCampos,
                        "context":               "",
                        "initialExperimentName": expName,
                        "currentTabIndex":       0
                    })
                }
            }
        }
    }
}
