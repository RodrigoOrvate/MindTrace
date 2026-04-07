# MindTrace — Contexto para IA

## Visão Geral

Plataforma C++/Qt5.12 (QML) para tracking comportamental em neurociência. O sistema monitora ratos em até 3 campos simultâneos (mosaico 2×2) usando modelo DeepLabCut exportado em ONNX, executando inferência **nativamente em C++** (sem subprocesso Python).

## Arquitetura

**Stack:** C++17, Qt 5.12.12 LTS, ONNX Runtime 1.16.3, QML
**Compatibilidade:** Windows 7 (Qt 5.12 LTS), MSVC 14.2+ (VS 2019+)

### Fluxo de Tracking (Pipeline Nativo)

```
QMediaPlayer (headless)
  → FrameCaptureSurface (QAbstractVideoSurface) — força decodificação em CPU, sem DXVA
    → frameReady signal (DirectConnection)
      → DlcController::onFrameCaptured
        → OnnxTracker::enqueueFrame (thread-safe, single-slot queue)
          → processJob() — 3 std::threads, uma por campo
            → inferCrop() — Ort::Session.Run() → locref → emit sinais
              → trackReceived / bodyReceived (QueuedConnection → QML)
```

**Pontos críticos da arquitetura:**
- **Headless player + displayPlayer separado**: O `QMediaPlayer` headless (C++) serve frames ao tracker. O vídeo visível no QML é um segundo `MediaPlayer` independente — pode usar hardware acceleration.
- **3 sessões ONNX paralelas**: Uma `Ort::Session` por campo, cada uma rodando em `std::thread` próprio dentro de `processJob()`.
- **Single-slot queue**: `enqueueFrame()` descarta frame anterior pendente — sempre processa o mais recente, evitando backpressure.

## Componentes C++

| Arquivo | Responsabilidade |
|---|---|
| `src/onnx_tracker.h/cpp` | QThread dedicada. Cria 3 `Ort::Session`, processa crops em paralelo via `std::thread`, aplica locref sub-pixel |
| `src/dlc_controller.h/cpp` | Orquestrador. FrameCaptureSurface captura frames do QMediaPlayer headless, alimenta OnnxTracker, emite sinais para QML |
| `src/ExperimentManager.cpp/h` | Gestão de experimentos (CRUD, I/O JSON/CSV) |
| `src/ExperimentTableModel.cpp/h` | Modelo de tabela para CSVs (lazy-loading) |
| `src/ArenaModel.cpp/h` | Engine de persistência das zonas e polígonos |
| `src/ArenaConfigModel.cpp/h` | Modelo de configuração da arena |

## QML

| Arquivo | Responsabilidade |
|---|---|
| `qml/LiveRecording.qml` | Tela de análise — Canvas overlay (skeleton body→nose + pontos), timer 300s por campo, zona de exploração, velocidade 1x–16x |
| `qml/ArenaSetup.qml` | Configuração da arena — zonas arrastáveis (Shift+drag), polígonos 3D (Ctrl/Alt+drag), seleção de modo offline/ao vivo |

## Modelo ONNX

- **Arquivo:** `Network-MemoryLab-v2.onnx`
- **Input:** `[1, 240, 360, 3]` RGB float32 — sem mean subtraction (modelo já faz)
- **Output 0:** `[1, 30, 46, 2]` scoremap (heatmaps nose/body)
- **Output 1:** `[1, 30, 46, 4]` locref (sub-pixel offsets)
- **Stride:** 8.0
- **Locref stdev:** 7.2801
- **Sem mean subtraction** — o grafo já normaliza internamente

## GPU / ONNX Execution Providers

O `OnnxTracker` tenta **DirectML** (DirectX 12) primeiro e cai para CPU automaticamente:

- **`onnx_tracker.cpp`**: `OrtSessionOptionsAppendExecutionProvider_DML(opts, 0)` tenta GPU primeiro
- **Fallback automático para CPU** se DirectML falhar — resultado visível no log via `infoMsg`
- **GPU ativo**: `SetIntraOpNumThreads(1)` — DML gerencia paralelismo internamente
- **CPU fallback**: `SetIntraOpNumThreads(2)` + `ORT_ENABLE_ALL` graph optimization
- **`d3d12.lib` NÃO é linkado** no executável — DX12 é carregado internamente pelo `onnxruntime.dll`. Linkar `d3d12.lib` causava falha de carregamento no Windows 7 (sem `d3d12.dll` no sistema)
- **DLLs DirectML prontas**: pasta `directml_x64/` contém `onnxruntime.dll` com DirectML baked-in
- **Build atual**: usa `onnxruntime-win-x64-1.16.3` bundle padrão

> **Windows 7 / GPU Kepler (K2000):** DirectML requer DX12 — indisponível no Windows 7 e em GPUs Kepler. O sistema cai para CPU automaticamente e emite `"Modo CPU: DirectML indisponível"` no log.

### Configuração GPU

```cpp
bool gpuOk = try_add_gpu_provider(opts);
if (gpuOk) {
    opts.SetIntraOpNumThreads(1);
    emit infoMsg("Modo GPU: DirectML ativo (DirectX 12)");
} else {
    opts.SetIntraOpNumThreads(2);
    opts.SetGraphOptimizationLevel(ORT_ENABLE_ALL);
    emit infoMsg("Modo CPU: DirectML indisponível (Windows 7 ou GPU sem DX12)");
}
```

