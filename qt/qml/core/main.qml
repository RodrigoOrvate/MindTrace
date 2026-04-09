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

    // ── Estado acumulado durante o fluxo de criação ───────────────────────
    property string pendingContext:     ""
    property string pendingArenaId:     ""
    property string pendingPair1:       ""
    property string pendingPair2:       ""
    property string pendingPair3:       ""
    property bool   pendingIncludeDrug: true

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
            if (root.awaitingCreation) {
                root.awaitingCreation = false
                stack.push(dashboardComponent, {
                    "context":      root.pendingContext,
                    "arenaId":      root.pendingArenaId,
                    "searchMode":   false,
                    "currentTabIndex": 1,
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
        parent: root
    }

    // ── Componentes de tela ───────────────────────────────────────────────

    Component {
        id: landingComponent
        LandingScreen {
            onCreateSelected: stack.push(homeScreenComponent)
            onSearchSelected: stack.push(dashboardComponent, { "searchMode": true, "context": "" })
        }
    }

    Component {
        id: homeScreenComponent
        HomeScreen {
            onNorSelected:    stack.push(arenaSelectionComponent)
            onBackRequested:  stack.pop()
        }
    }

    Component {
        id: arenaSelectionComponent
        ArenaSelection {
            onSelectionConfirmed: function(context, arenaId) {
                root.pendingContext = context
                root.pendingArenaId = arenaId
                stack.push(norSetupComponent, {
                    "context": context,
                    "arenaId": arenaId
                })
            }
            onBackRequested: stack.pop()
        }
    }

    Component {
        id: norSetupComponent
        NORSetupScreen {
            // Passa o laboratório e arena atuais para a tela de criação
            context: root.currentContext
            arenaId: root.currentArenaId

            onExperimentReady: function(name, cols, pair1, pair2, pair3, includeDrug, hasReactivation, savePath) {
                ExperimentManager.loadContext(root.pendingContext)
                root.pendingPair1       = pair1
                root.pendingPair2       = pair2
                root.pendingPair3       = pair3
                root.pendingIncludeDrug = includeDrug
                root.awaitingCreation   = true
                
                // Cria o experimento com os dados e salva no diretorio customizado se houver
                ExperimentManager.createExperimentFull(name, cols, pair1, pair2, pair3, includeDrug, hasReactivation, savePath)
            }
            onBackRequested: stack.pop()
        }
    }

    Component {
        id: dashboardComponent
        NORDashboard {
            onBackRequested: stack.pop()
        }
    }
}
