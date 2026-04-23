// qml/shared/AnimalSearchField.qml
// Searchable animal picker: debounced query + last-5 recents on focus.
// Dropdown attaches to Overlay.overlay so it is never clipped by parent Popups.
// Emits picked(internalId, dbId) on selection; falls back to manual typing if API is offline.

import QtQuick
import QtQuick.Controls
import QtCore
import "../core/Theme"
import MindTrace.Backend 1.0

Item {
    id: root

    // ── Public ────────────────────────────────────────────────────────────
    property string apiBase:     "http://localhost:8000"
    property string accentColor: "#1f4f7c"

    readonly property string internalId:  _selId
    readonly property int    animalDbId:  _selDbId

    signal picked(string internalId, int dbId)
    signal textEdited(string text)     // fires on every manual keystroke (no dropdown selection)

    // ── Internal ──────────────────────────────────────────────────────────
    property string _selId:      ""
    property int    _selDbId:    -1
    property bool   _isSelected: false
    property var    _results:    []
    property int    _hilightIdx: -1

    implicitWidth:  200
    implicitHeight: 30

    // ── Recent animals (persisted across sessions) ─────────────────────────
    Settings {
        id: store
        category: "AnimalPicker"
        property string recents: "[]"
    }

    property var _recents: []

    Component.onCompleted: {
        try { root._recents = JSON.parse(store.recents) } catch(e) { root._recents = [] }
    }

    function _saveRecent(a) {
        var arr = root._recents.filter(function(r) { return r.id !== a.id })
        arr.unshift({ id: a.id, internal_id: a.internal_id, status: a.status || "active", sex: a.sex || "unknown" })
        root._recents = arr.slice(0, 5)
        store.recents = JSON.stringify(root._recents)
    }

    // ── Core logic ────────────────────────────────────────────────────────
    function _openDropdown() {
        if (root._results.length === 0) return
        var pt = root.mapToItem(Overlay.overlay, 0, root.height + 2)
        dropdown.x = pt.x
        dropdown.y = pt.y
        dropdown.width = Math.max(root.width, 260)
        if (!dropdown.visible) dropdown.open()
    }

    function _showRecents() {
        if (root._recents.length === 0) return
        root._results = root._recents.slice()
        root._hilightIdx = -1
        _openDropdown()
    }

    function _select(animal) {
        root._selId      = animal.internal_id
        root._selDbId    = animal.id
        root._isSelected = true
        root._results    = []
        root._hilightIdx = -1
        dropdown.close()
        _saveRecent(animal)
        root.picked(animal.internal_id, animal.id)
    }

    function clear() {
        root._selId      = ""
        root._selDbId    = -1
        root._isSelected = false
        searchField.text = ""
        dropdown.close()
    }

    // ── Debounce timer ────────────────────────────────────────────────────
    Timer {
        id: debounce
        interval: 280
        onTriggered: _search(searchField.text.trim())
    }

    function _search(q) {
        if (!q) { _showRecents(); return }
        var ts = ExperimentManager.syncTimestamp()
        var sig = ExperimentManager.syncSignature(ts, "")
        if (!ts || !sig) { dropdown.close(); return }
        var xhr = new XMLHttpRequest()
        xhr.open("GET", root.apiBase + "/sync/mindtrace/animals?status=active&q=" + encodeURIComponent(q))
        xhr.setRequestHeader("X-MindTrace-Timestamp", ts)
        xhr.setRequestHeader("X-MindTrace-Signature", sig)
        xhr.setRequestHeader("X-MindTrace-Client", "mindtrace-qt")
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status === 200) {
                try {
                    root._results    = JSON.parse(xhr.responseText).slice(0, 7)
                    root._hilightIdx = -1
                    if (root._results.length > 0) _openDropdown()
                    else dropdown.close()
                } catch(e) { dropdown.close() }
            } else { dropdown.close() }
        }
        xhr.send()
    }

    // ── Selected-chip view ────────────────────────────────────────────────
    Rectangle {
        visible: root._isSelected
        anchors.fill: parent
        radius: 7
        color: "transparent"
        border.color: root.accentColor; border.width: 1.5

        Rectangle {
            anchors.fill: parent; radius: parent.radius
            color: root.accentColor; opacity: 0.1
        }

        Text {
            anchors { left: parent.left; leftMargin: 10; right: clearBtn.left; rightMargin: 2; verticalCenter: parent.verticalCenter }
            text: root._selId
            font.pixelSize: 12; font.weight: Font.Bold; font.family: "monospace"
            color: root.accentColor
            elide: Text.ElideRight
        }

        Rectangle {
            id: clearBtn
            anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
            width: 22; height: 22; radius: 11
            color: clearHover.containsMouse ? "#22dc2626" : "transparent"
            Text {
                anchors.centerIn: parent
                text: "×"
                font.pixelSize: 14; font.weight: Font.Bold
                color: ThemeManager.textSecondary
            }
            MouseArea {
                id: clearHover
                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: root.clear()
            }
        }
    }

    // ── Search field ──────────────────────────────────────────────────────
    TextField {
        id: searchField
        visible: !root._isSelected
        anchors.fill: parent
        placeholderText: LanguageManager.tr3("Buscar animal...", "Search animal...", "Buscar animal...")
        color: ThemeManager.textPrimary
        placeholderTextColor: ThemeManager.textTertiary
        font.pixelSize: 12
        leftPadding: 10; rightPadding: 10; topPadding: 6; bottomPadding: 6

        background: Rectangle {
            radius: 7; color: ThemeManager.surface
            Behavior on color { ColorAnimation { duration: 200 } }
            border.color: searchField.activeFocus ? root.accentColor : ThemeManager.border
            border.width:  searchField.activeFocus ? 1.5 : 1
            Behavior on border.color { ColorAnimation { duration: 150 } }
        }

        onTextChanged: {
            if (!root._isSelected) {
                root._hilightIdx = -1
                debounce.restart()
                root.textEdited(text)
            }
        }
        onActiveFocusChanged: {
            if (activeFocus && !root._isSelected && text.trim() === "")
                Qt.callLater(root._showRecents)
        }

        Keys.onUpPressed:     { if (root._hilightIdx > 0) root._hilightIdx-- }
        Keys.onDownPressed:   { if (root._hilightIdx < root._results.length - 1) root._hilightIdx++ }
        Keys.onReturnPressed: {
            if (root._hilightIdx >= 0 && root._hilightIdx < root._results.length)
                root._select(root._results[root._hilightIdx])
        }
        Keys.onEscapePressed: dropdown.close()
    }

    // ── Dropdown (Overlay-parented to avoid clip) ─────────────────────────
    Popup {
        id: dropdown
        parent: Overlay.overlay
        padding: 0
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle {
            radius: 8; color: ThemeManager.surface
            border.color: root.accentColor; border.width: 1
            Behavior on color { ColorAnimation { duration: 200 } }
        }

        contentItem: Column {
            spacing: 0

            // "Recentes" header — only when field is empty
            Text {
                visible: searchField.text.trim() === "" && root._recents.length > 0
                text: LanguageManager.tr3("  Recentes", "  Recent", "  Recientes")
                font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 1.2
                color: ThemeManager.textSecondary
                leftPadding: 12; topPadding: 8; bottomPadding: 4
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            Repeater {
                model: root._results
                delegate: Rectangle {
                    width:  dropdown.width
                    height: 40
                    color: (root._hilightIdx === index || rowMouse.containsMouse)
                           ? Qt.alpha(root.accentColor, 0.1) : "transparent"
                    Behavior on color { ColorAnimation { duration: 80 } }

                    Row {
                        anchors {
                            left: parent.left; right: statusDot.left; rightMargin: 8
                            verticalCenter: parent.verticalCenter
                        }
                        leftPadding: 12; spacing: 8

                        Text {
                            text: modelData.internal_id
                            font.pixelSize: 13; font.weight: Font.Bold; font.family: "monospace"
                            color: ThemeManager.textPrimary
                            anchors.verticalCenter: parent.verticalCenter
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            height: 18; width: sexLbl.implicitWidth + 10; radius: 9
                            color: Qt.alpha(root.accentColor, 0.15)
                            Text {
                                id: sexLbl
                                anchors.centerIn: parent
                                text: modelData.sex === "male"   ? "♂ M" :
                                      modelData.sex === "female" ? "♀ F" : "?"
                                font.pixelSize: 10; font.weight: Font.Bold
                                color: root.accentColor
                            }
                        }
                    }

                    // Active / inactive dot
                    Rectangle {
                        id: statusDot
                        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        width: 8; height: 8; radius: 4
                        color: modelData.status === "active" ? "#16a34a" : "#94a3b8"
                    }

                    // Row separator
                    Rectangle {
                        visible: index < root._results.length - 1
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 12; rightMargin: 12 }
                        height: 1; color: ThemeManager.border; opacity: 0.5
                    }

                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onEntered: root._hilightIdx = index
                        onClicked: root._select(modelData)
                    }
                }
            }

            // No results
            Text {
                visible: root._results.length === 0 && searchField.text.trim().length > 0
                text: LanguageManager.tr3("Nenhum animal encontrado", "No animals found", "Ningun animal encontrado")
                color: ThemeManager.textSecondary; font.pixelSize: 12
                padding: 14; leftPadding: 14
            }
        }
    }
}
