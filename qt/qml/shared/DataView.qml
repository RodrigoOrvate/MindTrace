// qml/shared/DataView.qml

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

    // Reactive to model changes (columns/headers)
    property string aparato: "generic"

    Connections {
        target: tableModel
        function onModelReset() { root.aparato = root.detectAparato() }
        function onColumnsInserted(parent, first, last) { root.aparato = root.detectAparato() }
        function onColumnsRemoved(parent, first, last) { root.aparato = root.detectAparato() }
        function onHeaderDataChanged(orientation, first, last) { root.aparato = root.detectAparato() }
    }

    onTableModelChanged: { root.aparato = root.detectAparato() }

    function normalizeHeaderText(rawHeader) {
        var normalized = String(rawHeader || "").toLowerCase()
        normalized = normalized.replace(/[áàâãä]/g, "a")
        normalized = normalized.replace(/[éèêë]/g, "e")
        normalized = normalized.replace(/[íìîï]/g, "i")
        normalized = normalized.replace(/[óòôõö]/g, "o")
        normalized = normalized.replace(/[úùûü]/g, "u")
        normalized = normalized.replace(/ç/g, "c")
        return normalized
    }

    function detectAparato() {
        if (!tableModel || tableModel.columnCount() === 0) return ""

        var headers = []
        for (var colIdx = 0; colIdx < tableModel.columnCount(); colIdx++) {
            var headerText = tableModel.headerData(colIdx, Qt.Horizontal, Qt.DisplayRole)
            headers.push(normalizeHeaderText(headerText))
        }

        var headersStr = headers.join(",")
        if (headersStr.includes("par de objetos") || headersStr.includes("object pair")) return "nor"
        if (headersStr.includes("latencia") || headersStr.includes("tempo plataforma") || headersStr.includes("platform time") || headersStr.includes("tiempo plataforma")) return "ei"
        if (headersStr.includes("duracao (min)") || headersStr.includes("duration (min)") || headersStr.includes("duracion (min)") || headersStr.includes("walking") || headersStr.includes("grooming")) return "cc"
        if (headersStr.includes("distância total") || headersStr.includes("total distance") || headersStr.includes("tempo no centro") || headersStr.includes("time in center") || headersStr.includes("tiempo en centro")) return "ca"

        return "generic"
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Apparatus info bar
        Rectangle {
            Layout.fillWidth: true
            height: 56
            color: ThemeManager.surface
            Behavior on color { ColorAnimation { duration: 200 } }

            Rectangle {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                height: 1
                color: ThemeManager.border
                Behavior on color { ColorAnimation { duration: 200 } }
            }

            RowLayout {
                anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                spacing: 12

                Text {
                    text: getAparatoIcon()
                    font.pixelSize: 24
                }

                ColumnLayout {
                    spacing: 0
                    Text {
                        text: getAparatoLabel()
                        color: getAparatoColor().accent
                        font.pixelSize: 14
                        font.weight: Font.Bold
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                    Text {
                        text: getAparatoSubtitle()
                        color: ThemeManager.textSecondary
                        font.pixelSize: 11
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                }

                Item { Layout.fillWidth: true }

                RowLayout {
                    spacing: 8
                    GhostButton {
                        text: LanguageManager.tr3("+ Linha", "+ Row", "+ Fila")
                        visible: tableModel
                        onClicked: tableModel.addRow()
                    }
                    Button {
                        text: "📤 " + LanguageManager.tr3("Exportar", "Export", "Exportar")
                        visible: tableModel && workArea && workArea.selectedPath
                        onClicked: {
                            if (tableModel.exportCsv(workArea.selectedPath + "/export_" +
                                new Date().toISOString().substring(0, 10) + ".xlsx"))
                                exportFeedback.show(LanguageManager.tr3("Exportado!", "Exported!", "Exportado!"))
                        }
                        background: Rectangle {
                            radius: 7
                            color: parent.hovered ? getAparatoColor().accentLight : getAparatoColor().accent
                            Behavior on color { ColorAnimation { duration: 200 } }
                        }
                        contentItem: Text {
                            text: parent.text
                            color: ThemeManager.buttonText
                            font.pixelSize: 12
                            font.weight: Font.Bold
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        leftPadding: 14; rightPadding: 14
                        topPadding: 6; bottomPadding: 6
                    }
                }
            }
        }

        // Dynamic apparatus content
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // NOR - Object Recognition
            NORDataView {
                id: norView
                anchors.fill: parent
                visible: root.aparato === "nor"
                tableModel: root.tableModel
                workArea: root.workArea
            }

            // CA - Open Field
            CADataView {
                id: caView
                anchors.fill: parent
                visible: root.aparato === "ca"
                tableModel: root.tableModel
                workArea: root.workArea
            }

            // CC - Complex Behavior
            CCDataView {
                id: ccView
                anchors.fill: parent
                visible: root.aparato === "cc"
                tableModel: root.tableModel
                workArea: root.workArea
            }

            // EI - Inhibitory Avoidance
            EIDataView {
                id: eiView
                anchors.fill: parent
                visible: root.aparato === "ei"
                tableModel: root.tableModel
                workArea: root.workArea
            }

            // Fallback / generic
            GenericDataView {
                anchors.fill: parent
                visible: root.aparato === "generic" || root.aparato === ""
                tableModel: root.tableModel
                workArea: root.workArea
            }
        }
    }

    // Helper functions
    function getAparatoIcon() {
        switch (root.aparato) {
            case "nor": return "\uD83E\uDDE0"
            case "ca": return "\uD83D\uDC01"
            case "cc": return "\uD83E\uDDE9"
            case "ei": return "\u26A1"
            default: return "\uD83D\uDCCA"
        }
    }

    function getAparatoLabel() {
        switch (root.aparato) {
            case "nor": return LanguageManager.tr3("Reconhecimento de Objetos (NOR)", "Object Recognition (NOR)", "Reconocimiento de Objetos (NOR)")
            case "ca": return LanguageManager.tr3("Campo Aberto (CA)", "Open Field (CA)", "Campo Abierto (CA)")
            case "cc": return LanguageManager.tr3("Comportamento Complexo (CC)", "Complex Behavior (CC)", "Comportamiento Complejo (CC)")
            case "ei": return LanguageManager.tr3("Esquiva Inibitoria (EI)", "Inhibitory Avoidance (EI)", "Evitacion Inhibitoria (EI)")
            default: return LanguageManager.tr3("Dados de Experimento", "Experiment Data", "Datos de Experimento")
        }
    }

    function getAparatoSubtitle() {
        switch (root.aparato) {
            case "nor": return LanguageManager.tr3("Exploração e discriminacao de objetos", "Object exploration and discrimination", "Exploracion y discriminacion de objetos")
            case "ca": return LanguageManager.tr3("Exploração em arena aberta", "Open arena exploration", "Exploracion en arena abierta")
            case "cc": return LanguageManager.tr3("Analise comportamental complexa", "Complex behavioral analysis", "Analisis conductual complejo")
            case "ei": return LanguageManager.tr3("Memoria aversiva passiva", "Passive aversive memory", "Memoria aversiva pasiva")
            default: return LanguageManager.tr3("Planilha de resultados", "Results sheet", "Hoja de resultados")
        }
    }

    function getAparatoColor() {
        switch (root.aparato) {
            case "nor": return {
                accent: "#ab3d4c",
                accentLight: "#cc5566",
                headerBg: "#fcecef",
                text: "#611824",
                textSecondary: "#8b3a4a"
            }
            case "ca": return {
                accent: "#3d7aab",
                accentLight: "#5d9fd4",
                headerBg: "#eaf3fb",
                text: "#153e5c",
                textSecondary: "#3d6a8a"
            }
            case "cc": return {
                accent: "#7a3dab",
                accentLight: "#9d5dd4",
                headerBg: "#f2eafc",
                text: "#3f1d61",
                textSecondary: "#6a3d8a"
            }
            case "ei": return {
                accent: "#c8a000",
                accentLight: "#e0b800",
                headerBg: "#fdf8e1",
                text: "#5a4200",
                textSecondary: "#7a5c00"
            }
            default: return {
                accent: "#4b5563",
                accentLight: "#6b7583",
                headerBg: "#f3f4f6",
                text: "#111827",
                textSecondary: "#4b5563"
            }
        }
    }

    // Toast feedback
    Toast {
        id: exportFeedback
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24
        successMode: true
    }

    // Placeholder para acesso dos dados
    Item {
        id: placeholder
        property var model: null
        property var workArea: null
    }
}

