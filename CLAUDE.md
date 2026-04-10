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
            → inferCrop() — Ort::Session.Run() → locref → emit sinais
              → trackReceived / bodyReceived (QueuedConnection → QML)
```

**Pontos críticos da arquitetura:**
- **Headless player + displayPlayer separado**: O `QMediaPlayer` headless (C++) serve frames ao motor de inferência. O vídeo visível no QML é um segundo `MediaPlayer` independente — pode usar hardware acceleration.
- **3 sessões ONNX paralelas**: Uma `Ort::Session` por campo, cada uma rodando em `std::thread` próprio dentro de `processJob()`.
- **Single-slot queue**: `enqueueFrame()` descarta frame anterior pendente — sempre processa o mais recente, evitando backpressure.

## Componentes C++

| Arquivo | Responsabilidade |
|---|---|
| `src/tracking/inference_engine.h/cpp` | QThread dedicada. Cria 3 `Ort::Session`, processa crops em paralelo via `std::thread`, aplica locref sub-pixel |
| `src/tracking/inference_controller.h/cpp` | Orquestrador. `QVideoSink` recebe frames do `QMediaPlayer` headless via `videoFrameChanged`, alimenta InferenceEngine, emite sinais para QML |
| `src/manager/ExperimentManager.cpp/h` | Gestão de experimentos (CRUD, I/O JSON/CSV, `registry.json`) |
| `src/models/ExperimentTableModel.cpp/h` | Modelo de tabela para CSVs (lazy-loading) |
| `src/models/ArenaModel.cpp/h` | Engine de persistência das zonas e polígonos |
| `src/models/ArenaConfigModel.cpp/h` | Modelo de configuração da arena |
| `src/core/main.cpp` | Ponto de entrada e registro de tipos QML |

## QML

| Pasta / Arquivo | Responsabilidade |
|---|---|
| `qml/core/` | Navegação base (`main.qml`, `LandingScreen.qml`, `HomeScreen.qml`), busca universal (`SearchBrowser.qml`), componentes reutilizáveis (`GhostButton.qml`, `Toast.qml`) |
| `qml/shared/` | Funcionalidades comuns: `LiveRecording.qml` (motor de análise + UI de gravação) e `SessionResultDialog.qml` (dados pós-sessão NOR) |
| `qml/nor/` | Fluxo NOR: `NORDashboard.qml`, `ArenaSetup.qml` (zonas + polígonos), `NORSetupScreen.qml`, `ArenaSelection.qml` |
| `qml/ca/` | Fluxo Campo Aberto: `CAArenaSelection.qml` (layout 2/3 campos), `CASetup.qml`, `CADashboard.qml`, `CAMetadataDialog.qml` |

## Modelo ONNX

- **Arquivo:** `Network-MemoryLab-v2.onnx`
- **Input:** `[1, 240, 360, 3]` RGB float32 — sem mean subtraction (modelo já faz)
- **Output 0:** `[1, 30, 46, 2]` scoremap (heatmaps nose/body)
- **Output 1:** `[1, 30, 46, 4]` locref (sub-pixel offsets)
- **Stride:** 8.0
- **Locref stdev:** 7.2801
- **Sem mean subtraction** — o grafo já normaliza internamente

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
- **Campos ativos:** 2 ou 3 (NOR e CA — configurável via `ArenaSelection` / `CAArenaSelection`)
  - Campo 0: `(0, 0)` — Topo-Esquerda
  - Campo 1: `(360, 0)` — Topo-Direita
  - Campo 2: `(0, 240)` — Baixo-Esquerda
- **`numCampos` em CA:** Reutiliza a lógica de 2 ou 3 campos do NOR para consistência. Layout de 1 campo removido para padronizar o pipeline de 3 crops paralelos.
- **Centro/Borda em CA:** O "Centro" é um quadrado central dinâmico definido por `centroRatio`. A "Borda" é a área do chão ao redor deste centro.

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
```

Métodos invocáveis do `InferenceController` (Q_INVOKABLE):
```
startAnalysis(videoPath, modelDir)
stopAnalysis()
setPlaybackRate(rate)   — sincroniza headless player com displayPlayer
position()              — posição atual do headless em ms
seekTo(ms)              — salta headless para posição (usado pelo positionSyncTimer)
```

## Velocidade e Distância (Body Point)

O `LiveRecording` calcula velocidade e distância a partir das coordenadas locais do body point a cada 100 ms:
- **`currentVelocity[campo]`** — m/s na última janela de 100 ms (filtrado: descarta >2 m/s como ruído)
- **`totalDistance[campo]`** — metros acumulados desde o início da sessão
- **`Corpo (Body Tracking)`** — Utilizado exclusivamente para todas as métricas de CA (distância, velocidade, visitas ao centro/borda) para maior estabilidade.
- **`numCampos`** — propriedade que controla quantos campos são ativos (2 ou 3).

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
| `setup_onnx.ps1` executado diretamente sem MSVC | Script deve ser chamado apenas pelo `build.bat`, que ativa o ambiente MSVC correto antes |
| Dupla navegação ao criar experimento CA | `onExperimentCreated` global + Connections interno em `caSetupComponent` ambos disparavam. Corrigido com flag `pendingCaFlow` e remoção do Connections interno |
| Repeater sem acesso a `id` de delegate | `CAMetadataDialog` usava Repeater com campos nomeados inacessíveis externamente. Corrigido com inline `component CampoDataRow` + sinais `animalChanged`/`drogaChanged` atualizando arrays `_animalTexts`/`_drogaTexts` no root |
| 5 cards NOR overflow na janela | 5 × 210px + 4 × 20px = 1130px > 980px. Corrigido reduzindo para 160×250 e spacing 14 (856px total) |
| Integração Arena CA | `ArenaSetup.qml` unificado para NOR e CA. Em CA, oculta edição de pares e ajusta rótulos ("Borda/Centro") |
| Busca Universal | Novo `SearchBrowser.qml` roteia experimentos NOR/CA com base no metadado `aparato` |
| Erro de escopo no SearchBrowser | Atribuição de propriedades de preview falhava por escopo (global property). Corrigido com `id: previewContainer` explícito |
| Erro de Parent no main.qml | `SettingsScreen` (Popup) não suportava `parent: root` (ApplicationWindow). Corrigido para `root.contentItem` |
| Style Customization Warning | Estilo `Default` no Windows restringe customização de botões/popups. Alterado para `Style=Basic` em `qtquickcontrols2.conf` |
| Lógica de Contexto CA | Regra atualizada: Escolha de contexto ("Padrão" vs "Contextual") disponível **apenas** para o layout de 2 campos |
| Padronização de Layouts | Campos de 1 layout removidos para consistência; NOR e CA suportam apenas 2 ou 3 campos |
| Dynamic CA Scaling | Implementado `Alt + MouseWheel` em `ArenaSetup.qml` para ajustar `centroRatio` (persistido no backend) |
| Tracking CA (Body) | Métricas de Campo Aberto migradas de nose para body tracking para maior precisão de ocupação de zona |
| Navigation Filters | `clearFilter()` adicionado ao voltar de experimentos para resetar a busca universal |
| Search Deletion | Adicionado suporte a exclusão (lixeira) diretamente no Universal Search Browser |
