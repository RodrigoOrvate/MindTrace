// qml/SessionResultDialog.qml
// Popup pós-gravação (300 s): usuário confirma os dados dos animais de cada campo.
// Campo, Par de Objetos e Dia são preenchidos automaticamente a partir da
// sessão configurada no dashboard. Apenas Animal e Droga são digitados aqui.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../core"
import MindTrace.Backend 1.0

Popup {
    id: root

    // ── Dados fornecidos pelo Dashboard ──────────────────────────────────
    property string experimentName:   ""
    property string pair1:            ""   // ID do par — ex.: "AA"
    property string pair2:            ""
    property string pair3:            ""
    property string sessionTypeLabel: ""
    property string dia:              ""
    property bool   includeDrug:      true
    property bool   hasReactivation:  false
    property string analysisMode:     "offline"  // "offline" ou "ao_vivo"
    property string saveDirectory:    ""
    property string videoPath:        ""

    // ── Validação ─────────────────────────────────────────────────────────
    property bool animalsOk: (animal1Field.text.trim() === "" || sessao1Field.text.trim().length > 0)
                          && (animal2Field.text.trim() === "" || sessao2Field.text.trim().length > 0)
                          && (animal3Field.text.trim() === "" || sessao3Field.text.trim().length > 0)
                          && (animal1Field.text.trim() !== "" || animal2Field.text.trim() !== "" || animal3Field.text.trim() !== "")
    property bool dirOk:     true // Path is automatically captured
    property bool allFilled: animalsOk

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
        animal1Field.text   = ""
        animal2Field.text   = ""
        animal3Field.text   = ""
        sessao1Field.text   = ""
        sessao2Field.text   = ""
        sessao3Field.text   = ""
        droga1Field.text    = ""
        droga2Field.text    = ""
        droga3Field.text    = ""
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
                    text: "Preencha a Fase: TR (Treino), RA (Reat.) ou TT (Teste)"
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

        // Video path capturado automaticamente

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
                RowLayout {
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
                        id: sessao1Field
                        width: 80
                        placeholderText: "Fase"
                        color: "#e8e8f0"; placeholderTextColor: "#8888aa"; font.pixelSize: 12
                        leftPadding: 10; rightPadding: 10; topPadding: 6; bottomPadding: 6
                        background: Rectangle {
                            radius: 6; color: "#12122a"
                            border.color: sessao1Field.activeFocus ? "#ab3d4c" : "#3a3a5c"; border.width: 1
                            Behavior on border.color { ColorAnimation { duration: 150 } }
                        }
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
                RowLayout {
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
                        id: sessao2Field
                        width: 80
                        placeholderText: "Fase"
                        color: "#e8e8f0"; placeholderTextColor: "#8888aa"; font.pixelSize: 12
                        leftPadding: 10; rightPadding: 10; topPadding: 6; bottomPadding: 6
                        background: Rectangle {
                            radius: 6; color: "#12122a"
                            border.color: sessao2Field.activeFocus ? "#ab3d4c" : "#3a3a5c"; border.width: 1
                            Behavior on border.color { ColorAnimation { duration: 150 } }
                        }
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
                RowLayout {
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
                        id: sessao3Field
                        width: 80
                        placeholderText: "Fase"
                        color: "#e8e8f0"; placeholderTextColor: "#8888aa"; font.pixelSize: 12
                        leftPadding: 10; rightPadding: 10; topPadding: 6; bottomPadding: 6
                        background: Rectangle {
                            radius: 6; color: "#12122a"
                            border.color: sessao3Field.activeFocus ? "#ab3d4c" : "#3a3a5c"; border.width: 1
                            Behavior on border.color { ColorAnimation { duration: 150 } }
                        }
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
                    var needsReactivationPrompt = false
                    
                    function parseDay(prefix) {
                        var p = prefix.toUpperCase().trim()
                        if (p === "TR") return "1"
                        if (p === "RA") {
                            if (!root.hasReactivation) needsReactivationPrompt = true
                            return "2"
                        }
                        if (p === "TT") return root.hasReactivation ? "3" : "2"
                        return ""
                    }
                    
                    var d1 = animal1Field.text.trim() ? parseDay(sessao1Field.text) : "0"
                    var d2 = animal2Field.text.trim() ? parseDay(sessao2Field.text) : "0"
                    var d3 = animal3Field.text.trim() ? parseDay(sessao3Field.text) : "0"
                    
                    if (d1 === "" || d2 === "" || d3 === "") {
                        errorPopup.open()
                        return
                    }
                    if (needsReactivationPrompt) {
                        reactivationPromptPopup.open()
                        return
                    }
                    root.doInsert()
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

    function doInsert() {
        var v = root.videoPath.replace("file:///", "")
        var rows = []

        function parseDay(prefix) {
            var p = prefix.toUpperCase().trim()
            if (p === "TR") return "1"
            if (p === "RA") return "2"
            if (p === "TT") return root.hasReactivation ? "3" : "2"
            return ""
        }

        if (animal1Field.text.trim()) {
            var r1 = [v, animal1Field.text.trim(), "1", parseDay(sessao1Field.text), root.pair1]
            if (root.includeDrug) r1.push(droga1Field.text.trim())
            rows.push(r1)
        }
        if (animal2Field.text.trim()) {
            var r2 = [v, animal2Field.text.trim(), "2", parseDay(sessao2Field.text), root.pair2]
            if (root.includeDrug) r2.push(droga2Field.text.trim())
            rows.push(r2)
        }
        if (animal3Field.text.trim()) {
            var r3 = [v, animal3Field.text.trim(), "3", parseDay(sessao3Field.text), root.pair3]
            if (root.includeDrug) r3.push(droga3Field.text.trim())
            rows.push(r3)
        }
        ExperimentManager.insertSessionResult(root.experimentName, rows)
        root.close()
    }

    Popup {
        id: errorPopup
        anchors.centerIn: parent
        width: 300; height: 120; modal: true
        background: Rectangle { radius: 10; color: "#1a1a2e"; border.color: "#ab3d4c" }
        ColumnLayout {
            anchors.centerIn: parent; spacing: 10
            Text { text: "Fase Inválida!"; color: "#ff5566"; font.weight: Font.Bold; font.pixelSize: 14 }
            Text { text: "Use apenas TR, RA ou TT."; color: "#e8e8f0"; font.pixelSize: 12 }
            Button { text: "OK"; onClicked: errorPopup.close() }
        }
    }

    Popup {
        id: reactivationPromptPopup
        anchors.centerIn: parent
        width: 350; height: 160; modal: true
        background: Rectangle { radius: 10; color: "#1a1a2e"; border.color: "#ffaa00" }
        ColumnLayout {
            anchors.fill: parent; anchors.margins: 16; spacing: 10
            Text { text: "Reativação não prevista!"; color: "#ffaa00"; font.weight: Font.Bold; font.pixelSize: 14 }
            Text { text: "Você digitou RA, mas o experimento foi criado sem reativação. Deseja alterar a configuração para incluir reativação?"; color: "#e8e8f0"; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                GhostButton { text: "Cancelar"; onClicked: reactivationPromptPopup.close() }
                Button {
                    text: "Sim, Incluir"
                    onClicked: {
                        ExperimentManager.setExperimentReactivation(root.experimentName, true)
                        root.hasReactivation = true
                        reactivationPromptPopup.close()
                        root.doInsert()
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
}
