// qml/ei/EIArenaSetup.qml
// Arena for Inhibitory Avoidance: single field, walls, floor and 2 rectangular zones.
// Plataforma (esquerda) + Grade (direita) — sem objetos pares NOR.
// Ctrl+Drag: Walls | Alt+Drag: Floor | Shift+Drag: Zones | Scroll: resize zones

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia
import QtQuick.Dialogs
import "../core"
import "../core/Theme"
import MindTrace.Backend 1.0
import MindTrace.Tracking 1.0

Item {
    id: root

    property string experimentPath: ""
    property string videoPath:      ""
    property string analysisMode:   ""
    property string saveDirectory:  ""
    property string liveOutputName: "live"
    property string cameraId:       ""    // description of the selected camera for live mode
    property bool   livePreviewFrozen: false
    property int    livePreviewFrameCount: 0
    property bool   _isDirectShowPreview: false
    property int    numCampos:      1
    property bool   devMode:        false
    property real   videoAspectRatio: 1.5 // default 720x480

    // Apparatus color (configurable for reuse in CA/CC with 1 field)
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
        // Read data from the source arena
        ArenaConfigModel.loadConfigFromPath(sourcePath)
        var srcFloor     = ArenaConfigModel.getFloorPoints()
        var srcZoneCount = ArenaConfigModel.zoneCount()
        // Restaura arena atual
        ArenaConfigModel.loadConfigFromPath(experimentPath, ":/arena_config_ei_referencia.json")
        var curFloor     = ArenaConfigModel.getFloorPoints()
        var curZoneCount = ArenaConfigModel.zoneCount()
        // Check only zone-type incompatibility (shape detection removed — normalised coords are imprecise)
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

    // Zonas: 2 zonas em formato {x, y, r} — r = metade da largura/altura normalizada
    // Neutral initial values; filled via zoneInitTimer after loading from the model
    property var zones:       [ { x: 0.25, y: 0.5, r: 0.15 }, { x: 0.70, y: 0.5, r: 0.25 } ]

    // Walls and floor — filled via zoneInitTimer (from EI reference or saved file)
    property var arenaPoints: [[]]
    property var floorPoints: [[]]

    signal zonasEditadas()
    signal analysisModeChangedExternally(string mode)

    function _cameraBaseName(cameraIdValue) {
        var s = String(cameraIdValue || "")
        var b = s.toLowerCase().indexOf("|backend:")
        if (b >= 0) s = s.substring(0, b)
        var i = s.toLowerCase().indexOf("|input:")
        if (i >= 0) s = s.substring(0, i)
        return s.replace(" [DirectShow]", "").trim().toLowerCase()
    }

    function _tryUseDefaultLiveCamera() {
        var defaultId = String(ThemeSettings.loadVariant("defaultLiveCameraId", "") || "")
        if (defaultId === "")
            return false

        var wantBase = _cameraBaseName(defaultId)
        if (wantBase === "")
            return false

        var nativeList = cameraProbe.listVideoInputs()
        for (var i = 0; i < nativeList.length; i++) {
            var n = nativeList[i].name || nativeList[i].description || String(nativeList[i])
            if (_cameraBaseName(n) === wantBase) {
                root.cameraId = defaultId
                root.analysisModeChangedExternally("ao_vivo")
                return true
            }
        }
        return false
    }

    Loader {
        id: mediaDevicesLoader
        active: true
        sourceComponent: Component { MediaDevices {} }
        onLoaded: eiCameraSelectPopup._populateFromDevices(item.videoInputs)
    }
    property alias mediaDevices: mediaDevicesLoader.item
    VideoInputEnumerator { id: cameraProbe }

    // Public function: open the mode popup
    function openVideoLoader() { analysisModePrompt.open() }

    // ── Unsaved toast ────────────────────────────────────────────────────
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
            text: LanguageManager.tr3("Zonas editadas! Nao esqueca de Salvar", "Zones edited! Don't forget to Save", "Zonas editadas! No olvide Guardar")
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
    // EI uses its own reference as fallback (no arena_config.json saved)
        ArenaConfigModel.loadConfigFromPath(experimentPath, ":/arena_config_ei_referencia.json")
    // arenaPoints, floorPoints and zones are applied in zoneInitTimer via onConfigChanged
    }

    Connections {
        target: ArenaConfigModel
        function onConfigChanged() { zoneInitTimer.restart() }
    }

    // Helper: parse JSON point string -> [[{x,y},...]] with minimum expectedCount
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
            // Apply arenaPoints and floorPoints from the model (from saved file or EI reference)
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

    // ── Video player (preview) ───────────────────────────────────────────
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

    // ── Live camera preview ──────────────────────────────────────────────
    CaptureSession {
        id: eiArenaCaptureSession
        videoOutput: null
        camera: Camera {
            id: eiArenaCamera
            active: false
        }
    }
    InferenceController { id: eiArenaPreviewInference }

    onCameraIdChanged: _updateEICameraPreview()
    onAnalysisModeChanged: _updateEICameraPreview()
    Timer {
        id: eiLiveFreezeTimer
        interval: 1000
        repeat: false
        onTriggered: {
            if (root.analysisMode !== "ao_vivo")
                return
            // Congela o frame atual da arena para facilitar ajuste manual.
            if (eiArenaCamera.active)
                eiArenaCamera.active = false
            if (eiArenaPreviewInference)
                eiArenaPreviewInference.stopLivePreview()
            root.livePreviewFrozen = true
        }
    }

    Connections {
        target: framePreview.videoSink
        enabled: root.analysisMode === "ao_vivo"
        function onVideoFrameChanged(frame) {
            if (!frame || root.livePreviewFrozen || !eiArenaCamera.active)
                return
            root.livePreviewFrameCount += 1
        }
    }

    function _updateEICameraPreview() {
        if (analysisMode !== "ao_vivo" || cameraId === "") {
            console.log("[EIArenaSetup] Live preview OFF (mode/camera not ready). mode=", analysisMode, "cameraId=", cameraId)
            eiLiveFreezeTimer.stop()
            livePreviewFrozen = false
            livePreviewFrameCount = 0
            _isDirectShowPreview = false
            eiArenaPreviewInference.setLivePreviewOutput(null)
            eiArenaPreviewInference.stopLivePreview()
            eiArenaCamera.active = false
            eiArenaCaptureSession.videoOutput = null
            videoPlayer.videoOutput = framePreview
            return
        }
        var selectedName = cameraId
        var lowerSelected = selectedName.toLowerCase()
        var isDirectShowSelection = selectedName.indexOf("[DirectShow]") >= 0
                                    || lowerSelected.indexOf("|input:") >= 0
                                    || lowerSelected.indexOf("|backend:dshow") >= 0
        selectedName = selectedName.replace(" [DirectShow]", "")
        var backendSep = selectedName.toLowerCase().indexOf("|backend:")
        if (backendSep >= 0)
            selectedName = selectedName.substring(0, backendSep).trim()
        var inputSep = selectedName.indexOf("|input:")
        if (inputSep >= 0)
            selectedName = selectedName.substring(0, inputSep).trim()
        if (isDirectShowSelection) {
            console.log("[EIArenaSetup] Live preview ON for DirectShow selection:", cameraId)
            eiLiveFreezeTimer.stop()
            livePreviewFrozen = false
            livePreviewFrameCount = 0
            _isDirectShowPreview = true
            eiArenaCaptureSession.videoOutput = null
            eiArenaCamera.active = false
            videoPlayer.videoOutput = null
            if (!eiArenaPreviewInference.startLivePreview(cameraId))
                console.log("[EIArenaSetup] DirectShow preview failed to start:", cameraId)
            Qt.callLater(function() {
                eiArenaPreviewInference.setLivePreviewOutput(framePreview)
                eiLiveFreezeTimer.restart()
            })
            return
        }
        _isDirectShowPreview = false
        eiArenaPreviewInference.setLivePreviewOutput(null)
        eiArenaPreviewInference.stopLivePreview()
        var devices = mediaDevices.videoInputs
        var selectedLower = selectedName.toLowerCase().trim()
        for (var i = 0; i < devices.length; i++) {
            var devName = (devices[i].description || "").trim()
            var devLower = devName.toLowerCase()
            var nameMatch = devLower === selectedLower
                            || devLower.indexOf(selectedLower) >= 0
                            || selectedLower.indexOf(devLower) >= 0
            if (nameMatch) {
                console.log("[EIArenaSetup] Live preview ON via Qt camera device:", devName, "<->", selectedName)
                eiArenaCamera.cameraDevice = devices[i]
                videoPlayer.videoOutput = null
                eiArenaCaptureSession.videoOutput = framePreview
                livePreviewFrozen = false
                livePreviewFrameCount = 0
                eiArenaCamera.active = true
                eiLiveFreezeTimer.restart()
                return
            }
        }
        var devNames = []
        for (var j = 0; j < devices.length; j++)
            devNames.push(devices[j].description || "")
        console.log("[EIArenaSetup] Qt devices available:", devNames.join(" | "))
        console.log("[EIArenaSetup] Live preview OFF (camera not found in Qt devices):", selectedName)
        eiLiveFreezeTimer.stop()
        livePreviewFrozen = false
        livePreviewFrameCount = 0
        eiArenaCaptureSession.videoOutput = null
        eiArenaCamera.active = false
    }

    function stopCameraPreview() {
        eiLiveFreezeTimer.stop()
        livePreviewFrameCount = 0
        eiArenaPreviewInference.setLivePreviewOutput(null)
        eiArenaPreviewInference.stopLivePreview()
        eiArenaCamera.active = false
        eiArenaCaptureSession.videoOutput = null
    }

    // ── Dialogs ──────────────────────────────────────────────────────────
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

    FolderDialog {
        id: eiSaveFolderPicker
        title: LanguageManager.tr3("Selecionar pasta de gravacao", "Select recording folder", "Seleccionar carpeta de grabacion")
        onAccepted: savePathField.text = selectedFolder.toString().replace("file:///", "")
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

    // Popup: confirm import with warnings
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
        width: Math.min(root.width - 24, 560)
        implicitHeight: modePromptCol.implicitHeight + 48
        height: implicitHeight
        anchors.centerIn: parent
        modal: true; focus: true
        closePolicy: Popup.CloseOnEscape

        background: Rectangle {
            radius: 14; color: ThemeManager.surface
            Behavior on color { ColorAnimation { duration: 200 } }
            border.color: root.primaryColor; border.width: 1
        }

        ColumnLayout {
            id: modePromptCol
            anchors { fill: parent; margins: 24 }
            spacing: 14

            Text {
                text: LanguageManager.tr3("Tipo de Analise", "Analysis Type", "Tipo de Analisis")
                color: ThemeManager.textPrimary
                Behavior on color { ColorAnimation { duration: 150 } }
                font.pixelSize: 16; font.weight: Font.Bold
            }
            Text {
                Layout.fillWidth: true
                text: LanguageManager.tr3("Escolha o modo de analise:", "Choose analysis mode:", "Elija el modo de analisis:")
                color: ThemeManager.textSecondary
                Behavior on color { ColorAnimation { duration: 150 } }
                font.pixelSize: 13
            }

            RowLayout {
                Layout.fillWidth: true; spacing: 12

                // Offline
                Rectangle {
                    Layout.fillWidth: true; Layout.minimumWidth: 0; radius: 8
                    implicitHeight: offlineChoiceCol.implicitHeight + 20
                    color: offMa.containsMouse ? ThemeManager.surfaceAlt : ThemeManager.surfaceDim
                    border.color: root.primaryColor; border.width: 2
                    Behavior on color { ColorAnimation { duration: 150 } }

                    ColumnLayout {
                        id: offlineChoiceCol
                        anchors { left: parent.left; right: parent.right; margins: 10; verticalCenter: parent.verticalCenter }
                        spacing: 4
                        Text {
                            Layout.fillWidth: true
                            text: "🎬  " + LanguageManager.tr3("Analise Offline", "Offline Analysis", "Analisis Offline")
                            color: ThemeManager.textPrimary
                            Behavior on color { ColorAnimation { duration: 150 } }
                            font.pixelSize: 13; font.weight: Font.Bold
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                        }
                        Text {
                            Layout.fillWidth: true
                            text: LanguageManager.tr3("Video pre-gravado", "Pre-recorded video", "Video pregrabado")
                            color: ThemeManager.textSecondary
                            Behavior on color { ColorAnimation { duration: 150 } }
                            font.pixelSize: 10; horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
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
                    Layout.fillWidth: true; Layout.minimumWidth: 0; radius: 8
                    implicitHeight: liveChoiceCol.implicitHeight + 20
                    color: liveMa.containsMouse ? ThemeManager.surfaceAlt : ThemeManager.background
                    border.color: ThemeManager.success; border.width: 2
                    Behavior on color { ColorAnimation { duration: 150 } }

                    ColumnLayout {
                        id: liveChoiceCol
                        anchors { left: parent.left; right: parent.right; margins: 10; verticalCenter: parent.verticalCenter }
                        spacing: 4
                        Text {
                            Layout.fillWidth: true
                            text: "📹  " + LanguageManager.tr3("Analise Ao Vivo", "Live Analysis", "Analisis En Vivo")
                            color: ThemeManager.textPrimary
                            Behavior on color { ColorAnimation { duration: 150 } }
                            font.pixelSize: 13; font.weight: Font.Bold
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                        }
                        Text {
                            Layout.fillWidth: true
                            text: LanguageManager.tr3("Camera ao vivo (grava video em arquivo)", "Live camera (records video to file)", "Camara en vivo (graba video en archivo)")
                            color: ThemeManager.textSecondary
                            Behavior on color { ColorAnimation { duration: 150 } }
                            font.pixelSize: 10; horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                        }
                    }
                    MouseArea {
                        id: liveMa; anchors.fill: parent
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.analysisMode = "ao_vivo"
                            analysisModePrompt.close()
                            savePathField.text = root.saveDirectory
                            saveNameField.text = root.liveOutputName
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

    // Popup: directory for saving live video
    Popup {
        id: saveDirPopup
        anchors.centerIn: parent
        width: 440; height: 220
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
                    placeholderTextColor: ThemeManager.textSecondary; font.pixelSize: 12
                    onTextChanged: root.saveDirectory = text
                    leftPadding: 10; rightPadding: 10; topPadding: 8; bottomPadding: 8
                    background: Rectangle {
                        radius: 6; color: ThemeManager.surfaceDim
                        Behavior on color { ColorAnimation { duration: 200 } }
                        border.color: savePathField.activeFocus ? root.primaryColor : ThemeManager.border; border.width: 1
                    }
                }
                Button {
                    text: LanguageManager.tr3("Pesquisar", "Browse", "Buscar")
                    onClicked: eiSaveFolderPicker.open()
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
                    placeholderTextColor: ThemeManager.textSecondary; font.pixelSize: 12
                    text: root.liveOutputName
                    onTextChanged: root.liveOutputName = text
                    leftPadding: 10; rightPadding: 10; topPadding: 8; bottomPadding: 8
                    background: Rectangle {
                        radius: 6; color: ThemeManager.surfaceDim
                        Behavior on color { ColorAnimation { duration: 200 } }
                        border.color: saveNameField.activeFocus ? root.primaryColor : ThemeManager.border; border.width: 1
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true; spacing: 8
                Item { Layout.fillWidth: true }
                GhostButton { text: LanguageManager.tr3("Cancelar", "Cancel", "Cancelar"); onClicked: saveDirPopup.close() }
                Button {
                    text: LanguageManager.tr3("Confirmar", "Confirm", "Confirmar")
                    enabled: savePathField.text.trim().length > 0 && saveNameField.text.trim().length > 0
                    onClicked: {
                        root.saveDirectory = savePathField.text.trim()
                        root.liveOutputName = saveNameField.text.trim()
                        saveDirPopup.close()
                        if (!root._tryUseDefaultLiveCamera())
                            eiCameraSelectPopup.open()
                    }
                    background: Rectangle {
                        radius: 8
                        color: parent.enabled ? (parent.hovered ? root.secondaryColor : root.primaryColor) : ThemeManager.surfaceDim
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

    // Popup: select camera for live analysis
    Popup {
        id: eiCameraSelectPopup
        anchors.centerIn: parent
        width: 520; modal: true; focus: true; closePolicy: Popup.CloseOnEscape
        height: Math.min(120 + Math.max(1, eiCameraSelectPopup._cameras.length) * 62 + 170, 560)
        background: Rectangle {
            radius: 14; color: ThemeManager.surface; Behavior on color { ColorAnimation { duration: 200 } }
            border.color: ThemeManager.success; border.width: 1
        }

        property int selectedIndex: 0
        property var _cameras: []
        property string _statusMsg: ""
        property string selectedInputType: "Composite"

        function _selectedCamera() {
            if (selectedIndex >= 0 && selectedIndex < _cameras.length)
                return _cameras[selectedIndex]
            return null
        }

        function _populateFromDevices(devices) {
            var list = []
            for (var i = 0; i < devices.length; i++) {
                var dn = devices[i].description || devices[i].name || String(devices[i])
                list.push({ name: dn, backend: "qt", hasComposite: false, hasSVideo: false })
            }
            var nativeList = cameraProbe.listVideoInputs()
            for (var j = 0; j < nativeList.length; j++) {
                var item = nativeList[j]
                var n = item.name || item.description || String(item)
                var exists = false
                for (var k = 0; k < list.length; k++) {
                    if (list[k].name === n) {
                        exists = true
                        break
                    }
                }
                if (!exists) {
                    list.push({
                        name: n,
                        backend: item.backend || "dshow",
                        hasComposite: !!item.hasComposite,
                        hasSVideo: !!item.hasSVideo,
                        isHauppauge: !!item.isHauppauge
                    })
                } else if ((item.backend || "").toLowerCase() === "dshow") {
                    // Keep Qt and DirectShow entries separate when names collide.
                    list.push({
                        name: n + " [DirectShow]",
                        backend: "dshow",
                        hasComposite: !!item.hasComposite,
                        hasSVideo: !!item.hasSVideo,
                        isHauppauge: !!item.isHauppauge
                    })
                }
            }
            _cameras = list
            selectedIndex = 0
            for (var s = 0; s < list.length; s++) {
                if (list[s].backend === "dshow" && (list[s].hasComposite || list[s].hasSVideo || list[s].isHauppauge)) {
                    selectedIndex = s
                    break
                }
            }
            selectedInputType = "Composite"
            _statusMsg = list.length > 0
                ? LanguageManager.tr3(list.length + " camera(s) encontrada(s).", list.length + " camera(s) found.", list.length + " camara(s) encontrada(s).")
                : LanguageManager.tr3("Nenhuma camera detectada pelo sistema.", "No camera detected by the system.", "Ninguna camara detectada por el sistema.")
        }

        function _refreshCameraList() {
            _statusMsg = LanguageManager.tr3("Buscando cameras...", "Searching cameras...", "Buscando camaras...")
            mediaDevicesLoader.active = false
            eiRefreshTimer.start()
        }

        Timer {
            id: eiRefreshTimer
            interval: 300
            repeat: false
            onTriggered: mediaDevicesLoader.active = true
        }

        onOpened: {
            if (mediaDevices)
                _populateFromDevices(mediaDevices.videoInputs)
            else
                _statusMsg = LanguageManager.tr3("Buscando cameras...", "Searching cameras...", "Buscando camaras...")
        }

        Connections {
            target: mediaDevices
            function onVideoInputsChanged() {
                eiCameraSelectPopup._populateFromDevices(mediaDevices.videoInputs)
            }
        }

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

            ListView {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(eiCameraSelectPopup._cameras.length * 62, 260)
                clip: true
                model: eiCameraSelectPopup._cameras
                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AlwaysOn
                    anchors.right: parent.right
                    anchors.rightMargin: -2
                    contentItem: Rectangle {
                        implicitWidth: 6
                        radius: 3
                        color: ThemeManager.borderLight
                    }
                }
                delegate: Rectangle {
                    width: ListView.view.width; height: 58; radius: 8
                    color: eiCameraSelectPopup.selectedIndex === index
                           ? Qt.rgba(0.15, 0.55, 0.25, 0.25)
                           : (eiCamMa.containsMouse ? ThemeManager.surfaceAlt : ThemeManager.surfaceDim)
                    border.color: eiCameraSelectPopup.selectedIndex === index ? ThemeManager.success : ThemeManager.border
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 120 } }

                    Column {
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 12; rightMargin: 12 }
                        spacing: 2
                        Text {
                            width: parent.width
                            text: (typeof modelData === "string")
                                  ? modelData
                                  : (modelData.name || modelData.description || "")
                            color: ThemeManager.textPrimary; Behavior on color { ColorAnimation { duration: 150 } }
                            font.pixelSize: 12; font.weight: Font.Medium
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: {
                                if (typeof modelData === "string") return "qt"
                                var mode = (modelData.backend || "qt")
                                var ins = []
                                if (modelData.hasComposite) ins.push("Composite")
                                if (modelData.hasSVideo) ins.push("S-Video")
                                return ins.length > 0 ? (mode + " • " + ins.join(" / ")) : mode
                            }
                            color: ThemeManager.textTertiary
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }
                    }
                    MouseArea {
                        id: eiCamMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            eiCameraSelectPopup.selectedIndex = index
                            eiCameraSelectPopup.selectedInputType = "Composite"
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: {
                    var cam = eiCameraSelectPopup._selectedCamera()
                    return cam && cam.backend === "dshow" && (cam.hasComposite || cam.hasSVideo || cam.isHauppauge)
                }
                spacing: 8

                Text {
                    text: LanguageManager.tr3("Entrada", "Input", "Entrada")
                    color: ThemeManager.textSecondary
                    font.pixelSize: 12
                }

                ComboBox {
                    id: eiInputTypeCombo
                    Layout.preferredWidth: 180
                    model: {
                        var cam = eiCameraSelectPopup._selectedCamera()
                        var opts = []
                        if (cam && cam.hasComposite) opts.push("Composite")
                        if (cam && cam.hasSVideo) opts.push("S-Video")
                        if (opts.length === 0) {
                            opts.push("Composite")
                            opts.push("S-Video")
                        }
                        return opts
                    }
                    currentIndex: Math.max(0, model.indexOf(eiCameraSelectPopup.selectedInputType))
                    onActivated: eiCameraSelectPopup.selectedInputType = currentText
                }
                Item { Layout.fillWidth: true }
            }

            Text {
                visible: eiCameraSelectPopup._statusMsg !== ""
                Layout.fillWidth: true
                text: eiCameraSelectPopup._statusMsg
                color: eiCameraSelectPopup._cameras.length > 0 ? ThemeManager.success : ThemeManager.textSecondary
                font.pixelSize: 11
                horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
            }

            RowLayout {
                Layout.fillWidth: true; spacing: 8
                GhostButton {
                    text: "\u{1F504} " + LanguageManager.tr3("Atualizar", "Refresh", "Actualizar")
                    onClicked: eiCameraSelectPopup._refreshCameraList()
                }
                Item { Layout.fillWidth: true }
                GhostButton { text: "Cancelar"; onClicked: { root.analysisMode = ""; eiCameraSelectPopup.close() } }
                Button {
                    text: LanguageManager.tr3("Iniciar ao Vivo", "Start Live", "Iniciar en Vivo")
                    enabled: eiCameraSelectPopup._cameras.length > 0
                    onClicked: {
                        var idx = eiCameraSelectPopup.selectedIndex
                        if (idx >= 0 && idx < eiCameraSelectPopup._cameras.length) {
                            var c = eiCameraSelectPopup._cameras[idx]
                            if (c.backend === "dshow") {
                                if (c.hasComposite || c.hasSVideo || c.isHauppauge)
                                    root.cameraId = c.name + " |backend:dshow |input:" + eiCameraSelectPopup.selectedInputType
                                else
                                    root.cameraId = c.name + " |backend:dshow"
                            }
                            else
                                root.cameraId = c.name + " |backend:qt"
                        }
                        eiCameraSelectPopup.close()
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

        // ── Action bar ───────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Text {
                            text: LanguageManager.tr3("Configuração da Arena", "Arena Setup", "Configuracion de la Arena")
                color: ThemeManager.textPrimary
                Behavior on color { ColorAnimation { duration: 150 } }
                font.pixelSize: 14; font.weight: Font.Bold
            }
            Item { Layout.fillWidth: true }

            Column {
                Layout.preferredWidth: Math.min(root.width * 0.74, 920)
                spacing: 6

                Text {
                    text: root.devMode
                        ? "🔧 devMode  |  Ctrl+Arrastar: Paredes  |  Shift+Arrastar: Plataforma  |  Alt+Arrastar: Grade"
                        : "🖱 Ctrl+Arrastar: Paredes  |  Shift+Arrastar: Plataforma  |  Alt+Arrastar: Grade"
                    width: parent.width
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignRight
                    color: ThemeManager.textTertiary
                    Behavior on color { ColorAnimation { duration: 150 } }
                    font.pixelSize: 10; verticalAlignment: Text.AlignVCenter
                }

                Flow {
                width: parent.width
                spacing: 8
                layoutDirection: Qt.RightToLeft

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

                // Load video
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
                    color: active ? (videoBtnRect.hovered ? ThemeManager.success : ThemeManager.successLight)
                                  : (videoBtnRect.hovered ? ThemeManager.surfaceAlt : ThemeManager.background)
                    Behavior on color { ColorAnimation { duration: 200 } }
                    border.color: active ? ThemeManager.success : (videoBtnRect.hovered ? ThemeManager.border : ThemeManager.borderLight)
                    Behavior on border.color { ColorAnimation { duration: 200 } }
                    border.width: 2
                }
                contentItem: Text {
                    text: parent.text
                    property bool active: root.videoPath !== "" || (root.analysisMode === "ao_vivo" && root.cameraId !== "")
                    color: active ? ThemeManager.textPrimary : (videoBtnRect.hovered ? ThemeManager.textPrimary : ThemeManager.textSecondary)
                    Behavior on color { ColorAnimation { duration: 150 } }
                    font.pixelSize: 11; font.weight: Font.Bold
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                }
                leftPadding: 14; rightPadding: 14; topPadding: 6; bottomPadding: 6
            }

                // Importar Arena
                Button {
                            text: "📥 " + LanguageManager.tr3("Importar Arena", "Import Arena", "Importar Arena")
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

                // Save configuration
                Button {
                            text: "💾 " + LanguageManager.tr3("Salvar Configuracao", "Save Configuration", "Guardar Configuracion")
                enabled: experimentPath !== ""
                onClicked: {
                    // In EI, zones are saved as quadrilaterals in floorPoints (JSON string)
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
            }
        }

        // ── Rectangular arena — single field ──────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Arena as rectangle (approx 2:1 ratio for EI)
            Item {
                id: arenaCell
                anchors.centerIn: parent
                // Dynamic aspect ratio based on video
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

                    // Video preview (single field, no mosaic crop)
                    ShaderEffectSource {
                        anchors.fill: parent
                        visible: root.videoPath !== "" || (root.analysisMode === "ao_vivo" && root.cameraId !== "")
                        sourceItem: framePreview
                        // No crop — shows the full video
                        sourceRect: {
                            var _fp = framePreview
                            if (!_fp || _fp.width === 0) return Qt.rect(0,0,0,0)
                            var cr = _fp.contentRect
                            return Qt.rect(cr.x, cr.y, cr.width, cr.height)
                        }
                        opacity: 0.9
                    }

                    // ── Canvas: walls + floor ───────────────────────────
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
                        Connections {
                            target: LanguageManager
                            function onCurrentLanguageChanged() { arenaCanvas.requestPaint() }
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
                                drawPoly(fp.slice(0, 4), "rgba(0, 255, 0, 0.15)", "rgba(0, 255, 0, 0.8)", LanguageManager.tr3("Plataforma", "Platform", "Plataforma"))
                            }

                            // 3. Grade (Ciano/Blue) - pontos 4-7 do floorPoints (Direita agora)
                            if (fp.length >= 8) {
                                drawPoly(fp.slice(4, 8), "rgba(0, 204, 255, 0.15)", "rgba(0, 204, 255, 0.8)", LanguageManager.tr3("Grade", "Grid", "Rejilla"))
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

                    // ── Floor points (Dev Mode) ────────────────────────
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

                    // ── Interaction: drag zones, walls, floor ────────────
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
                                // Drag Platform corner (floorPoints indices 0-3)
                                for (var c1 = 0; c1 < 4; c1++) {
                                    if (!fp[c1]) continue
                                    var fx1 = fp[c1].x * w, fy1 = fp[c1].y * h
                                    var df1 = (mouse.x-fx1)*(mouse.x-fx1)+(mouse.y-fy1)*(mouse.y-fy1)
                                    if (df1 < capDist) { capDist = df1; dragFloorCorner = c1 }
                                }
                            } else if (mouse.modifiers & Qt.AltModifier) {
                                // Drag Grid corner (floorPoints indices 4-7)
                                for (var c2 = 4; c2 < 8; c2++) {
                                    if (!fp[c2]) continue
                                    var fx2 = fp[c2].x * w, fy2 = fp[c2].y * h
                                    var df2 = (mouse.x-fx2)*(mouse.x-fx2)+(mouse.y-fy2)*(mouse.y-fy2)
                                    if (df2 < capDist) { capDist = df2; dragFloorCorner = c2 }
                                }
                            } else if (mouse.modifiers & Qt.ControlModifier) {
                                // Drag nearest wall corner (arenaPoints 0-3)
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
