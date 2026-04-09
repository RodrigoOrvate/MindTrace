import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Popup {
    id: settingsPopup
    modal: true
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    width: Math.min(parent.width - 60, 500)
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
        spacing: 20

        // ── HEADER ────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Text {
                text: "⚙️  Configurações"
                color: ThemeManager.textPrimary
                font.pixelSize: 20
                font.weight: Font.Bold
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            Item { Layout.fillWidth: true }

            // Close button (X)
            Button {
                text: "✕"
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

        // ── THEME TOGGLE ──────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            Text {
                text: "Tema"
                color: ThemeManager.textPrimary
                font.pixelSize: 14
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            Item { Layout.fillWidth: true }

            // ── Toggle Button ──────────────────────────────────────────
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

                // Animated circle indicator
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

                // Moon and sun icons overlays
                Item {
                    anchors.fill: parent
                    
                    Text {
                        anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                        text: "🌙"
                        font.pixelSize: 12
                        opacity: ThemeManager.isDarkMode ? 1.0 : 0.3
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                    }
                    
                    Text {
                        anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                        text: "☀️"
                        font.pixelSize: 12
                        opacity: !ThemeManager.isDarkMode ? 1.0 : 0.3
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                    }
                }
            }

            Text {
                text: ThemeManager.isDarkMode ? "Escuro" : "Claro"
                color: ThemeManager.textSecondary
                font.pixelSize: 13
                Behavior on color { ColorAnimation { duration: 150 } }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: ThemeManager.border
            Behavior on color { ColorAnimation { duration: 200 } }
        }

        // ── INFO ───────────────────────────────────────────────────────
        Text {
            Layout.fillWidth: true
            text: "O tema será aplicado imediatamente em todas as telas."
            color: ThemeManager.textTertiary
            font.pixelSize: 12
            wrapMode: Text.WordWrap
            Behavior on color { ColorAnimation { duration: 150 } }
        }

        Item { Layout.fillHeight: true; Layout.minimumHeight: 8 }

        // ── CLOSE BUTTON ───────────────────────────────────────────────
        Button {
            Layout.fillWidth: true
            text: "Fechar"
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
