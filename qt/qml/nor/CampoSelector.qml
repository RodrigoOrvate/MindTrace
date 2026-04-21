// qml/CampoSelector.qml
// Seletor unificado para os 3 campos (6 objetos).
// O Popup se mantém aberto e avança automaticamente até concluir a sequência.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../core"
import "../core/Theme"

Item {
    id: root

    property int numCampos: 3

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

    // Número máximo de steps baseado em numCampos (2 slots por campo)
    readonly property int maxStep: root.numCampos * 2 - 1

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
        width: 340
        height: letterPickerLayout.implicitHeight + 40
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle {
            radius: 12; color: ThemeManager.surface
            Behavior on color { ColorAnimation { duration: 200 } }
            border.color: ThemeManager.accent; border.width: 1
        }

        ColumnLayout {
            id: letterPickerLayout
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
            spacing: 12

            Text {
                text: LanguageManager.tr3("Objeto ", "Object ", "Objeto ") + ((root.activeStep % 2) + 1) + "  ·  " +
                      LanguageManager.tr3("Campo ", "Field ", "Campo ") + (Math.floor(root.activeStep / 2) + 1)
                color: ThemeManager.textPrimary
                Behavior on color { ColorAnimation { duration: 150 } }
                font.pixelSize: 14; font.weight: Font.Bold
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } } }

            Flow {
                Layout.fillWidth: true
                spacing: 8

                Repeater {
                    model: root.availableLetters
                    delegate: Rectangle {
                        width: 44; height: 44; radius: 8

                        property bool isSelected: root.getCurrentLetter(root.activeStep) === modelData

                        color: isSelected ? ThemeManager.accent : (lMa.containsMouse ? ThemeManager.surfaceHover : ThemeManager.surfaceDim)
                        border.color: isSelected ? ThemeManager.accentHover : ThemeManager.border; border.width: 1
                        Behavior on color { ColorAnimation { duration: 100 } }

                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            color: ThemeManager.textPrimary
                            Behavior on color { ColorAnimation { duration: 150 } }
                            font.pixelSize: 15; font.weight: Font.Bold
                        }

                        MouseArea {
                            id: lMa; anchors.fill: parent
                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.setLetter(root.activeStep, modelData)
                                if (root.activeStep < root.maxStep) {
                                    root.activeStep++
                                } else {
                                    letterPicker.close()
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
                color: ThemeManager.surface
                Behavior on color { ColorAnimation { duration: 200 } }
                border.color: ThemeManager.border; border.width: 1
                Text { anchors.centerIn: parent; text: LanguageManager.tr3("Campo 1", "Field 1", "Campo 1"); color: ThemeManager.textPrimary; font.pixelSize: 12; font.weight: Font.Bold }
            }

            RowLayout {
                Layout.fillWidth: true; spacing: 6

                // SLOT 0
                Rectangle {
                    Layout.fillWidth: true; height: 58; radius: 8
                    property bool filled: root.c1o1 !== ""
                    property bool isEnabled: true

                    opacity: isEnabled ? 1.0 : 0.4
                    color: filled ? ThemeManager.accentDim : (ma0.containsMouse ? ThemeManager.surfaceHover : ThemeManager.surfaceDim)
                    border.color: filled ? ThemeManager.accent : ThemeManager.border; border.width: filled ? 2 : 1
                    Behavior on color { ColorAnimation { duration: 150 } }

                    ColumnLayout {
                        anchors.centerIn: parent; spacing: 2
                        Text { Layout.alignment: Qt.AlignHCenter; text: LanguageManager.tr3("Objeto 1", "Object 1", "Objeto 1"); color: ThemeManager.textTertiary; font.pixelSize: 9 }
                        Text { Layout.alignment: Qt.AlignHCenter; text: root.c1o1 !== "" ? "OBJ" + root.c1o1 : LanguageManager.tr3("Choose", "Choose", "Elegir"); color: root.c1o1 !== "" ? ThemeManager.textPrimary : ThemeManager.textSecondary; font.pixelSize: 13; font.weight: Font.Bold }
                    }
                    MouseArea { id: ma0; anchors.fill: parent; enabled: parent.isEnabled; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.activeStep = 0; letterPicker.open() } }
                }

                // SLOT 1
                Rectangle {
                    Layout.fillWidth: true; height: 58; radius: 8
                    property bool filled: root.c1o2 !== ""
                    property bool isEnabled: root.c1o1 !== ""

                    opacity: isEnabled ? 1.0 : 0.4
                    color: filled ? ThemeManager.accentDim : (ma1.containsMouse ? ThemeManager.surfaceHover : ThemeManager.surfaceDim)
                    border.color: filled ? ThemeManager.accent : ThemeManager.border; border.width: filled ? 2 : 1
                    Behavior on color { ColorAnimation { duration: 150 } }

                    ColumnLayout {
                        anchors.centerIn: parent; spacing: 2
                        Text { Layout.alignment: Qt.AlignHCenter; text: LanguageManager.tr3("Objeto 2", "Object 2", "Objeto 2"); color: ThemeManager.textTertiary; font.pixelSize: 9 }
                        Text { Layout.alignment: Qt.AlignHCenter; text: root.c1o2 !== "" ? "OBJ" + root.c1o2 : LanguageManager.tr3("Choose", "Choose", "Elegir"); color: root.c1o2 !== "" ? ThemeManager.textPrimary : ThemeManager.textSecondary; font.pixelSize: 13; font.weight: Font.Bold }
                    }
                    MouseArea { id: ma1; anchors.fill: parent; enabled: parent.isEnabled; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.activeStep = 1; letterPicker.open() } }
                }
            }
        }

        // ════════ CAMPO 2 ════════
        ColumnLayout {
            Layout.fillWidth: true; spacing: 6
            visible: root.numCampos >= 2

            Rectangle {
                Layout.fillWidth: true; height: 32; radius: 6
                color: ThemeManager.surface
                Behavior on color { ColorAnimation { duration: 200 } }
                border.color: ThemeManager.border; border.width: 1
                Text { anchors.centerIn: parent; text: LanguageManager.tr3("Campo 2", "Field 2", "Campo 2"); color: ThemeManager.textPrimary; font.pixelSize: 12; font.weight: Font.Bold }
            }

            RowLayout {
                Layout.fillWidth: true; spacing: 6

                // SLOT 2
                Rectangle {
                    Layout.fillWidth: true; height: 58; radius: 8
                    property bool filled: root.c2o1 !== ""
                    property bool isEnabled: root.c1o2 !== ""

                    opacity: isEnabled ? 1.0 : 0.4
                    color: filled ? ThemeManager.accentDim : (ma2.containsMouse ? ThemeManager.surfaceHover : ThemeManager.surfaceDim)
                    border.color: filled ? ThemeManager.accent : ThemeManager.border; border.width: filled ? 2 : 1
                    Behavior on color { ColorAnimation { duration: 150 } }

                    ColumnLayout {
                        anchors.centerIn: parent; spacing: 2
                        Text { Layout.alignment: Qt.AlignHCenter; text: LanguageManager.tr3("Objeto 1", "Object 1", "Objeto 1"); color: ThemeManager.textTertiary; font.pixelSize: 9 }
                        Text { Layout.alignment: Qt.AlignHCenter; text: root.c2o1 !== "" ? "OBJ" + root.c2o1 : LanguageManager.tr3("Choose", "Choose", "Elegir"); color: root.c2o1 !== "" ? ThemeManager.textPrimary : ThemeManager.textSecondary; font.pixelSize: 13; font.weight: Font.Bold }
                    }
                    MouseArea { id: ma2; anchors.fill: parent; enabled: parent.isEnabled; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.activeStep = 2; letterPicker.open() } }
                }

                // SLOT 3
                Rectangle {
                    Layout.fillWidth: true; height: 58; radius: 8
                    property bool filled: root.c2o2 !== ""
                    property bool isEnabled: root.c2o1 !== ""

                    opacity: isEnabled ? 1.0 : 0.4
                    color: filled ? ThemeManager.accentDim : (ma3.containsMouse ? ThemeManager.surfaceHover : ThemeManager.surfaceDim)
                    border.color: filled ? ThemeManager.accent : ThemeManager.border; border.width: filled ? 2 : 1
                    Behavior on color { ColorAnimation { duration: 150 } }

                    ColumnLayout {
                        anchors.centerIn: parent; spacing: 2
                        Text { Layout.alignment: Qt.AlignHCenter; text: LanguageManager.tr3("Objeto 2", "Object 2", "Objeto 2"); color: ThemeManager.textTertiary; font.pixelSize: 9 }
                        Text { Layout.alignment: Qt.AlignHCenter; text: root.c2o2 !== "" ? "OBJ" + root.c2o2 : LanguageManager.tr3("Choose", "Choose", "Elegir"); color: root.c2o2 !== "" ? ThemeManager.textPrimary : ThemeManager.textSecondary; font.pixelSize: 13; font.weight: Font.Bold }
                    }
                    MouseArea { id: ma3; anchors.fill: parent; enabled: parent.isEnabled; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.activeStep = 3; letterPicker.open() } }
                }
            }
        }

        // ════════ CAMPO 3 ════════
        ColumnLayout {
            Layout.fillWidth: true; spacing: 6
            visible: root.numCampos >= 3

            Rectangle {
                Layout.fillWidth: true; height: 32; radius: 6
                color: ThemeManager.surface
                Behavior on color { ColorAnimation { duration: 200 } }
                border.color: ThemeManager.border; border.width: 1
                Text { anchors.centerIn: parent; text: LanguageManager.tr3("Campo 3", "Field 3", "Campo 3"); color: ThemeManager.textPrimary; font.pixelSize: 12; font.weight: Font.Bold }
            }

            RowLayout {
                Layout.fillWidth: true; spacing: 6

                // SLOT 4
                Rectangle {
                    Layout.fillWidth: true; height: 58; radius: 8
                    property bool filled: root.c3o1 !== ""
                    property bool isEnabled: root.c2o2 !== ""

                    opacity: isEnabled ? 1.0 : 0.4
                    color: filled ? ThemeManager.accentDim : (ma4.containsMouse ? ThemeManager.surfaceHover : ThemeManager.surfaceDim)
                    border.color: filled ? ThemeManager.accent : ThemeManager.border; border.width: filled ? 2 : 1
                    Behavior on color { ColorAnimation { duration: 150 } }

                    ColumnLayout {
                        anchors.centerIn: parent; spacing: 2
                        Text { Layout.alignment: Qt.AlignHCenter; text: LanguageManager.tr3("Objeto 1", "Object 1", "Objeto 1"); color: ThemeManager.textTertiary; font.pixelSize: 9 }
                        Text { Layout.alignment: Qt.AlignHCenter; text: root.c3o1 !== "" ? "OBJ" + root.c3o1 : LanguageManager.tr3("Choose", "Choose", "Elegir"); color: root.c3o1 !== "" ? ThemeManager.textPrimary : ThemeManager.textSecondary; font.pixelSize: 13; font.weight: Font.Bold }
                    }
                    MouseArea { id: ma4; anchors.fill: parent; enabled: parent.isEnabled; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.activeStep = 4; letterPicker.open() } }
                }

                // SLOT 5
                Rectangle {
                    Layout.fillWidth: true; height: 58; radius: 8
                    property bool filled: root.c3o2 !== ""
                    property bool isEnabled: root.c3o1 !== ""

                    opacity: isEnabled ? 1.0 : 0.4
                    color: filled ? ThemeManager.accentDim : (ma5.containsMouse ? ThemeManager.surfaceHover : ThemeManager.surfaceDim)
                    border.color: filled ? ThemeManager.accent : ThemeManager.border; border.width: filled ? 2 : 1
                    Behavior on color { ColorAnimation { duration: 150 } }

                    ColumnLayout {
                        anchors.centerIn: parent; spacing: 2
                        Text { Layout.alignment: Qt.AlignHCenter; text: LanguageManager.tr3("Objeto 2", "Object 2", "Objeto 2"); color: ThemeManager.textTertiary; font.pixelSize: 9 }
                        Text { Layout.alignment: Qt.AlignHCenter; text: root.c3o2 !== "" ? "OBJ" + root.c3o2 : LanguageManager.tr3("Choose", "Choose", "Elegir"); color: root.c3o2 !== "" ? ThemeManager.textPrimary : ThemeManager.textSecondary; font.pixelSize: 13; font.weight: Font.Bold }
                    }
                    MouseArea { id: ma5; anchors.fill: parent; enabled: parent.isEnabled; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.activeStep = 5; letterPicker.open() } }
                }
            }
        }
    }
}