**Alternativa Python (`dlc_processor.py`)**: script standalone que usa `onnxruntime` com `CPUExecutionProvider` apenas — serve como referência/gold standard, não integrado ao pipeline C++.

## Velocidade de Reprodução

Controle de velocidade funciona **apenas no modo offline** (vídeo pré-gravado):

- **Opções**: 1x, 2x, 4x — x8/x16 removidos (ONNX CPU ~60-120ms/frame; a x8+ lag >600ms)
- **Visível apenas quando** `isOffline === true` (i.e., `analysisMode === "offline"`)
- **Modo ao vivo**: usa 1:1 (tempo real) — botões de velocidade ocultos

### Timer de Sessão e Velocidade

```qml
var decrement = recordingRoot.isOffline ? Math.round(recordingRoot.playbackRate) : 1
```

- Cada campo tem timer independente de **300s** (5 min)
- **Offline**: decremento escala com `playbackRate` (1s real = 4s vídeo a 4x)
  - 1x → 300s reais para completar
  - 4x → 75s reais para completar
- **Ao vivo**: decremento = 1 (sempre 1:1 com tempo real)
- **Auto-encerra** quando todos os 3 campos concluem

### Sincronização Display ↔ Headless

Dois players independentes acumulam drift ao longo do tempo. Solução em três camadas:

1. **`DlcController::setPlaybackRate(rate)`** — sincroniza headless ao mudar velocidade
2. **Headless capped a 2x** — independente da velocidade de display, o headless nunca ultrapassa 2x, mantendo ONNX num ritmo gerenciável
3. **`positionSyncTimer` (400ms)** — se drift entre `displayPlayer.position` e `dlc.position()` ultrapassar 800ms, `dlc.seekTo(displayPlayer.position)` ressincroniza o headless

Mudança de velocidade usa **stop → setRate → seek → play** no `displayPlayer` para evitar frame preto do WMF durante transição.

## Mosaico 2×2

- **Resolução:** 720×480
- **FPS:** ~29.97
- **Campos ativos:** 3
  - Campo 0: `(0, 0)` — Topo-Esquerda
  - Campo 1: `(360, 0)` — Topo-Direita
  - Campo 2: `(0, 240)` — Baixo-Esquerda
- **Crop:** cada campo = 360×240 → resize para 360×240 do modelo

## Modos de Análise

| Modo | Input | Timer | Velocidade | Salva vídeo |
|------|-------|-------|-----------|-------------|
| **Offline** | Vídeo pré-gravado | Escala com speed | 1x, 2x, 4x | Não |
| **Ao vivo** | Câmera | 1:1 real-time | Fixo 1x | Sim (diretório configurável) |

Seleção via popup em `ArenaSetup.qml:166-272` ao clicar "Carregar Vídeo".

## Build

```cmd
cd qt && scripts\build.bat
```

- Qt 5.12.12 em `C:\Qt\Qt5.12.12`
- ONNX Runtime: `onnxruntime-win-x64-1.16.3` (bundled)
- C++17, CMake + NMake
- Build copia DLLs: `onnxruntime.dll`, `onnxruntime_providers_shared.dll`
- **MSVC 14.2+ obrigatório** (VS 2019+) — ONNX Runtime API usa `constexpr`
- Libs: `onnxruntime.lib` (apenas — `d3d12.lib` removido; DX12 é interno ao `onnxruntime.dll`)

## Protocolo QML ↔ C++

Sinais emitidos pelo `DlcController`:
```
readyReceived()               — modelo carregado
trackReceived(campo, x, y, p) — nose, coords mosaico em pixels
bodyReceived(campo, x, y, p)  — body, coords mosaico em pixels
dimsReceived(w, h)            — resolucao do vídeo
fpsReceived(fps)              — FPS do vídeo
infoReceived(msg)             — status informativo (ex: "Modo CPU: DirectML indisponível")
errorOccurred(msg)            — erro fatal
analyzingChanged()            — bool isAnalyzing
```

Métodos invocáveis do `DlcController` (Q_INVOKABLE):
```
startAnalysis(videoPath, modelDir)
stopAnalysis()
setPlaybackRate(rate)   — sincroniza headless player com displayPlayer
position()              — posição atual do headless em ms
seekTo(ms)              — salta headless para posição (usado pelo positionSyncTimer)
```

## Histórico de Problemas

| Problema | Solução |
|---|---|
| Double mean subtraction | Modelo já normaliza — não subtrair mean |
| Julia VideoIO vs OpenCV | Removido Julia, tudo via QMediaPlayer |
| Subprocesso Python lento | ONNX nativo C++ — sem subprocesso |
| `GetInputName` não existe | Usar `GetInputNameAllocated` (ONNX 1.16+) |
| Tracking sem sincronia | FrameCaptureSurface nativo garante frames reais do vídeo |
| Dessincronização em velocidade alta | Dois players independentes acumulam drift — resolvido com headless capped a 2x + `positionSyncTimer` (400ms) + stop-seek-play na troca de velocidade |
| DirectML causava crash no Windows 7 | `d3d12.lib` removido do executável; DX12 é interno ao `onnxruntime.dll`. Fallback CPU emite `infoReceived` com diagnóstico |
