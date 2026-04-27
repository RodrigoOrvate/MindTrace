// qml/nor/ArenaSelection.qml
// Passo 2 do fluxo NOR: seleÃ§Ã£o de nÃºmero de campos e contexto.
// 2 campos â†’ PadrÃ£o ou Contextual
// 3 campos â†’ Sem contexto (fixo)

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../core"
import "../core/Theme"

Item {
    id: root

    property int    selectedNumCampos: 3
    property var    fieldPatterns: ["horizontal", "vertical", "dots"]
    property int    editingFieldIdx: -1
    readonly property var patternOptions: [
        { key: "horizontal", label: LanguageManager.tr3("Listras horizontais", "Horizontal stripes", "Franjas horizontales") },
        { key: "vertical",   label: LanguageManager.tr3("Listras verticais", "Vertical stripes", "Franjas verticales") },
        { key: "dots",       label: LanguageManager.tr3("Bolinhas", "Dots", "Puntos") },
        { key: "triangles",  label: LanguageManager.tr3("Triangulos", "Triangles", "Triangulos") },
        { key: "squares",    label: LanguageManager.tr3("Quadrados", "Squares", "Cuadrados") }
    ]
    property string selectedContext:   "PadrÃ£o"

    // Contexto forÃ§ado para 3 campos
    readonly property bool contextForced: selectedNumCampos !== 2
    readonly property string resolvedContext: contextForced ? "PadrÃ£o" : selectedContext

    readonly property string selectedArenaId:
        "sq_" + (resolvedContext === "PadrÃ£o" ? "padrao" : "contextual")

    // signal: numCampos, context, arenaId
    signal selectionConfirmed(int numCampos, string context, string arenaId, var contextPatterns)
    signal backRequested()

    function patternLabel(key) {
        for (var i = 0; i < patternOptions.length; i++) {
            if (patternOptions[i].key === key) return patternOptions[i].label
        }
        return LanguageManager.tr3("Padrao", "Default", "Predeterminado")
    }
    function ensurePatternDefaults() {
        var defaults = ["horizontal", "vertical", "dots"]
        var next = []
        for (var i = 0; i < 3; i++) {
            var p = (fieldPatterns && fieldPatterns.length > i) ? String(fieldPatterns[i] || "") : ""
            next.push(p !== "" ? p : defaults[i])
        }
        fieldPatterns = next
    }
    function openPatternPicker(fieldIdx, fieldItem) {
        editingFieldIdx = fieldIdx
        var pt = fieldItem.mapToItem(root, fieldItem.width / 2, fieldItem.height / 2)
        patternPopup.x = Math.max(8, Math.min(root.width - patternPopup.width - 8, pt.x - patternPopup.width / 2))
        patternPopup.y = Math.max(8, Math.min(root.height - patternPopup.height - 8, pt.y - patternPopup.height / 2))
        patternPopup.open()
    }

    onContextForcedChanged: {
        if (contextForced) selectedContext = "Padrão"
        ensurePatternDefaults()
    }
    onSelectedNumCamposChanged: ensurePatternDefaults()
    Component.onCompleted: ensurePatternDefaults()

    Rectangle { anchors.fill: parent; color: ThemeManager.background; Behavior on color { ColorAnimation { duration: 200 } } }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 40
        spacing: 0

        // â”€â”€ Header â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        RowLayout {
            Layout.fillWidth: true; spacing: 10

            GhostButton { text: LanguageManager.tr3("<- Voltar", "<- Back", "<- Volver"); onClicked: root.backRequested() }
            Item { width: 8 }
            Text { text: "\uD83C\uDFA8"; font.pixelSize: 28; color: "#ab3d4c" }

            ColumnLayout {
                spacing: 2
                Text {
                text: LanguageManager.tr3("Reconhecimento de Objetos", "Object Recognition", "Reconocimiento de Objetos")
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

        // â”€â”€ Corpo â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 32

            // â”€â”€ Preview dinÃ¢mico â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

                        // Modelo para os 3 campos possÃ­veis
                        property var fieldDefs: [
                            { cx: 0,             cy: 0,             active: root.selectedNumCampos >= 1 },
                            { cx: cellW + 6,     cy: 0,             active: root.selectedNumCampos >= 2 },
                            { cx: 0,             cy: cellH + 6,     active: root.selectedNumCampos >= 3 }
                        ]

                        // Campo 1 (topo-esq)
                        Rectangle {
                            x: 0; y: 0
                            width: grid.cellW; height: grid.cellH
                            property int fieldIndex: 0
                            property color contextWallColor: "#ab3d4c"
                            radius: 6
                            color: grid.fieldDefs[0].active ? "#0d0d22" : "#0a0a18"
                            border.color: grid.fieldDefs[0].active ? "#ab3d4c" : "#1a1a2e"
                            border.width: 1; clip: true
                            Behavior on color { ColorAnimation { duration: 200 } }
                            Behavior on border.color { ColorAnimation { duration: 200 } }

                            Rectangle { anchors { top: parent.top; left: parent.left; right: parent.right }
                                        height: 4; color: parent.contextWallColor; opacity: 0.85
                                        visible: grid.ctx && grid.fieldDefs[0].active }
                            Rectangle { anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                                        height: 4; color: parent.contextWallColor; opacity: 0.85
                                        visible: grid.ctx && grid.fieldDefs[0].active }
                            Rectangle { anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                                        width: 4; color: parent.contextWallColor; opacity: 0.85
                                        visible: grid.ctx && grid.fieldDefs[0].active }
                            Rectangle { anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                                        width: 4; color: parent.contextWallColor; opacity: 0.85
                                        visible: grid.ctx && grid.fieldDefs[0].active }

                            Text {
                                anchors.centerIn: parent
                                text: grid.fieldDefs[0].active ? LanguageManager.tr3("Campo 1", "Field 1", "Campo 1") : "-"
                                color: grid.fieldDefs[0].active ? "#ab3d4c" : "#1a1a2e"
                                font.pixelSize: Math.max(8, parent.width * 0.13)
                                font.weight: Font.Bold
                                Behavior on color { ColorAnimation { duration: 200 } }
                            }
                            Text {
                                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 8 }
                                visible: grid.ctx && grid.fieldDefs[0].active
                                text: root.patternLabel(root.fieldPatterns[parent.fieldIndex])
                                color: ThemeManager.textSecondary
                                font.pixelSize: 9
                            }
                            MouseArea {
                                anchors.fill: parent
                                enabled: grid.fieldDefs[0].active && !root.contextForced
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.selectedContext !== "Contextual") root.selectedContext = "Contextual"
                                    root.openPatternPicker(parent.fieldIndex, parent)
                                }
                            }
                        }

                        // Campo 2 (topo-dir)
                        Rectangle {
                            x: grid.cellW + 6; y: 0
                            width: grid.cellW; height: grid.cellH
                            property int fieldIndex: 1
                            property color contextWallColor: "#3d7aab"
                            radius: 6
                            color: grid.fieldDefs[1].active ? "#0d0d22" : "#0a0a18"
                            border.color: grid.fieldDefs[1].active ? "#ab3d4c" : "#1a1a2e"
                            border.width: 1; clip: true
                            Behavior on color { ColorAnimation { duration: 200 } }
                            Behavior on border.color { ColorAnimation { duration: 200 } }

                            Rectangle { anchors { top: parent.top; left: parent.left; right: parent.right }
                                        height: 4; color: parent.contextWallColor; opacity: 0.85
                                        visible: grid.ctx && grid.fieldDefs[1].active }
                            Rectangle { anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                                        height: 4; color: parent.contextWallColor; opacity: 0.85
                                        visible: grid.ctx && grid.fieldDefs[1].active }
                            Rectangle { anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                                        width: 4; color: parent.contextWallColor; opacity: 0.85
                                        visible: grid.ctx && grid.fieldDefs[1].active }
                            Rectangle { anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                                        width: 4; color: parent.contextWallColor; opacity: 0.85
                                        visible: grid.ctx && grid.fieldDefs[1].active }

                            Text {
                                anchors.centerIn: parent
                                text: grid.fieldDefs[1].active ? LanguageManager.tr3("Campo 2", "Field 2", "Campo 2") : "-"
                                color: grid.fieldDefs[1].active ? "#ab3d4c" : "#1a1a2e"
                                font.pixelSize: Math.max(8, parent.width * 0.13)
                                font.weight: Font.Bold
                                Behavior on color { ColorAnimation { duration: 200 } }
                            }
                            Text {
                                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 8 }
                                visible: grid.ctx && grid.fieldDefs[1].active
                                text: root.patternLabel(root.fieldPatterns[parent.fieldIndex])
                                color: ThemeManager.textSecondary
                                font.pixelSize: 9
                            }
                            MouseArea {
                                anchors.fill: parent
                                enabled: grid.fieldDefs[1].active && !root.contextForced
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.selectedContext !== "Contextual") root.selectedContext = "Contextual"
                                    root.openPatternPicker(parent.fieldIndex, parent)
                                }
                            }
                        }

                        // Campo 3 (baixo-esq)
                        Rectangle {
                            x: 0; y: grid.cellH + 6
                            width: grid.cellW; height: grid.cellH
                            property int fieldIndex: 2
                            property color contextWallColor: "#6aab3d"
                            radius: 6
                            color: grid.fieldDefs[2].active ? "#0d0d22" : "#0a0a18"
                            border.color: grid.fieldDefs[2].active ? "#ab3d4c" : "#1a1a2e"
                            border.width: 1; clip: true
                            Behavior on color { ColorAnimation { duration: 200 } }
                            Behavior on border.color { ColorAnimation { duration: 200 } }

                            Rectangle { anchors { top: parent.top; left: parent.left; right: parent.right }
                                        height: 4; color: parent.contextWallColor; opacity: 0.85
                                        visible: grid.ctx && grid.fieldDefs[2].active }
                            Rectangle { anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                                        height: 4; color: parent.contextWallColor; opacity: 0.85
                                        visible: grid.ctx && grid.fieldDefs[2].active }
                            Rectangle { anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                                        width: 4; color: parent.contextWallColor; opacity: 0.85
                                        visible: grid.ctx && grid.fieldDefs[2].active }
                            Rectangle { anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                                        width: 4; color: parent.contextWallColor; opacity: 0.85
                                        visible: grid.ctx && grid.fieldDefs[2].active }

                            Text {
                                anchors.centerIn: parent
                                text: grid.fieldDefs[2].active ? LanguageManager.tr3("Campo 3", "Field 3", "Campo 3") : "-"
                                color: grid.fieldDefs[2].active ? "#ab3d4c" : "#1a1a2e"
                                font.pixelSize: Math.max(8, parent.width * 0.13)
                                font.weight: Font.Bold
                                Behavior on color { ColorAnimation { duration: 200 } }
                            }
                            Text {
                                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 8 }
                                visible: grid.ctx && grid.fieldDefs[2].active
                                text: root.patternLabel(root.fieldPatterns[parent.fieldIndex])
                                color: ThemeManager.textSecondary
                                font.pixelSize: 9
                            }
                            MouseArea {
                                anchors.fill: parent
                                enabled: grid.fieldDefs[2].active && !root.contextForced
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.selectedContext !== "Contextual") root.selectedContext = "Contextual"
                                    root.openPatternPicker(parent.fieldIndex, parent)
                                }
                            }
                        }

                        // CÃ©lula inferior-dir: sempre inativa
                        Rectangle {
                            x: grid.cellW + 6; y: grid.cellH + 6
                            width: grid.cellW; height: grid.cellH
                            radius: 6; color: "#0a0a18"
                            border.color: "#1a1a2e"; border.width: 1
                            Text {
                                anchors.centerIn: parent; text: "-"; color: "#1a1a2e"
                                font.pixelSize: Math.max(10, parent.width * 0.15); font.weight: Font.Bold
                            }
                        }
                    }
                }
            }

            // â”€â”€ Painel de opÃ§Ãµes â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            ColumnLayout {
                Layout.fillHeight: true
                Layout.preferredWidth: 280
                spacing: 24

                // â”€â”€ NÃºmero de campos â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Text {
                        text: LanguageManager.tr3("LAYOUT DE CAMPOS", "FIELD LAYOUT", "DISENO DE CAMPOS")
                        color: "#8888aa"; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.5
                    }

                    Repeater {
                        model: [
                            { n: 2, label: LanguageManager.tr3("2 Campos", "2 Fields", "2 Campos"), desc: LanguageManager.tr3("Dois campos - contexto selecionavel", "Two fields - selectable context", "Dos campos - contexto seleccionable") },
                            { n: 3, label: LanguageManager.tr3("3 Campos", "3 Fields", "3 Campos"), desc: LanguageManager.tr3("Tres campos - sem contexto", "Three fields - no context", "Tres campos - sin contexto") }
                        ]
                        delegate: Rectangle {
                            Layout.fillWidth: true; height: 56; radius: 10
                            property bool isSelected: root.selectedNumCampos === modelData.n
                            color: isSelected ? ThemeManager.accentDim : (ma.containsMouse ? ThemeManager.surfaceHover : ThemeManager.surfaceDim)
                            border.color: isSelected ? ThemeManager.accent : ThemeManager.border; border.width: isSelected ? 2 : 1
                            Behavior on color        { ColorAnimation { duration: 150 } }
                            Behavior on border.color { ColorAnimation { duration: 150 } }

                            ColumnLayout {
                                anchors { fill: parent; leftMargin: 14; rightMargin: 14; topMargin: 10; bottomMargin: 10 }
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
                                id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: root.selectedNumCampos = modelData.n
                            }
                        }
                    }
                }

                // Contexto (apenas para 2 campos)
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 10
                    opacity: root.contextForced ? 0.35 : 1.0
                    Behavior on opacity { NumberAnimation { duration: 200 } }

                    Text {
                        text: LanguageManager.tr3("CONTEXTO", "CONTEXT", "CONTEXTO")
                        color: ThemeManager.textSecondary; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.5
                    }

                    Rectangle {
                        Layout.fillWidth: true; height: 48; radius: 10
                        property bool isSelected: root.resolvedContext === "PadrÃ£o"
                        color: isSelected ? ThemeManager.accentDim : (std2.containsMouse && !root.contextForced ? ThemeManager.surfaceHover : ThemeManager.surfaceDim)
                        border.color: isSelected ? ThemeManager.accent : ThemeManager.border; border.width: isSelected ? 2 : 1
                        Behavior on color        { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                        Text {
                            anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                            text: LanguageManager.tr3("Sem contexto (Padrao)", "No context (Default)", "Sin contexto (Predeterminado)")
                            color: parent.isSelected ? ThemeManager.textPrimary : ThemeManager.textSecondary
                            font.pixelSize: 13; font.weight: Font.Bold
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                        MouseArea {
                            id: std2; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            enabled: !root.contextForced
                            onClicked: root.selectedContext = "PadrÃ£o"
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true; height: 48; radius: 10
                        property bool isSelected: root.resolvedContext === "Contextual"
                        color: isSelected ? ThemeManager.accentDim : (ctx2.containsMouse && !root.contextForced ? ThemeManager.surfaceHover : ThemeManager.surfaceDim)
                        border.color: isSelected ? ThemeManager.accent : ThemeManager.border; border.width: isSelected ? 2 : 1
                        Behavior on color        { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                        Text {
                            anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                            text: LanguageManager.tr3("Com contexto (Contextual)", "With context (Contextual)", "Con contexto (Contextual)")
                            color: parent.isSelected ? ThemeManager.textPrimary : ThemeManager.textSecondary
                            font.pixelSize: 13; font.weight: Font.Bold
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                        MouseArea {
                            id: ctx2; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            enabled: !root.contextForced
                            onClicked: root.selectedContext = "Contextual"
                        }
                    }

                    Text {
                        visible: root.contextForced
                        text: LanguageManager.tr3("Contexto fixo em Padrao para 3 campos", "Context fixed as Default for 3 fields", "Contexto fijo en Predeterminado para 3 campos")
                        color: ThemeManager.textTertiary; font.pixelSize: 10; font.italic: true
                    }
                }

                Item { Layout.fillHeight: true }
            }
        }

        Item { Layout.fillHeight: true; Layout.minimumHeight: 16 }

        // â”€â”€ RodapÃ© â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        RowLayout {
            Layout.alignment: Qt.AlignHCenter; spacing: 24

            Text { text: LanguageManager.tr3("Passo 2 - Campos e Contexto", "Step 2 - Fields and Context", "Paso 2 - Campos y Contexto"); color: ThemeManager.textSecondary; font.pixelSize: 11 }

            Button {
                text: LanguageManager.tr3("Proximo ->", "Next ->", "Siguiente ->")
                onClicked: root.selectionConfirmed(root.selectedNumCampos, root.resolvedContext, root.selectedArenaId, root.fieldPatterns.slice(0, root.selectedNumCampos))

                background: Rectangle {
                    radius: 8; color: parent.hovered ? "#8a2e3b" : "#ab3d4c"
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

    Popup {
        id: patternPopup
        modal: false
        focus: true
        width: 230
        height: patternList.implicitHeight + 16
        padding: 8
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle {
            radius: 10
            color: ThemeManager.surface
            border.color: "#ab3d4c"
            border.width: 1
        }
        ListView {
            id: patternList
            anchors.fill: parent
            clip: true
            model: root.patternOptions
            implicitHeight: contentHeight
            interactive: false
            delegate: Rectangle {
                width: patternList.width
                height: 30
                radius: 6
                property bool isSelected: root.editingFieldIdx >= 0
                                          && root.fieldPatterns[root.editingFieldIdx] === modelData.key
                color: isSelected ? ThemeManager.accentDim : (pm.containsMouse ? ThemeManager.surfaceHover : "transparent")
                Text {
                    anchors.centerIn: parent
                    text: modelData.label
                    color: ThemeManager.textPrimary
                    font.pixelSize: 12
                }
                MouseArea {
                    id: pm
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.editingFieldIdx >= 0) {
                            var arr = root.fieldPatterns.slice()
                            arr[root.editingFieldIdx] = modelData.key
                            root.fieldPatterns = arr
                        }
                        patternPopup.close()
                    }
                }
            }
        }
    }
}

