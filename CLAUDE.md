# MindTrace — Contexto para IA

## Visão Geral

Plataforma C++/Qt 6.11.0 (QML) para tracking comportamental em neurociência. O sistema monitora ratos em até 3 campos simultâneos (mosaico 2×2) usando modelo DeepLabCut exportado em ONNX, executando inferência **nativamente em C++** (sem subprocesso Python).

## Arquitetura

**Stack:** C++17, Qt 6.11.0, ONNX Runtime 1.24.4, QML
**Compatibilidade:** Windows 10/11 (64-bit), MSVC 14.4+ (VS 2022 ou superior)

### Fluxo de Tracking (Pipeline Nativo)

```
QMediaPlayer (headless)
  → QVideoSink::videoFrameChanged (DirectConnection, multimedia thread)
    → DlcController::onVideoFrameChanged
      → frame.toImage() → convertToFormat(RGB888)
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
| `src/tracking/onnx_tracker.h/cpp` | QThread dedicada. Cria 3 `Ort::Session`, processa crops em paralelo via `std::thread`, aplica locref sub-pixel |
| `src/tracking/dlc_controller.h/cpp` | Orquestrador. `QVideoSink` recebe frames do `QMediaPlayer` headless via `videoFrameChanged`, alimenta OnnxTracker, emite sinais para QML |
| `src/manager/ExperimentManager.cpp/h` | Gestão de experimentos (CRUD, I/O JSON/CSV, `registry.json`) |
| `src/models/ExperimentTableModel.cpp/h` | Modelo de tabela para CSVs (lazy-loading) |
| `src/models/ArenaModel.cpp/h` | Engine de persistência das zonas e polígonos |
| `src/models/ArenaConfigModel.cpp/h` | Modelo de configuração da arena |
| `src/core/main.cpp` | Ponto de entrada e registro de tipos QML |

## QML

| Pasta / Arquivo | Responsabilidade |
|---|---|
| `qml/core/` | Navegação base (`main.qml`, `LandingScreen.qml`), componentes reutilizáveis (`GhostButton.qml`, `Toast.qml`) |
| `qml/shared/` | Funcionalidades comuns como `LiveRecording.qml` (Análise) e `SessionResultDialog.qml` (Dados pós-sessão) |
| `qml/nor/` | Fluxo do Reconhecimento de Objetos: `NORDashboard.qml` (Antigo `MainDashboard`), `ArenaSetup.qml`, `NORSetupScreen.qml` |

## Modelo ONNX

- **Arquivo:** `Network-MemoryLab-v2.onnx`
- **Input:** `[1, 240, 360, 3]` RGB float32 — sem mean subtraction (modelo já faz)
- **Output 0:** `[1, 30, 46, 2]` scoremap (heatmaps nose/body)
- **Output 1:** `[1, 30, 46, 4]` locref (sub-pixel offsets)
- **Stride:** 8.0
- **Locref stdev:** 7.2801
- **Sem mean subtraction** — o grafo já normaliza internamente

## GPU / ONNX Execution Providers

O `OnnxTracker` detecta o fabricante da GPU via **DXGI** e roteia para o provider ideal:

- **DXGI** (`IDXGIFactory1`) enumera os adaptadores e lê o `VendorId` (`0x10DE`=NVIDIA, `0x1002`=AMD, `0x8086`=Intel) — chamada única na inicialização, sem overhead durante inferência
- **NVIDIA → CUDA**: requer `onnxruntime-win-x64-gpu-1.24.4` + drivers CUDA. Se o build for o padrão (sem CUDA), cai automaticamente para DirectML
- **AMD/Intel → DirectML**: requer `onnxruntime-win-x64-1.24.4` + DirectX 12 (Win10+)
- **CPU fallback**: ativa quando nenhum provider GPU está disponível
- **GPU ativo** (CUDA ou DML): `SetIntraOpNumThreads(1)` — provider gerencia paralelismo
- **CPU fallback**: `SetIntraOpNumThreads(4)` + `ORT_ENABLE_ALL` graph optimization
- **`dxgi.lib` linkado** para detecção de vendor. **`d3d12.lib` NÃO é linkado** — DX12/CUDA são internos ao `onnxruntime.dll`

> **Build ONNX Runtime:**
> - AMD/Intel → `onnxruntime-win-x64-1.24.4` (DirectML + CPU)
> - NVIDIA     → `onnxruntime-win-x64-gpu-1.24.4` (CUDA + CPU)
> O código detecta o vendor via DXGI; NVIDIA vai para CUDA, outros para DirectML.

### Configuração GPU

```cpp
const GpuVendor vendor = detectGpuVendor(); // DXGI VendorId

