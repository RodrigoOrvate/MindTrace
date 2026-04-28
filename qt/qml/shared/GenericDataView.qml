// qml/shared/GenericDataView.qml
// Fallback data view for unrecognized apparatus types.

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

    readonly property color accentColor: "#4b5563"
    readonly property color rowEven: ThemeManager.surfaceDim
    readonly property color rowOdd:  ThemeManager.surface

    function cell(row, col) {
        if (!tableModel) return ""
        if (col >= tableModel.columnCount()) return ""
        return tableModel.data(tableModel.index(row, col), Qt.DisplayRole) || ""
    }

    ColumnLayout {
        anchors { fill: parent; margins: 24 }
        spacing: 16

        // ── Summary ─────────────────────────────────────────────────────
        RowLayout {
            spacing: 8
            BusyIndicator {
                visible: tableModel && tableModel.fetchingMore
                running: visible; implicitWidth: 20; implicitHeight: 20
            }
            Text {
                text: tableModel && tableModel.rowCount() > 0
                      ? tableModel.rowCount() + " " + LanguageManager.tr3("registro(s)", "record(s)", "registro(s)")
                      : LanguageManager.tr3("Sem dados registrados", "No records", "Sin datos registrados")
                color: ThemeManager.textTertiary; font.pixelSize: 11
                Behavior on color { ColorAnimation { duration: 150 } }
            }
            Item { Layout.fillWidth: true }
        }

        // ── Dynamic table ────────────────────────────────────────────────
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: headerRow.implicitWidth
            contentHeight: tableLayout.implicitHeight

            ColumnLayout {
                id: tableLayout
                width: Math.max(parent.width, headerRow.implicitWidth)
                spacing: 0

                // Dynamic header
                RowLayout {
                    id: headerRow
                    Layout.fillWidth: true
                    spacing: 1

                    Repeater {
                        model: tableModel ? tableModel.columnCount() : 0
                        delegate: Rectangle {
                            property bool isLast: index === (tableModel ? tableModel.columnCount() - 1 : 0)
                            Layout.preferredWidth: 100
                            Layout.fillWidth: isLast
                            height: 40; color: accentColor
                            Text {
                                anchors { fill: parent; margins: 6 }
                                text: tableModel ? tableModel.headerData(index, Qt.Horizontal, Qt.DisplayRole) : ""
                                color: "white"; font.weight: Font.Bold; font.pixelSize: 10
                                elide: Text.ElideRight; wrapMode: Text.NoWrap
                            }
                        }
                    }
                }

                // Linhas de dados
                Repeater {
                    model: tableModel
                    delegate: RowLayout {
                        id: dataRow
                        required property int index
                        Layout.fillWidth: true; spacing: 1
                        readonly property color rowBg: index % 2 === 0 ? rowEven : rowOdd

                        Repeater {
                            model: tableModel ? tableModel.columnCount() : 0
                            delegate: Rectangle {
                                property bool isLast: index === (tableModel ? tableModel.columnCount() - 1 : 0)
                                Layout.preferredWidth: 100
                                Layout.fillWidth: isLast
                                height: 36
                                color: dataRow.rowBg; Behavior on color { ColorAnimation { duration: 150 } }
                                Text {
                                    anchors { fill: parent; margins: 6 }
                                    text: cell(dataRow.index, index)
                                    color: ThemeManager.textPrimary; font.pixelSize: 10; elide: Text.ElideRight
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }
                            }
                        }
                    }
                }
            }
        }

        Text {
            text: "📊 " + LanguageManager.tr3("Dados do experimento", "Experiment data", "Datos del experimento")
            color: ThemeManager.textTertiary; font.pixelSize: 9
            Behavior on color { ColorAnimation { duration: 150 } }
        }
    }

    Item {
        id: placeholder
        property var model: null
        property var workArea: null
    }
}
