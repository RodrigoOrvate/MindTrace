import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../core"
import "../core/Theme"
import QtMultimedia
import MindTrace.Tracking 1.0

Item {
    id: recordingRoot

    // Properties injected by the dashboard
    property string videoPath: ""
    property string saveDirectory: ""
    property string liveOutputName: ""
    property string cameraId: ""             // camera description for live mode
    property string pair1: ""
    property string pair2: ""
    property string pair3: ""
    property string analysisMode: "offline"  // "offline" or "ao_vivo"
    property string aparato:      "nor"
    property string context:      ""
    property var    contextPatterns: []
    property int    numCampos:    3           // 1, 2 ou 3 campos ativos
    property bool   ccMode:       false      // CC: shows only distance/speed/behavior

    property var zones
    property var arenaPoints
    property var floorPoints
    property double centroRatio: 0.5
    property bool   isReactivation: false  // true during Reactivation or Test (RO) phase

    // Propagate zones to inference engine
    onZonesChanged: {
        if (aparato !== "nor" && aparato !== "comportamento_complexo") return
        if (zones && zones.length > 0) {
            for (var c = 0; c < numCampos; c++) {
                var campoZones = []
                for (var i = 0; i < 2; i++) {
                    var idx = c * 2 + i
                    if (zones[idx]) campoZones.push(zones[idx])
                }
                inference.setZones(c, campoZones)
            }
            console.log("[LiveRecording] Zones propagated to inference:", zones.length, "zones")
        } else {
            // Clear zones in C++ to disable sniffing when no objects are configured
            for (var fc = 0; fc < numCampos; fc++) {
                inference.setZones(fc, [])
            }
            console.log("[LiveRecording] Zones cleared in inference (no object zones)")
        }
    }

    // Propagate floor polygon for rearing detection
    // Same mechanism as sniffing: nose outside floorPoly + body inside = rearing
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

    // Playback speed control (offline analysis)
    property double playbackRate: 1.0           // 1x, 2x, 4x, 8x, 16x
    property bool   isOffline: analysisMode === "offline"

    // Session timer — configurable duration (5 or 20 min)
    property int    sessionDurationMinutes: 5   // injetado pelo dashboard
    property int    sessionDurationSeconds: sessionDurationMinutes * 60

    property var timesRemaining: [sessionDurationSeconds, sessionDurationSeconds, sessionDurationSeconds]
    property var timerStarted:   [false, false, false]
    property var fieldFinished:  [false, false, false]

    // EI: elapsed session seconds at moment of first grade entry (-1 = not yet)
    property real eiLatencySeconds: -1

    signal sessionEnded()
    signal requestVideoLoad()   // emitted when user wants to load the next video
    signal liveAnalysisStarting() // emitted before startLiveAnalysis — dashboards must stop arena preview

    // Internal state
    property bool isAnalyzing:   false
    // Session-end guards — prevent double popup and distinguish manual stop
    property bool _sessionEndedEmitted:  false
    property bool _manualStopRequested:  false

    function _guardedSessionEnded() {
        if (!_sessionEndedEmitted) {
            _sessionEndedEmitted = true
            sessionEnded()
        }
    }
    property int  videoWidth:    0
    property int  videoHeight:   0

    // Normalized coords in full frame (0..1) — Nose
    property var ratNormX:      [-1, -1, -1]
    property var ratNormY:      [-1, -1, -1]
    property var ratLikelihood: [0,  0,  0 ]

    // Normalized coords in full frame (0..1) — Body
    property var bodyNormX:      [-1, -1, -1]
    property var bodyNormY:      [-1, -1, -1]
    property var bodyLikelihood: [0,  0,  0 ]

    // DLC-reported FPS (sent via FPS, signal)
    property double dlcFps:       30.0

    // Live diagnostics (visible only in live mode)
    property string liveCameraName: ""
    property string liveRecordedVideoPath: ""
    property int    liveFrameCount: 0
    property int    _lastFpsFrameCount: 0
    property double _lastFpsTimestampMs: 0
    property double _lastFpsLogTimestampMs: 0

    // Exploration per zone (6 zones — 2 per field)
    property var explorationTimes: [0, 0, 0, 0, 0, 0]
    property var explorationBouts: [[], [], [], [], [], []]

    // Internal bout control — simple arrays (no binding needed)
    property var _inZone:    [false, false, false, false, false, false]
    property var _entryTime: [0,     0,     0,     0,     0,     0    ]  // ms epoch

    // Velocity and Distance (body point)
    // Physical arena dimensions per field (configurable — 50 cm default)
    property double arenaWidthM:  0.50   // largura de 1 campo em metros
    property double arenaHeightM: 0.50   // altura  de 1 campo em metros

    property var currentVelocity: [0.0, 0.0, 0.0]   // m/s per field (last 100ms window)
    property var totalDistance:   [0.0, 0.0, 0.0]   // metros acumulados por campo

    // True average velocity = total distance / elapsed time per field
    readonly property var avgVelocityMeans: {
        var res = [0.0, 0.0, 0.0]
        for (var i = 0; i < 3; i++) {
            // timesRemaining[i] can be 0 (falsy) when session ends — use != null
            var remaining = (timesRemaining[i] != null && timesRemaining[i] !== undefined)
                            ? timesRemaining[i] : sessionDurationSeconds
            var elapsed = sessionDurationSeconds - remaining
            res[i] = elapsed > 1 ? (totalDistance[i] || 0) / elapsed : 0.0
        }
        return res
    }
    
    // Trail support
    property bool showTrail: false
    property var bodyHistory: [[], [], []]

    // Previous body position (local coords 0..1 within field)
    property var _prevBodyLX:   [-1.0, -1.0, -1.0]
    property var _prevBodyLY:   [-1.0, -1.0, -1.0]
    property var _prevBodyTime: [0, 0, 0]            // ms epoch

    // Per-minute snapshots
    // Records accumulated distance and exploration every 60s of real session time
    property int  _lastMinuteSnap: 0        // second of last snapshot (based on highest timer)
    property var  perMinuteData: [[], [], []]  // por campo: [{min, distM, expA_s, expB_s}]

    // Tick to force re-evaluation of live bout every 100 ms
    property int _explorationTick: 0
    property bool _dlcReady: false

    // Behavior Classification (rule-based)
    property var behaviorNames: ["Walking", "Sniffing", "Grooming", "Resting", "Rearing"]
    property var currentBehaviorString: ["", "", ""]
    property var behaviorCounts: [{}, {}, {}]
    property var _lastBehaviorId: [-1, -1, -1]
    readonly property double minBoutDurationSec: 0.5
    readonly property double maxBoutBridgeGapSec: 0.6

    // Public API for B-SOiD (inference is an internal ID, not accessible from outside)
    function exportBehaviorFeatures(csvPath, campo) {
        return inference.exportBehaviorFeatures(csvPath, campo)
    }
    function saveBehaviorCache(experimentPath, campo) {
        return inference.saveBehaviorCache(experimentPath, campo)
    }
    function behaviorCacheExists(experimentPath, campo) {
        return inference.behaviorCacheExists(experimentPath, campo)
    }
    function behaviorCachePath(experimentPath, campo) {
        return inference.behaviorCachePath(experimentPath, campo)
    }
    function getBehaviorFrames(campo) {
        return inference.getBehaviorFrames(campo)
    }
    function getBehaviorFramesFromCache(experimentPath, campo) {
        return inference.getBehaviorFramesFromCache(experimentPath, campo)
    }
    function writeTextFile(path, content, utf8Bom) {
        return inference.writeTextFile(path, content, utf8Bom)
    }
    function readTextFile(path) {
        return inference.readTextFile(path)
    }
    function savePdfReport(path, imagePaths, title, captions) {
        return inference.savePdfReport(path, imagePaths, title, captions)
    }

    function filteredBehaviorCounts(campo) {
        return _computeBehaviorBoutCounts(inference.getBehaviorFrames(campo), dlcFps)
    }

    function filteredBehaviorCountsFromCache(experimentPath, campo) {
        return _computeBehaviorBoutCounts(inference.getBehaviorFramesFromCache(experimentPath, campo), dlcFps)
    }

    function filteredBehaviorCountsForAllCampos() {
        var out = []
        for (var c = 0; c < 3; c++)
            out.push(filteredBehaviorCounts(c))
        return out
    }

    function _computeBehaviorBoutCounts(frames, fps) {
        var countsByName = ({})
        for (var nameIdx = 0; nameIdx < behaviorNames.length; nameIdx++)
            countsByName[behaviorNames[nameIdx]] = 0
        if (!frames || frames.length === 0)
            return countsByName

        var labels = []
        for (var i = 0; i < frames.length; i++) {
            var lbl = frames[i].ruleLabel
            labels.push(lbl >= 0 && lbl < behaviorNames.length ? lbl : null)
        }

        var mergedLabels = _mergeShortBehaviorInterruptions(labels, _bridgeBehaviorGapFrames(fps))
        var countsById = _countBehaviorBoutRuns(mergedLabels, _minBehaviorBoutFrames(fps))
        for (var j = 0; j < behaviorNames.length; j++)
            countsByName[behaviorNames[j]] = countsById[j] || 0
        return countsByName
    }

    function _minBehaviorBoutFrames(fps) {
        var safeFps = fps > 0 ? fps : 30.0
        return Math.max(1, Math.ceil(minBoutDurationSec * safeFps))
    }

    function _bridgeBehaviorGapFrames(fps) {
        var safeFps = fps > 0 ? fps : 30.0
        return Math.max(1, Math.ceil(maxBoutBridgeGapSec * safeFps))
    }

    function _mergeShortBehaviorInterruptions(labels, maxGapFrames) {
        if (!labels || labels.length < 3) return labels || []
        var out = labels.slice()
        var segments = []
        var cur = out[0]
        var start = 0

        for (var i = 1; i < out.length; i++) {
            if (out[i] !== cur) {
                segments.push({ label: cur, start: start, end: i - 1 })
                cur = out[i]
                start = i
            }
        }
        segments.push({ label: cur, start: start, end: out.length - 1 })

        for (var s = 1; s < segments.length - 1; s++) {
            var prev = segments[s - 1]
            var gap = segments[s]
            var next = segments[s + 1]
            var gapFrames = gap.end - gap.start + 1
            if (prev.label !== null && prev.label !== undefined
                    && prev.label === next.label
                    && gap.label !== prev.label
                    && gapFrames <= maxGapFrames) {
                for (var f = gap.start; f <= gap.end; f++)
                    out[f] = prev.label
            }
        }
        return out
    }

    function _countBehaviorBoutRuns(labels, minFrames) {
        var counts = ({})
        var current = null
        var frames = 0

        function flush() {
            if (current !== null && frames >= minFrames)
                counts[current] = (counts[current] || 0) + 1
        }

        for (var i = 0; i < labels.length; i++) {
            var lbl = labels[i]
            if (lbl === null || lbl === undefined || lbl === "") {
                flush()
                current = null
                frames = 0
                continue
            }
            if (lbl !== current) {
                flush()
                current = lbl
                frames = 1
            } else {
                frames++
            }
        }
        flush()
        return counts
    }

    // Log
    ListModel { id: logModel }

    function localizeBackendInfo(message) {
        if ((message.indexOf("Carregando") >= 0 || message.indexOf("Loading") >= 0) && message.toLowerCase().indexOf("pose") >= 0)
            return LanguageManager.tr3("Carregando modelos de pose...", "Loading pose models...", "Cargando modelos de pose...")
        if (message.indexOf("Modo GPU") >= 0 || message.indexOf("GPU Mode") >= 0) {
            var msgGpu = message
            msgGpu = msgGpu.replace("Modo GPU", LanguageManager.tr3("Modo GPU", "GPU Mode", "Modo GPU"))
            msgGpu = msgGpu.replace("GPU Mode", LanguageManager.tr3("Modo GPU", "GPU Mode", "Modo GPU"))
            msgGpu = msgGpu.replace("ativo", LanguageManager.tr3("ativo", "active", "activo"))
            msgGpu = msgGpu.replace("active", LanguageManager.tr3("ativo", "active", "activo"))
            return msgGpu
        }
        if (message.indexOf("Modo CPU") >= 0 || message.indexOf("CPU Mode") >= 0) {
            var msgCpu = message
            msgCpu = msgCpu.replace("Modo CPU", LanguageManager.tr3("Modo CPU", "CPU Mode", "Modo CPU"))
            msgCpu = msgCpu.replace("CPU Mode", LanguageManager.tr3("Modo CPU", "CPU Mode", "Modo CPU"))
            msgCpu = msgCpu.replace("não disponível", LanguageManager.tr3("nao disponível", "not available", "no disponible"))
            msgCpu = msgCpu.replace("not available", LanguageManager.tr3("nao disponível", "not available", "no disponible"))
            return msgCpu
        }
        return message
    }

    function relocalizeLogLines() {
        for (var i = 0; i < logModel.count; i++) {
            var row = logModel.get(i)
            if (!row || !row.msg) continue
            logModel.setProperty(i, "msg", localizeBackendInfo(row.msg))
        }
    }

    Connections {
        target: LanguageManager
        function onCurrentLanguageChanged() {
            recordingRoot.relocalizeLogLines()
        }
    }

    // ── Inference Controller (nativo — ONNX + QVideoProbe para captura de frames) ──
    InferenceController { id: inference }

    // Display player (native QML)
    // Qt 6: MediaPlayer.videoOutput points to VideoOutput (direction reversed vs Qt 5)
    MediaPlayer {
        id: displayPlayer
        videoOutput: framePreviewMaster
        
        onMediaStatusChanged: {
            if (mediaStatus === MediaPlayer.EndOfMedia && recordingRoot.isOffline && recordingRoot.isAnalyzing) {
                Qt.callLater(function() {
                    recordingRoot.stopSession()
                    recordingRoot._guardedSessionEnded()
                })
            }
        }

        onPlaybackStateChanged: {
            if (playbackState === MediaPlayer.StoppedState && mediaStatus === MediaPlayer.EndOfMedia
                    && recordingRoot.isOffline && recordingRoot.isAnalyzing) {
                Qt.callLater(function() {
                    recordingRoot.stopSession()
                    recordingRoot._guardedSessionEnded()
                })
            }
        }
    }

    // Qt 6: Connections uses 'function onSignal(params)' syntax to access parameters
    Connections {
        target: inference
        function onDimsReceived(width, height) {
            recordingRoot.videoWidth  = width
            recordingRoot.videoHeight = height
            logModel.append({ msg: LanguageManager.tr3("Info: Resolucao: ", "Info: Resolution: ", "Info: Resolucion: ") + width + "x" + height, isErr: false })
            logView.positionViewAtEnd()
        }
        function onFpsReceived(fps) {
            recordingRoot.dlcFps = fps
            var nowMs = Date.now()
            if (recordingRoot.isOffline || nowMs - recordingRoot._lastFpsLogTimestampMs >= 5000) {
                recordingRoot._lastFpsLogTimestampMs = nowMs
                logModel.append({ msg: "FPS: " + fps.toFixed(2), isErr: false })
                logView.positionViewAtEnd()
            }
        }
        function onInfoReceived(message) {
            logModel.append({ msg: localizeBackendInfo(message), isErr: false })
            logView.positionViewAtEnd()
            // Capture camera name emitted by startLiveAnalysis
            if (!recordingRoot.isOffline && message.indexOf("📹") >= 0)
                recordingRoot.liveCameraName = message.replace("📹 Câmera: ", "").replace("📹 Camera: ", "")
            if (message.indexOf("Live recording file: ") === 0)
                recordingRoot.liveRecordedVideoPath = message.substring("Live recording file: ".length)
        }
        function onReadyReceived() {
            recordingRoot._dlcReady = true
            logModel.append({ msg: LanguageManager.tr3("Inference engine ready - tracking active", "Inference engine ready - tracking active", "Motor de inferencia listo - tracking activo"), isErr: false })
            logView.positionViewAtEnd()
        }
        function onTrackReceived(campo, x, y, p) {
            // Count live frames for diagnostics
            if (!recordingRoot.isOffline && campo === 0) {
                recordingRoot.liveFrameCount++
                var nowMs = Date.now()
                if (recordingRoot._lastFpsTimestampMs <= 0) {
                    recordingRoot._lastFpsTimestampMs = nowMs
                    recordingRoot._lastFpsFrameCount = recordingRoot.liveFrameCount
                } else {
                    var dt = nowMs - recordingRoot._lastFpsTimestampMs
                    if (dt >= 1000) {
                        var df = recordingRoot.liveFrameCount - recordingRoot._lastFpsFrameCount
                        if (df >= 0) recordingRoot.dlcFps = (df * 1000.0) / dt
                        recordingRoot._lastFpsTimestampMs = nowMs
                        recordingRoot._lastFpsFrameCount = recordingRoot.liveFrameCount
                    }
                }
            }
            if (recordingRoot.fieldFinished[campo]) return
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
            if (recordingRoot.fieldFinished[campo]) return
            if (recordingRoot.videoWidth <= 0 || recordingRoot.videoHeight <= 0) return
            var bx = recordingRoot.bodyNormX.slice()
            var by = recordingRoot.bodyNormY.slice()
            var bl = recordingRoot.bodyLikelihood.slice()
            bx[campo] = x / recordingRoot.videoWidth
            by[campo] = y / recordingRoot.videoHeight
            bl[campo] = p

            // For CC and similar: body tracking can also start the timer
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
            if (recordingRoot.fieldFinished[campo]) return
            var bs = recordingRoot.currentBehaviorString.slice()
            if (labelId === -1) {
                bs[campo] = "---"
            } else {
                bs[campo] = recordingRoot.behaviorNames[labelId] || ("Id " + labelId)
            }
            recordingRoot.currentBehaviorString = bs
            
            // Increment count if it's a new occurrence (transitioning from a different behavior)
            if (labelId !== -1 && labelId !== recordingRoot._lastBehaviorId[campo]) {
                var counts = recordingRoot.behaviorCounts[campo] || {}
                var key = recordingRoot.behaviorNames[labelId] || ("Id " + labelId)
                counts[key] = (counts[key] || 0) + 1
                
                var bc = recordingRoot.behaviorCounts.slice()
                bc[campo] = counts
                recordingRoot.behaviorCounts = bc
            }
            
            var lbi = recordingRoot._lastBehaviorId.slice()
            lbi[campo] = labelId
            recordingRoot._lastBehaviorId = lbi
        }
        function onAnalyzingChanged() {
            if (!inference.isAnalyzing && recordingRoot.isAnalyzing) {
                var wasManual = recordingRoot._manualStopRequested
                displayPlayer.stop()
                recordingRoot.isAnalyzing = false
                recordingRoot._manualStopRequested = false
            logModel.append({ msg: LanguageManager.tr3("Analise encerrada.", "Analysis ended.", "Analisis finalizado."), isErr: false })
            logView.positionViewAtEnd()
                // Natural end of video (C++ closed it on its own): show popup
                if (!wasManual && recordingRoot.isOffline) {
                    Qt.callLater(recordingRoot._guardedSessionEnded)
                }
            }
        }
        function onErrorOccurred(errorMsg) {
            console.error("[LiveRecording] InferenceController error:", errorMsg)
            displayPlayer.stop()
            logModel.append({ msg: LanguageManager.tr3("Error: ", "Error: ", "Error: ") + errorMsg, isErr: true })
            logView.positionViewAtEnd()
            recordingRoot.isAnalyzing = false
        }
    }

    // Session timer (1 s) — each field decrements independently
    // In offline mode, timer scales with playbackRate (1s real = 4s video at 4x).
    // In live mode, uses 1:1 (video is real-time).
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
                        var rateField = recordingRoot.isOffline ? recordingRoot.playbackRate : 1.0
                        for (var zf = 0; zf < 2; zf++) {
                            var ziField = i * 2 + zf
                            if (recordingRoot._inZone[ziField]) {
                                var durField = (Date.now() - recordingRoot._entryTime[ziField]) / 1000.0 * rateField
                                if (durField > 0.1) {
                                    var eb = recordingRoot.explorationBouts.slice()
                                    var ebz = eb[ziField] ? eb[ziField].slice() : []
                                    ebz.push(parseFloat(durField.toFixed(1)))
                                    eb[ziField] = ebz
                                    recordingRoot.explorationBouts = eb
                                }
                                recordingRoot._inZone[ziField] = false
                            }
                        }
                    logModel.append({ msg: LanguageManager.tr3("Field ", "Field ", "Campo ") + (i+1) + LanguageManager.tr3(" finished!", " finished!", " finalizado!"), isErr: false })
                    logView.positionViewAtEnd()
                    }
                }
            }
            recordingRoot.timesRemaining = newTimes
            // Auto-encerra quando todos os campos ativos concluem
            var allActiveFieldsFinished = true
            for (var af = 0; af < recordingRoot.numCampos; af++) {
                if (!recordingRoot.fieldFinished[af]) {
                    allActiveFieldsFinished = false
                    break
                }
            }
            if (recordingRoot.isAnalyzing && allActiveFieldsFinished) {
                recordingRoot.stopSession()
                recordingRoot._guardedSessionEnded()
            }
        }
    }

    // Exploration timer (100 ms)
    Timer {
        id: explorationTimer
        interval: 100; repeat: true
        running: recordingRoot.isAnalyzing
        onTriggered: {
            recordingRoot.accumulateExploration()
            recordingRoot._explorationTick++
        }
    }

    // Position sync timer (400 ms)
    // The displayPlayer is master. Headless C++ runs at max 2x (ONNX cap).
    // At 4x display / 2x headless, drift grows 2s/s of real video.
    // Timer detects drift > 800ms and resyncs headless to display position.
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

    // Control functions
    function startSession() {
        console.log("[LiveRecording] startSession called. mode=", analysisMode, "cameraId=", cameraId, "videoPath=", videoPath)
        if (isAnalyzing) return
        if (analysisMode !== "ao_vivo" && (videoPath === "" || videoPath === "file:///")) {
            logModel.append({ msg: LanguageManager.tr3("Selecione um video na aba Arena primeiro.", "Select a video in the Arena tab first.", "Seleccione primero un video en la pestana Arena."), isErr: true })
            logView.positionViewAtEnd()
            return
        }
        if (analysisMode === "ao_vivo" && cameraId === "") {
            logModel.append({ msg: LanguageManager.tr3("Selecione uma camera na aba Arena primeiro.", "Select a camera in the Arena tab first.", "Seleccione primero una camara en la pestana Arena."), isErr: true })
            logView.positionViewAtEnd()
            return
        }
        _sessionEndedEmitted = false
        _manualStopRequested = false
        timesRemaining   = [sessionDurationSeconds, sessionDurationSeconds, sessionDurationSeconds]
        timerStarted     = [false, false, false]
        fieldFinished    = [false, false, false]
        // Mark fields beyond numCampos as finished (1 or 2 active fields)
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
        behaviorCounts   = [{}, {}, {}]
        currentBehaviorString = ["", "", ""]
        _lastBehaviorId  = [-1, -1, -1]
        ratNormX         = [-1, -1, -1]
        ratNormY         = [-1, -1, -1]
        ratLikelihood    = [0,  0,  0 ]
        bodyNormX        = [-1, -1, -1]
        bodyNormY        = [-1, -1, -1]
        bodyLikelihood   = [0,  0,  0 ]
        currentVelocity  = [0.0, 0.0, 0.0]
        totalDistance    = [0.0, 0.0, 0.0]
        bodyHistory      = [[], [], []]
        _prevBodyLX      = [-1.0, -1.0, -1.0]
        _prevBodyLY      = [-1.0, -1.0, -1.0]
        _prevBodyTime    = [0, 0, 0]
        perMinuteData    = [[], [], []]
        _lastMinuteSnap  = 0
        _explorationTick = 0
        _dlcReady        = false
        eiLatencySeconds = -1
        liveFrameCount   = 0
        _lastFpsFrameCount = 0
        _lastFpsTimestampMs = 0
        _lastFpsLogTimestampMs = 0
        liveCameraName   = ""
        liveRecordedVideoPath = ""
        logModel.clear()
        logModel.append({ msg: LanguageManager.tr3("Loading native inference engine...", "Loading native inference engine...", "Cargando motor nativo de inferencia..."), isErr: false })
        logView.positionViewAtEnd()
        // EI and 1-field use full frame (720x480); others use quadrants
        inference.setFullFrameMode(aparato === "esquiva_inibitoria" || numCampos === 1)
        if (recordingRoot.isOffline) {
            console.log("[LiveRecording] Starting OFFLINE analysis. playbackRate=", recordingRoot.playbackRate)
            // Offline mode: MediaPlayer plays video file
            var pr = recordingRoot.playbackRate
            displayPlayer.videoOutput = framePreviewMaster
            inference.setLivePreviewOutput(null)
            displayPlayer.source = videoPath
            displayPlayer.playbackRate = pr
            displayPlayer.play()
            inference.startAnalysis(videoPath, "")
            if (pr !== 1.0) inference.setPlaybackRate(Math.min(pr, 2.0))
        } else {
            console.log("[LiveRecording] Starting LIVE analysis via InferenceController. cameraId=", recordingRoot.cameraId)
            // Live mode: USB camera — no MediaPlayer
            // Signal dashboards to stop arena preview (frees camera for inference)
            liveAnalysisStarting()
            displayPlayer.videoOutput = null
            displayPlayer.source = ""
            inference.startLiveAnalysis(recordingRoot.cameraId, "", recordingRoot.saveDirectory, recordingRoot.liveOutputName, 0, 0, 0.0)
            // Conecta o CaptureSession C++ ao VideoOutput para exibir o feed ao vivo
            Qt.callLater(function() {
                console.log("[LiveRecording] setLivePreviewOutput(framePreviewMaster)")
                inference.setLivePreviewOutput(framePreviewMaster)
            })
        }
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
        inference.setLivePreviewOutput(null)
        displayPlayer.videoOutput = framePreviewMaster
        displayPlayer.stop()
        isAnalyzing = false
        logModel.append({ msg: LanguageManager.tr3("Sessão parada.", "Session stopped.", "Sesion detenida."), isErr: false })
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

        var ox    = [fieldGridOffsetX(0), fieldGridOffsetX(1), fieldGridOffsetX(2)]
        var oy    = [fieldGridOffsetY(0), fieldGridOffsetY(1), fieldGridOffsetY(2)]
        var cellW = 0.5
        var cellH = 0.5
        var now   = Date.now()
        var newTimes = explorationTimes.slice()
        var newBouts = []
        for (var i = 0; i < 6; i++) newBouts.push(explorationBouts[i].slice())
        var boutsChanged = false
        // In offline analysis, each 100 ms wall-clock tick covers (100 * rate) ms of video
        var rate = recordingRoot.isOffline ? recordingRoot.playbackRate : 1.0
        for (var campo = 0; campo < 3; campo++) {
            if (recordingRoot.fieldFinished[campo]) continue
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
                        var dur2 = (now - _entryTime[zi2]) / 1000.0 * rate
                        if (dur2 > 0.1) { newBouts[zi2].push(parseFloat(dur2.toFixed(1))); boutsChanged = true }
                        _inZone[zi2] = false
                    }
                }
                continue
            }

            if (recordingRoot.aparato === "campo_aberto") {
                // Open Field logic: Center vs Edge (Body Tracking)
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
                        newTimes[ziCA] += 0.1 * rate
                        if (!_inZone[ziCA]) { _inZone[ziCA] = true; _entryTime[ziCA] = now }
                    } else if (_inZone[ziCA]) {
                        var durCA = (now - _entryTime[ziCA]) / 1000.0 * rate
                        if (durCA > 0.1) { newBouts[ziCA].push(parseFloat(durCA.toFixed(1))); boutsChanged = true }
                        _inZone[ziCA] = false
                    }
                }
            } else if (recordingRoot.aparato === "comportamento_complexo") {
                continue
            } else if (recordingRoot.aparato === "esquiva_inibitoria") {
                // AI logic: quadrilateral zones (Platform, Grid)
                if (!floorPoints || !floorPoints[campo] || floorPoints[campo].length < 8) continue
                var blx = bodyLocalX(campo)
                var bly = bodyLocalY(campo)
                var ptIA = { x: blx, y: bly }
                var fpIA = floorPoints[campo]
                // Platform expanded: outer-left boundary → platform right edge
                // This covers the platform itself + the left wall (yellow area)
                var apIA = (recordingRoot.arenaPoints && recordingRoot.arenaPoints[campo])
                           ? recordingRoot.arenaPoints[campo] : fpIA
                var expandedPlataf = [apIA[0], fpIA[1], fpIA[2], apIA[3]]
                var polyGrade = fpIA.slice(4, 8)
                var inPlataf = isPointInPoly(ptIA, expandedPlataf)
                var inGrade  = isPointInPoly(ptIA, polyGrade)

                var zonesIA = [inPlataf, inGrade]
                for (var zia = 0; zia < 2; zia++) {
                    var ziA = campo * 2 + zia
                    if (zonesIA[zia]) {
                        newTimes[ziA] += 0.1 * rate
                        if (!_inZone[ziA]) {
                            _inZone[ziA] = true
                            _entryTime[ziA] = now
                            // Record latency: elapsed session time at first grade entry
                            if (zia === 1 && recordingRoot.eiLatencySeconds < 0) {
                                recordingRoot.eiLatencySeconds =
                                    recordingRoot.sessionDurationSeconds - recordingRoot.timesRemaining[campo]
                            }
                        }
                    } else if (_inZone[ziA]) {
                        var durIA = (now - _entryTime[ziA]) / 1000.0 * rate
                        if (durIA > 0.1) { newBouts[ziA].push(parseFloat(durIA.toFixed(1))); boutsChanged = true }
                        _inZone[ziA] = false
                    }
                }
            } else {
                // NOR logic: circular zones
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
                        newTimes[zi] += 0.1 * rate
                        if (!_inZone[zi]) { _inZone[zi] = true; _entryTime[zi] = now }
                    } else if (_inZone[zi]) {
                        var dur = (now - _entryTime[zi]) / 1000.0 * rate
                        if (dur > 0.1) { newBouts[zi].push(parseFloat(dur.toFixed(1))); boutsChanged = true }
                        _inZone[zi] = false
                    }
                }
            }
        }
        explorationTimes = newTimes
        if (boutsChanged) explorationBouts = newBouts

        // Velocity and distance from body point
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
            if (recordingRoot.fieldFinished[ci]) {
                newVel[ci] = 0.0
                newPBLX[ci] = -1.0
                newPBLY[ci] = -1.0
                continue
            }
            var blx = bodyLocalX(ci)
            var bly = bodyLocalY(ci)
            var bl  = bodyLikelihood[ci]

            if (blx >= 0 && bl >= 0.5 && recordingRoot.timerStarted[ci]) {
                newHist[ci].push({x: blx, y: bly})
                if (newHist[ci].length > 40) newHist[ci].shift() // Keep last ~4000ms visible
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
                // dt in video time: wall-clock * playbackRate
                var dt   = (now2 - prevT) / 1000.0 * rate

                // Filter impossible jumps (> 10 m/s video = model glitch or GPU skip)
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
        var elapsedSec = sessionDurationSeconds - maxTimer
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

    // Returns current bout seconds for zone zi (or 0 if not in zone)
    // Uses _explorationTick as reactive dependency to update every 100ms
    function currentBoutSec(zi) {
        var _t = recordingRoot._explorationTick
        if (!_inZone[zi]) return 0.0
        var rateDisp = recordingRoot.isOffline ? recordingRoot.playbackRate : 1.0
        return (Date.now() - _entryTime[zi]) / 1000.0 * rateDisp
    }

    // Discrimination index: (T_novel - T_familiar) / (T_novel + T_familiar)
    // OBJ B (zi1, direita) = novo; OBJ A (zi0, esquerda) = familiar
    function discriminationIndex(campo) {
        var tFam   = explorationTimes[campo * 2]
        var tNovo  = explorationTimes[campo * 2 + 1]
        var total  = tFam + tNovo
        if (total < 0.1) return NaN
        return (tNovo - tFam) / total
    }

    // Coordenada local do rat dentro do quadrante/frame (0..1)
    // For EI (fullFrameMode), normX already covers [0,1] the full frame — no *2.
    // For mosaic (NOR/CA/CC), each field is half the frame: apply offset/scale.
    function fieldQuadrant(campo) {
        if (!inference || !inference.activeQuadrantIndices || inference.activeQuadrantIndices.length <= campo) {
            return campo // fallback legacy: 0,1,2
        }
        return Number(inference.activeQuadrantIndices[campo])
    }
    function fieldGridOffsetX(campo) {
        var q = fieldQuadrant(campo)
        return (q % 2) * 0.5
    }
    function fieldGridOffsetY(campo) {
        var q = fieldQuadrant(campo)
        return (q >= 2 ? 1 : 0) * 0.5
    }
    function ratLocalX(campo) {
        var nx = ratNormX[campo]
        if (nx < 0) return -1
        if (recordingRoot.aparato === "esquiva_inibitoria" || recordingRoot.numCampos === 1) return nx
        return (nx - fieldGridOffsetX(campo)) * 2
    }
    function ratLocalY(campo) {
        var ny = ratNormY[campo]
        if (ny < 0) return -1
        if (recordingRoot.aparato === "esquiva_inibitoria" || recordingRoot.numCampos === 1) return ny
        return (ny - fieldGridOffsetY(campo)) * 2
    }
    function bodyLocalX(campo) {
        var bx = bodyNormX[campo]
        if (bx < 0) return -1
        if (recordingRoot.aparato === "esquiva_inibitoria" || recordingRoot.numCampos === 1) return bx
        return (bx - fieldGridOffsetX(campo)) * 2
    }
    function bodyLocalY(campo) {
        var by = bodyNormY[campo]
        if (by < 0) return -1
        if (recordingRoot.aparato === "esquiva_inibitoria" || recordingRoot.numCampos === 1) return by
        return (by - fieldGridOffsetY(campo)) * 2
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

        // Session panel (top)
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

                    // Speed display (offline mode only)
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
                                    // when changing playbackRate while the player is active
                                    displayPlayer.stop()
                                    displayPlayer.playbackRate = rate
                                    displayPlayer.setPosition(pos)
                                    displayPlayer.play()
                                    // Headless capped at 2x: ONNX CPU receives frames at max 2x.
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
                            { label: LanguageManager.tr3("Campo 1", "Field 1", "Campo 1"), pair: recordingRoot.pair1, visible: true },
                            { label: LanguageManager.tr3("Campo 2", "Field 2", "Campo 2"), pair: recordingRoot.pair2, visible: recordingRoot.numCampos >= 2 },
                            { label: LanguageManager.tr3("Campo 3", "Field 3", "Campo 3"), pair: recordingRoot.pair3, visible: recordingRoot.numCampos >= 3 }
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

        // Central area
        RowLayout {
            Layout.fillWidth: true; Layout.fillHeight: true; spacing: 0

            // 2x2 mosaic
            Rectangle {
                Layout.fillWidth: true; Layout.fillHeight: true
                color: "#05050a"

                GridLayout {
                    anchors.fill: parent
                    columns: (recordingRoot.aparato === "esquiva_inibitoria" || recordingRoot.numCampos === 1) ? 1 : 2
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

                                // Video quadrant via ShaderEffectSource
                                ShaderEffectSource {
                                    anchors.fill: parent
                                    sourceItem: framePreviewMaster
                                    sourceRect: {
                                        var _fp = framePreviewMaster
                                        if (!_fp || _fp.width === 0) return Qt.rect(0, 0, 0, 0)

                                        var cr = _fp.contentRect
                                        var cw = cr.width  / 2
                                        var ch = cr.height / 2
                                        var cx = cr.x
                                        var cy = cr.y

                                        // Usa o mapeamento dinâmico: pula quadrantes pretos
                                        var q = campoCell.ci
                                        if (inference
                                                && inference.activeQuadrantIndices
                                                && inference.activeQuadrantIndices.length > campoCell.ci) {
                                            q = Number(inference.activeQuadrantIndices[campoCell.ci])
                                        }
                                        var qx = q % 2
                                        var qy = q >= 2 ? 1 : 0
                                        return Qt.rect(cx + qx * cw, cy + qy * ch, cw, ch)
                                    }
                                    opacity: 0.85
                                }

                                // Overlay para exibir Behavior Badge — apenas no CC (Comportamento Complexo)
                                Rectangle {
                                    id: behaviorBadge
                                    anchors { top: parent.top; left: parent.left; margins: 10 }
                                    visible: (recordingRoot.aparato === "comportamento_complexo" || recordingRoot.ccMode)
                                          && recordingRoot.currentBehaviorString[campoCell.ci] !== ""
                                          && recordingRoot.isAnalyzing
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

                                // Arena overlay (walls + floor + zones)
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
                                        function onFloorPointsChanged()  { arenaCanv.requestPaint() }
                                        function onZonesChanged()        { arenaCanv.requestPaint() }
                                    }
                                    Connections {
                                        target: LanguageManager
                                        function onCurrentLanguageChanged() { arenaCanv.requestPaint() }
                                    }
                                    onPaint: {
                                        var ctx = getContext("2d")
                                        ctx.clearRect(0, 0, width, height)

                                        if (!recordingRoot.arenaPoints || !recordingRoot.floorPoints) {
                                            ctx.fillStyle = "red"
                                            ctx.fillText(LanguageManager.tr3("Sem arena", "No arena", "Sin arena"), 10, 20)
                                            return
                                        }
                                        var ap = recordingRoot.arenaPoints[ci]
                                        var fp = recordingRoot.floorPoints[ci]
                                        if (!ap || !fp) {
                                            ctx.fillStyle = "orange"
                                            ctx.fillText(LanguageManager.tr3("Sem AP/FP", "No AP/FP", "Sin AP/FP"), 10, 20)
                                            return
                                        }
                                        var w = width, h = height
                                        var oTL={x:ap[0].x*w,y:ap[0].y*h}, oTR={x:ap[1].x*w,y:ap[1].y*h}
                                        var oBR={x:ap[2].x*w,y:ap[2].y*h}, oBL={x:ap[3].x*w,y:ap[3].y*h}
                                        var iTL, iTR, iBR, iBL
                                        if (fp.length >= 8) {
                                            // EI-format (8 pts): fp[0..3]=Plataforma, fp[4..7]=Grade
                                            // Inner floor spans Plataforma-TL → Grade-TR/BR → Plataforma-BL
                                            iTL={x:fp[0].x*w,y:fp[0].y*h}
                                            iTR={x:fp[5].x*w,y:fp[5].y*h}
                                            iBR={x:fp[6].x*w,y:fp[6].y*h}
                                            iBL={x:fp[3].x*w,y:fp[3].y*h}
                                        } else {
                                            iTL={x:fp[0].x*w,y:fp[0].y*h}
                                            iTR={x:fp[1].x*w,y:fp[1].y*h}
                                            iBR={x:fp[2].x*w,y:fp[2].y*h}
                                            iBL={x:fp[3].x*w,y:fp[3].y*h}
                                        }
                                        function poly(pts,f,s){
                                            ctx.beginPath(); ctx.moveTo(pts[0].x,pts[0].y)
                                            for(var k=1;k<pts.length;k++) ctx.lineTo(pts[k].x,pts[k].y)
                                            ctx.closePath(); ctx.fillStyle=f; ctx.fill()
                                            ctx.lineWidth=1; ctx.strokeStyle=s; ctx.stroke()
                                        }
                                        function polyPath(pts){
                                            ctx.beginPath()
                                            ctx.moveTo(pts[0].x, pts[0].y)
                                            for (var t = 1; t < pts.length; t++) ctx.lineTo(pts[t].x, pts[t].y)
                                            ctx.closePath()
                                        }
                                        function fieldPatternStyle(fieldIdx){
                                            var p = (recordingRoot.contextPatterns && recordingRoot.contextPatterns.length > fieldIdx)
                                                    ? String(recordingRoot.contextPatterns[fieldIdx] || "")
                                                    : ""
                                            if (p !== "") return p
                                            if (fieldIdx % 3 === 0) return "horizontal"
                                            if (fieldIdx % 3 === 1) return "vertical"
                                            return "dots"
                                        }
                                        function hatchWall(pts, style, strokeColor, spacing){
                                            var minX = pts[0].x, maxX = pts[0].x
                                            var minY = pts[0].y, maxY = pts[0].y
                                            for (var m = 1; m < pts.length; m++) {
                                                minX = Math.min(minX, pts[m].x); maxX = Math.max(maxX, pts[m].x)
                                                minY = Math.min(minY, pts[m].y); maxY = Math.max(maxY, pts[m].y)
                                            }
                                            ctx.save()
                                            polyPath(pts)
                                            ctx.clip()
                                            ctx.strokeStyle = strokeColor
                                            ctx.lineWidth = 1
                                            if (style === "horizontal") {
                                                for (var y = minY - spacing; y <= maxY + spacing; y += spacing) {
                                                    ctx.beginPath()
                                                    ctx.moveTo(minX - 12, y)
                                                    ctx.lineTo(maxX + 12, y)
                                                    ctx.stroke()
                                                }
                                            } else if (style === "vertical") {
                                                for (var x = minX - spacing; x <= maxX + spacing; x += spacing) {
                                                    ctx.beginPath()
                                                    ctx.moveTo(x, minY - 12)
                                                    ctx.lineTo(x, maxY + 12)
                                                    ctx.stroke()
                                                }
                                            } else if (style === "dots") {
                                                for (var dy = minY; dy <= maxY; dy += spacing) {
                                                    for (var dx = minX; dx <= maxX; dx += spacing) {
                                                        ctx.beginPath()
                                                        ctx.arc(dx, dy, 1.2, 0, Math.PI * 2)
                                                        ctx.fillStyle = strokeColor
                                                        ctx.fill()
                                                    }
                                                }
                                            } else if (style === "triangles") {
                                                var tri = 5
                                                for (var ty = minY; ty <= maxY; ty += spacing) {
                                                    for (var tx = minX; tx <= maxX; tx += spacing) {
                                                        ctx.beginPath()
                                                        ctx.moveTo(tx, ty - tri * 0.8)
                                                        ctx.lineTo(tx - tri * 0.8, ty + tri * 0.8)
                                                        ctx.lineTo(tx + tri * 0.8, ty + tri * 0.8)
                                                        ctx.closePath()
                                                        ctx.fillStyle = strokeColor
                                                        ctx.fill()
                                                    }
                                                }
                                            } else if (style === "squares") {
                                                for (var sy = minY; sy <= maxY; sy += spacing) {
                                                    for (var sx = minX; sx <= maxX; sx += spacing) {
                                                        ctx.fillStyle = strokeColor
                                                        ctx.fillRect(sx - 1.6, sy - 1.6, 3.2, 3.2)
                                                    }
                                                }
                                            } else {
                                                var spanY = (maxY - minY) + 24
                                                for (var d = minX - spanY; d <= maxX + spanY; d += spacing) {
                                                    ctx.beginPath()
                                                    ctx.moveTo(d, minY - 12)
                                                    ctx.lineTo(d + spanY, maxY + 12)
                                                    ctx.stroke()
                                                }
                                            }
                                            ctx.restore()
                                        }

                                        if (recordingRoot.aparato === "esquiva_inibitoria") {
                                            // EI: desenha 4 paredes + Plataforma (0-3) + Grade (4-7)
                                            // 'inner' arena spans both polygons combined:
                                            //   canto TL  = fp[0] (Plataforma TL)
                                            //   canto TR  = fp[5] (Grade TR — extremo direito)
                                            //   canto BR  = fp[6] (Grade BR)
                                            //   canto BL  = fp[3] (Plataforma BL)
                                            if (fp.length >= 8) {
                                                var pTL = {x:fp[0].x*w, y:fp[0].y*h}
                                                var pBL = {x:fp[3].x*w, y:fp[3].y*h}
                                                var gTR = {x:fp[5].x*w, y:fp[5].y*h}
                                                var gBR = {x:fp[6].x*w, y:fp[6].y*h}
                                                // Parede superior (vermelho)
                                                poly([oTL,oTR,gTR,pTL], "rgba(255,0,0,0.10)",   "rgba(255,0,0,0.40)")
                                                // Parede inferior (rosa)
                                                poly([pBL,gBR,oBR,oBL], "rgba(255,0,255,0.10)", "rgba(255,0,255,0.40)")
                                                // Parede esquerda (laranja)
                                                poly([oTL,pTL,pBL,oBL], "rgba(255,170,0,0.10)", "rgba(255,170,0,0.40)")
                                                // Parede direita (marrom escuro)
                                                poly([oTR,oBR,gBR,gTR], "rgba(62,39,35,0.15)",  "rgba(62,39,35,0.50)")
                                                // Plataforma (fp 0-3, verde)
                                                var platPts = []
                                                for(var k1=0;k1<4;k1++) platPts.push({x:fp[k1].x*w, y:fp[k1].y*h})
                                                poly(platPts, "rgba(0,255,0,0.08)", "rgba(0,255,0,0.50)")
                                                // Grade (fp 4-7, ciano)
                                                var gradePts = []
                                                for(var k2=4;k2<8;k2++) gradePts.push({x:fp[k2].x*w, y:fp[k2].y*h})
                                                poly(gradePts, "rgba(0,204,255,0.08)", "rgba(0,204,255,0.50)")
                                            }
                                            return  // Specific walls already drawn — skip generic drawing
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

                                        if (recordingRoot.context === "Contextual" && ci < recordingRoot.numCampos) {
                                            var wallTop = [oTL,oTR,iTR,iTL]
                                            var wallBottom = [iBL,iBR,oBR,oBL]
                                            var wallLeft = [oTL,iTL,iBL,oBL]
                                            var wallRight = [iTR,oTR,oBR,iBR]
                                            var patt = fieldPatternStyle(ci)
                                            var color = ci % 3 === 0 ? "rgba(255,120,120,0.45)"
                                                      : ci % 3 === 1 ? "rgba(120,200,255,0.45)"
                                                                     : "rgba(180,255,120,0.42)"
                                            hatchWall(wallTop, patt, color, 8)
                                            hatchWall(wallBottom, patt, color, 8)
                                            hatchWall(wallLeft, patt, color, 8)
                                            hatchWall(wallRight, patt, color, 8)
                                        }

                                        ctx.strokeStyle="rgba(255,170,0,0.8)"; ctx.lineWidth=2
                                        ctx.beginPath(); ctx.moveTo(oTL.x,oTL.y)
                                        ctx.lineTo(oTR.x,oTR.y); ctx.lineTo(oBR.x,oTR.y); ctx.lineTo(oBL.x,oTR.y)
                                        ctx.closePath(); ctx.stroke()

                                        // Labels (apenas no CA, nunca no RO)
                                        if (recordingRoot.aparato === "campo_aberto") {
                                            ctx.font = "bold 9px Inter"; ctx.fillStyle = "rgba(255,255,255,0.7)"
                                            ctx.fillText(LanguageManager.tr3("Centro", "Center", "Centro"), (iTL.x+iBR.x)/2 - 12, (iTL.y+iBR.y)/2)
                                        }
                                    }
                                }

                                // Zone A (maroon) - only when zones are configured
                                Rectangle {
                                    id: zoneA
                                    visible: recordingRoot.aparato === "nor"
                                             ? (recordingRoot.zones && recordingRoot.zones.length > campoCell.ci*2)
                                             : (recordingRoot.aparato === "comportamento_complexo"
                                                && recordingRoot.zones && recordingRoot.zones.length > campoCell.ci*2)
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
                                // Zone B (blue) - only when zones are configured and pair has 2 objects
                                Rectangle {
                                    id: zoneB
                                    visible: recordingRoot.aparato === "nor"
                                             ? (recordingRoot.zones && recordingRoot.zones.length > campoCell.ci*2+1
                                                && recordingRoot.pairForCampo(campoCell.ci).length > 1)
                                             : (recordingRoot.aparato === "comportamento_complexo"
                                                && recordingRoot.zones && recordingRoot.zones.length > campoCell.ci*2+1)
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
                                        text: recordingRoot.fieldFinished[campoCell.ci] ? LanguageManager.tr3("✓ Fim", "✓ End", "✓ Fin")
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

                    // Bottom-right cell: master VideoOutput + state overlay
                    Rectangle {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        color: "#08080f"; border.color: "#1a1a2e"; border.width: 1

                        // Qt 6: VideoOutput has no 'source'. MediaPlayer references
                        // o VideoOutput via sua propriedade "videoOutput".
                        // Offline: fed by MediaPlayer. Live: fed by C++ CaptureSession via setLivePreviewOutput.
                        VideoOutput {
                            id: framePreviewMaster
                            anchors.fill: parent
                            fillMode: VideoOutput.PreserveAspectFit
                            opacity: 0.45
                        }

                        // Analysis state overlay (offline mode, no video loaded)
                        Column {
                            anchors.centerIn: parent
                            spacing: 6
                            visible: !recordingRoot.isAnalyzing && recordingRoot.isOffline

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "🎬"; font.pixelSize: 20; opacity: 0.3
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: recordingRoot.videoPath !== "" ? LanguageManager.tr3("Video pronto\npressione Iniciar", "Video ready\npress Start", "Video listo\npresione Iniciar") : LanguageManager.tr3("Carregue um video\nna aba Arena", "Load a video\nin the Arena tab", "Cargue un video\nen la pestana Arena")
                                color: "#444466"; font.pixelSize: 9
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }

                        // Live mode overlay — camera ready to start
                        Column {
                            anchors.centerIn: parent
                            spacing: 6
                            visible: !recordingRoot.isAnalyzing && !recordingRoot.isOffline

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "📹"; font.pixelSize: 20; opacity: 0.6
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: recordingRoot.cameraId !== ""
                                      ? LanguageManager.tr3("Camera selecionada\npressione Iniciar", "Camera selected\npress Start", "Camara seleccionada\npresione Iniciar")
                                      : LanguageManager.tr3("Selecione uma camera\nna aba Arena", "Select a camera\nin the Arena tab", "Seleccione una camara\nen la pestana Arena")
                                color: "#446644"; font.pixelSize: 9
                                horizontalAlignment: Text.AlignHCenter
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                visible: recordingRoot.cameraId !== ""
                                text: recordingRoot.cameraId
                                color: "#5aaa70"; font.pixelSize: 8
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                width: 120
                            }
                        }

                        // Live diagnostics panel (visible during live analysis)
                        Rectangle {
                            anchors { top: parent.top; left: parent.left; margins: 5 }
                            visible: !recordingRoot.isOffline && recordingRoot.isAnalyzing
                            color: "#cc000010"; radius: 5
                            border.color: "#5aaa70"; border.width: 1
                            width: liveDiagCol.implicitWidth + 14
                            height: liveDiagCol.implicitHeight + 10

                            Column {
                                id: liveDiagCol
                                anchors.centerIn: parent
                                spacing: 3

                                Text {
                                    text: "📹 AO VIVO"
                                    color: "#5aff80"; font.pixelSize: 9; font.weight: Font.Bold
                                }
                                Text {
                                    visible: recordingRoot.liveCameraName !== ""
                                    text: recordingRoot.liveCameraName
                                    color: "#aaffcc"; font.pixelSize: 8
                                    elide: Text.ElideRight; width: 120
                                }
                                Text {
                                    text: "FPS: " + recordingRoot.dlcFps.toFixed(0)
                                    color: "#aaffcc"; font.pixelSize: 8
                                }
                                Text {
                                    text: "Frames: " + recordingRoot.liveFrameCount
                                    color: "#aaffcc"; font.pixelSize: 8
                                }
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
                                text: recordingRoot._dlcReady ? LanguageManager.tr3("Live analysis...", "Live analysis...", "Analisis en vivo...") : LanguageManager.tr3("Starting DLC engine...", "Starting DLC engine...", "Iniciando motor DLC...")
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

                    // Start / Stop buttons + Load Video
                    RowLayout {
                        Layout.fillWidth: true; spacing: 6

                        // 'Load Video' button — visible only when stopped
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
                                text: recordingRoot.isOffline
                                      ? LanguageManager.tr3("Carregar Video", "Load Video", "Cargar Video")
                                      : LanguageManager.tr3("Configurar Ao Vivo", "Setup Live", "Configurar En Vivo")
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
                                text: recordingRoot.showTrail ? LanguageManager.tr3("Rastro ON", "Trail ON", "Rastro ON") : LanguageManager.tr3("Rastro OFF", "Trail OFF", "Rastro OFF")
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
                                text: recordingRoot.isAnalyzing ? LanguageManager.tr3("Parar", "Stop", "Detener") : LanguageManager.tr3("Iniciar", "Start", "Iniciar")
                                color: "white"; font.pixelSize: 12; font.bold: true
                            }
                            MouseArea {
                                id: startBtnMa; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (recordingRoot.isAnalyzing) {
                                        recordingRoot._manualStopRequested = true
                                        recordingRoot.stopSession()
                                    } else {
                                        recordingRoot.startSession()
                                    }
                                }
                            }
                        }
                    }

                    // ── LOG ────────────────────────────────────────────────────
                    Text {
                        text: LanguageManager.tr3("LOG", "LOG", "LOG")
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

                    // Object exploration panel
                    Rectangle {
                        Layout.fillWidth: true; height: 1; color: ThemeManager.border
                        Behavior on color { ColorAnimation { duration: 200 } }
                    }

                    Text {
                        text: recordingRoot.aparato === "campo_aberto"
                              ? LanguageManager.tr3("EXPLORACAO DE CAMPO", "FIELD EXPLORATION", "EXPLORACION DE CAMPO")
                              : (recordingRoot.aparato === "comportamento_complexo" || recordingRoot.aparato === "esquiva_inibitoria")
                                ? LanguageManager.tr3("EXPLORACAO GERAL", "GENERAL EXPLORATION", "EXPLORACION GENERAL")
                                : LanguageManager.tr3("EXPLORACAO DE OBJETOS", "OBJECT EXPLORATION", "EXPLORACION DE OBJETOS")
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

                                        // ── Field header ─────────────────────
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text {
                                                text: LanguageManager.tr3("CAMPO ", "FIELD ", "CAMPO ") + (campoCard.ci + 1)
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
                                                    text: recordingRoot.fieldFinished[campoCard.ci] ? LanguageManager.tr3("Concluido", "Done", "Completado") : recordingRoot.timerStarted[campoCard.ci] ? recordingRoot.formatTime(recordingRoot.timesRemaining[campoCard.ci]) : LanguageManager.tr3("Aguardando rato", "Waiting for mouse", "Esperando raton")
                                                    color: recordingRoot.fieldFinished[campoCard.ci] ? ThemeManager.successLight
                                                         : recordingRoot.timerStarted[campoCard.ci]
                                                           ? (recordingRoot.timesRemaining[campoCard.ci] <= 30 ? ThemeManager.error : ThemeManager.textPrimary)
                                                           : ThemeManager.textTertiary
                                                    font.pixelSize: 9; font.bold: true; font.family: "Consolas"
                                                }
                                            }
                                        }

                                        Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border }

                                        // ── APPARATUS-SPECIFIC METRICS (NOR vs CA) ──
                                        ColumnLayout {
                                            Layout.fillWidth: true; spacing: 5
                                            visible: (recordingRoot.aparato === "nor" || recordingRoot.aparato === "")

                                            // OBJ A (familiar)
                                            RowLayout {
                                                Layout.fillWidth: true; spacing: 5
                                                Rectangle { width: 8; height: 8; radius: 4; color: "#ab3d4c" }
                                                Text { text: "OBJ " + campoCard.la; color: "#cc5566"; font.pixelSize: 10; font.weight: Font.Bold }
                                                Item { Layout.fillWidth: true }
                                                Text { text: recordingRoot.explorationTimes[campoCard.zi0].toFixed(1) + " s"; color: ThemeManager.textPrimary; font.pixelSize: 11; font.family: "Consolas" }
                                            }
                                            // Bout live OBJ A
                                            Rectangle {
                                                Layout.fillWidth: true; height: 18; radius: 4; visible: recordingRoot._inZone[campoCard.zi0]
                                                color: ThemeManager.accentDim; border.color: ThemeManager.accent; border.width: 1
                                                Text {
                                                    anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 6 }
                                                    text: LanguageManager.tr3("▶ agora: ", "▶ now: ", "▶ ahora: ") + recordingRoot.currentBoutSec(campoCard.zi0).toFixed(1) + " s"
                                                    color: ThemeManager.accent; font.pixelSize: 9; font.bold: true
                                                }
                                            }

                                            // OBJ B (novo) — oculto em modo 1 objeto
                                            Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border; visible: pairStr.length > 1 }

                                            RowLayout {
                                                Layout.fillWidth: true; spacing: 5
                                                visible: pairStr.length > 1
                                                Rectangle { width: 8; height: 8; radius: 4; color: "#4466aa" }
                                                Text { text: "OBJ " + campoCard.lb; color: "#5577bb"; font.pixelSize: 10; font.weight: Font.Bold }
                                                Item { Layout.fillWidth: true }
                                                Text { text: recordingRoot.explorationTimes[campoCard.zi1].toFixed(1) + " s"; color: ThemeManager.textPrimary; font.pixelSize: 11; font.family: "Consolas" }
                                            }
                                            // Bout live OBJ B
                                            Rectangle {
                                                Layout.fillWidth: true; height: 18; radius: 4
                                                visible: pairStr.length > 1 && recordingRoot._inZone[campoCard.zi1]
                                                color: ThemeManager.surfaceDim; border.color: ThemeManager.borderLight; border.width: 1
                                                Text {
                                                    anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 6 }
                                                    text: LanguageManager.tr3("▶ agora: ", "▶ now: ", "▶ ahora: ") + recordingRoot.currentBoutSec(campoCard.zi1).toFixed(1) + " s"
                                                    color: "#6688cc"; font.pixelSize: 9; font.bold: true
                                                }
                                            }

                                            // Discrimination index (DI) — hidden in single-object mode
                                            Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border; visible: pairStr.length > 1 }

                                            Rectangle {
                                                id: diBox
                                                Layout.fillWidth: true; height: 26; radius: 4
                                                visible: pairStr.length > 1
                                                property real dv: recordingRoot.discriminationIndex(campoCard.ci)
                                                color: ThemeManager.surfaceDim; border.color: isNaN(diBox.dv) ? ThemeManager.border : (diBox.dv > 0.199 ? ThemeManager.success : ThemeManager.accent); border.width: 1
                                                RowLayout {
                                                    anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                                                    Text { text: "DI"; color: ThemeManager.textTertiary; font.pixelSize: 9; font.weight: Font.Bold }
                                                    Item { Layout.fillWidth: true }
                                                    Text {
                                                        text: isNaN(diBox.dv) ? "—" : (diBox.dv >= 0 ? "+" : "") + diBox.dv.toFixed(3)
                                                        color: isNaN(diBox.dv) ? "#444466" : (diBox.dv > 0.199 ? "#5aaa70" : "#ff5566")
                                                        font.pixelSize: 12; font.bold: true; font.family: "Consolas"
                                                    }
                                                    Text {
                                                        text: isNaN(diBox.dv) ? "" : (diBox.dv > 0.199
                                                            ? LanguageManager.tr3("↑ novo", "↑ new", "↑ nuevo")
                                                            : diBox.dv < 0
                                                                ? LanguageManager.tr3("↓ fam", "↓ fam", "↓ fam")
                                                                : "=")
                                                        color: isNaN(diBox.dv) ? "#444466" : (diBox.dv > 0.199 ? "#5aaa70" : "#ff5566")
                                                        font.pixelSize: 9
                                                    }
                                                }
                                            }
                                        }

                                        // ── INHIBITORY AVOIDANCE METRICS (EI) ──────
                                        ColumnLayout {
                                            Layout.fillWidth: true; spacing: 5
                                            visible: recordingRoot.aparato === "esquiva_inibitoria" && !recordingRoot.ccMode

                                            // Plataforma
                                            RowLayout {
                                                Layout.fillWidth: true; spacing: 5
                                                Rectangle { width: 8; height: 8; radius: 4; color: "#00ff00" }
                                                Text { text: LanguageManager.tr3("Plataforma", "Platform", "Plataforma"); color: "#00aa00"; font.pixelSize: 10; font.weight: Font.Bold }
                                                Item { Layout.fillWidth: true }
                                                Text { text: recordingRoot.explorationTimes[campoCard.zi0].toFixed(1) + " s"; color: ThemeManager.textPrimary; font.pixelSize: 11; font.family: "Consolas" }
                                            }
                                            // Grade
                                            RowLayout {
                                                Layout.fillWidth: true; spacing: 5
                                                Rectangle { width: 8; height: 8; radius: 4; color: "#00ccff" }
                                                Text { text: LanguageManager.tr3("Grade", "Grid", "Rejilla"); color: "#0088cc"; font.pixelSize: 10; font.weight: Font.Bold }
                                                Item { Layout.fillWidth: true }
                                                Text { text: recordingRoot.explorationTimes[campoCard.zi1].toFixed(1) + " s"; color: ThemeManager.textPrimary; font.pixelSize: 11; font.family: "Consolas" }
                                            }

                                            Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                Text { text: LanguageManager.tr3("Descidas a grade:", "Grid descents:", "Descensos a la rejilla:"); color: ThemeManager.textSecondary; font.pixelSize: 11 }
                                                Item { Layout.fillWidth: true }
                                                Text { text: recordingRoot.explorationBouts[campoCard.zi1].length; color: ThemeManager.textPrimary; font.pixelSize: 11; font.weight: Font.Bold }
                                            }
                                        }

                                        // ── OPEN FIELD METRICS (CA) ─────────────────
                                        ColumnLayout {
                                            Layout.fillWidth: true; spacing: 5
                                            visible: recordingRoot.aparato === "campo_aberto"

                                            // Visitas Centro
                                            RowLayout {
                                                Layout.fillWidth: true
                                                Text { text: LanguageManager.tr3("Visitas ao centro:", "Center visits:", "Visitas al centro:"); color: ThemeManager.textSecondary; font.pixelSize: 11 }
                                                Item { Layout.fillWidth: true }
                                                Text { text: recordingRoot.explorationBouts[campoCard.zi0].length; color: ThemeManager.textPrimary; font.pixelSize: 11; font.weight: Font.Bold }
                                            }

                                            Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border }

                                            // Tempo Centro
                                            RowLayout {
                                                Layout.fillWidth: true
                                                Text { text: LanguageManager.tr3("Tempo no centro:", "Time in center:", "Tiempo en el centro:"); color: ThemeManager.textSecondary; font.pixelSize: 11 }
                                                Item { Layout.fillWidth: true }
                                                Text { text: recordingRoot.explorationTimes[campoCard.zi0].toFixed(1) + " s"; color: ThemeManager.accent; font.pixelSize: 11; font.weight: Font.Bold }
                                            }

                                            // Tempo Borda
                                            RowLayout {
                                                Layout.fillWidth: true
                                                Text { text: LanguageManager.tr3("Tempo nas bordas:", "Time at borders:", "Tiempo en bordes:"); color: ThemeManager.textSecondary; font.pixelSize: 11 }
                                                Item { Layout.fillWidth: true }
                                                Text { text: recordingRoot.explorationTimes[campoCard.zi1].toFixed(1) + " s"; color: ThemeManager.accent; font.pixelSize: 11; font.weight: Font.Bold }
                                            }
                                        }

                                        Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border }

                                        // ── Velocity and Distance (body) ──────
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

                                            // Accumulated distance
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
