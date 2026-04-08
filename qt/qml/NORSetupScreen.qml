// qml/NORSetupScreen.qml
// Setup do experimento NOR: nome + pares de objetos por campo + checkbox Droga.
// Emite experimentReady(name, cols) para o roteador criar o experimento.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MindTrace.Backend 1.0

Item {
    id: root

    property string context: ""
    property string arenaId: ""

    // name, cols, par por campo, flag droga
    signal experimentReady(string name, var cols, string pair1, string pair2, string pair3, bool includeDrug)
    signal backRequested()

    // Par selecionado por campo — string de 2 letras (ex.: "AB", "AA") ou "" se não definido.
    property string campo1Id: camposMulti.pair1
    property string campo2Id: camposMulti.pair2
    property string campo3Id: camposMulti.pair3

    property bool allPairsSelected: campo1Id.length === 2
                                  && campo2Id.length === 2
                                  && campo3Id.length === 2

    function doCreate() {
        var cols = ["Diretório do Vídeo", "Animal", "Campo", "Dia", "Par de Objetos"]
        if (drugCheck.checked) cols.push("Droga")
        root.experimentReady(nameField.text.trim(), cols,
                             campo1Id, campo2Id, campo3Id, drugCheck.checked)
    }

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
                    text: "Configuração do Experimento"
                    color: "#e8e8f0"; font.pixelSize: 22; font.weight: Font.Bold
                }
                Text {
                    text: root.context !== "" ? "NOR " + root.context + "  ·  " + root.arenaId
                                              : "Reconhecimento de Objetos"
                    color: "#8888aa"; font.pixelSize: 13
                }
            }
        }

        Rectangle { Layout.fillWidth: true; Layout.topMargin: 18; height: 1; color: "#2d2d4a" }

        Item { Layout.fillHeight: true; Layout.minimumHeight: 24 }

        // ── Formulário central ────────────────────────────────────────────
        ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
            spacing: 24

            // Nome
            ColumnLayout {
                Layout.fillWidth: true; spacing: 8
                Text {
                    text: "NOME DO EXPERIMENTO"
                    color: "#8888aa"; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.5
                }
                TextField {
                    id: nameField
                    Layout.fillWidth: true
                    placeholderText: "Ex.: Controle_Grupo_A"
                    color: "#e8e8f0"; placeholderTextColor: "#8888aa"; font.pixelSize: 14
                    leftPadding: 14; rightPadding: 14; topPadding: 10; bottomPadding: 10
                    background: Rectangle {
                        radius: 8; color: "#12122a"
                        border.color: nameField.activeFocus ? "#ab3d4c" : "#3a3a5c"; border.width: 1
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: "#2d2d4a" }

            // Pares por campo
            ColumnLayout {
                Layout.fillWidth: true; spacing: 12
                Text {
                    text: "PAR DE OBJETOS POR CAMPO"
                    color: "#8888aa"; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.5
                }
                Text {
                    text: "Selecione um par para cada campo do laboratório."
                    color: "#555577"; font.pixelSize: 11
                }

                RowLayout {
                    Layout.fillWidth: true; spacing: 16

                    CampoSelector {
                    id: camposMulti
                    Layout.fillWidth: true
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: "#2d2d4a" }

            // Checkbox Droga
            RowLayout {
                spacing: 12

                Rectangle {
                    id: drugCheck
                    width: 20; height: 20; radius: 5
                    property bool checked: true
                    color:        checked ? "#ab3d4c" : "#12122a"
                    border.color: checked ? "#ab3d4c" : "#3a3a5c"; border.width: 1.5
                    Behavior on color        { ColorAnimation { duration: 150 } }
                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent; text: "✓"
                        color: "#e8e8f0"; font.pixelSize: 11; font.weight: Font.Bold
                        visible: drugCheck.checked
                    }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: drugCheck.checked = !drugCheck.checked
                    }
                }

                ColumnLayout {
                    spacing: 2
                    Text {
                        text: "Incluir coluna \"Droga\""
                        color: "#e8e8f0"; font.pixelSize: 13; font.weight: Font.Bold
                    }
                    Text {
                        text: "Desmarque se o experimento não utilizar tratamento farmacológico."
                        color: "#555577"; font.pixelSize: 11
                    }
                }
            }
        }

        Item { Layout.fillHeight: true; Layout.minimumHeight: 24 }

        // ── Rodapé + botão ────────────────────────────────────────────────
        RowLayout {
            Layout.alignment: Qt.AlignHCenter; spacing: 24

            Text {
                text: "Passo 3  —  Configuração do Experimento"
                color: "#8888aa"; font.pixelSize: 11
            }

            Button {
                text: "Criar Experimento →"
                enabled: nameField.text.trim().length > 0 && root.allPairsSelected

                onClicked: {
                    if (ExperimentManager.experimentExists(root.context, nameField.text.trim())) {
                        dupStep1Popup.open()
                    } else {
                        root.doCreate()
                    }
                }

                background: Rectangle {
                    radius: 8
                    color: parent.enabled ? (parent.hovered ? "#8a2e3b" : "#ab3d4c") : "#2d2d4a"
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

    // ── Popup duplicado — Passo 1: aviso ─────────────────────────────────────
    Popup {
        id: dupStep1Popup
        anchors.centerIn: parent
        width: 400; height: 200
        modal: true; focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle {
            radius: 14; color: "#1a1a2e"
            border.color: "#ab3d4c"; border.width: 1
        }

        ColumnLayout {
            anchors { fill: parent; margins: 24 }
            spacing: 14

            Text {
                text: "Experimento já existe"
                color: "#e8e8f0"; font.pixelSize: 16; font.weight: Font.Bold
            }

            Text {
                Layout.fillWidth: true
                text: "\"" + nameField.text.trim() + "\" já existe neste contexto.\n\nSe continuar, os dados anteriores serão substituídos."
                color: "#8888aa"; font.pixelSize: 13; wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true; spacing: 10
                Item { Layout.fillWidth: true }
                GhostButton { text: "Cancelar"; onClicked: dupStep1Popup.close() }
                Button {
                    text: "Continuar"
                    onClicked: {
                        dupStep1Popup.close()
                        dupConfirmField.text = ""
                        dupStep2Popup.open()
                    }
                    background: Rectangle {
                        radius: 7; color: parent.hovered ? "#8a2e3b" : "#ab3d4c"
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                    contentItem: Text {
                        text: parent.text; color: "#e8e8f0"; font.pixelSize: 12; font.weight: Font.Bold
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                    leftPadding: 16; rightPadding: 16; topPadding: 8; bottomPadding: 8
                }
            }
        }
    }

    // ── Popup duplicado — Passo 2: confirmar digitando o nome ────────────────
    Popup {
        id: dupStep2Popup
        anchors.centerIn: parent
        width: 420; height: 230
        modal: true; focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onOpened: dupConfirmField.forceActiveFocus()

        background: Rectangle {
            radius: 14; color: "#1a1a2e"
            border.color: "#ab3d4c"; border.width: 1
        }

        ColumnLayout {
            anchors { fill: parent; margins: 24 }
            spacing: 14

            Text {
                text: "Confirmar Substituição"
                color: "#e8e8f0"; font.pixelSize: 16; font.weight: Font.Bold
            }

            Text {
                Layout.fillWidth: true
                text: "Digite o nome do experimento para confirmar a substituição:"
                color: "#8888aa"; font.pixelSize: 13; wrapMode: Text.WordWrap
            }

            TextField {
                id: dupConfirmField
                Layout.fillWidth: true
                placeholderText: nameField.text.trim()
                color: "#e8e8f0"; placeholderTextColor: "#444466"; font.pixelSize: 13
                leftPadding: 10; rightPadding: 10; topPadding: 8; bottomPadding: 8
                background: Rectangle {
                    radius: 6; color: "#12122a"
                    border.color: dupConfirmField.activeFocus ? "#ab3d4c" : "#3a3a5c"; border.width: 1
                    Behavior on border.color { ColorAnimation { duration: 150 } }
                }
                Keys.onReturnPressed: {
                    if (text === nameField.text.trim()) {
                        dupStep2Popup.close(); root.doCreate()
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true; spacing: 10
                Item { Layout.fillWidth: true }
                GhostButton { text: "Cancelar"; onClicked: dupStep2Popup.close() }
                Button {
                    text: "Substituir"
                    enabled: dupConfirmField.text === nameField.text.trim()
                    onClicked: { dupStep2Popup.close(); root.doCreate() }
                    background: Rectangle {
                        radius: 7
                        color: parent.enabled ? (parent.hovered ? "#8a2e3b" : "#ab3d4c") : "#2d2d4a"
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                    contentItem: Text {
                        text: parent.text; color: "#e8e8f0"; font.pixelSize: 12; font.weight: Font.Bold
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                    leftPadding: 16; rightPadding: 16; topPadding: 8; bottomPadding: 8
                }
            }
        }
    }
}
