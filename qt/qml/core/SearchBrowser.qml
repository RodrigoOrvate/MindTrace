// qml/core/SearchBrowser.qml
// Browser universal de experimentos — agrupa NOR e Campo Aberto.
// Ao selecionar um experimento emite openExperiment(aparato, numCampos, name, path)
// para que main.qml roteie ao dashboard correto.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "Theme"
import MindTrace.Backend 1.0

Item {
    id: root

    property string aparatoFilter: ""
    property string pendingDeleteName: ""
    property string pendingDeleteContext: ""

    signal backRequested()
    signal openExperiment(string aparato, int numCampos, string expName, string expPath)

    onVisibleChanged: {
        if (visible) {
            ExperimentManager.clearFilter()
            ExperimentManager.loadAllContexts(root.aparatoFilter)
        }
    }

    Component.onCompleted: {
        ExperimentManager.clearFilter()
        ExperimentManager.loadAllContexts(root.aparatoFilter)
    }

    Rectangle { anchors.fill: parent; color: ThemeManager.background; Behavior on color { ColorAnimation { duration: 200 } } }

    // ── Barra superior ───────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

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

                GhostButton { text: "← Voltar"; onClicked: root.backRequested() }

                Text { text: "🔍"; font.pixelSize: 20 }

                Text {
                    text: "Todos os Experimentos"
                    color: ThemeManager.textPrimary; font.pixelSize: 16; font.weight: Font.Bold
                    Behavior on color { ColorAnimation { duration: 150 } }
                }

                Item { Layout.fillWidth: true }
            }
        }

        // ── Corpo: sidebar + preview ─────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // ── Sidebar ──────────────────────────────────────────────────
            Rectangle {
                width: 300; Layout.fillHeight: true
                color: ThemeManager.surface; Behavior on color { ColorAnimation { duration: 200 } }

                Rectangle {
                    anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
                    width: 1; color: ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } }
                }

                ColumnLayout {
                    anchors { fill: parent; margins: 12 }
                    spacing: 8

                    Text {
                        text: "Experimentos"
                        color: ThemeManager.textPrimary; font.pixelSize: 12; font.weight: Font.Bold
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    TextField {
                        id: searchField
                        Layout.fillWidth: true
                        placeholderText: "Pesquisar…"
                        color: ThemeManager.textPrimary; font.pixelSize: 13
                        leftPadding: 10; rightPadding: 10; topPadding: 6; bottomPadding: 6
                        background: Rectangle {
                            radius: 6; color: ThemeManager.surfaceDim; Behavior on color { ColorAnimation { duration: 200 } }
                            border.color: searchField.activeFocus ? ThemeManager.accent : ThemeManager.borderLight; border.width: 1
                            Behavior on border.color { ColorAnimation { duration: 150 } }
                        }
                        onTextChanged: ExperimentManager.setFilter(text)
                    }

                    ListView {
                        id: experimentList
                        Layout.fillWidth: true; Layout.fillHeight: true
                        clip: true; model: ExperimentManager.model; currentIndex: -1

                        ScrollBar.vertical: ScrollBar {
                            policy: ScrollBar.AsNeeded
                            contentItem: Rectangle { implicitWidth: 4; radius: 2; color: ThemeManager.borderLight; Behavior on color { ColorAnimation { duration: 200 } } }
                        }

                        delegate: Rectangle {
                            id: expDelegate
                            width: experimentList.width; height: 48
                            property bool isSelected: experimentList.currentIndex === index
                            property bool isHovered: mainArea.containsMouse || deleteMa.containsMouse
                            color: isSelected ? ThemeManager.accentDim : (isHovered ? ThemeManager.surfaceAlt : "transparent")
                            Behavior on color { ColorAnimation { duration: 120 } }

                            ColumnLayout {
                                anchors {
                                    left: parent.left; leftMargin: 12
                                    right: parent.right; rightMargin: 12
                                    verticalCenter: parent.verticalCenter
                                }
                                spacing: 2

                                Text {
                                    Layout.fillWidth: true
                                    text: model.name
                                    color: expDelegate.isSelected ? ThemeManager.textPrimary : ThemeManager.textSecondary
                                    font.pixelSize: 13; font.weight: Font.Bold; elide: Text.ElideRight
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: model.context
                                    color: ThemeManager.textTertiary; font.pixelSize: 10; elide: Text.ElideRight
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }
                            }

                            Rectangle {
                                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                height: 1; color: ThemeManager.border; opacity: 0.5
                                Behavior on color { ColorAnimation { duration: 200 } }
                            }

                            // Botão Excluir (lixeira) - sempre visível
                            Rectangle {
                                id: deleteBtn
                                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                width: 32; height: 32; radius: 16
                                color: deleteMa.containsMouse ? ThemeManager.errorDim : "transparent"
                                opacity: expDelegate.isHovered ? 1.0 : 0.0
                                visible: true
                                Behavior on color   { ColorAnimation { duration: 150 } }
                                Behavior on opacity { NumberAnimation { duration: 150 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: "🗑"
                                    font.pixelSize: 14; color: deleteMa.containsMouse ? ThemeManager.error : ThemeManager.textTertiary
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }
                            }

                            MouseArea {
                                id: deleteMa
                                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                width: 32; height: 32
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.pendingDeleteName = model.name
                                    root.pendingDeleteContext = model.context
                                    deleteStep1Popup.open()
                                }
                            }

                            MouseArea {
                                id: mainArea
                                anchors { fill: parent; rightMargin: 48 }
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    experimentList.currentIndex = index
                                    var path = model.path
                                    var meta = ExperimentManager.readMetadataFromPath(path)
                                    var appType = meta.aparato || "nor"
                                    previewName.text    = model.name
                                    previewContext.text = model.context
                                    previewAparato.text = appType === "comportamento_complexo" ? "🧩 Comp. Complexo"
                                                          : appType === "campo_aberto"          ? "🐀 Campo Aberto"
                                                          : appType === "esquiva_inibitoria"    ? "⚡ Esquiva Inibitória"
                                                          :                                       "🧠 Rec. de Objetos"
                                    previewCampos.text  = (meta.numCampos || 3) + " campo(s)"
                                    previewContainer.previewAparatoVal   = appType
                                    previewContainer.previewNumCamposVal = meta.numCampos || 3
                                    previewContainer.previewPathVal      = path
                                    previewPanel.visible = true
                                }
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: experimentList.count === 0
                            text: "Nenhum experimento\nencontrado"
                            color: ThemeManager.textSecondary; font.pixelSize: 12
                            horizontalAlignment: Text.AlignHCenter
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                    }
                }
            }

            // ── Painel de preview / abertura ──────────────────────────────
            Item {
                id: previewContainer
                Layout.fillWidth: true; Layout.fillHeight: true

                // Valores temporários para o experimento selecionado
                property string previewAparatoVal:   "nor"
                property int    previewNumCamposVal: 3
                property string previewPathVal:      ""

                // Placeholder
                ColumnLayout {
                    anchors.centerIn: parent; spacing: 12
                    visible: !previewPanel.visible

                    Text { Layout.alignment: Qt.AlignHCenter; text: "🔍"; font.pixelSize: 48; opacity: 0.3 }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "Selecione um experimento\nna barra lateral"
                        color: ThemeManager.textSecondary; font.pixelSize: 14
                        horizontalAlignment: Text.AlignHCenter
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                }

                // Card de preview
                Rectangle {
                    id: previewPanel
                    visible: false
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 80, 480); height: 260
                    radius: 16; color: ThemeManager.surface
                    border.color: ThemeManager.border; border.width: 1
                    Behavior on color { ColorAnimation { duration: 200 } }

                    ColumnLayout {
                        anchors { fill: parent; margins: 32 }
                        spacing: 16

                        Text {
                            id: previewAparato
                            Layout.alignment: Qt.AlignHCenter
                            text: ""; font.pixelSize: 15; font.weight: Font.Bold
                            color: ThemeManager.textSecondary
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }

                        Text {
                            id: previewName
                            Layout.alignment: Qt.AlignHCenter
                            text: ""
                            color: ThemeManager.textPrimary; font.pixelSize: 22; font.weight: Font.Bold
                            wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }

                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter; spacing: 24

                            ColumnLayout {
                                spacing: 2
                                Text { Layout.alignment: Qt.AlignHCenter; text: "Contexto"; color: ThemeManager.textTertiary; font.pixelSize: 11 }
                                Text { id: previewContext; Layout.alignment: Qt.AlignHCenter; text: ""; color: ThemeManager.textSecondary; font.pixelSize: 13; font.weight: Font.Bold }
                            }

                            ColumnLayout {
                                spacing: 2
                                Text { Layout.alignment: Qt.AlignHCenter; text: "Campos"; color: ThemeManager.textTertiary; font.pixelSize: 11 }
                                Text { id: previewCampos; Layout.alignment: Qt.AlignHCenter; text: ""; color: ThemeManager.textSecondary; font.pixelSize: 13; font.weight: Font.Bold }
                            }
                        }

                        Item { Layout.fillHeight: true }

                        Button {
                            Layout.alignment: Qt.AlignHCenter
                            text: "Abrir Experimento →"
                            onClicked: {
                                root.openExperiment(
                                    previewContainer.previewAparatoVal,
                                    previewContainer.previewNumCamposVal,
                                    previewName.text,
                                    previewContainer.previewPathVal
                                )
                            }

                            background: Rectangle {
                                radius: 8
                                color: parent.hovered ? ThemeManager.accentHover : ThemeManager.accent
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }
                            contentItem: Text {
                                text: parent.text; color: ThemeManager.buttonText
                                font.pixelSize: 13; font.weight: Font.Bold
                                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                            }
                            leftPadding: 28; rightPadding: 28; topPadding: 11; bottomPadding: 11
                        }
                    }
                }
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════
    // Popup: confirmar exclusão — passo 1
    // ════════════════════════════════════════════════════════════════════
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
                text: "Tem certeza que deseja excluir\n\"" + root.pendingDeleteName + "\"?\n\nEsta ação é irreversível."
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

    // ════════════════════════════════════════════════════════════════════
    // Popup: confirmar exclusão — passo 2
    // ════════════════════════════════════════════════════════════════════
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

            Text { text: "Confirmação Final"; color: ThemeManager.textPrimary; font.pixelSize: 16; font.weight: Font.Bold; Behavior on color { ColorAnimation { duration: 150 } } }

            Text {
                Layout.fillWidth: true
                text: "Para confirmar, digite o nome do experimento:"
                color: ThemeManager.textSecondary; font.pixelSize: 13; wrapMode: Text.WordWrap; Behavior on color { ColorAnimation { duration: 150 } }
            }

            // Nome em destaque — igual ao GitHub: "Digite exatamente: NomeDoExperimento"
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
                        ExperimentManager.deleteExperiment(root.pendingDeleteName, root.pendingDeleteContext)
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
                    onClicked: {
                        deleteStep2Popup.close()
                        ExperimentManager.deleteExperiment(root.pendingDeleteName, root.pendingDeleteContext)
                        previewPanel.visible = false
                    }
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
}
