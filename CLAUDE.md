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
    → InferenceController::onVideoFrameChanged 
      → frame.toImage() → convertToFormat(RGB888)
        → InferenceEngine::enqueueFrame (thread-safe, single-slot queue)
          → processJob() — 3 std::threads, uma por campo
            → inferPose() — Ort::Session.Run() → locref → nose/body coords
            → BehaviorScanner::pushFrame (Feature extraction: velocity, distance, rolling windows)
            → inferBehavior() — Ort::Session.Run() (SimBA/B-SOiD logic)
            → emit sinais (trackReceived, bodyReceived, behaviorReceived)
              → QML Update (UI Badges + BehaviorTimeline)
```

- **Dual-Model Inference**: Executa inferência de pose (DLC) seguida de classificação comportamental (SimBA/B-SOiD) no mesmo pipeline C++.
- **Single-slot queue**: `enqueueFrame()` descarta frame anterior pendente — sempre processa o mais recente, evitando backpressure.
- **Auto-loading Behavior.onnx**: Sistema busca nativamente por `Behavior.onnx` na pasta do modelo para ativar classificação automática.

## Componentes C++

| Arquivo | Responsabilidade |
|---|---|
| `src/tracking/inference_engine.h/cpp` | Orquestra 3 sessões de Pose + 1 sessão de Comportamento (compartilhada). Executa inferência de pose em threads paralelas; comportamento em série após pose. |
| `src/tracking/BehaviorScanner.h/cpp` | Extração de features (velocidade, aceleração, médias móveis) para o modelo comportamental. |
| `src/tracking/BehaviorTimeline.h/cpp` | Custom QQuickItem usando Scene Graph (GPU) para renderizar etogramas em tempo real. |
| `src/tracking/inference_controller.h/cpp` | Orquestrador. `QVideoSink` recebe frames, alimenta InferenceEngine, emite sinais (Pose+Behavior) para QML. |
| `src/manager/ExperimentManager.cpp/h` | Gestão de experimentos (I/O, `registry.json`) e Exportação (CSV Tracking + CSV Behavior). |
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

## Modelo de Comportamento ONNX

- **Arquivo:** `Behavior.onnx` (Opcional, busca automática em `appDir/` ou `defaultModelDir/`)
- **Geração:** SimBA `merge_to_onnx` — une N classificadores `.sav` (um por comportamento) em um único ONNX
- **Input:** `[None, 21]` float32 (Features do `BehaviorScanner`)
- **Output:** float tensor `[None, N_classes]` — cada valor é a probabilidade **independente** do comportamento (classificadores binários merged; NÃO somam 1)
- **Sem zipmap** — o `merge_to_onnx` gera float tensor direto, sem label int64 nem ZipMap
- **Threshold de confiança:** `MIN_CONFIDENCE = 0.25f` — adequado para probabilidades de binary merge (usar 0.40+ apenas para softmax multiclasse)

### Features (21) — `BehaviorScanner.cpp`

Mapeamento verificado contra `features_extracted/*.csv` do SimBA (colunas 7–27):

| Índice | Coluna SimBA | Descrição |
|---|---|---|
| 0 | Movement_nose | Deslocamento do nariz (px/frame, **espaço de treino**) |
| 1 | Movement_body | Deslocamento do corpo (px/frame) |
| 2 | All_bp_movements_Animal_1_sum | movNose + movBody |
| 3 | All_bp_movements_Animal_1_mean | movSum / 2 |
| 4 | All_bp_movements_Animal_1_min | min(movNose, movBody) |
| 5 | All_bp_movements_Animal_1_max | max(movNose, movBody) |
| 6–7 | Mean/Sum_..._mean_2 | Rolling mean/sum de **movMean** — janela 2s |
| 8–9 | Mean/Sum_..._mean_5 | Rolling mean/sum de movMean — janela 5s |
| 10–11 | Mean/Sum_..._mean_6 | Rolling mean/sum de movMean — janela 6s |
| 12–13 | Mean/Sum_..._mean_7.5 | Rolling mean/sum de movMean — janela 7.5s |
| 14–15 | Mean/Sum_..._mean_15 | Rolling mean/sum de movMean — janela 15s |
| 16 | Sum_probabilities | nose.p + body.p |
| 17 | Mean_probabilities | (nose.p + body.p) / 2 |
| 18–20 | Low_prob_detections_0.1/0.5/0.75 | **Contagem absoluta** de bodyparts com p abaixo do threshold na janela 1s (max = 2×fps; NÃO é fração) |

> **Escala de coordenadas:** DLC retorna coordenadas no espaço do crop (360×240). SimBA extrai features no espaço do vídeo original. `BehaviorScanner` aplica o fator de escala `TRAINING_W / CROP_W` e `TRAINING_H / CROP_H` (constantes em `BehaviorScanner.h`) para converter antes de calcular os deslocamentos. Ajustar `TRAINING_W/H` conforme o valor em SimBA → "Configure Video Parameters".
>
> **Rolling windows:** SimBA rola sobre `All_bp_movements_Animal_1_mean = (movNose + movBody) / 2`, não sobre a soma. O buffer interno `_movementsSumHist` guarda `movSum / 2.0f`.

## GPU / ONNX Execution Providers

O `InferenceEngine` detecta o fabricante da GPU via **DXGI** e tenta providers em cascata:

- **DXGI** (`IDXGIFactory1`) enumera os adaptadores e lê o `VendorId` (`0x10DE`=NVIDIA, `0x1002`=AMD, `0x8086`=Intel) — chamada única na inicialização, sem overhead durante inferência
- **NVIDIA → CUDA → DirectML → CPU**: tenta CUDA primeiro; se a sessão falhar (ex: CUDA Toolkit/cuDNN não instalados), cai para DirectML; se DirectML falhar, CPU
- **AMD/Intel → DirectML → CPU**: tenta DirectML; se falhar, CPU
- **GPU ativo** (CUDA ou DML): `SetIntraOpNumThreads(1)` — provider gerencia paralelismo
- **CPU fallback**: `SetIntraOpNumThreads(4)` + `ORT_ENABLE_ALL` graph optimization
- **`dxgi.lib` linkado** para detecção de vendor. **`d3d12.lib` NÃO é linkado** — DX12/CUDA são internos ao `onnxruntime.dll`

> **Setup ONNX Runtime:** usar `build.bat` — ele detecta SDK ausente e oferece download automático.  
> O `setup_onnx.ps1` **não deve ser executado diretamente** — o `build.bat` o chama com o ambiente MSVC correto.
> - NVIDIA  → opção 2 (Baixa `onnxruntime-win-x64-gpu` do GitHub)
> - AMD/Intel → opção 1 (Baixa `Microsoft.ML.OnnxRuntime.DirectML` do NuGet)

> **CUDA requer dependências externas ao ORT:** CUDA Toolkit 12.x + cuDNN 9.x instalados separadamente. Sem eles, o provider CUDA falha na criação da sessão e o fallback para DirectML é automático.

### Cascata de providers (`createSession`)

A lógica usa `tryCreateSessions(opts)` — helper que cria as 3 sessões e retorna `false` se qualquer uma falhar, permitindo retry com o próximo provider:

```
NVIDIA detectado → try_add_cuda_provider → tryCreateSessions
  ├── OK  → "Modo GPU: CUDA ativo (NVIDIA)"
  └── FAIL → try_add_dml_provider → tryCreateSessions
               ├── OK  → "Modo GPU: DirectML ativo (NVIDIA, DirectX 12)"
               └── FAIL → CPU opts → tryCreateSessions → "Modo CPU: GPU não disponível"

AMD/Intel detectado → try_add_dml_provider → tryCreateSessions
  ├── OK  → "Modo GPU: DirectML ativo (AMD/Intel, DirectX 12)"
  └── FAIL → CPU opts → "Modo CPU: GPU não disponível"
```

**Alternativa Python (`inference_processor.py`)**: script standalone que usa `onnxruntime` com `CPUExecutionProvider` apenas — serve como referência/gold standard, não integrado ao pipeline C++.

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

1. **`InferenceController::setPlaybackRate(rate)`** — sincroniza headless ao mudar velocidade
2. **Headless capped a 2x** — independente da velocidade de display, o headless nunca ultrapassa 2x, mantendo ONNX num ritmo gerenciável
3. **`positionSyncTimer` (400ms)** — se drift entre `displayPlayer.position` e `inference.position()` ultrapassar 800ms, `inference.seekTo(displayPlayer.position)` ressincroniza o headless

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

### Fluxo Campo Aberto (CA)
O módulo CA reutiliza o mesmo `ExperimentManager` do NOR. Diferenças:
- `createExperimentFull` chamado com strings de pares vazias (`"", "", ""`)
- `pendingCaFlow: bool` em `main.qml` diferencia NOR × CA no handler global `onExperimentCreated`
- `context` pode ser `"Padrão"` ou `"Contextual"` (3 campos força "Sem Contexto" via `CAArenaSelection`)
- `arenaId` segue padrão `"ca_Ncampos"` (ex: `"ca_3campos"`, `"ca_2campos"`, `"ca_1campo"`)
- CSV: `["Diretório do Vídeo", "Animal", "Campo", "Dia", "Distância Total (m)", "Velocidade Média (m/s)"]` + opcional "Droga"
- JSON de sessão: `aparato: "campo_aberto"`, sem bouts de exploração, inclui `porMinuto` com distância e velocidade por minuto

### Fluxo Comportamento Complexo (CC)
Semelhante ao CA, porém voltado para rastreamento genérico de locomoção sem requerer desenho do centro ou objetos.
- Usa a arquitetura de pasta e módulo `cc/`
- JSON de sessão: `aparato: "comportamento_complexo"`, métricas puras de tracker de corpo
- Interface LiveRecording esconde painéis laterais de tempos de zonas automaticamente e muda o título para "EXPLORAÇÃO GERAL"
- Filtro de distância na análise é mais brando (< 10 m/s) para captar toda flutuação e tem toggle `Rastro ON/OFF` para visualização na UI
- **Zonas editáveis**: Em CC, as zonas são arrastáveis e redimensionáveis na ArenaSetup
  - Shift+drag para mover zonas
  - Scroll do mouse para redimensionar
  - Labels "A"/"B" escondidos em CC (visíveis apenas em NOR)
  - Tamanho e posição são salvos e restaurados ao carregar a configuração
  - Zonas também visíveis na aba Gravação (LiveRecording.qml)

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
- ONNX Runtime: pasta `onnxruntime_sdk/` na raiz do projeto (gerada via `qt/scripts/setup_onnx.ps1`)
  - **Uso:** `powershell -ExecutionPolicy Bypass -File scripts\setup_onnx.ps1`
  - Estrutura esperada: `onnxruntime_sdk/include/` (headers) + `onnxruntime_sdk/lib/` (lib + DLLs, incluindo `DirectML.dll`)
- C++17, CMake 3.25+ + NMake
- Build copia DLLs de `onnxruntime_sdk/lib/` para `build/`
- **MSVC 14.4+ obrigatório** (VS 2022 ou superior)
- Libs: `onnxruntime.lib` + `dxgi.lib` (**d3d12.lib NÃO é linkado** — DX12/CUDA são internos ao `onnxruntime.dll`)

## Protocolo QML ↔ C++

Sinais emitidos pelo `InferenceController`:
```
readyReceived()               — modelo carregado
trackReceived(campo, x, y, p) — nose, coords mosaico em pixels
bodyReceived(campo, x, y, p)  — body, coords mosaico em pixels
dimsReceived(w, h)            — resolucao do vídeo
fpsReceived(fps)              — FPS do vídeo
infoReceived(msg)             — status informativo (ex: "Modo CPU: DirectML indisponível")
errorOccurred(msg)            — erro fatal
analyzingChanged()            — bool isAnalyzing
behaviorReceived(campo, label)— classificação de comportamento SimBA/BSOID
```

Métodos invocáveis do `InferenceController` (Q_INVOKABLE):
```
startAnalysis(videoPath, modelDir)
stopAnalysis()
setPlaybackRate(rate)   — sincroniza headless player com displayPlayer
position()              — posição atual do headless em ms
seekTo(ms)              — salta headless para posição (usado pelo positionSyncTimer)
loadBehaviorModel(path) — carrega modelo de comportamento manualmente
```

### Pre-warm de Sessões

O `InferenceController` inicia o carregamento das sessões ONNX **no construtor**, em background, assim que o app abre. Quando o usuário clica "Start Analysis":
- Se sessões já prontas (`m_modelReady && engine.isRunning()`): `readyReceived()` é emitido imediatamente — início instantâneo
- Se ainda carregando: o sinal `modelReady` dispara quando concluído (engine já está rodando)
- Após `stopAnalysis()`: engine para → próximo `startAnalysis()` recarrega sessões normalmente

O `readyReceived()` **não é emitido** durante o pre-warm silencioso (`m_isAnalyzing == false`), evitando sinalização prematura ao QML.

## Velocidade e Distância (Body Point)

O `LiveRecording` calcula velocidade e distância a partir das coordenadas locais do body point a cada 100 ms:
- **`currentVelocity[campo]`** — m/s na última janela de 100 ms (filtrado: descarta >2 m/s como ruído)
- **`totalDistance[campo]`** — metros acumulados desde o início da sessão
- **`arenaWidthM / arenaHeightM`** — dimensões físicas de 1 campo (padrão 0.5 m; ajustar conforme arena real)
- **`perMinuteData[campo]`** — snapshots por minuto: `{min, distM, expA_s, expB_s}`

## Metadados Ricos de Sessão

Ao salvar a sessão (`SessionResultDialog.doInsert`), além das linhas no CSV, é gerado um JSON em:
```
<experimento>/sessions/session_<timestamp>.json
```
Contém: `fase`, `dia`, `videoPath`, por campo → `animal`, `par`, `droga`, bouts de exploração por objeto, DI, `distancia_total_m`, `velocidade_media_ms`, dados por minuto.

## Sistema de Temas (Dark/Light)

O sistema de temas é gerido por dois singletons QML em `qml/core/Theme/`:

- **`ThemeManager.qml`** — expõe todas as cores como propriedades reativas, ex. `ThemeManager.background`, `ThemeManager.textPrimary`. Padrao: dark mode.
- **`ColorPalette.qml`** — define as paletas `darkTheme` e `lightTheme`.
- **`qmldir`** — **obrigatório** registrar ambos como `singleton`. Sem este arquivo, cada componente importando `Theme/` recebe uma instância separada e o toggle não funciona.

**Regras de uso:**
- Todos os elementos de UI estrutural (painéis, cards, textos, botões) devem usar `ThemeManager.*`
- `Behavior on color { ColorAnimation { duration: 150-200 } }` em todo elemento que muda de cor
- **Manter hardcoded** apenas: fundo da área de vídeo (`#05050a`, `#08080f`), cores semânticas de tracking no Canvas (vermelho/azul/verde), overlay badges sobre vídeo, cor de `ffcc00` dev mode

**Toggle:** `SettingsScreen.qml` → `ThemeManager.toggleTheme()`. App sempre inicia em dark mode (`isDarkMode: true` na inicialização).

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
| Redundância de SDK | Bibliotecas movidas para a raiz (fora de `qt/`) para um ambiente de código mais limpo |
| Aba Dados não atualizava | `innerTabs.currentIndex = 1` corrigido para `= 2` (Dados é índice 2, não Gravação) |
| Popup altura cortada | `CampoSelector` e `analysisModePrompt` receberam altura explícita/auto-sizing |
| Fase TR/TT/RA por rato | Unificado: campo `sessaoField` único aplica a mesma fase aos 3 ratos da sessão |
| Toggle de tema não funcionava | `qmldir` ausente em `Theme/` — sem ele `pragma Singleton` é ignorado e cada componente recebe instância separada |
| App iniciava em tema claro | `loadThemePreference()` carregava valor salvo anterior; removido de `Component.onCompleted` para garantir dark mode sempre |
| NVIDIA sem CUDA Toolkit não iniciava análise | `try_add_cuda_provider` não valida CUDA em runtime — a sessão só falha em `Ort::Session(...)`. Resolvido com `tryCreateSessions()` por tentativa: CUDA → DirectML → CPU |
| Exclusão no Browser global falhava | `ExperimentManager::deleteExperiment` aceita contexto; `SearchBrowser` passa contexto do item |
| Pontos da arena sumiam ao arrastar | Implementado clamp (trava) de coordenadas [0, width/height] no `onPositionChanged` |
| `setup_onnx.ps1` executado diretamente sem MSVC | Script deve ser chamado apenas pelo `build.bat`, que ativa o ambiente MSVC correto antes |
| Distância e Tracking zerados em modos sem zonas | `accumulateExploration` abortava cedo em arranjos sem zonas. Reduzido para exigir `zones.length < 6` apenas no `nor`. Layout dinâmico dos botões ajustado. |
| Comportamento SimBA sempre "---" | `bOutputs[0]` lido como `float*` mas é `int64` (sklearn-onnx label). `merge_to_onnx` do SimBA gera float direto — corrigido com detecção de `elemType` em runtime. Silent catch também escondia erros. |
| Inicialização lenta (3+ sessões ONNX no Start) | Pre-warm implementado no construtor do `InferenceController` — sessões carregam em background ao abrir o app; Start Analysis dispara imediatamente. |
| Threshold 0.40 bloqueava binary merge | `merge_to_onnx` gera classificadores binários independentes (não somam 1). Threshold reduzido para 0.25. |
| Classificação sempre "walking" (features erradas) | 3 bugs no `BehaviorScanner`: (1) rolling buffer guardava `movSum` mas SimBA usa `movMean=(movNose+movBody)/2` → features 6–15 chegavam 2× maiores; (2) `Low_prob_detections` implementado como fração [0,1] mas SimBA armazena contagem absoluta por bodypart (max=2×fps); (3) coordenadas em espaço do crop (360 px) mas treino foi em 330 px → escala aplicada via `TRAINING_W/CROP_W`. |
| `merge_to_onnx.py` gerava ONNX inválido (nomes duplicados) | `TreeEnsembleClassifier` tinha o mesmo nome em todos os sub-modelos. Corrigido com `prefix_model()` que renomeia absolutamente todos os nós, tensores e inicializadores antes de mesclar. |
| Softmax uniforme (todos os scores ~0.20) | Valores brutos dos classificadores binários são muito pequenos (0.0–0.3). Softmax de valores próximos de 0 fica uniforme. Corrigido com **temperatura T=0.05** antes do Softmax: `Div(probs_raw, 0.05)` → `Softmax`. |
| Comportamentos trocados na UI (walking aparecia como resting) | Ordem dos BEHAVIORS no `merge_to_onnx.py` era `[walking, sniffing, grooming, resting, rearing]` mas `behaviorNames` no QML era `[Walking, Resting, Rearing, Grooming, Sniffing, Thigmotaxis]`. Corrigido alinhando QML com a ordem do script e removendo Thigmotaxis. |
| B-SOiD retornava "Nenhum dado de features" mesmo após análise | `liveRecordingTab.inference` era `undefined` — IDs QML são escopados ao arquivo do componente e não acessíveis de fora. Corrigido com função pública `LiveRecording::exportBehaviorFeatures()` que delega internamente. |
| Timeline dupla e snippets de vídeo pendentes | Implementados: `BSoidAnalyzer::populateTimelines()` (preenche dois `BehaviorTimeline` de C++), `extractSnippets()` (FFmpeg via QProcess em background thread), UI em CCDashboard com dual timeline + botão "Extrair Clips". |

## ⚠️ Classificação de Comportamento — Rule-Based

O pipeline de classificação comportamental usa **classificação baseada em regras** em C++ (`BehaviorScanner::classifySimple()`). Modelos ONNX do SimBA foram removidos — regras nativas dão mais controle e robustez.

### Regras de Classificação (ordem de prioridade)

1. **Sniffing** (prioridade máxima): Se `hasZones` e focinho dentro de 1.5× raio da zona do objeto → sniffing (independente de velocidade)
2. **Rearing**: Focinho fora do polígono do chão (`_floorPoly`) e corpo ainda dentro → rearing (via ray-casting)
3. **Resting**: `_velocity < 0.05 m/s` → resting
4. **Grooming**: `movBody < 1.5 px/frame` e `movNose > 5.0 px/frame` → grooming
5. **Walking**: `movBody > 2.0 px/frame` ou `roll2sMean > 3.0 px/frame` → walking
6. **Fallback**: resting

> **Sniffing sem zonas**: Se o experimento não tiver objetos configurados, `_zones` fica vazio, `hasZones = false` e sniffing nunca dispara. Correto para CC sem objetos.

### Geometria Recebida do QML

| Método Q_INVOKABLE | Descrição |
|---|---|
| `setZones(campo, zones)` | Zonas de objeto `{x, y, r}` norm 0-1 — usadas para sniffing |
| `setFloorPolygon(campo, points)` | Polígono do chão `{x, y}` norm 0-1 — usado para rearing (ray-casting) |
| `setVelocity(campo, velocity)` | Velocidade em m/s do QML — usado para resting |

### Detalhes de Implementação

- **Velocidade**: Recebida do QML via `InferenceController::setVelocity(campo, velocity)` em m/s
- **Zonas**: Recebidas do QML via `InferenceController::setZones(campo, zones)` — usadas para detecção de sniffing
- **Floor polygon**: Recebido do QML via `InferenceController::setFloorPolygon(campo, points)` — polígono norm 0-1 do chão visível para detecção de rearing
- **isInsideFloor()**: Ray-casting exato espelhando o `isPointInPoly` do QML
- **Threshold de velocidade**: 0.05 m/s — calibrado para ratos em pé mas parados (rearing sem movimento)

## 🔬 B-SOiD — Análise Comportamental Enriquecida (Implementado)

B-SOiD complementa as regras nativas descobrindo padrões comportamentais adicionais de forma não-supervisionada. A arquitetura é **post-session** (roda após a análise terminar, sobre os dados coletados).

### Pipeline B-SOiD

```
Sessão finalizada
  → BehaviorScanner::_frameHistory (features[21] + ruleLabel por frame)
    → LiveRecording::exportBehaviorFeatures(path, campo)  [função pública QML]
      → InferenceController::exportBehaviorFeatures → CSV
        → BSoidAnalyzer::analyze(csvPath, nClusters=7)
          → PCA 21→6 dimensões (método da potência + deflação)
          → K-Means k=7 (K-Means++ init, seed fixo → reproduzível)
          → emit analysisReady(grupos[])
            → populateTimelines(ruleTimeline, clusterTimeline, fps)
              → CCDashboard: timeline dupla (Regras | B-SOiD grupos)
            → BSoidAnalyzer::extractSnippets(videoPath, outDir, fps, 3)
              → <experimento>/bsoid_snippets/grupo_N/clip_M.mp4 + timestamps.csv
```

### Componentes Implementados

| Arquivo | Responsabilidade | Status |
|---|---|---|
| `BehaviorScanner._frameHistory` | Buffer `{frameIdx, features[21], ruleLabel}` por sessão; `reset()` não limpa (só `clearHistory()`) | ✅ Implementado |
| `LiveRecording::exportBehaviorFeatures(path, campo)` | Wrapper público QML que delega ao InferenceController interno (IDs de componente não são acessíveis de fora) | ✅ Implementado |
| `InferenceController::exportBehaviorFeatures` | Exporta CSV com 21 features + rule_label por frame | ✅ Implementado |
| `src/analysis/BSoidAnalyzer.h/cpp` | PCA + K-Means nativo + `populateTimelines()` + `extractSnippets()` | ✅ Implementado |
| `CCDashboard` aba Comportamento | Clusters, timeline dupla (Regras vs B-SOiD), extração de clips de vídeo | ✅ Implementado |

### FrameCluster (mapeamento frame → cluster)

```cpp
struct FrameCluster {
    int frameIdx  = 0;
    int clusterId = 0;
    int ruleLabel = 0;  // resultado de BehaviorScanner::classifySimple()
};
```

### API do BSoidAnalyzer (Q_INVOKABLEs)

| Método | Descrição |
|---|---|
| `analyze(csvPath, nClusters)` | Roda PCA + K-Means em background thread |
| `getFrameMapping()` | Retorna `QVariantList` de `{frameIdx, clusterId, ruleLabel}` |
| `populateTimelines(ruleObj, clusterObj, fps)` | Preenche dois `BehaviorTimeline` diretamente de C++ (mais eficiente que iterar em JS) |
| `extractSnippets(videoPath, outDir, fps, nPerCluster)` | Encontra segmentos contíguos por cluster, extrai clips com FFmpeg (ou salva `timestamps.csv` se FFmpeg ausente) |
| `exportResult(outPath)` | Exporta `frame,cluster` CSV do último clustering |

### Sinais do BSoidAnalyzer

```
progress(int)             — 0–100 durante PCA+K-Means
analysisReady(groups)     — QVariantList de {clusterId, frameCount, percentage, avgMovNose, avgMovBody, dominantRule}
errorOccurred(msg)        — erro durante análise
snippetsProgress(int)     — 0–100 durante extração de clips
snippetsDone(ok, outDir, message) — clip extraction concluída (ou apenas timestamps.csv se sem FFmpeg)
```

### Timeline Dupla (CCDashboard)

Dois `BehaviorTimeline` (Scene Graph GPU) exibidos lado a lado após análise concluída:
- **Linha "Regras"**: cores fixas por comportamento (Verde=Walking, Azul=Sniffing, Rosa=Grooming, Cinza=Resting, Laranja=Rearing)
- **Linha "B-SOiD"**: cores automáticas por cluster (`bsoidColors[]`, até 12 clusters)
- Populados via `bsoidAnalyzer.populateTimelines(ruleTimeline, clusterTimeline, fps)` — chamada de C++ direto, sem iterar em JS

### Snippets de Vídeo por Grupo

```
<experimento>/bsoid_snippets/
  grupo_1/
    clip_1.mp4          — segmento mais longo do cluster (máx. 5s)
    clip_2.mp4
    clip_3.mp4
    timestamps.csv      — start_sec, end_sec, duration_sec (sempre criado)
  grupo_2/
    ...
```

- **Detecção de FFmpeg**: primeiro busca `ffmpeg.exe` na pasta do app, depois no PATH
- **Sem FFmpeg**: cria apenas `timestamps.csv` por grupo com os timestamps dos segmentos
- **Com FFmpeg**: `ffmpeg -ss {start} -i {video} -t {dur} -c:v libx264 -preset ultrafast -crf 28 -an -y {output}`
- **Seleção de segmentos**: segmentos contíguos de mesmo cluster, ordenados por duração decrescente, top 3
## 🪤 Esquiva Inibitória (EI) — Implementado

Paradigma de **memória aversiva passiva** (step-through, passive avoidance) para análise de medo e aprendizado.

### Arquitetura EI

**Fluxo:**
- **Pasta módulo:** `qml/ei/` (EISetup, EIDashboard, EIMetadataDialog)
- **Aparato:** `"esquiva_inibitoria"` (sempre 1 campo)
- **Sequência:** TR (Treino) → E1–E5 (Extinção, dias 2–6) → [RA (Reativação, opcional)] → TT (Teste)
- **Duração:** 5 min/sessão (timer fixo, não escalável)

### Configuração

Em **EISetup.qml**:
- Nome experimento + diretório (opcional)
- ✅ Checkbox: Reativação (default false) — habilita fase RA
- ✅ Checkbox: Drogas (default true) — coluna extra no CSV
- ✅ **SpinBox: Dias de Extinção** (padrão 5, range 1–30) — define quantas sessões E1...EN

Colunas CSV geradas:
```
["Diretório do Vídeo", "Animal", "Fase", "Dia",
 "Latência (s)", "Tempo Plataforma (s)", "Tempo Grade (s)",
 "Bouts Plataforma", "Bouts Grade",
 "Distância Total (m)", "Velocidade Média (m/s)", "Droga" (opcional)]
```

### Métricas

| Métrica | Fonte | Descrição |
|---|---|---|
| **Latência (s)** | `explorationBouts[0][0]` | Tempo até primeiro exit da plataforma |
| **Tempo Plataforma (s)** | `explorationTimes[0]` | Acumulado na zona 0 (plataforma) |
| **Tempo Grade (s)** | `explorationTimes[1]` | Acumulado na zona 1 (grade) |
| **Bouts Plataforma** | `explorationBouts[0].length` | Quantas vezes entrou na plataforma |
| **Bouts Grade** | `explorationBouts[1].length` | Quantas vezes entrou na grade |
| **Distância (m)** | `totalDistance[0]` | Movimento corporal acumulado |
| **Velocidade (m/s)** | `currentVelocity[0]` | Média no período |

### Arena EI

- **Tipo:** Quadrada com 2 zonas editáveis (Shift+drag para mover, scroll para redimensionar)
- **Zona 0:** Plataforma (retângulo pequeno, típico: esquerda)
- **Zona 1:** Grade (retângulo grande, típico: direita)
- **Rastreamento:** Body point (como CA) — zone detection usa ray-casting
- **Sincronização:** Via `ArenaSetup` embebido (igual CC)

### Fases Dinâmicas (EIMetadataDialog)

Botões gerados automaticamente:
```
TR → E1 → E2 → ... → EN → [RA] → TT
```
Onde N = `extincaoDays` (padrão 5).

**Mapeamento Dia:**
- TR → Dia 1
- E1 → Dia 2, E2 → Dia 3, ..., EN → Dia (1+N)
- RA → Dia (1+N+1) — apenas se `hasReactivation`
- TT → Dia (1+N+1) ou (1+N+2) com RA

### LiveRecording para EI

Branch novo em `accumulateExploration()`:
```qml
} else if (aparato === "esquiva_inibitoria") {
    // Zonas editáveis com ray-casting (raio circular)
    // Zona 0 = plataforma, Zona 1 = grade
    // Calcula explorationTimes, explorationBouts como CA
}
```

Sinais para C++:
- `inference.setVelocity(0, currentVelocity[0])` — para classificação de comportamento (opcional)
- Zonas via `setZones(0, zones[0:2])`

### Post-Sessão (EIMetadataDialog)

1. Seleciona fase (botões dinâmicos)
2. Insere animal ID
3. Exibe métricas (read-only)
4. Opcionalmente: Droga (texto livre)
5. "Salvar Sessão" → insere linha em `tracking_data.csv`, salva JSON metadados

JSON metadados:
```json
{
  "fase": "TR",
  "dia": "1",
  "videoPath": "...",
  "animal": "rato_01",
  "latencia_s": 2.5,
  "tempo_plataforma_s": 145.3,
  "tempo_grade_s": 14.7,
  "bouts_plataforma": 3,
  "bouts_grade": 8,
  "distancia_total_m": 12.5,
  "velocidade_media_ms": 0.042,
  "droga": "saline"
}
```
