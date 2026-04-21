import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Popup {
    id: settingsPopup

    property string selectedLanguage: LanguageManager.currentLanguage

    modal: true
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    width: Math.min(parent.width - 60, 520)
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

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
                    for (var i = 0; i < model.length; i++) {
                        if (model[i].code === settingsPopup.selectedLanguage) {
                            currentIndex = i
                            break
                        }
                    }
                }

                onActivated: {
                    if (currentIndex >= 0 && currentIndex < model.length) {
                        settingsPopup.selectedLanguage = model[currentIndex].code
                    }
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
