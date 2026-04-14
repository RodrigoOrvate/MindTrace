import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../core"
import "../core/Theme"
import QtMultimedia
import MindTrace.Tracking 1.0

Item {
    id: recordingRoot

    // ── Propriedades injetadas pelo MainDashboard ─────────────────────────────
    property string videoPath: ""
    property string pair1: ""
    property string pair2: ""
    property string pair3: ""
    property string analysisMode: "offline"  // "offline" ou "ao_vivo"
    property string aparato:      "nor"
    property int    numCampos:    3           // 1, 2 ou 3 campos ativos

    property var zones
    property var arenaPoints
    property var floorPoints
    property double centroRatio: 0.5
    property bool   isReactivation: false  // quando em fase de Reativação ou Teste (RO)

    // ── Propagate zones to inference engine ───────────────────────────────────────
    onZonesChanged: {
        if (zones && zones.length > 0 && (aparato === "nor" || aparato === "comportamento_complexo")) {
            for (var c = 0; c < numCampos; c++) {
                var campoZones = []
                // Each field has 2 zones (object A and B)
                for (var i = 0; i < 2; i++) {
                    var idx = c * 2 + i
                    if (zones[idx]) {
                        campoZones.push(zones[idx])
                    }
                }
                if (campoZones.length > 0) {
                    inference.setZones(c, campoZones)
                }
            }
            console.log("[LiveRecording] Zones propagated to inference:", zones.length, "zones")
        }
    }

    // ── Propaga polígono do chão para detecção de rearing ─────────────────────
    // Mesmo mecanismo do sniffing: nose fora do floorPoly + body dentro = rearing
    onFloorPointsChanged: {
        if (floorPoints) {
            for (var fc = 0; fc < numCampos; fc++) {
                if (floorPoints[fc] && floorPoints[fc].length >= 3) {
                    inference.setFloorPolygon(fc, floorPoints[fc])
                }
            }
            console.log("[LiveRecording] Floor polygon propagated for rearing detection")
        }
    }

    // ── Controle de velocidade (análise offline) ────────────────────────────────
    property double playbackRate: 1.0           // 1x, 2x, 4x, 8x, 16x
    property bool   isOffline: analysisMode === "offline"

    // ── Timer: durão configurável (5 ou 20 min) ────────────────────────────────
    property int    sessionDurationMinutes: 5   // injetado pelo dashboard
    property int    sessionDurationSeconds: sessionDurationMinutes * 60

    property var timesRemaining: [sessionDurationSeconds, sessionDurationSeconds, sessionDurationSeconds]
    property var timerStarted:   [false, false, false]
    property var fieldFinished:  [false, false, false]

    signal sessionEnded()
    signal requestVideoLoad()   // solicitado quando usuário quer carregar próximo vídeo

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

    // ── Velocidade e Distância (body point) ───────────────────────────────
    // Dimensão física da arena por campo (configurável — 50 cm padrão)
    property double arenaWidthM:  0.50   // largura de 1 campo em metros
    property double arenaHeightM: 0.50   // altura  de 1 campo em metros

    property var currentVelocity: [0.0, 0.0, 0.0]   // m/s por campo (última janela 100ms)
    property var totalDistance:   [0.0, 0.0, 0.0]   // metros acumulados por campo
    
    // Trail support
    property bool showTrail: false
    property var bodyHistory: [[], [], []]

    // Posição body anterior (coordenadas locais 0..1 dentro do campo)
    property var _prevBodyLX:   [-1.0, -1.0, -1.0]
    property var _prevBodyLY:   [-1.0, -1.0, -1.0]
    property var _prevBodyTime: [0, 0, 0]            // ms epoch

    // ── Snapshots por minuto ───────────────────────────────────────────────
    // Registra distância acumulada e exploração a cada 60 s de sessão real
    property int  _lastMinuteSnap: 0        // segundo em que foi o último snap (baseado no maior timer)
    property var  perMinuteData: [[], [], []]  // por campo: [{min, distM, expA_s, expB_s}]

    // Tick para forçar re-avaliação do bout live a cada 100 ms
    property int _explorationTick: 0
    property bool _dlcReady: false

    // ── Classificação de Comportamento (SimBA/B-SOiD) ──────────────────────────
    property var behaviorNames: ["Walking", "Sniffing", "Grooming", "Resting", "Rearing"]
    property var currentBehaviorString: ["", "", ""]

    // ── API pública para B-SOiD (inference é ID interno, não acessível de fora) ──
    function exportBehaviorFeatures(csvPath, campo) {
        return inference.exportBehaviorFeatures(csvPath, campo)
    }

    // ── Log ───────────────────────────────────────────────────────────────────
    ListModel { id: logModel }

    // ── Inference Controller (nativo — ONNX + QVideoProbe para captura de frames) ──
    InferenceController { id: inference }

    // ── Player de exibição (QML nativo) ──────────────────────────────────────────
    // Qt 6: MediaPlayer.videoOutput aponta para o VideoOutput (direção invertida vs Qt 5)
    MediaPlayer {
        id: displayPlayer
        videoOutput: framePreviewMaster
    }

    // Qt 6: Connections usa sintaxe "function onSignal(params)" para aceder parâmetros
    Connections {
        target: inference
        function onDimsReceived(width, height) {
            recordingRoot.videoWidth  = width
            recordingRoot.videoHeight = height
            logModel.append({ msg: "ℹ️ Resolução: " + width + "×" + height, isErr: false })
            logView.positionViewAtEnd()
        }
        function onFpsReceived(fps) {
            recordingRoot.dlcFps = fps
            logModel.append({ msg: "ℹ️ FPS: " + fps.toFixed(2), isErr: false })
            logView.positionViewAtEnd()
        }
        function onInfoReceived(message) {
            logModel.append({ msg: "ℹ️ " + message, isErr: false })
            logView.positionViewAtEnd()
        }
        function onReadyReceived() {
            recordingRoot._dlcReady = true
            logModel.append({ msg: "▶ Motor de Inferência pronto — tracking ativo", isErr: false })
            logView.positionViewAtEnd()
        }
        function onTrackReceived(campo, x, y, p) {
            // Nose position — direct signal from C++ ONNX inference
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
        function onBodyReceived(campo, x, y, p) {
            if (recordingRoot.videoWidth <= 0 || recordingRoot.videoHeight <= 0) return
            var bx = recordingRoot.bodyNormX.slice()
            var by = recordingRoot.bodyNormY.slice()
            var bl = recordingRoot.bodyLikelihood.slice()
            bx[campo] = x / recordingRoot.videoWidth
            by[campo] = y / recordingRoot.videoHeight
            bl[campo] = p

            // Para CC e afins, garantir que a detecção de corpo também pode iniciar o timer
            if (p > 0.5 && !recordingRoot.timerStarted[campo]) {
                var ts = recordingRoot.timerStarted.slice()
                ts[campo] = true
                recordingRoot.timerStarted = ts
            }

            recordingRoot.bodyNormX      = bx
            recordingRoot.bodyNormY      = by
            recordingRoot.bodyLikelihood = bl
        }
        function onBehaviorReceived(campo, labelId) {
            var bs = recordingRoot.currentBehaviorString.slice()
            if (labelId === -1) {
                bs[campo] = "---"
            } else {
                bs[campo] = recordingRoot.behaviorNames[labelId] || ("Id " + labelId)
            }
            recordingRoot.currentBehaviorString = bs
        }
        function onAnalyzingChanged() {
            if (!inference.isAnalyzing && recordingRoot.isAnalyzing) {
                displayPlayer.stop()
                logModel.append({ msg: "Análise encerrada.", isErr: false })
                logView.positionViewAtEnd()
                recordingRoot.isAnalyzing = false
            }
        }
        function onErrorOccurred(errorMsg) {
            displayPlayer.stop()
            logModel.append({ msg: "❌ " + errorMsg, isErr: true })
            logView.positionViewAtEnd()
            recordingRoot.isAnalyzing = false
        }
    }

    // ── Timer de sessão (1 s) — cada campo decrementa independentemente ────────
    // No modo offline, o timer escala com playbackRate (1s real = 4s vídeo a 4x).
    // No modo ao vivo, usa 1:1 (o vídeo é real-time).
    Timer {
        id: sessionMasterTimer
        interval: 1000; repeat: true; running: recordingRoot.isAnalyzing
        onTriggered: {
            var newTimes = recordingRoot.timesRemaining.slice()
            var decrement = recordingRoot.isOffline ? Math.round(recordingRoot.playbackRate) : 1
            for (var i = 0; i < 3; i++) {
                if (recordingRoot.timerStarted[i] && !recordingRoot.fieldFinished[i] && newTimes[i] > 0) {
                    newTimes[i] -= decrement
                    if (newTimes[i] <= 0) {
                        newTimes[i] = 0
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

    // ── Timer de sincronização de posição (400 ms) ────────────────────────────
    // O displayPlayer é o master. O headless C++ roda no máx 2x (cap de ONNX).
    // A 4x display / 2x headless, o drift cresce 2s/s de vídeo real.
    // O timer detecta drift > 800ms e resync o headless para a posição do display.
    Timer {
        id: positionSyncTimer
        interval: 400; repeat: true
        running: recordingRoot.isAnalyzing && recordingRoot.isOffline
        onTriggered: {
            if (recordingRoot.playbackRate <= 1) return
            var drift = displayPlayer.position - inference.position()
            if (Math.abs(drift) > 800)
                inference.seekTo(displayPlayer.position)
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
        // Marca campos além de numCampos como já concluídos (1 ou 2 campos ativos)
        if (numCampos < 3) {
            var _ff = fieldFinished.slice()
            var _ts = timerStarted.slice()
            var _tr = timesRemaining.slice()
            for (var _pi = numCampos; _pi < 3; _pi++) {
                _ff[_pi] = true; _ts[_pi] = true; _tr[_pi] = 0
            }
            fieldFinished  = _ff
            timerStarted   = _ts
            timesRemaining = _tr
        }
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
        currentVelocity  = [0.0, 0.0, 0.0]
        totalDistance    = [0.0, 0.0, 0.0]
        timerStarted     = [false, false, false]
        bodyHistory      = [[], [], []]
        _prevBodyLX      = [-1.0, -1.0, -1.0]
        _prevBodyLY      = [-1.0, -1.0, -1.0]
        _prevBodyTime    = [0, 0, 0]
        perMinuteData    = [[], [], []]
        _lastMinuteSnap  = 0
        _explorationTick = 0
        _dlcReady = false
        logModel.clear()
        logModel.append({ msg: "⏳ Carregando motor de inferência nativo...", isErr: false })
        logView.positionViewAtEnd()
        // Start display player immediately
        var pr = recordingRoot.isOffline ? recordingRoot.playbackRate : 1.0
        displayPlayer.source = videoPath
        displayPlayer.playbackRate = pr
        displayPlayer.play()
        // Start C++ backend (Model load + frame capture)
        inference.startAnalysis(videoPath, "")
        if (pr !== 1.0) inference.setPlaybackRate(Math.min(pr, 2.0))
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
        inference.stopAnalysis()
        displayPlayer.stop()
        isAnalyzing = false
        logModel.append({ msg: "⏹ Sessão parada.", isErr: false })
        logView.positionViewAtEnd()
    }

    function isPointInPoly(pt, poly) {
        if (!poly || poly.length < 3) return false
        var x = pt.x, y = pt.y
        var inside = false
        for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
            var xi = poly[i].x, yi = poly[i].y
            var xj = poly[j].x, yj = poly[j].y
            var intersect = ((yi > y) !== (yj > y)) && (x < (xj - xi) * (y - yi) / (yj - yi) + xi)
            if (intersect) inside = !inside
        }
        return inside
    }



    function accumulateExploration() {
        if (recordingRoot.aparato === "nor" && (!zones || zones.length < 6)) return
        
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
            var rx, ry, rli;
            if (recordingRoot.aparato === "campo_aberto") {
                rx  = recordingRoot.bodyNormX[campo]
                ry  = recordingRoot.bodyNormY[campo]
                rli = recordingRoot.bodyLikelihood[campo]
            } else {
                rx  = recordingRoot.ratNormX[campo]
                ry  = recordingRoot.ratNormY[campo]
                rli = recordingRoot.ratLikelihood[campo]
            }

            if (rx < 0 || rli < 0.5) {
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

            if (recordingRoot.aparato === "campo_aberto") {
                // -- Lógica Campo Aberto: Centro vs Borda (Body Tracking) --
                if (!floorPoints || !floorPoints[campo]) continue
                var fp = floorPoints[campo]
                var cr = recordingRoot.centroRatio
                var lx = bodyLocalX(campo)
                var ly = bodyLocalY(campo)
                var pt = { x: lx, y: ly }

                var cTL = { x: fp[0].x + (fp[2].x - fp[0].x)*(1-cr)/2, y: fp[0].y + (fp[2].y - fp[0].y)*(1-cr)/2 }
                var cTR = { x: fp[1].x + (fp[3].x - fp[1].x)*(1-cr)/2, y: fp[1].y + (fp[3].y - fp[1].y)*(1-cr)/2 }
                var cBR = { x: fp[2].x - (fp[2].x - fp[0].x)*(1-cr)/2, y: fp[2].y - (fp[2].y - fp[0].y)*(1-cr)/2 }
                var cBL = { x: fp[3].x - (fp[3].x - fp[1].x)*(1-cr)/2, y: fp[3].y - (fp[3].y - fp[1].y)*(1-cr)/2 }
                var centroPoly = [cTL, cTR, cBR, cBL]

                var inCentro = isPointInPoly(pt, centroPoly)
                var apCA = (recordingRoot.arenaPoints && recordingRoot.arenaPoints[campo]) ? recordingRoot.arenaPoints[campo] : fp
                var inBorda = !inCentro && isPointInPoly(pt, apCA)

                var zonesCA = [inCentro, inBorda]
                for (var zca = 0; zca < 2; zca++) {
                    var ziCA = campo * 2 + zca
                    if (zonesCA[zca]) {
                        newTimes[ziCA] += 0.1
                        if (!_inZone[ziCA]) { _inZone[ziCA] = true; _entryTime[ziCA] = now }
                    } else if (_inZone[ziCA]) {
                        var durCA = (now - _entryTime[ziCA]) / 1000.0
                        if (durCA > 0.1) { newBouts[ziCA].push(parseFloat(durCA.toFixed(1))); boutsChanged = true }
                        _inZone[ziCA] = false
                    }
                }
            } else if (recordingRoot.aparato === "comportamento_complexo") {
                continue
            } else if (recordingRoot.aparato === "esquiva_inibitoria") {
                // ── Lógica IA: Zonas quadrilaterais (Plataforma, Grade) ──
                if (!floorPoints || !floorPoints[campo] || floorPoints[campo].length < 8) continue
                var blx = bodyLocalX(campo)
                var bly = bodyLocalY(campo)
                var ptIA = { x: blx, y: bly }
                var fpIA = floorPoints[campo]
                var polyGrade = fpIA.slice(0, 4)
                var polyPlataf = fpIA.slice(4, 8)
                var inGrade = isPointInPoly(ptIA, polyGrade)
                var inPlataf = isPointInPoly(ptIA, polyPlataf)

                var zonesIA = [inPlataf, inGrade]
                for (var zia = 0; zia < 2; zia++) {
                    var ziA = campo * 2 + zia
                    if (zonesIA[zia]) {
                        newTimes[ziA] += 0.1
                        if (!_inZone[ziA]) { _inZone[ziA] = true; _entryTime[ziA] = now }
                    } else if (_inZone[ziA]) {
                        var durIA = (now - _entryTime[ziA]) / 1000.0
                        if (durIA > 0.1) { newBouts[ziA].push(parseFloat(durIA.toFixed(1))); boutsChanged = true }
                        _inZone[ziA] = false
                    }
                }
            } else {
                // -- Lógica NOR: Zonas Circulares --
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
        }
        explorationTimes = newTimes
        if (boutsChanged) explorationBouts = newBouts

        // ── Velocidade e distância do body point ──────────────────────────
        var now2    = Date.now()
        var newVel  = currentVelocity.slice()
        var newDist = totalDistance.slice()
        var newPBLX = _prevBodyLX.slice()
        var newPBLY = _prevBodyLY.slice()
        var newPBT  = _prevBodyTime.slice()
        var newHist = [
            recordingRoot.bodyHistory[0] ? recordingRoot.bodyHistory[0].slice() : [],
            recordingRoot.bodyHistory[1] ? recordingRoot.bodyHistory[1].slice() : [],
            recordingRoot.bodyHistory[2] ? recordingRoot.bodyHistory[2].slice() : []
        ]

        for (var ci = 0; ci < 3; ci++) {
            var blx = bodyLocalX(ci)
            var bly = bodyLocalY(ci)
            var bl  = bodyLikelihood[ci]

            if (blx >= 0 && bl >= 0.5 && recordingRoot.timerStarted[ci]) {
                newHist[ci].push({x: blx, y: bly})
                if (newHist[ci].length > 40) newHist[ci].shift() // Mantém últimos ~4000ms visíveis
            }

            if (blx < 0 || bl < 0.5 || !recordingRoot.timerStarted[ci]) {
                newVel[ci] = 0.0
                newPBLX[ci] = -1.0
                continue
            }

            var prevX = newPBLX[ci]
            var prevY = newPBLY[ci]
            var prevT = newPBT[ci]

            if (prevX >= 0 && prevT > 0) {
                var dx   = (blx - prevX) * arenaWidthM
                var dy   = (bly - prevY) * arenaHeightM
                var dist = Math.sqrt(dx * dx + dy * dy)
                var dt   = (now2 - prevT) / 1000.0

                // Filtra saltos impossíveis (> 10 m/s = glitch de modelo ou pulo da GPU)
                if (dt > 0 && dist / dt < 10.0) {
                    newVel[ci]   = dist / dt
                    newDist[ci] += dist
                }
            }

            newPBLX[ci] = blx
            newPBLY[ci] = bly
            newPBT[ci]  = now2
        }

        currentVelocity = newVel
        totalDistance   = newDist
        bodyHistory     = newHist
        _prevBodyLX     = newPBLX
        _prevBodyLY     = newPBLY
        _prevBodyTime   = newPBT

        // Propaga velocidade para o classificador de comportamento (C++)
        for (var c = 0; c < 3; c++) {
            inference.setVelocity(c, currentVelocity[c])
        }

        // ── Snapshot por minuto ──────────────────────────────────────────
        // Usa o maior timer restante para calcular minuto corrido
        var maxTimer = Math.max(timesRemaining[0], timesRemaining[1], timesRemaining[2])
        var elapsedSec = 300 - maxTimer
        var currentMin = Math.floor(elapsedSec / 60)
        if (currentMin > _lastMinuteSnap && elapsedSec >= 60) {
            _lastMinuteSnap = currentMin
            var newPMD = [perMinuteData[0].slice(), perMinuteData[1].slice(), perMinuteData[2].slice()]
            for (var pm = 0; pm < 3; pm++) {
                newPMD[pm].push({
                    "min":    currentMin,
                    "distM":  parseFloat(newDist[pm].toFixed(3)),
                    "expA_s": parseFloat(explorationTimes[pm * 2].toFixed(1)),
                    "expB_s": parseFloat(explorationTimes[pm * 2 + 1].toFixed(1))
                })
            }
            perMinuteData = newPMD
        }
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
            color: ThemeManager.surfaceDim
            border.color: ThemeManager.border; border.width: 1
            Behavior on color { ColorAnimation { duration: 200 } }
            Behavior on border.color { ColorAnimation { duration: 200 } }

            ColumnLayout {
                anchors.fill: parent; anchors.margins: 12; spacing: 12

                RowLayout {
                    spacing: 16
                    
                    Item { Layout.fillWidth: true }

                    // ── Velocidade (só aparece em modo offline) ──────────────
                    Text {
                        text: "\u23E9"; font.pixelSize: 13; color: ThemeManager.textTertiary
                        visible: recordingRoot.isOffline
                    }
                    Repeater {
                        // Limite fixado em 2x prescrevendo qualidade e evitando gargalo visual de sync do tracking/video
                        model: [1, 2]
                        delegate: Rectangle {
                            id: speedBtn
                            property bool isSel: recordingRoot.playbackRate === modelData
                            height: 28; radius: 6
                            width: spdLbl.implicitWidth + 14
                            visible: recordingRoot.isOffline
                            color: isSel ? ThemeManager.accent : (spdMa.containsMouse ? ThemeManager.surfaceAlt : "transparent")
                            border.color: isSel ? ThemeManager.accentHover : (spdMa.containsMouse ? ThemeManager.borderLight : ThemeManager.border)
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }
                            Text {
                                id: spdLbl; anchors.centerIn: parent
                                text: modelData + "x"
                                color: speedBtn.isSel ? ThemeManager.buttonText : (spdMa.containsMouse ? ThemeManager.textPrimary : ThemeManager.textSecondary)
                                font.pixelSize: 11; font.weight: Font.Bold
                            }
                            MouseArea {
                                id: spdMa; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                visible: recordingRoot.isOffline
                                onClicked: {
                                    var rate = modelData
                                    var pos  = displayPlayer.position
                                    recordingRoot.playbackRate = rate
                                    // Stop-seek-play evita o frame preto do WMF
                                    // ao mudar playbackRate enquanto o player está ativo
                                    displayPlayer.stop()
                                    displayPlayer.playbackRate = rate
                                    displayPlayer.setPosition(pos)
                                    displayPlayer.play()
                                    // Headless capped a 2x: ONNX CPU recebe frames no máx 2x.
                                    // O positionSyncTimer a cada 400ms compensa o drift restante.
                                    var headlessRate = Math.min(rate, 2.0)
                                    inference.setPlaybackRate(headlessRate)
                                    inference.seekTo(pos)
                                }
                            }
                        }
                    }
                }

                RowLayout {
                    spacing: 24
                    Repeater {
                        model: [
                            { label: "Campo 1", pair: recordingRoot.pair1, visible: true },
                            { label: "Campo 2", pair: recordingRoot.pair2, visible: recordingRoot.numCampos >= 2 },
                            { label: "Campo 3", pair: recordingRoot.pair3, visible: recordingRoot.numCampos >= 3 }
                        ]
                        delegate: RowLayout {
                            spacing: 6
                            visible: modelData.visible
                            Text { text: modelData.label; color: ThemeManager.textSecondary; font.pixelSize: 11 }
                            Rectangle {
                                radius: 4; color: ThemeManager.accentDim
                                border.color: ThemeManager.accent; border.width: 1
                                Behavior on color { ColorAnimation { duration: 150 } }
                                implicitWidth: cpTxt.implicitWidth + 16; implicitHeight: 20
                                Text {
                                    id: cpTxt; anchors.centerIn: parent
                                    text: (recordingRoot.aparato === "campo_aberto") ? "CA" 
                                           : (modelData.pair !== "" ? "Par " + modelData.pair : "—")
                                    color: ThemeManager.accent; font.pixelSize: 11; font.weight: Font.Bold
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
                    columns: recordingRoot.aparato === "esquiva_inibitoria" ? 1 : 2
                    rowSpacing: 2; columnSpacing: 2

                    // ── 3 campos (top-left, top-right, bottom-left) ───────────
                    Repeater {
                        model: recordingRoot.numCampos
                        delegate: Item {
                            id: campoCell
                            Layout.fillWidth: true; Layout.fillHeight: true
                            property int ci: index

                            Rectangle {
                                id: campoRect
                                width: Math.min(parent.width, parent.height)
                                height: width
                                anchors.centerIn: parent
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
                                        if (recordingRoot.aparato === "esquiva_inibitoria") return cr
                                        var cw = cr.width / 2
                                        var ch = cr.height / 2
                                        if (campoCell.ci === 0) return Qt.rect(cr.x,      cr.y,      cw, ch)
                                        if (campoCell.ci === 1) return Qt.rect(cr.x + cw, cr.y,      cw, ch)
                                        return                         Qt.rect(cr.x,      cr.y + ch, cw, ch)
                                    }
                                    opacity: 0.85
                                }

                                // Overlay para exibir Behavior Badge em tempo real
                                Rectangle {
                                    id: behaviorBadge
                                    anchors { top: parent.top; left: parent.left; margins: 10 }
                                    visible: recordingRoot.currentBehaviorString[campoCell.ci] !== "" && recordingRoot.isAnalyzing
                                    color: "#cc0a0a16"
                                    border.color: ThemeManager.accent
                                    border.width: 1
                                    radius: 6
                                    implicitWidth: bTxt.implicitWidth + 16
                                    implicitHeight: 24
                                    z: 100 // acima da grid e das zonas
                                    Text {
                                        id: bTxt
                                        anchors.centerIn: parent
                                        text: recordingRoot.currentBehaviorString[campoCell.ci]
                                        color: ThemeManager.textPrimary
                                        font.pixelSize: 11; font.weight: Font.Bold
                                    }
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
                                        function onArenaPointsChanged() { arenaCanv.requestPaint() }
                                        function onFloorPointsChanged() { arenaCanv.requestPaint() }
                                    }
                                    onPaint: {
                                        var ctx = getContext("2d")
                                        ctx.clearRect(0, 0, width, height)

                                        if (!recordingRoot.arenaPoints || !recordingRoot.floorPoints) {
                                            ctx.fillStyle = "red"
                                            ctx.fillText("SEM ARENA", 10, 20)
                                            return
                                        }
                                        var ap = recordingRoot.arenaPoints[ci]
                                        var fp = recordingRoot.floorPoints[ci]
                                        if (!ap || !fp) {
                                            ctx.fillStyle = "orange"
                                            ctx.fillText("SEM AP/FP", 10, 20)
                                            return
                                        }
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

                                        if (recordingRoot.aparato === "esquiva_inibitoria") {
                                            // Grade (0-3 do floorPoints)
                                            if (fp.length >= 4) {
                                                var polyF = []
                                                for(var k1=0;k1<4;k1++) polyF.push({x:fp[k1].x*w, y:fp[k1].y*h})
                                                poly(polyF, "rgba(0,204,255,0.08)", "rgba(0,204,255,0.5)")
                                            }
                                            // Plataforma (4-7 do floorPoints)
                                            if (fp.length >= 8) {
                                                var polyP = []
                                                for(var k2=4;k2<8;k2++) polyP.push({x:fp[k2].x*w, y:fp[k2].y*h})
                                                poly(polyP, "rgba(0,255,0,0.08)", "rgba(0,255,0,0.5)")
                                            }
                                        } else if (recordingRoot.aparato === "campo_aberto") {
                                            var cr = recordingRoot.centroRatio
                                            var cTL = { x: iTL.x + (iBR.x - iTL.x)*(1-cr)/2, y: iTL.y + (iBR.y - iTL.y)*(1-cr)/2 }
                                            var cTR = { x: iTR.x + (iBL.x - iTR.x)*(1-cr)/2, y: iTR.y + (iBL.y - iTR.y)*(1-cr)/2 }
                                            var cBR = { x: iBR.x - (iBR.x - iTL.x)*(1-cr)/2, y: iBR.y - (iBR.y - iTL.y)*(1-cr)/2 }
                                            var cBL = { x: iBL.x - (iBL.x - iTR.x)*(1-cr)/2, y: iBL.y - (iBL.y - iTR.y)*(1-cr)/2 }

                                            poly([iTL,iTR,iBR,iBL],"rgba(0,255,255,0.1)","rgba(0,255,255,0.5)") // Borda (Cyan)
                                            poly([cTL,cTR,cBR,cBL],"rgba(255,0,255,0.18)","rgba(255,0,255,0.7)") // Centro (Magenta)
                                        } else {
                                            poly([iTL,iTR,iBR,iBL],"rgba(255,0,255,0.12)","rgba(255,0,255,0.5)")
                                        }

                                        poly([oTL,oTR,iTR,iTL],"rgba(255,0,0,0.12)",  "rgba(255,0,0,0.5)")
                                        poly([iBL,iBR,oBR,oBL],"rgba(0,255,0,0.12)",  "rgba(0,255,0,0.5)")
                                        poly([oTL,iTL,iBL,oBL],"rgba(0,255,255,0.12)","rgba(0,255,255,0.5)")
                                        poly([iTR,oTR,oBR,iBR],"rgba(255,255,0,0.12)","rgba(255,255,0,0.5)")
                                        ctx.strokeStyle="rgba(255,170,0,0.8)"; ctx.lineWidth=2
                                        ctx.beginPath(); ctx.moveTo(oTL.x,oTL.y)
                                        ctx.lineTo(oTR.x,oTR.y); ctx.lineTo(oBR.x,oTR.y); ctx.lineTo(oBL.x,oTR.y)
                                        ctx.closePath(); ctx.stroke()

                                        // Labels (apenas no CA, nunca no RO)
                                        if (recordingRoot.aparato === "campo_aberto") {
                                            ctx.font = "bold 9px Inter"; ctx.fillStyle = "rgba(255,255,255,0.7)"
                                            ctx.fillText("Centro", (iTL.x+iBR.x)/2 - 12, (iTL.y+iBR.y)/2)
                                        }
                                    }
                                }

                                // Zona A (vinho) - visível quando não é CA
                                Rectangle {
                                    id: zoneA
                                    visible: (recordingRoot.aparato === "nor" || recordingRoot.aparato === "comportamento_complexo")
                                    property var zd: (recordingRoot.zones && recordingRoot.zones.length > campoCell.ci*2)
                                                     ? recordingRoot.zones[campoCell.ci*2] : {x:0.3,y:0.5,r:0.12}
                                    width:  parent.width  * (zd.r > 0 ? zd.r * 2 : 0.24)
                                    height: width
                                    radius: width / 2
                                    x: parent.width  * (zd.x > 0 ? zd.x : 0.3) - width/2
                                    y: parent.height * (zd.y > 0 ? zd.y : 0.5) - height/2
                                    color: "#40ab3d4c"; border.width: 2
                                    opacity: 0.7
                                }
                                // Zona B (azul) - visível quando não é CA
                                Rectangle {
                                    id: zoneB
                                    visible: (recordingRoot.aparato === "nor" || recordingRoot.aparato === "comportamento_complexo")
                                    property var zd: (recordingRoot.zones && recordingRoot.zones.length > campoCell.ci*2+1)
                                                     ? recordingRoot.zones[campoCell.ci*2+1] : {x:0.7,y:0.5,r:0.12}
                                    width:  parent.width  * (zd.r > 0 ? zd.r * 2 : 0.24)
                                    height: width
                                    radius: width / 2
                                    x: parent.width  * (zd.x > 0 ? zd.x : 0.7) - width/2
                                    y: parent.height * (zd.y > 0 ? zd.y : 0.5) - height/2
                                    color: "#404466aa"; border.width: 2
                                    opacity: 0.7
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

                                        // Rastro do rato
                                        if (recordingRoot.showTrail) {
                                            var hist = recordingRoot.bodyHistory[ci]
                                            if (hist && hist.length > 1) {
                                                ctx.beginPath()
                                                ctx.moveTo(hist[0].x * width, hist[0].y * height)
                                                for (var j = 1; j < hist.length; j++) {
                                                    ctx.lineTo(hist[j].x * width, hist[j].y * height)
                                                }
                                                ctx.strokeStyle = "rgba(255, 136, 0, 0.4)"
                                                ctx.lineWidth = 2
                                                ctx.stroke()
                                            }
                                        }

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

                        // Qt 6: VideoOutput não tem "source". O MediaPlayer referencia
                        // o VideoOutput via sua propriedade "videoOutput".
                        VideoOutput {
                            id: framePreviewMaster
                            anchors.fill: parent
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
                color: ThemeManager.surface
                Behavior on color { ColorAnimation { duration: 200 } }

                Rectangle {
                    anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
                    width: 1; color: ThemeManager.border
                    Behavior on color { ColorAnimation { duration: 200 } }
                }

                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 14; spacing: 8

                    // ── Botões Iniciar / Parar + Carregar Vídeo ───────────────
                    RowLayout {
                        Layout.fillWidth: true; spacing: 6

                        // Botão "Carregar Vídeo" — visível apenas quando parado
                        Rectangle {
                            visible: !recordingRoot.isAnalyzing
                            Layout.fillWidth: true; Layout.minimumWidth: 80
                            height: 34; radius: 8
                            color: loadBtnMa.containsMouse ? ThemeManager.surfaceAlt : ThemeManager.surfaceDim
                            border.color: ThemeManager.borderLight; border.width: 1
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }
                            Text {
                                anchors.centerIn: parent
                                text: "📂  Carregar Vídeo"
                                color: ThemeManager.textSecondary; font.pixelSize: 11; font.bold: true
                            }
                            MouseArea {
                                id: loadBtnMa; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: recordingRoot.requestVideoLoad()
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true; Layout.minimumWidth: 80
                            height: 34; radius: 8
                            color: recordingRoot.showTrail ? ThemeManager.accentDim : ThemeManager.surfaceDim
                            border.color: recordingRoot.showTrail ? ThemeManager.accent : ThemeManager.border
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Text {
                                anchors.centerIn: parent
                                text: recordingRoot.showTrail ? "👁 Rastro ON" : "🐾 Rastro OFF"
                                color: recordingRoot.showTrail ? ThemeManager.accentHover : ThemeManager.textSecondary
                                font.pixelSize: 11; font.bold: true
                            }
                            MouseArea {
                                anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: recordingRoot.showTrail = !recordingRoot.showTrail
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true; Layout.minimumWidth: 80
                            height: 34; radius: 8
                            color: recordingRoot.isAnalyzing
                                   ? (startBtnMa.containsMouse ? "#5a1020" : "#3a0d15")
                                   : (startBtnMa.containsMouse ? "#2a6a40" : "#1f5430")
                            border.color: recordingRoot.isAnalyzing ? "#ab3d4c" : "#3a8a50"
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Text {
                                anchors.centerIn: parent
                                text: recordingRoot.isAnalyzing ? "⏹  Parar" : "▶  Iniciar"
                                color: "white"; font.pixelSize: 12; font.bold: true
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
                        color: ThemeManager.textTertiary; font.pixelSize: 10; font.weight: Font.Bold
                        font.letterSpacing: 1
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    Rectangle {
                        Layout.fillWidth: true; height: 100
                        radius: 6; color: ThemeManager.surfaceDim
                        border.color: ThemeManager.border; border.width: 1
                        clip: true
                        Behavior on color { ColorAnimation { duration: 200 } }
                        Behavior on border.color { ColorAnimation { duration: 200 } }

                        ListView {
                            id: logView
                            anchors { fill: parent; margins: 6 }
                            model: logModel; clip: true; spacing: 2
                            ScrollBar.vertical: ScrollBar {
                                policy: ScrollBar.AsNeeded
                                contentItem: Rectangle { implicitWidth: 4; radius: 2; color: ThemeManager.borderLight }
                            }
                            delegate: Text {
                                width: logView.width - 10
                                text: model.msg
                                color: model.isErr ? ThemeManager.error : ThemeManager.textSecondary
                                font.pixelSize: 10; wrapMode: Text.WordWrap
                            }
                        }
                    }

                    // ── Exploração de objetos ──────────────────────────────────
                    Rectangle {
                        Layout.fillWidth: true; height: 1; color: ThemeManager.border
                        Behavior on color { ColorAnimation { duration: 200 } }
                    }

                    Text {
                        text: recordingRoot.aparato === "campo_aberto" ? "EXPLORAÇÃO DE CAMPO" :
                              recordingRoot.aparato === "comportamento_complexo" ? "EXPLORAÇÃO GERAL" : "EXPLORAÇÃO DE OBJETOS"
                        color: ThemeManager.textTertiary; font.pixelSize: 10; font.weight: Font.Bold
                        font.letterSpacing: 1
                        Behavior on color { ColorAnimation { duration: 150 } }
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
                                model: recordingRoot.numCampos
                                delegate: Rectangle {
                                    id: campoCard
                                    width: parent.width
                                    height: cardInner.implicitHeight + 16
                                    radius: 6; color: ThemeManager.surfaceDim
                                    border.color: recordingRoot.fieldFinished[index] ? ThemeManager.success : ThemeManager.border
                                    border.width: 1
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    Behavior on border.color { ColorAnimation { duration: 200 } }

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
                                                color: ThemeManager.textTertiary; font.pixelSize: 10; font.weight: Font.Bold
                                                Behavior on color { ColorAnimation { duration: 150 } }
                                            }
                                            Item { Layout.fillWidth: true }
                                            // Timer badge
                                            Rectangle {
                                                radius: 4
                                                color: recordingRoot.fieldFinished[campoCard.ci] ? ThemeManager.surfaceDim : ThemeManager.surface
                                                border.color: recordingRoot.fieldFinished[campoCard.ci] ? ThemeManager.success
                                                            : recordingRoot.timerStarted[campoCard.ci] ? ThemeManager.accent
                                                            : ThemeManager.border
                                                border.width: 1
                                                Behavior on color { ColorAnimation { duration: 150 } }
                                                Behavior on border.color { ColorAnimation { duration: 150 } }
                                                implicitWidth: timerBdg.implicitWidth + 10; implicitHeight: 18
                                                Text {
                                                    id: timerBdg; anchors.centerIn: parent
                                                    text: recordingRoot.fieldFinished[campoCard.ci] ? "✅ Concluído"
                                                        : recordingRoot.timerStarted[campoCard.ci]
                                                          ? recordingRoot.formatTime(recordingRoot.timesRemaining[campoCard.ci])
                                                          : "Aguardando rato"
                                                    color: recordingRoot.fieldFinished[campoCard.ci] ? ThemeManager.successLight
                                                         : recordingRoot.timerStarted[campoCard.ci]
                                                           ? (recordingRoot.timesRemaining[campoCard.ci] <= 30 ? ThemeManager.error : ThemeManager.textPrimary)
                                                           : ThemeManager.textTertiary
                                                    font.pixelSize: 9; font.bold: true; font.family: "Consolas"
                                                }
                                            }
                                        }

                                        Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border }

                                        // ── MÉTRICAS ESPECÍFICAS (NOR vs CA) ──
                                        ColumnLayout {
                                            Layout.fillWidth: true; spacing: 5
                                            visible: (recordingRoot.aparato === "nor" || recordingRoot.aparato === "")

                                            // OBJ A (familiar)
                                            RowLayout {
                                                Layout.fillWidth: true; spacing: 5
                                                Rectangle { width: 8; height: 8; radius: 4; color: "#ab3d4c" }
                                                Text { text: "OBJ " + campoCard.la + "  (familiar)"; color: "#cc5566"; font.pixelSize: 10; font.weight: Font.Bold }
                                                Item { Layout.fillWidth: true }
                                                Text { text: recordingRoot.explorationTimes[campoCard.zi0].toFixed(1) + " s"; color: ThemeManager.textPrimary; font.pixelSize: 11; font.family: "Consolas" }
                                            }
                                            // Bout live OBJ A
                                            Rectangle {
                                                Layout.fillWidth: true; height: 18; radius: 4; visible: recordingRoot._inZone[campoCard.zi0]
                                                color: ThemeManager.accentDim; border.color: ThemeManager.accent; border.width: 1
                                                Text {
                                                    anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 6 }
                                                    text: "▶ agora: " + recordingRoot.currentBoutSec(campoCard.zi0).toFixed(1) + " s"
                                                    color: ThemeManager.accent; font.pixelSize: 9; font.bold: true
                                                }
                                            }

                                            Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border }

                                            // OBJ B (novo)
                                            RowLayout {
                                                Layout.fillWidth: true; spacing: 5
                                                Rectangle { width: 8; height: 8; radius: 4; color: "#4466aa" }
                                                Text { text: "OBJ " + campoCard.lb + "  (novo)"; color: "#5577bb"; font.pixelSize: 10; font.weight: Font.Bold }
                                                Item { Layout.fillWidth: true }
                                                Text { text: recordingRoot.explorationTimes[campoCard.zi1].toFixed(1) + " s"; color: ThemeManager.textPrimary; font.pixelSize: 11; font.family: "Consolas" }
                                            }
                                            // Bout live OBJ B
                                            Rectangle {
                                                Layout.fillWidth: true; height: 18; radius: 4; visible: recordingRoot._inZone[campoCard.zi1]
                                                color: ThemeManager.surfaceDim; border.color: ThemeManager.borderLight; border.width: 1
                                                Text {
                                                    anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 6 }
                                                    text: "▶ agora: " + recordingRoot.currentBoutSec(campoCard.zi1).toFixed(1) + " s"
                                                    color: "#6688cc"; font.pixelSize: 9; font.bold: true
                                                }
                                            }

                                            Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border }

                                            // Discriminação (DI)
                                            Rectangle {
                                                id: diBox
                                                Layout.fillWidth: true; height: 26; radius: 4
                                                property real dv: recordingRoot.discriminationIndex(campoCard.ci)
                                                color: ThemeManager.surfaceDim; border.color: isNaN(diBox.dv) ? ThemeManager.border : (diBox.dv > 0 ? ThemeManager.success : ThemeManager.accent); border.width: 1
                                                RowLayout {
                                                    anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                                                    Text { text: "DI"; color: ThemeManager.textTertiary; font.pixelSize: 9; font.weight: Font.Bold }
                                                    Item { Layout.fillWidth: true }
                                                    Text {
                                                        text: isNaN(diBox.dv) ? "—" : (diBox.dv >= 0 ? "+" : "") + diBox.dv.toFixed(3)
                                                        color: isNaN(diBox.dv) ? "#444466" : (diBox.dv > 0 ? "#5aaa70" : "#ff5566")
                                                        font.pixelSize: 12; font.bold: true; font.family: "Consolas"
                                                    }
                                                    Text {
                                                        text: isNaN(diBox.dv) ? "" : (diBox.dv > 0 ? "↑ novo" : diBox.dv < 0 ? "↓ fam" : "=")
                                                        color: isNaN(diBox.dv) ? "#444466" : (diBox.dv > 0 ? "#5aaa70" : "#ff5566")
                                                        font.pixelSize: 9
                                                    }
                                                }
                                            }
                                        }

                                        // ── MÉTRICAS ESQUIVA INIBITÓRIA (EI) ────
                                        ColumnLayout {
                                            Layout.fillWidth: true; spacing: 5
                                            visible: recordingRoot.aparato === "esquiva_inibitoria"

                                            // Plataforma
                                            RowLayout {
                                                Layout.fillWidth: true; spacing: 5
                                                Rectangle { width: 8; height: 8; radius: 4; color: "#00ff00" }
                                                Text { text: "Plataforma"; color: "#00aa00"; font.pixelSize: 10; font.weight: Font.Bold }
                                                Item { Layout.fillWidth: true }
                                                Text { text: recordingRoot.explorationTimes[campoCard.zi0].toFixed(1) + " s"; color: ThemeManager.textPrimary; font.pixelSize: 11; font.family: "Consolas" }
                                            }
                                            // Grade
                                            RowLayout {
                                                Layout.fillWidth: true; spacing: 5
                                                Rectangle { width: 8; height: 8; radius: 4; color: "#00ccff" }
                                                Text { text: "Grade"; color: "#0088cc"; font.pixelSize: 10; font.weight: Font.Bold }
                                                Item { Layout.fillWidth: true }
                                                Text { text: recordingRoot.explorationTimes[campoCard.zi1].toFixed(1) + " s"; color: ThemeManager.textPrimary; font.pixelSize: 11; font.family: "Consolas" }
                                            }

                                            Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                Text { text: "Descidas à grade:"; color: ThemeManager.textSecondary; font.pixelSize: 11 }
                                                Item { Layout.fillWidth: true }
                                                Text { text: recordingRoot.explorationBouts[campoCard.zi1].length; color: ThemeManager.textPrimary; font.pixelSize: 11; font.weight: Font.Bold }
                                            }
                                        }

                                        // ── MÉTRICAS CAMPO ABERTO (CA) ──────────
                                        ColumnLayout {
                                            Layout.fillWidth: true; spacing: 5
                                            visible: recordingRoot.aparato === "campo_aberto"

                                            // Visitas Centro
                                            RowLayout {
                                                Layout.fillWidth: true
                                                Text { text: "Visitas ao centro:"; color: ThemeManager.textSecondary; font.pixelSize: 11 }
                                                Item { Layout.fillWidth: true }
                                                Text { text: recordingRoot.explorationBouts[campoCard.zi0].length; color: ThemeManager.textPrimary; font.pixelSize: 11; font.weight: Font.Bold }
                                            }

                                            // Visitas Borda
                                            RowLayout {
                                                Layout.fillWidth: true
                                                Text { text: "Visitas nas bordas:"; color: ThemeManager.textSecondary; font.pixelSize: 11 }
                                                Item { Layout.fillWidth: true }
                                                Text { text: recordingRoot.explorationBouts[campoCard.zi1].length; color: ThemeManager.textPrimary; font.pixelSize: 11; font.weight: Font.Bold }
                                            }

                                            Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border }

                                            // Tempo Centro
                                            RowLayout {
                                                Layout.fillWidth: true
                                                Text { text: "Tempo no centro:"; color: ThemeManager.textSecondary; font.pixelSize: 11 }
                                                Item { Layout.fillWidth: true }
                                                Text { text: recordingRoot.explorationTimes[campoCard.zi0].toFixed(1) + " s"; color: ThemeManager.accent; font.pixelSize: 11; font.weight: Font.Bold }
                                            }

                                            // Tempo Borda
                                            RowLayout {
                                                Layout.fillWidth: true
                                                Text { text: "Tempo nas bordas:"; color: ThemeManager.textSecondary; font.pixelSize: 11 }
                                                Item { Layout.fillWidth: true }
                                                Text { text: recordingRoot.explorationTimes[campoCard.zi1].toFixed(1) + " s"; color: ThemeManager.accent; font.pixelSize: 11; font.weight: Font.Bold }
                                            }
                                        }

                                        Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border }

                                        // ── Velocidade e Distância (body) ─────
                                        RowLayout {
                                            Layout.fillWidth: true; spacing: 6

                                            // Velocidade atual
                                            Rectangle {
                                                Layout.fillWidth: true; height: 26; radius: 4
                                                color: ThemeManager.surfaceDim; border.color: ThemeManager.border; border.width: 1
                                                Behavior on color { ColorAnimation { duration: 200 } }

                                                RowLayout {
                                                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                                    Text {
                                                        text: "⚡"
                                                        color: ThemeManager.textTertiary; font.pixelSize: 9
                                                    }
                                                    Item { Layout.fillWidth: true }
                                                    Text {
                                                        text: recordingRoot.currentVelocity[campoCard.ci].toFixed(2) + " m/s"
                                                        color: recordingRoot.currentVelocity[campoCard.ci] > 0.05
                                                               ? "#88aaff" : "#444466"
                                                        font.pixelSize: 10; font.bold: true; font.family: "Consolas"
                                                    }
                                                }
                                            }

                                            // Distância acumulada
                                            Rectangle {
                                                Layout.fillWidth: true; height: 26; radius: 4
                                                color: ThemeManager.surfaceDim; border.color: ThemeManager.border; border.width: 1
                                                Behavior on color { ColorAnimation { duration: 200 } }

                                                RowLayout {
                                                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                                    Text {
                                                        text: "📍"
                                                        color: ThemeManager.textTertiary; font.pixelSize: 9
                                                    }
                                                    Item { Layout.fillWidth: true }
                                                    Text {
                                                        text: recordingRoot.totalDistance[campoCard.ci].toFixed(2) + " m"
                                                        color: "#88aaff"
                                                        font.pixelSize: 10; font.bold: true; font.family: "Consolas"
                                                    }
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
