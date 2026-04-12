// qml/cc/CCArenaSelection.qml
// Passo 2 do fluxo CC: seleção do layout de campos e contexto.

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
                    width:  Math.min(parent.width, parent.height) * 0.85
                    height: width
                    anchors.centerIn: parent
                    radius: 10
                    color: "#06060f"
                    border.color: ThemeManager.borderLight
                    border.width: 2
                    clip: true

                    Item {
                        id: grid
                        anchors { fill: parent; margins: 8 }

                        property real cellW: (width  - 6) / 2
                        property real cellH: (height - 6) / 2
                        property bool ctx:   root.selectedContext === "Contextual"

                        property var fieldDefs: [
                            { cx: 0,             cy: 0,             active: root.selectedNumCampos >= 1 },
                            { cx: cellW + 6,     cy: 0,             active: root.selectedNumCampos >= 2 },
                            { cx: 0,             cy: cellH + 6,     active: root.selectedNumCampos >= 3 }
                        ]

                        Repeater {
                            model: 3
                            delegate: Rectangle {
                                x: grid.fieldDefs[index].cx
                                y: grid.fieldDefs[index].cy
                                width: grid.cellW; height: grid.cellH
                                radius: 6
                                color:        grid.fieldDefs[index].active ? "#0d0d22" : "#0a0a18"
                                border.color: grid.fieldDefs[index].active ? "#7a3dab" : "#1a1a2e"
                                border.width: 1; clip: true
                                Behavior on color { ColorAnimation { duration: 200 } }
                                Behavior on border.color { ColorAnimation { duration: 200 } }
                                visible: grid.fieldDefs[index].active

                                // Contexto topo
                                Rectangle {
                                    anchors { top: parent.top; left: parent.left; right: parent.right }
                                    height: 4; color: "#ab3d4c"; opacity: 0.8
                                    visible: grid.ctx
                                }
                                // Contexto lado
                                Rectangle {
                                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                                    width: 4; color: "#6aab3d"; opacity: 0.8
                                    visible: grid.ctx
                                }

                                // Label C1/C2/C3
                                Text {
                                    anchors { top: parent.top; left: parent.left; margins: 6 }
                                    text: "C" + (index + 1)
                                    color: "#7a3dab"; font.pixelSize: 11; font.weight: Font.Bold
                                }

                                // Chão interior (sem círculos de objetos, sem centro)
                                Rectangle {
                                    anchors { fill: parent; margins: parent.width * 0.15 }
                                    color: "transparent"
                                    border.color: "#7a3dab"; border.width: 1; radius: 3; opacity: 0.5
                                }
                            }
                        }
                    }
                }
            }

            // ── Controles de seleção ──────────────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 20

                // Número de campos
                ColumnLayout {
                    spacing: 10
                    Text {
                        text: "NÚMERO DE CAMPOS"
                        color: ThemeManager.textSecondary
                        font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.5
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    Repeater {
                        model: [
                            { n: 3, label: "3 campos", desc: "Três sessões independentes" },
                            { n: 2, label: "2 campos", desc: "Com ou sem contexto" },
                            { n: 1, label: "1 campo",  desc: "Sessão única" }
                        ]
                        delegate: Rectangle {
                            Layout.fillWidth: true; height: 56; radius: 10
                            property bool sel: root.selectedNumCampos === modelData.n
                            color: sel ? "#1a0d2e" : (hov.containsMouse ? ThemeManager.surfaceAlt : ThemeManager.surfaceDim)
                            border.color: sel ? "#7a3dab" : ThemeManager.border
                            border.width: sel ? 2 : 1
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on border.color { ColorAnimation { duration: 150 } }

                            RowLayout {
                                anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                                spacing: 12
                                ColumnLayout {
                                    spacing: 2
                                    Text { text: modelData.label; color: ThemeManager.textPrimary; font.pixelSize: 13; font.weight: Font.Bold }
                                    Text { text: modelData.desc; color: ThemeManager.textSecondary; font.pixelSize: 11 }
                                }
                                Item { Layout.fillWidth: true }
                                Rectangle {
                                    width: 18; height: 18; radius: 9
                                    color: "transparent"
                                    border.color: sel ? "#7a3dab" : ThemeManager.border; border.width: 2
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 8; height: 8; radius: 4
                                        color: "#7a3dab"
                                        visible: sel
                                    }
                                }
                            }
                            MouseArea {
                                id: hov; anchors.fill: parent
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: root.selectedNumCampos = modelData.n
                            }
                        }
                    }
                }

                // Contexto (apenas 2 campos)
                ColumnLayout {
                    spacing: 10
                    visible: root.selectedNumCampos === 2

                    Text {
                        text: "CONTEXTO"
                        color: ThemeManager.textSecondary
                        font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.5
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    Repeater {
                        model: [
                            { c: "Padrão",      label: "Sem contexto",  desc: "Campos idênticos" },
                            { c: "Contextual",  label: "Com contexto",  desc: "Campos diferenciados" }
                        ]
                        delegate: Rectangle {
                            Layout.fillWidth: true; height: 48; radius: 10
                            property bool sel: root.selectedContext === modelData.c
                            color: sel ? "#1a0d2e" : (ctxHov.containsMouse ? ThemeManager.surfaceAlt : ThemeManager.surfaceDim)
                            border.color: sel ? "#7a3dab" : ThemeManager.border; border.width: sel ? 2 : 1
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on border.color { ColorAnimation { duration: 150 } }

                            RowLayout {
                                anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                                ColumnLayout {
                                    spacing: 2
                                    Text { text: modelData.label; color: ThemeManager.textPrimary; font.pixelSize: 13; font.weight: Font.Bold }
                                    Text { text: modelData.desc;  color: ThemeManager.textSecondary; font.pixelSize: 11 }
                                }
                                Item { Layout.fillWidth: true }
                                Rectangle {
                                    width: 18; height: 18; radius: 9; color: "transparent"
                                    border.color: sel ? "#7a3dab" : ThemeManager.border; border.width: 2
                                    Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: "#7a3dab"; visible: sel }
                                }
                            }
                            MouseArea {
                                id: ctxHov; anchors.fill: parent
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: root.selectedContext = modelData.c
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

            Text {
                text: "Passo 2  —  Layout da Arena"
                color: ThemeManager.textSecondary; font.pixelSize: 11
            }

            Rectangle {
                height: 36; radius: 8
                implicitWidth: nextLbl.implicitWidth + 32
                color: nextMa.containsMouse ? "#6a2d9a" : "#7a3dab"
                Behavior on color { ColorAnimation { duration: 150 } }

                Text {
                    id: nextLbl; anchors.centerIn: parent
                    text: "Continuar →"
                    color: "white"; font.pixelSize: 13; font.weight: Font.Bold
                }
                MouseArea {
                    id: nextMa; anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: root.selectionConfirmed(root.selectedNumCampos, root.selectedContext, root.selectedArenaId)
                }
            }
        }

        Item { Layout.minimumHeight: 4 }
    }
}
