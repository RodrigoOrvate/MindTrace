// qml/ca/CAArenaSelection.qml
// Passo 2 do fluxo CA: seleção do layout de campos e contexto.
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
        "ca_" + selectedNumCampos + "campos"

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

            GhostButton { text: LanguageManager.tr3("<- Voltar", "<- Back", "<- Volver"); onClicked: root.backRequested() }
            Item { width: 8 }
            Text { text: "🐀"; font.pixelSize: 28; color: "#3d7aab" }

            ColumnLayout {
                spacing: 2
                Text {
                    text: LanguageManager.tr3("Campo Aberto", "Open Field", "Campo Abierto")
                    color: ThemeManager.textPrimary
                    Behavior on color { ColorAnimation { duration: 150 } }
                    font.pixelSize: 22; font.weight: Font.Bold
                }
                Text {
                    text: LanguageManager.tr3("Selecione o layout de campos e contexto da arena", "Select the field layout and arena context", "Seleccione el diseno de campos y contexto de la arena")
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

                        property var fieldDefs: [
                            { cx: 0,             cy: 0,             active: root.selectedNumCampos >= 1 },
                            { cx: cellW + 6,     cy: 0,             active: root.selectedNumCampos >= 2 },
                            { cx: 0,             cy: cellH + 6,     active: root.selectedNumCampos >= 3 }
                        ]

                        // Campo 1 (topo-esq)
                        Rectangle {
                            x: 0; y: 0
                            width: grid.cellW; height: grid.cellH
                            radius: 6
                            color: grid.fieldDefs[0].active ? "#0d0d22" : "#0a0a18"
                            border.color: grid.fieldDefs[0].active ? "#3d7aab" : "#1a1a2e"
                            border.width: 1; clip: true
                            Behavior on color { ColorAnimation { duration: 200 } }
                            Behavior on border.color { ColorAnimation { duration: 200 } }

                            Rectangle { anchors { top: parent.top; left: parent.left; right: parent.right }
                                        height: 4; color: "#ab3d4c"; opacity: 0.8
                                        visible: grid.ctx && grid.fieldDefs[0].active }
                            Rectangle { anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                                        width: 4; color: "#6aab3d"; opacity: 0.8
                                        visible: grid.ctx && grid.fieldDefs[0].active }

                            Text {
                                anchors.centerIn: parent
                                text: grid.fieldDefs[0].active ? LanguageManager.tr3("Campo 1", "Field 1", "Campo 1") : "—"
                                color: grid.fieldDefs[0].active ? "#3d7aab" : "#1a1a2e"
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
                            color: grid.fieldDefs[1].active ? "#0d0d22" : "#0a0a18"
                            border.color: grid.fieldDefs[1].active ? "#3d7aab" : "#1a1a2e"
                            border.width: 1; clip: true
                            Behavior on color { ColorAnimation { duration: 200 } }
                            Behavior on border.color { ColorAnimation { duration: 200 } }

                            Rectangle { anchors { top: parent.top; left: parent.left; right: parent.right }
                                        height: 4; color: "#ab3d4c"; opacity: 0.8
                                        visible: grid.ctx && grid.fieldDefs[1].active }
                            Rectangle { anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                                        width: 4; color: "#ab8a3d"; opacity: 0.8
                                        visible: grid.ctx && grid.fieldDefs[1].active }

                            Text {
                                anchors.centerIn: parent
                                text: grid.fieldDefs[1].active ? LanguageManager.tr3("Campo 2", "Field 2", "Campo 2") : "—"
                                color: grid.fieldDefs[1].active ? "#3d7aab" : "#1a1a2e"
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
                            color: grid.fieldDefs[2].active ? "#0d0d22" : "#0a0a18"
                            border.color: grid.fieldDefs[2].active ? "#3d7aab" : "#1a1a2e"
                            border.width: 1; clip: true
                            Behavior on color { ColorAnimation { duration: 200 } }
                            Behavior on border.color { ColorAnimation { duration: 200 } }

                            Rectangle { anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                                        height: 4; color: "#3d7aab"; opacity: 0.8
                                        visible: grid.ctx && grid.fieldDefs[2].active }
                            Rectangle { anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                                        width: 4; color: "#6aab3d"; opacity: 0.8
                                        visible: grid.ctx && grid.fieldDefs[2].active }

                            Text {
                                anchors.centerIn: parent
                                text: grid.fieldDefs[2].active ? LanguageManager.tr3("Campo 3", "Field 3", "Campo 3") : "—"
                                color: grid.fieldDefs[2].active ? "#3d7aab" : "#1a1a2e"
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
                            id: caZona1
                            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                            width: parent.width * 0.38 - 3
                            radius: 6; color: "#0d1a22"
                            border.color: "#3d7aab"; border.width: 1
                            Text {
                                anchors.centerIn: parent
                                text: LanguageManager.tr3("Zona 1", "Zone 1", "Zona 1")
                                color: "#3d7aab"
                                font.pixelSize: Math.max(8, parent.width * 0.14)
                                font.weight: Font.Bold
                            }
                        }

                        Rectangle {
                            anchors { top: parent.top; bottom: parent.bottom; left: caZona1.right; leftMargin: 2 }
                            width: 2; color: ThemeManager.border; opacity: 0.5
                        }

                        Rectangle {
                            anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                            width: parent.width * 0.62 - 3
                            radius: 6; color: "#0d0d22"
                            border.color: "#3d7aab"; border.width: 1
                            Text {
                                anchors.centerIn: parent
                                text: LanguageManager.tr3("Zona 2", "Zone 2", "Zona 2")
                                color: "#3d7aab"
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
                        text: LanguageManager.tr3("LAYOUT DE CAMPOS", "FIELD LAYOUT", "DISENO DE CAMPOS")
                        color: "#8888aa"; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.5
                    }

                    Repeater {
                        model: [
                            { n: 1, label: LanguageManager.tr3("1 Campo", "1 Field", "1 Campo"),  desc: LanguageManager.tr3("Um campo - sem contexto", "One field - no context", "Un campo - sin contexto") },
                            { n: 2, label: LanguageManager.tr3("2 Campos", "2 Fields", "2 Campos"), desc: LanguageManager.tr3("Dois campos - contexto selecionavel", "Two fields - selectable context", "Dos campos - contexto seleccionable") },
                            { n: 3, label: LanguageManager.tr3("3 Campos", "3 Fields", "3 Campos"), desc: LanguageManager.tr3("Tres campos - sem contexto", "Three fields - no context", "Tres campos - sin contexto") }
                        ]
                        delegate: Rectangle {
                            Layout.fillWidth: true; height: 56; radius: 10
                            property bool isSelected: root.selectedNumCampos === modelData.n
                            color:        isSelected ? ThemeManager.accentDim : (layoutMa.containsMouse ? ThemeManager.surfaceHover : ThemeManager.surfaceDim)
                            border.color: isSelected ? "#3d7aab" : ThemeManager.border
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
                        text: LanguageManager.tr3("CONTEXTO", "CONTEXT", "CONTEXTO")
                        color: "#8888aa"; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.5
                    }

                    Rectangle {
                        Layout.fillWidth: true; height: 32; radius: 8
                        visible: root.contextForced
                        color: "#1a1a30"; border.color: "#3a3a5c"; border.width: 1
                        Text {
                            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                            text: LanguageManager.tr3("Contexto fixo em Padrao para ", "Context fixed as Default for ", "Contexto fijo en Predeterminado para ") + root.selectedNumCampos + " " + LanguageManager.tr3("campo", "field", "campo") + (root.selectedNumCampos > 1 ? "s" : "")
                            color: "#666688"; font.pixelSize: 11
                        }
                    }

                    Repeater {
                        model: [
                            { ctx: "Padrão",     label: LanguageManager.tr3("Sem Contexto", "No Context", "Sin Contexto"),  desc: LanguageManager.tr3("Paredes uniformes - arena neutra.", "Uniform walls - neutral arena.", "Paredes uniformes - arena neutra.") },
                            { ctx: "Contextual", label: LanguageManager.tr3("Com Contexto", "With Context", "Con Contexto"),  desc: LanguageManager.tr3("Paredes coloridas - pistas visuais distintas.", "Colored walls - distinct visual cues.", "Paredes coloreadas - pistas visuales distintas.") }
                        ]
                        delegate: Rectangle {
                            Layout.fillWidth: true; height: 52; radius: 10
                            property bool isSelected: root.selectedContext === modelData.ctx
                            enabled: !root.contextForced
                            color:        isSelected ? ThemeManager.accentDim : (ctxMa.containsMouse ? ThemeManager.surfaceHover : ThemeManager.surfaceDim)
                            border.color: isSelected ? "#3d7aab" : ThemeManager.border
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

            Text { text: LanguageManager.tr3("Passo 2 - Layout da Arena", "Step 2 - Arena Layout", "Paso 2 - Diseno de la Arena"); color: ThemeManager.textSecondary; font.pixelSize: 11 }

            Button {
                text: LanguageManager.tr3("Proximo ->", "Next ->", "Siguiente ->")
                onClicked: root.selectionConfirmed(root.selectedNumCampos, root.selectedContext, root.selectedArenaId)

                background: Rectangle {
                    radius: 8
                    color: parent.hovered ? "#2d5f8a" : "#3d7aab"
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
