// qml/shared/NORDataView.qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../core"
import "../core/Theme"
import MindTrace.Backend 1.0

Item {
    id: root

    property alias tableModel: placeholder.model
    property alias workArea: placeholder.workArea

    readonly property color accentColor: "#ab3d4c"
    readonly property color rowEven: ThemeManager.surfaceDim
    readonly property color rowOdd:  ThemeManager.surface

    // ── Mapa reativo de colunas ─────────────────────────────────────
    property var colMap: ({})

    function buildColMap() {
        var map = {}
        if (!tableModel) return map
        for (var i = 0; i < tableModel.columnCount(); i++)
            map[String(tableModel.headerData(i, Qt.Horizontal, Qt.DisplayRole)).trim()] = i
        return map
    }

    function colOf(name) { return colMap.hasOwnProperty(name) ? colMap[name] : -1 }
    function colOfAny(names) {
        for (var i = 0; i < names.length; i++) {
            var idx = colOf(names[i])
            if (idx >= 0) return idx
        }
        return -1
    }
    function cellOf(row, name) {
        var idx = colOf(name)
        return (idx >= 0 && tableModel) ? (tableModel.data(tableModel.index(row, idx), Qt.DisplayRole) || "") : ""
    }
    function cellAny(row, names) {
        var idx = colOfAny(names)
        return (idx >= 0 && tableModel) ? (tableModel.data(tableModel.index(row, idx), Qt.DisplayRole) || "") : ""
    }
    function hasTreatment() { return colOfAny(["Tratamento", "Treatment", "Tratamiento"]) >= 0 }

    Connections {
        target: tableModel
        function onModelReset()    { root.colMap = root.buildColMap() }
        function onRowsInserted()  { root.colMap = root.buildColMap() }
    }
    onTableModelChanged: root.colMap = root.buildColMap()

    ColumnLayout {
        anchors { fill: parent; margins: 24 }
        spacing: 16

        RowLayout {
            spacing: 8
            BusyIndicator { visible: tableModel && tableModel.fetchingMore; running: visible; implicitWidth: 20; implicitHeight: 20 }
            Text {
                text: tableModel && tableModel.rowCount() > 0
                      ? tableModel.rowCount() + " registro(s) · Exporte para ver métricas detalhadas"
                      : LanguageManager.tr3("Sem dados registrados", "No data recorded", "Sin datos registrados")
                color: ThemeManager.textTertiary; font.pixelSize: 11
                Behavior on color { ColorAnimation { duration: 150 } }
            }
            Item { Layout.fillWidth: true }
        }

        ScrollView {
            Layout.fillWidth: true; Layout.fillHeight: true
            contentWidth: headerRow.implicitWidth
            contentHeight: tableLayout.implicitHeight

            ColumnLayout {
                id: tableLayout
                width: Math.max(parent.width, headerRow.implicitWidth)
                spacing: 0

                // ── Cabeçalho ─────────────────────────────────────
                RowLayout {
                    id: headerRow
                    Layout.fillWidth: true; spacing: 1

                    Rectangle { Layout.preferredWidth: 140; height: 40; color: accentColor
                        Text { anchors.fill: parent; anchors.margins: 8; text: "Vídeo"
                            color: "white"; font.weight: Font.Bold; font.pixelSize: 11; elide: Text.ElideRight } }
                    Rectangle { Layout.preferredWidth: 90; height: 40; color: accentColor
                        Text { anchors.centerIn: parent; text: LanguageManager.tr3("Animal", "Animal", "Animal")
                            color: "white"; font.weight: Font.Bold; font.pixelSize: 11 } }
                    Rectangle { Layout.preferredWidth: 130; height: 40; color: accentColor
                        Text { anchors.centerIn: parent; text: LanguageManager.tr3("Object Pair", "Object Pair", "Par de Objetos")
                            color: "white"; font.weight: Font.Bold; font.pixelSize: 11 } }
                    Rectangle { Layout.preferredWidth: 70; height: 40; color: accentColor
                        Text { anchors.centerIn: parent; text: LanguageManager.tr3("Campo", "Field", "Campo")
                            color: "white"; font.weight: Font.Bold; font.pixelSize: 11 } }
                    Rectangle { Layout.preferredWidth: 90; height: 40; color: accentColor
                        Text { anchors.centerIn: parent; text: LanguageManager.tr3("Dia", "Day", "Dia")
                            color: "white"; font.weight: Font.Bold; font.pixelSize: 11 } }
                    Rectangle {
                        visible: hasTreatment()
                        Layout.fillWidth: true; Layout.minimumWidth: 90; height: 40; color: accentColor
                        Text { anchors.centerIn: parent; text: LanguageManager.tr3("Tratamento", "Treatment", "Tratamiento")
                            color: "white"; font.weight: Font.Bold; font.pixelSize: 11 } }
                    Item { visible: !hasTreatment(); Layout.fillWidth: true }
                }

                // ── Dados ─────────────────────────────────────────
                Repeater {
                    model: tableModel
                    delegate: RowLayout {
                        id: dataRow
                        required property int index
                        Layout.fillWidth: true; spacing: 1
                        readonly property color rowBg: index % 2 === 0 ? rowEven : rowOdd

                        Rectangle { Layout.preferredWidth: 140; height: 36; color: dataRow.rowBg
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Text { anchors.fill: parent; anchors.margins: 6
                                text: cellAny(dataRow.index, ["Diretorio do Video", "Diretório do Vídeo", "Video Directory", "Directorio del Video"])
                                color: ThemeManager.textTertiary; font.pixelSize: 9; elide: Text.ElideLeft
                                Behavior on color { ColorAnimation { duration: 150 } } } }
                        Rectangle { Layout.preferredWidth: 90; height: 36; color: dataRow.rowBg
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Text { anchors.centerIn: parent; text: cellAny(dataRow.index, ["Animal"])
                                color: ThemeManager.textPrimary; font.pixelSize: 12; font.weight: Font.Bold
                                Behavior on color { ColorAnimation { duration: 150 } } } }
                        Rectangle { Layout.preferredWidth: 130; height: 36; color: dataRow.rowBg
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Text { anchors.centerIn: parent; text: cellAny(dataRow.index, ["Par de Objetos", "Object Pair"])
                                color: ThemeManager.textSecondary; font.pixelSize: 11
                                Behavior on color { ColorAnimation { duration: 150 } } } }
                        Rectangle { Layout.preferredWidth: 70; height: 36; color: dataRow.rowBg
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Text { anchors.centerIn: parent; text: cellAny(dataRow.index, ["Campo", "Field"])
                                color: ThemeManager.textSecondary; font.pixelSize: 11
                                Behavior on color { ColorAnimation { duration: 150 } } } }
                        Rectangle { Layout.preferredWidth: 90; height: 36; color: dataRow.rowBg
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Text { anchors.centerIn: parent; text: cellAny(dataRow.index, ["Dia", "Day"])
                                color: accentColor; font.pixelSize: 11; font.weight: Font.Bold
                                Behavior on color { ColorAnimation { duration: 150 } } } }
                        Rectangle {
                            visible: hasTreatment()
                            Layout.fillWidth: true; Layout.minimumWidth: 90; height: 36; color: dataRow.rowBg
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Text { anchors.centerIn: parent; text: cellAny(dataRow.index, ["Tratamento", "Treatment", "Tratamiento"])
                                color: ThemeManager.textSecondary; font.pixelSize: 11; elide: Text.ElideRight
                                Behavior on color { ColorAnimation { duration: 150 } } } }
                        Item { visible: !hasTreatment(); Layout.fillWidth: true }
                    }
                }
            }
        }

        RowLayout {
            spacing: 8
            Text { text: "💡"; font.pixelSize: 12 }
            Text { text: "Use \"Exportar\" para ver métricas completas: exploração, DI, distância e velocidade."
                color: ThemeManager.textTertiary; font.pixelSize: 10
                Behavior on color { ColorAnimation { duration: 150 } } }
        }
    }

    Item { id: placeholder; property var model: null; property var workArea: null }
}

