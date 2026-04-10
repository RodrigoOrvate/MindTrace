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
                        color: ThemeManager.textPrimary; placeholderTextColor: ThemeManager.textSecondary; font.pixelSize: 13
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
                            property bool isHovered: mainArea.containsMouse
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

                            // Botão Excluir (lixeira)
                            Rectangle {
                                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                width: 32; height: 32; radius: 16
                                color: deleteMa.containsMouse ? ThemeManager.errorDim : "transparent"
                                visible: expDelegate.isHovered || expDelegate.isSelected
                                Behavior on color { ColorAnimation { duration: 150 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: "🗑"
                                    font.pixelSize: 14; color: deleteMa.containsMouse ? ThemeManager.error : ThemeManager.textTertiary
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }

                                MouseArea {
                                    id: deleteMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        deleteConfirmPopup.targetName = model.name
                                        deleteConfirmPopup.targetPath = model.path
                                        deleteConfirmPopup.open()
                                    }
                                }
                            }

                            MouseArea {
                                id: mainArea
                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    experimentList.currentIndex = index
                                    var path = model.path
                                    var meta = ExperimentManager.readMetadataFromPath(path)
                                    previewName.text    = model.name
                                    previewContext.text = model.context
                                    previewAparato.text = (meta.aparato || "nor") === "campo_aberto" ? "🐀 Campo Aberto" : "🧠 Rec. de Objetos"
                                    previewCampos.text  = (meta.numCampos || 3) + " campo(s)"
                                    previewContainer.previewAparatoVal   = meta.aparato || "nor"
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

    // ── Popup de Confirmação de Exclusão ──────────────────────────────────
    Popup {
        id: deleteConfirmPopup
        anchors.centerIn: parent
        width: 320; height: 180; modal: true; focus: true
        padding: 0
        
        property string targetName: ""
        property string targetPath: ""

        background: Rectangle {
            color: ThemeManager.surface; radius: 12
            border.color: ThemeManager.border; border.width: 1
            layer.enabled: true
            Behavior on color { ColorAnimation { duration: 200 } }
        }

        ColumnLayout {
            anchors { fill: parent; margins: 20 }
            spacing: 16

            Text {
                text: "Confirmar Exclusão"
                color: ThemeManager.textPrimary; font.pixelSize: 16; font.weight: Font.Bold
                Layout.alignment: Qt.AlignHCenter
            }

            Text {
                text: "Deseja realmente excluir o experimento\n<b>" + deleteConfirmPopup.targetName + "</b>?\nEsta ação não pode ser desfeita."
                color: ThemeManager.textSecondary; font.pixelSize: 12; horizontalAlignment: Text.AlignHCenter
                Layout.fillWidth: true; wrapMode: Text.WordWrap; Layout.alignment: Qt.AlignHCenter
            }

            RowLayout {
                Layout.fillWidth: true; spacing: 12; Layout.topMargin: 8

                GhostButton {
                    text: "Cancelar"
                    Layout.fillWidth: true
                    onClicked: deleteConfirmPopup.close()
                }

                Button {
                    text: "Excluir"
                    Layout.fillWidth: true; Layout.preferredHeight: 36
                    onClicked: {
                        ExperimentManager.deleteExperiment(deleteConfirmPopup.targetName)
                        deleteConfirmPopup.close()
                        previewPanel.visible = false
                    }
                    background: Rectangle {
                        radius: 8; color: parent.hovered ? ThemeManager.errorHover : ThemeManager.error
                    }
                    contentItem: Text {
                        text: parent.text; color: "white"; font.pixelSize: 12; font.weight: Font.Bold
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }
    }
}
