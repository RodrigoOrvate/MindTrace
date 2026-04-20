// qml/shared/EIDataView.qml
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

    readonly property color accentColor: "#c8a000"
    readonly property color rowEven: ThemeManager.surfaceDim
    readonly property color rowOdd:  ThemeManager.surface

    property var colMap: ({})
    function buildColMap() {
        var map = {}
        if (!tableModel) return map
        for (var i = 0; i < tableModel.columnCount(); i++)
            map[String(tableModel.headerData(i, Qt.Horizontal, Qt.DisplayRole)).trim()] = i
        return map
    }
    function colOf(name) { return colMap.hasOwnProperty(name) ? colMap[name] : -1 }
    function cellOf(row, name) {
        var idx = colOf(name)
        return (idx >= 0 && tableModel) ? (tableModel.data(tableModel.index(row, idx), Qt.DisplayRole) || "") : ""
    }
    function hasTreatment() { return colMap.hasOwnProperty("Tratamento") }

    Connections {
        target: tableModel
        function onModelReset()   { root.colMap = root.buildColMap() }
        function onRowsInserted() { root.colMap = root.buildColMap() }
    }
    onTableModelChanged: root.colMap = root.buildColMap()

    ColumnLayout {
        anchors { fill: parent; margins: 24 }
        spacing: 16

        RowLayout {
            spacing: 8
            BusyIndicator { visible: tableModel && tableModel.fetchingMore; running: visible; implicitWidth: 20; implicitHeight: 20 }
            Text { text: tableModel && tableModel.rowCount() > 0
                         ? tableModel.rowCount() + " registro(s) · Exporte para ver latência e métricas"
                         : "Sem dados registrados"
                color: ThemeManager.textTertiary; font.pixelSize: 11
                Behavior on color { ColorAnimation { duration: 150 } } }
            Item { Layout.fillWidth: true }
        }

        ScrollView {
            Layout.fillWidth: true; Layout.fillHeight: true
            contentWidth: headerRow.implicitWidth; contentHeight: tableLayout.implicitHeight

            ColumnLayout {
                id: tableLayout
                width: Math.max(parent.width, headerRow.implicitWidth); spacing: 0

                RowLayout {
                    id: headerRow
                    Layout.fillWidth: true; spacing: 1
                    Rectangle { Layout.preferredWidth: 140; height: 40; color: accentColor
                        Text { anchors.fill: parent; anchors.margins: 8; text: "Vídeo"
                            color: "white"; font.weight: Font.Bold; font.pixelSize: 11; elide: Text.ElideRight } }
                    Rectangle { Layout.preferredWidth: 90; height: 40; color: accentColor
                        Text { anchors.centerIn: parent; text: "Animal"; color: "white"; font.weight: Font.Bold; font.pixelSize: 11 } }
                    Rectangle { Layout.preferredWidth: 90; height: 40; color: accentColor
                        Text { anchors.centerIn: parent; text: "Dia"; color: "white"; font.weight: Font.Bold; font.pixelSize: 11 } }
                    Rectangle { visible: hasTreatment(); Layout.fillWidth: true; Layout.minimumWidth: 90; height: 40; color: accentColor
                        Text { anchors.centerIn: parent; text: "Tratamento"; color: "white"; font.weight: Font.Bold; font.pixelSize: 11 } }
                    Item { visible: !hasTreatment(); Layout.fillWidth: true }
                }

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
                                text: cellOf(dataRow.index, "Diretório do Vídeo")
                                color: ThemeManager.textTertiary; font.pixelSize: 9; elide: Text.ElideLeft
                                Behavior on color { ColorAnimation { duration: 150 } } } }
                        Rectangle { Layout.preferredWidth: 90; height: 36; color: dataRow.rowBg
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Text { anchors.centerIn: parent; text: cellOf(dataRow.index, "Animal")
                                color: ThemeManager.textPrimary; font.pixelSize: 12; font.weight: Font.Bold
                                Behavior on color { ColorAnimation { duration: 150 } } } }
                        Rectangle { Layout.preferredWidth: 90; height: 36; color: dataRow.rowBg
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Text { anchors.centerIn: parent; text: cellOf(dataRow.index, "Dia")
                                color: accentColor; font.pixelSize: 11; font.weight: Font.Bold
                                Behavior on color { ColorAnimation { duration: 150 } } } }
                        Rectangle { visible: hasTreatment(); Layout.fillWidth: true; Layout.minimumWidth: 90; height: 36; color: dataRow.rowBg
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Text { anchors.centerIn: parent; text: cellOf(dataRow.index, "Tratamento")
                                color: ThemeManager.textSecondary; font.pixelSize: 11; elide: Text.ElideRight
                                Behavior on color { ColorAnimation { duration: 150 } } } }
                        Item { visible: !hasTreatment(); Layout.fillWidth: true }
                    }
                }
            }
        }

        RowLayout { spacing: 8
            Text { text: "💡"; font.pixelSize: 12 }
            Text { text: "Use \"Exportar\" para ver latência, tempos na plataforma/grade, distância e velocidade."
                color: ThemeManager.textTertiary; font.pixelSize: 10
                Behavior on color { ColorAnimation { duration: 150 } } } }
    }
    Item { id: placeholder; property var model: null; property var workArea: null }
}