if (vendor == GpuVendor::NVIDIA && try_add_cuda_provider(opts)) {
    opts.SetIntraOpNumThreads(1);
    emit infoMsg("Modo GPU: CUDA ativo (NVIDIA)");
} else if (try_add_dml_provider(opts)) {
    opts.SetIntraOpNumThreads(1);
    emit infoMsg(QString("Modo GPU: DirectML ativo (%1, DirectX 12)").arg(gpuName));
} else {
    opts.SetIntraOpNumThreads(4);
    opts.SetGraphOptimizationLevel(ORT_ENABLE_ALL);
    emit infoMsg("Modo CPU: GPU não disponível");
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

## Gestão de Experimentos e Fluxo

### Sistema de Registro e Caminhos Customizados
O `ExperimentManager` utiliza um arquivo `registry.json` na raiz da pasta de dados para rastrear experimentos salvos em diretórios personalizados (fora da pasta padrão "Documentos").
- `createExperimentFull`: Permite especificar um `savePath`.
- `loadAllContexts`: Mescla a pasta padrão com os caminhos registrados no `registry.json`.

### Códigos de Sessão e Metadados de Reativação
O sistema utiliza metadados (`hasReactivation`) para determinar o fluxo de sessões no popup de finalização (`SessionResultDialog.qml`):
- **TR** (Treino): Dia 1.
- **RA** (Reativação): Dia 2 (Habilita dinamicamente o metadado se necessário).
- **TT** (Teste): Dia 2 ou 3 (Auto-detectado com base em `hasReactivation`).

### Compatibilidade Excel
Todos os CSVs são gravados com **UTF-8 BOM** (`\xEF\xBB\xBF`) garantindo visualização perfeita de acentos ("í", "ó") no Microsoft Excel.

## Modos de Análise

| Modo | Input | Timer | Velocidade | Salva vídeo | Autofill Path |
|------|-------|-------|-----------|-------------|---------------|
| **Offline** | Vídeo pré-gravado | Escala com speed | 1x, 2x, 4x | Não | Sim (Automático) |
| **Ao vivo** | Câmera | 1:1 real-time | Fixo 1x | Sim | N/A |

Seleção via popup em `ArenaSetup.qml` ao clicar "Carregar Vídeo".

## Build

```cmd
cd qt && scripts\build.bat
```

- Qt 6.11.0 em `C:\Qt\6.11.0\msvc2022_64` (módulos obrigatórios: Qt Multimedia + Qt Shader Tools)
- ONNX Runtime: `onnxruntime-win-x64-1.24.4` (DirectML/CPU) ou `onnxruntime-win-x64-gpu-1.24.4` (CUDA/CPU)
- C++17, CMake 3.25+ + NMake
- Build copia DLLs: `onnxruntime.dll`, `onnxruntime_providers_shared.dll` (+ `onnxruntime_providers_cuda.dll` se build GPU)
- **MSVC 14.4+ obrigatório** (VS 2022 ou superior)
- Libs: `onnxruntime.lib` + `dxgi.lib` (d3d12.lib/CUDA são internos ao `onnxruntime.dll`)

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
| Tracking sem sincronia | `QVideoSink::videoFrameChanged` entrega frames reais do decoder |
| QAbstractVideoSurface removido (Qt 6) | Substituído por `QVideoSink` + `videoFrameChanged` + `frame.toImage()` |
| Dessincronização em velocidade alta | Dois players independentes acumulam drift — resolvido com headless capped a 2x + `positionSyncTimer` (400ms) + stop-seek-play na troca de velocidade |
| Suporte Windows 7 removido | Requer Windows 10/11 (DirectX 12 nativo). Qt 6.11.0 + ONNX Runtime 1.24.4 |
| Caracteres especiais no Excel | Injeção de UTF-8 BOM (\xEF\xBB\xBF) na escrita dos CSVs |
| Armazenamento rígido | Implementado registry.json para permitir salvar experimentos em diretórios customizados |
| Complexidade de diretórios | Organização de QML e SRC em subpastas core/shared/nor/models para escalabilidade |
