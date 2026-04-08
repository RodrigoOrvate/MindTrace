// qml/ArenaSelection.qml
// Passo 2 do fluxo NOR: seleção do contexto da arena quadrada (60×60 cm).

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../core"

Item {
    id: root

    // "Padrão" ou "Contextual"
    property string selectedContext: "Padrão"

    // arenaId: "sq_padrao" ou "sq_contextual"
    readonly property string selectedArenaId:
        "sq_" + (selectedContext === "Padrão" ? "padrao" : "contextual")

    signal selectionConfirmed(string context, string arenaId)
    signal backRequested()

    Rectangle { anchors.fill: parent; color: "#0f0f1a" }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 40
        spacing: 0

        // ── Header ───────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true; spacing: 10

            GhostButton { text: "← Voltar"; onClicked: root.backRequested() }
            Item { width: 8 }
            Text { text: "🧠"; font.pixelSize: 28; color: "#ab3d4c" }

            ColumnLayout {
                spacing: 2
                Text {
                    text: "Reconhecimento de Objetos"
                    color: "#e8e8f0"; font.pixelSize: 22; font.weight: Font.Bold
                }
                Text {
                    text: "Defina o tipo de contexto — arena quadrada (60×60 cm)"
                    color: "#8888aa"; font.pixelSize: 13
                }
            }
        }

        Rectangle { Layout.fillWidth: true; Layout.topMargin: 18; height: 1; color: "#2d2d4a" }

        Item { Layout.fillHeight: true; Layout.minimumHeight: 16 }

        // ── Corpo principal ───────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 32

            // ── Preview da arena — mosaico 2×2 (3 campos ativos) ─────────────────
            Item {
                Layout.fillHeight: true
                Layout.preferredWidth: parent.height

                // Outer frame: representa o campo de visão da câmera
                Rectangle {
                    id: outerFrame
                    width:  Math.min(parent.width, parent.height) * 0.85
                    height: width
                    anchors.centerIn: parent

                    radius: 10
                    color: "#06060f"
                    border.color: "#4a4a6a"
                    border.width: 2
                    clip: true

                    // Container interno das 4 células
                    Item {
                        id: grid
                        anchors { fill: parent; margins: 8 }

                        property real cellW: (width  - 6) / 2
                        property real cellH: (height - 6) / 2
                        property bool ctx: root.selectedContext === "Contextual"

                        // ── Campo 1 (topo-esquerda) ───────────────────────
                        Rectangle {
                            x: 0; y: 0
                            width: grid.cellW; height: grid.cellH
                            radius: 6; color: "#0d0d22"
                            border.color: "#ab3d4c"; border.width: 1; clip: true

                            // Paredes contextuais
                            Rectangle { anchors { top: parent.top; left: parent.left; right: parent.right }
                                        height: 4; color: "#ab3d4c"; opacity: 0.8
                                        visible: grid.ctx }
                            Rectangle { anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                                        width: 4; color: "#6aab3d"; opacity: 0.8
                                        visible: grid.ctx }

                            Text {
                                anchors.centerIn: parent
                                text: "Campo 1"; color: "#ab3d4c"
                                font.pixelSize: Math.max(8, parent.width * 0.13)
                                font.weight: Font.Bold
                            }
                        }

                        // ── Campo 2 (topo-direita) ────────────────────────
                        Rectangle {
                            x: grid.cellW + 6; y: 0
                            width: grid.cellW; height: grid.cellH
                            radius: 6; color: "#0d0d22"
                            border.color: "#ab3d4c"; border.width: 1; clip: true

                            Rectangle { anchors { top: parent.top; left: parent.left; right: parent.right }
                                        height: 4; color: "#ab3d4c"; opacity: 0.8
                                        visible: grid.ctx }
                            Rectangle { anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                                        width: 4; color: "#ab8a3d"; opacity: 0.8
                                        visible: grid.ctx }

                            Text {
                                anchors.centerIn: parent
                                text: "Campo 2"; color: "#ab3d4c"
                                font.pixelSize: Math.max(8, parent.width * 0.13)
                                font.weight: Font.Bold
                            }
                        }

                        // ── Campo 3 (baixo-esquerda) ──────────────────────
                        Rectangle {
                            x: 0; y: grid.cellH + 6
                            width: grid.cellW; height: grid.cellH
                            radius: 6; color: "#0d0d22"
                            border.color: "#ab3d4c"; border.width: 1; clip: true

                            Rectangle { anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                                        height: 4; color: "#3d7aab"; opacity: 0.8
                                        visible: grid.ctx }
                            Rectangle { anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                                        width: 4; color: "#6aab3d"; opacity: 0.8
                                        visible: grid.ctx }

                            Text {
                                anchors.centerIn: parent
                                text: "Campo 3"; color: "#ab3d4c"
                                font.pixelSize: Math.max(8, parent.width * 0.13)
                                font.weight: Font.Bold
                            }
                        }

                        // ── Célula desativada (baixo-direita) ─────────────
                        Rectangle {
                            x: grid.cellW + 6; y: grid.cellH + 6
                            width: grid.cellW; height: grid.cellH
                            radius: 6; color: "#0a0a18"
                            border.color: "#2a2a3a"; border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: "—"; color: "#2a2a3a"
                                font.pixelSize: Math.max(10, parent.width * 0.15)
                                font.weight: Font.Bold
                            }
                        }
                    }
                }
            }

            // ── Painel de opções (direita) ────────────────────────────────
            ColumnLayout {
                Layout.fillHeight: true
                Layout.preferredWidth: 260
                spacing: 28

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Text {
                        text: "CONTEXTO"
                        color: "#8888aa"; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.5
                    }

                    // Sem contexto (Padrão)
                    Rectangle {
                        Layout.fillWidth: true; height: 64; radius: 10
                        property bool isSelected: root.selectedContext === "Padrão"
                        color:        isSelected ? "#1f0d10" : (stdMouse.containsMouse ? "#16162e" : "#12122a")
                        border.color: isSelected ? "#ab3d4c" : "#2d2d4a"; border.width: isSelected ? 2 : 1
                        Behavior on color        { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        ColumnLayout {
                            anchors { fill: parent; leftMargin: 14; rightMargin: 14; topMargin: 10; bottomMargin: 10 }
                            spacing: 2
                            Text {
                                text: "Sem contexto  (Padrão)"
                                color: parent.parent.isSelected ? "#e8e8f0" : "#8888aa"
                                font.pixelSize: 13; font.weight: Font.Bold
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }
                            Text {
                                text: "Paredes uniformes — arena não diferencia o contexto."
                                color: "#555577"; font.pixelSize: 10; wrapMode: Text.WordWrap
                            }
                        }
                        MouseArea {
                            id: stdMouse; anchors.fill: parent
                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: root.selectedContext = "Padrão"
                        }
                    }

                    // Com contexto (Contextual)
                    Rectangle {
                        Layout.fillWidth: true; height: 64; radius: 10
                        property bool isSelected: root.selectedContext === "Contextual"
                        color:        isSelected ? "#1f0d10" : (ctxMouse.containsMouse ? "#16162e" : "#12122a")
                        border.color: isSelected ? "#ab3d4c" : "#2d2d4a"; border.width: isSelected ? 2 : 1
                        Behavior on color        { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        ColumnLayout {
                            anchors { fill: parent; leftMargin: 14; rightMargin: 14; topMargin: 10; bottomMargin: 10 }
                            spacing: 2
                            Text {
                                text: "Com contexto  (Contextual)"
                                color: parent.parent.isSelected ? "#e8e8f0" : "#8888aa"
                                font.pixelSize: 13; font.weight: Font.Bold
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }
                            Text {
                                text: "Paredes coloridas distintas — contexto visualmente diferenciado."
                                color: "#555577"; font.pixelSize: 10; wrapMode: Text.WordWrap
                            }
                        }
                        MouseArea {
                            id: ctxMouse; anchors.fill: parent
                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: root.selectedContext = "Contextual"
                        }
                    }
                }

                Item { Layout.fillHeight: true }

                // Legenda de paredes contextuais
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.selectedContext === "Contextual"
                    spacing: 4

                    Text { text: "Paredes da arena:"; color: "#555577"; font.pixelSize: 10 }

                    RowLayout {
                        spacing: 6
                        Repeater {
                            model: [
                                { label: "Norte", color: "#ab3d4c" },
                                { label: "Sul",   color: "#3d7aab" },
                                { label: "Oeste", color: "#6aab3d" },
                                { label: "Leste", color: "#ab8a3d" }
                            ]
                            delegate: RowLayout {
                                spacing: 4
                                Rectangle { width: 10; height: 10; radius: 2; color: modelData.color }
                                Text { text: modelData.label; color: "#666688"; font.pixelSize: 9 }
                            }
                        }
                    }
                }
            }
        }

        Item { Layout.fillHeight: true; Layout.minimumHeight: 16 }

        // ── Rodapé ────────────────────────────────────────────────────────
        RowLayout {
            Layout.alignment: Qt.AlignHCenter; spacing: 24

            Text { text: "Passo 2  —  Contexto da Arena"; color: "#8888aa"; font.pixelSize: 11 }

            Button {
                text: "Próximo →"
                onClicked: root.selectionConfirmed(root.selectedContext, root.selectedArenaId)

                background: Rectangle {
                    radius: 8
                    color: parent.hovered ? "#8a2e3b" : "#ab3d4c"
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
                contentItem: Text {
                    text: parent.text; color: "#e8e8f0"
                    font.pixelSize: 13; font.weight: Font.Bold
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                }
                leftPadding: 24; rightPadding: 24; topPadding: 10; bottomPadding: 10
            }
        }

        Item { Layout.minimumHeight: 4 }
    }
}
