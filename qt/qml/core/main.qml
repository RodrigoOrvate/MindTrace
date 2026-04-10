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
import "Theme"

ApplicationWindow {
    id: root
    visible: true
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

    // ── Estado acumulado durante o fluxo de criação CA ───────────────────
    property int    pendingCaNumCampos: 3
    property string pendingCaContext:   "Padrão"
    property string pendingCaArenaId:   "ca_3campos"
    property bool   pendingCaFlow:      false   // distingue NOR vs CA no onExperimentCreated

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

            if (root.pendingCaFlow) {
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
                    "currentTabIndex":       1,
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

    // ── Settings Button in Chrome (top-right) ─────────────────────────────
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

    Component {
        id: searchBrowserComponent
        SearchBrowser {
            onBackRequested: {
                ExperimentManager.clearFilter()
                stack.pop()
            }
            aparatoFilter: "" // Mostra todos por padrão no browser universal
            onOpenExperiment: function(aparato, numCampos, expName, expPath) {
                if (aparato === "campo_aberto") {
                    stack.push(caDashboardComponent, {
                        "searchMode": true,
                        "numCampos":  numCampos
                    })
                } else {
                    stack.push(dashboardComponent, {
                        "searchMode": true,
                        "numCampos":  numCampos,
                        "context":    ""
                    })
                }
            }
        }
    }
}
