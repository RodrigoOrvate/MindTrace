// qml/shared/DataView.qml
// Visualizador de dados aparato-específico com layout e cores personalizadas.
// Detecta o aparato pelos headers do CSV e renderiza o componente apropriado.

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

    // Detecta aparato a partir do modelo — reativo às mudanças de colunas/headers
    property string aparato: "generic"

    Connections {
        target: tableModel
        function onColumnCountChanged() { root.aparato = root.detectAparato() }
        function onModelReset() { root.aparato = root.detectAparato() }
    }

    onTableModelChanged: { root.aparato = root.detectAparato() }

    function detectAparato() {
        if (!tableModel || tableModel.columnCount() === 0) return ""
        
        // Verifica headers para determinar aparato
        var headers = []
        for (var i = 0; i < tableModel.columnCount(); i++) {
            var h = tableModel.headerData(i, Qt.Horizontal, Qt.DisplayRole)
            headers.push(String(h))
        }
        
        var headersStr = headers.join(",")
        if (headersStr.includes("Par de Objetos")) return "nor"
        if (headersStr.includes("Latência") || headersStr.includes("Tempo Plataforma")) return "ei"
        if (headersStr.includes("Duração (min)")) return "cc"
        if (headersStr.includes("Distância Total")) return "ca"
        
        return "generic"
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── Barra superior com informações do aparato ──────────────
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
                        text: "＋ Linha"
                        visible: tableModel
                        onClicked: tableModel.addRow()
                    }
                    Button {
                        text: "📤 Exportar"
                        visible: tableModel && workArea && workArea.selectedPath
                        onClicked: {
                            if (tableModel.exportCsv(workArea.selectedPath + "/export_" +
                                new Date().toISOString().substring(0, 10) + ".xlsx"))
                                exportFeedback.show("Exportado!")
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

        // ── Conteúdo dinâmico por aparato ──────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // NOR - Reconhecimento de Objetos
            NORDataView {
                id: norView
                anchors.fill: parent
                visible: root.aparato === "nor"
                tableModel: root.tableModel
                workArea: root.workArea
            }

            // CA - Campo Aberto
            CADataView {
                id: caView
                anchors.fill: parent
                visible: root.aparato === "ca"
                tableModel: root.tableModel
                workArea: root.workArea
            }

            // CC - Comportamento Complexo
            CCDataView {
                id: ccView
                anchors.fill: parent
                visible: root.aparato === "cc"
                tableModel: root.tableModel
                workArea: root.workArea
            }

            // EI - Esquiva Inibitória
            EIDataView {
                id: eiView
                anchors.fill: parent
                visible: root.aparato === "ei"
                tableModel: root.tableModel
                workArea: root.workArea
            }

            // Genérico/Fallback
            GenericDataView {
                anchors.fill: parent
                visible: root.aparato === "generic" || root.aparato === ""
                tableModel: root.tableModel
                workArea: root.workArea
            }
        }
    }

    // ── Helper functions ──────────────────────────────────────────────
    function getAparatoIcon() {
        switch (root.aparato) {
            case "nor": return "🧠"
            case "ca": return "🐀"
            case "cc": return "🧩"
            case "ei": return "⚡"
            default: return "📊"
        }
    }

    function getAparatoLabel() {
        switch (root.aparato) {
            case "nor": return "Reconhecimento de Objetos (NOR)"
            case "ca": return "Campo Aberto (CA)"
            case "cc": return "Comportamento Complexo (CC)"
            case "ei": return "Esquiva Inibitória (EI)"
            default: return "Dados de Experimento"
        }
    }

    function getAparatoSubtitle() {
        switch (root.aparato) {
            case "nor": return "Exploração e discriminação de objetos"
            case "ca": return "Exploração em arena aberta"
            case "cc": return "Análise comportamental complexa"
            case "ei": return "Memória aversiva passiva"
            default: return "Planilha de resultados"
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
                accent: "#2f7a4b",
                accentLight: "#4d9d6a",
                headerBg: "#eaf7ef",
                text: "#0f4d27",
                textSecondary: "#3d6a4d"
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

    // Toast — centralizado na parte inferior
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
