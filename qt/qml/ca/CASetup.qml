// qml/ca/CASetup.qml
// Passo 3 do fluxo CA: nome do experimento, diretório, opções e criação.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../core"
import "../core/Theme"
import QtQuick.Dialogs
import MindTrace.Backend 1.0
import "../core/dayNameUtils.js" as DayNameUtils

Item {
    id: root

    property int    numCampos: 3
    property string context:   ""
    property string arenaId:   ""
    property string selectedPath: ""

    // name, cols, includeDrug, dayNames, savePath
    signal experimentReady(string name, var cols, bool includeDrug, var dayNames, string savePath)
    signal backRequested()

    function doCreate() {
        var cols = ["Diretório do Vídeo", "Animal", "Campo", "Dia",
                    "Distância Total (m)", "Velocidade Média (m/s)"]
        if (drugCheck.checked) cols.push("Tratamento")
        var names = []
        for (var i = 0; i < dayNamesModel.count; i++) names.push(dayNamesModel.get(i).dayName)
        root.experimentReady(nameField.text.trim(), cols, drugCheck.checked, names, root.selectedPath)
    }

    FolderDialog {
        id: folderDialog
        title: "Escolha a Pasta Raiz do Experimento"
        onAccepted: root.selectedPath = folderDialog.selectedFolder.toString()
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
            Text { text: "🐀"; font.pixelSize: 28; color: "#3d7aab" }

            ColumnLayout {
                spacing: 2
                Text {
                    text: "Configuração do Experimento"
                    color: ThemeManager.textPrimary
                    Behavior on color { ColorAnimation { duration: 150 } }
                    font.pixelSize: 22; font.weight: Font.Bold
                }
                Text {
                    text: "Campo Aberto  ·  " + root.numCampos + " campo" + (root.numCampos > 1 ? "s" : "") +
                          (root.context !== "" && root.context !== "Padrão" ? "  ·  " + root.context : "")
                    color: ThemeManager.textSecondary
                    Behavior on color { ColorAnimation { duration: 150 } }
                    font.pixelSize: 13
                }
            }
        }

        Rectangle { Layout.fillWidth: true; Layout.topMargin: 18; height: 1; color: ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } } }

        Item { Layout.fillHeight: true; Layout.minimumHeight: 24 }

        // ── Formulário ───────────────────────────────────────────────────
        ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
            spacing: 24

            // Nome + Diretório
            RowLayout {
                Layout.fillWidth: true; spacing: 16

                ColumnLayout {
                    Layout.fillWidth: true; spacing: 8
                    Text {
                        text: "NOME DO EXPERIMENTO"
                        color: ThemeManager.textSecondary; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.5
                    }
                    TextField {
                        id: nameField
                        Layout.fillWidth: true
                        placeholderText: "Ex.: CA_Controle_GrupoA"
                        color: ThemeManager.textPrimary; placeholderTextColor: ThemeManager.textSecondary; font.pixelSize: 14
                        leftPadding: 14; rightPadding: 14; topPadding: 10; bottomPadding: 10
                        background: Rectangle {
                            radius: 8; color: ThemeManager.surfaceDim
                            Behavior on color { ColorAnimation { duration: 200 } }
                            border.color: nameField.activeFocus ? "#3d7aab" : ThemeManager.border; border.width: 1
                            Behavior on border.color { ColorAnimation { duration: 150 } }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true; spacing: 8
                    Text {
                        text: "DIRETÓRIO RAIZ (Opcional)"
                        color: ThemeManager.textSecondary; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.5
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 6
                        TextField {
                            id: dirField
                            Layout.fillWidth: true; readOnly: true
                            text: root.selectedPath.replace("file:///", "")
                            placeholderText: "Padrão: Documentos/MindTrace_Data"
                            color: ThemeManager.textPrimary; placeholderTextColor: ThemeManager.textSecondary; font.pixelSize: 14
                            leftPadding: 14; rightPadding: 14; topPadding: 10; bottomPadding: 10
                            background: Rectangle {
                                radius: 8; color: ThemeManager.surfaceDim
                                Behavior on color { ColorAnimation { duration: 200 } }
                                border.color: ThemeManager.border; border.width: 1
                            }
                        }
                        GhostButton { text: "Procurar..."; onClicked: folderDialog.open() }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } } }

            // ── Informação de layout ──────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true; height: 48; radius: 10
                color: ThemeManager.surfaceDim
                border.color: "#3d7aab"; border.width: 1

                RowLayout {
                    anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                    spacing: 12

                    Text { text: "🐀"; font.pixelSize: 20 }

                    ColumnLayout {
                        spacing: 2
                        Text {
                            text: root.numCampos + " campo" + (root.numCampos > 1 ? "s ativos" : " ativo")
                            color: ThemeManager.textPrimary; font.pixelSize: 13; font.weight: Font.Bold
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                        Text {
                            text: "Duração: 5 min por campo  ·  Métricas: distância e velocidade"
                            color: ThemeManager.textTertiary; font.pixelSize: 11
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } } }

            // ── Tratamento + Dias ─────────────────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 16

                RowLayout {
                    spacing: 12
                    Rectangle {
                        id: drugCheck
                        width: 20; height: 20; radius: 5
                        property bool checked: true
                        color:        checked ? "#3d7aab" : ThemeManager.surfaceDim
                        border.color: checked ? "#3d7aab" : ThemeManager.border; border.width: 1.5
                        Behavior on color        { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                        Text { anchors.centerIn: parent; text: "✓"; color: ThemeManager.buttonText; font.pixelSize: 11; font.weight: Font.Bold; visible: drugCheck.checked }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: drugCheck.checked = !drugCheck.checked }
                    }
                    ColumnLayout {
                        spacing: 2
                        Text { text: "Incluir coluna \"Tratamento\""; color: ThemeManager.textPrimary; font.pixelSize: 13; font.weight: Font.Bold }
                        Text { text: "Para tratamentos farmacológicos."; color: ThemeManager.textTertiary; font.pixelSize: 11 }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: "DIAS DO EXPERIMENTO"
                        color: ThemeManager.textSecondary; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.5
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    ListModel {
                        id: dayNamesModel
                        ListElement { dayName: "Treino" }
                        ListElement { dayName: "Teste" }
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 8

                        Repeater {
                            model: dayNamesModel
                            delegate: Rectangle {
                                height: 34
                                width: Math.max(110, dayLabel.width + dayNameInput.width + removeBtn.width + 28)
                                radius: 8
                                color: ThemeManager.surfaceDim
                                border.color: ThemeManager.border; border.width: 1

                                RowLayout {
                                    anchors { fill: parent; leftMargin: 10; rightMargin: 6 }
                                    spacing: 4
                                    Text {
                                        id: dayLabel
                                        text: "Dia " + (index + 1) + ":"
                                        color: ThemeManager.textSecondary; font.pixelSize: 11
                                    }
                                    TextInput {
                                        id: dayNameInput
                                        text: model.dayName
                                        color: ThemeManager.textPrimary; font.pixelSize: 12; font.weight: Font.Bold
                                        width: Math.max(48, contentWidth + 4)
                                        selectByMouse: true
                                        onTextChanged: dayNamesModel.setProperty(index, "dayName", text)
                                        onEditingFinished: {
                                            var n = DayNameUtils.normalizeDayName(text)
                                            if (n !== text) text = n
                                        }
                                    }
                                    Item { width: 2 }
                                    Rectangle {
                                        id: removeBtn
                                        width: 16; height: 16; radius: 8
                                        color: removeHov.containsMouse ? "#c0392b" : "transparent"
                                        visible: dayNamesModel.count > 1
                                        Behavior on color { ColorAnimation { duration: 100 } }
                                        Text {
                                            anchors.centerIn: parent; text: "×"
                                            color: removeHov.containsMouse ? "white" : ThemeManager.textSecondary
                                            font.pixelSize: 13; font.weight: Font.Bold
                                        }
                                        MouseArea {
                                            id: removeHov; anchors.fill: parent
                                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: dayNamesModel.remove(index)
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            height: 34; width: 76; radius: 8
                            color: addDayHov.containsMouse ? ThemeManager.surfaceAlt : ThemeManager.surfaceDim
                            border.color: ThemeManager.border; border.width: 1
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Text { anchors.centerIn: parent; text: "+ Dia"; color: ThemeManager.textSecondary; font.pixelSize: 12 }
                            MouseArea {
                                id: addDayHov; anchors.fill: parent
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: dayNamesModel.append({ dayName: "Dia " + (dayNamesModel.count + 1) })
                            }
                        }
                    }
                }
            }
        }

        Item { Layout.fillHeight: true; Layout.minimumHeight: 24 }

        // ── Rodapé ────────────────────────────────────────────────────────
        RowLayout {
            Layout.alignment: Qt.AlignHCenter; spacing: 24

            Text { text: "Passo 3  —  Configuração do Experimento"; color: ThemeManager.textSecondary; font.pixelSize: 11 }

            Button {
                text: "Criar Experimento →"
                enabled: nameField.text.trim().length > 0

                onClicked: {
                    if (ExperimentManager.experimentExists(root.context, nameField.text.trim())) {
                        dupStep1Popup.open()
                    } else {
                        root.doCreate()
                    }
                }

                background: Rectangle {
                    radius: 8
                    color: parent.enabled ? (parent.hovered ? "#2d5f8a" : "#3d7aab") : "#2d2d4a"
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

    // ── Popup duplicado — Passo 1 ─────────────────────────────────────────
    Popup {
        id: dupStep1Popup
        anchors.centerIn: parent; width: 400; height: 200
        modal: true; focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle { radius: 14; color: ThemeManager.surface; Behavior on color { ColorAnimation { duration: 200 } } border.color: "#3d7aab"; border.width: 1 }

        ColumnLayout {
            anchors { fill: parent; margins: 24 }
            spacing: 14
            Text { text: "Experimento já existe"; color: ThemeManager.textPrimary; font.pixelSize: 16; font.weight: Font.Bold }
            Text {
                Layout.fillWidth: true
                text: "\"" + nameField.text.trim() + "\" já existe neste contexto.\n\nSe continuar, os dados anteriores serão substituídos."
                color: ThemeManager.textSecondary; font.pixelSize: 13; wrapMode: Text.WordWrap
            }
            RowLayout {
                Layout.fillWidth: true; spacing: 10; Item { Layout.fillWidth: true }
                GhostButton { text: "Cancelar"; onClicked: dupStep1Popup.close() }
                Button {
                    text: "Continuar"
                    onClicked: { dupStep1Popup.close(); dupConfirmField.text = ""; dupStep2Popup.open() }
                    background: Rectangle { radius: 7; color: parent.hovered ? "#2d5f8a" : "#3d7aab"; Behavior on color { ColorAnimation { duration: 150 } } }
                    contentItem: Text { text: parent.text; color: ThemeManager.buttonText; font.pixelSize: 12; font.weight: Font.Bold; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    leftPadding: 16; rightPadding: 16; topPadding: 8; bottomPadding: 8
                }
            }
        }
    }

    // ── Popup duplicado — Passo 2 ─────────────────────────────────────────
    Popup {
        id: dupStep2Popup
        anchors.centerIn: parent; width: 420; height: 230
        modal: true; focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onOpened: dupConfirmField.forceActiveFocus()
        background: Rectangle { radius: 14; color: ThemeManager.surface; Behavior on color { ColorAnimation { duration: 200 } } border.color: "#3d7aab"; border.width: 1 }

        ColumnLayout {
            anchors { fill: parent; margins: 24 }
            spacing: 14
            Text { text: "Confirmar Substituição"; color: ThemeManager.textPrimary; font.pixelSize: 16; font.weight: Font.Bold }
            Text { Layout.fillWidth: true; text: "Digite o nome do experimento para confirmar:"; color: ThemeManager.textSecondary; font.pixelSize: 13; wrapMode: Text.WordWrap }
            TextField {
                id: dupConfirmField; Layout.fillWidth: true
                placeholderText: nameField.text.trim()
                color: ThemeManager.textPrimary; placeholderTextColor: ThemeManager.textSecondary; font.pixelSize: 13
                leftPadding: 10; rightPadding: 10; topPadding: 8; bottomPadding: 8
                background: Rectangle { radius: 6; color: ThemeManager.surfaceDim; Behavior on color { ColorAnimation { duration: 200 } } border.color: dupConfirmField.activeFocus ? "#3d7aab" : ThemeManager.border; border.width: 1; Behavior on border.color { ColorAnimation { duration: 150 } } }
                Keys.onReturnPressed: { if (text === nameField.text.trim()) { dupStep2Popup.close(); root.doCreate() } }
            }
            RowLayout {
                Layout.fillWidth: true; spacing: 10; Item { Layout.fillWidth: true }
                GhostButton { text: "Cancelar"; onClicked: dupStep2Popup.close() }
                Button {
                    text: "Substituir"; enabled: dupConfirmField.text === nameField.text.trim()
                    onClicked: { dupStep2Popup.close(); root.doCreate() }
                    background: Rectangle { radius: 7; color: parent.enabled ? (parent.hovered ? "#2d5f8a" : "#3d7aab") : ThemeManager.surfaceDim; Behavior on color { ColorAnimation { duration: 150 } } }
                    contentItem: Text { text: parent.text; color: ThemeManager.buttonText; font.pixelSize: 12; font.weight: Font.Bold; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    leftPadding: 16; rightPadding: 16; topPadding: 8; bottomPadding: 8
                }
            }
        }
    }
}
