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
| `qml/shared/` | Funcionalidades comuns: `LiveRecording.qml` (Análise), `SessionResultDialog.qml` (Dados pós-sessão), **Data Views por aparato** (`DataView.qml`, `NORDataView.qml`, `CADataView.qml`, `CCDataView.qml`, `EIDataView.qml`, `GenericDataView.qml`), **`BoutEditorPanel.qml`** (revisão post-sessão de bouts) |
| `qml/nor/` | Fluxo do Reconhecimento de Objetos: `NORDashboard.qml` (Antigo `MainDashboard`), `ArenaSetup.qml`, `NORSetupScreen.qml` |
| `qml/ca/` | Fluxo do Campo Aberto: `CADashboard.qml`, `CAArenaSelection.qml`, `CASetup.qml`, `CAMetadataDialog.qml` |
| `qml/cc/` | Fluxo do Comportamento Complexo: `CCDashboard.qml`, `CCArenaSelection.qml`, `CCSetup.qml`, `CCMetadataDialog.qml` |
| `qml/ei/` | Fluxo da Esquiva Inibitória: `EIDashboard.qml`, `EISetup.qml`, `EIMetadataDialog.qml` |

### Câmera padrão (modo ao vivo)

- Definida em `SettingsScreen.qml` e persistida em `mindtrace_settings.json` como `defaultLiveCameraId`.
- Ao confirmar "Carregar Vídeo" no modo ao vivo, `ArenaSetup.qml` e `EIArenaSetup.qml` tentam aplicar a câmera padrão automaticamente.
- Se a câmera padrão não estiver disponível, o app abre o popup de seleção normalmente.

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
getBehaviorFrames(campo) — retorna [{frameIdx, ruleLabel, movNose, movBody, movMean}] para BoutEditorPanel
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

## Data Views Aparato-Específicos (Aba "Dados" em cada Dashboard)

Cada dashboard (NOR, CA, CC, EI) possui uma aba "Dados" que exibe os resultados experimentais com **detecção automática de aparato** e **theming específico por tipo**.

### Arquitetura de Componentes

