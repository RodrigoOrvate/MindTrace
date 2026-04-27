// qml/cc/CCSetup.qml
// Passo 3 do fluxo CC: nome do experimento, duração, diretório e criação.

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

    property int    numCampos:    3
    property string context:      ""
    property string arenaId:      ""
    property var    contextPatterns: []
    property string selectedPath: ""
    property int    sessionMinutes: 5    // 5 ou 20

    // name, cols, includeDrug, sessionMinutes, hasObjectZones, responsavel, dayNames, savePath
    signal experimentReady(string name, var cols, bool includeDrug, int sessionMinutes, bool hasObjectZones, string responsibleUsername, var dayNames, string savePath)
    signal backRequested()
    property string responsibleUsername: ""
    property bool   responsibleUnknown: false

    function isDefaultDayNames() {
        if (dayNamesModel.count !== 2) return false
        var a = dayNamesModel.get(0).dayName
        var b = dayNamesModel.get(1).dayName
        var d1 = ["Treino", "Training", "Entrenamiento"]
        var d2 = ["Teste", "Test", "Prueba"]
        return d1.indexOf(a) >= 0 && d2.indexOf(b) >= 0
    }

    function resetDefaultDayNames() {
        dayNamesModel.clear()
        dayNamesModel.append({ dayName: LanguageManager.tr3("Treino", "Training", "Entrenamiento") })
        dayNamesModel.append({ dayName: LanguageManager.tr3("Teste", "Test", "Prueba") })
    }

    Component.onCompleted: {
        ExperimentManager.refreshResearchers()
        if (ExperimentManager.researcherUsers.length === 0) {
            responsibleUnknown = true
            responsibleUsername = "desconhecido"
        } else if (responsibleUsername === "") {
            responsibleUsername = ExperimentManager.researcherUsers[0]
        }
        if (dayNamesModel.count === 0 || isDefaultDayNames())
            resetDefaultDayNames()
    }

    Connections {
        target: LanguageManager
        function onCurrentLanguageChanged() {
            if (root.isDefaultDayNames())
                root.resetDefaultDayNames()
        }
    }

    Connections {
        target: ExperimentManager
        function onResearcherUsersChanged() {
            if (ExperimentManager.researcherUsers.length === 0) {
                root.responsibleUnknown = true
                root.responsibleUsername = "desconhecido"
            } else if (!root.responsibleUnknown && root.responsibleUsername === "") {
                root.responsibleUsername = ExperimentManager.researcherUsers[0]
            }
        }
    }

    function doCreate() {
        var cols = [
            LanguageManager.tr3("Diretorio do Video", "Video Directory", "Directorio del Video"),
            LanguageManager.tr3("Animal", "Animal", "Animal"),
            LanguageManager.tr3("Campo", "Field", "Campo"),
            LanguageManager.tr3("Dia", "Day", "Dia"),
            LanguageManager.tr3("Contexto", "Context", "Contexto"),
            LanguageManager.tr3("Duracao (min)", "Duration (min)", "Duracion (min)"),
            LanguageManager.tr3("Distancia Total (m)", "Total Distance (m)", "Distancia Total (m)"),
            LanguageManager.tr3("Velocidade Media (m/s)", "Average Speed (m/s)", "Velocidad Media (m/s)"),
            "Walking", "Sniffing", "Grooming", "Resting", "Rearing"
        ]
        if (drugCheck.checked) cols.push(LanguageManager.tr3("Tratamento", "Treatment", "Tratamiento"))
        var names = []
        for (var i = 0; i < dayNamesModel.count; i++) names.push(dayNamesModel.get(i).dayName)
        root.experimentReady(nameField.text.trim(), cols,
                             drugCheck.checked, root.sessionMinutes,
                             root.numCampos > 1 ? objectZonesCheck.checked : false,
                             root.responsibleUnknown ? "desconhecido" : responsibleUsername,
                             names, root.selectedPath)
    }

    FolderDialog {
        id: folderDialog
        title: "Escolha a Pasta Raiz do Experimento"
        onAccepted: root.selectedPath = folderDialog.selectedFolder.toString()
    }

    Rectangle { anchors.fill: parent; color: ThemeManager.background; Behavior on color { ColorAnimation { duration: 200 } } }

    ScrollView {
        id: formScroll
        anchors.fill: parent
        anchors.margins: 40
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: ScrollBar.AlwaysOn
        rightPadding: 6

        ColumnLayout {
        width: Math.max(formScroll.availableWidth, 980)
        spacing: 0

        // ── Header ───────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true; spacing: 10

            GhostButton { text: LanguageManager.tr3("<- Voltar", "<- Back", "<- Volver"); onClicked: root.backRequested() }
            Item { width: 8 }
            Text { text: "🧩"; font.pixelSize: 28; color: "#7a3dab" }

            ColumnLayout {
                spacing: 2
                Text {
                    text: LanguageManager.tr3("Configuracao do Experimento", "Experiment Setup", "Configuracion del Experimento")
                    color: ThemeManager.textPrimary
                    Behavior on color { ColorAnimation { duration: 150 } }
                    font.pixelSize: 22; font.weight: Font.Bold
                }
                Text {
                    text: LanguageManager.tr3("Comportamento Complexo", "Complex Behavior", "Comportamiento Complejo") + "  ·  " + root.numCampos + " " +
                          LanguageManager.tr3("campo", "field", "campo") + (root.numCampos > 1 ? "s" : "") +
                          (root.context !== "" && root.context !== "Padrão" ? "  ·  " + root.context : "")
                    color: ThemeManager.textSecondary
                    Behavior on color { ColorAnimation { duration: 150 } }
                    font.pixelSize: 13
                }
            }
        }

        Rectangle { Layout.fillWidth: true; Layout.topMargin: 18; height: 1; color: ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } } }

        Item { Layout.minimumHeight: 24 }

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
                        text: LanguageManager.tr3("NOME DO EXPERIMENTO", "EXPERIMENT NAME", "NOMBRE DEL EXPERIMENTO")
                        color: ThemeManager.textSecondary; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.5
                    }
                    TextField {
                        id: nameField
                        Layout.fillWidth: true
                        placeholderText: "Ex.: CC_Labirinto_GrupoA"
                        color: ThemeManager.textPrimary; placeholderTextColor: ThemeManager.textSecondary; font.pixelSize: 14
                        leftPadding: 14; rightPadding: 14; topPadding: 10; bottomPadding: 10
                        background: Rectangle {
                            radius: 8; color: ThemeManager.surfaceDim
                            Behavior on color { ColorAnimation { duration: 200 } }
                            border.color: nameField.activeFocus ? "#7a3dab" : ThemeManager.border; border.width: 1
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
                    placeholderText: LanguageManager.tr3("Padrao: Documentos/MindTrace_Data", "Default: Documents/MindTrace_Data", "Predeterminado: Documentos/MindTrace_Data")
                            color: ThemeManager.textPrimary; placeholderTextColor: ThemeManager.textSecondary; font.pixelSize: 14
                            leftPadding: 14; rightPadding: 14; topPadding: 10; bottomPadding: 10
                            background: Rectangle {
                                radius: 8; color: ThemeManager.surfaceDim
                                Behavior on color { ColorAnimation { duration: 200 } }
                                border.color: ThemeManager.border; border.width: 1
                            }
                        }
                        GhostButton { text: LanguageManager.tr3("Procurar...", "Browse...", "Buscar..."); onClicked: folderDialog.open() }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true; spacing: 8
                Text {
                    text: "RESPONSAVEL"
                    color: ThemeManager.textSecondary; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.5
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    ComboBox {
                        id: responsibleBox
                        Layout.fillWidth: false
                        Layout.preferredWidth: 520
                        Layout.maximumWidth: 520
                        model: ExperimentManager.researcherUsers
                        currentIndex: ExperimentManager.researcherUsers.indexOf(root.responsibleUsername)
                        onActivated: root.responsibleUsername = currentText
                        onCurrentTextChanged: {
                            if (currentIndex >= 0)
                                root.responsibleUsername = currentText
                        }
                        enabled: model.length > 0 && !root.responsibleUnknown
                        font.pixelSize: 14
                        implicitHeight: 44
                        contentItem: Text {
                            leftPadding: 14
                            rightPadding: 30
                            text: ExperimentManager.researcherFullName(responsibleBox.currentText)
                            color: ThemeManager.textPrimary
                            font: responsibleBox.font
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }
                        background: Rectangle {
                            radius: 8
                            color: ThemeManager.surfaceDim
                            border.color: responsibleBox.activeFocus ? "#7a3dab" : ThemeManager.border
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 200 } }
                            Behavior on border.color { ColorAnimation { duration: 150 } }
                        }
                        indicator: Text {
                            text: "▾"
                            color: ThemeManager.textSecondary
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            font.pixelSize: 14
                        }
                        delegate: ItemDelegate {
                            width: responsibleBox.width - 12
                            height: 40
                            highlighted: responsibleBox.highlightedIndex === index
                            contentItem: Text {
                                text: ExperimentManager.researcherFullName(modelData)
                                color: ThemeManager.textPrimary
                                font.pixelSize: 14
                                verticalAlignment: Text.AlignVCenter
                                leftPadding: 12
                                elide: Text.ElideRight
                            }
                            background: Rectangle {
                                radius: 8
                                color: parent.highlighted ? ThemeManager.surfaceAlt : ThemeManager.surfaceDim
                                border.color: ThemeManager.border
                                border.width: 1
                            }
                        }
                        popup: Popup {
                            y: responsibleBox.height + 6
                            width: responsibleBox.width
                            padding: 6
                            background: Rectangle {
                                radius: 10
                                color: ThemeManager.surface
                                border.color: ThemeManager.border
                                border.width: 1
                            }
                            contentItem: ListView {
                                clip: true
                                implicitHeight: Math.min(contentHeight, 220)
                                model: responsibleBox.popup.visible ? responsibleBox.delegateModel : null
                                currentIndex: responsibleBox.highlightedIndex
                                ScrollIndicator.vertical: ScrollIndicator { }
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        RowLayout {
                            spacing: 8

                            Rectangle {
                                id: unknownResponsibleToggle
                                width: 20; height: 20; radius: 5
                                color: root.responsibleUnknown ? "#7a3dab" : ThemeManager.surfaceDim
                                border.color: root.responsibleUnknown ? "#7a3dab" : ThemeManager.border
                                border.width: 1.5
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on border.color { ColorAnimation { duration: 150 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: "✓"
                                    color: ThemeManager.buttonText
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    visible: root.responsibleUnknown
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.responsibleUnknown = !root.responsibleUnknown
                                        if (root.responsibleUnknown) {
                                            root.responsibleUsername = "desconhecido"
                                        } else if (ExperimentManager.researcherUsers.length > 0) {
                                            root.responsibleUsername = ExperimentManager.researcherUsers[0]
                                        } else {
                                            root.responsibleUsername = ""
                                        }
                                    }
                                }
                            }

                            Text {
                                text: "Responsavel desconhecido"
                                color: ThemeManager.textPrimary
                                font.pixelSize: 13
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                        Text {
                            text: "Recomendado: informe um responsavel sempre que houver usuario disponivel."
                            color: "#d8c26a"; font.pixelSize: 11
                            wrapMode: Text.Wrap
                        }
                    }
                }
                Text {
                    text: root.responsibleUnknown
                          ? "Responsavel sera salvo como \"desconhecido\"."
                          : (ExperimentManager.researcherUsers.length === 0
                             ? "Nenhum pesquisador disponivel. Verifique MINDTRACE_SYNC_URL/MINDTRACE_SYNC_SECRET e usuarios nao-admin ativos."
                             : "Responsavel registrado no metadata e sincronizado no historico.")
                    color: ThemeManager.textTertiary; font.pixelSize: 11
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } } }

            // ── Duração da sessão ─────────────────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true; spacing: 12

                Text {
                    text: LanguageManager.tr3("DURACAO DA SESSAO", "SESSION DURATION", "DURACION DE LA SESION")
                    color: ThemeManager.textSecondary; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.5
                }

                RowLayout {
                    spacing: 12

                    Repeater {
                        model: [
                            {
                                min: 5,
                                label: LanguageManager.tr3("5 minutos", "5 minutes", "5 minutos"),
                                desc: LanguageManager.tr3("Protocolos curtos e habituacao", "Short protocols and habituation", "Protocolos cortos y habituacion")
                            },
                            {
                                min: 20,
                                label: LanguageManager.tr3("20 minutos", "20 minutes", "20 minutos"),
                                desc: LanguageManager.tr3("Labirinto, sociabilidade e exploracao prolongada", "Maze, sociability, and extended exploration", "Laberinto, sociabilidad y exploracion prolongada")
                            }
                        ]
                        delegate: Rectangle {
                            Layout.fillWidth: true; height: 64; radius: 10
                            property bool sel: root.sessionMinutes === modelData.min
                            color: sel ? "#1a0d2e" : (durHov.containsMouse ? ThemeManager.surfaceAlt : ThemeManager.surfaceDim)
                            border.color: sel ? "#7a3dab" : ThemeManager.border; border.width: sel ? 2 : 1
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on border.color { ColorAnimation { duration: 150 } }

                            RowLayout {
                                anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                                spacing: 12
                                Text { text: "⏱"; font.pixelSize: 20 }
                                ColumnLayout {
                                    spacing: 2
                                    Text { text: modelData.label; color: ThemeManager.textPrimary; font.pixelSize: 13; font.weight: Font.Bold }
                                    Text { text: modelData.desc;  color: ThemeManager.textSecondary; font.pixelSize: 11; wrapMode: Text.WordWrap }
                                }
                                Item { Layout.fillWidth: true }
                                Rectangle {
                                    width: 18; height: 18; radius: 9; color: "transparent"
                                    border.color: sel ? "#7a3dab" : ThemeManager.border; border.width: 2
                                    Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: "#7a3dab"; visible: sel }
                                }
                            }
                            MouseArea {
                                id: durHov; anchors.fill: parent
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: root.sessionMinutes = modelData.min
                            }
                        }
                    }
                }

                Text {
                    text: LanguageManager.tr3(
                              "Para videos offline: o tracking encerra no tempo escolhido, mesmo que o video seja mais longo.",
                              "For offline videos: tracking ends at the selected duration, even if the video is longer.",
                              "Para videos offline: el tracking termina en la duracion seleccionada, incluso si el video es mas largo."
                          )
                    color: ThemeManager.textTertiary; font.pixelSize: 10
                    Behavior on color { ColorAnimation { duration: 150 } }
                    wrapMode: Text.WordWrap; Layout.fillWidth: true
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } } }

            // ── Dias do experimento ────────────────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true; spacing: 8

                Text {
                    text: LanguageManager.tr3("DIAS DO EXPERIMENTO", "EXPERIMENT DAYS", "DIAS DEL EXPERIMENTO")
                    color: ThemeManager.textSecondary; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.5
                    Behavior on color { ColorAnimation { duration: 150 } }
                }

                ListModel {
                    id: dayNamesModel
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
                                    text: LanguageManager.tr3("Dia ", "Day ", "Dia ") + (index + 1) + ":"
                                    color: ThemeManager.textSecondary; font.pixelSize: 11
                                }
                                TextInput {
                                    id: dayNameInput
                                    text: model.dayName
                                    color: ThemeManager.textPrimary; font.pixelSize: 12; font.weight: Font.Bold
                                    width: Math.max(48, contentWidth + 4)
                                    selectByMouse: true
                                    onTextEdited: dayNamesModel.setProperty(index, "dayName", text)
                                    onEditingFinished: {
                                        var n = DayNameUtils.normalizeDayName(text)
                                        if (n !== text) text = n
                                        dayNamesModel.setProperty(index, "dayName", text)
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
                        Text { anchors.centerIn: parent; text: LanguageManager.tr3("+ Dia", "+ Day", "+ Dia"); color: ThemeManager.textSecondary; font.pixelSize: 12 }
                        MouseArea {
                            id: addDayHov; anchors.fill: parent
                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: dayNamesModel.append({ dayName: LanguageManager.tr3("Dia ", "Day ", "Dia ") + (dayNamesModel.count + 1) })
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } } }

            // ── Informação de layout ──────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true; height: 48; radius: 10
                color: ThemeManager.surfaceDim
                border.color: "#7a3dab"; border.width: 1

                RowLayout {
                    anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                    spacing: 12
                    Text { text: "🧩"; font.pixelSize: 20 }
                    ColumnLayout {
                        spacing: 2
                        Text {
                    text: root.numCampos + " " + LanguageManager.tr3("campo", "field", "campo") + (root.numCampos > 1 ? LanguageManager.tr3("s ativos", "s active", "s activos") : LanguageManager.tr3(" ativo", " active", " activo")) +
                                  "  ·  " + root.sessionMinutes + " min"
                            color: ThemeManager.textPrimary; font.pixelSize: 13; font.weight: Font.Bold
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                        Text {
                    text: LanguageManager.tr3("Metricas: distancia percorrida e velocidade", "Metrics: traveled distance and speed", "Metricas: distancia recorrida y velocidad")
                            color: ThemeManager.textTertiary; font.pixelSize: 11
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } } }

            // ── Opções ────────────────────────────────────────────────────
            RowLayout {
                spacing: 30

                // Tratamento
                RowLayout {
                    spacing: 12
                    Rectangle {
                        id: drugCheck
                        width: 20; height: 20; radius: 5
                        property bool checked: true
                        color:        checked ? "#7a3dab" : ThemeManager.surfaceDim
                        border.color: checked ? "#7a3dab" : ThemeManager.border; border.width: 1.5
                        Behavior on color        { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                        Text { anchors.centerIn: parent; text: "✓"; color: "white"; font.pixelSize: 11; font.weight: Font.Bold; visible: drugCheck.checked }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: drugCheck.checked = !drugCheck.checked }
                    }
                    ColumnLayout {
                        spacing: 2
                        Text { text: LanguageManager.tr3("Incluir coluna \"Tratamento\"", "Include \"Treatment\" column", "Incluir columna \"Tratamiento\""); color: ThemeManager.textPrimary; font.pixelSize: 13; font.weight: Font.Bold }
                        Text { text: LanguageManager.tr3("Para tratamentos farmacologicos.", "For pharmacological treatments.", "Para tratamientos farmacologicos."); color: ThemeManager.textTertiary; font.pixelSize: 11 }
                    }
                }

                // Zonas de Objetos — oculto para 1 campo (arena EI não tem objetos)
                RowLayout {
                    visible: root.numCampos > 1
                    spacing: 12
                    Rectangle {
                        id: objectZonesCheck
                        width: 20; height: 20; radius: 5
                        property bool checked: true
                        color:        checked ? "#7a3dab" : ThemeManager.surfaceDim
                        border.color: checked ? "#7a3dab" : ThemeManager.border; border.width: 1.5
                        Behavior on color        { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                        Text { anchors.centerIn: parent; text: "✓"; color: "white"; font.pixelSize: 11; font.weight: Font.Bold; visible: objectZonesCheck.checked }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: objectZonesCheck.checked = !objectZonesCheck.checked }
                    }
                    ColumnLayout {
                        spacing: 2
                        Text { text: "Sniffing"; color: ThemeManager.textPrimary; font.pixelSize: 13; font.weight: Font.Bold }
                        Text { text: LanguageManager.tr3("Habilita deteccao sniffing vs resting.", "Enables sniffing vs resting detection.", "Habilita deteccion sniffing vs resting."); color: ThemeManager.textTertiary; font.pixelSize: 11 }
                    }
                }
            }
        }

        Item { Layout.minimumHeight: 24 }

        // ── Rodapé ────────────────────────────────────────────────────────
        RowLayout {
            Layout.alignment: Qt.AlignHCenter; spacing: 24

            Text { text: LanguageManager.tr3("Passo 3 - Configuracao do Experimento", "Step 3 - Experiment Setup", "Paso 3 - Configuracion del Experimento"); color: ThemeManager.textSecondary; font.pixelSize: 11 }

            Button {
                text: LanguageManager.tr3("Criar Experimento ->", "Create Experiment ->", "Crear Experimento ->")
                enabled: nameField.text.trim().length > 0 && (root.responsibleUnknown || root.responsibleUsername.length > 0)

                onClicked: {
                    if (ExperimentManager.experimentExists(root.context, nameField.text.trim())) {
                        dupStep1Popup.open()
                    } else {
                        root.doCreate()
                    }
                }

                background: Rectangle {
                    radius: 8
                    color: parent.enabled ? (parent.hovered ? "#6a2d9a" : "#7a3dab") : "#2d2d4a"
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
                contentItem: Text {
                    text: parent.text; color: "white"
                    font.pixelSize: 13; font.weight: Font.Bold
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                }
                leftPadding: 24; rightPadding: 24; topPadding: 10; bottomPadding: 10
            }
        }

        Item { Layout.minimumHeight: 4 }
        }
    }

    // ── Popup duplicado — Passo 1 ─────────────────────────────────────────
    Popup {
        id: dupStep1Popup
        anchors.centerIn: parent; width: 400; height: 200
        modal: true; focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle { radius: 14; color: ThemeManager.surface; Behavior on color { ColorAnimation { duration: 200 } } border.color: "#7a3dab"; border.width: 1 }

        ColumnLayout {
            anchors { fill: parent; margins: 24 }
            spacing: 14
            Text { text: LanguageManager.tr3("Experimento ja existe", "Experiment already exists", "El experimento ya existe"); color: ThemeManager.textPrimary; font.pixelSize: 16; font.weight: Font.Bold }
            Text {
                Layout.fillWidth: true
                            text: LanguageManager.tr3("\"", "\"", "\"") + nameField.text.trim() + LanguageManager.tr3("\" already exists in this context.\n\nIf you continue, previous data will be overwritten.", "\" already exists in this context.\n\nIf you continue, previous data will be overwritten.", "\" ya existe en este contexto.\n\nSi continua, los datos anteriores seran sobrescritos.")
                color: ThemeManager.textSecondary; font.pixelSize: 13; wrapMode: Text.WordWrap
            }
            RowLayout {
                Layout.fillWidth: true; spacing: 10; Item { Layout.fillWidth: true }
                GhostButton { text: "Cancelar"; onClicked: dupStep1Popup.close() }
                Button {
                    text: "Continuar"
                    onClicked: { dupStep1Popup.close(); dupConfirmField.text = ""; dupStep2Popup.open() }
                    background: Rectangle { radius: 7; color: parent.hovered ? "#6a2d9a" : "#7a3dab"; Behavior on color { ColorAnimation { duration: 150 } } }
                    contentItem: Text { text: parent.text; color: "white"; font.pixelSize: 12; font.weight: Font.Bold; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
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
        background: Rectangle { radius: 14; color: ThemeManager.surface; Behavior on color { ColorAnimation { duration: 200 } } border.color: "#7a3dab"; border.width: 1 }

        ColumnLayout {
            anchors { fill: parent; margins: 24 }
            spacing: 14
            Text { text: LanguageManager.tr3("Confirmar Substituicao", "Confirm Overwrite", "Confirmar Sobrescritura"); color: ThemeManager.textPrimary; font.pixelSize: 16; font.weight: Font.Bold }
            Text { Layout.fillWidth: true; text: LanguageManager.tr3("Digite o nome do experimento para confirmar:", "Type the experiment name to confirm:", "Escriba el nombre del experimento para confirmar:"); color: ThemeManager.textSecondary; font.pixelSize: 13; wrapMode: Text.WordWrap }
            TextField {
                id: dupConfirmField; Layout.fillWidth: true
                placeholderText: nameField.text.trim()
                color: ThemeManager.textPrimary; placeholderTextColor: ThemeManager.textSecondary; font.pixelSize: 13
                leftPadding: 10; rightPadding: 10; topPadding: 8; bottomPadding: 8
                background: Rectangle { radius: 6; color: ThemeManager.surfaceDim; Behavior on color { ColorAnimation { duration: 200 } } border.color: dupConfirmField.activeFocus ? "#7a3dab" : ThemeManager.border; border.width: 1; Behavior on border.color { ColorAnimation { duration: 150 } } }
                Keys.onReturnPressed: { if (text === nameField.text.trim()) { dupStep2Popup.close(); root.doCreate() } }
            }
            RowLayout {
                Layout.fillWidth: true; spacing: 10; Item { Layout.fillWidth: true }
                GhostButton { text: "Cancelar"; onClicked: dupStep2Popup.close() }
                Button {
                    text: "Substituir"; enabled: dupConfirmField.text === nameField.text.trim()
                    onClicked: { dupStep2Popup.close(); root.doCreate() }
                    background: Rectangle { radius: 7; color: parent.enabled ? (parent.hovered ? "#6a2d9a" : "#7a3dab") : ThemeManager.surfaceDim; Behavior on color { ColorAnimation { duration: 150 } } }
                    contentItem: Text { text: parent.text; color: "white"; font.pixelSize: 12; font.weight: Font.Bold; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    leftPadding: 16; rightPadding: 16; topPadding: 8; bottomPadding: 8
                }
            }
        }
    }
}
