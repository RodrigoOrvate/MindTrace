// qml/ArenaSetup.qml
// Mosaico 2×2 — zonas arrastáveis via Shift+Esq (drag em tempo real).
// Dev Mode: exibe diâmetro das zonas; Shift+Scroll redimensiona.
// Vídeo offline: um VideoOutput no canto + ShaderEffectSource por campo (sem bug de hardware overlay).

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../core"
import "../core/Theme"
import QtMultimedia
import QtQuick.Dialogs
import MindTrace.Backend 1.0

Item {
    id: root

    property string experimentPath: ""
    property string context: ""
    property string pair1: ""
    property string pair2: ""
    property string pair3: ""
    property string videoPath: ""
    property bool   devMode:   false
    // Mode: "offline" (video already exists) or "ao_vivo" (camera, save when done)
    property string analysisMode: ""
    property string saveDirectory: ""
    property string liveOutputName: "live"
    property string cameraId: ""      // descrição da câmera selecionada para ao_vivo
    property bool   livePreviewFrozen: false
    property int    livePreviewFrameCount: 0

    // CA mode: hides pair selectors, uses borda/centro zone labels
    property string aparato:         "nor"
    property bool   caMode:          aparato === "campo_aberto" || aparato === "comportamento_complexo"
    // CC mode: caMode + sem zona de centro (sem centroRatio no canvas)
    property bool   ccMode:          aparato === "comportamento_complexo"
    property bool   showObjectZones: true   // false = esconde círculos de zona em CC sem objetos
    property int    numCampos: 3

    signal pairsEdited(string p1, string p2, string p3)
    signal analysisModeChangedExternally(string mode)
    signal zonasEditadas()  // Emitido quando as zonas são editadas (tempo real)

    MediaDevices { id: mediaDevices }

    Rectangle {
        id: unsavedToast
        visible: false
        width: unsavedText.implicitWidth + 24; height: 32; radius: 6
        color: "#1a0a0a"; border.color: "#ff4757"; border.width: 1
        anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 12 }
        opacity: 0; z: 100
        Behavior on opacity { NumberAnimation { duration: 180 } }
        Text {
            id: unsavedText
            anchors.centerIn: parent
            text: LanguageManager.tr3("Zonas editadas! Nao esqueca de Salvar", "Zones edited! Don't forget to Save", "Zonas editadas! No olvide Guardar")
            color: "#ff6b7a"; font.pixelSize: 11
        }
    }

    function showUnsavedToast() {
        unsavedToast.opacity = 1
        unsavedToast.visible = true
        unsavedToastTimer.restart()
    }

    Timer {
        id: unsavedToastTimer
        interval: 3000
        onTriggered: {
            unsavedToast.opacity = 0
            unsavedToast.visible = false
        }
    }

    // Chamado pela aba Gravação quando o usuário quer carregar um novo vídeo
    function openVideoLoader() { analysisModePrompt.open() }

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
        ArenaConfigModel.loadConfigFromPath(experimentPath)
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
        saveToast.show(LanguageManager.tr3("Arena importada! Clique em 'Salvar Configuracao' para confirmar.", "Arena imported! Click 'Save Configuration' to confirm.", "Arena importada! Haga clic en 'Guardar Configuracion' para confirmar."))
    }

    // 6 zonas, 2 por campo: { x: xRatio, y: yRatio, r: radiusRatio }
    property var zones: [
        {x: 0.3, y: 0.5, r: 0.12}, {x: 0.7, y: 0.5, r: 0.12},
        {x: 0.3, y: 0.5, r: 0.12}, {x: 0.7, y: 0.5, r: 0.12},
        {x: 0.3, y: 0.5, r: 0.12}, {x: 0.7, y: 0.5, r: 0.12}
    ]

    // NOVO: A borda externa agora é um polígono livre de 4 pontos (Topo das paredes)!
    property var arenaPoints: [
        [{x:0.02, y:0.02}, {x:0.98, y:0.02}, {x:0.98, y:0.98}, {x:0.02, y:0.98}],
        [{x:0.02, y:0.02}, {x:0.98, y:0.02}, {x:0.98, y:0.98}, {x:0.02, y:0.98}],
        [{x:0.02, y:0.02}, {x:0.98, y:0.02}, {x:0.98, y:0.98}, {x:0.02, y:0.98}]
    ]

    // (Mantenha o floorPoints aqui embaixo igualzinho)
    property var floorPoints: [
        [{x: 0.15, y: 0.15}, {x: 0.85, y: 0.15}, {x: 0.85, y: 0.85}, {x: 0.15, y: 0.85}],
        [{x: 0.15, y: 0.15}, {x: 0.85, y: 0.15}, {x: 0.85, y: 0.85}, {x: 0.15, y: 0.85}],
        [{x: 0.15, y: 0.15}, {x: 0.85, y: 0.15}, {x: 0.85, y: 0.85}, {x: 0.15, y: 0.85}]
    ]

    // Razão do quadrado central no Campo Aberto (relativo aos floorPoints)
    property real centroRatio: 0.5

    function zoneIdsForPair(pair) {
        if (!pair || pair.length < 2) return ["—", "—"]
        var a = pair[0], b = pair[1]
        if (a === b) return ["OBJ" + a, "OBJ" + a + "1"]
        return ["OBJ" + a, "OBJ" + b]
    }

    // ── COLOQUE A NOVA FUNÇÃO AQUI ──────────────────────────
    function getRadiusForObject(objId) {
        var match = objId.match(/OBJ([A-Z])/);
        if (!match) return 0.12;

        var letter = match[1];

        // A sua biblioteca exata da UFRN
        var pxSizes = {
            "A": 42, "B": 42, "C": 47, "G": 56,
            "F": 37, "J": 37, "N": 42, "D": 39,
            "R": 32, "E": 50, "P": 47, "I": 63
        };

        var px = pxSizes[letter];
        if (px === undefined) return 0.12; 

        // Regra de três: normaliza baseado no padrão de 93px (0.12)
        return (px / 93.0) * 0.12;
    }

    onExperimentPathChanged: {
        if (experimentPath !== "") {
            ArenaConfigModel.loadConfigFromPath(experimentPath);

            var meta = ExperimentManager.readMetadataFromPath(experimentPath);
            
            root.pair1 = meta.pair1 || "";
            root.pair2 = meta.pair2 || "";
            root.pair3 = meta.pair3 || "";
            root.centroRatio = meta.centroRatio || 0.5;
            
            var savedArena = ArenaConfigModel.getArenaPoints();
            var savedFloor = ArenaConfigModel.getFloorPoints();
            
            if (savedArena && savedArena !== "") {
                root.arenaPoints = JSON.parse(savedArena);
            }
            if (savedFloor && savedFloor !== "") {
                root.floorPoints = JSON.parse(savedFloor);
            }
            
            zoneInitTimer.restart();
        }
    }

    Connections {
        target: ArenaConfigModel
        onConfigChanged: zoneInitTimer.restart()
    }

    Timer {
        id: zoneInitTimer; interval: 60; repeat: false
        onTriggered: {
            var n = ArenaConfigModel.zoneCount()
            var nz = []
            
            for (var i = 0; i < 6; i++) {
                // Descobre de qual campo e de qual par este círculo pertence
                var campoIdx = Math.floor(i / 2)
                var campoPair = campoIdx === 0 ? root.pair1 : (campoIdx === 1 ? root.pair2 : root.pair3)
                
                // Extrai o ID ("OBJA", "OBJB", etc)
                var ids = root.zoneIdsForPair(campoPair)
                var objId = ids[i % 2]
                
                // Puxa o raio matemático automático baseado na letra
                var dynamicRadius = root.getRadiusForObject(objId)

                if (i < n) {
                    var z = ArenaConfigModel.zone(i)
                    // Em CC: usa raio salvo; em NOR: usa raio dinâmico baseado no objId
                    var radius = root.ccMode ? (z.radiusRatio || dynamicRadius) : dynamicRadius
                    nz.push({ x: z.xRatio, y: z.yRatio, r: radius })
                } else {
                    // Círculos novos também já nascem com o tamanho correto
                    nz.push({ x: (i % 2 === 0 ? 0.3 : 0.7), y: 0.5, r: dynamicRadius })
                }
            }
            zones = nz
            zonasEditadas()  // Avisa que as zonas mudaram (tempo real)
        }
    }

    // ── Player de vídeo offline ──────────────────────────────────────────────
    // Qt 6: MediaPlayer.videoOutput aponta para o VideoOutput; status → mediaStatus
    MediaPlayer {
        id: videoPlayer
        autoPlay: false
        videoOutput: framePreview
        onMediaStatusChanged: {
            // Quando o vídeo carrega, pulamos para 1 segundo (segurança contra tela preta)
            if (mediaStatus === MediaPlayer.LoadedMedia) {
                setPosition(1000)  // Qt 6: seek() → setPosition()
                pause()
            }
        }
    }

    // ── Preview de câmera ao vivo ────────────────────────────────────────────
    MediaDevices { id: arenaMediaDevices }

    CaptureSession {
        id: arenaCaptureSession
        videoOutput: null
        camera: Camera {
            id: arenaCamera
            active: false
        }
    }

    // Inicia/para câmera ao mudar cameraId ou analysisMode
    onCameraIdChanged: _updateCameraPreview()
    onAnalysisModeChanged: _updateCameraPreview()
    Timer {
        id: liveFreezeTimer
        interval: 2500
        repeat: false
        onTriggered: {
            if (analysisMode === "ao_vivo" && cameraId !== "" && arenaCamera.active) {
                arenaCamera.active = false
                livePreviewFrozen = true
            }
        }
    }

    Connections {
        target: framePreview.videoSink
        enabled: root.analysisMode === "ao_vivo"
        function onVideoFrameChanged(frame) {
            if (!frame || root.livePreviewFrozen || !arenaCamera.active)
                return
            root.livePreviewFrameCount += 1
            // Evita congelar frames iniciais (startup verde/instável) do driver.
            if (root.livePreviewFrameCount >= 12) {
                arenaCamera.active = false
                root.livePreviewFrozen = true
                liveFreezeTimer.stop()
            }
        }
    }

    function _updateCameraPreview() {
        if (analysisMode !== "ao_vivo" || cameraId === "") {
            liveFreezeTimer.stop()
            livePreviewFrozen = false
            livePreviewFrameCount = 0
            arenaCamera.active = false
            arenaCaptureSession.videoOutput = null
            videoPlayer.videoOutput = framePreview
            return
        }
        var devices = arenaMediaDevices.videoInputs
        for (var i = 0; i < devices.length; i++) {
            if (devices[i].description === cameraId) {
                arenaCamera.cameraDevice = devices[i]
                videoPlayer.videoOutput = null
                arenaCaptureSession.videoOutput = framePreview
                livePreviewFrozen = false
                livePreviewFrameCount = 0
                arenaCamera.active = true
                liveFreezeTimer.restart()
                return
            }
        }
        liveFreezeTimer.stop()
        livePreviewFrozen = false
        livePreviewFrameCount = 0
        arenaCaptureSession.videoOutput = null
        arenaCamera.active = false
    }

    function stopCameraPreview() {
        liveFreezeTimer.stop()
        livePreviewFrameCount = 0
        arenaCamera.active = false
        arenaCaptureSession.videoOutput = null
    }

    FileDialog {
        id: videoFileDialog
        title: "Selecionar Vídeo de Análise"
        nameFilters: ["Vídeos (*.mp4 *.mpg *.mpeg *.avi *.mov)", "Todos os arquivos (*)"]
        onAccepted: {
            videoPlayer.stop()
            root.videoPath = selectedFile.toString()  // Qt 6: fileUrl → selectedFile
            videoPlayer.source = selectedFile
        }
    }

    FolderDialog {
        id: saveFolderPicker
        title: LanguageManager.tr3("Selecionar pasta para gravacao", "Select recording folder", "Seleccionar carpeta de grabacion")
        onAccepted: savePathField.text = selectedFolder.toString().replace("file:///", "")
    }

    FileDialog {
        id: importFolderDialog
        title: "Selecionar arena_config.json do experimento de origem"
        nameFilters: ["Configuração de Arena (arena_config.json)", "JSON (*.json)", "Todos os arquivos (*)"]
        onAccepted: {
            var filePath = selectedFile.toString().replace("file:///", "")
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
                    background: Rectangle { radius: 7; color: parent.hovered ? ThemeManager.accentHover : ThemeManager.accent; Behavior on color { ColorAnimation { duration: 150 } } }
                    contentItem: Text { text: parent.text; color: ThemeManager.textPrimary; font.pixelSize: 12; font.weight: Font.Bold; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    leftPadding: 16; rightPadding: 16; topPadding: 8; bottomPadding: 8
                }
            }
        }
    }

    // Popup: análise offline ou ao vivo?
    Popup {
        id: analysisModePrompt
        width: 400; height: 280
        anchors.centerIn: parent
        modal: true; focus: true
        closePolicy: Popup.CloseOnEscape

        background: Rectangle {
            radius: 14; color: ThemeManager.surface; Behavior on color { ColorAnimation { duration: 200 } }
            border.color: ThemeManager.accent; border.width: 1; Behavior on border.color { ColorAnimation { duration: 200 } }
        }

        ColumnLayout {
            anchors { fill: parent; margins: 24 }
            spacing: 14

            Text {
                text: LanguageManager.tr3("Tipo de Analise", "Analysis Type", "Tipo de Analisis"); color: ThemeManager.textPrimary; Behavior on color { ColorAnimation { duration: 150 } }
                font.pixelSize: 16; font.weight: Font.Bold
            }

            Text {
                Layout.fillWidth: true
                text: LanguageManager.tr3("Escolha o modo de analise:", "Choose analysis mode:", "Elija el modo de analisis:")
                color: ThemeManager.textSecondary; font.pixelSize: 13; Behavior on color { ColorAnimation { duration: 150 } }
            }

            RowLayout {
                Layout.fillWidth: true; spacing: 12

                // Análise Offline
                Rectangle {
                    Layout.fillWidth: true; height: 80; radius: 8
                    color: offBtnMa.offlineHover ? ThemeManager.accentHover : ThemeManager.surfaceAlt
                    border.color: ThemeManager.accent; border.width: 2; Behavior on color { ColorAnimation { duration: 200 } }

                    property bool offlineHover: offBtnMa.containsMouse

                    ColumnLayout {
                        anchors.centerIn: parent; spacing: 4
                        Text {
                                text: "🎬  " + LanguageManager.tr3("Analise Offline", "Offline Analysis", "Analisis Offline"); color: ThemeManager.textPrimary; Behavior on color { ColorAnimation { duration: 150 } }
                            font.pixelSize: 13; font.weight: Font.Bold
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Text {
                                text: LanguageManager.tr3("Video pre-gravado", "Pre-recorded video", "Video pregrabado"); color: ThemeManager.textSecondary; Behavior on color { ColorAnimation { duration: 150 } }
                            font.pixelSize: 10; horizontalAlignment: Text.AlignHCenter
                        }
                    }
                    MouseArea {
                        id: offBtnMa; anchors.fill: parent
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.analysisMode = "offline"
                            root.saveDirectory = ""
                            analysisModePrompt.close()
                            videoFileDialog.open()
                        }
                    }
                }

                // Análise Ao Vivo
                Rectangle {
                    Layout.fillWidth: true; height: 80; radius: 8
                    color: liveBtnMa.liveHover ? ThemeManager.accentHover : ThemeManager.background; Behavior on color { ColorAnimation { duration: 200 } }
                    border.color: ThemeManager.success; border.width: 2; Behavior on border.color { ColorAnimation { duration: 200 } }

                    property bool liveHover: liveBtnMa.containsMouse

                    ColumnLayout {
                        anchors.centerIn: parent; spacing: 4
                        Text {
                            text: "📹  " + LanguageManager.tr3("Analise Ao Vivo", "Live Analysis", "Analisis En Vivo")
                            color: ThemeManager.textPrimary
                            Behavior on color { ColorAnimation { duration: 150 } }
                            font.pixelSize: 13; font.weight: Font.Bold
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Text {
                            text: LanguageManager.tr3("Camera ao vivo (grava video em arquivo)", "Live camera (records video to file)", "Camara en vivo (graba video en archivo)"); color: ThemeManager.textSecondary; Behavior on color { ColorAnimation { duration: 150 } }
                            font.pixelSize: 10; horizontalAlignment: Text.AlignHCenter
                        }
                    }
                    MouseArea {
                        id: liveBtnMa; anchors.fill: parent
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.analysisMode = "ao_vivo"
                            analysisModePrompt.close()
                            savePathField.text = root.saveDirectory
                            saveNameField.text = root.liveOutputName
                            saveDirDialog.open()
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true; spacing: 8
                Item { Layout.fillWidth: true }
                GhostButton {
                    text: "Cancelar"; onClicked: {
                        root.videoPath = ""
                        analysisModePrompt.close()
                    }
                }
            }
        }
    }

    // Dialog: escolher diretório para salvar vídeo ao vivo
    Popup {
        id: saveDirDialog
        anchors.centerIn: parent
        width: 440; height: 220
        modal: true; focus: true; closePolicy: Popup.CloseOnEscape
        background: Rectangle {
            radius: 14; color: ThemeManager.surface; Behavior on color { ColorAnimation { duration: 200 } }
            border.color: ThemeManager.accent; border.width: 1; Behavior on border.color { ColorAnimation { duration: 200 } }
        }
        ColumnLayout {
            anchors { fill: parent; margins: 20 }
            spacing: 12
            Text {
                text: LanguageManager.tr3("Selecionar pasta de gravacao", "Select recording folder", "Seleccionar carpeta de grabacion")
                color: ThemeManager.textPrimary
                Behavior on color { ColorAnimation { duration: 150 } }
                font.pixelSize: 15; font.weight: Font.Bold
            }
            RowLayout {
                Layout.fillWidth: true; spacing: 8
                TextField {
                    id: savePathField
                    Layout.fillWidth: true
                    placeholderText: LanguageManager.tr3("Cole o caminho ou clique Pesquisar...", "Paste path or click Browse...", "Pegue la ruta o haga clic en Buscar...")
                    color: ThemeManager.textPrimary
                    Behavior on color { ColorAnimation { duration: 150 } }
                    placeholderTextColor: ThemeManager.textPlaceholder; font.pixelSize: 12
                    onTextChanged: root.saveDirectory = text
                    background: Rectangle {
                        radius: 6; color: ThemeManager.background; Behavior on color { ColorAnimation { duration: 200 } }
                        border.color: savePathField.activeFocus ? ThemeManager.accent : ThemeManager.border; Behavior on border.color { ColorAnimation { duration: 200 } }
                        border.width: 1
                    }
                }
                Button {
                    text: LanguageManager.tr3("Pesquisar", "Browse", "Buscar")
                    onClicked: saveFolderPicker.open()
                    background: Rectangle {
                        radius: 6
                        color: parent.hovered ? ThemeManager.surfaceAlt : ThemeManager.surfaceDim; Behavior on color { ColorAnimation { duration: 200 } }
                        border.color: ThemeManager.border; border.width: 1
                    }
                    contentItem: Text {
                        text: parent.text; color: ThemeManager.textSecondary; Behavior on color { ColorAnimation { duration: 150 } }
                        font.pixelSize: 12; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                    leftPadding: 12; rightPadding: 12; topPadding: 8; bottomPadding: 8
                }
            }
            RowLayout {
                Layout.fillWidth: true; spacing: 8
                TextField {
                    id: saveNameField
                    Layout.fillWidth: true
                    placeholderText: LanguageManager.tr3("Nome do video (ex: sessao_rato_01)", "Video name (e.g., rat_session_01)", "Nombre del video (ej: sesion_rata_01)")
                    color: ThemeManager.textPrimary
                    Behavior on color { ColorAnimation { duration: 150 } }
                    placeholderTextColor: ThemeManager.textPlaceholder; font.pixelSize: 12
                    text: root.liveOutputName
                    onTextChanged: root.liveOutputName = text
                    background: Rectangle {
                        radius: 6; color: ThemeManager.background; Behavior on color { ColorAnimation { duration: 200 } }
                        border.color: saveNameField.activeFocus ? ThemeManager.accent : ThemeManager.border; Behavior on border.color { ColorAnimation { duration: 200 } }
                        border.width: 1
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Item { Layout.fillWidth: true }
                GhostButton { text: LanguageManager.tr3("Cancelar", "Cancel", "Cancelar"); onClicked: saveDirDialog.close() }
                Button {
                    text: LanguageManager.tr3("Confirmar", "Confirm", "Confirmar")
                    enabled: savePathField.text.trim().length > 0 && saveNameField.text.trim().length > 0
                    onClicked: {
                        root.saveDirectory = savePathField.text.trim()
                        root.liveOutputName = saveNameField.text.trim()
                        saveDirDialog.close()
                        cameraSelectPopup.open()
                    }
                    background: Rectangle {
                        radius: 8
                        color: parent.enabled ? (parent.hovered ? ThemeManager.accentHover : ThemeManager.accent) : ThemeManager.surfaceDim; Behavior on color { ColorAnimation { duration: 200 } }
                    }
                    contentItem: Text {
                        text: parent.text; color: ThemeManager.textPrimary; Behavior on color { ColorAnimation { duration: 150 } }
                        font.pixelSize: 13; font.weight: Font.Bold
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                    leftPadding: 18; rightPadding: 18; topPadding: 9; bottomPadding: 9
                }
            }
        }
    }

    // Popup: selecionar câmera para análise ao vivo
    Popup {
        id: cameraSelectPopup
        anchors.centerIn: parent
        width: 400; modal: true; focus: true; closePolicy: Popup.CloseOnEscape
        height: Math.min(80 + Math.max(1, mediaDevices.videoInputs.length) * 52 + 130, 460)
        background: Rectangle {
            radius: 14; color: ThemeManager.surface; Behavior on color { ColorAnimation { duration: 200 } }
            border.color: ThemeManager.success; border.width: 1
        }

        property int selectedIndex: 0

        onOpened: selectedIndex = 0

        ColumnLayout {
            anchors { fill: parent; margins: 20 }
            spacing: 12

            Text {
                text: "📹  " + LanguageManager.tr3("Selecionar Camera", "Select Camera", "Seleccionar Camara")
                color: ThemeManager.textPrimary; Behavior on color { ColorAnimation { duration: 150 } }
                font.pixelSize: 15; font.weight: Font.Bold
            }
            Text {
                Layout.fillWidth: true
                text: LanguageManager.tr3("Recomendado no DroidCam: MJPEG ou YUY2 (1280x720 @ 30 FPS). Evite AVC/H.264, pois pode causar tela verde.", "Recommended for DroidCam: MJPEG or YUY2 (1280x720 @ 30 FPS). Avoid AVC/H.264, as it may cause green video.", "Recomendado para DroidCam: MJPEG o YUY2 (1280x720 @ 30 FPS). Evite AVC/H.264, puede causar pantalla verde.")
                color: "#d8c26a"
                font.pixelSize: 11
                wrapMode: Text.Wrap
            }

            // Lista de câmeras
            ListView {
                Layout.fillWidth: true
                height: Math.min(mediaDevices.videoInputs.length * 52, 220)
                clip: true
                model: mediaDevices.videoInputs
                delegate: Rectangle {
                    width: ListView.view.width; height: 48; radius: 8
                    color: cameraSelectPopup.selectedIndex === index
                           ? Qt.rgba(0.15, 0.55, 0.25, 0.25)
                           : (camMa.containsMouse ? ThemeManager.surfaceAlt : ThemeManager.surfaceDim)
                    border.color: cameraSelectPopup.selectedIndex === index ? ThemeManager.success : ThemeManager.border
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 120 } }

                    ColumnLayout {
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 12; rightMargin: 12 }
                        spacing: 2
                        Text {
                            Layout.fillWidth: true
                            text: modelData.description
                            color: ThemeManager.textPrimary; Behavior on color { ColorAnimation { duration: 150 } }
                            font.pixelSize: 12; font.weight: Font.Medium
                            elide: Text.ElideRight
                        }
                        Text {
                            text: modelData.isDefault ? LanguageManager.tr3("Padrao", "Default", "Predeterminada") : ""
                            color: ThemeManager.success; font.pixelSize: 10
                            visible: modelData.isDefault
                        }
                    }
                    MouseArea {
                        id: camMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: cameraSelectPopup.selectedIndex = index
                    }
                }
            }

            // Mensagem quando sem câmeras
            Text {
                visible: mediaDevices.videoInputs.length === 0
                Layout.fillWidth: true
                text: LanguageManager.tr3("Nenhuma camera detectada.\nConecte uma camera USB e tente novamente.", "No camera detected.\nConnect a USB camera and try again.", "Ninguna camara detectada.\nConecte una camara USB e intente de nuevo.")
                color: ThemeManager.textSecondary; font.pixelSize: 12
                horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
            }

            RowLayout {
                Layout.fillWidth: true; spacing: 8
                Item { Layout.fillWidth: true }
                GhostButton { text: "Cancelar"; onClicked: { root.analysisMode = ""; cameraSelectPopup.close() } }
                Button {
                    text: LanguageManager.tr3("Iniciar ao Vivo", "Start Live", "Iniciar en Vivo")
                    enabled: mediaDevices.videoInputs.length > 0
                    onClicked: {
                        var idx = cameraSelectPopup.selectedIndex
                        if (idx >= 0 && idx < mediaDevices.videoInputs.length)
                            root.cameraId = mediaDevices.videoInputs[idx].description
                        cameraSelectPopup.close()
                        root.analysisModeChangedExternally("ao_vivo")
                    }
                    background: Rectangle {
                        radius: 8
                        color: parent.enabled ? (parent.hovered ? Qt.darker(ThemeManager.success, 1.15) : ThemeManager.success) : ThemeManager.surfaceDim
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                    contentItem: Text {
                        text: parent.text; color: "white"
                        font.pixelSize: 13; font.weight: Font.Bold
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                    leftPadding: 18; rightPadding: 18; topPadding: 9; bottomPadding: 9
                }
            }
        }
    }

    // ── Layout principal ─────────────────────────────────────────────────────
    ColumnLayout {
        anchors { fill: parent; margins: 16 }
        spacing: 10

        // ── Barra superior ───────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true; spacing: 8

            Text {
                            text: LanguageManager.tr3("Configuracao da Arena", "Arena Setup", "Configuracion de la Arena")
                color: ThemeManager.textPrimary
                Behavior on color { ColorAnimation { duration: 150 } }
                font.pixelSize: 14; font.weight: Font.Bold
            }
            Item { Layout.fillWidth: true }
            Text {
                // CA: scroll simples = centro | Ctrl+drag = paredes | Alt+drag = chão
                // CC: scroll = objetos | Shift+drag = mover | Ctrl+drag = paredes | Alt+drag = chão
                // NOR (devMode): scroll simples = objetos | Ctrl+drag = paredes | Alt+drag = chão
                text: root.ccMode
                      ? LanguageManager.tr3(
                          "\u{1F5B1} Scroll: +/- Zonas  |  Shift + Arrastar: Mover Zonas  |  Ctrl + Arrastar: Paredes  |  Alt + Arrastar: Chao",
                          "\u{1F5B1} Scroll: +/- Zones  |  Shift + Drag: Move Zones  |  Ctrl + Drag: Walls  |  Alt + Drag: Floor",
                          "\u{1F5B1} Scroll: +/- Zonas  |  Shift + Arrastrar: Mover Zonas  |  Ctrl + Arrastrar: Paredes  |  Alt + Arrastrar: Piso")
                      : root.caMode
                        ? LanguageManager.tr3(
                          "\u{1F5B1} Scroll: +/- Centro  |  Ctrl + Arrastar: Paredes  |  Alt + Arrastar: Chao",
                          "\u{1F5B1} Scroll: +/- Center  |  Ctrl + Drag: Walls  |  Alt + Drag: Floor",
                          "\u{1F5B1} Scroll: +/- Centro  |  Ctrl + Arrastrar: Paredes  |  Alt + Arrastrar: Piso")
                        : LanguageManager.tr3(
                          "\u{1F527} Dev Mode  |  Scroll: +/- Objetos  |  Shift + Arrastar: Objetos  |  Ctrl + Arrastar: Paredes  |  Alt + Arrastar: Chao",
                          "\u{1F527} Dev Mode  |  Scroll: +/- Objects  |  Shift + Drag: Objects  |  Ctrl + Drag: Walls  |  Alt + Drag: Floor",
                          "\u{1F527} Dev Mode  |  Scroll: +/- Objetos  |  Shift + Arrastrar: Objetos  |  Ctrl + Arrastrar: Paredes  |  Alt + Arrastrar: Piso")
                color: ThemeManager.textTertiary
                Behavior on color { ColorAnimation { duration: 150 } }
                font.pixelSize: 10; verticalAlignment: Text.AlignVCenter
            }

            // ── Editar Pares (apenas NOR — CA não tem pares de objetos) ──
            Button {
                id: editPairsBtn
                visible: !root.caMode
                            text: "✏ " + LanguageManager.tr3("Editar Pares", "Edit Pairs", "Editar Pares")
                onClicked: editPairsPopup.open()

                background: Rectangle {
                    radius: 6
                    color: editPairsBtn.hovered ? ThemeManager.surfaceHover : ThemeManager.background; Behavior on color { ColorAnimation { duration: 200 } }
                    border.color: editPairsBtn.hovered ? ThemeManager.border : ThemeManager.borderLight; Behavior on border.color { ColorAnimation { duration: 200 } }
                    border.width: 2
                }

                contentItem: Text {
                    text: parent.text
                    color: editPairsBtn.hovered ? ThemeManager.textPrimary : ThemeManager.textPlaceholder; Behavior on color { ColorAnimation { duration: 150 } }
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                leftPadding: 14; rightPadding: 14; topPadding: 6; bottomPadding: 6
            }

            // ── Dev Mode ──
            Button {
                id: devModeBtn
                text: root.devMode ? "🔧 Dev ON" : "🔧 Dev OFF"
                onClicked: root.devMode = !root.devMode
                
                background: Rectangle {
                    radius: 6
                    color: root.devMode ? (devModeBtn.hovered ? "#7a5500" : "#8a6200") : (devModeBtn.hovered ? ThemeManager.surfaceHover : ThemeManager.background); Behavior on color { ColorAnimation { duration: 200 } }
                    border.color: root.devMode ? "#c88000" : (devModeBtn.hovered ? ThemeManager.border : ThemeManager.borderLight); Behavior on border.color { ColorAnimation { duration: 200 } }
                    border.width: 2
                }
                
                contentItem: Text {
                    text: parent.text
                    color: root.devMode ? "#ffffff" : (devModeBtn.hovered ? ThemeManager.textPrimary : ThemeManager.textPlaceholder); Behavior on color { ColorAnimation { duration: 150 } }
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                
                // O padding força o botão a manter o seu tamanho independentemente do texto
                leftPadding: 14; rightPadding: 14; topPadding: 6; bottomPadding: 6
            }

            // ── Carregar Vídeo ────────────────────────────────────────────────
            Button {
                id: videoBtnRect
                text: root.analysisMode === "ao_vivo" && root.cameraId !== ""
                      ? "📹 " + LanguageManager.tr3("Camera Selecionada", "Camera Selected", "Camara Seleccionada")
                      : root.videoPath !== ""
                        ? "🎬 " + LanguageManager.tr3("Video OK", "Video OK", "Video OK")
                        : "🎬 " + LanguageManager.tr3("Carregar Video", "Load Video", "Cargar Video")
                onClicked: analysisModePrompt.open()
                
                background: Rectangle {
                    radius: 6
                    property bool active: root.videoPath !== "" || (root.analysisMode === "ao_vivo" && root.cameraId !== "")
                    color: active ? (videoBtnRect.hovered ? ThemeManager.success : ThemeManager.successLight) : (videoBtnRect.hovered ? ThemeManager.surfaceHover : ThemeManager.background); Behavior on color { ColorAnimation { duration: 200 } }
                    border.color: active ? ThemeManager.success : (videoBtnRect.hovered ? ThemeManager.border : ThemeManager.borderLight); Behavior on border.color { ColorAnimation { duration: 200 } }
                    border.width: 2
                }

                contentItem: Text {
                    text: parent.text
                    property bool active: root.videoPath !== "" || (root.analysisMode === "ao_vivo" && root.cameraId !== "")
                    color: active ? ThemeManager.textPrimary : (videoBtnRect.hovered ? ThemeManager.textPrimary : ThemeManager.textPlaceholder); Behavior on color { ColorAnimation { duration: 150 } }
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                
                // Mantém a área de clique grande e o botão estável
                leftPadding: 14; rightPadding: 14; topPadding: 6; bottomPadding: 6
            }

            // ── Importar Arena ───────────────────────────────────────────────
            Button {
                            text: "📥 " + LanguageManager.tr3("Importar Arena", "Import Arena", "Importar Arena")
                enabled: experimentPath !== ""
                onClicked: importFolderDialog.open()
                background: Rectangle {
                    radius: 6
                    color: parent.enabled ? (parent.hovered ? ThemeManager.surfaceAlt : ThemeManager.background) : ThemeManager.surfaceDim
                    Behavior on color { ColorAnimation { duration: 200 } }
                    border.color: parent.enabled ? (parent.hovered ? ThemeManager.accent : ThemeManager.borderLight) : ThemeManager.borderLight
                    Behavior on border.color { ColorAnimation { duration: 200 } }
                    border.width: 2
                }
                contentItem: Text {
                    text: parent.text
                    color: parent.enabled ? (parent.hovered ? ThemeManager.accent : ThemeManager.textSecondary) : ThemeManager.textTertiary
                    Behavior on color { ColorAnimation { duration: 150 } }
                    font.pixelSize: 11; font.weight: Font.Bold
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                }
                leftPadding: 14; rightPadding: 14; topPadding: 7; bottomPadding: 7
            }

            // ── Salvar Configuração ──────────────────────────────────────────
            Button {
                            text: "💾 " + LanguageManager.tr3("Salvar Configuracao", "Save Configuration", "Guardar Configuracion")
                enabled: experimentPath !== "" && (root.caMode || root.ccMode || pair1 !== "")
                onClicked: {
                    var allZones = []
                    for (var i = 0; i < 6; i++) {
                        var z = zones[i]
                        // r: z.r já salva o tamanho do objeto atualizado!
                        allZones.push({ "xRatio": z.x, "yRatio": z.y, "radiusRatio": z.r, "objectId": "" })
                    }
                    
                    // Empacota os polígonos 3D em texto (JSON) para o C++
                    var arenaStr = JSON.stringify(root.arenaPoints)
                    var floorStr = JSON.stringify(root.floorPoints)

                    var pairId = root.caMode ? "" : (pair1 + "/" + pair2 + "/" + pair3)
                    if (ArenaConfigModel.saveConfigToPath(experimentPath, pairId, "", allZones, arenaStr, floorStr)) {
                        if (root.caMode) {
                            ExperimentManager.updateCentroRatio(experimentPath, root.centroRatio)
                        }
                        saveToast.show("Configuração salva com sucesso!");
                    }
                }
                background: Rectangle {
                    radius: 7
                    color: parent.enabled ? (parent.hovered ? ThemeManager.accentHover : ThemeManager.accent) : ThemeManager.surfaceDim; Behavior on color { ColorAnimation { duration: 150 } }
                }
                contentItem: Text {
                    text: parent.text; color: ThemeManager.textPrimary; Behavior on color { ColorAnimation { duration: 150 } }
                    font.pixelSize: 12; font.weight: Font.Bold
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                }
                leftPadding: 14; rightPadding: 14; topPadding: 7; bottomPadding: 7
            }
        }

        // ── Mosaico 2×2 ──────────────────────────────────────────────────────
        GridLayout {
            Layout.fillWidth: true; Layout.fillHeight: true
            columns: 2; rowSpacing: 8; columnSpacing: 8

            // ── 3 Campos ─────────────────────────────────────────────────────
            Repeater {
                model: root.numCampos
                delegate: Item {
                    id: campoCell
                    Layout.fillWidth: true; Layout.fillHeight: true

                    property int    campoIndex: index
                    property string campoPair:  index === 0 ? root.pair1
                                              : index === 1 ? root.pair2
                                              : root.pair3
                    property var    campoIds:   root.zoneIdsForPair(campoPair)

                    ColumnLayout {
                        anchors { fill: parent; margins: 4 }
                        spacing: 4

                        // Rótulo
                        RowLayout {
                            Layout.fillWidth: true; spacing: 6
                            Text {
                                text: LanguageManager.tr3("Campo ", "Field ", "Campo ") + (campoCell.campoIndex + 1)
                                color: ThemeManager.textSecondary
                                Behavior on color { ColorAnimation { duration: 150 } }
                                font.pixelSize: 11; font.weight: Font.Bold
                            }
                            Rectangle {
                                visible: !root.caMode && campoCell.campoPair !== ""
                                radius: 3; color: ThemeManager.background; Behavior on color { ColorAnimation { duration: 200 } }
                                border.color: ThemeManager.accent; border.width: 1; Behavior on border.color { ColorAnimation { duration: 200 } }
                                implicitWidth: pairTxt.implicitWidth + 10; implicitHeight: 16
                                Text {
                                    id: pairTxt; anchors.centerIn: parent
                                text: LanguageManager.tr3("Par ", "Pair ", "Par ") + campoCell.campoPair
                                    color: ThemeManager.accent
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    font.pixelSize: 9
                                }
                            }
                            Item { Layout.fillWidth: true }
                        }

                        // Arena quadrada
                        Item {
                            Layout.fillWidth: true; Layout.fillHeight: true

                            Rectangle {
                                id: arenaRect
                                width:  Math.min(parent.width, parent.height)
                                height: width
                                anchors.centerIn: parent
                                color: ThemeManager.background; Behavior on color { ColorAnimation { duration: 200 } }
                                border.color: ThemeManager.accent; border.width: 2; Behavior on border.color { ColorAnimation { duration: 200 } }
                                clip: true

                                ShaderEffectSource {
                                    anchors.fill: parent
                                    visible: root.videoPath !== "" || (root.analysisMode === "ao_vivo" && root.cameraId !== "")
                                    sourceItem: framePreview

                                    // Recorta o quadrante 2×2 correspondente ao campo
                                    sourceRect: {
                                        var _fp = framePreview
                                        if (!_fp || _fp.width === 0) return Qt.rect(0,0,0,0)

                                        // Puxa as coordenadas EXATAS do vídeo, ignorando faixas pretas
                                        var cr = _fp.contentRect
                                        var cw = cr.width / 2
                                        var ch = cr.height / 2
                                        var cx = cr.x
                                        var cy = cr.y

                                        // Divide o quadrado do vídeo igual por igual
                                        if (campoCell.campoIndex === 0) return Qt.rect(cx,      cy,      cw, ch) // Topo-Esq (Campo 1)
                                        if (campoCell.campoIndex === 1) return Qt.rect(cx + cw, cy,      cw, ch) // Topo-Dir (Campo 2)
                                        return Qt.rect(cx,      cy + ch, cw, ch) // Baixo-Esq (Campo 3)
                                    }
                                    opacity: 0.9
                                }

                                // ── Limites 3D da Arena (Paredes + Chão Livres) ───────────
                                Canvas {
                                    id: arenaCanvas
                                    anchors.fill: parent
                                    visible: true

                                    onWidthChanged: requestPaint()
                                    onHeightChanged: requestPaint()
                                    Component.onCompleted: requestPaint()

                                    Connections {
                                        target: root
                                        onArenaPointsChanged: arenaCanvas.requestPaint()
                                        onFloorPointsChanged: arenaCanvas.requestPaint()
                                        onDevModeChanged:     arenaCanvas.requestPaint()
                                        onCaModeChanged:      arenaCanvas.requestPaint()
                                        onNumCamposChanged:   arenaCanvas.requestPaint()
                                    }
                                    Connections {
                                        target: LanguageManager
                                        function onCurrentLanguageChanged() { arenaCanvas.requestPaint() }
                                    }

                                    onPaint: {
                                        var ctx = getContext("2d")
                                        ctx.clearRect(0, 0, width, height)
                                        var ci = campoCell.campoIndex
                                        if (!root.arenaPoints || !root.floorPoints) return
                                        var ap = root.arenaPoints[ci]
                                        var fp = root.floorPoints[ci]
                                        if (!ap || !fp) return
                                        var w = width, h = height
                                        var oTL={x:ap[0].x*w,y:ap[0].y*h}, oTR={x:ap[1].x*w,y:ap[1].y*h}
                                        var oBR={x:ap[2].x*w,y:ap[2].y*h}, oBL={x:ap[3].x*w,y:ap[3].y*h}
                                        var iTL={x:fp[0].x*w,y:fp[0].y*h}, iTR={x:fp[1].x*w,y:fp[1].y*h}
                                        var iBR={x:fp[2].x*w,y:fp[2].y*h}, iBL={x:fp[3].x*w,y:fp[3].y*h}
                                        function poly(pts,f,s){
                                            ctx.beginPath(); ctx.moveTo(pts[0].x,pts[0].y)
                                            for(var k=1;k<pts.length;k++) ctx.lineTo(pts[k].x,pts[k].y)
                                            ctx.closePath(); ctx.fillStyle=f; ctx.fill()
                                            ctx.lineWidth=1; ctx.strokeStyle=s; ctx.stroke()
                                        }

                                        if (root.caMode) {
                                            // --- MODO CA / CC ---
                                            var midX = (iTL.x + iTR.x + iBR.x + iBL.x) / 4
                                            var midY = (iTL.y + iTR.y + iBR.y + iBL.y) / 4

                                            if (!root.ccMode) {
                                                // Centro — só CA (não CC)
                                                var cTL={ x: midX + (iTL.x - midX) * root.centroRatio, y: midY + (iTL.y - midY) * root.centroRatio }
                                                var cTR={ x: midX + (iTR.x - midX) * root.centroRatio, y: midY + (iTR.y - midY) * root.centroRatio }
                                                var cBR={ x: midX + (iBR.x - midX) * root.centroRatio, y: midY + (iBR.y - midY) * root.centroRatio }
                                                var cBL={ x: midX + (iBL.x - midX) * root.centroRatio, y: midY + (iBL.y - midY) * root.centroRatio }
                                                poly([cTL,cTR,cBR,cBL], "rgba(255,0,255,0.2)", "rgba(255,0,255,0.8)")
                                                ctx.font = "bold 10px sans-serif"; ctx.fillStyle = "white"
                                                ctx.fillText(LanguageManager.tr3("Centro", "Center", "Centro"), midX - 15, midY + 4)
                                            }

                                            // Borda (chão)
                                            ctx.globalCompositeOperation = "destination-over"
                                            poly([iTL,iTR,iBR,iBL], "rgba(0,255,255,0.15)", "rgba(0,255,255,0.6)")
                                            ctx.globalCompositeOperation = "source-over"

                                            // Paredes (área entre chão e arena)
                                            poly([oTL,oTR,iTR,iTL],"rgba(255,255,255,0.03)", "rgba(255,255,255,0.15)")
                                            poly([iBL,iBR,oBR,oBL],"rgba(255,255,255,0.03)", "rgba(255,255,255,0.15)")
                                            poly([oTL,iTL,iBL,oBL],"rgba(255,255,255,0.03)", "rgba(255,255,255,0.15)")
                                            poly([iTR,oTR,oBR,iBR],"rgba(255,255,255,0.03)", "rgba(255,255,255,0.15)")

                                            // Labels
                                            ctx.font = "bold 10px sans-serif"
                                            ctx.fillStyle = "rgba(255,255,255,0.7)"
                                            if (!root.ccMode) ctx.fillText(LanguageManager.tr3("Borda", "Border", "Borde"), (iTL.x + (midX + (iTL.x-midX)*root.centroRatio))/2 - 15, midY + 4)
                                            ctx.fillText(LanguageManager.tr3("Parede", "Wall", "Pared"), (oTL.x + iTL.x)/2 - 15, midY + 4)
                                        } else {
                                            // --- MODO RECONHECIMENTO (NOR/RO) ---
                                            // Chão
                                            poly([iTL,iTR,iBR,iBL], "rgba(255,0,255,0.12)", "rgba(255,0,255,0.5)") 
                                            // Paredes coloridas
                                            poly([oTL,oTR,iTR,iTL],"rgba(255,0,0,0.12)",  "rgba(255,0,0,0.5)") 
                                            poly([iBL,iBR,oBR,oBL],"rgba(0,255,0,0.12)",  "rgba(0,255,0,0.5)") 
                                            poly([oTL,iTL,iBL,oBL],"rgba(0,255,255,0.12)","rgba(0,255,255,0.5)")
                                            poly([iTR,oTR,oBR,iBR],"rgba(255,255,0,0.12)","rgba(255,255,0,0.5)")

                                            // Labels NOR
                                            ctx.font = "bold 10px sans-serif"; ctx.fillStyle = "rgba(255,0,255,0.8)"
                                            ctx.fillText(LanguageManager.tr3("Chao", "Floor", "Suelo"), (iTL.x+iBR.x)/2 - 15, (iTL.y+iBR.y)/2)
                                            ctx.fillStyle = "rgba(255,255,255,0.6)"
                                            ctx.fillText(LanguageManager.tr3("Parede", "Wall", "Pared"), (oTL.x+iTL.x)/2 - 15, (oTL.y+iTL.y)/2)
                                        }

                                        // Borda da arena total
                                        ctx.strokeStyle="rgba(255,170,0,0.8)"; ctx.lineWidth=2
                                        ctx.beginPath(); ctx.moveTo(oTL.x,oTL.y)
                                        ctx.lineTo(oTR.x,oTR.y); ctx.lineTo(oBR.x,oBR.y); ctx.lineTo(oBL.x,oBL.y)
                                        ctx.closePath(); ctx.stroke()
                                    }
                                }

                                // ── Zona A (vinho) ────────────────────────────
                                Rectangle {
                                    id: zoneA
                                    visible: (!root.caMode || root.ccMode) && root.showObjectZones
                                    property var zd: root.zones[campoCell.campoIndex * 2]
                                    width:  arenaRect.width  * zd.r * 2
                                    height: width; radius: width / 2
                                    x: arenaRect.width  * zd.x - width  / 2
                                    y: arenaRect.height * zd.y - height / 2
                                    color: "#40ab3d4c"; border.color: "#ab3d4c"; border.width: 2

                                    Column {
                                        anchors.centerIn: parent; spacing: 1
                                        Text {
                                            visible: !root.ccMode
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: campoCell.campoIds[0]; color: ThemeManager.textPrimary
                                            font.pixelSize: Math.max(7, zoneA.width * 0.22); font.weight: Font.Bold
                                        }
                                        Text {
                                            visible: root.devMode
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: Math.round(zoneA.zd.r * arenaRect.width * 2) + "px Ø"
                                            color: "#ffcc00"; font.pixelSize: Math.max(6, zoneA.width * 0.16)
                                        }
                                    }
                                }

                                // ── Zona B (azul) ─────────────────────────────
                                Rectangle {
                                    id: zoneB
                                    visible: (!root.caMode || root.ccMode) && root.showObjectZones
                                    property var zd: root.zones[campoCell.campoIndex * 2 + 1]
                                    width:  arenaRect.width  * zd.r * 2
                                    height: width; radius: width / 2
                                    x: arenaRect.width  * zd.x - width  / 2
                                    y: arenaRect.height * zd.y - height / 2
                                    color: "#404466aa"; border.color: "#4466aa"; border.width: 2

                                    Column {
                                        anchors.centerIn: parent; spacing: 1
                                        Text {
                                            visible: !root.ccMode
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: campoCell.campoIds[1]; color: "#e8e8f0"
                                            font.pixelSize: Math.max(7, zoneB.width * 0.22); font.weight: Font.Bold
                                        }
                                        Text {
                                            visible: root.devMode
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: Math.round(zoneB.zd.r * arenaRect.width * 2) + "px Ø"
                                            color: "#ffcc00"; font.pixelSize: Math.max(6, zoneB.width * 0.16)
                                        }
                                    }
                                }

                                // ── Pontos de Parede (Dev Mode) ───────────────────────────
                                Repeater {
                                    model: root.devMode ? 4 : 0
                                    Rectangle {
                                        z: 20; width: 12; height: 12; radius: 6
                                        color: "#ff5500"; border.color: "white"; border.width: 1.5
                                        property var pt: root.arenaPoints[campoCell.campoIndex] ? root.arenaPoints[campoCell.campoIndex][index] : {x:0,y:0}
                                        x: arenaRect.width  * pt.x - width/2
                                        y: arenaRect.height * pt.y - height/2
                                        scale: (interactionMa.dragOuterCorner === index) ? 1.4 : 1.0
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
                                        property var pt: root.floorPoints[campoCell.campoIndex] ? root.floorPoints[campoCell.campoIndex][index] : {x:0,y:0}
                                        x: arenaRect.width  * pt.x - width/2
                                        y: arenaRect.height * pt.y - height/2
                                        scale: (interactionMa.dragFloorCorner === index) ? 1.4 : 1.0
                                        Behavior on scale { NumberAnimation { duration: 150 } }
                                        Text {
                                            anchors { top: parent.bottom; horizontalCenter: parent.horizontalCenter; topMargin: 1 }
                                            text: ["TL","TR","BR","BL"][index]
                                            color: "#00ccff"; font.pixelSize: 8; font.weight: Font.Bold
                                        }
                                    }
                                }

                                // ── Badge CAM (overlay canto sup-dir) ─────────
                                Rectangle {
                                    visible: root.videoPath !== ""
                                    anchors { top: parent.top; right: parent.right; margins: 4 }
                                    radius: 3; color: "#0d1f10"
                                    border.color: "#3a8a50"; border.width: 1
                                    width: camBadgeTxt.implicitWidth + 10; height: 16
                                    z: 10
                                    Text {
                                        id: camBadgeTxt; anchors.centerIn: parent
                                        text: "CAM " + (campoCell.campoIndex + 1)
                                        color: "#5aaa70"; font.pixelSize: 9
                                    }
                                }

                                // ── Overlay de interação ──────────────────────
                                MouseArea {
                                    id: interactionMa
                                    anchors.fill: parent
                                    z: 100
                                    acceptedButtons: Qt.LeftButton
                                    hoverEnabled: true // Para o tracker de debug
                                    
                                    property int dragZoneIdx: -1
                                    property int dragOuterCorner: -1
                                    property int dragFloorCorner: -1

                                    function onPressedHandler(mouse) {
                                        // No modo CA: Ctrl e Alt funcionam sem devMode
                                        // No modo CC: Shift funciona para zonas
                                        // No modo NOR: tudo requer devMode
                                        var needsDev = !root.caMode && !root.ccMode
                                        if (needsDev && !root.devMode) return;
                                        var capturingDist = 900;
                                        var fp = root.floorPoints[campoCell.campoIndex]
                                        var w = arenaRect.width, h = arenaRect.height

                                        if (mouse.modifiers & Qt.ShiftModifier) {
                                            if (!root.devMode && !root.ccMode) return;  // Shift (objetos) requer devMode ou ccMode
                                            if (root.ccMode && !root.showObjectZones) return;  // CC sem objetos: sem drag de zonas
                                            var i0 = campoCell.campoIndex * 2, i1 = i0 + 1
                                            var cx0 = root.zones[i0].x * w, cy0 = root.zones[i0].y * h
                                            var cx1 = root.zones[i1].x * w, cy1 = root.zones[i1].y * h
                                            var d0 = (mouse.x-cx0)*(mouse.x-cx0)+(mouse.y-cy0)*(mouse.y-cy0)
                                            var d1 = (mouse.x-cx1)*(mouse.x-cx1)+(mouse.y-cy1)*(mouse.y-cy1)
                                            dragZoneIdx = d0 <= d1 ? i0 : i1
                                        } else if (mouse.modifiers & Qt.ControlModifier) {
                                            // Ctrl funciona em CA e CC sem devMode
                                            var ap = root.arenaPoints[campoCell.campoIndex]
                                            // SEM limite de distância: sempre captura o canto mais próximo
                                            // mesmo se estiver fora do quadrante visível
                                            dragOuterCorner = -1
                                            var minDistOuter = Infinity
                                            for (var c=0; c<4; c++) {
                                                var px = ap[c].x * w, py = ap[c].y * h
                                                var dist = (mouse.x-px)*(mouse.x-px) + (mouse.y-py)*(mouse.y-py)
                                                if (dist < minDistOuter) { minDistOuter = dist; dragOuterCorner = c }
                                            }
                                        } else if (mouse.modifiers & Qt.AltModifier) {
                                            var minDistFloor = capturingDist; dragFloorCorner = -1
                                            for (var c=0; c<4; c++) {
                                                var fx = fp[c].x * w, fy = fp[c].y * h
                                                var distF = (mouse.x-fx)*(mouse.x-fx)+(mouse.y-fy)*(mouse.y-fy)
                                                if (distF < minDistFloor) { minDistFloor = distF; dragFloorCorner = c }
                                            }
                                        }
                                    }

                                    onPressed: (mouse) => onPressedHandler(mouse)
                                    onReleased: { dragZoneIdx = -1; dragOuterCorner = -1; dragFloorCorner = -1 }

                                    onPositionChanged: (mouse) => {
                                        // No modo CC: zonas podem ser arrastadas
                                        // No modo NOR, requer devMode; no CA, Ctrl/Alt funcionam sempre
                                        var allowDrag = root.devMode || root.caMode || root.ccMode
                                        if (!allowDrag) return;
                                        var w = arenaRect.width, h = arenaRect.height

                                        // Clamp para zonas e chão (devem ficar dentro do quadrante)
                                        var mx = Math.max(0, Math.min(w, mouse.x))
                                        var my = Math.max(0, Math.min(h, mouse.y))

                                        if (dragZoneIdx >= 0) {
                                            // Zonas podem ser arrastadas em devMode OU ccMode (com objetos habilitados)
                                            if (!root.devMode && !root.ccMode) return;
                                            if (root.ccMode && !root.showObjectZones) return;
                                            var nz = root.zones.slice()
                                            nz[dragZoneIdx] = { x: mx/w, y: my/h, r: root.zones[dragZoneIdx].r }
                                            root.zones = nz
                                            root.zonasEditadas(); showUnsavedToast()
                                        } else if (dragOuterCorner >= 0) {
                                            // Pontos de PAREDE podem sair do quadrante (sem clamp)
                                            var rawX = mouse.x / w
                                            var rawY = mouse.y / h
                                            var nap = root.arenaPoints.slice()
                                            var ptsAp = JSON.parse(JSON.stringify(nap[campoCell.campoIndex]))
                                            ptsAp[dragOuterCorner] = { x: rawX, y: rawY }
                                            nap[campoCell.campoIndex] = ptsAp
                                            root.arenaPoints = nap
                                            root.zonasEditadas(); showUnsavedToast()
                                        } else if (dragFloorCorner >= 0) {
                                            var nfp = root.floorPoints.slice()
                                            var ptsFp = JSON.parse(JSON.stringify(nfp[campoCell.campoIndex]))
                                            ptsFp[dragFloorCorner] = { x: mx/w, y: my/h }
                                            nfp[campoCell.campoIndex] = ptsFp
                                            root.floorPoints = nfp
                                            root.zonasEditadas(); showUnsavedToast()
                                        }
                                    }

                                    onWheel: (wheel) => {
                                        // Modo CC: scroll redimensiona zonas (apenas se objetos habilitados)
                                        if (root.ccMode && root.showObjectZones && (wheel.modifiers === Qt.NoModifier || (wheel.modifiers & Qt.ShiftModifier))) {
                                            wheel.accepted = true
                                            var i0 = campoCell.campoIndex * 2, i1 = i0 + 1
                                            var dx0 = wheel.x - root.zones[i0].x * arenaRect.width
                                            var dy0 = wheel.y - root.zones[i0].y * arenaRect.height
                                            var dx1 = wheel.x - root.zones[i1].x * arenaRect.width
                                            var dy1 = wheel.y - root.zones[i1].y * arenaRect.height
                                            var ti = (dx0*dx0+dy0*dy0) <= (dx1*dx1+dy1*dy1) ? i0 : i1
                                            var step2 = wheel.angleDelta.y > 0 ? 1.05 : 0.952
                                            var nzW = root.zones.slice()
                                            nzW[ti] = { x: nzW[ti].x, y: nzW[ti].y, r: Math.max(0.04, Math.min(0.4, nzW[ti].r * step2)) }
                                            root.zones = nzW; root.zonasEditadas(); showUnsavedToast()
                                            return
                                        }
                                        // No modo CA: scroll simples (sem modificador ou com Alt)
                                        // ajusta centroRatio. Não requer devMode.
                                        if (root.caMode && !root.ccMode && (wheel.modifiers === Qt.NoModifier || (wheel.modifiers & Qt.AltModifier))) {
                                            wheel.accepted = true
                                            var step = 0.02
                                            if (wheel.angleDelta.y > 0) root.centroRatio = Math.min(0.95, root.centroRatio + step)
                                            else if (wheel.angleDelta.y < 0) root.centroRatio = Math.max(0.05, root.centroRatio - step)
                                            arenaCanvas.requestPaint()
                                            root.zonasEditadas(); showUnsavedToast()
                                            return
                                        }
                                        // No modo NOR (devMode): scroll simples redimensiona o objeto mais próximo
                                        if (!root.caMode && root.devMode &&
                                                (wheel.modifiers === Qt.NoModifier || (wheel.modifiers & Qt.ShiftModifier))) {
                                            wheel.accepted = true
                                            var i0 = campoCell.campoIndex * 2, i1 = i0 + 1
                                            var dx0 = wheel.x - root.zones[i0].x * arenaRect.width
                                            var dy0 = wheel.y - root.zones[i0].y * arenaRect.height
                                            var dx1 = wheel.x - root.zones[i1].x * arenaRect.width
                                            var dy1 = wheel.y - root.zones[i1].y * arenaRect.height
                                            var ti = (dx0*dx0+dy0*dy0) <= (dx1*dx1+dy1*dy1) ? i0 : i1
                                            var step2 = wheel.angleDelta.y > 0 ? 1.05 : 0.952
                                            var nzW = root.zones.slice()
                                            nzW[ti] = { x: nzW[ti].x, y: nzW[ti].y, r: Math.max(0.04, Math.min(0.4, nzW[ti].r * step2)) }
                                            root.zones = nzW; root.zonasEditadas(); showUnsavedToast()
                                            return
                                        }
                                        wheel.accepted = false
                                    }
                                }

                                // Tracker de mouse para debug visual (apenas em modo dev)
                                Rectangle {
                                    width: 14; height: 14; radius: 7; color: "#ff00ff"; opacity: 0.6; z: 110
                                    x: interactionMa.mouseX - 7; y: interactionMa.mouseY - 7
                                    visible: root.devMode && interactionMa.containsMouse
                                    border.color: "white"; border.width: 1
                                    
                                    Text {
                                        anchors.bottom: parent.top; anchors.horizontalCenter: parent.horizontalCenter
                                        text: "X: " + Math.round(interactionMa.mouseX) + " Y: " + Math.round(interactionMa.mouseY)
                                        color: "magenta"; font.pixelSize: 10; font.weight: Font.Bold
                                    }
                                }

                                // Placeholder quando par não definido e sem vídeo
                                Text {
                                    anchors.centerIn: parent
                                    visible: !root.caMode && campoCell.campoPair === "" && root.videoPath === ""
                                text: LanguageManager.tr3("Par nao definido", "Pair not set", "Par no definido")
                                    color: "white"; opacity: 0.3; font.pixelSize: 10
                                }
                            }
                        }
                    }
                }
            }

            // ── Célula vazia: VideoOutput mestre + controles ──────────────────
            // masterVideoOut renderiza o vídeo inteiro aqui. ShaderEffectSource
            // nos campos acima captura esse item (via scene graph, não hardware overlay).
            Rectangle {
                Layout.fillWidth: true; Layout.fillHeight: true
                color: "#08080f"; border.color: "#1a1a2e"; border.width: 1; radius: 2

                property bool hasMedia: root.videoPath !== "" || (root.analysisMode === "ao_vivo" && root.cameraId !== "")

                ColumnLayout {
                    anchors { fill: parent; margins: 8 }
                    spacing: 6
                    visible: parent.hasMedia

                    // VideoOutput mestre — ocupa a maior parte da célula
                    // Offline: alimentado por MediaPlayer. Ao vivo: alimentado por CaptureSession.
                    VideoOutput {
                        id: framePreview
                        Layout.fillWidth: true; Layout.fillHeight: true
                        fillMode: VideoOutput.PreserveAspectFit
                        opacity: 0.5
                    }

                    // Status do player (somente offline)
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: {
                            if (root.analysisMode === "ao_vivo") return ""
                            var s = videoPlayer.mediaStatus
                            if (s === MediaPlayer.LoadingMedia)  return "⏳ Carregando…"
                            if (s === MediaPlayer.InvalidMedia)  return "⚠ Formato invalido"
                            if (s === MediaPlayer.NoMedia)       return "Sem midia"
                            return ""
                        }
                        color: videoPlayer.mediaStatus === MediaPlayer.InvalidMedia ? ThemeManager.error : ThemeManager.textSecondary
                        font.pixelSize: 9
                        visible: text !== ""
                    }

                    // Controles
                    RowLayout {
                        Layout.fillWidth: true; spacing: 6

                        Text {
                            text: root.analysisMode === "ao_vivo"
                                  ? "\u{1F4F9} " + LanguageManager.tr3("Camera ao vivo", "Live camera", "Camara en vivo")
                                  : "\u{1F4F7} Frame capturado"
                            color: ThemeManager.success; font.pixelSize: 9; opacity: 0.8
                        }

                        Item { Layout.fillWidth: true }

                        // Remover vídeo (somente offline)
                        Rectangle {
                            visible: root.analysisMode !== "ao_vivo"
                            height: 24; radius: 5
                            implicitWidth: rmLbl.implicitWidth + 16
                            color: rmMa.containsMouse ? ThemeManager.accentHover : ThemeManager.surfaceDim
                            Behavior on color { ColorAnimation { duration: 150 } }
                            border.color: ThemeManager.accent; border.width: 1
                            Text {
                                id: rmLbl; anchors.centerIn: parent
                                text: "✕ Remover"; color: ThemeManager.error
                                font.pixelSize: 10
                            }
                            MouseArea {
                                id: rmMa; anchors.fill: parent
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    videoPlayer.stop()
                                    root.videoPath = ""
                                }
                            }
                        }
                    }
                }

                // Placeholder sem mídia
                Column {
                    anchors.centerIn: parent
                    spacing: 6
                    visible: !parent.hasMedia
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.analysisMode === "ao_vivo" ? "\u{1F4F9}" : "\u{1F3AC}"
                        font.pixelSize: 22; opacity: 0.15
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.analysisMode === "ao_vivo"
                              ? LanguageManager.tr3("Selecione uma camera\n(clique em Carregar Video)", "Select a camera\n(click Load Video)", "Seleccione una camara\n(clic en Cargar Video)")
                              : LanguageManager.tr3("Analise offline\n(camera 4 nao usada)", "Offline analysis\n(camera 4 not used)", "Analisis offline\n(camara 4 no usada)")
                        color: ThemeManager.border; font.pixelSize: 9
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
        }
    }

    // ── Popup para Editar Pares ─────────────────────────────────────────────
    Popup {
        id: editPairsPopup
        anchors.centerIn: parent
        width: 340; height: 286
        modal: true; focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        
        // Quando abre, preenche os campos com os pares atuais
        onOpened: {
            editP1.text = root.pair1
            editP2.text = root.pair2
            editP3.text = root.pair3
        }

        background: Rectangle {
            radius: 12; color: ThemeManager.surface; Behavior on color { ColorAnimation { duration: 200 } }
            border.color: ThemeManager.border; border.width: 1; Behavior on border.color { ColorAnimation { duration: 200 } }
        }

        ColumnLayout {
            anchors { fill: parent; leftMargin: 20; rightMargin: 20; topMargin: 20; bottomMargin: 28 }
            spacing: 14

            Text {
            text: LanguageManager.tr3("Editar Pares de Objetos", "Edit Object Pairs", "Editar Pares de Objetos")
                color: ThemeManager.textPrimary
                Behavior on color { ColorAnimation { duration: 150 } }
                font.pixelSize: 15; font.weight: Font.Bold
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.borderLight; Behavior on color { ColorAnimation { duration: 200 } } }

            RowLayout {
                spacing: 10
                Text { text: LanguageManager.tr3("Campo 1:", "Field 1:", "Campo 1:"); color: ThemeManager.textSecondary; font.pixelSize: 12; Layout.preferredWidth: 60 }
                TextField {
                    id: editP1; Layout.fillWidth: true
                    color: ThemeManager.textPrimary; font.pixelSize: 13; placeholderText: "Ex: AA"
                    leftPadding: 10; rightPadding: 10; topPadding: 6; bottomPadding: 6
                    background: Rectangle { color: ThemeManager.surfaceDim; Behavior on color { ColorAnimation { duration: 200 } } border.color: editP1.activeFocus ? ThemeManager.accent : ThemeManager.border; border.width: 1; radius: 5 }
                }
            }
            RowLayout {
                spacing: 10
                Text { text: LanguageManager.tr3("Campo 2:", "Field 2:", "Campo 2:"); color: ThemeManager.textSecondary; font.pixelSize: 12; Layout.preferredWidth: 60 }
                TextField {
                    id: editP2; Layout.fillWidth: true
                    color: ThemeManager.textPrimary; font.pixelSize: 13; placeholderText: "Ex: BB"
                    leftPadding: 10; rightPadding: 10; topPadding: 6; bottomPadding: 6
                    background: Rectangle { color: ThemeManager.surfaceDim; Behavior on color { ColorAnimation { duration: 200 } } border.color: editP2.activeFocus ? ThemeManager.accent : ThemeManager.border; border.width: 1; radius: 5 }
                }
            }
            RowLayout {
                spacing: 10; Layout.fillWidth: true
                visible: root.numCampos >= 3
                Text { text: LanguageManager.tr3("Campo 3:", "Field 3:", "Campo 3:"); color: ThemeManager.textSecondary; font.pixelSize: 12; Layout.preferredWidth: 60 }
                TextField {
                    id: editP3; Layout.fillWidth: true
                    color: ThemeManager.textPrimary; font.pixelSize: 13; placeholderText: "Ex: CC"
                    leftPadding: 10; rightPadding: 10; topPadding: 6; bottomPadding: 6
                    background: Rectangle { color: ThemeManager.surfaceDim; Behavior on color { ColorAnimation { duration: 200 } } border.color: editP3.activeFocus ? ThemeManager.accent : ThemeManager.border; border.width: 1; radius: 5 }
                }
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true; spacing: 10
                Item { Layout.fillWidth: true }
                Button {
                    text: LanguageManager.tr3("Cancelar", "Cancel", "Cancelar"); onClicked: editPairsPopup.close()
                    background: Rectangle { color: "transparent" }
                    contentItem: Text { text: parent.text; color: ThemeManager.textSecondary; font.pixelSize: 12; font.weight: Font.Bold }
                }
                Button {
                    text: LanguageManager.tr3("Aplicar", "Apply", "Aplicar")
                    onClicked: {
                        var p1 = editP1.text.trim().toUpperCase()
                        var p2 = editP2.text.trim().toUpperCase()
                        var p3 = editP3.text.trim().toUpperCase()

                        // Atualiza as variáveis locais da Arena
                        root.pair1 = p1
                        root.pair2 = p2
                        root.pair3 = p3

                        // Propaga para o dashboard (atualiza aba Dados e SessionResultDialog)
                        root.pairsEdited(p1, p2, p3)

                        // Força a re-leitura dos tamanhos dos objetos (sua biblioteca)
                        zoneInitTimer.restart()

                        editPairsPopup.close()
                        saveToast.show(LanguageManager.tr3("Pares alterados! Nao esqueca de Salvar a Configuracao.", "Pairs updated! Don't forget to Save Configuration.", "Pares actualizados! No olvide Guardar Configuracion."))
                    }
                    background: Rectangle { radius: 6; color: parent.hovered ? ThemeManager.accentHover : ThemeManager.accent; Behavior on color { ColorAnimation { duration: 150 } } }
                    contentItem: Text { text: parent.text; color: ThemeManager.buttonText; font.pixelSize: 12; font.weight: Font.Bold; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    leftPadding: 16; rightPadding: 16; topPadding: 8; bottomPadding: 8
                }
            }
        }
    }

    Toast {
        id: saveToast; successMode: true
        anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 12 }
    }
}


