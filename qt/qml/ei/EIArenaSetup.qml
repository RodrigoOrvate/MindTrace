// qml/ei/EIArenaSetup.qml
// Arena para Esquiva Inibitória: campo único, paredes, chão e 2 zonas retangulares.
// Plataforma (esquerda) + Grade (direita) — sem objetos pares NOR.
// Ctrl+Arrastar: Paredes | Alt+Arrastar: Chão | Shift+Arrastar: Zonas | Scroll: +/- Zonas

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia
import QtQuick.Dialogs
import "../core"
import "../core/Theme"
import MindTrace.Backend 1.0

Item {
    id: root

    property string experimentPath: ""
    property string videoPath:      ""
    property string analysisMode:   ""
    property string saveDirectory:  ""
    property int    numCampos:      1
    property bool   devMode:        false
    property real   videoAspectRatio: 1.5 // 720x480 padrão

    // Cor do aparato (parametrizável para reuso em CA/CC com 1 campo)
    property color primaryColor:   "#c8a000"
    property color secondaryColor: "#9a7800"

    // ── Import Arena ──────────────────────────────────────────────────────────
    property string _pendingImportPath: ""
    property bool   _importWarnShape:   false
    property bool   _importWarnZones:   false

    function _arenaShape(arenaJson) {
        try {
            var pts = JSON.parse(arenaJson)
            if (Array.isArray(pts) && pts.length > 0 && Array.isArray(pts[0])) pts = pts[0]
            if (!Array.isArray(pts) || pts.length < 3) return "desconhecida"
            var minX = pts[0].x, maxX = pts[0].x, minY = pts[0].y, maxY = pts[0].y
            for (var i = 1; i < pts.length; i++) {
                if (pts[i].x < minX) minX = pts[i].x; if (pts[i].x > maxX) maxX = pts[i].x
                if (pts[i].y < minY) minY = pts[i].y; if (pts[i].y > maxY) maxY = pts[i].y
            }
            var ratio = (maxX - minX) / Math.max(maxY - minY, 0.001)
            return (ratio > 1.4 || ratio < 0.714) ? "retangular" : "quadrada"
        } catch(e) { return "desconhecida" }
    }

    function _zoneType(zoneCount, floorJson) {
        if (zoneCount >= 4) return "objetos"
        try {
            var fp = JSON.parse(floorJson)
            if (Array.isArray(fp) && fp.length > 0 && Array.isArray(fp[0])) fp = fp[0]
            if (Array.isArray(fp) && fp.length >= 8) return "plataforma_grade"
        } catch(e) {}
        return "padrao"
    }

    function _startImport(sourcePath) {
        if (!sourcePath || sourcePath === "" || experimentPath === "") return
        // Lê dados da arena fonte
        ArenaConfigModel.loadConfigFromPath(sourcePath)
        var srcFloor     = ArenaConfigModel.getFloorPoints()
        var srcZoneCount = ArenaConfigModel.zoneCount()
        // Restaura arena atual
        ArenaConfigModel.loadConfigFromPath(experimentPath, ":/arena_config_ei_referencia.json")
        var curFloor     = ArenaConfigModel.getFloorPoints()
        var curZoneCount = ArenaConfigModel.zoneCount()
        // Verifica apenas incompatibilidade de tipo de zona (shape detection removida — coords normalizadas são imprecisas)
        var srcType  = _zoneType(srcZoneCount, srcFloor)
        var curType  = _zoneType(curZoneCount, curFloor)
        _pendingImportPath = sourcePath
        _importWarnShape   = false
        _importWarnZones   = (srcType !== curType)
        if (_importWarnZones) {
            importConfirmPopup.open()
        } else {
            _doImport()
        }
    }

    function _doImport() {
        ArenaConfigModel.loadConfigFromPath(_pendingImportPath)
        _pendingImportPath = ""
        saveToast.show("Arena importada! Clique em 'Salvar Configuração' para confirmar.")
    }

    // Zonas: 2 zonas em formato {x, y, r} — r = metade da largura/altura normalizada
    // Valores iniciais neutros; preenchidos via zoneInitTimer após carregar do modelo
    property var zones:       [ { x: 0.25, y: 0.5, r: 0.15 }, { x: 0.70, y: 0.5, r: 0.25 } ]

    // Paredes e chão — preenchidos via zoneInitTimer (da referência EI ou do arquivo salvo)
    property var arenaPoints: [[]]
    property var floorPoints: [[]]

    signal zonasEditadas()
    signal analysisModeChangedExternally(string mode)

    // Função pública: abre o popup de modo
    function openVideoLoader() { analysisModePrompt.open() }

    // ── Toast "não salvo" ────────────────────────────────────────────────────
    Rectangle {
        id: unsavedToast
        visible: false; z: 5000
        width: unsavedText.implicitWidth + 24; height: 32; radius: 6
        color: "#1a0a0a"; border.color: "#ff4757"; border.width: 1
        anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 12 }
        opacity: 0
        Behavior on opacity { NumberAnimation { duration: 180 } }
        Text {
            id: unsavedText; anchors.centerIn: parent
            text: "⚠️ Zonas editadas! Não esqueça de Salvar"
            color: "#ff6b7a"; font.pixelSize: 11
        }
    }
    function showUnsavedToast() {
        unsavedToast.opacity = 1; unsavedToast.visible = true; unsavedToastTimer.restart()
    }
    Timer {
        id: unsavedToastTimer; interval: 3000
        onTriggered: { unsavedToast.opacity = 0; unsavedToast.visible = false }
    }

    // ── Carregar config ao abrir experimento ────────────────────────────────
    onExperimentPathChanged: {
        if (experimentPath === "") return
        // EI usa referência própria como fallback (sem arena_config.json salvo)
        ArenaConfigModel.loadConfigFromPath(experimentPath, ":/arena_config_ei_referencia.json")
        // arenaPoints, floorPoints e zones são aplicados em zoneInitTimer via onConfigChanged
    }

    Connections {
        target: ArenaConfigModel
        function onConfigChanged() { zoneInitTimer.restart() }
    }

    // Helper: parseia string JSON de pontos → [[{x,y},...]] com expectedCount mínimo
    function normalizePoints(data, expectedCount) {
        try {
            if (!data || data === "") return null
            var p = JSON.parse(data)
            if (Array.isArray(p) && p.length > 0 && Array.isArray(p[0])) p = p[0]
            if (Array.isArray(p) && p.length > 0 && p[0].x !== undefined) {
                while (p.length < expectedCount) p.push({x: 0.5, y: 0.5})
                return [p]
            }
            return null
        } catch(e) { return null }
    }

    Timer {
        id: zoneInitTimer; interval: 60; repeat: false
        onTriggered: {
            // Aplica arenaPoints e floorPoints do modelo (vem do arquivo salvo ou da referência EI)
            var normArena = root.normalizePoints(ArenaConfigModel.getArenaPoints(), 4)
            var normFloor = root.normalizePoints(ArenaConfigModel.getFloorPoints(), 8)
            if (normArena) root.arenaPoints = normArena
            if (normFloor) root.floorPoints = normFloor

            // Aplica zonas do modelo
            var n = ArenaConfigModel.zoneCount()
            if (n >= 2) {
                var z0 = ArenaConfigModel.zone(0)
                var z1 = ArenaConfigModel.zone(1)
                zones = [
                    { x: z0.xRatio || 0.25, y: z0.yRatio || 0.5, r: z0.radiusRatio || 0.15 },
                    { x: z1.xRatio || 0.70, y: z1.yRatio || 0.5, r: z1.radiusRatio || 0.25 }
                ]
            }
            root.zonasEditadas()
        }
    }

    // ── Player de vídeo (preview) ────────────────────────────────────────────
    MediaPlayer {
        id: videoPlayer
        autoPlay: false
        videoOutput: framePreview
        onMediaStatusChanged: {
            if (mediaStatus === MediaPlayer.LoadedMedia) {
                setPosition(1000)
                pause()
            }
        }
    }

    // ── Diálogos ─────────────────────────────────────────────────────────────
    FileDialog {
        id: videoFileDialog
        title: "Selecionar Vídeo de Análise"
        nameFilters: ["Vídeos (*.mp4 *.mpg *.mpeg *.avi *.mov)", "Todos os arquivos (*)"]
        onAccepted: {
            videoPlayer.stop()
            root.videoPath = selectedFile.toString()
            videoPlayer.source = selectedFile
            root.analysisModeChangedExternally(root.analysisMode)
        }
    }

    FileDialog {
        id: importFolderDialog
        title: "Selecionar arena_config.json do experimento de origem"
        nameFilters: ["Configuração de Arena (arena_config.json)", "JSON (*.json)", "Todos os arquivos (*)"]
        onAccepted: {
            var filePath = selectedFile.toString().replace("file:///", "")
            // Extrai a pasta pai do arquivo selecionado
            var folderPath = filePath.substring(0, filePath.lastIndexOf("/"))
            root._startImport(folderPath)
        }
    }

    // Popup: confirmar importação com avisos
    Popup {
        id: importConfirmPopup
        anchors.centerIn: parent
        width: 440; height: importConfirmLayout.implicitHeight + 48
        modal: true; focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle {
            radius: 14; color: ThemeManager.surface
            Behavior on color { ColorAnimation { duration: 200 } }
            border.color: "#e0a000"; border.width: 1.5
        }
        ColumnLayout {
            id: importConfirmLayout
            anchors { fill: parent; margins: 24 }
            spacing: 14
            Text {
                text: "⚠️ Atenção — Importar Arena"
                color: ThemeManager.textPrimary; font.pixelSize: 15; font.weight: Font.Bold
                Behavior on color { ColorAnimation { duration: 150 } }
            }
            Text {
                Layout.fillWidth: true
                text: {
                    var msg = ""
                    if (root._importWarnShape)
                        msg += "• A arena de origem tem <b>formato diferente</b> (quadrada ↔ retangular). As proporções serão mantidas, mas a posição dos elementos pode mudar.<br>"
                    if (root._importWarnZones)
                        msg += "• A arena de origem tem <b>configuração de zonas diferente</b> (ex: plataforma/grade vs. sem zonas, ou zonas de objetos). As zonas do destino podem ficar incompatíveis.<br>"
                    msg += "<br>Deseja importar mesmo assim?"
                    return msg
                }
                textFormat: Text.RichText
                color: ThemeManager.textSecondary; font.pixelSize: 13; wrapMode: Text.WordWrap
                Behavior on color { ColorAnimation { duration: 150 } }
            }
            RowLayout {
                Layout.fillWidth: true; spacing: 10
                Item { Layout.fillWidth: true }
                GhostButton { text: "Cancelar"; onClicked: { importConfirmPopup.close(); root._pendingImportPath = "" } }
                Button {
                    text: "Importar Mesmo Assim"
                    onClicked: { importConfirmPopup.close(); root._doImport() }
                    background: Rectangle { radius: 7; color: parent.hovered ? "#9a7800" : "#c8a000"; Behavior on color { ColorAnimation { duration: 150 } } }
                    contentItem: Text { text: parent.text; color: ThemeManager.buttonText; font.pixelSize: 12; font.weight: Font.Bold; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    leftPadding: 16; rightPadding: 16; topPadding: 8; bottomPadding: 8
                }
            }
        }
    }

    // Popup: offline ou ao vivo?
    Popup {
        id: analysisModePrompt
        width: 400; height: 260
        anchors.centerIn: parent
        modal: true; focus: true
        closePolicy: Popup.CloseOnEscape

        background: Rectangle {
            radius: 14; color: ThemeManager.surface
            Behavior on color { ColorAnimation { duration: 200 } }
            border.color: root.primaryColor; border.width: 1
        }

        ColumnLayout {
            anchors { fill: parent; margins: 24 }
            spacing: 14

            Text {
                text: "Tipo de Análise"
                color: ThemeManager.textPrimary
                Behavior on color { ColorAnimation { duration: 150 } }
                font.pixelSize: 16; font.weight: Font.Bold
            }
            Text {
                Layout.fillWidth: true
                text: "Escolha o modo e carregue o vídeo:"
                color: ThemeManager.textSecondary
                Behavior on color { ColorAnimation { duration: 150 } }
                font.pixelSize: 13
            }

            RowLayout {
                Layout.fillWidth: true; spacing: 12

                // Offline
                Rectangle {
                    Layout.fillWidth: true; height: 80; radius: 8
                    color: offMa.containsMouse ? ThemeManager.surfaceAlt : ThemeManager.surfaceDim
                    border.color: root.primaryColor; border.width: 2
                    Behavior on color { ColorAnimation { duration: 150 } }

                    ColumnLayout {
                        anchors.centerIn: parent; spacing: 4
                        Text {
                            text: "🎬  Análise Offline"
                            color: ThemeManager.textPrimary
                            Behavior on color { ColorAnimation { duration: 150 } }
                            font.pixelSize: 13; font.weight: Font.Bold
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Text {
                            text: "Vídeo pré-gravado"
                            color: ThemeManager.textSecondary
                            Behavior on color { ColorAnimation { duration: 150 } }
                            font.pixelSize: 10; horizontalAlignment: Text.AlignHCenter
                        }
                    }
                    MouseArea {
                        id: offMa; anchors.fill: parent
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.analysisMode = "offline"
                            root.saveDirectory = ""
                            analysisModePrompt.close()
                            videoFileDialog.open()
                        }
                    }
                }

                // Ao vivo
                Rectangle {
                    Layout.fillWidth: true; height: 80; radius: 8
                    color: liveMa.containsMouse ? ThemeManager.surfaceAlt : ThemeManager.background
                    border.color: ThemeManager.success; border.width: 2
                    Behavior on color { ColorAnimation { duration: 150 } }

                    ColumnLayout {
                        anchors.centerIn: parent; spacing: 4
                        Text {
                            text: "📹  Análise Ao Vivo"
                            color: ThemeManager.textPrimary
                            Behavior on color { ColorAnimation { duration: 150 } }
                            font.pixelSize: 13; font.weight: Font.Bold
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Text {
                            text: "Câmera (salva o vídeo)"
                            color: ThemeManager.textSecondary
                            Behavior on color { ColorAnimation { duration: 150 } }
                            font.pixelSize: 10; horizontalAlignment: Text.AlignHCenter
                        }
                    }
                    MouseArea {
                        id: liveMa; anchors.fill: parent
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.analysisMode = "ao_vivo"
                            analysisModePrompt.close()
                            saveDirPopup.open()
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true; spacing: 8
                Item { Layout.fillWidth: true }
                GhostButton {
                    text: "Cancelar"
                    onClicked: { root.videoPath = ""; analysisModePrompt.close() }
                }
            }
        }
    }

    // Popup: diretório para salvar vídeo ao vivo
    Popup {
        id: saveDirPopup
        anchors.centerIn: parent
        width: 440; height: 180
        modal: true; focus: true
        closePolicy: Popup.CloseOnEscape
        background: Rectangle {
            radius: 14; color: ThemeManager.surface
            Behavior on color { ColorAnimation { duration: 200 } }
            border.color: root.primaryColor; border.width: 1
        }
        ColumnLayout {
            anchors { fill: parent; margins: 20 }
            spacing: 12
            Text {
                text: "Selecionar diretório de gravação"
                color: ThemeManager.textPrimary
                Behavior on color { ColorAnimation { duration: 150 } }
                font.pixelSize: 15; font.weight: Font.Bold
            }
            TextField {
                id: savePathField
                Layout.fillWidth: true
                placeholderText: "Cole o caminho ou confirme vazio para padrão"
                color: ThemeManager.textPrimary
                Behavior on color { ColorAnimation { duration: 150 } }
                placeholderTextColor: ThemeManager.textSecondary; font.pixelSize: 12
                onTextChanged: root.saveDirectory = text
                leftPadding: 10; rightPadding: 10; topPadding: 8; bottomPadding: 8
                background: Rectangle {
                    radius: 6; color: ThemeManager.surfaceDim
                    Behavior on color { ColorAnimation { duration: 200 } }
                    border.color: savePathField.activeFocus ? root.primaryColor : ThemeManager.border; border.width: 1
                }
            }
            RowLayout {
                Layout.fillWidth: true; spacing: 8
                Item { Layout.fillWidth: true }
                GhostButton { text: "Cancelar"; onClicked: saveDirPopup.close() }
                Button {
                    text: "Confirmar"
                    onClicked: {
                        root.saveDirectory = savePathField.text.trim()
                        saveDirPopup.close()
                        root.analysisModeChangedExternally("ao_vivo")
                    }
                    background: Rectangle {
                        radius: 8
                        color: parent.hovered ? root.secondaryColor : root.primaryColor
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                    contentItem: Text {
                        text: parent.text; color: ThemeManager.buttonText
                        font.pixelSize: 13; font.weight: Font.Bold
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                    leftPadding: 18; rightPadding: 18; topPadding: 9; bottomPadding: 9
                }
            }
        }
    }

    // ── Toast de salvo — renderizado no Overlay da janela para ficar acima de tudo ──
    Toast {
        id: saveToast
        parent: Overlay.overlay
        successMode: true
        anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 20 }
    }

    // ── VideoOutput oculto (source para o ShaderEffectSource) ────────────────
    Item {
        id: hiddenVideoContainer
        width: 320; height: 180; visible: true; opacity: 0.001; z: -1
        anchors.bottom: parent.bottom; anchors.right: parent.right
        VideoOutput {
            id: framePreview
            anchors.fill: parent
            fillMode: VideoOutput.PreserveAspectFit
            onImplicitWidthChanged:  if (implicitWidth > 0 && implicitHeight > 0) root.videoAspectRatio = implicitWidth / implicitHeight
            onImplicitHeightChanged: if (implicitWidth > 0 && implicitHeight > 0) root.videoAspectRatio = implicitWidth / implicitHeight
        }
    }

    // ── Layout Principal ──────────────────────────────────────────────────────
    ColumnLayout {
        anchors { fill: parent; margins: 16 }
        spacing: 10

        // ── Barra de ações ────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true; spacing: 8

            Text {
                text: "Configuração da Arena"
                color: ThemeManager.textPrimary
                Behavior on color { ColorAnimation { duration: 150 } }
                font.pixelSize: 14; font.weight: Font.Bold
            }
            Item { Layout.fillWidth: true }

            Text {
                text: root.devMode
                    ? "🔧 devMode  |  Ctrl+Arrastar: Paredes  |  Shift+Arrastar: Plataforma  |  Alt+Arrastar: Grade"
                    : "🖱 Ctrl+Arrastar: Paredes  |  Shift+Arrastar: Plataforma  |  Alt+Arrastar: Grade"
                color: ThemeManager.textTertiary
                Behavior on color { ColorAnimation { duration: 150 } }
                font.pixelSize: 10; verticalAlignment: Text.AlignVCenter
            }

            // Dev Mode
            Button {
                id: devModeBtn
                text: root.devMode ? "🔧 Dev ON" : "🔧 Dev OFF"
                onClicked: root.devMode = !root.devMode
                background: Rectangle {
                    radius: 6
                    color: root.devMode ? (devModeBtn.hovered ? "#7a5500" : "#8a6200")
                                       : (devModeBtn.hovered ? ThemeManager.surfaceAlt : ThemeManager.background)
                    Behavior on color { ColorAnimation { duration: 200 } }
                    border.color: root.devMode ? "#c88000" : (devModeBtn.hovered ? ThemeManager.border : ThemeManager.borderLight)
                    Behavior on border.color { ColorAnimation { duration: 200 } }
                    border.width: 2
                }
                contentItem: Text {
                    text: parent.text
                    color: root.devMode ? "#ffffff" : (devModeBtn.hovered ? ThemeManager.textPrimary : ThemeManager.textSecondary)
                    Behavior on color { ColorAnimation { duration: 150 } }
                    font.pixelSize: 11; font.weight: Font.Bold
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                }
                leftPadding: 14; rightPadding: 14; topPadding: 6; bottomPadding: 6
            }

            // Carregar vídeo
            Button {
                id: videoBtnRect
                text: root.videoPath !== "" ? "🎬 Vídeo ✓" : "🎬 Carregar Vídeo"
                onClicked: analysisModePrompt.open()
                background: Rectangle {
                    radius: 6
                    color: root.videoPath !== ""
                           ? (videoBtnRect.hovered ? ThemeManager.success : ThemeManager.successLight)
                           : (videoBtnRect.hovered ? ThemeManager.surfaceAlt : ThemeManager.background)
                    Behavior on color { ColorAnimation { duration: 200 } }
                    border.color: root.videoPath !== "" ? ThemeManager.success : (videoBtnRect.hovered ? ThemeManager.border : ThemeManager.borderLight)
                    Behavior on border.color { ColorAnimation { duration: 200 } }
                    border.width: 2
                }
                contentItem: Text {
                    text: parent.text
                    color: root.videoPath !== "" ? ThemeManager.textPrimary : (videoBtnRect.hovered ? ThemeManager.textPrimary : ThemeManager.textSecondary)
                    Behavior on color { ColorAnimation { duration: 150 } }
                    font.pixelSize: 11; font.weight: Font.Bold
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                }
                leftPadding: 14; rightPadding: 14; topPadding: 6; bottomPadding: 6
            }

            // Importar Arena
            Button {
                text: "📥 Importar Arena"
                enabled: experimentPath !== ""
                onClicked: importFolderDialog.open()
                background: Rectangle {
                    radius: 6
                    color: parent.enabled ? (parent.hovered ? ThemeManager.surfaceAlt : ThemeManager.background) : ThemeManager.surfaceDim
                    Behavior on color { ColorAnimation { duration: 200 } }
                    border.color: parent.enabled ? (parent.hovered ? root.primaryColor : ThemeManager.borderLight) : ThemeManager.borderLight
                    Behavior on border.color { ColorAnimation { duration: 200 } }
                    border.width: 2
                }
                contentItem: Text {
                    text: parent.text; color: parent.enabled ? (parent.hovered ? root.primaryColor : ThemeManager.textSecondary) : ThemeManager.textTertiary
                    Behavior on color { ColorAnimation { duration: 150 } }
                    font.pixelSize: 11; font.weight: Font.Bold
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                }
                leftPadding: 14; rightPadding: 14; topPadding: 7; bottomPadding: 7
            }

            // Salvar configuração
            Button {
                text: "💾 Salvar Configuração"
                enabled: experimentPath !== ""
                onClicked: {
                    // No EI, zones são salvos como quadrilaterais no floorPoints (string JSON)
                    var arenaStr = JSON.stringify(root.arenaPoints)
                    var floorStr = JSON.stringify(root.floorPoints)
                    if (ArenaConfigModel.saveConfigToPath(experimentPath, "", "", [], arenaStr, floorStr)) {
                        saveToast.show("Configuração salva!")
                    }
                }
                background: Rectangle {
                    radius: 7
                    color: parent.enabled ? (parent.hovered ? root.secondaryColor : root.primaryColor) : ThemeManager.surfaceDim
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
                contentItem: Text {
                    text: parent.text; color: ThemeManager.buttonText
                    Behavior on color { ColorAnimation { duration: 150 } }
                    font.pixelSize: 12; font.weight: Font.Bold
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                }
                leftPadding: 14; rightPadding: 14; topPadding: 7; bottomPadding: 7
            }
        }

        // ── Arena retangular — campo único ────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Arena como retângulo (proporção 2:1 aprox para EI)
            Item {
                id: arenaCell
                anchors.centerIn: parent
                // Proporção dinâmica baseada no vídeo
                width:  parent.width  > parent.height * root.videoAspectRatio ? parent.height * root.videoAspectRatio : parent.width
                height: width / root.videoAspectRatio

                // Fundo da arena
                Rectangle {
                    id: arenaRect
                    anchors.fill: parent
                    color: "#08080f"
                    border.color: ThemeManager.accent; border.width: 2
                    Behavior on color { ColorAnimation { duration: 200 } }
                    clip: true

                    // Preview do vídeo (campo único, sem crop de mosaico)
                    ShaderEffectSource {
                        anchors.fill: parent
                        visible: root.videoPath !== ""
                        sourceItem: framePreview
                        // Nenhum crop — mostra o vídeo inteiro
                        sourceRect: {
                            if (!framePreview || framePreview.width === 0) return Qt.rect(0,0,0,0)
                            var cr = framePreview.contentRect
                            return Qt.rect(cr.x, cr.y, cr.width, cr.height)
                        }
                        opacity: 0.9
                    }

                    // ── Canvas: paredes + chão ──────────────────────────────
                    Canvas {
                        id: arenaCanvas
                        anchors.fill: parent
                        onWidthChanged:  requestPaint()
                        onHeightChanged: requestPaint()
                        Component.onCompleted: requestPaint()

                        Connections {
                            target: root
                            function onArenaPointsChanged() { arenaCanvas.requestPaint() }
                            function onFloorPointsChanged()  { arenaCanvas.requestPaint() }
                            function onZonesChanged()        { arenaCanvas.requestPaint() }
                        }

                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            if (!root.arenaPoints[0] || !root.floorPoints[0]) return

                            var w = width, h = height
                            var ap = root.arenaPoints[0]
                            var fp = root.floorPoints[0]

                            function drawPoly(pts, fill, stroke, label) {
                                if (!pts || pts.length < 3) return
                                ctx.beginPath()
                                ctx.moveTo(pts[0].x * w, pts[0].y * h)
                                for (var i = 1; i < pts.length; i++) ctx.lineTo(pts[i].x * w, pts[i].y * h)
                                ctx.closePath()
                                if (fill) { ctx.fillStyle = fill; ctx.fill() }
                                if (stroke) { ctx.strokeStyle = stroke; ctx.lineWidth = 2; ctx.stroke() }
                                
                                if (label) {
                                    ctx.fillStyle = stroke
                                    ctx.font = "bold 10px sans-serif"
                                    ctx.fillText(label, pts[0].x * w + 5, pts[0].y * h + 15)
                                }
                            }

                            // 1. Paredas (Sombreamento das 4 paredes - Visual Apenas)
                            // ap: 0:TL, 1:TR, 2:BR, 3:BL
                            // fp: 0:G_TL, 1:G_TR, 2:G_BR, 3:G_BL | 4:P_TL, 5:P_TR, 6:P_BR, 7:P_BL
                            if (ap.length >= 4 && fp.length >= 8) {
                                var p_outer = [
                                    {x: ap[0].x*w, y: ap[0].y*h}, {x: ap[1].x*w, y: ap[1].y*h},
                                    {x: ap[2].x*w, y: ap[2].y*h}, {x: ap[3].x*w, y: ap[3].y*h}
                                ]
                                var p_inner = [
                                    {x: fp[0].x*w, y: fp[0].y*h}, {x: fp[5].x*w, y: fp[5].y*h},
                                    {x: fp[6].x*w, y: fp[6].y*h}, {x: fp[3].x*w, y: fp[3].y*h}
                                ]

                                // Top Wall (Red)
                                drawPoly([ap[0], ap[1], fp[5], fp[0]], "rgba(255, 0, 0, 0.1)", "rgba(255, 0, 0, 0.4)")
                                // Bottom Wall (Pink)
                                drawPoly([fp[3], fp[6], ap[2], ap[3]], "rgba(255, 0, 255, 0.1)", "rgba(255, 0, 255, 0.4)")
                                // Left Wall (Orange)
                                drawPoly([ap[0], fp[0], fp[3], ap[3]], "rgba(255, 170, 0, 0.1)", "rgba(255, 170, 0, 0.4)")
                                // Right Wall (Dark Brown)
                                drawPoly([ap[1], ap[2], fp[6], fp[5]], "rgba(62, 39, 35, 0.2)", "rgba(62, 39, 35, 0.5)")
                            }

                            // 2. Plataforma (Verde) - pontos 0-3 do floorPoints (Esquerda agora)
                            if (fp.length >= 4) {
                                drawPoly(fp.slice(0, 4), "rgba(0, 255, 0, 0.15)", "rgba(0, 255, 0, 0.8)", "Plataforma")
                            }

                            // 3. Grade (Ciano/Blue) - pontos 4-7 do floorPoints (Direita agora)
                            if (fp.length >= 8) {
                                drawPoly(fp.slice(4, 8), "rgba(0, 204, 255, 0.15)", "rgba(0, 204, 255, 0.8)", "Grade")
                            }
                        }
                    }

                    // ── Pontos de Parede (Dev Mode) ───────────────────────────
                    Repeater {
                        model: root.devMode ? 4 : 0
                        Rectangle {
                            z: 20; width: 12; height: 12; radius: 6
                            color: "#ff5500"; border.color: "white"; border.width: 1.5
                            property var pt: root.arenaPoints[0] ? root.arenaPoints[0][index] : {x:0,y:0}
                            x: arenaRect.width  * pt.x - width/2
                            y: arenaRect.height * pt.y - height/2
                            scale: interactionMa.dragOuterCorner === index ? 1.4 : 1.0
                            Behavior on scale { NumberAnimation { duration: 150 } }
                            Text {
                                anchors { bottom: parent.top; horizontalCenter: parent.horizontalCenter; bottomMargin: 1 }
                                text: ["TL","TR","BR","BL"][index]
                                color: "#ff5500"; font.pixelSize: 8; font.weight: Font.Bold
                            }
                        }
                    }

                    // ── Pontos de Chão (Dev Mode) ─────────────────────────────
                    Repeater {
                        model: root.devMode ? 4 : 0
                        Rectangle {
                            z: 21; width: 12; height: 12; radius: 2
                            color: "#00ccff"; border.color: "white"; border.width: 1.5
                            property var pt: root.floorPoints[0] ? root.floorPoints[0][index] : {x:0,y:0}
                            x: arenaRect.width  * pt.x - width/2
                            y: arenaRect.height * pt.y - height/2
                            scale: interactionMa.dragFloorCorner === index ? 1.4 : 1.0
                            Behavior on scale { NumberAnimation { duration: 150 } }
                        }
                    }

                    // ── Pontos de Grade (Dev Mode - Alt) ────────────────────
                    Repeater {
                        model: root.devMode ? 4 : 0
                        Rectangle {
                            z: 22; width: 14; height: 14; radius: 0
                            color: "#00ccff"; border.color: "white"; border.width: 2
                            property var pt: root.floorPoints[0] ? root.floorPoints[0][index + 4] : {x:0,y:0}
                            x: arenaRect.width  * pt.x - width/2
                            y: arenaRect.height * pt.y - height/2
                            scale: interactionMa.dragFloorCorner === (index + 4) ? 1.4 : 1.0
                            Behavior on scale { NumberAnimation { duration: 150 } }
                            Text { anchors.centerIn: parent; text: "G"; color: "black"; font.pixelSize: 8; font.weight: Font.Bold }
                        }
                    }

                    // ── Pontos de Plataforma (Dev Mode - Shift) ──────────────
                    Repeater {
                        model: root.devMode ? 4 : 0
                        Rectangle {
                            z: 22; width: 14; height: 14; radius: 7
                            color: "#00ff00"; border.color: "white"; border.width: 2
                            property var pt: root.floorPoints[0] ? root.floorPoints[0][index] : {x:0,y:0}
                            x: arenaRect.width  * pt.x - width/2
                            y: arenaRect.height * pt.y - height/2
                            scale: interactionMa.dragFloorCorner === index ? 1.4 : 1.0
                            Behavior on scale { NumberAnimation { duration: 150 } }
                            Text { anchors.centerIn: parent; text: "P"; color: "black"; font.pixelSize: 8; font.weight: Font.Bold }
                        }
                    }

                    // ── Badge CAM ─────────────────────────────────────────────
                    Rectangle {
                        visible: root.videoPath !== ""
                        anchors { top: parent.top; right: parent.right; margins: 4 }
                        radius: 3; color: "#0d1f10"; z: 10
                        border.color: "#3a8a50"; border.width: 1
                        width: camTxt.implicitWidth + 10; height: 16
                        Text {
                            id: camTxt; anchors.centerIn: parent
                            text: "CAM 1"; color: "#5aaa70"; font.pixelSize: 9
                        }
                    }

                    // ── Interação: arrastar zonas, paredes, chão ──────────────
                    MouseArea {
                        id: interactionMa
                        anchors.fill: parent
                        hoverEnabled: true
                        property int dragOuterCorner: -1
                        property int dragFloorCorner: -1

                        onPressed: (mouse) => {
                            var w = arenaRect.width, h = arenaRect.height
                            var fp = root.floorPoints[0] || []
                            var ap = root.arenaPoints[0] || []
                            dragOuterCorner = -1; dragFloorCorner = -1

                            // Removido capDist fixo para permitir selecionar pontos fora do frame
                            var capDist = Infinity 

                            if (mouse.modifiers & Qt.ShiftModifier) {
                                // Arrasta canto da Plataforma (índices 0-3 do floorPoints agora)
                                for (var c1 = 0; c1 < 4; c1++) {
                                    if (!fp[c1]) continue
                                    var fx1 = fp[c1].x * w, fy1 = fp[c1].y * h
                                    var df1 = (mouse.x-fx1)*(mouse.x-fx1)+(mouse.y-fy1)*(mouse.y-fy1)
                                    if (df1 < capDist) { capDist = df1; dragFloorCorner = c1 }
                                }
                            } else if (mouse.modifiers & Qt.AltModifier) {
                                // Arrasta canto da Grade (índices 4-7 do floorPoints agora)
                                for (var c2 = 4; c2 < 8; c2++) {
                                    if (!fp[c2]) continue
                                    var fx2 = fp[c2].x * w, fy2 = fp[c2].y * h
                                    var df2 = (mouse.x-fx2)*(mouse.x-fx2)+(mouse.y-fy2)*(mouse.y-fy2)
                                    if (df2 < capDist) { capDist = df2; dragFloorCorner = c2 }
                                }
                            } else if (mouse.modifiers & Qt.ControlModifier) {
                                // Arrasta canto mais próximo das paredes (arenaPoints 0-3)
                                for (var c3 = 0; c3 < 4; c3++) {
                                    if (!ap[c3]) continue
                                    var px = ap[c3].x * w, py = ap[c3].y * h
                                    var dd = (mouse.x-px)*(mouse.x-px)+(mouse.y-py)*(mouse.y-py)
                                    if (dd < capDist) { capDist = dd; dragOuterCorner = c3 }
                                }
                            }
                        }

                        onReleased: {
                            dragOuterCorner = -1; dragFloorCorner = -1
                        }

                        onPositionChanged: (mouse) => {
                            var w = arenaRect.width, h = arenaRect.height
                            // Permitir arrastar levemente para fora para ajustes de perspectiva (ex: de -25% a 125%)
                            var mx = Math.max(-w*0.25, Math.min(w*1.25, mouse.x))
                            var my = Math.max(-h*0.25, Math.min(h*1.25, mouse.y))

                            if (dragOuterCorner >= 0) {
                                var nap = JSON.parse(JSON.stringify(root.arenaPoints))
                                nap[0][dragOuterCorner] = { x: mx/w, y: my/h }
                                root.arenaPoints = nap
                                root.zonasEditadas(); showUnsavedToast()
                            } else if (dragFloorCorner >= 0) {
                                var nfp = JSON.parse(JSON.stringify(root.floorPoints))
                                nfp[0][dragFloorCorner] = { x: mx/w, y: my/h }
                                root.floorPoints = nfp
                                root.zonasEditadas(); showUnsavedToast()
                            }
                        }
                    }
                }
            }
        }
    }
}
