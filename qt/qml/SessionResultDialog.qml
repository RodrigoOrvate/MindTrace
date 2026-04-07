// qml/SessionResultDialog.qml
// Popup pós-gravação (300 s): usuário confirma os dados dos animais de cada campo.
// Campo, Par de Objetos e Dia são preenchidos automaticamente a partir da
// sessão configurada no dashboard. Apenas Animal e Droga são digitados aqui.

import QtQuick 2.12
import QtQuick.Controls 2.12
import QtQuick.Layouts 1.3
import MindTrace.Backend 1.0

Popup {
    id: root

    // ── Dados fornecidos pelo Dashboard ──────────────────────────────────
    property string experimentName:   ""
    property string pair1:            ""   // ID do par — ex.: "AA"
    property string pair2:            ""
    property string pair3:            ""
    property string sessionTypeLabel: "Treino"
    property string dia:              "1"
    property bool   includeDrug:      true
    property string analysisMode:     "offline"  // "offline" ou "ao_vivo"
    property string saveDirectory:    ""

    // ── Validação ─────────────────────────────────────────────────────────
    property bool animalsOk: animal1Field.text.trim().length > 0
                          && animal2Field.text.trim().length > 0
                          && animal3Field.text.trim().length > 0
    property bool dirOk:     root.analysisMode === "offline"
                          || videoPathField.text.trim().length > 0
                          || (root.saveDirectory !== "" && root.analysisMode === "ao_vivo")
    property bool allFilled: animalsOk && dirOk

    // ── Geometria ─────────────────────────────────────────────────────────
    anchors.centerIn: parent
    width: 520
    // Altura se ajusta: campos de droga são ocultos quando includeDrug = false
    // O ColumnLayout calcula a altura correta via implicitHeight
    height: mainLayout.implicitHeight + 48

    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape

    onOpened: {
        videoPathField.text = ""
        animal1Field.text   = ""
        animal2Field.text   = ""
        animal3Field.text   = ""
        droga1Field.text    = ""
        droga2Field.text    = ""
        droga3Field.text    = ""
        // Ao vivo: pre-fill save directory
        if (root.analysisMode === "ao_vivo") {
            videoPathField.placeholderText = root.saveDirectory
        } else {
            videoPathField.placeholderText = "Diretório do vídeo (opcional)"
        }
        animal1Field.forceActiveFocus()
    }

    background: Rectangle {
        radius: 14; color: "#1a1a2e"
        border.color: "#ab3d4c"; border.width: 1
    }

    ColumnLayout {
        id: mainLayout
        // Não usa anchors.fill para que implicitHeight seja calculado pelo conteúdo
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
        spacing: 12

        // ── Header ───────────────────────────────────────────────────────
        RowLayout {
            spacing: 10
            Text { text: "🎬"; font.pixelSize: 20 }
            ColumnLayout {
                spacing: 2
                Text {
                    text: "Sessão Concluída"
                    color: "#e8e8f0"; font.pixelSize: 16; font.weight: Font.Bold
                }
                Text {
                    text: root.sessionTypeLabel + "  ·  Dia " + root.dia
                    color: "#ab3d4c"; font.pixelSize: 11
                }
            }
            Item { Layout.fillWidth: true }
            Text {
                text: "✕"; color: "#8888aa"; font.pixelSize: 14
                MouseArea {
                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: root.close()
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: "#2d2d4a" }

        // ── Vídeo ──
        // Offline: vídeo já conhecido na Arena, campo oculto
        // Ao vivo: precisa definir onde salvar o vídeo
        RowLayout {
            visible: root.analysisMode === "ao_vivo"
            Layout.fillWidth: true; spacing: 8
            Text { text: "📁"; font.pixelSize: 14; color: "#8888aa" }
            TextField {
                id: videoPathField
                Layout.fillWidth: true
                placeholderText: root.saveDirectory !== ""
                                 ? root.saveDirectory
                                 : "Diretório de salvamento"
                color: "#e8e8f0"; placeholderTextColor: "#8888aa"; font.pixelSize: 12
                leftPadding: 10; rightPadding: 10; topPadding: 6; bottomPadding: 6
                background: Rectangle {
                    radius: 6; color: "#12122a"
                    border.color: videoPathField.activeFocus ? "#ab3d4c" : "#3a3a5c"; border.width: 1
                    Behavior on border.color { ColorAnimation { duration: 150 } }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: "#2d2d4a" }

        // ── Campo 1 ───────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true; spacing: 10

            Rectangle {
                width: 56; height: 40; radius: 6
                color: "#1f0d10"; border.color: "#ab3d4c"; border.width: 1
                ColumnLayout {
                    anchors.centerIn: parent; spacing: 2
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Campo 1"; color: "#ab3d4c"; font.pixelSize: 9; font.weight: Font.Bold
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.pair1 !== "" ? "Par " + root.pair1 : "—"
                        color: "#8888aa"; font.pixelSize: 8
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true; spacing: 4
                TextField {
                    id: animal1Field
                    Layout.fillWidth: true
                    placeholderText: "Nº do Animal"
                    color: "#e8e8f0"; placeholderTextColor: "#8888aa"; font.pixelSize: 12
                    leftPadding: 10; rightPadding: 10; topPadding: 6; bottomPadding: 6
                    background: Rectangle {
                        radius: 6; color: "#12122a"
                        border.color: animal1Field.activeFocus ? "#ab3d4c" : "#3a3a5c"; border.width: 1
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                    }
                }
                TextField {
                    id: droga1Field
                    Layout.fillWidth: true
                    visible: root.includeDrug
                    placeholderText: "Droga"
                    color: "#e8e8f0"; placeholderTextColor: "#8888aa"; font.pixelSize: 12
                    leftPadding: 10; rightPadding: 10; topPadding: 6; bottomPadding: 6
                    background: Rectangle {
                        radius: 6; color: "#12122a"
                        border.color: droga1Field.activeFocus ? "#ab3d4c" : "#3a3a5c"; border.width: 1
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                    }
                }
            }
        }

        // ── Campo 2 ───────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true; spacing: 10

            Rectangle {
                width: 56; height: 40; radius: 6
                color: "#1f0d10"; border.color: "#ab3d4c"; border.width: 1
                ColumnLayout {
                    anchors.centerIn: parent; spacing: 2
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Campo 2"; color: "#ab3d4c"; font.pixelSize: 9; font.weight: Font.Bold
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.pair2 !== "" ? "Par " + root.pair2 : "—"
                        color: "#8888aa"; font.pixelSize: 8
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true; spacing: 4
                TextField {
                    id: animal2Field
                    Layout.fillWidth: true
                    placeholderText: "Nº do Animal"
                    color: "#e8e8f0"; placeholderTextColor: "#8888aa"; font.pixelSize: 12
                    leftPadding: 10; rightPadding: 10; topPadding: 6; bottomPadding: 6
                    background: Rectangle {
                        radius: 6; color: "#12122a"
                        border.color: animal2Field.activeFocus ? "#ab3d4c" : "#3a3a5c"; border.width: 1
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                    }
                }
                TextField {
                    id: droga2Field
                    Layout.fillWidth: true
                    visible: root.includeDrug
                    placeholderText: "Droga"
                    color: "#e8e8f0"; placeholderTextColor: "#8888aa"; font.pixelSize: 12
                    leftPadding: 10; rightPadding: 10; topPadding: 6; bottomPadding: 6
                    background: Rectangle {
                        radius: 6; color: "#12122a"
                        border.color: droga2Field.activeFocus ? "#ab3d4c" : "#3a3a5c"; border.width: 1
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                    }
                }
            }
        }

        // ── Campo 3 ───────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true; spacing: 10

            Rectangle {
                width: 56; height: 40; radius: 6
                color: "#1f0d10"; border.color: "#ab3d4c"; border.width: 1
                ColumnLayout {
                    anchors.centerIn: parent; spacing: 2
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Campo 3"; color: "#ab3d4c"; font.pixelSize: 9; font.weight: Font.Bold
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.pair3 !== "" ? "Par " + root.pair3 : "—"
                        color: "#8888aa"; font.pixelSize: 8
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true; spacing: 4
                TextField {
                    id: animal3Field
                    Layout.fillWidth: true
                    placeholderText: "Nº do Animal"
                    color: "#e8e8f0"; placeholderTextColor: "#8888aa"; font.pixelSize: 12
                    leftPadding: 10; rightPadding: 10; topPadding: 6; bottomPadding: 6
                    background: Rectangle {
                        radius: 6; color: "#12122a"
                        border.color: animal3Field.activeFocus ? "#ab3d4c" : "#3a3a5c"; border.width: 1
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                    }
                }
                TextField {
                    id: droga3Field
                    Layout.fillWidth: true
                    visible: root.includeDrug
                    placeholderText: "Droga"
                    color: "#e8e8f0"; placeholderTextColor: "#8888aa"; font.pixelSize: 12
                    leftPadding: 10; rightPadding: 10; topPadding: 6; bottomPadding: 6
                    background: Rectangle {
                        radius: 6; color: "#12122a"
                        border.color: droga3Field.activeFocus ? "#ab3d4c" : "#3a3a5c"; border.width: 1
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                    }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: "#2d2d4a" }

        // ── Botões ───────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true; spacing: 10
            Item { Layout.fillWidth: true }
            GhostButton { text: "Cancelar"; onClicked: root.close() }
            Button {
                text: "✓ Inserir Dados"
                enabled: root.allFilled
                onClicked: {
                    // For offline, no video path needed; for live use typed dir or saved dir
                    var v = root.analysisMode === "offline" ? ""
                          : (videoPathField.text.trim() || root.saveDirectory.replace("file:///", ""))
                    var rows = []

                    var r1 = [v, animal1Field.text.trim(), "1", root.dia, root.pair1]
                    if (root.includeDrug) r1.push(droga1Field.text.trim())
                    rows.push(r1)

                    var r2 = [v, animal2Field.text.trim(), "2", root.dia, root.pair2]
                    if (root.includeDrug) r2.push(droga2Field.text.trim())
                    rows.push(r2)

                    var r3 = [v, animal3Field.text.trim(), "3", root.dia, root.pair3]
                    if (root.includeDrug) r3.push(droga3Field.text.trim())
                    rows.push(r3)

                    ExperimentManager.insertSessionResult(root.experimentName, rows)
                    root.close()
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
                leftPadding: 18; rightPadding: 18; topPadding: 9; bottomPadding: 9
            }
        }
    }
}
