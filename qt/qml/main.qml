// qml/main.qml
// Janela raiz e roteador de telas.
//
// Fluxo "Criar":
//   LandingScreen → HomeScreen (aparatos) → ArenaSelection → NORSetupScreen → MainDashboard
//
// Fluxo "Procurar":
//   LandingScreen → MainDashboard (searchMode)

import QtQuick 2.12
import QtQuick.Controls 2.12
import MindTrace.Backend 1.0

ApplicationWindow {
    id: root
    visible: true
    width:  980
    height: 700
    minimumWidth:  820
    minimumHeight: 580
    title: "MindTrace"
    color: "#0f0f1a"

    // ── Estado acumulado durante o fluxo de criação ───────────────────────
    property string pendingContext:     ""
    property string pendingArenaId:     ""
    property string pendingPair1:       ""
    property string pendingPair2:       ""
    property string pendingPair3:       ""
    property bool   pendingIncludeDrug: true

    // ── Conexão global: quando ExperimentManager cria um experimento
    //    via NORSetupScreen, navega para o dashboard.
    //    (Criações vindas do botão interno do dashboard são geridas lá.)
    property bool awaitingCreation: false

    Connections {
        target: ExperimentManager
        onExperimentCreated: {
            if (root.awaitingCreation) {
                root.awaitingCreation = false
                
                stack.push(dashboardComponent, {
                    "context":      root.pendingContext,
                    "arenaId":      root.pendingArenaId,
                    "searchMode":   false,
                    "currentTabIndex": 1, 
                    // NOVO: Passa o nome do experimento recém-criado
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

            onExperimentReady: function(name, cols, pair1, pair2, pair3, includeDrug) {
                ExperimentManager.loadContext(root.pendingContext)
                root.pendingPair1       = pair1
                root.pendingPair2       = pair2
                root.pendingPair3       = pair3
                root.pendingIncludeDrug = includeDrug
                root.awaitingCreation   = true
                
                // Cria o experimento com os dados e salva em Documentos
                ExperimentManager.createExperimentFull(name, cols, pair1, pair2, pair3, includeDrug)
            }
            onBackRequested: stack.pop()
        }
    }

    Component {
        id: dashboardComponent
        MainDashboard {
            onBackRequested: stack.pop()
        }
    }
}