| Componente | Responsabilidade |
|---|---|
| **`DataView.qml`** | Roteador inteligente — escaneia headers CSV, detecta aparato, renderiza view apropriada |
| **`NORDataView.qml`** | Reconhecimento de Objetos — tema vermelho (#ab3d4c), colunas: Vídeo, Animal, Campo, Dia, Par de Objetos, Tratamento |
| **`CADataView.qml`** | Campo Aberto — tema azul (#3d7aab), colunas: Animal, Campo, Dia, Distância (m), Velocidade (m/s), Tratamento |
| **`CCDataView.qml`** | Comportamento Complexo — tema roxo (#7a3dab), colunas de locomoção e velocidade |
| **`EIDataView.qml`** | Esquiva Inibitória — tema amarelo (#c8a000), colunas com metrics de latência/plataforma/grade com color-coding |
| **`GenericDataView.qml`** | Fallback — tema neutro para aparatos não-reconhecidos |

### Detecção Automática de Aparato

O componente `DataView` escaneia os headers da tabela CSV procurando por palavras-chave:

| Headers Detectados | Aparato Inferido | View Renderizada | Cor Primária |
|---|---|---|---|
| `"Par de Objetos"` | **NOR** | `NORDataView` | Vermelho (#ab3d4c) |
| `"Latência"` ou `"Tempo Plataforma"` | **EI** | `EIDataView` | Amarelo (#c8a000) |
| `"Duração"` (sem "Par") | **CC** | `CCDataView` | Roxo (#7a3dab) |
| `"Distância Total"` | **CA** | `CADataView` | Azul (#3d7aab) |
| Outro | **Genérico** | `GenericDataView` | Cinza |

### Padrão de Integração em Dashboards

Todas as abas "Dados" usam o mesmo padrão simples:

```qml
// -- Tab N: Dados -- Layout aparato-especifico
DataView {
    anchors.fill: parent
    tableModel: tableModel
    workArea: workArea
}
```

O componente `DataView` automaticamente:
1. Lê headers do `tableModel`
2. Identifica o aparato
3. Renderiza a view correspondente com cores, layout e legendas apropriadas

### Features Comuns a Todas as Views

✓ Headers temáticos com cor primária do aparato  
✓ Linhas alternadas com cor light do aparato para melhor legibilidade  
✓ BusyIndicator durante carregamento de dados  
✓ Botões "Exportar" (verde) e "Salvar" (aparato-specific color)  
✓ Row count display  
✓ Edição de células (TextInput)  
✓ ScrollBars com styling customizado  
✓ Toast feedback pós-ação  
✓ Legends descritivas (ex: "Métricas de Campo Aberto")  

### Color-Coding em EI (Exemplo Avançado)

A view `EIDataView` implementa color-coding semântico para métricas críticas:

| Métrica | Cor | Significado |
|---|---|---|
| **Latência** | Vermelho (#d9534f) | Tempo até 1º exit (risco/aversão) |
| **Tempo Plataforma** | Verde (#5cb85c) | Segurança/permanência |
| **Tempo Grade** | Azul (#0275d8) | Castigo/aversão |

Cada métrica colorida em sua célula de dados, facilitando interpretação rápida de resultados.

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
| Exportação XLSX falhando no Google Drive | Substituído SpreadsheetML/HTML nativo para um backend C++ que gera o CSV puro seguido do script `formatar_mindtrace.py` usando pacote embutido `zipfile/xml` para gerar `.xlsx` nativo nativamente (Sem instalação do Pandas ou `openpyxl`). |
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
| Sistema de dias rígido (TR/RA/TT hardcoded) | Substituído por `dayNames: var[]` definido no setup via editor de chips. Salvo em `metadata.json` via `updateDayNames()`. Diálogos pós-sessão usam ComboBox. Fallback automático para experimentos antigos. |
| "Droga" em formulários e CSVs | Renomeado para "Tratamento" em todos os 4 tipos de experimento (setup screens + metadata dialogs). |
| "Zona de objetos" em CCSetup | Renomeado para "Sniffing" (checkbox que habilita detecção de sniffing vs resting). |
| `dayNames` não aparecia nos diálogos pós-sessão | `readMetadataFromPath()` e `readMetadata()` em C++ nunca incluíam `dayNames` no mapa de retorno — campo era escrito por `updateDayNames()` mas ignorado na leitura. Adicionado parsing do array `dayNames` em ambas as funções antes de `return result`. |
| Nomes de dias corrompidos (ex: "Teste2"→"Teste", "Treino-2"→"Treino") | `dayNameUtils.js` aplicava Levenshtein fuzzy matching com distância ≤2 contra nomes canônicos. Removido completamente o fuzzy matching; apenas E+dígitos (E1, E2…) e códigos de exatamente 2 letras ficam em uppercase. |
| Popups pós-sessão inconsistentes (CA achatado, EI com métricas inline, NOR sem controle de campos) | `SessionResultDialog` (NOR), `CAMetadataDialog` e `EIMetadataDialog` reescritos no padrão CC-style: `CampoBlock` inline com badge + stats + campos Animal/Tratamento, altura dinâmica (`mainLayout.implicitHeight + 48`). Cores: NOR=#ab3d4c, CA=#3d7aab, CC=#7a3dab, EI=#c8a000 (amarelo). |
| Botão "Novo Experimento" aparecia no NORDashboard após criar experimento | Bloco do botão removido do sidebar do `NORDashboard.qml`. |
| Campo 3 visível em NOR com 2 campos ativos | `SessionResultDialog` não tinha propriedade `numCampos`. Adicionado `property int numCampos: 3` com `visible: root.numCampos >= N` nos CampoBlocks; `NORDashboard` passa `numCampos: workArea.activeNumCampos`. |
| "Campo 3:" negrito no popup de editar pares NOR | `font.weight: Font.Bold` acidentalmente adicionado em `ArenaSetup.qml` — removido. |
| `sessionEnded` emitido duas vezes (popup abria e fechava) | Timer em `LiveRecording` disparava `sessionEnded()` depois que `onMediaStatusChanged` já havia encerrado a sessão. Adicionado guard `recordingRoot.isAnalyzing` dentro dos `Qt.callLater()` em ambos os handlers de fim de vídeo. |
| Fim de vídeo não disparava popup (CA, EI) | `onMediaStatusChanged` e `onPlaybackStateChanged` chamavam `stopSession()` diretamente de dentro do handler do `displayPlayer`, causando re-entrância no MediaPlayer Qt. Corrigido com `Qt.callLater()` nos dois handlers — execução adiada para após o estado do player ser finalizado. |
| `timerStarted` resetado para inactive campos em experimentos 1/2-campo | Em `startSession()`, a linha `timerStarted = [false, false, false]` após o bloco de inicialização de campos inativos desfazia os valores corretos. Linha duplicada removida. |
| Tema EI azul em vez de amarelo | `EIDashboard.qml`, `EISetup.qml` e `EIDataView` (XLSX export via `formatar_mindtrace.py`) usavam `#3d7aab` (azul). Todos os elementos de UI de EI alterados para amarelo (`#c8a000`/`#e0b800`/`#9a7800`). Excel EI atualizado de `FF2F7A4B` (verde) para `FFC8A000` (amarelo). |
| Botão "Salvar Configuração" do CA aparecia amarelo | `EIArenaSetup.qml` tinha cores hardcoded `#c8a000`/`#9a7800`; CA e CC o reutilizam para modo 1-campo. Adicionadas props `primaryColor`/`secondaryColor`; CA passa `#3d7aab`/`#2d5f8a`, CC passa `#7a3dab`/`#6a2d9a`. |
| Popup pós-sessão não aparecia ao fim do vídeo (CA/CC/EI) | Race condition: `onAnalyzingChanged` (sinal C++ assíncrono) setava `isAnalyzing = false` antes dos closures `Qt.callLater` rodarem, bloqueando o popup. Corrigido com `_guardedSessionEnded()` (flag `_sessionEndedEmitted`) e `_manualStopRequested` para distinguir stop manual de fim natural. |
| Aba Dados EI com cor verde em vez de amarelo | `EIDataView.qml` tinha `accentColor: "#2f7a4b"` (verde). Alterado para `"#c8a000"` (amarelo). |
| Popup EI nunca aparecia (mesmo com vídeo terminado) | `EIMetadataDialog` estava com `parent: root` (Item do dashboard) em vez de `parent: Overlay.overlay`. Corrigido para `Overlay.overlay` + `anchors.centerIn: parent`. |
| Impossível reaproveitar configuração de arena entre experimentos | Implementada função **Importar Arena** em `ArenaSetup.qml` e `EIArenaSetup.qml`: lê config do experimento fonte via `ArenaConfigModel`, detecta shape (quadrada/retangular por bounding-box ratio) e tipo de zona (`zoneCount≥4`=objetos, `floorPoints≥8`=plataforma_grade, else=padrão), exibe popup de aviso se incompatível, confirma → recarrega config. |
| Ícones sumindo após implementação de traduções | Emoji de 4 bytes (ex: 🧠, 📋) corrompidos por double-UTF-8 ao editar arquivos com encoding errado. Corrigido com replacement binário exato por arquivo. Smart quotes (U+201C/U+201D) introduzidas como delimitadores de string causavam parse error; substituídas por ASCII `"` em todos os QML. |
| Acentos corrompidos em dashboards (PadrÃ£o, Ã‰rea) | Double-encoding de 128 caracteres Unicode U+0080–U+00FF nos mesmos arquivos. `ExperimentManager.loadContext("PadrÃ£o")` falhava silenciosamente deixando lista vazia no EIDashboard. Corrigido com script Python que gerou e aplicou todos os pares de substituição C383/C382 + C2 → bytes originais. |
| EIDashboard vazio ao criar novo experimento | `loadContext("PadrÃ£o", "esquiva_inibitoria")` (double-encoding de "Padrão") não encontrava o contexto → lista de experimentos ficava vazia → `initialSelectTimer` nunca selecionava o experimento criado. Corrigido pelo fix de double-encoding acima. |
| "EXPLORAÇÃO DE OBJETOS" visível na aba Gravação do EI | Label usava fallback NOR para `aparato === "esquiva_inibitoria"`. Adicionada condição para mostrar "EXPLORAÇÃO GERAL" igual ao CC. |
| Start no modo ao_vivo bloqueado por falta de videoPath | `startSession()` checava `videoPath === ""` antes do modo. Adicionada condição `analysisMode !== "ao_vivo"` para bypass; erro específico quando `cameraId === ""` no modo ao vivo. |
| Aba Arena sem preview de câmera ao vivo | `CaptureSession` + `Camera` adicionados em `ArenaSetup.qml` e `EIArenaSetup.qml`. Ao selecionar câmera, `arenaCamera.active = true` alimenta o `framePreview` (mesmo VideoOutput usado offline). `ShaderEffectSource` nos campos atualizado para `visible` quando modo ao_vivo ativo. |
| Seleção de câmera (modo ao_vivo) não navegava para aba Gravação | `onAnalysisModeChangedExternally` em todos os 4 dashboards não trocava de aba. Adicionado `if (mode === "ao_vivo") Qt.callLater(function() { innerTabs.currentIndex = 1 })` em NORDashboard, CADashboard (2 handlers), CCDashboard (2 handlers) e EIDashboard. |
| Botão "Carregar Video" sem feedback visual no modo câmera | Botão mostrava estado "vazio" mesmo após selecionar câmera. Atualizado em `ArenaSetup.qml` e `EIArenaSetup.qml`: mostra "📹 Camera Selecionada" (verde) quando `analysisMode === "ao_vivo" && cameraId !== ""`. |
| Diálogo "Salvar em" sem botão de browse | Campo de diretório tinha apenas TextInput sem botão de abrir janela nativa. Adicionado `FolderDialog` do Qt Quick Dialogs + botão "Pesquisar" em `ArenaSetup.qml` e `EIArenaSetup.qml`. |
| Texto dev-mode não traduzível | Hint bar do dev-mode usava string literal. Migrado para `LanguageManager.tr3()` com unicode escapes `\u{1F527}` / `\u{1F5B1}` para evitar corrupção de emoji. |
| Frames: 0 e tela preta na aba Gravação (ao vivo) | `startLiveAnalysis` chamava `m_captureSession->setVideoOutput(m_liveSink)` passando `QVideoSink*` para o método de display. Correto é `setVideoSink(m_liveSink)`. Segundo problema: `displayPlayer.source = ""` matava o `framePreviewMaster` sem nova fonte. Corrigido com `InferenceController::setLivePreviewOutput(QObject*)` que chama `m_captureSession->setVideoOutput(videoOutput)`, alimentando o `VideoOutput` QML diretamente pelo `CaptureSession` do C++. |
| Conflito de câmera entre ArenaSetup e inferência ao vivo | Dois `QMediaCaptureSession` tentavam abrir o mesmo device simultaneamente. Adicionado sinal `liveAnalysisStarting()` no `LiveRecording`; dashboards conectam ao `stopCameraPreview()` de `ArenaSetup`/`EIArenaSetup` que desativa `arenaCamera.active` antes do `startLiveAnalysis` C++ abrir a câmera. |
| Tela verde ao vivo (Arena e Gravação) | `MediaPlayer` e `CaptureSession` apontavam estaticamente para o mesmo `VideoOutput` (`framePreview`/`framePreviewMaster`). Qt 6 não suporta dois provedores simultâneos no mesmo VideoOutput → tela verde. Corrigido: `CaptureSession` sem `videoOutput` estático; `_updateCameraPreview()` faz `videoPlayer.videoOutput = null` antes de `arenaCaptureSession.videoOutput = framePreview`. `LiveRecording` faz `displayPlayer.videoOutput = null` antes de `startLiveAnalysis`; restaura ao parar. |
| `saveDirectory` não existe em `workArea` do EIDashboard | Handler `onAnalysisModeChangedExternally` do EI tentava `workArea.saveDirectory = ...` mas `workArea` (Item local) não tem essa propriedade. Removida a linha — EI sempre usa 1 campo e não precisa de `saveDirectory`. |
| Tela verde ao vivo ainda persiste + `stopCameraPreview` not a function | **PENDENTE.** Abordagem atual (dois `VideoOutput` por arena: `framePreviewOffline`/`framePreviewLive`) ainda resulta em tela verde. Adicionalmente, `stopCameraPreview` foi acidentalmente removida de `ArenaSetup.qml` pelo script de simplificação de `_updateCameraPreview` (o script calculou `idx_end` como o `}` de `stopCameraPreview` em vez do `}` de `_updateCameraPreview`, porque `stopCameraPreview` ficou entre as duas funções e antes do `FileDialog`). **Para resolver:** (1) Re-adicionar `function stopCameraPreview() { arenaCamera.active = false }` em `ArenaSetup.qml` após `_updateCameraPreview`; (2) Diagnosticar root cause real do verde — verificar se o problema é NV12→RGB no shader Qt 6 com DroidCam, ou se a abordagem de dois VideoOutputs com `ShaderEffectSource` tem outro conflito. |
| Live em 1080p com FPS real baixo (~22 FPS) | Perfil solicitado/aplicado pode mostrar 1920x1080 @ up to 60 FPS, mas FPS real ainda fica em ~22 no runtime atual. **PENDENTE (passo 2):** investigar gargalo ponta a ponta (fonte DroidCam/driver, formato de pixel, custo `toImage()`/conversão, throughput de inferência) para buscar **request alvo de 60 FPS reais**. |
| Seleção de câmera repetida no modo ao vivo | Adicionada opção em SettingsScreen.qml para definir câmera padrão (defaultLiveCameraId), persistida em mindtrace_settings.json via ThemeSettings.saveVariant/loadVariant. ArenaSetup.qml e EIArenaSetup.qml aplicam automaticamente; se indisponível, fazem fallback para o popup. |
| `BoutEditorPanel is not a type` ao iniciar app | Novo componente QML em `qml/shared/` não estava registrado em `qml/shared/qmldir`. Adicionada linha `BoutEditorPanel 1.0 BoutEditorPanel.qml`. Regra: qualquer novo `.qml` em `shared/` exige entrada no `qmldir`. |

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
| `LiveRecording::getBehaviorFrames(campo)` | Wrapper público QML que expõe `getBehaviorFrames` do InferenceController para BoutEditorPanel | ✅ Implementado |
| `InferenceController::exportBehaviorFeatures` | Exporta CSV com 21 features + rule_label por frame | ✅ Implementado |
| `InferenceController::getBehaviorFrames(campo)` | Retorna `QVariantList` de `{frameIdx, ruleLabel, movNose, movBody, movMean}` para revisão de bouts | ✅ Implementado |
| `src/analysis/BSoidAnalyzer.h/cpp` | PCA + K-Means nativo + `populateTimelines()` + `extractSnippets()` | ✅ Implementado |
| `CCDashboard` aba Comportamento | Clusters, timeline dupla (Regras vs B-SOiD), extração de clips de vídeo, **Revisão de Bouts** | ✅ Implementado |
| `qml/shared/BoutEditorPanel.qml` | Painel de revisão post-sessão: tabela de bouts, filtros por label, editar label, split, merge, undo, exportar CSV/JSON | ✅ Implementado |

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
- **Dias:** definidos livremente via editor de chips em EISetup (default: Treino, E1–E5, Teste)
- **Duração:** 5 min/sessão (timer fixo, não escalável)

### Configuração

Em **EISetup.qml**:
- Nome experimento + diretório (opcional)
- ✅ Checkbox: Tratamento (default true) — coluna extra no CSV
- 📅 **Editor de dias:** chips com TextInput editável (padrão: Treino, E1, E2, E3, E4, E5, Teste). Adicione/remova livremente.

Colunas CSV geradas:
```
["Diretório do Vídeo", "Animal", "Dia",
 "Latência (s)", "Tempo Plataforma (s)", "Tempo Grade (s)",
 "Bouts Plataforma", "Bouts Grade",
 "Distância Total (m)", "Velocidade Média (m/s)", "Tratamento" (opcional)]
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

### Seleção de Dia (EIMetadataDialog)

ComboBox populado com `dayNames` carregado de `metadata.json`. O índice selecionado + 1 é o número do dia gravado no CSV. Experimentos antigos (sem `dayNames`) recebem fallback automático que reconstrói Treino/E1-EN/Reativação/Teste a partir dos campos legados `extincaoDays`/`hasReactivation`.

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

1. Seleciona dia (ComboBox com `dayNames`)
2. Insere animal ID
3. Opcionalmente: Tratamento (texto livre)
4. "Salvar Sessão" → insere linha em `tracking_data.csv`, salva JSON metadados

> Tema: amarelo (#c8a000). Métricas não são exibidas inline — são calculadas internamente e gravadas diretamente no CSV.

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

## 🌐 Sistema de Idiomas (Implementado)

Suporte a pt-BR, en-US e es-ES persistido em `mindtrace_settings.json`.

### Arquitetura

| Componente | Localização | Responsabilidade |
|---|---|---|
| `LanguageSettings` (C++) | `src/settings/LanguageSettings.h/cpp` | Lê/escreve `language` em `mindtrace_settings.json` via `QStandardPaths::AppDataLocation` |
| `LanguageManager.qml` | `qml/core/Theme/LanguageManager.qml` | Singleton QML; expõe `currentLanguage`, `tr3(pt, en, es)`, `toggleLanguage()` |
| `qmldir` | `qml/core/Theme/qmldir` | Registra `LanguageManager` e `ThemeManager` como singletons — **obrigatório** |
| `SettingsScreen.qml` | `qml/core/Theme/SettingsScreen.qml` | Selector de idioma com 3 botões PT / EN / ES |

### Uso em QML

```qml
import "core/Theme" as Theme
// Depois usar LanguageManager diretamente (singleton global após import)
text: LanguageManager.tr3("Salvar", "Save", "Guardar")
```

### Regra de encoding para emoji em strings traduzidas

Usar **unicode escapes** `\u{XXXXX}` — nunca embutir emoji literais em strings QML. O Edit tool pode re-codificar bytes suplementares e corromper o arquivo:

```qml
// CORRETO
text: LanguageManager.tr3("\u{1F527} Dev Mode", "\u{1F527} Dev Mode", "\u{1F527} Dev Mode")
// ERRADO — emoji literal pode corromper o arquivo ao editar
text: LanguageManager.tr3("🔧 Dev Mode", "🔧 Dev Mode", "🔧 Dev Mode")
```

### Idioma padrão

App sempre inicia em **pt-BR** na primeira execução. Preferência persistida em `mindtrace_settings.json` e restaurada via `LanguageSettings::language()` em `main.cpp`.

---

## 📹 Análise ao Vivo com Câmera (Implementado)

Suporte a câmeras USB (DroidCam, Camo, IVCam ou qualquer UVC/webcam) como fonte de vídeo.

### Arquitetura C++ (InferenceController)

| Método | Descrição |
|---|---|
| `startLiveAnalysis(cameraId, modelDir)` | Inicia análise usando `QCamera` + `QMediaCaptureSession` + `QVideoSink` |
| `listVideoInputs()` | Retorna `QStringList` com descrições de câmeras via `QMediaDevices::videoInputs()` |
| `startAnalysis(videoPath, modelDir)` | Modo offline (inalterado) |

Pipeline ao vivo:
```
QCamera → QMediaCaptureSession → QVideoSink
  → videoFrameChanged → InferenceController::onVideoFrameChanged
    → frame.toImage() → InferenceEngine::enqueueFrame
      → (mesma cadeia do modo offline)
```

### UI — Seleção de Câmera

Popup `analysisModePrompt` em `ArenaSetup.qml` e `EIArenaSetup.qml`:
1. Usuário clica "Carregar Vídeo"
2. Popup oferece "Vídeo" vs "Ao Vivo"
3. Se "Ao Vivo": lista câmeras detectadas via `InferenceController.listVideoInputs()`
4. Ao confirmar câmera: `analysisMode = "ao_vivo"`, `cameraId = <descrição>` e emite `analysisModeChangedExternally(mode)`

### UX — Navegação Automática

Ao selecionar câmera, todos os dashboards (NOR, CA, CC, EI) navegam automaticamente para a **aba Gravação** via `Qt.callLater` no handler `onAnalysisModeChangedExternally`.

Botão "Carregar Vídeo" muda para **"📹 Camera Selecionada"** (verde) quando `analysisMode === "ao_vivo" && cameraId !== ""`.

### Câmera USB via DroidCam

- Instalar **DroidCam** no celular e no PC (Windows client)
- Conectar celular por USB; o app cria dispositivo UVC virtual
- O dispositivo aparece como "DroidCam Source" na lista de câmeras do MindTrace
- Resolução recomendada: 720p / 30fps
- 1 câmera física → 3 campos virtuais por corte de mosaico (360×240 cada)

### Gravação ao vivo

A gravação do stream (salvar vídeo da câmera) ainda não está implementada. A sessão ao vivo executa inferência em tempo real mas **não salva arquivo de vídeo**. Um aviso "Gravação não disponível no modo ao vivo" é exibido na UI.

### Feed de Vídeo na Aba Gravação (ao vivo)

`QMediaCaptureSession` suporta **dois destinos simultâneos**:
- `setVideoSink(QVideoSink*)` — entrega raw frames para inferência C++
- `setVideoOutput(QObject*)` — alimenta `VideoOutput` QML para display

Fluxo ao iniciar sessão ao vivo:
1. `liveAnalysisStarting()` — sinal emitido ANTES de `startLiveAnalysis`; dashboards param o preview da arena (`stopCameraPreview()`) para liberar a câmera
2. `inference.startLiveAnalysis(cameraId, "")` — cria `QMediaCaptureSession` + `QVideoSink`
3. `Qt.callLater(() => inference.setLivePreviewOutput(framePreviewMaster))` — conecta `VideoOutput` do painel de gravação ao `CaptureSession`

Preview na aba Arena usa `CaptureSession` separado com `arenaCamera`/`eiArenaCamera` que são desativados ao iniciar análise.

## Atualizacao da Sessao (2026-04-21)

### CC/B-SOiD - fluxo e confiabilidade
- Fluxo da aba Classificacao reorganizado para sequencia guiada:
1. Analisar
2. Filtrar clusters (Min %)
3. Fixar clusters visiveis
4. Gerar snippets e nomear
5. Gerar comparacao
6. Salvar rotulos + estatistica
- Comparacao final condicionada ao preenchimento dos clusters visiveis.
- Filtro `Min %` propagado para matriz, timeline e exportacao final.
- Limiar de confianca B-SOiD padrao alterado para 50%.
- Helpers adicionados:
1. explicacao do `~ Regra (x%)`
2. explicacao leiga dos 3 modos de rotulo final.

### Relatorios
- Exportacao de PDF de resultados implementada no backend C++:
1. grafico de colunas Rules
2. grafico de colunas B-SOiD
3. timeline Rules vs B-SOiD
4. matriz de concordancia
- Novo metodo `InferenceController::savePdfReport(...)`.
- Novo botao na UI `Salvar PDF Results Report`.

### UI e idioma
- Badge `ACTIVE` corrigido para `ATIVO` em portugues.
- Popup de modo de analise (NOR/EI) com layout adaptativo para PT/EN/ES (sem overflow de texto).
- Icone de configuracoes padronizado para engrenagem (`\u2699`) para evitar renderizacao como reticencias.


