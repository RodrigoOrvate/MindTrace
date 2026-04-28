import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MindTrace.Tracking 1.0

Popup {
    id: settingsPopup

    property string selectedLanguage: LanguageManager.currentLanguage
    property var liveCameraOptions: []
    property int selectedLiveCameraIndex: -1
    property string selectedLiveInputType: "Composite"
    property string savedDefaultLiveCameraId: ""

    VideoInputEnumerator { id: settingsCameraProbe }

    function _cameraBaseName(cameraId) {
        var s = String(cameraId || "")
        var backendPos = s.toLowerCase().indexOf("|backend:")
        if (backendPos >= 0) s = s.substring(0, backendPos)
        var inputPos = s.toLowerCase().indexOf("|input:")
        if (inputPos >= 0) s = s.substring(0, inputPos)
        return s.replace(" [DirectShow]", "").trim()
    }

    function _cameraBackend(cameraId) {
        var s = String(cameraId || "")
        var low = s.toLowerCase()
        var idx = low.indexOf("|backend:")
        if (idx < 0) return ""
        var tail = s.substring(idx + 9)
        var sep = tail.indexOf("|")
        return (sep >= 0 ? tail.substring(0, sep) : tail).trim().toLowerCase()
    }

    function _cameraInput(cameraId) {
        var s = String(cameraId || "")
        var low = s.toLowerCase()
        var idx = low.indexOf("|input:")
        if (idx < 0) return "Composite"
        var tail = s.substring(idx + 7)
        var sep = tail.indexOf("|")
        var inp = (sep >= 0 ? tail.substring(0, sep) : tail).trim()
        return inp.length > 0 ? inp : "Composite"
    }

    function _selectedLiveCamera() {
        if (selectedLiveCameraIndex >= 0 && selectedLiveCameraIndex < liveCameraOptions.length)
            return liveCameraOptions[selectedLiveCameraIndex]
        return null
    }

    function _buildLiveCameraId(cam) {
        if (!cam) return ""
        if ((cam.backend || "qt") === "dshow") {
            if (cam.hasComposite || cam.hasSVideo || cam.isHauppauge)
                return cam.name + " |backend:dshow |input:" + selectedLiveInputType
            return cam.name + " |backend:dshow"
        }
        return cam.name + " |backend:qt"
    }

    function refreshLiveCameraOptions() {
        var list = settingsCameraProbe.listVideoInputs()
        liveCameraOptions = list || []
        savedDefaultLiveCameraId = String(ThemeSettings.loadVariant("defaultLiveCameraId", "") || "")

        selectedLiveCameraIndex = liveCameraOptions.length > 0 ? 0 : -1
        selectedLiveInputType = _cameraInput(savedDefaultLiveCameraId)

        if (savedDefaultLiveCameraId !== "") {
            var wantBase = _cameraBaseName(savedDefaultLiveCameraId).toLowerCase()
            var wantBackend = _cameraBackend(savedDefaultLiveCameraId)
            for (var cameraIdx = 0; cameraIdx < liveCameraOptions.length; cameraIdx++) {
                var cam = liveCameraOptions[cameraIdx]
                var cBase = _cameraBaseName(cam.name || "").toLowerCase()
                var cBackend = String(cam.backend || "").toLowerCase()
                if (cBase === wantBase && (wantBackend === "" || cBackend === wantBackend)) {
                    selectedLiveCameraIndex = cameraIdx
                    break
                }
            }
        }
    }

    modal: true
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    width: Math.min(parent.width - 60, 520)
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
    onOpened: refreshLiveCameraOptions()

    background: Rectangle {
        color: ThemeManager.surface
        border.color: ThemeManager.border
        border.width: 1
        radius: 8
        Behavior on color { ColorAnimation { duration: 200 } }
        Behavior on border.color { ColorAnimation { duration: 200 } }
    }

    contentItem: ColumnLayout {
        anchors.margins: 24
        spacing: 16

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Text {
                text: LanguageManager.tr3("Configuracoes", "Settings", "Configuracion")
                color: ThemeManager.textPrimary
                font.pixelSize: 20
                font.weight: Font.Bold
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            Item { Layout.fillWidth: true }

            Button {
                text: "X"
                flat: true
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                contentItem: Text {
                    text: parent.text
                    color: ThemeManager.textSecondary
                    font.pixelSize: 16
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
                background: Rectangle {
                    color: parent.hovered ? ThemeManager.surfaceAlt : "transparent"
                    radius: 4
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
                onClicked: settingsPopup.close()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: ThemeManager.border
            Behavior on color { ColorAnimation { duration: 200 } }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: generalBlock.implicitHeight + 24
            radius: 8
            color: ThemeManager.surfaceDim
            border.color: ThemeManager.borderLight
            border.width: 1
            Behavior on color { ColorAnimation { duration: 150 } }
            Behavior on border.color { ColorAnimation { duration: 150 } }

            ColumnLayout {
                id: generalBlock
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 12
                spacing: 10

                Text {
                    text: LanguageManager.tr3("Geral", "General", "General")
                    color: ThemeManager.textSecondary
                    font.pixelSize: 11
                    font.weight: Font.Bold
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16

                    Text {
                        text: LanguageManager.tr3("Tema", "Theme", "Tema")
                        color: ThemeManager.textPrimary
                        font.pixelSize: 14
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        Layout.preferredWidth: 60
                        Layout.preferredHeight: 32
                        radius: 16
                        color: ThemeManager.isDarkMode ? ThemeManager.accent : ThemeManager.surfaceAlt
                        border.color: ThemeManager.border
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 200 } }
                        Behavior on border.color { ColorAnimation { duration: 200 } }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ThemeManager.toggleTheme()
                        }

                        Rectangle {
                            id: toggle
                            width: 28
                            height: 28
                            radius: 14
                            color: ThemeManager.textPrimary
                            y: (parent.height - height) / 2
                            Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }

                        states: [
                            State {
                                name: "dark"
                                when: ThemeManager.isDarkMode
                                PropertyChanges { target: toggle; x: 2 }
                            },
                            State {
                                name: "light"
                                when: !ThemeManager.isDarkMode
                                PropertyChanges { target: toggle; x: parent.width - toggle.width - 2 }
                            }
                        ]
                    }

                    Text {
                        text: ThemeManager.isDarkMode
                            ? LanguageManager.tr3("Escuro", "Dark", "Oscuro")
                            : LanguageManager.tr3("Claro", "Light", "Claro")
                        color: ThemeManager.textSecondary
                        font.pixelSize: 13
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: ThemeManager.border
                    Behavior on color { ColorAnimation { duration: 150 } }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Text {
                        text: LanguageManager.tr3("Idioma", "Language", "Idioma")
                        color: ThemeManager.textPrimary
                        font.pixelSize: 14
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    Item { Layout.fillWidth: true }

                    ComboBox {
                        id: languageCombo
                        Layout.preferredWidth: 210
                        model: LanguageManager.supportedLanguages
                        textRole: "label"
                        valueRole: "code"
                        implicitHeight: 34

                        delegate: ItemDelegate {
                            width: languageCombo.width
                            text: modelData.label
                            highlighted: languageCombo.highlightedIndex === index
                            background: Rectangle {
                                color: parent.highlighted ? ThemeManager.surfaceHover : ThemeManager.surface
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }
                            contentItem: Text {
                                text: parent.text
                                color: ThemeManager.textPrimary
                                font.pixelSize: 12
                                elide: Text.ElideRight
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        indicator: Canvas {
                            x: languageCombo.width - width - 10
                            y: (languageCombo.height - height) / 2
                            width: 10
                            height: 6
                            contextType: "2d"
                            onPaint: {
                                context.reset()
                                context.moveTo(0, 0)
                                context.lineTo(width, 0)
                                context.lineTo(width / 2, height)
                                context.closePath()
                                context.fillStyle = ThemeManager.textSecondary
                                context.fill()
                            }
                        }

                        contentItem: Text {
                            leftPadding: 10
                            rightPadding: languageCombo.indicator.width + 16
                            text: languageCombo.displayText
                            color: ThemeManager.textPrimary
                            font.pixelSize: 12
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                        }

                        background: Rectangle {
                            radius: 6
                            color: ThemeManager.surfaceDim
                            border.width: 1
                            border.color: languageCombo.popup.visible ? ThemeManager.accent : ThemeManager.borderLight
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on border.color { ColorAnimation { duration: 150 } }
                        }

                        popup: Popup {
                            y: languageCombo.height + 4
                            width: languageCombo.width
                            implicitHeight: contentItem.implicitHeight
                            padding: 1
                            background: Rectangle {
                                radius: 6
                                color: ThemeManager.surface
                                border.color: ThemeManager.border
                                border.width: 1
                            }
                            contentItem: ListView {
                                clip: true
                                implicitHeight: contentHeight
                                model: languageCombo.popup.visible ? languageCombo.delegateModel : null
                                currentIndex: languageCombo.highlightedIndex
                                ScrollIndicator.vertical: ScrollIndicator { }
                            }
                        }

                        Component.onCompleted: {
                            for (var langIdx = 0; langIdx < model.length; langIdx++) {
                                if (model[langIdx].code === settingsPopup.selectedLanguage) {
                                    currentIndex = langIdx
                                    break
                                }
                            }
                        }

                        onActivated: {
                            if (currentIndex >= 0 && currentIndex < model.length)
                                settingsPopup.selectedLanguage = model[currentIndex].code
                        }
                    }

                    Button {
                        text: LanguageManager.tr3("Aplicar", "Apply", "Aplicar")
                        enabled: settingsPopup.selectedLanguage !== LanguageManager.currentLanguage
                        onClicked: LanguageManager.setLanguage(settingsPopup.selectedLanguage)
                        background: Rectangle {
                            radius: 6
                            color: parent.enabled
                                ? (parent.hovered ? ThemeManager.accentHover : ThemeManager.accent)
                                : ThemeManager.surfaceDim
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                        contentItem: Text {
                            text: parent.text
                            color: "#ffffff"
                            font.pixelSize: 12
                            font.weight: Font.Bold
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: cameraBlock.implicitHeight + 24
            radius: 8
            color: ThemeManager.surfaceDim
            border.color: ThemeManager.borderLight
            border.width: 1
            Behavior on color { ColorAnimation { duration: 150 } }
            Behavior on border.color { ColorAnimation { duration: 150 } }

            ColumnLayout {
                id: cameraBlock
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 12
                spacing: 10

                Text {
                    text: LanguageManager.tr3("Video", "Video", "Video")
                    color: ThemeManager.textSecondary
                    font.pixelSize: 11
                    font.weight: Font.Bold
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Text {
                        text: LanguageManager.tr3("Camera Padrao (Ao Vivo)", "Default Camera (Live)", "Camara Predeterminada (En Vivo)")
                        color: ThemeManager.textPrimary
                        font.pixelSize: 14
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    Item { Layout.fillWidth: true }

                    Button {
                        text: LanguageManager.tr3("Atualizar", "Refresh", "Actualizar")
                        onClicked: refreshLiveCameraOptions()
                        background: Rectangle {
                            radius: 6
                            color: parent.hovered ? ThemeManager.surfaceAlt : ThemeManager.surfaceDim
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                        contentItem: Text {
                            text: parent.text
                            color: ThemeManager.textPrimary
                            font.pixelSize: 12
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }

                ComboBox {
                    id: defaultLiveCameraCombo
                    Layout.fillWidth: true
                    model: settingsPopup.liveCameraOptions
                    textRole: "name"
                    valueRole: "name"
                    enabled: model.length > 0
                    currentIndex: settingsPopup.selectedLiveCameraIndex
                    onActivated: settingsPopup.selectedLiveCameraIndex = currentIndex

                    background: Rectangle {
                        radius: 6
                        color: ThemeManager.surfaceDim
                        border.width: 1
                        border.color: defaultLiveCameraCombo.popup.visible ? ThemeManager.accent : ThemeManager.borderLight
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                    }

                    contentItem: Text {
                        leftPadding: 10
                        rightPadding: 26
                        text: defaultLiveCameraCombo.currentText
                        color: ThemeManager.textPrimary
                        font.pixelSize: 13
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }

                    delegate: ItemDelegate {
                        width: defaultLiveCameraCombo.width
                        height: 38
                        highlighted: defaultLiveCameraCombo.highlightedIndex === index
                        property string cameraLabel: (typeof modelData === "string")
                                                     ? modelData
                                                     : (modelData.name || "")
                        contentItem: Text {
                            text: parent.cameraLabel
                            color: parent.highlighted ? ThemeManager.buttonText : ThemeManager.textPrimary
                            font.pixelSize: 13
                            verticalAlignment: Text.AlignVCenter
                            leftPadding: 10
                            rightPadding: 10
                            elide: Text.ElideRight
                        }
                        background: Rectangle {
                            radius: 6
                            color: parent.highlighted ? ThemeManager.accent : ThemeManager.surfaceDim
                            border.color: parent.highlighted ? ThemeManager.accentHover : ThemeManager.borderLight
                            border.width: 1
                        }
                    }

                    popup: Popup {
                        y: defaultLiveCameraCombo.height + 6
                        width: defaultLiveCameraCombo.width
                        padding: 6
                        background: Rectangle {
                            radius: 10
                            color: ThemeManager.surface
                            border.color: ThemeManager.border
                            border.width: 1
                        }
                        contentItem: ListView {
                            clip: true
                            implicitHeight: Math.min(contentHeight, 240)
                            model: defaultLiveCameraCombo.popup.visible ? defaultLiveCameraCombo.delegateModel : null
                            currentIndex: defaultLiveCameraCombo.highlightedIndex
                            ScrollIndicator.vertical: ScrollIndicator { }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    visible: {
                        var cam = settingsPopup._selectedLiveCamera()
                        return cam && cam.backend === "dshow" && (cam.hasComposite || cam.hasSVideo || cam.isHauppauge)
                    }

                    Text {
                        text: LanguageManager.tr3("Entrada", "Input", "Entrada")
                        color: ThemeManager.textSecondary
                        font.pixelSize: 12
                    }

                    ComboBox {
                        id: defaultLiveInputCombo
                        Layout.preferredWidth: 180
                        model: {
                            var cam = settingsPopup._selectedLiveCamera()
                            var opts = []
                            if (cam && cam.hasComposite) opts.push("Composite")
                            if (cam && cam.hasSVideo) opts.push("S-Video")
                            if (opts.length === 0) {
                                opts.push("Composite")
                                opts.push("S-Video")
                            }
                            return opts
                        }
                        currentIndex: Math.max(0, model.indexOf(settingsPopup.selectedLiveInputType))
                        onActivated: settingsPopup.selectedLiveInputType = currentText

                        background: Rectangle {
                            radius: 6
                            color: ThemeManager.surfaceDim
                            border.width: 1
                            border.color: defaultLiveInputCombo.popup.visible ? ThemeManager.accent : ThemeManager.borderLight
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on border.color { ColorAnimation { duration: 150 } }
                        }

                        contentItem: Text {
                            leftPadding: 10
                            rightPadding: 26
                            text: defaultLiveInputCombo.currentText
                            color: ThemeManager.textPrimary
                            font.pixelSize: 13
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }

                        delegate: ItemDelegate {
                            width: defaultLiveInputCombo.width
                            height: 36
                            highlighted: defaultLiveInputCombo.highlightedIndex === index
                            contentItem: Text {
                                text: modelData
                                color: parent.highlighted ? ThemeManager.buttonText : ThemeManager.textPrimary
                                font.pixelSize: 13
                                verticalAlignment: Text.AlignVCenter
                                leftPadding: 10
                                rightPadding: 10
                                elide: Text.ElideRight
                            }
                            background: Rectangle {
                                radius: 6
                                color: parent.highlighted ? ThemeManager.accent : ThemeManager.surfaceDim
                                border.color: parent.highlighted ? ThemeManager.accentHover : ThemeManager.borderLight
                                border.width: 1
                            }
                        }

                        popup: Popup {
                            y: defaultLiveInputCombo.height + 6
                            width: defaultLiveInputCombo.width
                            padding: 6
                            background: Rectangle {
                                radius: 10
                                color: ThemeManager.surface
                                border.color: ThemeManager.border
                                border.width: 1
                            }
                            contentItem: ListView {
                                clip: true
                                implicitHeight: Math.min(contentHeight, 180)
                                model: defaultLiveInputCombo.popup.visible ? defaultLiveInputCombo.delegateModel : null
                                currentIndex: defaultLiveInputCombo.highlightedIndex
                                ScrollIndicator.vertical: ScrollIndicator { }
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        Layout.fillWidth: true
                        text: settingsPopup.savedDefaultLiveCameraId !== ""
                              ? (LanguageManager.tr3("Padrao atual: ", "Current default: ", "Predeterminada actual: ") + settingsPopup.savedDefaultLiveCameraId)
                              : LanguageManager.tr3("Sem camera padrao configurada.", "No default camera configured.", "Sin camara predeterminada configurada.")
                        color: ThemeManager.textTertiary
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }

                    Button {
                        text: LanguageManager.tr3("Salvar Padrao", "Save Default", "Guardar Predeterminada")
                        enabled: settingsPopup._selectedLiveCamera() !== null
                        onClicked: {
                            var cam = settingsPopup._selectedLiveCamera()
                            var id = settingsPopup._buildLiveCameraId(cam)
                            ThemeSettings.saveVariant("defaultLiveCameraId", id)
                            settingsPopup.savedDefaultLiveCameraId = id
                        }
                        background: Rectangle {
                            radius: 6
                            color: parent.enabled ? (parent.hovered ? ThemeManager.accentHover : ThemeManager.accent) : ThemeManager.surfaceDim
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                        contentItem: Text {
                            text: parent.text
                            color: "#ffffff"
                            font.pixelSize: 12
                            font.weight: Font.Bold
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    Button {
                        text: LanguageManager.tr3("Limpar", "Clear", "Limpiar")
                        onClicked: {
                            ThemeSettings.saveVariant("defaultLiveCameraId", null)
                            settingsPopup.savedDefaultLiveCameraId = ""
                        }
                        background: Rectangle {
                            radius: 6
                            color: parent.hovered ? ThemeManager.surfaceAlt : ThemeManager.surfaceDim
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                        contentItem: Text {
                            text: parent.text
                            color: ThemeManager.textPrimary
                            font.pixelSize: 12
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: ThemeManager.border
            Behavior on color { ColorAnimation { duration: 200 } }
        }

        Text {
            Layout.fillWidth: true
            text: LanguageManager.tr3(
                "Tema e idioma sao salvos automaticamente. A traducao sera expandida nas proximas telas.",
                "Theme and language are saved automatically. Translation coverage will be expanded across screens.",
                "Tema e idioma se guardan automaticamente. La traduccion se ampliara en las proximas pantallas."
            )
            color: ThemeManager.textTertiary
            font.pixelSize: 12
            wrapMode: Text.WordWrap
            Behavior on color { ColorAnimation { duration: 150 } }
        }

        Item { Layout.fillHeight: true; Layout.minimumHeight: 8 }

        Button {
            Layout.fillWidth: true
            text: LanguageManager.tr3("Fechar", "Close", "Cerrar")
            height: 36

            background: Rectangle {
                color: parent.hovered ? ThemeManager.accentHover : ThemeManager.accent
                radius: 6
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            contentItem: Text {
                text: parent.text
                color: "#ffffff"
                font.pixelSize: 13
                font.weight: Font.Bold
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            onClicked: settingsPopup.close()
        }
    }
}
