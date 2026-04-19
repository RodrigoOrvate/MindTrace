// qml/SessionResultDialog.qml
// Popup pós-gravação (300 s): usuário confirma os dados dos animais de cada campo.
// Campo, Par de Objetos e Dia são preenchidos automaticamente a partir da
// sessão configurada no dashboard. Apenas Animal e Droga são digitados aqui.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../core"
import "../core/Theme"
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
    property bool   hasReactivation:  false  // kept for compat; dayNames preferred
    property var    dayNames:         []
    property string analysisMode:     "offline"  // "offline" ou "ao_vivo"
    property string saveDirectory:    ""
    property string videoPath:        ""

    // ── Dados de tracking da sessão (injetados pelo LiveRecording) ────────
    // explorationBouts: array[6] de arrays de durações (s) por zona
    // explorationTimes: array[6] de tempos totais (s) por zona
    // totalDistance: array[3] de distâncias (m) por campo
    // currentVelocity: array[3] de velocidades médias (m/s) por campo
    property var sessionExplorationBouts: [[], [], [], [], [], []]
    property var sessionExplorationTimes: [0, 0, 0, 0, 0, 0]
    property var sessionTotalDistance:    [0.0, 0.0, 0.0]
    property var sessionAvgVelocity:      [0.0, 0.0, 0.0]
    property var sessionPerMinuteData:    [{}, {}, {}]  // por campo

    // ── Validação ─────────────────────────────────────────────────────────
    property bool animalsOk: (animal1Field.text.trim() !== "" || animal2Field.text.trim() !== "" || animal3Field.text.trim() !== "")
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
        dayCombo.currentIndex = 0
        animal1Field.text     = ""
        animal2Field.text     = ""
        animal3Field.text     = ""
        droga1Field.text      = ""
        droga2Field.text      = ""
        droga3Field.text      = ""
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
                    text: "Selecione o dia desta sessão"
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

        // ── Dia da sessão (ComboBox com dayNames) ─────────────────────────
        RowLayout {
            Layout.fillWidth: true; spacing: 10

            ColumnLayout {
                spacing: 4
                Text {
                    text: "DIA"
                    color: "#8888aa"; font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 1.2
                }
                Text {
                    text: "Mesmo para os " + (root.pair1 ? "3 campos" : "campos ativos")
                    color: "#444466"; font.pixelSize: 9
                }
            }

            ComboBox {
                id: dayCombo
                model: root.dayNames.length > 0 ? root.dayNames : ["Dia 1"]
                Layout.fillWidth: true
                font.pixelSize: 13; font.weight: Font.Bold

                contentItem: Text {
                    leftPadding: 12
                    text: dayCombo.displayText
                    color: "#e8e8f0"; font: dayCombo.font
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    radius: 6; color: "#12122a"
                    border.color: dayCombo.activeFocus ? "#ab3d4c" : "#4a4a8c"; border.width: 1
                    Behavior on border.color { ColorAnimation { duration: 150 } }
                }
                delegate: ItemDelegate {
                    width: dayCombo.width
                    contentItem: Text {
                        text: modelData
                        color: dayCombo.currentIndex === index ? "#ff7788" : "#e8e8f0"
                        font.pixelSize: 13; font.weight: Font.Bold
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        color: hovered ? "#2a2a4a" : "#12122a"
                    }
                }
                popup: Popup {
                    y: dayCombo.height
                    width: dayCombo.width
                    padding: 0
                    background: Rectangle { color: "#12122a"; border.color: "#4a4a8c"; radius: 6 }
                    contentItem: ListView {
                        implicitHeight: contentHeight
                        model: dayCombo.delegateModel
                        clip: true
                    }
                }
            }

            // Badge dia selecionado
            Rectangle {
                radius: 5; color: "#1f0d10"
                border.color: "#ab3d4c"; border.width: 1
                implicitWidth: faseLbl.implicitWidth + 16; implicitHeight: 28
                Text {
                    id: faseLbl; anchors.centerIn: parent
                    text: "Dia " + (dayCombo.currentIndex + 1)
                    color: "#ff7788"; font.pixelSize: 13; font.weight: Font.Bold
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
                    placeholderText: "Nº do Animal (ou deixe vazio para pular)"
                    color: "#e8e8f0"; placeholderTextColor: "#8888aa"; font.pixelSize: 12
                    leftPadding: 10; rightPadding: 10; topPadding: 6; bottomPadding: 6
                    background: Rectangle {
                        radius: 6; color: "#12122a"
                        border.color: animal1Field.activeFocus ? "#ab3d4c" : "#3a3a5c"; border.width: 1
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                    }
                    Keys.onReturnPressed: animal2Field.forceActiveFocus()
                }
                TextField {
                    id: droga1Field
                    Layout.fillWidth: true
                    visible: root.includeDrug
                    placeholderText: "Tratamento"
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
                    placeholderText: "Nº do Animal (ou deixe vazio para pular)"
                    color: "#e8e8f0"; placeholderTextColor: "#8888aa"; font.pixelSize: 12
                    leftPadding: 10; rightPadding: 10; topPadding: 6; bottomPadding: 6
                    background: Rectangle {
                        radius: 6; color: "#12122a"
                        border.color: animal2Field.activeFocus ? "#ab3d4c" : "#3a3a5c"; border.width: 1
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                    }
                    Keys.onReturnPressed: animal3Field.forceActiveFocus()
                }
                TextField {
                    id: droga2Field
                    Layout.fillWidth: true
                    visible: root.includeDrug
                    placeholderText: "Tratamento"
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
                    placeholderText: "Nº do Animal (ou deixe vazio para pular)"
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
                    placeholderText: "Tratamento"
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
                onClicked: root.doInsert()
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
        var v    = root.videoPath.replace("file:///", "")
        var fase = dayCombo.currentText
        var dia  = String(dayCombo.currentIndex + 1)
        var rows = []

        if (animal1Field.text.trim()) {
            var r1 = [v, animal1Field.text.trim(), "1", dia, root.pair1]
            if (root.includeDrug) r1.push(droga1Field.text.trim())
            rows.push(r1)
        }
        if (animal2Field.text.trim()) {
            var r2 = [v, animal2Field.text.trim(), "2", dia, root.pair2]
            if (root.includeDrug) r2.push(droga2Field.text.trim())
            rows.push(r2)
        }
        if (animal3Field.text.trim()) {
            var r3 = [v, animal3Field.text.trim(), "3", dia, root.pair3]
            if (root.includeDrug) r3.push(droga3Field.text.trim())
            rows.push(r3)
        }

        ExperimentManager.insertSessionResult(root.experimentName, rows)

        // ── Salva metadados ricos da sessão (bouts, distância, velocidade) ──
        var sessionMeta = {
            "timestamp":  new Date().toISOString(),
            "fase":       fase,
            "dia":        dia,
            "videoPath":  v,
            "campos": []
        }
        var animais = [animal1Field.text.trim(), animal2Field.text.trim(), animal3Field.text.trim()]
        var drogas  = [droga1Field.text.trim(),  droga2Field.text.trim(),  droga3Field.text.trim()]
        var pares   = [root.pair1, root.pair2, root.pair3]
        for (var i = 0; i < 3; i++) {
            if (!animais[i]) continue
            var zi0 = i * 2
            var zi1 = i * 2 + 1
            var bouts0 = root.sessionExplorationBouts[zi0] || []
            var bouts1 = root.sessionExplorationBouts[zi1] || []
            var campoMeta = {
                "animal":        animais[i],
                "campo":         i + 1,
                "par":           pares[i],
                "droga":         drogas[i],
                "exploração": {
                    "objA_total_s":  (root.sessionExplorationTimes[zi0] || 0).toFixed(1),
                    "objB_total_s":  (root.sessionExplorationTimes[zi1] || 0).toFixed(1),
                    "objA_bouts":    bouts0,
                    "objB_bouts":    bouts1,
                    "objA_n_bouts":  bouts0.length,
                    "objB_n_bouts":  bouts1.length,
                    "DI":            (bouts0.length + bouts1.length > 0)
                                     ? (((root.sessionExplorationTimes[zi1] || 0) - (root.sessionExplorationTimes[zi0] || 0))
                                        / ((root.sessionExplorationTimes[zi0] || 0) + (root.sessionExplorationTimes[zi1] || 0) + 0.001)).toFixed(3)
                                     : "NaN"
                },
                "movimento": {
                    "distancia_total_m":  (root.sessionTotalDistance[i]  || 0).toFixed(3),
                    "velocidade_media_ms":(root.sessionAvgVelocity[i]    || 0).toFixed(3)
                },
                "porMinuto": root.sessionPerMinuteData[i] || []
            }
            sessionMeta["campos"].push(campoMeta)
        }

        // Constrói hint legível para o nome do arquivo: ex. "TR_A1-A2"
        var animaisStr = animais.filter(function(a){ return a.length > 0; }).join("-")
        var nameHint   = fase + "_" + animaisStr
        ExperimentManager.saveSessionMetadata(root.experimentName, JSON.stringify(sessionMeta), nameHint)

        root.close()
    }

}
