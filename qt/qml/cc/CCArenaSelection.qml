// qml/cc/CCArenaSelection.qml
// Passo 2 do fluxo CC: seleção do layout de campos e contexto.
//
// Regras de layout:
// 2 campos → Padrão ou Contextual
// 3 campos → Sem contexto (fixo)

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../core"
import "../core/Theme"

Item {
    id: root

    property int    selectedNumCampos: 3
    property string selectedContext:   "Padrão"

    readonly property string selectedArenaId:
        "cc_" + selectedNumCampos + "campos"

    // 1 e 3 campos não permitem escolha de contexto
    readonly property bool contextForced: selectedNumCampos !== 2

    signal selectionConfirmed(int numCampos, string context, string arenaId)
    signal backRequested()

    onContextForcedChanged: {
        if (contextForced) selectedContext = "Padrão"
    }

    Rectangle { anchors.fill: parent; color: ThemeManager.background; Behavior on color { ColorAnimation { duration: 200 } } }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 40
        spacing: 0

        // ── Header ───────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true; spacing: 10

            GhostButton { text: "← Voltar"; onClicked: root.backRequested() }
            Item { width: 8 }
            Text { text: "🧩"; font.pixelSize: 28; color: "#7a3dab" }

            ColumnLayout {
                spacing: 2
                Text {
                    text: "Comportamento Complexo"
                    color: ThemeManager.textPrimary
                    Behavior on color { ColorAnimation { duration: 150 } }
                    font.pixelSize: 22; font.weight: Font.Bold
                }
                Text {
                    text: "Selecione o layout de campos e contexto da arena"
                    color: ThemeManager.textSecondary
                    Behavior on color { ColorAnimation { duration: 150 } }
                    font.pixelSize: 13
                }
            }
        }

        Rectangle { Layout.fillWidth: true; Layout.topMargin: 18; height: 1; color: ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } } }

        Item { Layout.fillHeight: true; Layout.minimumHeight: 16 }

        // ── Corpo ─────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 32

            // ── Preview dinâmico ─────────────────────────────────────────
            Item {
                Layout.fillHeight: true
                Layout.preferredWidth: parent.height

                Rectangle {
                    id: outerFrame
                    width:  root.selectedNumCampos === 1
                            ? Math.min(parent.width * 0.95, parent.height * 1.55)
                            : Math.min(parent.width, parent.height) * 0.85
                    height: root.selectedNumCampos === 1 ? width / 1.55 : width
                    anchors.centerIn: parent
                    radius: 10
                    color: "#06060f"
                    border.color: ThemeManager.borderLight
                    border.width: 2
                    clip: true
                    Behavior on width  { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                    Behavior on height { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

                    // Grid view — 2 ou 3 campos
                    Item {
                        id: grid
                        anchors { fill: parent; margins: 8 }
                        opacity: root.selectedNumCampos > 1 ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 200 } }

                        property real cellW: (width  - 6) / 2
                        property real cellH: (height - 6) / 2
                        property bool ctx:   root.selectedContext === "Contextual"

                        // Campo 1 (topo-esq)
                        Rectangle {
                            x: 0; y: 0
                            width: grid.cellW; height: grid.cellH
                            radius: 6
                            color: root.selectedNumCampos >= 1 ? "#0d0d22" : "#0a0a18"
                            border.color: root.selectedNumCampos >= 1 ? "#7a3dab" : "#1a1a2e"
                            border.width: 1; clip: true
                            Behavior on color { ColorAnimation { duration: 200 } }
                            Behavior on border.color { ColorAnimation { duration: 200 } }

                            Rectangle { anchors { top: parent.top; left: parent.left; right: parent.right }
                                        height: 4; color: "#ab3d4c"; opacity: 0.8
                                        visible: grid.ctx && root.selectedNumCampos >= 1 }
                            Rectangle { anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                                        width: 4; color: "#6aab3d"; opacity: 0.8
                                        visible: grid.ctx && root.selectedNumCampos >= 1 }

                            Text {
                                anchors.centerIn: parent
                                text: root.selectedNumCampos >= 1 ? "Campo 1" : "—"
                                color: root.selectedNumCampos >= 1 ? "#7a3dab" : "#1a1a2e"
                                font.pixelSize: Math.max(8, parent.width * 0.13)
                                font.weight: Font.Bold
                                Behavior on color { ColorAnimation { duration: 200 } }
                            }
                        }

                        // Campo 2 (topo-dir)
                        Rectangle {
                            x: grid.cellW + 6; y: 0
                            width: grid.cellW; height: grid.cellH
                            radius: 6
                            color: root.selectedNumCampos >= 2 ? "#0d0d22" : "#0a0a18"
                            border.color: root.selectedNumCampos >= 2 ? "#7a3dab" : "#1a1a2e"
                            border.width: 1; clip: true
                            Behavior on color { ColorAnimation { duration: 200 } }
                            Behavior on border.color { ColorAnimation { duration: 200 } }

                            Rectangle { anchors { top: parent.top; left: parent.left; right: parent.right }
                                        height: 4; color: "#ab3d4c"; opacity: 0.8
                                        visible: grid.ctx && root.selectedNumCampos >= 2 }
                            Rectangle { anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                                        width: 4; color: "#ab8a3d"; opacity: 0.8
                                        visible: grid.ctx && root.selectedNumCampos >= 2 }

                            Text {
                                anchors.centerIn: parent
                                text: root.selectedNumCampos >= 2 ? "Campo 2" : "—"
                                color: root.selectedNumCampos >= 2 ? "#7a3dab" : "#1a1a2e"
                                font.pixelSize: Math.max(8, parent.width * 0.13)
                                font.weight: Font.Bold
                                Behavior on color { ColorAnimation { duration: 200 } }
                            }
                        }

                        // Campo 3 (baixo-esq)
                        Rectangle {
                            x: 0; y: grid.cellH + 6
                            width: grid.cellW; height: grid.cellH
                            radius: 6
                            color: root.selectedNumCampos >= 3 ? "#0d0d22" : "#0a0a18"
                            border.color: root.selectedNumCampos >= 3 ? "#7a3dab" : "#1a1a2e"
                            border.width: 1; clip: true
                            Behavior on color { ColorAnimation { duration: 200 } }
                            Behavior on border.color { ColorAnimation { duration: 200 } }

                            Rectangle { anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                                        height: 4; color: "#3d7aab"; opacity: 0.8
                                        visible: grid.ctx && root.selectedNumCampos >= 3 }
                            Rectangle { anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                                        width: 4; color: "#6aab3d"; opacity: 0.8
                                        visible: grid.ctx && root.selectedNumCampos >= 3 }

                            Text {
                                anchors.centerIn: parent
                                text: root.selectedNumCampos >= 3 ? "Campo 3" : "—"
                                color: root.selectedNumCampos >= 3 ? "#7a3dab" : "#1a1a2e"
                                font.pixelSize: Math.max(8, parent.width * 0.13)
                                font.weight: Font.Bold
                                Behavior on color { ColorAnimation { duration: 200 } }
                            }
                        }

                        // Célula inferior-dir: sempre inativa
                        Rectangle {
                            x: grid.cellW + 6; y: grid.cellH + 6
                            width: grid.cellW; height: grid.cellH
                            radius: 6; color: "#0a0a18"
                            border.color: "#1a1a2e"; border.width: 1
                            Text {
                                anchors.centerIn: parent; text: "—"; color: "#1a1a2e"
                                font.pixelSize: Math.max(10, parent.width * 0.15); font.weight: Font.Bold
                            }
                        }
                    }

                    // Vista retangular — 1 campo (estilo EI adaptado)
                    Item {
                        anchors { fill: parent; margins: 8 }
                        opacity: root.selectedNumCampos === 1 ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 200 } }

                        Rectangle {
                            id: ccZona1
                            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                            width: parent.width * 0.38 - 3
                            radius: 6; color: "#0d1422"
                            border.color: "#7a3dab"; border.width: 1
                            Text {
                                anchors.centerIn: parent
                                text: "Zona 1"
                                color: "#7a3dab"
                                font.pixelSize: Math.max(8, parent.width * 0.14)
                                font.weight: Font.Bold
                            }
                        }

                        Rectangle {
                            anchors { top: parent.top; bottom: parent.bottom; left: ccZona1.right; leftMargin: 2 }
                            width: 2; color: ThemeManager.border; opacity: 0.5
                        }

                        Rectangle {
                            anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                            width: parent.width * 0.62 - 3
                            radius: 6; color: "#0d0d22"
                            border.color: "#7a3dab"; border.width: 1
                            Text {
                                anchors.centerIn: parent
                                text: "Zona 2"
                                color: "#7a3dab"
                                font.pixelSize: Math.max(8, parent.width * 0.14)
                                font.weight: Font.Bold
                            }
                        }
                    }
                }
            }

            // ── Painel de opções ─────────────────────────────────────────
            ColumnLayout {
                Layout.fillHeight: true
                Layout.preferredWidth: 280
                spacing: 24

                // ── Número de campos ──────────────────────────────────────
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Text {
                        text: "LAYOUT DE CAMPOS"
                        color: "#8888aa"; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.5
                    }

                    Repeater {
                        model: [
                            { n: 1, label: "1 Campo",  desc: "Um campo — sem contexto" },
                            { n: 2, label: "2 Campos", desc: "Dois campos — contexto selecionável" },
                            { n: 3, label: "3 Campos", desc: "Três campos — sem contexto" }
                        ]
                        delegate: Rectangle {
                            Layout.fillWidth: true; height: 56; radius: 10
                            property bool isSelected: root.selectedNumCampos === modelData.n
                            color:        isSelected ? ThemeManager.accentDim : (layoutMa.containsMouse ? ThemeManager.surfaceHover : ThemeManager.surfaceDim)
                            border.color: isSelected ? "#7a3dab" : ThemeManager.border
                            border.width: isSelected ? 2 : 1
                            Behavior on color        { ColorAnimation { duration: 150 } }
                            Behavior on border.color { ColorAnimation { duration: 150 } }

                            ColumnLayout {
                                anchors { fill: parent; leftMargin: 14; rightMargin: 14; topMargin: 8; bottomMargin: 8 }
                                spacing: 2
                                Text {
                                    text: modelData.label
                                    color: parent.parent.isSelected ? ThemeManager.textPrimary : ThemeManager.textSecondary
                                    font.pixelSize: 13; font.weight: Font.Bold
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }
                                Text {
                                    text: modelData.desc
                                    color: ThemeManager.textTertiary; font.pixelSize: 10; wrapMode: Text.WordWrap
                                }
                            }
                            MouseArea {
                                id: layoutMa; anchors.fill: parent
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: root.selectedNumCampos = modelData.n
                            }
                        }
                    }
                }

                // ── Contexto ──────────────────────────────────────────────
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    opacity: root.contextForced ? 0.45 : 1.0
                    Behavior on opacity { NumberAnimation { duration: 200 } }

                    Text {
                        text: "CONTEXTO"
                        color: "#8888aa"; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.5
                    }

                    Rectangle {
                        Layout.fillWidth: true; height: 32; radius: 8
                        visible: root.contextForced
                        color: "#1a1a30"; border.color: "#3a3a5c"; border.width: 1
                        Text {
                            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                            text: "Contexto fixo em Padrão para " + root.selectedNumCampos + " campo" + (root.selectedNumCampos > 1 ? "s" : "")
                            color: "#666688"; font.pixelSize: 11
                        }
                    }

                    Repeater {
                        model: [
                            { ctx: "Padrão",     label: "Sem Contexto",  desc: "Paredes uniformes — arena neutra." },
                            { ctx: "Contextual", label: "Com Contexto",  desc: "Paredes coloridas — pistas visuais distintas." }
                        ]
                        delegate: Rectangle {
                            Layout.fillWidth: true; height: 52; radius: 10
                            property bool isSelected: root.selectedContext === modelData.ctx
                            enabled: !root.contextForced
                            color:        isSelected ? ThemeManager.accentDim : (ctxMa.containsMouse ? ThemeManager.surfaceHover : ThemeManager.surfaceDim)
                            border.color: isSelected ? "#7a3dab" : ThemeManager.border
                            border.width: isSelected ? 2 : 1
                            Behavior on color        { ColorAnimation { duration: 150 } }
                            Behavior on border.color { ColorAnimation { duration: 150 } }

                            ColumnLayout {
                                anchors { fill: parent; leftMargin: 14; rightMargin: 14; topMargin: 8; bottomMargin: 8 }
                                spacing: 2
                                Text {
                                    text: modelData.label
                                    color: parent.parent.isSelected ? ThemeManager.textPrimary : ThemeManager.textSecondary
                                    font.pixelSize: 13; font.weight: Font.Bold
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }
                                Text {
                                    text: modelData.desc
                                    color: ThemeManager.textTertiary; font.pixelSize: 10; wrapMode: Text.WordWrap
                                }
                            }
                            MouseArea {
                                id: ctxMa; anchors.fill: parent
                                enabled: !root.contextForced
                                hoverEnabled: true; cursorShape: root.contextForced ? Qt.ArrowCursor : Qt.PointingHandCursor
                                onClicked: if (!root.contextForced) root.selectedContext = modelData.ctx
                            }
                        }
                    }
                }

                Item { Layout.fillHeight: true }
            }
        }

        Item { Layout.fillHeight: true; Layout.minimumHeight: 16 }

        // ── Rodapé ────────────────────────────────────────────────────────
        RowLayout {
            Layout.alignment: Qt.AlignHCenter; spacing: 24

            Text { text: "Passo 2  —  Layout da Arena"; color: ThemeManager.textSecondary; font.pixelSize: 11 }

            Button {
                text: "Próximo →"
                onClicked: root.selectionConfirmed(root.selectedNumCampos, root.selectedContext, root.selectedArenaId)

                background: Rectangle {
                    radius: 8
                    color: parent.hovered ? "#6a2d9a" : "#7a3dab"
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
                contentItem: Text {
                    text: parent.text; color: ThemeManager.buttonText
                    font.pixelSize: 13; font.weight: Font.Bold
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                }
                leftPadding: 24; rightPadding: 24; topPadding: 10; bottomPadding: 10
            }
        }

        Item { Layout.minimumHeight: 4 }
    }
}
