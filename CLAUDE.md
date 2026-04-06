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
| `qml/LiveRecording.qml` | Tela de tracking ao vivo — Canvas overlay (skeleton body→nose + pontos), timer 300s por campo, zona de exploração |

## Modelo ONNX

- **Arquivo:** `Network-MemoryLab-v2.onnx`
- **Input:** `[1, 240, 360, 3]` RGB float32 — sem mean subtraction (modelo já faz)
- **Output 0:** `[1, 30, 46, 2]` scoremap (heatmaps nose/body)
- **Output 1:** `[1, 30, 46, 4]` locref (sub-pixel offsets)
- **Stride:** 8.0
- **Locref stdev:** 7.2801
- **Sem mean subtraction** — o grafo já normaliza internamente

## Mosaico 2×2

- **Resolução:** 720×480
- **FPS:** ~29.97
- **Campos ativos:** 3
  - Campo 0: `(0, 0)` — Topo-Esquerda
  - Campo 1: `(360, 0)` — Topo-Direita
  - Campo 2: `(0, 240)` — Baixo-Esquerda
- **Crop:** cada campo = 360×240 → resize para 360×240 do modelo

## Build

```cmd
cd qt && scripts\build.bat
```

- Qt 5.12.12 em `C:\Qt\Qt5.12.12`
- ONNX Runtime: `onnxruntime-win-x64-1.16.3` (bundled)
- C++17, CMake + NMake
- Build copia DLLs: `onnxruntime.dll`, `onnxruntime_providers_shared.dll`
- **MSVC 14.2+ obrigatório** (VS 2019+) — ONNX Runtime API usa `constexpr`

## Protocolo QML ↔ C++

Sinais emitidos pelo `DlcController`:
```
readyReceived()               — modelo carregado
trackReceived(campo, x, y, p) — nose, coords mosaico em pixels
bodyReceived(campo, x, y, p)  — body, coords mosaico em pixels
dimsReceived(w, h)            — resolucao do vídeo
fpsReceived(fps)              — FPS do vídeo
errorOccurred(msg)            — erro fatal
analyzingChanged()            — bool isAnalyzing
```

## Histórico de Problemas

| Problema | Solução |
|---|---|
| Double mean subtraction | Modelo já normaliza — não subtrair mean |
| Julia VideoIO vs OpenCV | Removido Julia, tudo via QMediaPlayer |
| Subprocesso Python lento | ONNX nativo C++ — sem subprocesso |
| `GetInputName` não existe | Usar `GetInputNameAllocated` (ONNX 1.16+) |
| Tracking sem sincronia | FrameCaptureSurface nativo garante frames reais do vídeo |
