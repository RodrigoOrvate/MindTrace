// qml/cc/CCDashboard.qml
// Dashboard Comportamento Complexo: sidebar + Arena + Gravação + Classificação + Dados.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtMultimedia
import "../core"
import "../core/Theme"
import "../shared"
import "../nor"
import "../ei"
import MindTrace.Backend 1.0
import MindTrace.Analysis 1.0
import MindTrace.Tracking 1.0

Item {
    id: root

    property string context:   ""
    property string arenaId:   ""
    property int    numCampos: 3
    property bool   searchMode: false
    property int    currentTabIndex: 0
    property string initialExperimentName: ""

    signal backRequested()

    Component.onCompleted: {
        if (root.searchMode) {
            ExperimentManager.loadAllContexts("comportamento_complexo")
        }
        if (initialExperimentName !== "") {
            experimentList.selectExperimentByName(initialExperimentName)
            innerTabs.currentIndex = 0
        }
    }

    property string pendingDeleteName: ""

    function _isCurrentSelectionStillInModel() {
        if (!workArea.selectedName || !workArea.selectedPath)
            return false
        var m = ExperimentManager.model
        if (!m) return false
        for (var i = 0; i < m.count; ++i) {
            var idx = m.index(i, 0)
            var name = m.data(idx, Qt.UserRole + 1)
            var path = m.data(idx, Qt.UserRole + 2)
            if (name === workArea.selectedName && path === workArea.selectedPath)
                return true
        }
        return false
    }

    function _resetSelectionState() {
        try {
            if (liveRecordingTab && liveRecordingTab.isAnalyzing)
                liveRecordingTab.stopSession()
        } catch (e) {}
        try {
            if (tabArenaSetup && tabArenaSetup.stopCameraPreview)
                tabArenaSetup.stopCameraPreview()
        } catch (e2) {}
        try {
            if (eiArenaSetupCC && eiArenaSetupCC.stopCameraPreview)
                eiArenaSetupCC.stopCameraPreview()
        } catch (e3) {}

        workArea.selectedName = ""
        workArea.selectedPath = ""
        workArea.analysisMode = "offline"
        workArea.saveDirectory = ""
        workArea.cameraId = ""
        workStack.currentIndex = 0
        innerTabs.currentIndex = 0
        experimentList.currentIndex = -1
    }

    function _syncSelectionWithModel() {
        if (!workArea.selectedName && !workArea.selectedPath)
            return
        if (!_isCurrentSelectionStillInModel())
            _resetSelectionState()
    }

    // â"€â"€ B-SOiD â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€
    property bool   bsoidRunning:   false
    property int    bsoidProgress:  0
    property var    bsoidGroups:    []   // lista de {clusterId, frameCount, percentage, ...}
    property var    bsoidGroupNames: []  // nomes personalizados dos clusters (editáveis)
    property string bsoidError:     ""
    property bool   bsoidDone:      false
    property double bsoidFps:       30.0
    property string bsoidVideoPath: ""
    property int    bsoidCampo:     0    // campo selecionado para análise (0=C1, 1=C2, 2=C3)
    property int    _boutCampo:    0    // campo selecionado para revisão de bouts
    property bool   showBoutReview: false

    // â”€â”€ Estatísticas e alinhamento Rules vs B-SOiD â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    property var    behaviorStats:      []   // [{name, bouts, color}]
    property var    bsoidBehaviorStats: []   // [{name, bouts, color}]
    property var    bsoidMappingRaw:    []   // getFrameMapping()
    property var    bsoidRulesSmooth:   []
    property var    bsoidClustersSmooth:[]
    property var    bsoidClusterToRule: ({}) // { clusterId: ruleId }
    property double bsoidAgreementPct:  0.0
    property int    bsoidBestLagFrames: 0
    property int    bsoidComparedFrames: 0
    property var    bsoidConfusionGroups: [] // [{clusterId, shortLabel, label, color}]
    property var    bsoidConfusionRows:   [] // [{ruleId, ruleName, total, bestPct, cells:[...]}]
    property double bsoidConfusionMacroTop1: 0.0
    property double bsoidConfusionWeightedTop1: 0.0
    property var    bsoidClusterTopRule: ({}) // { clusterId: ruleId } from aligned matrix
    property var    bsoidClusterTopPct:  ({}) // { clusterId: pct(0..100) } from aligned matrix
    property string bsoidDecisionMode: "rules_only" // rules_only | hybrid_confident | bsoid_exploratory
    property double bsoidTrustedThresholdPct: 50.0
    property int    bsoidNumClusters: 10
    property double bsoidMinVisibleClusterPct: 1.0
    property var    bsoidModelClusterIds: []
    property bool   bsoidNamesTypedByUser: false
    property var    bsoidEditedGroups: []
    property var    bsoidFinalLabelStats: [] // [{name, frames, pct, bouts, trusted}]
    property bool   bsoidStep1LoadedPrev: false
    property bool   bsoidStep2DataReady: false
    property bool   bsoidStep3Embedded: false
    property bool   bsoidStep4Clustered: false
    property bool   bsoidStep5LearnedViewed: false
    property bool   bsoidStep6ModelCreated: false
    property bool   bsoidStep7SnippetsDone: false
    property bool   bsoidStep8Predicted: false
    property bool   bsoidFinalComparisonUnlocked: false
    property int    bsoidWorkflowCursor: 1
    property int    bsoidFlowStage: 1 // 1=analyze, 2=filter clusters, 3=snippets+label, 4=compare, 5=save labels+stats

    function ruleColor(ruleId) {
        var colors = ["#8b5cf6","#f97316","#eab308","#3b82f6","#10b981"]
        return (ruleId >= 0 && ruleId < colors.length) ? colors[ruleId] : ThemeManager.border
    }

    function behaviorName(ruleId) {
        var names = ["Walking", "Sniffing", "Grooming", "Resting", "Rearing"]
        return (ruleId >= 0 && ruleId < names.length) ? names[ruleId] : "Unknown"
    }

    function decisionModeLabel(mode) {
        if (mode === "rules_only")
            return LanguageManager.tr3("Somente Rules", "Rules only", "Solo Rules")
        if (mode === "hybrid_confident")
            return LanguageManager.tr3("Rules + B-SOiD confiavel", "Rules + trusted B-SOiD", "Rules + B-SOiD confiable")
        return LanguageManager.tr3("B-SOiD exploratorio", "Exploratory B-SOiD", "B-SOiD exploratorio")
    }

    function resetBsoidWorkflow() {
        bsoidStep1LoadedPrev = false
        bsoidStep2DataReady = false
        bsoidStep3Embedded = false
        bsoidStep4Clustered = false
        bsoidStep5LearnedViewed = false
        bsoidStep6ModelCreated = false
        bsoidStep7SnippetsDone = false
        bsoidStep8Predicted = false
        bsoidFinalComparisonUnlocked = false
        bsoidWorkflowCursor = 1
        bsoidFlowStage = 1
    }

    function bsoidWorkflowActionText() {
        switch (bsoidWorkflowCursor) {
        case 1: return LanguageManager.tr3("Continuar: carregar iteracao anterior (opcional)", "Continue: load previous iteration (optional)", "Continuar: cargar iteracion previa (opcional)")
        case 2: return LanguageManager.tr3("Continuar: preparar dados", "Continue: prepare data", "Continuar: preparar datos")
        case 3: return LanguageManager.tr3("Continuar: extrair e embeber features", "Continue: extract and embed features", "Continuar: extraer y embeber features")
        case 4: return LanguageManager.tr3("Continuar: confirmar clusters", "Continue: confirm clusters", "Continuar: confirmar clusters")
        case 5: return LanguageManager.tr3("Continuar: revisar aprendizado", "Continue: review learned patterns", "Continuar: revisar aprendizaje")
        case 6: return LanguageManager.tr3("Continuar: salvar rotulos + estatistica", "Continue: save labels + stats", "Continuar: guardar etiquetas + estadistica")
        case 7: return LanguageManager.tr3("Continuar: gerar snippets", "Continue: generate snippets", "Continuar: generar snippets")
        case 8: return LanguageManager.tr3("Continuar: aplicar modelo", "Continue: apply model", "Continuar: aplicar modelo")
        default: return LanguageManager.tr3("Finalizar: liberar comparacao", "Finish: unlock comparison", "Finalizar: liberar comparacion")
        }
    }

    function bsoidWorkflowAdvance() {
        switch (bsoidWorkflowCursor) {
        case 1:
            root.bsoidStep1LoadedPrev = root.loadNamedGroupLabels() || true
            root.bsoidWorkflowCursor = 2
            break
        case 2: {
            var okPrep = false
            if (workArea.selectedPath !== "")
                okPrep = liveRecordingTab.saveBehaviorCache(workArea.selectedPath, root.bsoidCampo)
            root.bsoidStep2DataReady = !!okPrep
            if (okPrep) root.bsoidWorkflowCursor = 3
            else errorToast.show(LanguageManager.tr3("Falha ao preparar dados B-SOiD.", "Failed to prepare B-SOiD data.", "Error al preparar datos B-SOiD."))
            break
        }
        case 3:
            if (!root.bsoidRunning) root.startBsoidAnalysis()
            break
        case 4:
            if (root.bsoidDone) {
                root.bsoidStep4Clustered = true
                root.bsoidWorkflowCursor = 5
            }
            break
        case 5:
            root.bsoidStep5LearnedViewed = true
            root.bsoidWorkflowCursor = 6
            break
        case 6:
            root.saveNamedGroupReport()
            if (root.bsoidStep6ModelCreated) root.bsoidWorkflowCursor = 7
            break
        case 7:
            if (root.bsoidDone && !root.snippetsRunning) {
                var outDir = workArea.selectedPath + "/bsoid_snippets"
                root.snippetsRunning  = true
                root.snippetsComplete = false
                root.snippetsError    = ""
                root.snippetsProgress = 0
                bsoidAnalyzer.extractSnippets(root.bsoidVideoPath, outDir, root.bsoidFps, 3)
            }
            break
        case 8:
            root.bsoidStep8Predicted = true
            root.bsoidWorkflowCursor = 9
            break
        case 9:
            root.tryUnlockFinalComparison()
            break
        }
    }

    function canonicalBehaviorName(rawName) {
        var s = String(rawName || "").toLowerCase().trim()
        if (s === "") return ""
        s = s.replace(/[\s_\-]+/g, "")
        s = s.replace(/á|à|â|ã|ä/g, "a")
        s = s.replace(/é|è|ê|ë/g, "e")
        s = s.replace(/í|ì|î|ï/g, "i")
        s = s.replace(/ó|ò|ô|õ|ö/g, "o")
        s = s.replace(/ú|ù|û|ü/g, "u")
        s = s.replace(/ç/g, "c")

        if (s === "walking" || s === "locomotion" || s === "locomocao" || s === "andar")
            return "Walking"
        if (s === "sniffing" || s === "objectzones" || s === "zonadeobjetos" || s === "zonasdeobjetos")
            return "Sniffing"
        if (s === "grooming" || s === "autogrooming")
            return "Grooming"
        if (s === "resting" || s === "rest" || s === "idle" || s === "freeze" || s === "freezing")
            return "Resting"
        if (s === "rearing")
            return "Rearing"
        return ""
    }

    function bsoidColorByClusterId(clusterId) {
        if (clusterId >= 0 && bsoidColors && bsoidColors.length > 0)
            return bsoidColors[clusterId % bsoidColors.length]
        return ThemeManager.border
    }

    function namedGroupLabelByClusterId(clusterId) {
        for (var i = 0; i < bsoidGroups.length; i++) {
            var g = bsoidGroups[i]
            if (g.clusterId === clusterId) {
                var typed = (bsoidGroupNames && bsoidGroupNames.length > i) ? String(bsoidGroupNames[i] || "").trim() : ""
                return typed !== "" ? typed : ("Group " + (clusterId + 1))
            }
        }
        return "Group " + (clusterId + 1)
    }

    function bsoidDisplayGroups() {
        var out = []
        for (var i = 0; i < bsoidGroups.length; i++) {
            var g = bsoidGroups[i]
            if (!g) continue
            if ((g.percentage || 0) >= bsoidMinVisibleClusterPct) {
                var copy = {}
                for (var k in g) copy[k] = g[k]
                copy._idx = i
                out.push(copy)
            }
        }
        return out
    }

    function bsoidEffectiveGroups() {
        if (!bsoidModelClusterIds || bsoidModelClusterIds.length === 0)
            return bsoidDisplayGroups()
        var keep = ({})
        for (var i = 0; i < bsoidModelClusterIds.length; i++)
            keep[bsoidModelClusterIds[i]] = true
        var out = []
        for (var j = 0; j < bsoidGroups.length; j++) {
            var g = bsoidGroups[j]
            if (!g || !keep[g.clusterId]) continue
            var copy = {}
            for (var k in g) copy[k] = g[k]
            copy._idx = j
            out.push(copy)
        }
        return out
    }

    function createModelFromVisibleClusters() {
        var vis = bsoidDisplayGroups()
        if (!vis || vis.length === 0) {
            errorToast.show(LanguageManager.tr3("Nenhum cluster visivel para fixar nesta analise.", "No visible clusters to freeze in this analysis.", "No hay clusters visibles para fijar en este analisis."))
            return false
        }
        var ids = []
        for (var i = 0; i < vis.length; i++)
            ids.push(vis[i].clusterId)
        bsoidModelClusterIds = ids
        bsoidFlowStage = 3
        return true
    }

    function hasAllVisibleClustersNamed() {
        var groups = bsoidEffectiveGroups()
        if (!groups || groups.length === 0)
            return false
        for (var i = 0; i < groups.length; i++) {
            var idx = groups[i]._idx
            var typed = (bsoidGroupNames && bsoidGroupNames.length > idx) ? String(bsoidGroupNames[idx] || "").trim() : ""
            if (typed === "")
                return false
        }
        return true
    }

    function hasAllVisibleClustersEditedByUser() {
        var groups = bsoidEffectiveGroups()
        if (!groups || groups.length === 0)
            return false
        if (!bsoidEditedGroups || bsoidEditedGroups.length === 0)
            return false
        for (var i = 0; i < groups.length; i++) {
            var idx = groups[i]._idx
            if (!bsoidEditedGroups[idx])
                return false
        }
        return true
    }

    function canUnlockFinalComparison() {
        return hasAllVisibleClustersNamed() && hasAllVisibleClustersEditedByUser()
    }

    function unlockBlockingMessage() {
        if (!hasAllVisibleClustersNamed())
            return LanguageManager.tr3("Preencha o nome de todos os clusters visiveis.", "Fill in names for all visible clusters.", "Complete el nombre de todos los clusters visibles.")
        if (!hasAllVisibleClustersEditedByUser())
            return LanguageManager.tr3("Edite manualmente cada cluster visivel nesta analise antes da comparacao final.", "Manually edit each visible cluster in this analysis before final comparison.", "Edite manualmente cada cluster visible en este analisis antes de la comparacion final.")
        return ""
    }

    function tryUnlockFinalComparison() {
        if (!canUnlockFinalComparison()) {
            errorToast.show(unlockBlockingMessage())
            return false
        }
        bsoidFinalComparisonUnlocked = true
        return true
    }

    function isClusterTrusted(clusterId) {
        var p = (bsoidClusterTopPct[clusterId] !== undefined) ? bsoidClusterTopPct[clusterId] : 0.0
        return p >= bsoidTrustedThresholdPct
    }

    function finalLabelByMode(clusterId, ruleId) {
        var rName = behaviorName(ruleId)
        var bName = namedGroupLabelByClusterId(clusterId)
        if (bsoidDecisionMode === "rules_only")
            return rName
        if (bsoidDecisionMode === "hybrid_confident")
            return isClusterTrusted(clusterId) ? bName : rName
        return bName
    }

    function rebuildFinalLabelStats() {
        if (!bsoidDone || !bsoidMappingRaw || bsoidMappingRaw.length === 0) {
            bsoidFinalLabelStats = []
            return
        }
        var cut = Math.max(0, bsoidBestLagFrames || 0)
        var maxLen = Math.max(0, bsoidMappingRaw.length - cut)
        if (maxLen <= 0) {
            bsoidFinalLabelStats = []
            return
        }

        var byName = ({})
        var prev = ""
        for (var i = 0; i < maxLen; i++) {
            var b = bsoidMappingRaw[i]
            var r = bsoidMappingRaw[i + cut]
            if (!b || !r) continue
            var nm = finalLabelByMode(b.clusterId, r.ruleLabel)
            if (!byName[nm]) {
                byName[nm] = {
                    frames: 0,
                    bouts: 0,
                    trustedFrames: 0
                }
            }
            byName[nm].frames++
            if (nm !== prev) byName[nm].bouts++
            if (isClusterTrusted(b.clusterId)) byName[nm].trustedFrames++
            prev = nm
        }

        var out = []
        for (var k in byName) {
            out.push({
                name: k,
                frames: byName[k].frames,
                pct: 100.0 * byName[k].frames / maxLen,
                bouts: byName[k].bouts,
                trusted: byName[k].frames > 0 ? (100.0 * byName[k].trustedFrames / byName[k].frames) : 0.0
            })
        }
        out.sort(function(a,b){ return b.frames - a.frames })
        bsoidFinalLabelStats = out
    }

    function rebuildAgreementMatrixView() {
        var displayed = bsoidEffectiveGroups()
        if (!bsoidDone || !displayed || displayed.length === 0 || !bsoidMappingRaw || bsoidMappingRaw.length === 0) {
            bsoidConfusionGroups = []
            bsoidConfusionRows = []
            bsoidConfusionMacroTop1 = 0.0
            bsoidConfusionWeightedTop1 = 0.0
            bsoidClusterTopRule = ({})
            bsoidClusterTopPct = ({})
            rebuildFinalLabelStats()
            return
        }

        var groups = []
        var groupIndexByCluster = ({})
        for (var gi = 0; gi < displayed.length; gi++) {
            var cid = displayed[gi].clusterId
            var lbl = namedGroupLabelByClusterId(cid)
            groups.push({
                clusterId: cid,
                shortLabel: "G" + (cid + 1),
                label: lbl,
                color: bsoidColorByClusterId(cid)
            })
            groupIndexByCluster[cid] = gi
        }

        var cut = Math.max(0, bsoidBestLagFrames || 0)
        var maxLen = Math.max(0, bsoidMappingRaw.length - cut)
        var matrix = []
        var rowTotals = [0, 0, 0, 0, 0]
        var colTotals = []
        for (var r = 0; r < 5; r++) {
            var row = []
            for (var c = 0; c < groups.length; c++) row.push(0)
            matrix.push(row)
        }
        for (var c0 = 0; c0 < groups.length; c0++) colTotals.push(0)

        for (var i2 = 0; i2 < maxLen; i2++) {
            var b = bsoidMappingRaw[i2]
            var rr = bsoidMappingRaw[i2 + cut]
            var ruleId = rr.ruleLabel
            var clusterId = b.clusterId
            if (ruleId < 0 || ruleId > 4) continue
            if (clusterId < 0 || groupIndexByCluster[clusterId] === undefined) continue
            var col = groupIndexByCluster[clusterId]
            matrix[ruleId][col] += 1
            rowTotals[ruleId] += 1
            colTotals[col] += 1
        }

        var rows = []
        var macroAcc = 0.0
        var macroN = 0
        var weightedNum = 0.0
        var weightedDen = 0.0
        for (var r2 = 0; r2 < 5; r2++) {
            var cells = []
            var bestPct = 0.0
            for (var c2 = 0; c2 < groups.length; c2++) {
                var cnt = matrix[r2][c2]
                var pct = rowTotals[r2] > 0 ? (100.0 * cnt / rowTotals[r2]) : 0.0
                if (pct > bestPct) bestPct = pct
                cells.push({
                    clusterId: groups[c2].clusterId,
                    count: cnt,
                    pct: pct
                })
            }
            if (rowTotals[r2] > 0) {
                macroAcc += bestPct
                macroN++
                weightedNum += bestPct * rowTotals[r2]
                weightedDen += rowTotals[r2]
            }
            rows.push({
                ruleId: r2,
                ruleName: behaviorName(r2),
                total: rowTotals[r2],
                bestPct: bestPct,
                cells: cells
            })
        }

        bsoidConfusionGroups = groups
        bsoidConfusionRows = rows
        bsoidConfusionMacroTop1 = macroN > 0 ? (macroAcc / macroN) : 0.0
        bsoidConfusionWeightedTop1 = weightedDen > 0 ? (weightedNum / weightedDen) : 0.0

        // Cluster purity with the same aligned window used by matrix/timeline.
        var topRule = ({})
        var topPct = ({})
        for (var c3 = 0; c3 < groups.length; c3++) {
            var bestRule = -1
            var bestCnt = -1
            for (var r3 = 0; r3 < 5; r3++) {
                if (matrix[r3][c3] > bestCnt) {
                    bestCnt = matrix[r3][c3]
                    bestRule = r3
                }
            }
            var cid3 = groups[c3].clusterId
            topRule[cid3] = bestRule
            topPct[cid3] = colTotals[c3] > 0 ? (100.0 * bestCnt / colTotals[c3]) : 0.0
        }
        bsoidClusterTopRule = topRule
        bsoidClusterTopPct = topPct
        rebuildFinalLabelStats()
        bsoidBehaviorStats = computeBsoidBehaviorStats()
    }

    onBsoidDecisionModeChanged: rebuildFinalLabelStats()
    onBsoidTrustedThresholdPctChanged: rebuildFinalLabelStats()
    onBsoidModelClusterIdsChanged: {
        if (bsoidDone) {
            rebuildAgreementMatrixView()
            Qt.callLater(function() { renderAlignedTimelines() })
        }
    }
    onBsoidMinVisibleClusterPctChanged: {
        if (bsoidDone) {
            rebuildAgreementMatrixView()
            Qt.callLater(function() { renderAlignedTimelines() })
        }
    }

    function clusterColor(ruleId, clusterId) {
        // Keep semantic family per rule, but vary shade by cluster for visual separation.
        var palettes = [
            ["#8b5cf6", "#a78bfa", "#7c3aed"], // Walking
            ["#f97316", "#fb923c", "#ea580c"], // Sniffing
            ["#eab308", "#facc15", "#ca8a04"], // Grooming
            ["#3b82f6", "#60a5fa", "#2563eb"], // Resting
            ["#10b981", "#34d399", "#059669"]  // Rearing
        ]
        if (ruleId < 0 || ruleId >= palettes.length)
            return root.bsoidColors[clusterId % root.bsoidColors.length] || ThemeManager.accent
        var shades = palettes[ruleId]
        return shades[clusterId % shades.length]
    }

    function computeBehaviorStats(fps) {
        var mapping = bsoidMappingRaw
        var bouts   = [0,0,0,0,0]
        var prev    = -1
        for (var i = 0; i < mapping.length; i++) {
            var lbl = mapping[i].ruleLabel
            if (lbl >= 0 && lbl < 5) {
                if (lbl !== prev) bouts[lbl]++
            }
            prev = (lbl >= 0 && lbl < 5) ? lbl : prev
        }
        var result = []
        for (var j = 0; j < 5; j++) {
            result.push({ name: behaviorName(j), bouts: bouts[j], color: ruleColor(j) })
        }
        return result
    }

    function computeBsoidBehaviorStats() {
        if (!bsoidMappingRaw || bsoidMappingRaw.length === 0)
            return []
        var keep = ({})
        var eff = bsoidEffectiveGroups()
        for (var i = 0; i < eff.length; i++)
            keep[eff[i].clusterId] = true

        var bouts = [0,0,0,0,0]
        var prev = -1
        var cut = Math.max(0, bsoidBestLagFrames || 0)
        var maxLen = Math.max(0, bsoidMappingRaw.length - cut)
        for (var j = 0; j < maxLen; j++) {
            var b = bsoidMappingRaw[j]
            if (!b || b.clusterId === undefined || !keep[b.clusterId]) {
                prev = -1
                continue
            }
            var rid = (bsoidClusterTopRule[b.clusterId] !== undefined) ? bsoidClusterTopRule[b.clusterId] : -1
            if (rid >= 0 && rid < 5) {
                if (rid !== prev) bouts[rid]++
                prev = rid
            } else {
                prev = -1
            }
        }

        var out = []
        for (var k = 0; k < 5; k++)
            out.push({ name: behaviorName(k), bouts: bouts[k], color: ruleColor(k) })
        return out
    }

    function _maxBouts(stats) {
        var m = 1
        for (var i = 0; i < stats.length; i++) {
            var v = Number(stats[i].bouts || 0)
            if (v > m) m = v
        }
        return m
    }

    function _reportBasePath() {
        var base = workArea.selectedPath || ""
        if (base === "") return ""
        var ts = new Date().toISOString().replace(/[:.]/g, "-")
        return base + "/results_report_c" + (root.bsoidCampo + 1) + "_" + ts
    }

    function exportResultsPdfReport() {
        if (!root.bsoidFinalComparisonUnlocked) {
            errorToast.show(LanguageManager.tr3("Gere a comparacao antes de exportar o PDF.", "Generate comparison before exporting PDF.", "Genere la comparacion antes de exportar el PDF."))
            return
        }
        var base = _reportBasePath()
        if (base === "") {
            errorToast.show(LanguageManager.tr3("Nenhum experimento selecionado.", "No experiment selected.", "Ningun experimento seleccionado."))
            return
        }

        var imgBars = base + "_bars.png"
        var imgTimeline = base + "_timeline.png"
        var imgMatrix = base + "_matrix.png"
        var pdfPath = base + "_results_report.pdf"

        barsReportCard.grabToImage(function(r1) {
            if (!r1 || !r1.saveToFile(imgBars)) {
                errorToast.show(LanguageManager.tr3("Falha ao capturar grafico de colunas.", "Failed to capture bar chart.", "Error al capturar grafico de columnas."))
                return
            }
            timelineReportCard.grabToImage(function(r2) {
                if (!r2 || !r2.saveToFile(imgTimeline)) {
                    errorToast.show(LanguageManager.tr3("Falha ao capturar timeline.", "Failed to capture timeline.", "Error al capturar timeline."))
                    return
                }
                matrixReportCard.grabToImage(function(r3) {
                    if (!r3 || !r3.saveToFile(imgMatrix)) {
                        errorToast.show(LanguageManager.tr3("Falha ao capturar matriz de concordancia.", "Failed to capture agreement matrix.", "Error al capturar matriz de concordancia."))
                        return
                    }
                    var ok = liveRecordingTab.savePdfReport(
                                pdfPath,
                                [imgBars, imgTimeline, imgMatrix],
                                "MindTrace - B-SOiD Results Report",
                                [
                                    LanguageManager.tr3("Grafico de colunas: Rules vs B-SOiD (bouts).", "Bar chart: Rules vs B-SOiD (bouts).", "Grafico de columnas: Rules vs B-SOiD (bouts)."),
                                    LanguageManager.tr3("Timeline alinhada: Rules vs B-SOiD.", "Aligned timeline: Rules vs B-SOiD.", "Timeline alineada: Rules vs B-SOiD."),
                                    LanguageManager.tr3("Matriz de concordancia Rules x B-SOiD.", "Agreement matrix Rules x B-SOiD.", "Matriz de concordancia Rules x B-SOiD.")
                                ])
                    if (ok)
                        successToast.show(LanguageManager.tr3("PDF salvo em: ", "PDF saved at: ", "PDF guardado en: ") + pdfPath)
                    else
                        errorToast.show(LanguageManager.tr3("Falha ao salvar PDF de resultados.", "Failed to save results PDF.", "Error al guardar PDF de resultados."))
                })
            })
        })
    }

    function smoothLabels(labels, radius) {
        var out = []
        if (!labels || labels.length === 0) return out
        var r = Math.max(0, radius || 0)
        for (var i = 0; i < labels.length; i++) {
            var counts = ({})
            var bestLabel = labels[i]
            var bestCount = -1
            for (var j = i - r; j <= i + r; j++) {
                if (j < 0 || j >= labels.length) continue
                var lbl = labels[j]
                if (lbl < 0) continue
                counts[lbl] = (counts[lbl] || 0) + 1
            }
            for (var k in counts) {
                if (counts[k] > bestCount) {
                    bestCount = counts[k]
                    bestLabel = parseInt(k)
                }
            }
            out.push(bestLabel)
        }
        return out
    }

    function buildLagAndMapping(fps) {
        var mapping = bsoidMappingRaw
        if (!mapping || mapping.length === 0) return null

        var rawRules = []
        var rawClusters = []
        for (var i = 0; i < mapping.length; i++) {
            rawRules.push(mapping[i].ruleLabel)
            rawClusters.push(mapping[i].clusterId)
        }

        var rules = smoothLabels(rawRules, 0)
        var clusters = smoothLabels(rawClusters, 0)
        var safeFps = fps > 0 ? fps : 30.0
        var lagMax = Math.max(1, Math.round(safeFps * 2.0)) // up to 2s cut on Rules
        // 1) Estimate how many initial Rules frames to cut to align with B-SOiD.
        var fixedMap = ({})
        for (var g = 0; g < bsoidGroups.length; g++) {
            var grp = bsoidGroups[g]
            if (grp && grp.clusterId !== undefined && grp.dominantRule !== undefined
                    && grp.dominantRule >= 0 && grp.dominantRule <= 4) {
                fixedMap[grp.clusterId] = grp.dominantRule
            }
        }

        function scoreRuleCut(cut, mapObj) {
            var valid = 0
            var hit = 0
            for (var t = 0; t < clusters.length; t++) {
                var trIdx = t + cut
                if (trIdx < 0 || trIdx >= rules.length) continue
                var tr = rules[trIdx]
                var tc = clusters[t]
                if (tr < 0 || tr > 4 || tc < 0) continue
                var pred = mapObj[tc]
                if (pred === undefined) continue
                valid++
                if (pred === tr) hit++
            }
            return { agreement: valid > 0 ? (hit / valid) : 0.0, valid: valid }
        }

        var bestCut = 0
        var bestScore = { agreement: -1, valid: 0 }
        for (var cut = 0; cut <= lagMax; cut++) {
            var sc = scoreRuleCut(cut, fixedMap)
            var replace = false
            if (sc.agreement > bestScore.agreement) replace = true
            else if (Math.abs(sc.agreement - bestScore.agreement) < 1e-9 && cut < bestCut) replace = true
            if (replace) { bestCut = cut; bestScore = sc }
        }

        // 2) Refine cluster->rule map once at best cut.
        var votes = ({}) // cluster -> [r0..r4]
        for (var p = 0; p < clusters.length; p++) {
            var q = p + bestCut
            if (q < 0 || q >= rules.length) continue
            var rlbl = rules[q]
            var clbl = clusters[p]
            if (rlbl < 0 || rlbl > 4 || clbl < 0) continue
            if (!votes[clbl]) votes[clbl] = [0,0,0,0,0]
            votes[clbl][rlbl] += 1
        }
        var refinedMap = ({})
        for (var ck in votes) {
            var arr = votes[ck]
            var br = 0
            var bc = arr[0]
            for (var rr = 1; rr < 5; rr++) {
                if (arr[rr] > bc) { bc = arr[rr]; br = rr }
            }
            refinedMap[ck] = br
        }

        // Ensure all visible clusters have a mapping fallback.
        for (var g2 = 0; g2 < bsoidGroups.length; g2++) {
            var grp2 = bsoidGroups[g2]
            if (grp2 && refinedMap[grp2.clusterId] === undefined) {
                if (grp2.dominantRule !== undefined && grp2.dominantRule >= 0 && grp2.dominantRule <= 4)
                    refinedMap[grp2.clusterId] = grp2.dominantRule
            }
        }

        var best = { lag: bestCut, agreement: bestScore.agreement, valid: bestScore.valid, map: refinedMap }

        return {
            rules: rules,
            clusters: clusters,
            lag: best.lag,
            map: best.map,
            agreementPct: best.agreement * 100.0,
            compared: best.valid
        }
    }

    function renderAlignedTimelines() {
        if (!ruleTimeline || !clusterTimeline) return
        ruleTimeline.clear()
        clusterTimeline.clear()

        var displayed = bsoidEffectiveGroups()
        var visibleClusterSet = ({})
        for (var rid = 0; rid < 5; rid++) ruleTimeline.setLabelColor(rid, ruleColor(rid))
        for (var gi = 0; gi < displayed.length; gi++) {
            var cid = displayed[gi].clusterId
            visibleClusterSet[cid] = true
            clusterTimeline.setLabelColor(cid, bsoidColors[cid % bsoidColors.length])
        }

        var safeFps = bsoidFps > 0 ? bsoidFps : 30.0
        var mapping = bsoidMappingRaw
        var cut = Math.max(0, bsoidBestLagFrames || 0)
        var maxLen = Math.max(0, mapping.length - cut)

        // Align visual start by first VALID sample on each row (not first raw sample).
        var firstRulesFrame = -1
        var firstBsoidFrame = -1
        for (var k = 0; k < maxLen; k++) {
            var br = mapping[k]
            var rr = mapping[k + cut]
            if (firstBsoidFrame < 0 && br.clusterId >= 0 && visibleClusterSet[br.clusterId]) firstBsoidFrame = br.frameIdx
            if (firstRulesFrame < 0 && rr.ruleLabel >= 0 && rr.ruleLabel <= 4) firstRulesFrame = rr.frameIdx
            if (firstBsoidFrame >= 0 && firstRulesFrame >= 0) break
        }
        if (firstBsoidFrame < 0) firstBsoidFrame = 0
        if (firstRulesFrame < 0) firstRulesFrame = 0

        for (var i = 0; i < maxLen; i++) {
            var b = mapping[i]
            var r = mapping[i + cut]

            var tB = (b.frameIdx - firstBsoidFrame) / safeFps
            var tR = (r.frameIdx - firstRulesFrame) / safeFps

            if (r.ruleLabel >= 0 && r.ruleLabel <= 4) ruleTimeline.appendPoint(tR, r.ruleLabel)
            if (b.clusterId >= 0 && visibleClusterSet[b.clusterId]) clusterTimeline.appendPoint(tB, b.clusterId)
        }
    }

    // â"€â"€ Snippets â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€
    property bool   snippetsRunning:  false
    property int    snippetsProgress: 0
    property bool   snippetsComplete: false
    property string snippetsOutDir:   ""
    property string snippetsError:    ""

    BSoidAnalyzer {
        id: bsoidAnalyzer
        onProgress: function(pct) { root.bsoidProgress = pct }
        onAnalysisReady: function(groups) {
            root.bsoidRunning  = false
            root.bsoidDone     = true
            root.bsoidGroups   = groups
            root.bsoidError    = ""
            root.bsoidProgress = 100
            if (root.bsoidFlowStage < 2) root.bsoidFlowStage = 2
            root.bsoidStep3Embedded = true
            root.bsoidStep4Clustered = false
            if (root.bsoidWorkflowCursor <= 3) root.bsoidWorkflowCursor = 4
            root.bsoidModelClusterIds = []
            root.bsoidMappingRaw = bsoidAnalyzer.getFrameMapping()
            // Inicializa nomes em branco para cada cluster
            var names = []
            for (var n = 0; n < groups.length; n++) names.push("")
            root.bsoidGroupNames = names
            var edited = []
            for (var e = 0; e < groups.length; e++) edited.push(false)
            root.bsoidEditedGroups = edited
            root.bsoidStep1LoadedPrev = root.loadNamedGroupLabels()
            root.bsoidNamesTypedByUser = false

            var cmp = root.buildLagAndMapping(root.bsoidFps)
            if (cmp) {
                root.bsoidRulesSmooth    = cmp.rules
                root.bsoidClustersSmooth = cmp.clusters
                root.bsoidClusterToRule  = cmp.map
                root.bsoidBestLagFrames  = cmp.lag
                root.bsoidAgreementPct   = cmp.agreementPct
                root.bsoidComparedFrames = cmp.compared
            } else {
                root.bsoidRulesSmooth    = []
                root.bsoidClustersSmooth = []
                root.bsoidClusterToRule  = ({})
                root.bsoidBestLagFrames  = 0
                root.bsoidAgreementPct   = 0.0
                root.bsoidComparedFrames = 0
            }

            // Computa estatísticas por comportamento
            root.behaviorStats = root.computeBehaviorStats(root.bsoidFps)
            root.bsoidBehaviorStats = []
            root.rebuildAgreementMatrixView()
            // Renderiza timelines com alinhamento temporal + remapeamento cluster→regra
            Qt.callLater(function() {
                root.renderAlignedTimelines()
            })
        }
        onErrorOccurred: function(msg) {
            root.bsoidRunning = false
            root.bsoidError   = msg
        }
        onSnippetsProgress: function(pct) { root.snippetsProgress = pct }
        onSnippetsDone: function(ok, outDir, msg) {
            root.snippetsRunning  = false
            root.snippetsComplete = ok
            root.snippetsOutDir   = ok ? outDir : ""
            root.snippetsError    = ok ? "" : msg
            if (ok) {
                root.bsoidStep7SnippetsDone = true
                if (root.bsoidFlowStage < 4) root.bsoidFlowStage = 4
                if (root.bsoidWorkflowCursor <= 7) root.bsoidWorkflowCursor = 8
            }
        }
    }

    // Cores dos clusters B-SOiD â€" família vermelhos/amarelos/violetas,
    // deliberadamente distintas das regras nativas:
    // Walking=#10b981(verde), Sniffing=#3b82f6(azul), Grooming=#ec4899(rosa),
    // Resting=#6b7280(cinza), Rearing=#f97316(laranja)
    readonly property var bsoidColors: [
        "#ef4444",  // vermelho      G1
        "#eab308",  // amarelo       G2
        "#8b5cf6",  // violeta       G3
        "#d946ef",  // fúcsia        G4
        "#6366f1",  // índigo        G5
        "#dc2626",  // vermelho esc  G6
        "#ca8a04",  // ouro          G7
        "#7c3aed",  // violeta esc   G8
        "#c026d3",  // magenta       G9
        "#be123c",  // carmim        G10
        "#a21caf",  // magenta esc   G11
        "#4f46e5"   // índigo esc    G12
    ]

    function bsoidRuleName(ruleId) {
        return behaviorName(ruleId)
    }

    function startBsoidAnalysis() {
        if (root.bsoidRunning) return
        var campo = root.bsoidCampo
        var sessionPath = workArea.selectedPath  // pasta do experimento
        if (!sessionPath) { root.bsoidError = LanguageManager.tr3("Nenhum experimento selecionado.", "No experiment selected.", "Ningun experimento seleccionado."); return }
        var csvPath = liveRecordingTab.behaviorCachePath(sessionPath, campo)
        var ok = liveRecordingTab.exportBehaviorFeatures(csvPath, campo)
        if (!ok) ok = liveRecordingTab.behaviorCacheExists(sessionPath, campo)
        if (!ok) { root.bsoidError = LanguageManager.tr3("Nenhum dado de features disponivel. Execute uma analise primeiro.", "No feature data available. Run an analysis first.", "No hay datos de features disponibles. Ejecute un analisis primero."); return }
        root.bsoidStep2DataReady = true
        // Captura FPS e caminho do vídeo para timeline e snippets
        root.bsoidFps       = (liveRecordingTab.dlcFps > 0) ? liveRecordingTab.dlcFps : 30.0
        root.bsoidVideoPath = liveRecordingTab.videoPath
        root.bsoidFlowStage = 1
        root.bsoidFinalComparisonUnlocked = false
        root.bsoidNamesTypedByUser = false
        if (root.bsoidWorkflowCursor < 3) root.bsoidWorkflowCursor = 3
        root.bsoidRunning    = true
        root.bsoidDone       = false
        root.bsoidStep3Embedded = false
        root.bsoidStep4Clustered = false
        root.bsoidGroups     = []
        root.bsoidGroupNames = []
        root.bsoidEditedGroups = []
        root.bsoidModelClusterIds = []
        root.behaviorStats   = []
        root.bsoidBehaviorStats = []
        root.bsoidMappingRaw = []
        root.bsoidRulesSmooth = []
        root.bsoidClustersSmooth = []
        root.bsoidClusterToRule = ({})
        root.bsoidAgreementPct = 0.0
        root.bsoidBestLagFrames = 0
        root.bsoidComparedFrames = 0
        root.bsoidConfusionGroups = []
        root.bsoidConfusionRows = []
        root.bsoidConfusionMacroTop1 = 0.0
        root.bsoidConfusionWeightedTop1 = 0.0
        root.bsoidClusterTopRule = ({})
        root.bsoidClusterTopPct = ({})
        root.bsoidFinalLabelStats = []
        root.bsoidError      = ""
        root.bsoidProgress   = 0
        root.snippetsComplete = false
        root.snippetsOutDir   = ""
        root.snippetsError    = ""
        var k = Math.max(4, Math.min(12, root.bsoidNumClusters))
        bsoidAnalyzer.analyze(csvPath, k)
    }

    function _saveTextFile(path, content) {
        return !!liveRecordingTab.writeTextFile(path, content, false)
    }

    function _loadJsonFile(path) {
        try {
            var txt = String(liveRecordingTab.readTextFile(path) || "").trim()
            if (txt !== "") return JSON.parse(txt)
        } catch (e) {}
        return null
    }

    function _csvEscape(v) {
        var s = String(v === undefined || v === null ? "" : v)
        if (s.indexOf(",") >= 0 || s.indexOf("\"") >= 0 || s.indexOf("\n") >= 0)
            return "\"" + s.replace(/"/g, "\"\"") + "\""
        return s
    }

    function buildNamedGroupReport() {
        var effective = bsoidEffectiveGroups()
        if (!bsoidDone || !effective || effective.length === 0 || !bsoidMappingRaw || bsoidMappingRaw.length === 0)
            return null

        var clusterToName = ({})
        var clusterToDefaultRule = ({})
        var allowedClusters = ({})
        var defs = []
        for (var i = 0; i < effective.length; i++) {
            var g = effective[i]
            var srcIdx = g._idx
            var typed = (bsoidGroupNames && bsoidGroupNames.length > srcIdx) ? String(bsoidGroupNames[srcIdx] || "").trim() : ""
            var finalName = typed !== "" ? typed : ("Group " + (g.clusterId + 1))
            clusterToName[g.clusterId] = finalName
            allowedClusters[g.clusterId] = true
            var alignedRule = (bsoidClusterTopRule[g.clusterId] !== undefined) ? bsoidClusterTopRule[g.clusterId] : g.dominantRule
            clusterToDefaultRule[g.clusterId] = alignedRule
            defs.push({
                clusterId: g.clusterId,
                groupName: finalName,
                dominantRule: bsoidRuleName(alignedRule),
                frameCount: g.frameCount,
                percentage: g.percentage
            })
        }

        var byName = ({})
        var prevName = ""
        var cut = Math.max(0, bsoidBestLagFrames || 0)
        var maxLen = Math.max(0, bsoidMappingRaw.length - cut)
        var countedFrames = 0
        for (var j = 0; j < maxLen; j++) {
            var recB = bsoidMappingRaw[j]
            var recR = bsoidMappingRaw[j + cut]
            var cid = recB.clusterId
            if (!allowedClusters[cid]) continue
            var rule = recR.ruleLabel
            var nm = clusterToName[cid] !== undefined ? clusterToName[cid] : ("Group " + (cid + 1))
            if (!byName[nm]) {
                byName[nm] = {
                    frames: 0,
                    bouts: 0,
                    clusters: ({}),
                    ruleCounts: ({})
                }
            }
            byName[nm].frames++
            countedFrames++
            byName[nm].clusters[cid] = true
            if (prevName !== nm) byName[nm].bouts++
            prevName = nm

            if (rule >= 0 && rule <= 4) {
                var rn = behaviorName(rule)
                byName[nm].ruleCounts[rn] = (byName[nm].ruleCounts[rn] || 0) + 1
            }
        }

        var namedSummary = []
        var totalFrames = countedFrames
        for (var key in byName) {
            var rs = byName[key].ruleCounts
            var topRule = "Unknown"
            var topCnt = -1
            for (var rr in rs) {
                if (rs[rr] > topCnt) { topCnt = rs[rr]; topRule = rr }
            }
            var clusterIds = []
            for (var ck in byName[key].clusters) clusterIds.push(parseInt(ck) + 1)
            clusterIds.sort(function(a,b){ return a-b })
            namedSummary.push({
                groupName: key,
                clusters: clusterIds,
                frames: byName[key].frames,
                percentage: totalFrames > 0 ? (100.0 * byName[key].frames / totalFrames) : 0.0,
                bouts: byName[key].bouts,
                dominantRule: topRule
            })
        }
        namedSummary.sort(function(a,b){ return b.frames - a.frames })

        return {
            version: 1,
            savedAt: new Date().toISOString(),
            experimentPath: workArea.selectedPath,
            campo: bsoidCampo + 1,
            totalFrames: totalFrames,
            decisionMode: bsoidDecisionMode,
            decisionModeLabel: decisionModeLabel(bsoidDecisionMode),
            trustedThresholdPct: bsoidTrustedThresholdPct,
            typedGroupNames: defs,
            namedSummary: namedSummary,
            finalLabelSummary: bsoidFinalLabelStats
        }
    }

    function loadNamedGroupLabels() {
        if (!bsoidDone || !bsoidGroups || bsoidGroups.length === 0 || workArea.selectedPath === "")
            return false
        var path = workArea.selectedPath + "/analysis_cache/bsoid_named_groups_campo" + (bsoidCampo + 1) + ".json"
        var doc = _loadJsonFile(path)
        if (!doc || !doc.typedGroupNames || !doc.typedGroupNames.length)
            return false

        var byCluster = ({})
        for (var i = 0; i < doc.typedGroupNames.length; i++) {
            var g = doc.typedGroupNames[i]
            if (g && g.clusterId !== undefined && g.groupName !== undefined)
                byCluster[g.clusterId] = String(g.groupName)
        }

        var names = []
        for (var j = 0; j < bsoidGroups.length; j++) {
            var cid = bsoidGroups[j].clusterId
            names.push(byCluster[cid] !== undefined ? byCluster[cid] : "")
        }
        bsoidGroupNames = names
        return true
    }

    function saveNamedGroupReport() {
        if (workArea.selectedPath === "") {
            errorToast.show(LanguageManager.tr3("Nenhum experimento selecionado.", "No experiment selected.", "Ningun experimento seleccionado."))
            return
        }
        var report = buildNamedGroupReport()
        if (!report) {
            errorToast.show(LanguageManager.tr3("Nada para salvar ainda.", "Nothing to save yet.", "Nada para guardar aun."))
            return
        }

        // Ensure analysis_cache exists (created by cache export path in C++).
        liveRecordingTab.saveBehaviorCache(workArea.selectedPath, bsoidCampo)

        var base = workArea.selectedPath + "/analysis_cache/bsoid_named_groups_campo" + (bsoidCampo + 1)
        var jsonPath = base + ".json"
        var csvPath = base + ".csv"
        var confCsvPath = base + "_confusion.csv"

        var jsonOk = !!liveRecordingTab.writeTextFile(jsonPath, JSON.stringify(report, null, 2), false)

        var csvLines = ["group_name,clusters,frames,percentage,bouts,dominant_rule"]
        for (var i = 0; i < report.namedSummary.length; i++) {
            var row = report.namedSummary[i]
            csvLines.push([
                _csvEscape(row.groupName),
                _csvEscape(row.clusters.join("|")),
                row.frames,
                row.percentage.toFixed(3),
                row.bouts,
                _csvEscape(row.dominantRule)
            ].join(","))
        }
        var csvOk = !!liveRecordingTab.writeTextFile(csvPath, csvLines.join("\n"), true)

        // Confusion matrix: Rules x Named Group (frame-level)
        var ruleNames = ["Walking", "Sniffing", "Grooming", "Resting", "Rearing"]
        var clusterToName = ({})
        for (var di = 0; di < report.typedGroupNames.length; di++) {
            var d = report.typedGroupNames[di]
            clusterToName[d.clusterId] = d.groupName
        }
        var allGroupNames = []
        for (var ns = 0; ns < report.namedSummary.length; ns++)
            allGroupNames.push(report.namedSummary[ns].groupName)

        var mat = ({})
        for (var rn = 0; rn < ruleNames.length; rn++) {
            var rname = ruleNames[rn]
            mat[rname] = ({})
            for (var gn = 0; gn < allGroupNames.length; gn++)
                mat[rname][allGroupNames[gn]] = 0
        }
        var cut2 = Math.max(0, bsoidBestLagFrames || 0)
        var maxLen2 = Math.max(0, bsoidMappingRaw.length - cut2)
        for (var mi = 0; mi < maxLen2; mi++) {
            var recB = bsoidMappingRaw[mi]
            var recR = bsoidMappingRaw[mi + cut2]
            if (recR.ruleLabel < 0 || recR.ruleLabel > 4) continue
            var rrn = ruleNames[recR.ruleLabel]
            var gnm = clusterToName[recB.clusterId] !== undefined ? clusterToName[recB.clusterId] : ("Group " + (recB.clusterId + 1))
            if (mat[rrn][gnm] === undefined) mat[rrn][gnm] = 0
            mat[rrn][gnm]++
        }

        var confLines = []
        confLines.push(["rule"].concat(allGroupNames).join(","))
        for (var rn2 = 0; rn2 < ruleNames.length; rn2++) {
            var rr2 = ruleNames[rn2]
            var row = [_csvEscape(rr2)]
            for (var gn2 = 0; gn2 < allGroupNames.length; gn2++) {
                var gg2 = allGroupNames[gn2]
                row.push(mat[rr2][gg2] !== undefined ? mat[rr2][gg2] : 0)
            }
            confLines.push(row.join(","))
        }
        var confCsvOk = !!liveRecordingTab.writeTextFile(confCsvPath, confLines.join("\n"), true)

        if (jsonOk && csvOk && confCsvOk)
        {
            root.bsoidStep6ModelCreated = true
            if (root.bsoidFlowStage < 4) root.bsoidFlowStage = 4
            if (root.bsoidWorkflowCursor <= 6) root.bsoidWorkflowCursor = 7
            successToast.show(LanguageManager.tr3("Relatorio salvo em: ", "Report saved at: ", "Informe guardado en: ") + base)
        } else
            errorToast.show(LanguageManager.tr3("Falha ao salvar relatorio B-SOiD.", "Failed to save B-SOiD report.", "Error al guardar informe B-SOiD."))
    }

    onContextChanged: {
        if (!root.searchMode && context !== "")
            ExperimentManager.loadContext(context, "comportamento_complexo")
    }

    Rectangle { anchors.fill: parent; color: ThemeManager.background; Behavior on color { ColorAnimation { duration: 200 } } }

    Connections {
        target: ExperimentManager

        function onErrorOccurred(message) { errorToast.show(message) }

        function onExperimentCreated(name, path) {
            successToast.show(LanguageManager.tr3("Experiment \"", "Experiment \"", "Experimento \"") + name + LanguageManager.tr3("\" created!", "\" created!", "\" creado!"))
            experimentList.selectExperimentByName(name)
            innerTabs.currentIndex = 0
        }

        function onExperimentDeleted(name) {
            successToast.show(LanguageManager.tr3("Experiment \"", "Experiment \"", "Experimento \"") + name + LanguageManager.tr3("\" deleted.", "\" deleted.", "\" eliminado."))
            root._syncSelectionWithModel()
        }

        function onSessionDataInserted(experimentName, sessionPath) {
            if (workArea.selectedName === experimentName) {
                tableModel.loadCsv(workArea.selectedPath + "/tracking_data.csv")
                successToast.show(LanguageManager.tr3("Session saved!", "Session saved!", "Sesion guardada!"))
                innerTabs.currentIndex = 2  // aba Classificação
            }
        }
    }

    Connections {
        target: ExperimentManager.model
        function onRowsRemoved() { root._syncSelectionWithModel() }
        function onModelReset() { root._syncSelectionWithModel() }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // â"€â"€ Barra superior â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€
        Rectangle {
            Layout.fillWidth: true
            height: 56; color: ThemeManager.surface; Behavior on color { ColorAnimation { duration: 200 } }

            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 1; color: ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } }
            }

            RowLayout {
                anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                spacing: 14

                GhostButton { text: LanguageManager.tr3("<- Voltar", "<- Back", "<- Volver"); onClicked: root.backRequested() }

                Text { text: "\u2699"; font.pixelSize: 20 }

                Text {
                    text: root.searchMode
                          ? LanguageManager.tr3("Comportamento Complexo - Experimentos", "Complex Behavior - Experiments", "Comportamiento Complejo - Experimentos")
                          : LanguageManager.tr3("Comportamento Complexo - Dashboard", "Complex Behavior - Dashboard", "Comportamiento Complejo - Panel")
                    color: ThemeManager.textPrimary; font.pixelSize: 16; font.weight: Font.Bold
                    Behavior on color { ColorAnimation { duration: 150 } }
                }

                Rectangle {
                    visible: root.numCampos > 0 && !root.searchMode
                    radius: 4; color: ThemeManager.surfaceHover
                    border.color: "#7a3dab"; border.width: 1
                    Behavior on color { ColorAnimation { duration: 200 } }
                    implicitWidth: numLabel.implicitWidth + 16; implicitHeight: 24
                    Text {
                        id: numLabel
                        anchors.centerIn: parent
                        text: root.numCampos + " " + LanguageManager.tr3("campo", "field", "campo") + (root.numCampos > 1 ? "s" : "")
                        color: "#7a3dab"; font.pixelSize: 11; font.weight: Font.Bold
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                }

                Item { Layout.fillWidth: true }
            }
        }

        // â"€â"€ Corpo â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // â"€â"€ Sidebar â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€
            Rectangle {
                width: 250; Layout.fillHeight: true
                color: ThemeManager.surface; Behavior on color { ColorAnimation { duration: 200 } }

                Rectangle {
                    anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
                    width: 1; color: ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } }
                }

                ColumnLayout {
                    anchors { fill: parent; margins: 12 }
                    spacing: 8

                    Text {
                        text: LanguageManager.tr3("Experimentos", "Experiments", "Experimentos")
                        color: ThemeManager.textPrimary; font.pixelSize: 12; font.weight: Font.Bold
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    TextField {
                        id: searchField
                        Layout.fillWidth: true
                        placeholderText: LanguageManager.tr3("Pesquisar...", "Search...", "Buscar...")
                        color: ThemeManager.textPrimary; placeholderTextColor: ThemeManager.textSecondary; font.pixelSize: 13
                        leftPadding: 10; rightPadding: 10; topPadding: 6; bottomPadding: 6
                        background: Rectangle {
                            radius: 6; color: ThemeManager.surfaceDim; Behavior on color { ColorAnimation { duration: 200 } }
                            border.color: searchField.activeFocus ? "#7a3dab" : ThemeManager.borderLight; border.width: 1
                            Behavior on border.color { ColorAnimation { duration: 150 } }
                        }
                        onTextChanged: ExperimentManager.setFilter(text)
                    }

                    ListView {
                        id: experimentList
                        Layout.fillWidth: true; Layout.fillHeight: true
                        clip: true; model: ExperimentManager.model; currentIndex: -1

                        function selectExperimentByName(name) {
                            for (var i = 0; i < model.count; ++i) {
                                if (model.data(model.index(i, 0), Qt.UserRole + 1) === name) {
                                    currentIndex = i
                                    var path = model.data(model.index(i, 0), Qt.UserRole + 2)
                                    workArea.loadExperiment(name, path)
                                    return
                                }
                            }
                        }

                        ScrollBar.vertical: ScrollBar {
                            policy: ScrollBar.AsNeeded
                            contentItem: Rectangle { implicitWidth: 4; radius: 2; color: ThemeManager.borderLight; Behavior on color { ColorAnimation { duration: 200 } } }
                        }

                        delegate: Rectangle {
                            id: expDelegate
                            width: experimentList.width; height: 36
                            property bool isSelected: experimentList.currentIndex === index
                            property bool isHovered: mainArea.containsMouse || trashArea.containsMouse
                            color: isSelected ? "#7a3dab" : (isHovered ? ThemeManager.surfaceAlt : "transparent")
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Text {
                                anchors { left: parent.left; leftMargin: 10; right: trashItem.left; rightMargin: 4; top: parent.top; bottom: parent.bottom }
                                text: model.name
                                color: expDelegate.isSelected ? ThemeManager.textPrimary : ThemeManager.textSecondary
                                Behavior on color { ColorAnimation { duration: 150 } }
                                font.pixelSize: 13; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter
                            }

                            Item {
                                id: trashItem
                                anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                                width: 30; opacity: expDelegate.isHovered ? 1.0 : 0.0
                                Behavior on opacity { NumberAnimation { duration: 150 } }
                                Text {
                                    anchors.centerIn: parent; text: "\uD83D\uDDD1"; font.pixelSize: 13
                                    color: trashArea.containsMouse ? "#9a5ddb" : "#7a3dab"
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }
                                MouseArea {
                                    id: trashArea; anchors.fill: parent
                                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        ExperimentManager.setActiveContext(model.context)
                                        root.pendingDeleteName = model.name
                                        deleteStep1Popup.open()
                                    }
                                }
                            }

                            MouseArea {
                                id: mainArea
                                anchors { fill: parent; rightMargin: trashItem.width }
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    experimentList.currentIndex = index
                                    workArea.loadExperiment(model.name, model.path)
                                }
                            }

                            Rectangle {
                                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                height: 1; color: ThemeManager.border; opacity: 0.5
                                Behavior on color { ColorAnimation { duration: 200 } }
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: experimentList.count === 0
                        text: LanguageManager.tr3("Nenhum experimento\nencontrado", "No experiment\nfound", "Ningun experimento\nencontrado")
                            color: ThemeManager.textSecondary; font.pixelSize: 12
                            Behavior on color { ColorAnimation { duration: 150 } }
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }
            }

            // â"€â"€ Área de trabalho â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€
            Item {
                id: workArea
                Layout.fillWidth: true; Layout.fillHeight: true

                property string selectedName: ""
                property string selectedPath: ""
                property int    colCount:     0
                property bool   includeDrug:      true
                property bool   hasObjectZones:   true
                property string analysisMode:     "offline"
                property string cameraId:         ""
                property int    activeNumCampos:  root.numCampos
                property int    sessionMinutes:   5
                property var    dayNames:         []

                function loadExperiment(name, path) {
                    selectedName = name
                    selectedPath = path
                    tableModel.loadCsv(path + "/tracking_data.csv")
                    workStack.currentIndex = 1

                    var meta = ExperimentManager.readMetadataFromPath(path)
                    var ctx  = meta.context || ""
                    ExperimentManager.setActiveContext(ctx)

                    includeDrug     = meta.includeDrug !== false
                    hasObjectZones  = meta.hasObjectZones !== false
                    activeNumCampos = meta.numCampos || root.numCampos
                    sessionMinutes  = meta.sessionMinutes || 5
                    dayNames        = meta.dayNames || Array.from({length: meta.sessionDays || 5}, function(_, i) { return LanguageManager.tr3("Day ", "Day ", "Dia ") + (i+1) })

                    if (activeNumCampos === 1) {
                        ArenaConfigModel.loadConfigFromPath(path, ":/arena_config_ei_referencia.json")
                        Qt.callLater(function() {
                            var fp = JSON.parse(ArenaConfigModel.getFloorPoints() || "[]")
                            var pts = (fp.length > 0 && Array.isArray(fp[0])) ? fp[0] : fp
                            if (!Array.isArray(pts) || pts.length < 8)
                                ArenaConfigModel.loadConfigFromPath("", ":/arena_config_ei_referencia.json")
                        })
                    } else {
                        ArenaConfigModel.loadConfigFromPath(path)
                    }

                    // Propaga pontos de arena para aba Gravação
                    liveRecordingTab.arenaPoints = JSON.parse(ArenaConfigModel.getArenaPoints() || "[]")
                    liveRecordingTab.floorPoints = JSON.parse(ArenaConfigModel.getFloorPoints() || "[]")
                    
                    // Propaga zonas se hasObjectZones; limpa explicitamente se não
                    if (workArea.hasObjectZones) {
                        var src = ArenaConfigModel.zones || []
                        if (src.length > 0) {
                            var converted = []
                            for (var i = 0; i < src.length; i++) {
                                var z = src[i]
                                converted.push({
                                    x: z.xRatio !== undefined ? z.xRatio : 0.3,
                                    y: z.yRatio !== undefined ? z.yRatio : 0.5,
                                    r: z.radiusRatio !== undefined ? z.radiusRatio : 0.12
                                })
                            }
                            liveRecordingTab.zones = converted
                        }
                    } else {
                        liveRecordingTab.zones = []
                    }

                    colCount = tableModel.columnCount()
                }

                ExperimentTableModel { id: tableModel }
                Connections { target: tableModel; function onModelReset() { workArea.colCount = tableModel.columnCount() } }

                StackLayout {
                    id: workStack
                    anchors.fill: parent
                    currentIndex: 0

                    // Índice 0: placeholder "selecione um experimento"
                    Item {
                        ColumnLayout {
                            anchors.centerIn: parent; spacing: 14
                                        Text { text: "\u2699"; font.pixelSize: 48; opacity: 0.15; Layout.alignment: Qt.AlignHCenter }
                            Text {
                                text: LanguageManager.tr3("Selecione um experimento", "Select an experiment", "Seleccione un experimento")
                                color: ThemeManager.textSecondary; font.pixelSize: 16
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }
                    }

                    // Índice 1: painel com abas
                    ColumnLayout {
                        spacing: 0

                        // â"€â"€ Barra de abas interna â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€
                        Rectangle {
                            Layout.fillWidth: true; height: 42
                            color: ThemeManager.surface; Behavior on color { ColorAnimation { duration: 200 } }
                            border.color: ThemeManager.border; border.width: 0

                            Rectangle {
                                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                height: 1; color: ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } }
                            }

                            RowLayout {
                                anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                                spacing: 0

                                Repeater {
                                    id: innerTabs
                                    property int currentIndex: 0
                                    model: ["🗺 " + LanguageManager.tr3("Arena", "Arena", "Arena"), "🎬 " + LanguageManager.tr3("Gravacao", "Recording", "Grabacion"), "🧠 " + LanguageManager.tr3("Classificacao", "Behavior", "Clasificacion"), "📊 " + LanguageManager.tr3("Dados", "Data", "Datos")]

                                    delegate: Item {
                                        id: tabItem
                                        width: tabLabel.implicitWidth + 28; height: parent.height
                                        property bool isActive:  innerTabs.currentIndex === index
                                        property bool isHovered: tabMouseArea.containsMouse

                                        scale: tabMouseArea.pressed ? 0.95 : (isHovered ? 1.05 : 1.0)
                                        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

                                        Rectangle {
                                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                            height: parent.isActive ? 2 : (parent.isHovered ? 1 : 0)
                                            color: parent.isActive ? "#7a3dab" : (parent.isHovered ? "#9a5ddb" : "transparent")
                                            Behavior on color  { ColorAnimation { duration: 150 } }
                                            Behavior on height { NumberAnimation { duration: 150 } }
                                        }

                                        Text {
                                            id: tabLabel; anchors.centerIn: parent
                                            text: modelData
                                            color: tabItem.isActive ? ThemeManager.textPrimary : (tabItem.isHovered ? ThemeManager.textSecondary : ThemeManager.textTertiary)
                                            Behavior on color { ColorAnimation { duration: 150 } }
                                            font.pixelSize: 12; font.weight: tabItem.isActive ? Font.Bold : Font.Normal
                                        }

                                        MouseArea {
                                            id: tabMouseArea; anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                            onClicked: innerTabs.currentIndex = index
                                        }
                                    }
                                }

                                Item { Layout.fillWidth: true }

                                Text {
                                    text: workArea.selectedName
                                    color: ThemeManager.textTertiary; font.pixelSize: 12; elide: Text.ElideRight
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }
                            }
                        }

                        StackLayout {
                            id: innerStack
                            Layout.fillWidth: true; Layout.fillHeight: true
                            currentIndex: innerTabs.currentIndex

                            // â"€â"€ Tab 0: Arena â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€
                            Item {
                                // ArenaSetup padrão â€" 2 ou 3 campos
                                ArenaSetup {
                                    id: tabArenaSetup
                                    anchors.fill: parent
                                    visible: workArea.activeNumCampos > 1
                                    experimentPath: workArea.activeNumCampos > 1 ? workArea.selectedPath : ""
                                    context: root.context
                                    numCampos: workArea.activeNumCampos
                                    aparato: "comportamento_complexo"
                                    caMode: true
                                    ccMode: true
                                    showObjectZones: workArea.hasObjectZones

                                    onAnalysisModeChangedExternally: function(mode) {
                                        workArea.analysisMode = mode
                                        workArea.cameraId     = tabArenaSetup.cameraId
                                        if (mode !== "offline") workArea.saveDirectory = tabArenaSetup.saveDirectory
                                    }
                                    onZonasEditadas: {
                                        if (workArea.activeNumCampos === 1) return
                                        liveRecordingTab.zones       = workArea.hasObjectZones ? tabArenaSetup.zones : []
                                        liveRecordingTab.arenaPoints = tabArenaSetup.arenaPoints
                                        liveRecordingTab.floorPoints = tabArenaSetup.floorPoints
                                    }
                                }

                                // EIArenaSetup â€" 1 campo (arena EI adaptada para CC)
                                EIArenaSetup {
                                    id: eiArenaSetupCC
                                    anchors.fill: parent
                                    visible: workArea.activeNumCampos === 1
                                    experimentPath: workArea.activeNumCampos === 1 ? workArea.selectedPath : ""
                                    numCampos: 1
                                    primaryColor:   "#7a3dab"
                                    secondaryColor: "#6a2d9a"

                                    onAnalysisModeChangedExternally: function(mode) {
                                        workArea.analysisMode = mode
                                        workArea.cameraId     = eiArenaSetupCC.cameraId
                                        if (mode !== "offline") workArea.saveDirectory = eiArenaSetupCC.saveDirectory
                                    }
                                    onZonasEditadas: {
                                        liveRecordingTab.zones       = []
                                        liveRecordingTab.arenaPoints = eiArenaSetupCC.arenaPoints
                                        liveRecordingTab.floorPoints = eiArenaSetupCC.floorPoints
                                    }
                                }
                            }

                            // â"€â"€ Tab 1: Gravação â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€
                            LiveRecording {
                                id: liveRecordingTab
                                videoPath:    workArea.activeNumCampos === 1 ? eiArenaSetupCC.videoPath : tabArenaSetup.videoPath
                                analysisMode: workArea.analysisMode
                                saveDirectory: workArea.saveDirectory || ""
                                liveOutputName: (workArea.activeNumCampos === 1 ? eiArenaSetupCC.liveOutputName : tabArenaSetup.liveOutputName) || ""
                                cameraId:     workArea.cameraId
                                numCampos:    workArea.activeNumCampos
                                aparato:      workArea.activeNumCampos === 1 ? "esquiva_inibitoria" : "comportamento_complexo"
                                ccMode:       true
                                sessionDurationMinutes: workArea.sessionMinutes

                                zones:        workArea.activeNumCampos === 1 ? [] : (workArea.hasObjectZones ? tabArenaSetup.zones : [])
                                arenaPoints:  JSON.parse(ArenaConfigModel.getArenaPoints() || "[]")
                                floorPoints:  JSON.parse(ArenaConfigModel.getFloorPoints() || "[]")

                                Connections {
                                    target: ArenaConfigModel
                                    function onConfigChanged() {
                                        liveRecordingTab.arenaPoints = JSON.parse(ArenaConfigModel.getArenaPoints() || "[]")
                                        liveRecordingTab.floorPoints = JSON.parse(ArenaConfigModel.getFloorPoints() || "[]")
                                    }
                                }

                                onSessionEnded: {
                                    // Persiste cache de features para Classificação pós-sessão
                                    if (workArea.selectedPath !== "") {
                                        for (var c = 0; c < workArea.activeNumCampos; c++)
                                            liveRecordingTab.saveBehaviorCache(workArea.selectedPath, c)
                                    }
                                    ccResultDialog.totalDistance  = liveRecordingTab.totalDistance
                                    ccResultDialog.avgVelocity    = liveRecordingTab.avgVelocityMeans
                                    ccResultDialog.perMinuteData  = liveRecordingTab.perMinuteData
                                    ccResultDialog.behaviorCounts = liveRecordingTab.behaviorCounts
                                    ccResultDialog.includeDrug    = workArea.includeDrug
                                    ccResultDialog.experimentName = workArea.selectedName
                                    ccResultDialog.experimentPath = workArea.selectedPath
                                    ccResultDialog.numCampos      = workArea.activeNumCampos
                                    ccResultDialog.videoPath      = workArea.analysisMode === "ao_vivo"
                                                                    ? ((liveRecordingTab.liveRecordedVideoPath && liveRecordingTab.liveRecordedVideoPath !== "")
                                                                       ? liveRecordingTab.liveRecordedVideoPath
                                                                       : ("camera://" + workArea.cameraId))
                                                                    : (workArea.activeNumCampos === 1 ? eiArenaSetupCC.videoPath : tabArenaSetup.videoPath)
                                    ccResultDialog.dayNames       = workArea.dayNames
                                    ccResultDialog.sessionMinutes = workArea.sessionMinutes || 5
                                    ccResultDialog.open()
                                }

                                onLiveAnalysisStarting: {
                                    tabArenaSetup.stopCameraPreview()
                                    eiArenaSetupCC.stopCameraPreview()
                                }

                                onRequestVideoLoad: {
                                    innerTabs.currentIndex = 0
                                }
                            }

                            // â"€â"€ Tab 2: Classificação â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€
                            Item {
                                id: classificationTab

                                Rectangle {
                                    anchors.fill: parent
                                    color: ThemeManager.background
                                    Behavior on color { ColorAnimation { duration: 200 } }

                                    ScrollView {
                                        anchors.fill: parent
                                        contentWidth: availableWidth
                                        clip: true

                                        ColumnLayout {
                                            width: Math.min(820, parent.width - 80)
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            anchors.top: parent.top
                                            anchors.topMargin: 28
                                            spacing: 20

                                            // Título
                                            RowLayout {
                                                Layout.alignment: Qt.AlignHCenter
                                                spacing: 12
                                                Text { text: "\u2699"; font.pixelSize: 30 }
                                                ColumnLayout {
                                                    spacing: 2
                                                    Text {
                                                        text: LanguageManager.tr3("Analise Comportamental Nativa", "Native Behavioral Analysis", "Analisis Conductual Nativo")
                                                        color: ThemeManager.textPrimary
                                                        font.pixelSize: 20; font.weight: Font.Bold
                                                        Behavior on color { ColorAnimation { duration: 150 } }
                                                    }
                                                    Text {
                                                        text: LanguageManager.tr3(
                                                                  "Classificacao por regras em tempo real · B-SOiD disponivel pos-sessao",
                                                                  "Real-time rule-based classification · B-SOiD available after session",
                                                                  "Clasificacion por reglas en tiempo real · B-SOiD disponible despues de la sesion"
                                                              )
                                                        color: ThemeManager.textSecondary; font.pixelSize: 11
                                                        Behavior on color { ColorAnimation { duration: 150 } }
                                                    }
                                                }
                                            }

                                            // Card: motor de regras ativo
                                            Rectangle {
                                                Layout.fillWidth: true; radius: 12
                                                color: ThemeManager.surfaceDim
                                                border.color: ThemeManager.borderLight; border.width: 1
                                                implicitHeight: ruleRow.implicitHeight + 24
                                                Behavior on color { ColorAnimation { duration: 150 } }
                                                Behavior on border.color { ColorAnimation { duration: 150 } }
                                                RowLayout {
                                                    id: ruleRow
                                                    anchors { fill: parent; margins: 12 }
                                                    spacing: 12
                                                    Text { text: "\u2699"; font.pixelSize: 20 }
                                                    ColumnLayout {
                                                        spacing: 2
                                                        Text {
                                                            text: LanguageManager.tr3("Motor de Regras Nativo (C++)", "Native Rules Engine (C++)", "Motor de Reglas Nativo (C++)")
                                                            color: ThemeManager.textPrimary; font.weight: Font.Bold; font.pixelSize: 13
                                                            Behavior on color { ColorAnimation { duration: 150 } }
                                                        }
                                                        Text {
                                                            text: LanguageManager.tr3(
                                                                      "Sniffing · Rearing · Resting · Grooming · Walking - sem modelo ONNX",
                                                                      "Sniffing · Rearing · Resting · Grooming · Walking - no ONNX model",
                                                                      "Sniffing · Rearing · Resting · Grooming · Walking - sin modelo ONNX"
                                                                  )
                                                            color: ThemeManager.textSecondary; font.pixelSize: 11
                                                            Behavior on color { ColorAnimation { duration: 150 } }
                                                        }
                                                    }
                                                    Item { Layout.fillWidth: true }
                                                    Rectangle {
                                                        color: ThemeManager.successLight; radius: 6
                                                        implicitWidth: ruleStatusTxt.implicitWidth + 16
                                                        implicitHeight: ruleStatusTxt.implicitHeight + 8
                                                        Text {
                                                            id: ruleStatusTxt
                                                            anchors.centerIn: parent
                                                            text: LanguageManager.tr3("ATIVO", "ACTIVE", "ACTIVO")
                                                            color: ThemeManager.success
                                                            font.pixelSize: 12; font.weight: Font.Bold
                                                        }
                                                    }
                                                }
                                            }

                                            // Badges em tempo real por campo
                                            RowLayout {
                                                Layout.fillWidth: true; spacing: 16
                                                Repeater {
                                                    model: workArea.activeNumCampos
                                                    delegate: Rectangle {
                                                        Layout.fillWidth: true; Layout.minimumHeight: 120; radius: 12
                                                        color: ThemeManager.surface
                                                        border.color: ThemeManager.border; border.width: 1
                                                        Behavior on color { ColorAnimation { duration: 150 } }
                                                        Behavior on border.color { ColorAnimation { duration: 150 } }
                                                        ColumnLayout {
                                                            anchors.centerIn: parent; spacing: 12
                                                            Text {
                                                                Layout.alignment: Qt.AlignHCenter
                                                                text: LanguageManager.tr3("Campo ", "Field ", "Campo ") + (index + 1)
                                                                color: ThemeManager.textSecondary
                                                                font.pixelSize: 13; font.weight: Font.Bold
                                                                Behavior on color { ColorAnimation { duration: 150 } }
                                                            }
                                                            Rectangle {
                                                                Layout.alignment: Qt.AlignHCenter
                                                                radius: 6; implicitHeight: 36; implicitWidth: bhvTxt.implicitWidth + 36
                                                                property string bhvName: liveRecordingTab.currentBehaviorString[index] || LanguageManager.tr3("Detectando...", "Detecting...", "Detectando...")
                                                                property color badgeColor: {
                                                                    if (bhvName === "Walking")  return "#8b5cf6"
                                                                    if (bhvName === "Resting")  return "#3b82f6"
                                                                    if (bhvName === "Rearing")  return "#10b981"
                                                                    if (bhvName === "Grooming") return "#eab308"
                                                                    if (bhvName === "Sniffing") return "#f97316"
                                                                    return ThemeManager.surfaceAlt
                                                                }
                                                                color: badgeColor
                                                                Behavior on color { ColorAnimation { duration: 250 } }
                                                                Text {
                                                                    id: bhvTxt
                                                                    anchors.centerIn: parent
                                                                    text: parent.bhvName
                                                                    color: parent.bhvName === LanguageManager.tr3("Detectando...", "Detecting...", "Detectando...") ? ThemeManager.textSecondary : "#ffffff"
                                                                    font.pixelSize: 14; font.weight: Font.Bold
                                                                    Behavior on color { ColorAnimation { duration: 250 } }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }

                                            // Legenda
                                            Rectangle {
                                                Layout.fillWidth: true; radius: 8
                                                color: "transparent"
                                                border.color: ThemeManager.borderLight; border.width: 1
                                                Behavior on border.color { ColorAnimation { duration: 150 } }
                                                implicitHeight: legendRow.implicitHeight + 20
                                                RowLayout {
                                                    id: legendRow
                                                    anchors { fill: parent; margins: 10 }
                                                    spacing: 16
                                                    Item { Layout.fillWidth: true }
                                                    Repeater {
                                                        model: ["Walking|#8b5cf6", "Sniffing|#f97316", "Grooming|#eab308", "Resting|#3b82f6", "Rearing|#10b981"]
                                                        delegate: RowLayout {
                                                            spacing: 6
                                                            Rectangle { width: 14; height: 14; radius: 7; color: modelData.split("|")[1] }
                                                            Text {
                                                                text: modelData.split("|")[0]
                                                                color: ThemeManager.textSecondary; font.pixelSize: 12
                                                                Behavior on color { ColorAnimation { duration: 150 } }
                                                            }
                                                        }
                                                    }
                                                    Item { Layout.fillWidth: true }
                                                }
                                            }

                                            // Separador B-SOiD
                                            RowLayout {
                                                Layout.fillWidth: true; spacing: 12
                                                Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } } }
                                                Text {
                                                    text: "B-SOiD"
                                                    color: ThemeManager.textSecondary; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.2
                                                    Behavior on color { ColorAnimation { duration: 150 } }
                                                }
                                                Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } } }
                                            }

                                            // Card B-SOiD (pós-sessão â€" interativo)
                                            Rectangle {
                                                Layout.fillWidth: true; radius: 12
                                                color: ThemeManager.surfaceDim
                                                border.color: ThemeManager.borderLight; border.width: 1
                                                implicitHeight: bsoidMainCol.implicitHeight + 28
                                                Behavior on color { ColorAnimation { duration: 150 } }
                                                Behavior on border.color { ColorAnimation { duration: 150 } }

                                                ColumnLayout {
                                                    id: bsoidMainCol
                                                    anchors { fill: parent; margins: 14 }
                                                    spacing: 12

                                                    // Header responsivo: evita estouro horizontal
                                                    ColumnLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 8

                                                        RowLayout {
                                                            Layout.fillWidth: true
                                                            spacing: 10
                                                            Text { text: "\uD83D\uDD2C"; font.pixelSize: 18 }
                                                            ColumnLayout {
                                                                Layout.fillWidth: true
                                                                spacing: 2
                                                                Text {
                                                                    text: LanguageManager.tr3("Analise B-SOiD (Pos-Sessao)", "B-SOiD Analysis (Post-Session)", "Analisis B-SOiD (Post-Sesion)")
                                                                    color: ThemeManager.textPrimary; font.weight: Font.Bold; font.pixelSize: 13
                                                                    Behavior on color { ColorAnimation { duration: 150 } }
                                                                }
                                                                Text {
                                                                    text: LanguageManager.tr3(
                                                                              "Agrupa frames por padrao de movimento via PCA + K-Means (aprox. B-SOiD)",
                                                                              "Groups frames by movement pattern using PCA + K-Means (B-SOiD approximation)",
                                                                              "Agrupa fotogramas por patron de movimiento via PCA + K-Means (aprox. B-SOiD)"
                                                                          )
                                                                    color: ThemeManager.textSecondary; font.pixelSize: 11
                                                                    wrapMode: Text.WordWrap
                                                                    Behavior on color { ColorAnimation { duration: 150 } }
                                                                }
                                                            }
                                                            Rectangle {
                                                                radius: 6
                                                                color: root.bsoidDone ? ThemeManager.successLight : "#1a1a3a"
                                                                border.color: root.bsoidDone ? ThemeManager.success : "#4a4a8c"
                                                                border.width: 1
                                                                implicitWidth: bsoidBadgeTxt.implicitWidth + 16
                                                                implicitHeight: bsoidBadgeTxt.implicitHeight + 8
                                                                Behavior on color { ColorAnimation { duration: 200 } }
                                                                Text {
                                                                    id: bsoidBadgeTxt
                                                                    anchors.centerIn: parent
                                                                    text: root.bsoidDone ? LanguageManager.tr3("Concluido", "Done", "Completado") : root.bsoidRunning ? ("" + root.bsoidProgress + "%") : LanguageManager.tr3("Aguardando", "Waiting", "Esperando")
                                                                    color: root.bsoidDone ? ThemeManager.success : "#8888cc"
                                                                    font.pixelSize: 11; font.weight: Font.Bold
                                                                    Behavior on color { ColorAnimation { duration: 200 } }
                                                                }
                                                            }
                                                        }

                                                        Flow {
                                                            Layout.fillWidth: true
                                                            spacing: 8

                                                            Text {
                                                                text: LanguageManager.tr3("Campo:", "Field:", "Campo:")
                                                                color: ThemeManager.textSecondary; font.pixelSize: 11
                                                            }
                                                            Repeater {
                                                                model: workArea.activeNumCampos
                                                                delegate: Rectangle {
                                                                    width: 36; height: 26; radius: 6
                                                                    property bool sel: root.bsoidCampo === index
                                                                    color: sel ? "#1a0d2e" : (cma.containsMouse ? ThemeManager.surfaceHover : ThemeManager.surfaceDim)
                                                                    border.color: sel ? "#7c3aed" : ThemeManager.border; border.width: sel ? 2 : 1
                                                                    Text {
                                                                        anchors.centerIn: parent
                                                                        text: "C" + (index + 1)
                                                                        color: sel ? "#a78bfa" : ThemeManager.textSecondary
                                                                        font.pixelSize: 11; font.weight: Font.Bold
                                                                    }
                                                                    MouseArea {
                                                                        id: cma; anchors.fill: parent
                                                                        cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                                                        onClicked: {
                                                                            if (root.bsoidCampo !== index) {
                                                                                root.bsoidCampo   = index
                                                                                root.resetBsoidWorkflow()
                                                                                root.bsoidDone    = false
                                                                                root.bsoidGroups  = []
                                                                                root.bsoidGroupNames = []
                                                                                root.behaviorStats   = []
                                                                                root.bsoidMappingRaw = []
                                                                                root.bsoidRulesSmooth = []
                                                                                root.bsoidClustersSmooth = []
                                                                                root.bsoidClusterToRule = ({})
                                                                                root.bsoidAgreementPct = 0.0
                                                                                root.bsoidBestLagFrames = 0
                                                                                root.bsoidComparedFrames = 0
                                                                                root.bsoidConfusionGroups = []
                                                                                root.bsoidConfusionRows = []
                                                                                root.bsoidConfusionMacroTop1 = 0.0
                                                                                root.bsoidConfusionWeightedTop1 = 0.0
                                                                                root.bsoidClusterTopRule = ({})
                                                                                root.bsoidClusterTopPct = ({})
                                                                                root.bsoidFinalLabelStats = []
                                                                                root.bsoidError   = ""
                                                                            }
                                                                        }
                                                                    }
                                                                }
                                                            }

                                                            Text {
                                                                text: LanguageManager.tr3("Clusters (max):", "Clusters (max):", "Clusters (max):")
                                                                color: ThemeManager.textSecondary; font.pixelSize: 11
                                                            }
                                                            RowLayout {
                                                                spacing: 4
                                                                Rectangle {
                                                                    width: 24; height: 24; radius: 4
                                                                    color: minusClusters.containsMouse ? ThemeManager.surfaceHover : ThemeManager.surfaceDim
                                                                    border.color: ThemeManager.border; border.width: 1
                                                                    Text { anchors.centerIn: parent; text: "−"; color: ThemeManager.textPrimary; font.pixelSize: 12; font.weight: Font.Bold }
                                                                    MouseArea {
                                                                        id: minusClusters
                                                                        anchors.fill: parent
                                                                        hoverEnabled: true
                                                                        cursorShape: Qt.PointingHandCursor
                                                                        onClicked: root.bsoidNumClusters = Math.max(4, root.bsoidNumClusters - 1)
                                                                    }
                                                                }
                                                                Rectangle {
                                                                    width: 34; height: 24; radius: 4
                                                                    color: ThemeManager.surfaceDim
                                                                    border.color: ThemeManager.border; border.width: 1
                                                                    Text {
                                                                        anchors.centerIn: parent
                                                                        text: root.bsoidNumClusters
                                                                        color: ThemeManager.textPrimary
                                                                        font.pixelSize: 11
                                                                        font.weight: Font.Bold
                                                                    }
                                                                }
                                                                Rectangle {
                                                                    width: 24; height: 24; radius: 4
                                                                    color: plusClusters.containsMouse ? ThemeManager.surfaceHover : ThemeManager.surfaceDim
                                                                    border.color: ThemeManager.border; border.width: 1
                                                                    Text { anchors.centerIn: parent; text: "+"; color: ThemeManager.textPrimary; font.pixelSize: 12; font.weight: Font.Bold }
                                                                    MouseArea {
                                                                        id: plusClusters
                                                                        anchors.fill: parent
                                                                        hoverEnabled: true
                                                                        cursorShape: Qt.PointingHandCursor
                                                                        onClicked: root.bsoidNumClusters = Math.min(12, root.bsoidNumClusters + 1)
                                                                    }
                                                                }
                                                            }

                                                            Button {
                                                                visible: root.bsoidDone && !root.bsoidRunning
                                                                text: LanguageManager.tr3("Reanalisar", "Re-analyze", "Reanalizar")
                                                                onClicked: root.startBsoidAnalysis()
                                                                background: Rectangle {
                                                                    radius: 7
                                                                    color: parent.hovered ? ThemeManager.surfaceHover : ThemeManager.surfaceDim
                                                                    border.color: ThemeManager.border
                                                                    border.width: 1
                                                                }
                                                                contentItem: Text {
                                                                    text: parent.text; color: ThemeManager.textSecondary
                                                                    font.pixelSize: 11; font.weight: Font.Bold
                                                                    horizontalAlignment: Text.AlignHCenter
                                                                    verticalAlignment: Text.AlignVCenter
                                                                }
                                                                leftPadding: 12; rightPadding: 12; topPadding: 6; bottomPadding: 6
                                                            }

                                                            BusyIndicator {
                                                                visible: root.bsoidRunning
                                                                width: 28; height: 28
                                                                running: root.bsoidRunning
                                                            }
                                                        }
                                                    }

                                                    // Barra de progresso
                                                    Rectangle {
                                                        visible: root.bsoidRunning
                                                        Layout.fillWidth: true; height: 4; radius: 2
                                                        color: ThemeManager.border
                                                        Behavior on color { ColorAnimation { duration: 200 } }
                                                        Rectangle {
                                                            width: parent.width * (root.bsoidProgress / 100)
                                                            height: parent.height; radius: parent.radius
                                                            color: "#7c3aed"
                                                            Behavior on width { NumberAnimation { duration: 200 } }
                                                        }
                                                    }

                                                    // Mensagem de erro
                                                    Text {
                                                        visible: root.bsoidError !== ""
                                                        text: LanguageManager.tr3("Warning: ", "Warning: ", "Aviso: ") + root.bsoidError
                                                        color: "#ef4444"; font.pixelSize: 11
                                                        wrapMode: Text.WordWrap; Layout.fillWidth: true
                                                    }

                                                    // Texto de ajuda (apenas antes da análise)
                                                    Text {
                                                        visible: !root.bsoidDone && !root.bsoidRunning && root.bsoidError === ""
                                                        text: LanguageManager.tr3("Clique em Analisar apos finalizar a gravacao. O algoritmo analisa os dados de trajetoria coletados e descobre grupos comportamentais adicionais as regras nativas.", "Click Analyze after recording ends. The algorithm analyzes trajectory data and discovers behavioral groups in addition to native rules.", "Haga clic en Analizar despues de finalizar la grabacion. El algoritmo analiza los datos de trayectoria y descubre grupos conductuales adicionales a las reglas nativas.")
                                                        color: ThemeManager.textTertiary; font.pixelSize: 11
                                                        wrapMode: Text.WordWrap; Layout.fillWidth: true
                                                        Behavior on color { ColorAnimation { duration: 150 } }
                                                    }

                                                    // Fluxo B-SOiD limpo e progressivo (unidirecional)
                                                    ColumnLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 8

                                                        Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } } }

                                                        Text {
                                                            text: LanguageManager.tr3("FLUXO B-SOiD", "B-SOiD FLOW", "FLUJO B-SOiD")
                                                            color: ThemeManager.textSecondary
                                                            font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 1.2
                                                        }

                                                        Rectangle {
                                                            Layout.fillWidth: true
                                                            radius: 7
                                                            color: "#121834"
                                                            border.color: "#2b3b84"
                                                            border.width: 1
                                                            implicitHeight: stageTxt.implicitHeight + 12
                                                            Text {
                                                                id: stageTxt
                                                                anchors { left: parent.left; right: parent.right; margins: 8; verticalCenter: parent.verticalCenter }
                                                                text: root.bsoidFlowStage === 1 ? LanguageManager.tr3("1/5 - Rodar analise B-SOiD", "1/5 - Run B-SOiD analysis", "1/5 - Ejecutar analisis B-SOiD")
                                                                     : root.bsoidFlowStage === 2 ? LanguageManager.tr3("2/5 - Filtrar clusters relevantes (Min %)", "2/5 - Filter relevant clusters (Min %)", "2/5 - Filtrar clusters relevantes (Min %)")
                                                                     : root.bsoidFlowStage === 3 ? LanguageManager.tr3("3/5 - Gerar snippets e nomear clusters", "3/5 - Generate snippets and label clusters", "3/5 - Generar snippets y nombrar clusters")
                                                                     : root.bsoidFlowStage === 4 ? LanguageManager.tr3("4/5 - Gerar comparacao com Rules", "4/5 - Generate comparison with Rules", "4/5 - Generar comparacion con Rules")
                                                                     : LanguageManager.tr3("5/5 - Salvar rotulos + estatistica", "5/5 - Save labels + stats", "5/5 - Guardar etiquetas + estadistica")
                                                                color: "#c7d2fe"
                                                                font.pixelSize: 10
                                                                wrapMode: Text.WordWrap
                                                            }
                                                        }

                                                        Button {
                                                            visible: root.bsoidFlowStage === 1
                                                            enabled: !root.bsoidRunning
                                                            text: root.bsoidRunning
                                                                  ? LanguageManager.tr3("Analisando...", "Analyzing...", "Analizando...")
                                                                  : LanguageManager.tr3("Analisar", "Analyze", "Analizar")
                                                            onClicked: root.startBsoidAnalysis()
                                                            background: Rectangle {
                                                                radius: 7
                                                                color: parent.enabled ? (parent.hovered ? "#5b21b6" : "#7c3aed") : ThemeManager.border
                                                            }
                                                            contentItem: Text {
                                                                text: parent.text
                                                                color: parent.enabled ? "#ffffff" : ThemeManager.textTertiary
                                                                font.pixelSize: 12
                                                                font.weight: Font.Bold
                                                                horizontalAlignment: Text.AlignHCenter
                                                                verticalAlignment: Text.AlignVCenter
                                                            }
                                                        }

                                                        Button {
                                                            visible: root.bsoidFlowStage === 2
                                                            enabled: root.bsoidDone
                                                            text: LanguageManager.tr3("Fixar Clusters Visiveis", "Freeze Visible Clusters", "Fijar Clusters Visibles")
                                                            onClicked: root.createModelFromVisibleClusters()
                                                            background: Rectangle {
                                                                radius: 7
                                                                color: parent.enabled ? (parent.hovered ? "#5b21b6" : "#7c3aed") : ThemeManager.border
                                                            }
                                                            contentItem: Text {
                                                                text: parent.text
                                                                color: parent.enabled ? "#ffffff" : ThemeManager.textTertiary
                                                                font.pixelSize: 12
                                                                font.weight: Font.Bold
                                                                horizontalAlignment: Text.AlignHCenter
                                                                verticalAlignment: Text.AlignVCenter
                                                            }
                                                        }

                                                        Button {
                                                            visible: root.bsoidFlowStage === 3
                                                            enabled: root.bsoidDone && !root.snippetsRunning
                                                            text: root.snippetsRunning ? LanguageManager.tr3("Gerando Snippets...", "Generating snippets...", "Generando snippets...")
                                                                 : LanguageManager.tr3("Gerar Snippets", "Generate Snippets", "Generar Snippets")
                                                            onClicked: {
                                                                var outDir = workArea.selectedPath + "/bsoid_snippets"
                                                                root.snippetsRunning  = true
                                                                root.snippetsComplete = false
                                                                root.snippetsError    = ""
                                                                root.snippetsProgress = 0
                                                                bsoidAnalyzer.extractSnippets(root.bsoidVideoPath, outDir, root.bsoidFps, 3)
                                                            }
                                                            background: Rectangle {
                                                                radius: 7
                                                                color: parent.enabled ? (parent.hovered ? "#5b21b6" : "#7c3aed") : ThemeManager.border
                                                            }
                                                            contentItem: Text {
                                                                text: parent.text
                                                                color: parent.enabled ? "#ffffff" : ThemeManager.textTertiary
                                                                font.pixelSize: 12
                                                                font.weight: Font.Bold
                                                                horizontalAlignment: Text.AlignHCenter
                                                                verticalAlignment: Text.AlignVCenter
                                                            }
                                                        }

                                                        Button {
                                                            visible: root.bsoidFlowStage === 4
                                                            enabled: root.snippetsComplete && root.canUnlockFinalComparison()
                                                            text: LanguageManager.tr3("Gerar Comparacao", "Generate Comparison", "Generar Comparacion")
                                                            onClicked: {
                                                                if (root.tryUnlockFinalComparison())
                                                                    root.bsoidFlowStage = 5
                                                            }
                                                            background: Rectangle {
                                                                radius: 7
                                                                color: parent.enabled ? (parent.hovered ? "#5b21b6" : "#7c3aed") : ThemeManager.border
                                                            }
                                                            contentItem: Text {
                                                                text: parent.text
                                                                color: parent.enabled ? "#ffffff" : ThemeManager.textTertiary
                                                                font.pixelSize: 12
                                                                font.weight: Font.Bold
                                                                horizontalAlignment: Text.AlignHCenter
                                                                verticalAlignment: Text.AlignVCenter
                                                            }
                                                        }

                                                        Button {
                                                            visible: root.bsoidFlowStage === 5 && root.bsoidFinalComparisonUnlocked
                                                            enabled: root.bsoidDone
                                                            text: LanguageManager.tr3("Salvar Rotulos + Estatistica", "Save Labels + Stats", "Guardar Etiquetas + Estadistica")
                                                            onClicked: root.saveNamedGroupReport()
                                                            background: Rectangle {
                                                                radius: 7
                                                                color: parent.enabled ? (parent.hovered ? "#5b21b6" : "#7c3aed") : ThemeManager.border
                                                            }
                                                            contentItem: Text {
                                                                text: parent.text
                                                                color: parent.enabled ? "#ffffff" : ThemeManager.textTertiary
                                                                font.pixelSize: 12
                                                                font.weight: Font.Bold
                                                                horizontalAlignment: Text.AlignHCenter
                                                                verticalAlignment: Text.AlignVCenter
                                                            }
                                                        }

                                                        Button {
                                                            visible: root.bsoidFlowStage === 5 && root.bsoidFinalComparisonUnlocked
                                                            enabled: root.bsoidDone && root.bsoidConfusionRows.length > 0
                                                            text: LanguageManager.tr3("Salvar PDF Results Report", "Save PDF Results Report", "Guardar PDF Results Report")
                                                            onClicked: root.exportResultsPdfReport()
                                                            background: Rectangle {
                                                                radius: 7
                                                                color: parent.enabled ? (parent.hovered ? "#0f766e" : "#0ea5a3") : ThemeManager.border
                                                            }
                                                            contentItem: Text {
                                                                text: parent.text
                                                                color: parent.enabled ? "#ffffff" : ThemeManager.textTertiary
                                                                font.pixelSize: 12
                                                                font.weight: Font.Bold
                                                                horizontalAlignment: Text.AlignHCenter
                                                                verticalAlignment: Text.AlignVCenter
                                                            }
                                                        }

                                                        Text {
                                                            visible: root.bsoidFlowStage === 4 && (!root.snippetsComplete || !root.canUnlockFinalComparison())
                                                            text: !root.snippetsComplete
                                                                  ? LanguageManager.tr3("Gere os snippets antes de comparar.", "Generate snippets before comparison.", "Genere snippets antes de comparar.")
                                                                  : root.unlockBlockingMessage()
                                                            color: "#f59e0b"
                                                            font.pixelSize: 10
                                                            wrapMode: Text.WordWrap
                                                            Layout.fillWidth: true
                                                        }
                                                    }

                                                    // â"€â"€ Estatísticas por comportamento (pós B-SOiD) â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€
                                                    ColumnLayout {
                                                        visible: root.bsoidDone && root.behaviorStats.length > 0
                                                        Layout.fillWidth: true; spacing: 6

                                                        Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } } }

                                                        Text {
                                                            text: LanguageManager.tr3("BEHAVIORS - BOUTS · C", "BEHAVIORS - BOUTS · C", "COMPORTAMIENTOS - BOUTS · C") + (root.bsoidCampo + 1)
                                                            color: ThemeManager.textSecondary
                                                            font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 1.2
                                                            Behavior on color { ColorAnimation { duration: 150 } }
                                                        }

                                                        // Cabeçalho tabela
                                                        RowLayout {
                                                            Layout.fillWidth: true; spacing: 0
                                                            Text { text: LanguageManager.tr3("Comportamento", "Behavior", "Comportamiento"); width: 120; color: ThemeManager.textTertiary; font.pixelSize: 10; font.weight: Font.Bold }
                                                            Text { text: "Bouts";         width: 60;  color: ThemeManager.textTertiary; font.pixelSize: 10; font.weight: Font.Bold; horizontalAlignment: Text.AlignRight }
                                                            Item { Layout.fillWidth: true }
                                                        }

                                                        Repeater {
                                                            model: root.behaviorStats
                                                            delegate: RowLayout {
                                                                Layout.fillWidth: true; spacing: 8
                                                                Rectangle { width: 10; height: 10; radius: 5; color: modelData.color }
                                                                Text { text: modelData.name; width: 120; color: ThemeManager.textPrimary; font.pixelSize: 11 }
                                                                Text { text: "•"; color: ThemeManager.textTertiary; font.pixelSize: 11 }
                                                                Text { text: modelData.bouts + " bouts"; width: 90; color: ThemeManager.textSecondary; font.pixelSize: 11; horizontalAlignment: Text.AlignRight }
                                                                Item { Layout.fillWidth: true }
                                                            }
                                                        }
                                                    }

                                                    ColumnLayout {
                                                        id: barsReportCard
                                                        visible: root.bsoidDone && root.bsoidFinalComparisonUnlocked && root.behaviorStats.length > 0
                                                        Layout.fillWidth: true
                                                        spacing: 6

                                                        Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border }
                                                        Text {
                                                            text: LanguageManager.tr3("GRAFICOS DE COLUNAS - Rules vs B-SOiD", "BAR CHARTS - Rules vs B-SOiD", "GRAFICOS DE COLUMNAS - Rules vs B-SOiD")
                                                            color: ThemeManager.textSecondary
                                                            font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 1.2
                                                        }

                                                        RowLayout {
                                                            Layout.fillWidth: true
                                                            spacing: 12

                                                            Rectangle {
                                                                Layout.fillWidth: true
                                                                Layout.preferredHeight: 170
                                                                radius: 8
                                                                color: ThemeManager.surface
                                                                border.color: ThemeManager.border
                                                                border.width: 1
                                                                ColumnLayout {
                                                                    anchors.fill: parent
                                                                    anchors.margins: 8
                                                                    spacing: 6
                                                                    Text { text: "Rules"; color: ThemeManager.textPrimary; font.pixelSize: 11; font.weight: Font.Bold }
                                                                    Repeater {
                                                                        model: root.behaviorStats
                                                                        delegate: RowLayout {
                                                                            required property var modelData
                                                                            Layout.fillWidth: true
                                                                            spacing: 6
                                                                            Text { text: modelData.name; width: 66; color: ThemeManager.textTertiary; font.pixelSize: 9; elide: Text.ElideRight }
                                                                            Rectangle {
                                                                                Layout.fillWidth: true
                                                                                height: 10
                                                                                radius: 5
                                                                                color: ThemeManager.border
                                                                                Rectangle {
                                                                                    width: parent.width * (Number(modelData.bouts || 0) / root._maxBouts(root.behaviorStats))
                                                                                    height: parent.height
                                                                                    radius: parent.radius
                                                                                    color: modelData.color
                                                                                }
                                                                            }
                                                                            Text { text: String(modelData.bouts); width: 34; color: ThemeManager.textSecondary; font.pixelSize: 9; horizontalAlignment: Text.AlignRight }
                                                                        }
                                                                    }
                                                                }
                                                            }

                                                            Rectangle {
                                                                Layout.fillWidth: true
                                                                Layout.preferredHeight: 170
                                                                radius: 8
                                                                color: ThemeManager.surface
                                                                border.color: ThemeManager.border
                                                                border.width: 1
                                                                ColumnLayout {
                                                                    anchors.fill: parent
                                                                    anchors.margins: 8
                                                                    spacing: 6
                                                                    Text { text: "B-SOiD"; color: ThemeManager.textPrimary; font.pixelSize: 11; font.weight: Font.Bold }
                                                                    Repeater {
                                                                        model: root.bsoidBehaviorStats
                                                                        delegate: RowLayout {
                                                                            required property var modelData
                                                                            Layout.fillWidth: true
                                                                            spacing: 6
                                                                            Text { text: modelData.name; width: 66; color: ThemeManager.textTertiary; font.pixelSize: 9; elide: Text.ElideRight }
                                                                            Rectangle {
                                                                                Layout.fillWidth: true
                                                                                height: 10
                                                                                radius: 5
                                                                                color: ThemeManager.border
                                                                                Rectangle {
                                                                                    width: parent.width * (Number(modelData.bouts || 0) / root._maxBouts(root.bsoidBehaviorStats))
                                                                                    height: parent.height
                                                                                    radius: parent.radius
                                                                                    color: modelData.color
                                                                                }
                                                                            }
                                                                            Text { text: String(modelData.bouts); width: 34; color: ThemeManager.textSecondary; font.pixelSize: 9; horizontalAlignment: Text.AlignRight }
                                                                        }
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }

                                                    // Resultados: grupos descobertos
                                                    ColumnLayout {
                                                        visible: root.bsoidDone && !root.bsoidFinalComparisonUnlocked && root.bsoidEffectiveGroups().length > 0
                                                        Layout.fillWidth: true; spacing: 6

                                                        RowLayout {
                                                            Layout.fillWidth: true
                                                            Text {
                                                            text: LanguageManager.tr3("DISCOVERED GROUPS - ", "DISCOVERED GROUPS - ", "GRUPOS DESCUBIERTOS - ")
                                                                  + root.bsoidEffectiveGroups().length
                                                                  + LanguageManager.tr3(" visiveis", " visible", " visibles")
                                                                  + " · C" + (root.bsoidCampo + 1)
                                                                color: ThemeManager.textSecondary
                                                                font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 1.2
                                                                Behavior on color { ColorAnimation { duration: 150 } }
                                                            }
                                                            Item { Layout.fillWidth: true }
                                                            Text {
                                                                visible: root.bsoidFlowStage === 2
                                                                text: LanguageManager.tr3("Min % cluster:", "Min % cluster:", "Min % cluster:")
                                                                color: ThemeManager.textTertiary; font.pixelSize: 10
                                                            }
                                                            RowLayout {
                                                                visible: root.bsoidFlowStage === 2
                                                                spacing: 4
                                                                Rectangle {
                                                                    width: 22; height: 22; radius: 4
                                                                    color: minPctMinus.containsMouse ? ThemeManager.surfaceHover : ThemeManager.surfaceDim
                                                                    border.color: ThemeManager.border; border.width: 1
                                                                    Text { anchors.centerIn: parent; text: "−"; color: ThemeManager.textPrimary; font.pixelSize: 11; font.weight: Font.Bold }
                                                                    MouseArea {
                                                                        id: minPctMinus
                                                                        anchors.fill: parent
                                                                        hoverEnabled: true
                                                                        cursorShape: Qt.PointingHandCursor
                                                                        onClicked: root.bsoidMinVisibleClusterPct = Math.max(0, root.bsoidMinVisibleClusterPct - 1)
                                                                    }
                                                                }
                                                                Rectangle {
                                                                    width: 30; height: 22; radius: 4
                                                                    color: ThemeManager.surfaceDim
                                                                    border.color: ThemeManager.border; border.width: 1
                                                                    Text {
                                                                        anchors.centerIn: parent
                                                                        text: Math.round(root.bsoidMinVisibleClusterPct)
                                                                        color: ThemeManager.textPrimary
                                                                        font.pixelSize: 10
                                                                        font.weight: Font.Bold
                                                                    }
                                                                }
                                                                Rectangle {
                                                                    width: 22; height: 22; radius: 4
                                                                    color: minPctPlus.containsMouse ? ThemeManager.surfaceHover : ThemeManager.surfaceDim
                                                                    border.color: ThemeManager.border; border.width: 1
                                                                    Text { anchors.centerIn: parent; text: "+"; color: ThemeManager.textPrimary; font.pixelSize: 11; font.weight: Font.Bold }
                                                                    MouseArea {
                                                                        id: minPctPlus
                                                                        anchors.fill: parent
                                                                        hoverEnabled: true
                                                                        cursorShape: Qt.PointingHandCursor
                                                                        onClicked: root.bsoidMinVisibleClusterPct = Math.min(5, root.bsoidMinVisibleClusterPct + 1)
                                                                    }
                                                                }
                                                            }
                                                        }

                                                        // Dica: ver clips antes de nomear
                                                        Rectangle {
                                                            Layout.fillWidth: true; radius: 7
                                                            color: "#120a1e"; border.color: "#4c1d95"; border.width: 1
                                                            implicitHeight: hintRow.implicitHeight + 12
                                                            RowLayout {
                                                                id: hintRow
                                                                anchors { left: parent.left; right: parent.right; margins: 10; verticalCenter: parent.verticalCenter }
                                                                spacing: 8
                                                                Text { text: "\u2139"; font.pixelSize: 13 }
                                                                Text {
                                                                    Layout.fillWidth: true
                                                                    text: LanguageManager.tr3("Use 'Gerar Snippets' no fluxo acima, assista a cada grupo e nomeie o comportamento observado.", "Use 'Generate Snippets' in the flow above, watch each group, and name the observed behavior.", "Use 'Generar Snippets' en el flujo superior, observe cada grupo y nombre el comportamiento observado.")
                                                                    color: "#c4b5fd"; font.pixelSize: 10; wrapMode: Text.WordWrap
                                                                }
                                                            }
                                                        }
                                                        Text {
                                                            Layout.fillWidth: true
                                                            text: LanguageManager.tr3("~ Regra (x%) = regra dominante deste cluster apos alinhamento temporal com Rules. Ex.: '~ Sniffing (49%)' significa que 49% dos frames do cluster coincidem com Sniffing no Rules.", "~ Rule (x%) = dominant rule for this cluster after temporal alignment with Rules. Ex.: '~ Sniffing (49%)' means 49% of cluster frames match Sniffing in Rules.", "~ Regla (x%) = regla dominante de este cluster tras alineacion temporal con Rules. Ej.: '~ Sniffing (49%)' significa que 49% de los frames del cluster coinciden con Sniffing en Rules.")
                                                            color: ThemeManager.textTertiary
                                                            font.pixelSize: 9
                                                            wrapMode: Text.WordWrap
                                                        }

                                                        Repeater {
                                                            id: groupsRepeater
                                                            model: root.bsoidEffectiveGroups()
                                                            delegate: Rectangle {
                                                                id: groupCard
                                                                Layout.fillWidth: true; radius: 8
                                                                implicitHeight: grpCol.implicitHeight + 14
                                                                color: ThemeManager.surface
                                                                border.color: ThemeManager.border; border.width: 1
                                                                Behavior on color { ColorAnimation { duration: 150 } }

                                                                property var grp: modelData
                                                                property color clusterColor: root.bsoidColors[grp.clusterId % root.bsoidColors.length] || ThemeManager.accent
                                                                property int grpIdx: grp._idx
                                                                property string typedName: (root.bsoidGroupNames && root.bsoidGroupNames.length > grpIdx) ? String(root.bsoidGroupNames[grpIdx] || "").trim() : ""
                                                                property int alignedTopRuleId: (root.bsoidClusterTopRule[grp.clusterId] !== undefined) ? root.bsoidClusterTopRule[grp.clusterId] : grp.dominantRule
                                                                property real alignedTopRulePct: (root.bsoidClusterTopPct[grp.clusterId] !== undefined) ? root.bsoidClusterTopPct[grp.clusterId] : 0.0
                                                                property string dominantRuleName: root.bsoidRuleName(alignedTopRuleId)
                                                                property string typedCanonical: root.canonicalBehaviorName(typedName)
                                                                property string dominantCanonical: root.canonicalBehaviorName(dominantRuleName)
                                                                property bool hasTypedName: typedName !== ""
                                                                property bool labelUnknown: hasTypedName && typedCanonical === ""
                                                                property bool labelMismatch: hasTypedName && typedCanonical !== "" && dominantCanonical !== "" && typedCanonical !== dominantCanonical

                                                                ColumnLayout {
                                                                    id: grpCol
                                                                    anchors { left: parent.left; right: parent.right; margins: 10; top: parent.top; topMargin: 7 }
                                                                    spacing: 6

                                                                    RowLayout {
                                                                        spacing: 10
                                                                        Rectangle {
                                                                            width: 12; height: 12; radius: 6
                                                                            color: groupCard.clusterColor
                                                                        }
                                                                        Text {
                                                                text: LanguageManager.tr3("Grupo ", "Group ", "Grupo ") + (grp.clusterId + 1)
                                                                            color: ThemeManager.textPrimary; font.pixelSize: 12; font.weight: Font.Bold
                                                                            Behavior on color { ColorAnimation { duration: 150 } }
                                                                        }
                                                                        Rectangle {
                                                                            Layout.fillWidth: true; height: 6; radius: 3
                                                                            color: ThemeManager.border
                                                                            Behavior on color { ColorAnimation { duration: 150 } }
                                                                            Rectangle {
                                                                                width: parent.width * (grp.percentage / 100)
                                                                                height: parent.height; radius: parent.radius
                                                                                color: groupCard.clusterColor
                                                                                Behavior on width { NumberAnimation { duration: 300 } }
                                                                            }
                                                                        }
                                                                        Text {
                                                                            text: grp.percentage.toFixed(1) + "%"
                                                                            color: ThemeManager.textSecondary; font.pixelSize: 12; font.weight: Font.Bold
                                                                            Behavior on color { ColorAnimation { duration: 150 } }
                                                                        }
                                                                        Text {
                                                                text: "~ " + groupCard.dominantRuleName + " (" + groupCard.alignedTopRulePct.toFixed(0) + "%)"
                                                                            color: ThemeManager.textTertiary; font.pixelSize: 10
                                                                            Behavior on color { ColorAnimation { duration: 150 } }
                                                                        }
                                                                    }

                                                                    // Campo de nomeação do grupo
                                                                    RowLayout {
                                                                        spacing: 6
                                                                        Text {
                                                                            text: LanguageManager.tr3("Nome:", "Name:", "Nombre:")
                                                                            color: ThemeManager.textTertiary; font.pixelSize: 10
                                                                            Behavior on color { ColorAnimation { duration: 150 } }
                                                                        }
                                                                        TextField {
                                                                            id: groupNameField
                                                                            Layout.fillWidth: true; height: 26
                                                                            // Sem binding reativo â€" inicializa uma vez; onTextEdited atualiza o array
                                                                            Component.onCompleted: {
                                                                                text = (root.bsoidGroupNames && root.bsoidGroupNames.length > grpIdx)
                                                                                       ? (root.bsoidGroupNames[grpIdx] || "") : ""
                                                                            }
                                                                            placeholderText: LanguageManager.tr3("Ex.: Exploracao, Repouso, Grooming...", "Ex.: Exploration, Resting, Grooming...", "Ej.: Exploracion, Reposo, Grooming...")
                                                                            color: ThemeManager.textPrimary
                                                                            placeholderTextColor: ThemeManager.textTertiary
                                                                            font.pixelSize: 11
                                                                            leftPadding: 8; rightPadding: 8; topPadding: 4; bottomPadding: 4
                                                                            background: Rectangle {
                                                                                radius: 6; color: ThemeManager.surfaceDim
                                                                                Behavior on color { ColorAnimation { duration: 200 } }
                                                                                border.color: groupCard.labelMismatch ? "#ef4444"
                                                                                           : (groupCard.labelUnknown ? "#f59e0b"
                                                                                              : (groupNameField.activeFocus ? "#7c3aed" : ThemeManager.border))
                                                                                border.width: groupCard.labelMismatch ? 2 : 1
                                                                                Behavior on border.color { ColorAnimation { duration: 150 } }
                                                                            }
                                                                            onTextEdited: {
                                                                                if (root.bsoidGroupNames && root.bsoidGroupNames.length > grpIdx) {
                                                                                    var names = root.bsoidGroupNames.slice()
                                                                                    names[grpIdx] = text
                                                                                    root.bsoidGroupNames = names
                                                                                    var edited = root.bsoidEditedGroups ? root.bsoidEditedGroups.slice() : []
                                                                                    while (edited.length < root.bsoidGroups.length) edited.push(false)
                                                                                    edited[grpIdx] = true
                                                                                    root.bsoidEditedGroups = edited
                                                                                    root.bsoidNamesTypedByUser = true
                                                                                    root.rebuildAgreementMatrixView()
                                                                                }
                                                                            }
                                                                        }
                                                                    }

                                                                    Rectangle {
                                                                        visible: groupCard.labelMismatch || groupCard.labelUnknown
                                                                        Layout.fillWidth: true
                                                                        radius: 6
                                                                        color: groupCard.labelMismatch ? "#2a0f16" : "#2a1f08"
                                                                        border.color: groupCard.labelMismatch ? "#ef4444" : "#f59e0b"
                                                                        border.width: 1
                                                                        implicitHeight: warnTxt.implicitHeight + 10
                                                                        Text {
                                                                            id: warnTxt
                                                                            anchors { left: parent.left; right: parent.right; margins: 8; verticalCenter: parent.verticalCenter }
                                                                            text: groupCard.labelMismatch
                                                                                ? (LanguageManager.tr3("Alerta: nome diverge da regra dominante (", "Warning: label differs from dominant rule (", "Alerta: etiqueta difiere de la regla dominante (")
                                                                                    + groupCard.dominantRuleName + ").")
                                                                                : LanguageManager.tr3("Alerta: nome fora dos comportamentos padrao (Walking, Sniffing, Grooming, Resting, Rearing).", "Warning: label is outside standard behaviors (Walking, Sniffing, Grooming, Resting, Rearing).", "Alerta: etiqueta fuera de comportamientos estandar (Walking, Sniffing, Grooming, Resting, Rearing).")
                                                                            color: groupCard.labelMismatch ? "#fecaca" : "#fde68a"
                                                                            font.pixelSize: 9
                                                                            wrapMode: Text.WordWrap
                                                                        }
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }

                                                    // â"€â"€ Timeline Dupla â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€
                                                    ColumnLayout {
                                                        id: timelineReportCard
                                                        visible: root.bsoidDone && root.bsoidFinalComparisonUnlocked
                                                        Layout.fillWidth: true; spacing: 6

                                                        Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } } }

                                                        Text {
                                                            text: LanguageManager.tr3("TIMELINE - RULES vs B-SOiD", "TIMELINE - RULES vs B-SOiD", "LINEA DE TIEMPO - REGLAS vs B-SOiD")
                                                            color: ThemeManager.textSecondary
                                                            font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 1.2
                                                            Behavior on color { ColorAnimation { duration: 150 } }
                                                        }

                                                        Text {
                                                            Layout.fillWidth: true
                                                            text: LanguageManager.tr3(
                                                                      "Alinhamento automatico: ",
                                                                      "Automatic alignment: ",
                                                                      "Alineacion automatica: "
                                                                  )
                                                                  + root.bsoidAgreementPct.toFixed(1) + "% · "
                                                                  + LanguageManager.tr3("rules cut", "rules cut", "recorte rules") + " "
                                                                  + root.bsoidBestLagFrames + " fr ("
                                                                  + (root.bsoidBestLagFrames / (root.bsoidFps > 0 ? root.bsoidFps : 30.0)).toFixed(2) + " s)"
                                                                  + " · n=" + root.bsoidComparedFrames
                                                            color: ThemeManager.textTertiary
                                                            font.pixelSize: 10
                                                            wrapMode: Text.WordWrap
                                                            Behavior on color { ColorAnimation { duration: 150 } }
                                                        }

                                                        // Linha 1 â€" Regras nativas
                                                        RowLayout {
                                                            Layout.fillWidth: true; spacing: 6
                                                            Text {
                                                                text: LanguageManager.tr3("Regras", "Rules", "Reglas")
                                                                width: 46; color: ThemeManager.textTertiary
                                                                font.pixelSize: 10; verticalAlignment: Text.AlignVCenter
                                                                Behavior on color { ColorAnimation { duration: 150 } }
                                                            }
                                                            BehaviorTimeline {
                                                                id: ruleTimeline
                                                                Layout.fillWidth: true; height: 20
                                                                defaultColor: ThemeManager.border
                                                            }
                                                        }

                                                        // Linha 2 â€" Clusters B-SOiD
                                                        RowLayout {
                                                            Layout.fillWidth: true; spacing: 6
                                                            Text {
                                                                text: "B-SOiD"
                                                                width: 46; color: ThemeManager.textTertiary
                                                                font.pixelSize: 10; verticalAlignment: Text.AlignVCenter
                                                                Behavior on color { ColorAnimation { duration: 150 } }
                                                            }
                                                            BehaviorTimeline {
                                                                id: clusterTimeline
                                                                Layout.fillWidth: true; height: 20
                                                                defaultColor: ThemeManager.border
                                                            }
                                                        }

                                                        // Legenda de cores dos clusters
                                                        Flow {
                                                            Layout.fillWidth: true; spacing: 8
                                                            Repeater {
                                                                model: root.bsoidGroups
                                                                delegate: RowLayout {
                                                                    spacing: 4
                                                                    Rectangle {
                                                                        width: 8; height: 8; radius: 4
                                                                        color: root.bsoidColors[modelData.clusterId % root.bsoidColors.length]
                                                                    }
                                                                    Text {
                                                                        text: "G" + (modelData.clusterId + 1)
                                                                              + " ≈ " + root.bsoidRuleName(
                                                                                    root.bsoidClusterTopRule[modelData.clusterId] !== undefined
                                                                                    ? root.bsoidClusterTopRule[modelData.clusterId]
                                                                                    : modelData.dominantRule
                                                                                )
                                                                              + " (" + (
                                                                                    root.bsoidClusterTopPct[modelData.clusterId] !== undefined
                                                                                    ? root.bsoidClusterTopPct[modelData.clusterId] : 0
                                                                                ).toFixed(0) + "%)"
                                                                        color: ThemeManager.textTertiary; font.pixelSize: 9
                                                                        Behavior on color { ColorAnimation { duration: 150 } }
                                                                    }
                                                                }
                                                            }
                                                        }

                                                    }

                                                    // Matriz de concordância visual: Rules x B-SOiD
                                                    ColumnLayout {
                                                        id: matrixReportCard
                                                        visible: root.bsoidDone && root.bsoidFinalComparisonUnlocked && root.bsoidConfusionRows.length > 0
                                                        Layout.fillWidth: true; spacing: 6

                                                        Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } } }

                                                        Text {
                                                            text: LanguageManager.tr3("MATRIZ DE CONCORDANCIA - Rules x B-SOiD", "AGREEMENT MATRIX - Rules x B-SOiD", "MATRIZ DE CONCORDANCIA - Rules x B-SOiD")
                                                            color: ThemeManager.textSecondary
                                                            font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 1.2
                                                            Behavior on color { ColorAnimation { duration: 150 } }
                                                        }

                                                        Text {
                                                            Layout.fillWidth: true
                                                            text: LanguageManager.tr3("Top-1 medio por regra: ", "Mean top-1 per rule: ", "Top-1 medio por regla: ")
                                                                  + root.bsoidConfusionMacroTop1.toFixed(1) + "%"
                                                                  + " · "
                                                                  + LanguageManager.tr3("ponderado: ", "weighted: ", "ponderado: ")
                                                                  + root.bsoidConfusionWeightedTop1.toFixed(1) + "%"
                                                                  + " · n=" + root.bsoidComparedFrames
                                                            color: ThemeManager.textTertiary
                                                            font.pixelSize: 10
                                                            wrapMode: Text.WordWrap
                                                            Behavior on color { ColorAnimation { duration: 150 } }
                                                        }

                                                        Flickable {
                                                            Layout.fillWidth: true
                                                            Layout.preferredHeight: 178
                                                            clip: true
                                                            contentWidth: matrixColumn.implicitWidth
                                                            contentHeight: matrixColumn.implicitHeight

                                                            Column {
                                                                id: matrixColumn
                                                                spacing: 4

                                                                Row {
                                                                    spacing: 4
                                                                    Rectangle {
                                                                        width: 120; height: 24; radius: 4
                                                                        color: ThemeManager.surfaceDim; border.color: ThemeManager.border; border.width: 1
                                                                        Text {
                                                                            anchors.centerIn: parent
                                                                            text: LanguageManager.tr3("Rule / Group", "Rule / Group", "Regla / Grupo")
                                                                            color: ThemeManager.textTertiary; font.pixelSize: 9; font.weight: Font.Bold
                                                                        }
                                                                    }
                                                                    Repeater {
                                                                        model: root.bsoidConfusionGroups
                                                                        delegate: Rectangle {
                                                                            required property var modelData
                                                                            width: 56; height: 24; radius: 4
                                                                            color: ThemeManager.surfaceDim; border.color: ThemeManager.border; border.width: 1
                                                                            Text {
                                                                                anchors.centerIn: parent
                                                                                text: modelData.shortLabel
                                                                                color: ThemeManager.textSecondary; font.pixelSize: 9; font.weight: Font.Bold
                                                                            }
                                                                        }
                                                                    }
                                                                }

                                                                Repeater {
                                                                    model: root.bsoidConfusionRows
                                                                    delegate: Row {
                                                                        required property var modelData
                                                                        spacing: 4

                                                                        Rectangle {
                                                                            width: 120; height: 24; radius: 4
                                                                            color: ThemeManager.surfaceDim; border.color: ThemeManager.border; border.width: 1
                                                                            Text {
                                                                                anchors.left: parent.left
                                                                                anchors.leftMargin: 6
                                                                                anchors.verticalCenter: parent.verticalCenter
                                                                                text: modelData.ruleName + " (" + modelData.total + ")"
                                                                                color: ThemeManager.textSecondary; font.pixelSize: 9
                                                                            }
                                                                        }

                                                                        Repeater {
                                                                            model: modelData.cells
                                                                            delegate: Rectangle {
                                                                                required property var modelData
                                                                                width: 56; height: 24; radius: 4
                                                                                border.color: ThemeManager.border; border.width: 1
                                                                                property color baseColor: root.bsoidColorByClusterId(modelData.clusterId)
                                                                                property real heat: Math.max(0.0, Math.min(1.0, (modelData.pct || 0.0) / 100.0))
                                                                                color: Qt.rgba(baseColor.r, baseColor.g, baseColor.b, 0.12 + 0.68 * heat)
                                                                                Text {
                                                                                    anchors.centerIn: parent
                                                                                    text: modelData.pct > 0 ? modelData.pct.toFixed(0) + "%" : ""
                                                                                    color: ThemeManager.textPrimary
                                                                                    font.pixelSize: 9
                                                                                }
                                                                            }
                                                                        }
                                                                    }
                                                                }
                                                            }

                                                            ScrollBar.horizontal: ScrollBar {
                                                                policy: ScrollBar.AsNeeded
                                                                contentItem: Rectangle { implicitHeight: 6; radius: 3; color: ThemeManager.border }
                                                                background: Rectangle { color: "transparent" }
                                                            }
                                                        }

                                                        Flow {
                                                            Layout.fillWidth: true; spacing: 8
                                                            Repeater {
                                                                model: root.bsoidConfusionGroups
                                                                delegate: RowLayout {
                                                                    required property var modelData
                                                                    spacing: 4
                                                                    Rectangle {
                                                                        width: 8; height: 8; radius: 4
                                                                        color: modelData.color
                                                                    }
                                                                    Text {
                                                                        text: modelData.shortLabel + " = " + modelData.label
                                                                        color: ThemeManager.textTertiary; font.pixelSize: 9
                                                                        Behavior on color { ColorAnimation { duration: 150 } }
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }

                                                    // Política final de rótulos (segurança)
                                                    ColumnLayout {
                                                        visible: root.bsoidDone && root.bsoidFinalComparisonUnlocked
                                                        Layout.fillWidth: true; spacing: 6

                                                        Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } } }

                                                        Text {
                                                            text: LanguageManager.tr3("ROTULO FINAL - POLITICA DE CONFIANCA", "FINAL LABEL - TRUST POLICY", "ETIQUETA FINAL - POLITICA DE CONFIANZA")
                                                            color: ThemeManager.textSecondary
                                                            font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 1.2
                                                            Behavior on color { ColorAnimation { duration: 150 } }
                                                        }

                                                        Rectangle {
                                                            Layout.fillWidth: true
                                                            radius: 6
                                                            color: "#101a36"
                                                            border.color: "#294586"
                                                            border.width: 1
                                                            implicitHeight: helperTxt.implicitHeight + 12
                                                            Text {
                                                                id: helperTxt
                                                                anchors { left: parent.left; right: parent.right; margins: 8; verticalCenter: parent.verticalCenter }
                                                                text: LanguageManager.tr3("Guia rapido: Somente Rules = mais seguro para conclusao final. Hibrido = usa B-SOiD apenas quando o grupo e consistente (acima do limiar). Exploratorio = prioriza B-SOiD para descobrir padroes novos, mas exige cautela para conclusoes.", "Quick guide: Rules only = safest for final conclusions. Hybrid = uses B-SOiD only when a group is consistent (above threshold). Exploratory = prioritizes B-SOiD to discover new patterns, but use caution for conclusions.", "Guia rapido: Solo Rules = mas seguro para conclusion final. Hibrido = usa B-SOiD solo cuando el grupo es consistente (sobre el umbral). Exploratorio = prioriza B-SOiD para descubrir patrones nuevos, pero requiere cautela para conclusiones.")
                                                                color: "#c7d2fe"
                                                                font.pixelSize: 10
                                                                wrapMode: Text.WordWrap
                                                            }
                                                        }

                                                        RowLayout {
                                                            Layout.fillWidth: true; spacing: 8
                                                            Text {
                                                                text: LanguageManager.tr3("Modo:", "Mode:", "Modo:")
                                                                color: ThemeManager.textTertiary; font.pixelSize: 10
                                                            }
                                                            ComboBox {
                                                                id: decisionModeBox
                                                                Layout.preferredWidth: 260
                                                                model: [
                                                                    { id: "rules_only", name: root.decisionModeLabel("rules_only") },
                                                                    { id: "hybrid_confident", name: root.decisionModeLabel("hybrid_confident") },
                                                                    { id: "bsoid_exploratory", name: root.decisionModeLabel("bsoid_exploratory") }
                                                                ]
                                                                textRole: "name"
                                                                onActivated: {
                                                                    if (currentIndex >= 0 && currentIndex < model.length)
                                                                        root.bsoidDecisionMode = model[currentIndex].id
                                                                }
                                                                Component.onCompleted: {
                                                                    for (var i = 0; i < model.length; i++) {
                                                                        if (model[i].id === root.bsoidDecisionMode) {
                                                                            currentIndex = i
                                                                            break
                                                                        }
                                                                    }
                                                                }
                                                                background: Rectangle {
                                                                    radius: 6
                                                                    color: ThemeManager.surfaceDim
                                                                    border.color: decisionModeBox.activeFocus ? "#7c3aed" : ThemeManager.border
                                                                    border.width: 1
                                                                    Behavior on border.color { ColorAnimation { duration: 120 } }
                                                                }
                                                                contentItem: Text {
                                                                    leftPadding: 10
                                                                    rightPadding: 24
                                                                    text: decisionModeBox.displayText
                                                                    color: ThemeManager.textPrimary
                                                                    font.pixelSize: 11
                                                                    verticalAlignment: Text.AlignVCenter
                                                                    elide: Text.ElideRight
                                                                }
                                                            }

                                                            Text {
                                                                text: LanguageManager.tr3("Limiar de confianca B-SOiD:", "B-SOiD confidence threshold:", "Umbral de confianza B-SOiD:")
                                                                color: ThemeManager.textTertiary; font.pixelSize: 10
                                                            }
                                                            Slider {
                                                                Layout.fillWidth: true
                                                                from: 50; to: 95; stepSize: 1
                                                                value: root.bsoidTrustedThresholdPct
                                                                onValueChanged: root.bsoidTrustedThresholdPct = value
                                                            }
                                                            Text {
                                                                text: Math.round(root.bsoidTrustedThresholdPct) + "%"
                                                                color: ThemeManager.textSecondary; font.pixelSize: 10; font.weight: Font.Bold
                                                            }
                                                        }

                                                        Rectangle {
                                                            Layout.fillWidth: true; radius: 6
                                                            color: "#0f1730"; border.color: "#2b4ea2"; border.width: 1
                                                            implicitHeight: policyTxt.implicitHeight + 10
                                                            Text {
                                                                id: policyTxt
                                                                anchors { left: parent.left; right: parent.right; margins: 8; verticalCenter: parent.verticalCenter }
                                                                text: root.bsoidDecisionMode === "rules_only"
                                                                      ? LanguageManager.tr3("Modo seguro ativo: somente Rules define o rotulo final.", "Safe mode active: only Rules define final labels.", "Modo seguro activo: solo Rules define la etiqueta final.")
                                                                      : (root.bsoidDecisionMode === "hybrid_confident"
                                                                         ? (LanguageManager.tr3("Hibrido ativo: B-SOiD so substitui Rules quando pureza do grupo >= ", "Hybrid active: B-SOiD overrides Rules only when group purity >= ", "Hibrido activo: B-SOiD solo sustituye Rules cuando pureza del grupo >= ")
                                                                            + Math.round(root.bsoidTrustedThresholdPct) + "%.")
                                                                         : LanguageManager.tr3("Exploratorio ativo: rotulo final vem do B-SOiD (usar para descoberta, nao para conclusao final).", "Exploratory active: final label comes from B-SOiD (use for discovery, not final conclusion).", "Exploratorio activo: etiqueta final viene de B-SOiD (usar para descubrimiento, no para conclusion final)."))
                                                                color: "#c7d2fe"; font.pixelSize: 10; wrapMode: Text.WordWrap
                                                            }
                                                        }

                                                        ColumnLayout {
                                                            Layout.fillWidth: true; spacing: 4
                                                            Text {
                                                                text: LanguageManager.tr3("Resumo de rotulos finais (preview):", "Final labels summary (preview):", "Resumen de etiquetas finales (preview):")
                                                                color: ThemeManager.textTertiary; font.pixelSize: 10
                                                            }
                                                            Repeater {
                                                                model: root.bsoidFinalLabelStats
                                                                delegate: RowLayout {
                                                                    required property var modelData
                                                                    Layout.fillWidth: true; spacing: 6
                                                                    Text { text: modelData.name; width: 120; color: ThemeManager.textPrimary; font.pixelSize: 10 }
                                                                    Text { text: modelData.pct.toFixed(1) + "%"; width: 56; color: ThemeManager.textSecondary; font.pixelSize: 10; horizontalAlignment: Text.AlignRight }
                                                                    Text { text: LanguageManager.tr3("bouts ", "bouts ", "bouts ") + modelData.bouts; width: 72; color: ThemeManager.textTertiary; font.pixelSize: 10 }
                                                                    Text {
                                                                        text: LanguageManager.tr3("confianca B-SOiD ", "B-SOiD confidence ", "confianza B-SOiD ") + modelData.trusted.toFixed(0) + "%"
                                                                        color: modelData.trusted >= root.bsoidTrustedThresholdPct ? "#86efac" : "#fca5a5"
                                                                        font.pixelSize: 10
                                                                    }
                                                                    Item { Layout.fillWidth: true }
                                                                }
                                                            }
                                                        }
                                                    }

                                                    // â"€â"€ Extração de Clips de Vídeo â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€
                                                    ColumnLayout {
                                                        visible: false
                                                        Layout.fillWidth: true; spacing: 6

                                                        Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.border; Behavior on color { ColorAnimation { duration: 200 } } }

                                                        Text {
                                                            text: LanguageManager.tr3("VIDEO CLIPS PER GROUP", "VIDEO CLIPS PER GROUP", "CLIPS DE VIDEO POR GRUPO")
                                                            color: ThemeManager.textSecondary
                                                            font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 1.2
                                                            Behavior on color { ColorAnimation { duration: 150 } }
                                                        }

                                                        RowLayout {
                                                            Layout.fillWidth: true; spacing: 8

                                                            Text {
                                                                Layout.fillWidth: true
                                                                text: root.snippetsComplete
                                                                    ? (LanguageManager.tr3("Clipes salvos em: ", "Clips saved at: ", "Clips guardados en: ") + root.snippetsOutDir)
                                                                    : root.snippetsRunning
                                                                        ? (LanguageManager.tr3("Extracting... ", "Extracting... ", "Extrayendo... ") + root.snippetsProgress + "%")
                                                                        : root.snippetsError !== ""
                                                                            ? (LanguageManager.tr3("Warning: ", "Warning: ", "Aviso: ") + root.snippetsError)
                                                                            : LanguageManager.tr3("Extrai ate 3 clipes .mp4 por grupo. Requer ffmpeg.exe no PATH ou na pasta do app. Sem FFmpeg, salva apenas timestamps.csv.", "Extracts up to 3 .mp4 clips per group. Requires ffmpeg.exe in PATH or app folder. Without FFmpeg, only timestamps.csv is saved.", "Extrae hasta 3 clips .mp4 por grupo. Requiere ffmpeg.exe en PATH o en la carpeta de la app. Sin FFmpeg, solo guarda timestamps.csv.")
                                                                color: root.snippetsComplete ? ThemeManager.success
                                                                     : root.snippetsError !== "" ? "#ef4444"
                                                                     : ThemeManager.textTertiary
                                                                font.pixelSize: 10; wrapMode: Text.WordWrap
                                                                Behavior on color { ColorAnimation { duration: 200 } }
                                                            }

                                                            // Abre pasta no Explorer
                                                            Button {
                                                                visible: root.snippetsComplete && !root.snippetsRunning
                                                                text: LanguageManager.tr3("Abrir", "Open", "Abrir")
                                                                onClicked: Qt.openUrlExternally("file:///" + root.snippetsOutDir)
                                                                background: Rectangle {
                                                                    radius: 7
                                                                    color: parent.hovered ? ThemeManager.surfaceHover : ThemeManager.surfaceDim
                                                                    border.color: ThemeManager.border; border.width: 1
                                                                    Behavior on color { ColorAnimation { duration: 150 } }
                                                                }
                                                                contentItem: Text {
                                                                    text: parent.text; color: ThemeManager.textPrimary
                                                                    font.pixelSize: 11; font.weight: Font.Bold
                                                                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                                                                }
                                                                leftPadding: 10; rightPadding: 10; topPadding: 6; bottomPadding: 6
                                                            }

                                                            BusyIndicator {
                                                                visible: root.snippetsRunning
                                                                width: 24; height: 24; running: root.snippetsRunning
                                                            }

                                                            // Barra de progresso dos snippets
                                                            Rectangle {
                                                                visible: root.snippetsRunning
                                                                width: 80; height: 4; radius: 2
                                                                color: ThemeManager.border
                                                                Behavior on color { ColorAnimation { duration: 200 } }
                                                                Rectangle {
                                                                    width: parent.width * (root.snippetsProgress / 100)
                                                                    height: parent.height; radius: parent.radius
                                                                    color: "#2563eb"
                                                                    Behavior on width { NumberAnimation { duration: 200 } }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }

                                            // ── Revisão de Bouts ──────────────────────────────────────────────────
                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 8
                                                Text {
                                                    text: LanguageManager.tr3("Revisao de Bouts", "Bout Review", "Revision de Bouts")
                                                    color: ThemeManager.textSecondary
                                                    font.pixelSize: 10
                                                    font.weight: Font.Bold
                                                    font.letterSpacing: 1.2
                                                }
                                                Item { Layout.fillWidth: true }
                                                Button {
                                                    text: root.showBoutReview
                                                        ? LanguageManager.tr3("Ocultar", "Hide", "Ocultar")
                                                        : LanguageManager.tr3("Mostrar", "Show", "Mostrar")
                                                    onClicked: root.showBoutReview = !root.showBoutReview
                                                    background: Rectangle {
                                                        radius: 7
                                                        color: parent.hovered ? ThemeManager.surfaceHover : ThemeManager.surfaceDim
                                                        border.color: ThemeManager.border
                                                        border.width: 1
                                                    }
                                                    contentItem: Text {
                                                        text: parent.text
                                                        color: ThemeManager.textPrimary
                                                        font.pixelSize: 11
                                                        font.weight: Font.Bold
                                                        horizontalAlignment: Text.AlignHCenter
                                                        verticalAlignment: Text.AlignVCenter
                                                    }
                                                    leftPadding: 12; rightPadding: 12; topPadding: 6; bottomPadding: 6
                                                }
                                            }

                                            Rectangle {
                                                visible: root.showBoutReview
                                                Layout.fillWidth: true; radius: 12
                                                color: ThemeManager.surfaceDim
                                                border.color: ThemeManager.borderLight; border.width: 1
                                                implicitHeight: boutSectionCol.implicitHeight + 24
                                                Behavior on color { ColorAnimation { duration: 150 } }
                                                Behavior on border.color { ColorAnimation { duration: 150 } }

                                                ColumnLayout {
                                                    id: boutSectionCol
                                                    anchors { fill: parent; margins: 12 }
                                                    spacing: 10

                                                    // Cabeçalho
                                                    RowLayout {
                                                        Layout.fillWidth: true
                                                        Text { text: "✎"; font.pixelSize: 20 }
                                                        ColumnLayout {
                                                            spacing: 2
                                                            Text {
                                                                text: LanguageManager.tr3("Revisao de Bouts", "Bout Review", "Revision de Bouts")
                                                                color: ThemeManager.textPrimary; font.pixelSize: 14; font.weight: Font.Bold
                                                                Behavior on color { ColorAnimation { duration: 150 } }
                                                            }
                                                            Text {
                                                                text: LanguageManager.tr3(
                                                                          "Edite labels, divida ou mescle bouts e exporte a revisao",
                                                                          "Edit labels, split or merge bouts and export the review",
                                                                          "Edite etiquetas, divida o fusione bouts y exporte la revision"
                                                                      )
                                                                color: ThemeManager.textSecondary; font.pixelSize: 10
                                                                Behavior on color { ColorAnimation { duration: 150 } }
                                                            }
                                                        }
                                                        Item { Layout.fillWidth: true }

                                                        // Campo selector
                                                        RowLayout {
                                                            spacing: 4
                                                            Repeater {
                                                                model: workArea.activeNumCampos
                                                                delegate: Rectangle {
                                                                    width: 32; height: 26; radius: 5
                                                                    property bool isActive: root._boutCampo === index
                                                                    color: isActive ? "#7a3dab" : ThemeManager.surfaceAlt
                                                                    border.color: isActive ? "#9a5dc8" : ThemeManager.border; border.width: 1
                                                                    Behavior on color { ColorAnimation { duration: 100 } }
                                                                    Text {
                                                                        anchors.centerIn: parent
                                                                        text: "C" + (index + 1)
                                                                        color: parent.isActive ? "white" : ThemeManager.textSecondary
                                                                        font.pixelSize: 10; font.weight: Font.Bold
                                                                    }
                                                                    MouseArea {
                                                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                                        onClicked: root._boutCampo = index
                                                                    }
                                                                }
                                                            }
                                                        }

                                                        // Botão carregar
                                                        Rectangle {
                                                            width: boutLoadText.implicitWidth + 24; height: 28; radius: 6
                                                            color: boutLoadMa.containsMouse ? "#5c2d8a" : "#4a1d7a"
                                                            border.color: "#7a3dab"; border.width: 1
                                                            Behavior on color { ColorAnimation { duration: 100 } }
                                                            Text {
                                                                id: boutLoadText
                                                                anchors.centerIn: parent
                                                                text: LanguageManager.tr3("Carregar Bouts", "Load Bouts", "Cargar Bouts")
                                                                color: "#d4a8ff"; font.pixelSize: 11; font.weight: Font.Bold
                                                            }
                                                            MouseArea {
                                                                id: boutLoadMa; anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                                onClicked: {
                                                                    var frames = liveRecordingTab.getBehaviorFrames(root._boutCampo)
                                                                    if ((!frames || frames.length === 0) && workArea.selectedPath !== "")
                                                                        frames = liveRecordingTab.getBehaviorFramesFromCache(workArea.selectedPath, root._boutCampo)
                                                                    if (!frames || frames.length === 0) {
                                                                        errorToast.show(LanguageManager.tr3("Nenhum dado de bouts salvo para este campo.", "No saved bout data for this field.", "No hay datos de bouts guardados para este campo."))
                                                                        return
                                                                    }
                                                                    boutEditor.frameData = frames
                                                                    boutEditor.fps       = root.bsoidFps > 0 ? root.bsoidFps : 30.0
                                                                    boutEditor.campo     = root._boutCampo
                                                                    boutEditor.experimentPath = workArea.selectedPath
                                                                    boutEditor.sessionLabel   = "session_" + new Date().toISOString().replace(/[:.]/g, "-").substring(0, 19)
                                                                }
                                                            }
                                                        }
                                                    }

                                                    // Panel
                                                    BoutEditorPanel {
                                                        id: boutEditor
                                                        Layout.fillWidth: true
                                                        height: 320
                                                        fps:            30.0
                                                        campo:          root._boutCampo
                                                        experimentPath: workArea.selectedPath

                                                        onExportReady: function(path, content) {
                                                            var xhr = new XMLHttpRequest()
                                                            xhr.open("PUT", "file:///" + path)
                                                            xhr.send(content)
                                                            successToast.show(LanguageManager.tr3("Revisao exportada!", "Review exported!", "Revision exportada!"))
                                                        }
                                                    }
                                                }
                                            }

                                            Item { height: 20 }
                                        }
                                    }
                                }
                            }

                            // ── Tab 3: Dados — Layout aparato-específico
                            DataView {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                tableModel: tableModel
                                workArea: workArea
                            }
                        }
                    }
                }
            }
        }
    }

    // â"€â"€ Diálogo de resultado CC â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€
    CCMetadataDialog {
        id: ccResultDialog
        parent: Overlay.overlay
        anchors.centerIn: parent
    }

    // â"€â"€ Toasts â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€
    Toast { id: successToast; anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 16 } }
    Toast { id: errorToast;   anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 16 } }

    // â"€â"€ Popup delete â€" Passo 1 â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€
    Popup {
        id: deleteStep1Popup
        anchors.centerIn: parent; width: 400
        height: step1Layout.implicitHeight + 56
        modal: true; focus: true; closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle { radius: 14; color: ThemeManager.surface; Behavior on color { ColorAnimation { duration: 200 } } border.color: ThemeManager.borderLight; border.width: 1 }

        ColumnLayout {
            id: step1Layout
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
            spacing: 14
            Text { text: LanguageManager.tr3("Excluir Experimento", "Delete Experiment", "Eliminar Experimento"); color: ThemeManager.textPrimary; font.pixelSize: 16; font.weight: Font.Bold }
            Text {
                Layout.fillWidth: true
                text: LanguageManager.tr3(
                          "Tem certeza que deseja excluir\n\"",
                          "Are you sure you want to delete\n\"",
                          "Seguro que desea eliminar\n\""
                      ) + root.pendingDeleteName + LanguageManager.tr3(
                          "\"?\n\nEsta acao e irreversivel.",
                          "\"?\n\nThis action is irreversible.",
                          "\"?\n\nEsta accion es irreversible."
                      )
                color: ThemeManager.textSecondary; font.pixelSize: 13; wrapMode: Text.WordWrap
            }
            RowLayout {
                Layout.fillWidth: true; spacing: 10; Item { Layout.fillWidth: true }
                GhostButton { text: LanguageManager.tr3("Cancelar", "Cancel", "Cancelar"); onClicked: deleteStep1Popup.close() }
                Button {
                    text: LanguageManager.tr3("Continuar", "Continue", "Continuar")
                    onClicked: { deleteStep1Popup.close(); deleteNameField.text = ""; deleteStep2Popup.open() }
                    background: Rectangle { radius: 7; color: parent.hovered ? ThemeManager.accentHover : ThemeManager.accent; Behavior on color { ColorAnimation { duration: 150 } } }
                    contentItem: Text { text: parent.text; color: ThemeManager.buttonText; font.pixelSize: 12; font.weight: Font.Bold; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    leftPadding: 16; rightPadding: 16; topPadding: 8; bottomPadding: 8
                }
            }
        }
    }

    // â"€â"€ Popup delete â€" Passo 2 â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€
    Popup {
        id: deleteStep2Popup
        anchors.centerIn: parent; width: 420
        height: step2Layout.implicitHeight + 56
        modal: true; focus: true; closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onOpened: deleteNameField.forceActiveFocus()
        background: Rectangle { radius: 14; color: ThemeManager.surface; Behavior on color { ColorAnimation { duration: 200 } } border.color: ThemeManager.accent; border.width: 1 }

        ColumnLayout {
            id: step2Layout
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
            spacing: 14
            Text { text: LanguageManager.tr3("Confirmacao Final", "Final Confirmation", "Confirmacion Final"); color: ThemeManager.textPrimary; font.pixelSize: 16; font.weight: Font.Bold }
            Text { Layout.fillWidth: true; text: LanguageManager.tr3("Para confirmar, digite o nome do experimento:", "To confirm, type the experiment name:", "Para confirmar, escriba el nombre del experimento:"); color: ThemeManager.textSecondary; font.pixelSize: 13; wrapMode: Text.WordWrap }
            Rectangle {
                Layout.fillWidth: true; height: nameLabel.implicitHeight + 10; radius: 5
                color: ThemeManager.surfaceDim; border.color: ThemeManager.borderLight; border.width: 1
                Text {
                    id: nameLabel
                    anchors { verticalCenter: parent.verticalCenter; left: parent.left; right: parent.right; margins: 10 }
                    text: root.pendingDeleteName; color: ThemeManager.textPrimary; font.pixelSize: 13; wrapMode: Text.WrapAnywhere
                }
            }
            TextField {
                id: deleteNameField; Layout.fillWidth: true; placeholderText: root.pendingDeleteName
                color: ThemeManager.textPrimary; placeholderTextColor: ThemeManager.textPlaceholder; font.pixelSize: 13
                leftPadding: 10; rightPadding: 10; topPadding: 8; bottomPadding: 8
                background: Rectangle {
                    radius: 6; color: ThemeManager.surfaceDim; Behavior on color { ColorAnimation { duration: 200 } }
                    border.color: deleteNameField.activeFocus ? ThemeManager.accent : ThemeManager.borderLight; border.width: 1
                }
                Keys.onReturnPressed: {
                    if (text === root.pendingDeleteName) { deleteStep2Popup.close(); ExperimentManager.deleteExperiment(root.pendingDeleteName) }
                }
            }
            RowLayout {
                Layout.fillWidth: true; spacing: 10; Item { Layout.fillWidth: true }
                GhostButton { text: LanguageManager.tr3("Cancelar", "Cancel", "Cancelar"); onClicked: deleteStep2Popup.close() }
                Button {
                    text: LanguageManager.tr3("Excluir Definitivamente", "Delete Permanently", "Eliminar Definitivamente")
                    enabled: deleteNameField.text === root.pendingDeleteName
                    onClicked: { deleteStep2Popup.close(); ExperimentManager.deleteExperiment(root.pendingDeleteName) }
                    background: Rectangle {
                        radius: 7; color: parent.enabled ? (parent.hovered ? ThemeManager.accentHover : ThemeManager.accent) : ThemeManager.surfaceDim
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                    contentItem: Text { text: parent.text; color: ThemeManager.buttonText; font.pixelSize: 12; font.weight: Font.Bold; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    leftPadding: 16; rightPadding: 16; topPadding: 8; bottomPadding: 8
                }
            }
        }
    }
}
