import QtQuick 2.12
import QtQuick.Controls 2.12
import QtQuick.Layouts 1.3
import QtMultimedia 5.12
import MindTrace.Tracking 1.0

Item {
    id: recordingRoot

    // ── Propriedades injetadas pelo MainDashboard ─────────────────────────────
    property string videoPath: ""
    property string pair1: ""
    property string pair2: ""
    property string pair3: ""
    property string sessionType: "Treino"

    property var zones
    property var arenaPoints
    property var floorPoints

    // ── Timers independentes por campo (cada campo conta 300s sozinho) ─────────
    property var timesRemaining: [300, 300, 300]
    property var timerStarted:   [false, false, false]
    property var fieldFinished:  [false, false, false]

    signal sessionEnded()

    // ── Estado interno ────────────────────────────────────────────────────────
    property bool isAnalyzing:   false
    property int  videoWidth:    0
    property int  videoHeight:   0

    // Coords normalizadas no frame completo (0..1) — Nose
    property var ratNormX:      [-1, -1, -1]
    property var ratNormY:      [-1, -1, -1]
    property var ratLikelihood: [0,  0,  0 ]

    // Coords normalizadas no frame completo (0..1) — Body
    property var bodyNormX:      [-1, -1, -1]
    property var bodyNormY:      [-1, -1, -1]
    property var bodyLikelihood: [0,  0,  0 ]

    // DLC-reported FPS (sent via FPS, signal)
    property double dlcFps:       30.0

    // Exploração por zona (6 zonas — 2 por campo)
    property var explorationTimes: [0, 0, 0, 0, 0, 0]
    property var explorationBouts: [[], [], [], [], [], []]

    // Controle interno de bout — arrays simples (não precisam de binding)
    property var _inZone:    [false, false, false, false, false, false]
    property var _entryTime: [0,     0,     0,     0,     0,     0    ]  // ms epoch

    // Tick para forçar re-avaliação do bout live a cada 100 ms
    property int _explorationTick: 0
    property bool _dlcReady: false

    // ── Log ───────────────────────────────────────────────────────────────────
    ListModel { id: logModel }

    // ── DLC Controller (nativo — ONNX + QVideoProbe para captura de frames) ──
    DlcController { id: dlc }

    // ── Player de exibição (QML nativo — VideoOutput funciona de forma garantida) ─
    MediaPlayer {
        id: displayPlayer
        autoLoad: false
    }

    Connections {
        target: dlc
        onDimsReceived: {
            recordingRoot.videoWidth  = width
            recordingRoot.videoHeight = height
            logModel.append({ msg: "ℹ️ Resolução: " + width + "×" + height, isErr: false })
            logView.positionViewAtEnd()
        }
        onFpsReceived: {
            recordingRoot.dlcFps = fps
            logModel.append({ msg: "ℹ️ FPS: " + fps.toFixed(2), isErr: false })
            logView.positionViewAtEnd()
        }
        onInfoReceived: {
            logModel.append({ msg: "ℹ️ " + message, isErr: false })
            logView.positionViewAtEnd()
        }
        onReadyReceived: {
            recordingRoot._dlcReady = true
            logModel.append({ msg: "▶ Motor ONNX pronto — tracking ativo", isErr: false })
            logView.positionViewAtEnd()
        }
        onTrackReceived: {
            // Nose position — direct signal from C++ ONNX inference (already synced to displayed frame)
            if (recordingRoot.videoWidth <= 0 || recordingRoot.videoHeight <= 0) return
            var nx = recordingRoot.ratNormX.slice()
            var ny = recordingRoot.ratNormY.slice()
            var nl = recordingRoot.ratLikelihood.slice()
            nx[campo] = x / recordingRoot.videoWidth
            ny[campo] = y / recordingRoot.videoHeight
            nl[campo] = p
            // Start per-campo session timer on first confident detection
            if (p > 0.5 && !recordingRoot.timerStarted[campo]) {
                var ts = recordingRoot.timerStarted.slice()
                ts[campo] = true
                recordingRoot.timerStarted = ts
            }
            recordingRoot.ratNormX      = nx
            recordingRoot.ratNormY      = ny
            recordingRoot.ratLikelihood = nl
        }
        onBodyReceived: {
            if (recordingRoot.videoWidth <= 0 || recordingRoot.videoHeight <= 0) return
            var bx = recordingRoot.bodyNormX.slice()
            var by = recordingRoot.bodyNormY.slice()
            var bl = recordingRoot.bodyLikelihood.slice()
            bx[campo] = x / recordingRoot.videoWidth
            by[campo] = y / recordingRoot.videoHeight
            bl[campo] = p
            recordingRoot.bodyNormX      = bx
            recordingRoot.bodyNormY      = by
            recordingRoot.bodyLikelihood = bl
        }
        onAnalyzingChanged: {
            if (!dlc.isAnalyzing && recordingRoot.isAnalyzing) {
                displayPlayer.stop()
                logModel.append({ msg: "Análise encerrada.", isErr: false })
                logView.positionViewAtEnd()
                recordingRoot.isAnalyzing = false
            }
        }
        onErrorOccurred: {
            displayPlayer.stop()
            logModel.append({ msg: "❌ " + errorMsg, isErr: true })
            logView.positionViewAtEnd()
            recordingRoot.isAnalyzing = false
        }
    }

    // ── Timer de sessão (1 s) — cada campo decrementa independentemente ────────
    Timer {
        id: sessionMasterTimer
        interval: 1000; repeat: true; running: recordingRoot.isAnalyzing
        onTriggered: {
            var newTimes = recordingRoot.timesRemaining.slice()
            for (var i = 0; i < 3; i++) {
                if (recordingRoot.timerStarted[i] && !recordingRoot.fieldFinished[i] && newTimes[i] > 0) {
                    newTimes[i]--
                    if (newTimes[i] <= 0) {
                        var ff = recordingRoot.fieldFinished.slice()
                        ff[i] = true
                        recordingRoot.fieldFinished = ff
                        logModel.append({ msg: "✅ Campo " + (i+1) + " concluído!", isErr: false })
                        logView.positionViewAtEnd()
                    }
                }
            }
            recordingRoot.timesRemaining = newTimes
            // Auto-encerra quando todos concluem
            if (recordingRoot.fieldFinished[0] && recordingRoot.fieldFinished[1] && recordingRoot.fieldFinished[2]) {
                recordingRoot.stopSession()
                recordingRoot.sessionEnded()
            }
        }
    }

    // ── Timer de exploração (100 ms) ──────────────────────────────────────────
    Timer {
        id: explorationTimer
        interval: 100; repeat: true
        running: recordingRoot.isAnalyzing
        onTriggered: {
            recordingRoot.accumulateExploration()
            recordingRoot._explorationTick++
        }
    }

    // ── Funções de controle ───────────────────────────────────────────────────
    function startSession() {
        if (isAnalyzing) return
        if (videoPath === "" || videoPath === "file:///") {
            logModel.append({ msg: "⚠ Selecione um vídeo na aba Arena primeiro.", isErr: true })
            logView.positionViewAtEnd()
            return
        }
        timesRemaining   = [300, 300, 300]
        timerStarted     = [false, false, false]
        fieldFinished    = [false, false, false]
        explorationTimes = [0, 0, 0, 0, 0, 0]
        explorationBouts = [[], [], [], [], [], []]
        _inZone          = [false, false, false, false, false, false]
        _entryTime       = [0,     0,     0,     0,     0,     0    ]
        ratNormX         = [-1, -1, -1]
        ratNormY         = [-1, -1, -1]
        ratLikelihood    = [0,  0,  0 ]
        bodyNormX        = [-1, -1, -1]
        bodyNormY        = [-1, -1, -1]
        bodyLikelihood   = [0,  0,  0 ]
        _explorationTick = 0
        _dlcReady = false
        logModel.clear()
        logModel.append({ msg: "⏳ Carregando motor ONNX nativo...", isErr: false })
        logView.positionViewAtEnd()
        // Start display player immediately (shows video regardless of probe/ONNX state)
        displayPlayer.source = videoPath
        displayPlayer.play()
        // Start C++ backend (ONNX load + QVideoProbe frame capture)
        dlc.startAnalysis(videoPath, "")
        isAnalyzing = true
    }

    function stopSession() {
        if (!isAnalyzing) return
        var now = Date.now()
        var nb  = []
        for (var i = 0; i < 6; i++) nb.push(explorationBouts[i].slice())
        for (var zi = 0; zi < 6; zi++) {
            if (_inZone[zi]) {
                var dur = (now - _entryTime[zi]) / 1000.0
                if (dur > 0.1) nb[zi].push(parseFloat(dur.toFixed(1)))
                _inZone[zi] = false
            }
        }
        explorationBouts = nb
        dlc.stopAnalysis()
        displayPlayer.stop()
        isAnalyzing = false
        logModel.append({ msg: "⏹ Sessão parada.", isErr: false })
        logView.positionViewAtEnd()
    }

    function accumulateExploration() {
        if (!zones || zones.length < 6) return
        var ox    = [0,   0.5, 0  ]
        var oy    = [0,   0,   0.5]
        var cellW = 0.5
        var cellH = 0.5
        var now   = Date.now()
        var newTimes = explorationTimes.slice()
        var newBouts = []
        for (var i = 0; i < 6; i++) newBouts.push(explorationBouts[i].slice())
        var boutsChanged = false
        for (var campo = 0; campo < 3; campo++) {
            var rx = recordingRoot.ratNormX[campo]
            var ry = recordingRoot.ratNormY[campo]
            if (rx < 0 || recordingRoot.ratLikelihood[campo] < 0.5) {
                for (var ob2 = 0; ob2 < 2; ob2++) {
                    var zi2 = campo * 2 + ob2
                    if (_inZone[zi2]) {
                        var dur2 = (now - _entryTime[zi2]) / 1000.0
                        if (dur2 > 0.1) { newBouts[zi2].push(parseFloat(dur2.toFixed(1))); boutsChanged = true }
                        _inZone[zi2] = false
                    }
                }
                continue
            }
            for (var obj = 0; obj < 2; obj++) {
                var zi = campo * 2 + obj
                var z  = zones[zi]
                if (!z) continue
                var zx   = ox[campo] + z.x * cellW
                var zy   = oy[campo] + z.y * cellH
                var zr   = z.r * cellW
                var dx   = rx - zx
                var dy   = ry - zy
                var inZ  = (Math.sqrt(dx*dx + dy*dy) < zr)
                if (inZ) {
                    newTimes[zi] += 0.1
                    if (!_inZone[zi]) { _inZone[zi] = true; _entryTime[zi] = now }
                } else if (_inZone[zi]) {
                    var dur = (now - _entryTime[zi]) / 1000.0
                    if (dur > 0.1) { newBouts[zi].push(parseFloat(dur.toFixed(1))); boutsChanged = true }
                    _inZone[zi] = false
                }
            }
        }
        explorationTimes = newTimes
        if (boutsChanged) explorationBouts = newBouts
    }

    // Retorna segundos do bout atual para a zona zi (ou 0 se não estiver na zona)
    // Usa _explorationTick como dependência reativa para atualizar a cada 100ms
    function currentBoutSec(zi) {
        var _t = recordingRoot._explorationTick
        if (!_inZone[zi]) return 0.0
        return (Date.now() - _entryTime[zi]) / 1000.0
    }

    // Índice de discriminação: (T_novo - T_familiar) / (T_novo + T_familiar)
    // OBJ B (zi1, direita) = novo; OBJ A (zi0, esquerda) = familiar
    function discriminationIndex(campo) {
        var tFam   = explorationTimes[campo * 2]
        var tNovo  = explorationTimes[campo * 2 + 1]
        var total  = tFam + tNovo
        if (total < 0.1) return NaN
        return (tNovo - tFam) / total
    }

    // Coordenada local do rat dentro do quadrante (0..1)
    function ratLocalX(campo) {
        var nx = ratNormX[campo]
        if (nx < 0) return -1
        return campo === 1 ? (nx - 0.5) * 2 : nx * 2
    }
    function ratLocalY(campo) {
        var ny = ratNormY[campo]
        if (ny < 0) return -1
        return campo === 2 ? (ny - 0.5) * 2 : ny * 2
    }
    function bodyLocalX(campo) {
        var bx = bodyNormX[campo]
        if (bx < 0) return -1
        return campo === 1 ? (bx - 0.5) * 2 : bx * 2
    }
    function bodyLocalY(campo) {
        var by = bodyNormY[campo]
        if (by < 0) return -1
        return campo === 2 ? (by - 0.5) * 2 : by * 2
    }

    function pairForCampo(i) { return i === 0 ? pair1 : (i === 1 ? pair2 : pair3) }
    function formatTime(s) {
        var m   = Math.floor(s / 60)
        var sec = s % 60
        return (m   < 10 ? "0" + m   : "" + m)   + ":"
             + (sec < 10 ? "0" + sec : "" + sec)
    }

    // ── Layout ────────────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── Painel de sessão (topo) ───────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 110
            color: "#12122a"
            border.color: "#2d2d4a"; border.width: 1

            ColumnLayout {
                anchors.fill: parent; anchors.margins: 12; spacing: 12

                RowLayout {
                    spacing: 16
                    Text { text: "⚠️ SESSÃO"; color: "#ffcc00"; font.pixelSize: 13; font.weight: Font.Bold }
                    Repeater {
                        model: ["Treino", "Reativação", "Teste D2", "Teste D3"]
                        delegate: Rectangle {
                            id: sessBtn
                            property bool isSel: recordingRoot.sessionType === modelData
                            height: 36; radius: 8
                            implicitWidth: stLbl.implicitWidth + 30
                            color: isSel ? "#ab3d4c" : (stMa.containsMouse ? "#25253e" : "transparent")
                            border.color: isSel ? "#ff5566" : (stMa.containsMouse ? "#4a4a6c" : "#3a3a5c")
                            border.width: isSel ? 2 : 1
                            Text {
                                id: stLbl; anchors.centerIn: parent; text: modelData
                                color: sessBtn.isSel ? "#ffffff" : (stMa.containsMouse ? "#e8e8f0" : "#8888aa")
                                font.pixelSize: 14; font.weight: Font.Bold
                            }
                            MouseArea {
                                id: stMa; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: recordingRoot.sessionType = modelData
                            }
                        }
                    }
                    Item { Layout.fillWidth: true }
                }

                RowLayout {
                    spacing: 24
                    Repeater {
                        model: [
                            { label: "Campo 1", pair: recordingRoot.pair1 },
                            { label: "Campo 2", pair: recordingRoot.pair2 },
                            { label: "Campo 3", pair: recordingRoot.pair3 }
                        ]
                        delegate: RowLayout {
                            spacing: 6
                            Text { text: modelData.label; color: "#8888aa"; font.pixelSize: 11 }
                            Rectangle {
                                radius: 4; color: "#1f0d10"
                                border.color: "#ab3d4c"; border.width: 1
                                implicitWidth: cpTxt.implicitWidth + 16; implicitHeight: 20
                                Text {
                                    id: cpTxt; anchors.centerIn: parent
                                    text: modelData.pair !== "" ? "Par " + modelData.pair : "—"
                                    color: "#ff7788"; font.pixelSize: 11; font.weight: Font.Bold
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Área central ──────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true; Layout.fillHeight: true; spacing: 0

            // ── Mosaico 2×2 ───────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true; Layout.fillHeight: true
                color: "#05050a"

                GridLayout {
                    anchors.fill: parent
                    columns: 2; rowSpacing: 2; columnSpacing: 2

                    // ── 3 campos (top-left, top-right, bottom-left) ───────────
                    Repeater {
                        model: 3
                        delegate: Item {
                            id: campoCell
                            Layout.fillWidth: true; Layout.fillHeight: true
                            property int ci: index

                            Rectangle {
                                anchors.fill: parent
                                color: "#0a0a16"
                                border.color: recordingRoot.fieldFinished[campoCell.ci] ? "#3a8a50" : "#2d2d4a"
                                border.width: 1
                                clip: true

                                // Quadrante do vídeo via ShaderEffectSource
                                ShaderEffectSource {
                                    anchors.fill: parent
                                    sourceItem: framePreviewMaster
                                    sourceRect: {
                                        if (!framePreviewMaster || framePreviewMaster.width === 0)
                                            return Qt.rect(0, 0, 0, 0)
                                        var cr = framePreviewMaster.contentRect
                                        var cw = cr.width  / 2
                                        var ch = cr.height / 2
                                        if (campoCell.ci === 0) return Qt.rect(cr.x,      cr.y,      cw, ch)
                                        if (campoCell.ci === 1) return Qt.rect(cr.x + cw, cr.y,      cw, ch)
                                        return                         Qt.rect(cr.x,      cr.y + ch, cw, ch)
                                    }
                                    opacity: 0.85
                                }

                                // Overlay arena (paredes + chão + zonas)
                                Canvas {
                                    id: arenaCanv
                                    anchors.fill: parent
                                    property int ci: campoCell.ci
                                    onWidthChanged:  requestPaint()
                                    onHeightChanged: requestPaint()
                                    Component.onCompleted: requestPaint()
                                    Connections {
                                        target: recordingRoot
                                        onArenaPointsChanged: arenaCanv.requestPaint()
                                        onFloorPointsChanged: arenaCanv.requestPaint()
                                    }
                                    onPaint: {
                                        var ctx = getContext("2d")
                                        ctx.clearRect(0, 0, width, height)
                                        if (!recordingRoot.arenaPoints || !recordingRoot.floorPoints) return
                                        var ap = recordingRoot.arenaPoints[ci]
                                        var fp = recordingRoot.floorPoints[ci]
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
                                        poly([iTL,iTR,iBR,iBL],"rgba(255,0,255,0.12)","rgba(255,0,255,0.5)")
                                        poly([oTL,oTR,iTR,iTL],"rgba(255,0,0,0.12)",  "rgba(255,0,0,0.5)")
                                        poly([iBL,iBR,oBR,oBL],"rgba(0,255,0,0.12)",  "rgba(0,255,0,0.5)")
                                        poly([oTL,iTL,iBL,oBL],"rgba(0,255,255,0.12)","rgba(0,255,255,0.5)")
                                        poly([iTR,oTR,oBR,iBR],"rgba(255,255,0,0.12)","rgba(255,255,0,0.5)")
                                        ctx.strokeStyle="rgba(255,170,0,0.8)"; ctx.lineWidth=2
                                        ctx.beginPath(); ctx.moveTo(oTL.x,oTL.y)
                                        ctx.lineTo(oTR.x,oTR.y); ctx.lineTo(oBR.x,oBR.y); ctx.lineTo(oBL.x,oBL.y)
                                        ctx.closePath(); ctx.stroke()
                                    }
                                }

                                // Zona A (vinho)
                                Rectangle {
                                    property var zd: (recordingRoot.zones && recordingRoot.zones.length > campoCell.ci*2)
                                                     ? recordingRoot.zones[campoCell.ci*2] : {x:0,y:0,r:0}
                                    width:  parent.width  * zd.r * 2; height: width; radius: width/2
                                    x: parent.width  * zd.x - width/2
                                    y: parent.height * zd.y - height/2
                                    color: "#40ab3d4c"; border.color: "#ab3d4c"; border.width: 2
                                }
                                // Zona B (azul)
                                Rectangle {
                                    property var zd: (recordingRoot.zones && recordingRoot.zones.length > campoCell.ci*2+1)
                                                     ? recordingRoot.zones[campoCell.ci*2+1] : {x:0,y:0,r:0}
                                    width:  parent.width  * zd.r * 2; height: width; radius: width/2
                                    x: parent.width  * zd.x - width/2
                                    y: parent.height * zd.y - height/2
                                    color: "#404466aa"; border.color: "#4466aa"; border.width: 2
                                }

                                // Esqueleto: linha body→nose + pontos
                                Canvas {
                                    id: skeletonCanv
                                    anchors.fill: parent
                                    z: 10
                                    property int ci: campoCell.ci

                                    property real _nx: recordingRoot.ratLocalX(ci)
                                    property real _ny: recordingRoot.ratLocalY(ci)
                                    property real _nl: recordingRoot.ratLikelihood[ci]
                                    property real _bx: recordingRoot.bodyLocalX(ci)
                                    property real _by: recordingRoot.bodyLocalY(ci)
                                    property real _bl: recordingRoot.bodyLikelihood[ci]

                                    on_NxChanged: requestPaint()
                                    on_NyChanged: requestPaint()
                                    on_NlChanged: requestPaint()
                                    on_BxChanged: requestPaint()
                                    on_ByChanged: requestPaint()
                                    on_BlChanged: requestPaint()
                                    onWidthChanged:  requestPaint()
                                    onHeightChanged: requestPaint()

                                    onPaint: {
                                        var ctx = getContext("2d")
                                        ctx.clearRect(0, 0, width, height)

                                        var noseOk = _nl > 0.5 && _nx >= 0
                                        var bodyOk = _bl > 0.5 && _bx >= 0

                                        var nX = _nx * width
                                        var nY = _ny * height
                                        var bX = _bx * width
                                        var bY = _by * height

                                        // Linha do esqueleto body → nose
                                        if (noseOk && bodyOk) {
                                            ctx.beginPath()
                                            ctx.moveTo(bX, bY)
                                            ctx.lineTo(nX, nY)
                                            ctx.strokeStyle = "rgba(255,255,255,0.85)"
                                            ctx.lineWidth = 2
                                            ctx.stroke()
                                        }

                                        // Nariz (vermelho)
                                        if (noseOk) {
                                            ctx.beginPath()
                                            ctx.arc(nX, nY, 6, 0, Math.PI * 2)
                                            ctx.fillStyle = "#ff3366"
                                            ctx.fill()
                                            ctx.strokeStyle = "white"
                                            ctx.lineWidth = 2
                                            ctx.stroke()
                                        }

                                        // Corpo (laranja)
                                        if (bodyOk) {
                                            ctx.beginPath()
                                            ctx.arc(bX, bY, 5, 0, Math.PI * 2)
                                            ctx.fillStyle = "#ff8800"
                                            ctx.fill()
                                            ctx.strokeStyle = "white"
                                            ctx.lineWidth = 2
                                            ctx.stroke()
                                        }
                                    }
                                }

                                // Badge campo (canto sup-esq)
                                Rectangle {
                                    anchors { top: parent.top; left: parent.left; margins: 4 }
                                    radius: 3; color: "#aa0a0a16"
                                    border.color: "#3a3a5c"; border.width: 1
                                    width: fieldLbl.implicitWidth + 10; height: 18; z: 10
                                    Text {
                                        id: fieldLbl; anchors.centerIn: parent
                                        text: "C" + (campoCell.ci + 1)
                                        color: "#8888aa"; font.pixelSize: 9; font.weight: Font.Bold
                                    }
                                }

                                // Badge timer independente (canto sup-dir)
                                Rectangle {
                                    anchors { top: parent.top; right: parent.right; margins: 4 }
                                    radius: 3
                                    color: recordingRoot.fieldFinished[campoCell.ci] ? "#0d1f10" : "#aa000000"
                                    border.color: {
                                        if (recordingRoot.fieldFinished[campoCell.ci]) return "#3a8a50"
                                        if (recordingRoot.timerStarted[campoCell.ci])  return "#ab3d4c"
                                        return "#3a3a5c"
                                    }
                                    border.width: 1
                                    width: timerLbl.implicitWidth + 10; height: 18; z: 10
                                    Text {
                                        id: timerLbl; anchors.centerIn: parent
                                        text: recordingRoot.fieldFinished[campoCell.ci] ? "✓ Fim"
                                            : recordingRoot.timerStarted[campoCell.ci]
                                              ? recordingRoot.formatTime(recordingRoot.timesRemaining[campoCell.ci])
                                              : "—"
                                        color: recordingRoot.fieldFinished[campoCell.ci] ? "#5aaa70"
                                             : recordingRoot.timesRemaining[campoCell.ci] <= 30 ? "#ff5566"
                                             : "#e8e8f0"
                                        font.pixelSize: 9; font.bold: true; font.family: "Consolas"
                                    }
                                }
                            }
                        }
                    }

                    // ── Célula inferior-dir: VideoOutput mestre + estado ──────
                    Rectangle {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        color: "#08080f"; border.color: "#1a1a2e"; border.width: 1

                        VideoOutput {
                            id: framePreviewMaster
                            anchors.fill: parent
                            source: displayPlayer
                            fillMode: VideoOutput.PreserveAspectFit
                            opacity: 0.45
                        }

                        // Estado da análise sobreposto
                        Column {
                            anchors.centerIn: parent
                            spacing: 6
                            visible: !recordingRoot.isAnalyzing

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "🎬"; font.pixelSize: 20; opacity: 0.3
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: recordingRoot.videoPath !== "" ? "Vídeo pronto\npressione Iniciar" : "Carregue um vídeo\nna aba Arena"
                                color: "#444466"; font.pixelSize: 9
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }

                        // Badge de estado (carregando / analisando)
                        Rectangle {
                            anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 6 }
                            visible: recordingRoot.isAnalyzing
                            radius: 3
                            color: recordingRoot.isAnalyzing ? "#0d1f10" : (recordingRoot._dlcReady ? "#1f0d10" : "#1a1000")
                            border.color: recordingRoot.isAnalyzing ? "#3a8a50" : (recordingRoot._dlcReady ? "#ab3d4c" : "#aa6600")
                            border.width: 1
                            width: analyzingLbl.implicitWidth + 12; height: 18
                            Text {
                                id: analyzingLbl; anchors.centerIn: parent
                                text: recordingRoot._dlcReady ? "▶ Analisando ao vivo..." : "⏳ Iniciando motor DLC..."
                                color: recordingRoot._dlcReady ? "#5aaa70" : "#ffaa44"
                                font.pixelSize: 9; font.weight: Font.Bold
                            }
                        }
                    }
                }
            }

            // ── Painel de dados (direita) ──────────────────────────────────────
            Rectangle {
                width: 370; Layout.fillHeight: true
                color: "#1a1a2e"

                Rectangle {
                    anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
                    width: 1; color: "#2d2d4a"
                }

                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 14; spacing: 8

                    // ── Botão Iniciar / Parar ──────────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true; spacing: 6

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            implicitWidth: 120; height: 34; radius: 8
                            color: recordingRoot.isAnalyzing
                                   ? (startBtnMa.containsMouse ? "#5a1020" : "#3a0d15")
                                   : (startBtnMa.containsMouse ? "#2a6a40" : "#1f5430")
                            border.color: recordingRoot.isAnalyzing ? "#ab3d4c" : "#3a8a50"
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Text {
                                anchors.centerIn: parent
                                text: recordingRoot.isAnalyzing ? "⏹  Parar" : "▶  Iniciar"
                                color: "white"; font.pixelSize: 13; font.bold: true
                            }
                            MouseArea {
                                id: startBtnMa; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (recordingRoot.isAnalyzing) recordingRoot.stopSession()
                                    else                           recordingRoot.startSession()
                                }
                            }
                        }
                    }

                    // ── LOG ────────────────────────────────────────────────────
                    Text {
                        text: "LOG"
                        color: "#555577"; font.pixelSize: 10; font.weight: Font.Bold
                        font.letterSpacing: 1
                    }

                    Rectangle {
                        Layout.fillWidth: true; height: 100
                        radius: 6; color: "#0a0a16"
                        border.color: "#2d2d4a"; border.width: 1
                        clip: true

                        ListView {
                            id: logView
                            anchors { fill: parent; margins: 6 }
                            model: logModel; clip: true; spacing: 2
                            ScrollBar.vertical: ScrollBar {
                                policy: ScrollBar.AsNeeded
                                contentItem: Rectangle { implicitWidth: 4; radius: 2; color: "#3a3a5c" }
                            }
                            delegate: Text {
                                width: logView.width - 10
                                text: model.msg
                                color: model.isErr ? "#ff5566" : "#8888aa"
                                font.pixelSize: 10; wrapMode: Text.WordWrap
                            }
                        }
                    }

                    // ── Exploração de objetos ──────────────────────────────────
                    Rectangle { Layout.fillWidth: true; height: 1; color: "#2d2d4a" }

                    Text {
                        text: "EXPLORAÇÃO DE OBJETOS"
                        color: "#555577"; font.pixelSize: 10; font.weight: Font.Bold
                        font.letterSpacing: 1
                    }

                    ScrollView {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        clip: true
                        ScrollBar.vertical.policy: ScrollBar.AsNeeded
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                        ColumnLayout {
                            width: 370 - 14 * 2 - 8
                            spacing: 6

                            Repeater {
                                model: 3
                                delegate: Rectangle {
                                    id: campoCard
                                    width: parent.width
                                    height: cardInner.implicitHeight + 16
                                    radius: 6; color: "#12122a"
                                    border.color: recordingRoot.fieldFinished[index] ? "#2a4a30" : "#2d2d4a"
                                    border.width: 1

                                    property int    ci:      index
                                    property int    zi0:     index * 2
                                    property int    zi1:     index * 2 + 1
                                    property string pairStr: recordingRoot.pairForCampo(index)
                                    property string la: pairStr.length > 0 ? pairStr.charAt(0) : "?"
                                    property string lb: pairStr.length > 1 ? pairStr.charAt(1) : "?"

                                    ColumnLayout {
                                        id: cardInner
                                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                                        spacing: 5

                                        // ── Cabeçalho do campo ────────────────
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text {
                                                text: "CAMPO " + (campoCard.ci + 1)
                                                color: "#555577"; font.pixelSize: 10; font.weight: Font.Bold
                                            }
                                            Item { Layout.fillWidth: true }
                                            // Timer badge
                                            Rectangle {
                                                radius: 4
                                                color: recordingRoot.fieldFinished[campoCard.ci] ? "#0d1f10" : "#1a1a30"
                                                border.color: recordingRoot.fieldFinished[campoCard.ci] ? "#3a8a50"
                                                            : recordingRoot.timerStarted[campoCard.ci] ? "#ab3d4c"
                                                            : "#3a3a5c"
                                                border.width: 1
                                                implicitWidth: timerBdg.implicitWidth + 10; implicitHeight: 18
                                                Text {
                                                    id: timerBdg; anchors.centerIn: parent
                                                    text: recordingRoot.fieldFinished[campoCard.ci] ? "✅ Concluído"
                                                        : recordingRoot.timerStarted[campoCard.ci]
                                                          ? recordingRoot.formatTime(recordingRoot.timesRemaining[campoCard.ci])
                                                          : "Aguardando rato"
                                                    color: recordingRoot.fieldFinished[campoCard.ci] ? "#5aaa70"
                                                         : recordingRoot.timerStarted[campoCard.ci]
                                                           ? (recordingRoot.timesRemaining[campoCard.ci] <= 30 ? "#ff5566" : "#e8e8f0")
                                                           : "#555577"
                                                    font.pixelSize: 9; font.bold: true; font.family: "Consolas"
                                                }
                                            }
                                        }

                                        Rectangle { Layout.fillWidth: true; height: 1; color: "#1f1f3a" }

                                        // ── OBJ A (familiar / esquerda) ───────
                                        RowLayout {
                                            Layout.fillWidth: true; spacing: 5
                                            Rectangle { width: 8; height: 8; radius: 4; color: "#ab3d4c" }
                                            Text {
                                                text: "OBJ " + campoCard.la + "  (familiar)"
                                                color: "#cc5566"; font.pixelSize: 10; font.weight: Font.Bold
                                            }
                                            Item { Layout.fillWidth: true }
                                            Text {
                                                text: recordingRoot.explorationTimes[campoCard.zi0].toFixed(1) + " s"
                                                color: "#e8e8f0"; font.pixelSize: 11; font.family: "Consolas"
                                            }
                                        }
                                        // Bout live OBJ A
                                        Rectangle {
                                            Layout.fillWidth: true; height: 18; radius: 4
                                            visible: recordingRoot._inZone[campoCard.zi0]
                                            color: "#2a0d14"
                                            border.color: "#7a2030"; border.width: 1
                                            Text {
                                                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 6 }
                                                text: "▶ agora: " + recordingRoot.currentBoutSec(campoCard.zi0).toFixed(1) + " s"
                                                color: "#ff7788"; font.pixelSize: 9; font.bold: true
                                            }
                                        }

                                        Rectangle { Layout.fillWidth: true; height: 1; color: "#1a1a2e" }

                                        // ── OBJ B (novo / direita) ────────────
                                        RowLayout {
                                            Layout.fillWidth: true; spacing: 5
                                            Rectangle { width: 8; height: 8; radius: 4; color: "#4466aa" }
                                            Text {
                                                text: "OBJ " + campoCard.lb + "  (novo)"
                                                color: "#5577bb"; font.pixelSize: 10; font.weight: Font.Bold
                                            }
                                            Item { Layout.fillWidth: true }
                                            Text {
                                                text: recordingRoot.explorationTimes[campoCard.zi1].toFixed(1) + " s"
                                                color: "#e8e8f0"; font.pixelSize: 11; font.family: "Consolas"
                                            }
                                        }
                                        // Bout live OBJ B
                                        Rectangle {
                                            Layout.fillWidth: true; height: 18; radius: 4
                                            visible: recordingRoot._inZone[campoCard.zi1]
                                            color: "#0d1020"
                                            border.color: "#2a3a60"; border.width: 1
                                            Text {
                                                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 6 }
                                                text: "▶ agora: " + recordingRoot.currentBoutSec(campoCard.zi1).toFixed(1) + " s"
                                                color: "#6688cc"; font.pixelSize: 9; font.bold: true
                                            }
                                        }

                                        Rectangle { Layout.fillWidth: true; height: 1; color: "#1f1f3a" }

                                        // ── Índice de Discriminação ───────────
                                        Rectangle {
                                            Layout.fillWidth: true; height: 26; radius: 4
                                            property real diVal: recordingRoot.discriminationIndex(campoCard.ci)
                                            color: isNaN(diVal) ? "#14141e"
                                                 : diVal > 0    ? "#0d1f10"
                                                 : "#1f0d10"
                                            border.color: isNaN(diVal) ? "#2d2d4a"
                                                        : diVal > 0    ? "#2a4a30"
                                                        : "#4a2030"
                                            border.width: 1

                                            RowLayout {
                                                anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                                                Text {
                                                    text: "DI"
                                                    color: "#555577"; font.pixelSize: 9; font.weight: Font.Bold
                                                }
                                                Item { Layout.fillWidth: true }
                                                Text {
                                                    property real dv: recordingRoot.discriminationIndex(campoCard.ci)
                                                    text: isNaN(dv) ? "—" : (dv >= 0 ? "+" : "") + dv.toFixed(3)
                                                    color: isNaN(dv) ? "#444466"
                                                         : dv > 0   ? "#5aaa70"
                                                         : "#ff5566"
                                                    font.pixelSize: 12; font.bold: true; font.family: "Consolas"
                                                }
                                                Text {
                                                    property real dv: recordingRoot.discriminationIndex(campoCard.ci)
                                                    text: isNaN(dv) ? "" : (dv > 0 ? "↑ novo" : dv < 0 ? "↓ fam" : "=")
                                                    color: isNaN(dv) ? "#444466"
                                                         : dv > 0   ? "#5aaa70"
                                                         : "#ff5566"
                                                    font.pixelSize: 9
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            Item { width: 1; height: 4 }
                        }
                    }
                }
            }
        }
    }
}
