// qml/CampoSelector.qml
// Seletor unificado para os 3 campos (6 objetos).
// O Popup se mantém aberto e avança automaticamente até concluir a sequência.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    // Variáveis de estado individuais (blindadas contra bugs de reatividade do Qt)
    property string c1o1: ""
    property string c1o2: ""
    property string c2o1: ""
    property string c2o2: ""
    property string c3o1: ""
    property string c3o2: ""

    // Expondo os pares formados para o arquivo pai
    property string pair1: c1o1 !== "" && c1o2 !== "" ? c1o1 + c1o2 : ""
    property string pair2: c2o1 !== "" && c2o2 !== "" ? c2o1 + c2o2 : ""
    property string pair3: c3o1 !== "" && c3o2 !== "" ? c3o1 + c3o2 : ""

    // Sequência atual: 0=C1O1, 1=C1O2, 2=C2O1, 3=C2O2, 4=C3O1, 5=C3O2
    property int activeStep: 0

    // O objeto H foi removido da biblioteca!
    readonly property var availableLetters: ["A", "B", "C", "D", "E", "F", "G", "I", "J", "L", "M", "N", "O", "P", "R", "S"]

    signal allPairsCompleted()

    implicitHeight: mainLayout.implicitHeight

    // Função auxiliar para injetar a letra no slot correto da sequência
    function setLetter(step, letter) {
        if (step === 0) c1o1 = letter; else if (step === 1) c1o2 = letter;
        else if (step === 2) c2o1 = letter; else if (step === 3) c2o2 = letter;
        else if (step === 4) c3o1 = letter; else if (step === 5) c3o2 = letter;
    }

    // Função para pegar a letra do slot atual (para marcar vermelho no popup)
    function getCurrentLetter(step) {
        if (step === 0) return c1o1; if (step === 1) return c1o2;
        if (step === 2) return c2o1; if (step === 3) return c2o2;
        if (step === 4) return c3o1; if (step === 5) return c3o2;
        return "";
    }

    // ── Popup de seleção (Aumentado e Contínuo) ──────────────────────────────
    Popup {
        id: letterPicker
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: 340 // Janela mais larga para comportar bem a grade
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle {
            radius: 12; color: "#1a1a2e"
            border.color: "#ab3d4c"; border.width: 1
        }

        ColumnLayout {
            anchors { fill: parent; margins: 16 }
            spacing: 12

            Text {
                // Título dinâmico: Muda sozinho a cada clique!
                text: "Objeto " + ((root.activeStep % 2) + 1) + "  ·  Campo " + (Math.floor(root.activeStep / 2) + 1)
                color: "#e8e8f0"; font.pixelSize: 14; font.weight: Font.Bold
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: "#2d2d4a" }

            Flow {
                Layout.fillWidth: true
                spacing: 8 // Mais espaço entre os botões para clicar rápido

                Repeater {
                    model: root.availableLetters
                    delegate: Rectangle {
                        width: 44; height: 44; radius: 8 // Botões mais gordinhos
                        
                        property bool isSelected: root.getCurrentLetter(root.activeStep) === modelData
                        
                        color: isSelected ? "#ab3d4c" : (lMa.containsMouse ? "#222240" : "#12122a")
                        border.color: isSelected ? "#7a2030" : "#3a3a5c"; border.width: 1
                        Behavior on color { ColorAnimation { duration: 100 } }

                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            color: "#e8e8f0"; font.pixelSize: 15; font.weight: Font.Bold
                        }

                        MouseArea {
                            id: lMa; anchors.fill: parent
                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                // 1. Grava a letra
                                root.setLetter(root.activeStep, modelData)
                                
                                // 2. Avança ou encerra
                                if (root.activeStep < 5) {
                                    root.activeStep++ // Pula pro próximo sem fechar a janela!
                                } else {
                                    letterPicker.close() // Fechou no Objeto 6
                                    root.allPairsCompleted()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Layout principal desenhando os 3 Campos ─────────────────────────────
    RowLayout {
        id: mainLayout
        anchors { left: parent.left; right: parent.right }
        spacing: 16

        // ════════ CAMPO 1 ════════
        ColumnLayout {
            Layout.fillWidth: true; spacing: 6
            
            Rectangle {
                Layout.fillWidth: true; height: 32; radius: 6
                color: "#1a1a2e"; border.color: "#2d2d4a"; border.width: 1
                Text { anchors.centerIn: parent; text: "Campo 1"; color: "#e8e8f0"; font.pixelSize: 12; font.weight: Font.Bold }
            }

            RowLayout {
                Layout.fillWidth: true; spacing: 6
                
                // SLOT 0
                Rectangle {
                    Layout.fillWidth: true; height: 58; radius: 8
                    property bool filled: root.c1o1 !== ""
                    property bool isEnabled: true // Primeiro SEMPRE destravado
                    
                    opacity: isEnabled ? 1.0 : 0.4
                    color: filled ? "#1f0d10" : (ma0.containsMouse ? "#16162e" : "#12122a")
                    border.color: filled ? "#ab3d4c" : "#2d2d4a"; border.width: filled ? 2 : 1

                    ColumnLayout {
                        anchors.centerIn: parent; spacing: 2
                        Text { Layout.alignment: Qt.AlignHCenter; text: "Objeto 1"; color: "#555577"; font.pixelSize: 9 }
                        Text { Layout.alignment: Qt.AlignHCenter; text: root.c1o1 !== "" ? "OBJ" + root.c1o1 : "▾ Escolher"; color: root.c1o1 !== "" ? "#e8e8f0" : "#666688"; font.pixelSize: 13; font.weight: Font.Bold }
                    }
                    MouseArea { id: ma0; anchors.fill: parent; enabled: parent.isEnabled; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.activeStep = 0; letterPicker.open() } }
                }

                // SLOT 1
                Rectangle {
                    Layout.fillWidth: true; height: 58; radius: 8
                    property bool filled: root.c1o2 !== ""
                    property bool isEnabled: root.c1o1 !== "" // Só destrava se o 0 existir
                    
                    opacity: isEnabled ? 1.0 : 0.4
                    color: filled ? "#1f0d10" : (ma1.containsMouse ? "#16162e" : "#12122a")
                    border.color: filled ? "#ab3d4c" : "#2d2d4a"; border.width: filled ? 2 : 1

                    ColumnLayout {
                        anchors.centerIn: parent; spacing: 2
                        Text { Layout.alignment: Qt.AlignHCenter; text: "Objeto 2"; color: "#555577"; font.pixelSize: 9 }
                        Text { Layout.alignment: Qt.AlignHCenter; text: root.c1o2 !== "" ? "OBJ" + root.c1o2 : "▾ Escolher"; color: root.c1o2 !== "" ? "#e8e8f0" : "#666688"; font.pixelSize: 13; font.weight: Font.Bold }
                    }
                    MouseArea { id: ma1; anchors.fill: parent; enabled: parent.isEnabled; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.activeStep = 1; letterPicker.open() } }
                }
            }
        }

        // ════════ CAMPO 2 ════════
        ColumnLayout {
            Layout.fillWidth: true; spacing: 6
            
            Rectangle {
                Layout.fillWidth: true; height: 32; radius: 6
                color: "#1a1a2e"; border.color: "#2d2d4a"; border.width: 1
                Text { anchors.centerIn: parent; text: "Campo 2"; color: "#e8e8f0"; font.pixelSize: 12; font.weight: Font.Bold }
            }

            RowLayout {
                Layout.fillWidth: true; spacing: 6
                
                // SLOT 2
                Rectangle {
                    Layout.fillWidth: true; height: 58; radius: 8
                    property bool filled: root.c2o1 !== ""
                    property bool isEnabled: root.c1o2 !== "" // Só destrava se o Campo 1 terminou
                    
                    opacity: isEnabled ? 1.0 : 0.4
                    color: filled ? "#1f0d10" : (ma2.containsMouse ? "#16162e" : "#12122a")
                    border.color: filled ? "#ab3d4c" : "#2d2d4a"; border.width: filled ? 2 : 1

                    ColumnLayout {
                        anchors.centerIn: parent; spacing: 2
                        Text { Layout.alignment: Qt.AlignHCenter; text: "Objeto 1"; color: "#555577"; font.pixelSize: 9 }
                        Text { Layout.alignment: Qt.AlignHCenter; text: root.c2o1 !== "" ? "OBJ" + root.c2o1 : "▾ Escolher"; color: root.c2o1 !== "" ? "#e8e8f0" : "#666688"; font.pixelSize: 13; font.weight: Font.Bold }
                    }
                    MouseArea { id: ma2; anchors.fill: parent; enabled: parent.isEnabled; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.activeStep = 2; letterPicker.open() } }
                }

                // SLOT 3
                Rectangle {
                    Layout.fillWidth: true; height: 58; radius: 8
                    property bool filled: root.c2o2 !== ""
                    property bool isEnabled: root.c2o1 !== ""
                    
                    opacity: isEnabled ? 1.0 : 0.4
                    color: filled ? "#1f0d10" : (ma3.containsMouse ? "#16162e" : "#12122a")
                    border.color: filled ? "#ab3d4c" : "#2d2d4a"; border.width: filled ? 2 : 1

                    ColumnLayout {
                        anchors.centerIn: parent; spacing: 2
                        Text { Layout.alignment: Qt.AlignHCenter; text: "Objeto 2"; color: "#555577"; font.pixelSize: 9 }
                        Text { Layout.alignment: Qt.AlignHCenter; text: root.c2o2 !== "" ? "OBJ" + root.c2o2 : "▾ Escolher"; color: root.c2o2 !== "" ? "#e8e8f0" : "#666688"; font.pixelSize: 13; font.weight: Font.Bold }
                    }
                    MouseArea { id: ma3; anchors.fill: parent; enabled: parent.isEnabled; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.activeStep = 3; letterPicker.open() } }
                }
            }
        }

        // ════════ CAMPO 3 ════════
        ColumnLayout {
            Layout.fillWidth: true; spacing: 6
            
            Rectangle {
                Layout.fillWidth: true; height: 32; radius: 6
                color: "#1a1a2e"; border.color: "#2d2d4a"; border.width: 1
                Text { anchors.centerIn: parent; text: "Campo 3"; color: "#e8e8f0"; font.pixelSize: 12; font.weight: Font.Bold }
            }

            RowLayout {
                Layout.fillWidth: true; spacing: 6
                
                // SLOT 4
                Rectangle {
                    Layout.fillWidth: true; height: 58; radius: 8
                    property bool filled: root.c3o1 !== ""
                    property bool isEnabled: root.c2o2 !== "" // Só destrava se o Campo 2 terminou
                    
                    opacity: isEnabled ? 1.0 : 0.4
                    color: filled ? "#1f0d10" : (ma4.containsMouse ? "#16162e" : "#12122a")
                    border.color: filled ? "#ab3d4c" : "#2d2d4a"; border.width: filled ? 2 : 1

                    ColumnLayout {
                        anchors.centerIn: parent; spacing: 2
                        Text { Layout.alignment: Qt.AlignHCenter; text: "Objeto 1"; color: "#555577"; font.pixelSize: 9 }
                        Text { Layout.alignment: Qt.AlignHCenter; text: root.c3o1 !== "" ? "OBJ" + root.c3o1 : "▾ Escolher"; color: root.c3o1 !== "" ? "#e8e8f0" : "#666688"; font.pixelSize: 13; font.weight: Font.Bold }
                    }
                    MouseArea { id: ma4; anchors.fill: parent; enabled: parent.isEnabled; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.activeStep = 4; letterPicker.open() } }
                }

                // SLOT 5
                Rectangle {
                    Layout.fillWidth: true; height: 58; radius: 8
                    property bool filled: root.c3o2 !== ""
                    property bool isEnabled: root.c3o1 !== ""
                    
                    opacity: isEnabled ? 1.0 : 0.4
                    color: filled ? "#1f0d10" : (ma5.containsMouse ? "#16162e" : "#12122a")
                    border.color: filled ? "#ab3d4c" : "#2d2d4a"; border.width: filled ? 2 : 1

                    ColumnLayout {
                        anchors.centerIn: parent; spacing: 2
                        Text { Layout.alignment: Qt.AlignHCenter; text: "Objeto 2"; color: "#555577"; font.pixelSize: 9 }
                        Text { Layout.alignment: Qt.AlignHCenter; text: root.c3o2 !== "" ? "OBJ" + root.c3o2 : "▾ Escolher"; color: root.c3o2 !== "" ? "#e8e8f0" : "#666688"; font.pixelSize: 13; font.weight: Font.Bold }
                    }
                    MouseArea { id: ma5; anchors.fill: parent; enabled: parent.isEnabled; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.activeStep = 5; letterPicker.open() } }
                }
            }
        }
    }
}