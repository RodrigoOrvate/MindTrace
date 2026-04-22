## Aplicativo de Ciclo de Vida (Animal Lifecycle Platform)

Além do MindTrace (Qt/C++), este repositório também inclui um aplicativo separado para cadastro, histórico e segurança de acesso dos animais:

- Pasta: `animal-lifecycle-platform/`
- Backend: FastAPI + SQLite (com autenticação e auditoria)
- Frontend: Expo (web/mobile)

Para instalação, configuração de `.env`, criação de usuário admin inicial, regras de IP e integração com MindTrace, use o guia completo em:

- `animal-lifecycle-platform/README.md`

Observação:
- Este README raiz descreve o MindTrace.
- O README dentro de `animal-lifecycle-platform` descreve o aplicativo de ciclo de vida.
# MindTrace â€” MemoryLab / UFRN

Sistema de tracking comportamental de ratos para paradigmas **NOR (Novel Object Recognition)**, **Campo Aberto (Open Field)**, **Comportamento Complexo (CC)** e **Esquiva InibitÃ³ria (EI)**, rodando **nativamente em C++** com ONNX Runtime. Sem subprocesso Python â€” toda inferÃªncia ocorre dentro do `MindTrace.exe`.

> **Sistema operacional:** Windows 10 ou 11 (64-bit) â€” obrigatÃ³rio (usa DirectX 12 / DirectML)

---

## 1. PrÃ©-requisitos

### Software obrigatÃ³rio

| Componente | VersÃ£o mÃ­nima | ObservaÃ§Ã£o |
|---|---|---|
| Windows | 10 / 11 (64-bit) | DirectX 12 nativo â€” Win 7/8 nÃ£o suportados |
| Visual Studio | 2022 ou superior | Instalar workload "Desenvolvimento para desktop com C++" |
| CMake | 3.25+ | Adicionar ao PATH durante instalaÃ§Ã£o |
| Qt | 6.11.0 | Ver seÃ§Ã£o abaixo â€” instalar via Qt Online Installer |
| ONNX Runtime | 1.24.4 | Configurado automaticamente pelo `build.bat` (ver SeÃ§Ã£o 2) |
| Python | 3.12+ (opcional) | Apenas para debug/validaÃ§Ã£o do modelo |

### InstalaÃ§Ã£o do Qt 6.11.0

Baixe o **Qt Online Installer** em [qt.io/download](https://www.qt.io/download-open-source) (use conta Qt gratuita).

Durante a instalaÃ§Ã£o, selecione em **Qt 6.11.0 > MSVC 2022 64-bit**:

| MÃ³dulo | ObrigatÃ³rio | Finalidade |
|---|---|---|
| Qt Multimedia | âœ… Sim | QMediaPlayer, QVideoSink â€” pipeline de vÃ­deo |
| Qt Shader Tools | âœ… Sim | DependÃªncia de renderizaÃ§Ã£o de vÃ­deo |

Todos os outros mÃ³dulos podem ficar **desmarcados**.

Certifique-se de que Qt estÃ¡ instalado em `C:\Qt\6.11.0\msvc2022_64\`.  
Se o caminho for diferente, edite a variÃ¡vel `QT_DIR` no inÃ­cio de `qt\scripts\build.bat`.

---

## 2. ONNX Runtime 1.24.4

> VocÃª sÃ³ precisa **baixar um pacote** â€” o que corresponde Ã  sua GPU.  
> O cÃ³digo detecta a GPU automaticamente em runtime (via DXGI) e usa o melhor provider disponÃ­vel.

### Passo 1 â€” ConfiguraÃ§Ã£o AutomÃ¡tica (Recomendado)

O `build.bat` detecta automaticamente se o SDK estÃ¡ faltando e oferece baixÃ¡-lo:

```cmd
cd qt
scripts\build.bat
```

Na primeira execuÃ§Ã£o sem o SDK, ele perguntarÃ¡:
```
[1] Sim, para GPU AMD ou Intel (DirectML)
[2] Sim, para GPU NVIDIA (CUDA)
[3] NÃ£o, sair
```

Selecione a opÃ§Ã£o correspondente Ã  sua GPU. O script baixa e organiza tudo automaticamente.

> **NÃ£o execute o `setup_onnx.ps1` diretamente.** Use sempre o `build.bat` â€” ele garante o ambiente MSVC correto antes de qualquer operaÃ§Ã£o.

---

### Passo 2 â€” ConfiguraÃ§Ã£o Manual (Fallback)

Se o download automÃ¡tico falhar, organize os arquivos manualmente:

#### Para AMD / Intel (DirectML):
1.  **Baixe o Motor:** [`Microsoft.ML.OnnxRuntime.DirectML.1.24.4.nupkg`](https://www.nuget.org/api/v2/package/Microsoft.ML.OnnxRuntime.DirectML/1.24.4)
2.  **Baixe a Base:** [`Microsoft.AI.DirectML.1.15.4.nupkg`](https://www.nuget.org/api/v2/package/Microsoft.AI.DirectML/1.15.4)
3.  Renomeie para `.zip` e extraia DLLs de `runtimes/win-x64/native/` para `onnxruntime_sdk/lib/`.
4.  Extraia `DirectML.dll` (do segundo pacote) para `onnxruntime_sdk/lib/`.
5.  Extraia headers de `build/native/include/` para `onnxruntime_sdk/include/`.

#### Para NVIDIA (CUDA):
1.  Baixe [`onnxruntime-win-x64-gpu-1.24.4.zip`](https://github.com/microsoft/onnxruntime/releases/download/v1.24.4/onnxruntime-win-x64-gpu-1.24.4.zip).
2.  Extraia e renomeie a pasta para `onnxruntime_sdk/` na raiz do projeto.

**Estrutura Final Esperada:**
```
MindTrace/
â”œâ”€â”€ onnxruntime_sdk/        â€” Raiz do SDK
â”‚   â”œâ”€â”€ include/            â€” CabeÃ§alhos (.h)
â”‚   â””â”€â”€ lib/                â€” DLLs e .lib
â””â”€â”€ qt/                     â€” CÃ³digo-fonte
```

> **AtenÃ§Ã£o:** a pasta `qt/` contÃ©m o cÃ³digo-fonte. O `onnxruntime_sdk` deve ficar na raiz (`MindTrace/`), nÃ£o dentro de `qt/`.

### Aviso para usuÃ¡rios NVIDIA (CUDA)

O pacote `onnxruntime-win-x64-gpu` **nÃ£o inclui** os drivers CUDA â€” apenas o motor de inferÃªncia.  
Para que o provider CUDA funcione, vocÃª precisa instalar separadamente:

| DependÃªncia | VersÃ£o recomendada | Download |
|---|---|---|
| CUDA Toolkit | 12.6.3 | [Baixar CUDA 12.6.3](https://developer.nvidia.com/cuda-12-6-3-download-archive) Â· [Arquivo completo](https://developer.nvidia.com/cuda-toolkit-archive) |
| cuDNN | 9.x (para CUDA 12) | [Baixar cuDNN](https://developer.nvidia.com/cudnn-downloads) Â· [Arquivo completo](https://developer.nvidia.com/rdp/cudnn-archive) |

#### Instalando o cuDNN (passo obrigatÃ³rio apÃ³s o download)

A partir do **cuDNN 8**, o instalador **nÃ£o copia mais os arquivos para dentro da pasta do CUDA** â€” ele instala em um diretÃ³rio separado. VocÃª precisa copiar as DLLs manualmente.

**1. Localize a pasta do cuDNN instalado:**
```
C:\Program Files\NVIDIA\CUDNN\v9.x\bin\
```
Dentro de `bin\` haverÃ¡ uma subpasta com a versÃ£o do CUDA correspondente (ex: `12.6\`). Use a que bater com a versÃ£o do seu CUDA Toolkit.

**2. Copie todas as DLLs dessa subpasta para o `bin\` do CUDA:**

| Origem | Destino |
|---|---|
| `C:\Program Files\NVIDIA\CUDNN\v9.x\bin\12.6\*.dll` | `C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.6\bin\` |

> Se instalou CUDA 13.x em vez de 12.x, o procedimento Ã© o mesmo â€” use a subpasta `13.x\` do cuDNN e copie para o `bin\` do CUDA 13.

**3. Verifique** que o arquivo `cudnn64_9.dll` estÃ¡ em:
```
C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.6\bin\cudnn64_9.dll
```

ApÃ³s copiar, rode `scripts\build.bat` e o log do app deve exibir `"Modo GPU: CUDA ativo (NVIDIA)"`.

> **Sem esses drivers, o CUDA falha silenciosamente e o app cai automaticamente para DirectML (DirectX 12).** O comportamento Ã© idÃªntico ao de placas AMD/Intel â€” sem perda de funcionalidade, apenas menor desempenho de inferÃªncia comparado ao CUDA nativo.  
> VocÃª verÃ¡ no log: `"Modo GPU: DirectML ativo (NVIDIA, DirectX 12)"` em vez de `"Modo GPU: CUDA ativo (NVIDIA)"`.

---

## 3. Modelo ONNX

Coloque o arquivo `Network-MemoryLab-v2.onnx` em `qt/` (nÃ£o incluÃ­do no repositÃ³rio por tamanho).

- **Input:** `[1, 240, 360, 3]` â€” RGB float32, **sem** subtraÃ§Ã£o de mÃ©dia (o grafo jÃ¡ normaliza)
- **Output 0:** `[1, 30, 46, 2]` â€” scoremap (heatmaps nose/body)
- **Output 1:** `[1, 30, 46, 4]` â€” locref (offsets sub-pixel)
- **Stride:** 8.0 Â· **Locref stdev:** 7.2801

---

## 4. Build

```cmd
cd qt
scripts\build.bat
```

O script:
1. Detecta o Visual Studio instalado via `vswhere`
2. Verifica o SDK ONNX e oferece download automÃ¡tico se ausente
3. Configura CMake (C++17, NMake Makefiles)
4. Compila e roda `windeployqt`
5. Copia DLLs do ONNX Runtime de `onnxruntime_sdk\lib\` para `build\`
6. Executa `MindTrace.exe`

---

## 5. DetecÃ§Ã£o de GPU em Runtime

O cÃ³digo detecta automaticamente a GPU via **DXGI** na inicializaÃ§Ã£o e tenta os providers em cascata â€” sem necessidade de recompilar:

| GPU detectada | Provider tentado (ordem) | Resultado se falhar |
|---|---|---|
| NVIDIA | CUDA â†’ DirectML â†’ CPU | Fallback automÃ¡tico para o prÃ³ximo |
| AMD / Intel | DirectML â†’ CPU | Fallback automÃ¡tico para CPU |
| Nenhuma | CPU | â€” |

O status Ã© exibido na Ã¡rea de log durante o carregamento do modelo, ex.:  
`"Modo GPU: CUDA ativo (NVIDIA)"` ou `"Modo GPU: DirectML ativo (NVIDIA, DirectX 12)"`.

---

## 6. Modelo Neural

- **Arquitetura:** ResNet-50 via DeepLabCut (MobileNetV2 em treinamento)
- **Bodyparts:** `nose` (canal 0), `body` (canal 1)
- **Config:** `qt/pose_cfg.yaml` â€” `stride: 8.0`, `locref_stdev: 7.2801`

---

## 7. VÃ­deo e Mosaico

- **Fonte:** DVR Intelbras â€” mosaico 2Ã—2 em arquivo Ãºnico
- **ResoluÃ§Ã£o:** 720Ã—480 @ ~29.97 fps
- **Campos ativos (3):**
  - Campo 0: Topo-Esquerda `(0, 0)` â€” 360Ã—240
  - Campo 1: Topo-Direita `(360, 0)` â€” 360Ã—240
  - Campo 2: Baixo-Esquerda `(0, 240)` â€” 360Ã—240

---

## 8. Arquitetura do Sistema

```
MindTrace.exe (Qt 6.11.0 / C++17 / ONNX Runtime 1.24.4)
  â””â”€â”€ LiveRecording.qml
        â””â”€â”€ InferenceController (C++)
             â”œâ”€â”€ QVideoSink          â€” recebe cada frame decodificado do QMediaPlayer headless
             â”‚    â””â”€â”€ videoFrameChanged â†’ onVideoFrameChanged â†’ enqueueFrame
             â””â”€â”€ InferenceEngine (QThread)  â€” inferÃªncia nativa (Pose + Comportamento rule-based)
                  â”œâ”€â”€ DXGI vendor detection â†’ CUDA (NVIDIA) / DirectML / CPU (cascata)
                  â”œâ”€â”€ BehaviorScanner[3]  â€” extraÃ§Ã£o de 21 features + classifySimple() + _frameHistory
                  â”œâ”€â”€ 3Ã— Ort::Session (Pose DLC)
                  â””â”€â”€ std::thread por campo â†’ inferÃªncia paralela via HW Acceleration

  â””â”€â”€ CCDashboard (Comportamento Complexo)
        â””â”€â”€ BSoidAnalyzer (C++ QObject)
             â”œâ”€â”€ BSoidWorker (QThread) â€” PCA 21â†’6 + K-Means++ k=7
             â”œâ”€â”€ populateTimelines()  â€” preenche BehaviorTimeline (Regras + B-SOiD) de C++
             â””â”€â”€ extractSnippets()   â€” QThread + QProcess (FFmpeg) â†’ clips por cluster
```

**Sinais emitidos (`InferenceController` â†’ QML):**

```
readyReceived()                      â€” modelo carregado, tracking ativo
trackReceived(campo, x, y, p)       â€” nose â€” coordenadas em pixels do mosaico
bodyReceived(campo, x, y, p)        â€” body â€” coordenadas em pixels do mosaico
dimsReceived(width, height)         â€” resoluÃ§Ã£o do vÃ­deo
fpsReceived(fps)                    â€” FPS extraÃ­do do metadata
infoReceived(msg)                   â€” ex: "Modo GPU: DirectML ativo (AMD, DirectX 12)"
errorOccurred(msg)                  â€” erro fatal
analyzingChanged()                  â€” bool isAnalyzing
behaviorReceived(campo, labelId)    â€” id do compartamento SimBA/B-SOiD detectado
```

---

## 9. Estrutura de Pastas

```
MindTrace/
â”œâ”€â”€ onnxruntime_sdk/        â€” SDK ONNX Runtime (configurado pelo build.bat)
â””â”€â”€ qt/
    â”œâ”€â”€ src/
    â”‚   â”œâ”€â”€ core/           â€” main.cpp (registro de tipos QML)
    â”‚   â”œâ”€â”€ manager/        â€” ExperimentManager.cpp/.h (CRUD, Registry)
    â”‚   â”œâ”€â”€ models/         â€” TableModels, ArenaModel, ConfigModels
    â”‚   â”œâ”€â”€ tracking/       â€” InferenceController, InferenceEngine, BehaviorScanner, BehaviorTimeline
    â”‚   â””â”€â”€ analysis/       â€” BSoidAnalyzer.h/cpp (PCA + K-Means + snippets)
    â”œâ”€â”€ qml/
    â”‚   â”œâ”€â”€ core/           â€” NavegaÃ§Ã£o e componentes base (main.qml, GhostButton, Theme/)
    â”‚   â”œâ”€â”€ shared/         â€” LiveRecording.qml, SessionResultDialog.qml, BoutEditorPanel.qml, **DataView.qml + 5 aparato-views**
    â”‚   â”œâ”€â”€ nor/            â€” NORDashboard, ArenaSetup, NORSetupScreen
    â”‚   â”œâ”€â”€ ca/             â€” CADashboard, CAArenaSelection, CASetup, CAMetadataDialog
    â”‚   â”œâ”€â”€ cc/             â€” CCDashboard, CCArenaSelection, CCSetup, CCMetadataDialog
    â”‚   â””â”€â”€ ei/             â€” EIDashboard, EISetup, EIMetadataDialog
    â”œâ”€â”€ data/               â€” arenas.json, arena_config_referencia.json
    â”œâ”€â”€ scripts/            â€” build.bat, setup_onnx.ps1
    â”œâ”€â”€ CMakeLists.txt
    â””â”€â”€ resources.qrc
```

**SaÃ­da por experimento:**
```
<experimento>/
â”œâ”€â”€ tracking_data.csv           â€” coordenadas nose/body por frame
â”œâ”€â”€ behavior_summary.csv        â€” % de tempo por comportamento (rule-based)
â”œâ”€â”€ sessions/
â”‚   â””â”€â”€ session_<ts>.json       â€” metadados ricos (bouts, DI, por minuto)
â””â”€â”€ bsoid_snippets/             â€” gerado pelo BSoidAnalyzer apÃ³s anÃ¡lise
    â”œâ”€â”€ grupo_1/
    â”‚   â”œâ”€â”€ clip_1.mp4          â€” segmento representativo (mÃ¡x. 5s)
    â”‚   â””â”€â”€ timestamps.csv      â€” start/end de cada clip
    â””â”€â”€ grupo_N/
        â””â”€â”€ ...
```

---

## 10. Sistema de Temas (Dark / Light)

O app suporta dark mode e light mode via `ThemeManager` (singleton QML em `qml/core/Theme/`).

- **Ativar/desativar:** botÃ£o de configuraÃ§Ãµes (âš™) no canto superior direito de qualquer tela
- **PadrÃ£o:** dark mode (sempre inicia em dark)
- Todas as telas respondem ao tema em tempo real com animaÃ§Ãµes suaves

---

## 11. Funcionalidades Principais

- **Registry System:** Salve experimentos em qualquer HD/PartiÃ§Ã£o; o MindTrace gerencia o atalho no `registry.json`.
- **Sistema de Dias CustomizÃ¡vel:** Na criaÃ§Ã£o de qualquer experimento (NOR, CA, CC, EI), defina os nomes dos dias livremente via editor de chips (ex.: "Treino", "E1", "E2", "Teste"). O popup pÃ³s-sessÃ£o apresenta um ComboBox com esses nomes para seleÃ§Ã£o. Experimentos antigos sÃ£o compatÃ­veis via fallback automÃ¡tico.
- **Tratamento (ex-Droga):** Campo renomeado de "Droga" para "Tratamento" em todos os formulÃ¡rios e CSVs.
- **Excel Fix:** Suporte nativo a acentos em CSVs via UTF-8 BOM.
- **Offline Path:** Preenchimento automÃ¡tico do diretÃ³rio de vÃ­deo em anÃ¡lises offline.
- **Velocidade:** AnÃ¡lise offline em 1x, 2x ou 4x com sincronizaÃ§Ã£o automÃ¡tica entre display e inferÃªncia.
- **Motor Comportamental:** ClassificaÃ§Ã£o baseada em regras (`BehaviorScanner::classifySimple()`) executada nativamente em C++. Sistema rule-based com detecÃ§Ã£o de:
  - **Sniffing**: focinho dentro da zona do objeto
  - **Rearing**: focinho bem acima do corpo (>30px) + bordas (parede)
  - **Resting**: velocidade < 0.05 m/s ou corpo parado
  - **Walking**: corpo movendo significativamente
  - **Grooming**: nariz ativo + corpo quase parado
- **AnÃ¡lise B-SOiD (NÃ£o-Supervisionada):** Descoberta de padrÃµes comportamentais via clustering nativo (PCA + K-Means).
  - **Timeline Dupla:** VisualizaÃ§Ã£o comparativa entre Regras (supervisionadas) e B-SOiD (descobertas).
  - **ExtraÃ§Ã£o de Clips:** SegmentaÃ§Ã£o automÃ¡tica de vÃ­deo para validaÃ§Ã£o visual dos grupos descobertos.
- **Abas de Dados com Tema Aparato-EspecÃ­fico:** Cada dashboard (NOR, CA, CC, EI) possui uma aba "Dados" que exibe os resultados com **detecÃ§Ã£o automÃ¡tica de aparato** e **theming Ãºnico**:
  - **NOR:** Tema vermelho (#ab3d4c) â€” VÃ­deo, Animal, Campo, Dia, Par de Objetos, Tratamento
  - **CA:** Tema azul (#3d7aab) â€” Animal, Campo, Dia, DistÃ¢ncia Total, Velocidade MÃ©dia, Tratamento
  - **CC:** Tema roxo (#7a3dab) â€” Comportamento Complexo com locomoÃ§Ã£o e velocidade
  - **EI:** Dashboard/Setup/popup e Aba Dados (`EIDataView`) todos em tema **amarelo (#c8a000)** com color-coding semÃ¢ntico nas cÃ©lulas: LatÃªncia (vermelho), Tempo Plataforma (verde), Tempo Grade (azul)
  - **DetecÃ§Ã£o automÃ¡tica:** Componente `DataView` escaneia headers CSV e renderiza view apropriada sem intervenÃ§Ã£o manual
  - **Recursos:** BotÃµes Exportar/Salvar, BusyIndicator, scroll, ediÃ§Ã£o de cÃ©lulas, legends contextualizadas
- **Zonas EditÃ¡veis (CC)**: Em modo Comportamento Complexo, as zonas podem ser editadas na ArenaSetup (Shift+drag para mover, scroll para redimensionar). Tamanho e posiÃ§Ã£o sÃ£o salvos/restaurados.
- **Importar Arena**: BotÃ£o "ðŸ“¥ Importar Arena" nas telas de configuraÃ§Ã£o (`ArenaSetup.qml` e `EIArenaSetup.qml`). Selecione a pasta de outro experimento para copiar sua configuraÃ§Ã£o de arena. Aviso automÃ¡tico se houver incompatibilidade de forma (quadrada â†” retangular) ou tipo de zona (objetos / plataforma-grade / padrÃ£o).
- **RevisÃ£o de Bouts (BoutEditorPanel):** Painel de revisÃ£o pÃ³s-sessÃ£o integrado ao CCDashboard na aba Comportamento. Carrega o histÃ³rico de frames classificados e permite editar labels, dividir bouts, mesclar bouts adjacentes, desfazer (undo 30 nÃ­veis) e exportar a revisÃ£o como CSV ou JSON. ExportaÃ§Ã£o via `XMLHttpRequest PUT` diretamente do QML, sem backend C++.

---

## 12. Fluxo de AnÃ¡lise B-SOiD

Para realizar a descoberta de novos comportamentos apÃ³s uma sessÃ£o de Comportamento Complexo (CC):

1.  **FinalizaÃ§Ã£o da SessÃ£o:** Complete a anÃ¡lise offline ou ao vivo.
2.  **ExportaÃ§Ã£o de Features:** Na aba "Comportamento" do CCDashboard, clique em "Analisar B-SOiD". O sistema exportarÃ¡ as 21 features cinemÃ¡ticas por frame.
3.  **Processamento Nativo:** O motor `BSoidAnalyzer` executa a reduÃ§Ã£o de dimensionalidade (PCA) e o agrupamento (K-Means) em background.
4.  **Linha do Tempo:** Explore os grupos gerados na `BehaviorTimeline` de SceneGraph (GPU).
5.  **ExtraÃ§Ã£o de Snippets:** Clique em "Extrair Clips" para gerar vÃ­deos curtos (FFmpeg) de cada grupo comportamental na pasta `bsoid_snippets/` do experimento.

---

## 13. HistÃ³rico de Problemas Resolvidos

| Problema | SoluÃ§Ã£o |
|---|---|
| pÃ¢â€°Ë†0.0001 (modelo cego) | Removida double mean subtraction â€” modelo jÃ¡ normaliza |
| Tracking desviado | Frame capture nativo + displayPlayer separado |
| `GetInputName` nÃ£o existe | Usa `GetInputNameAllocated` (ONNX API 1.16+) |
| Subprocesso Python lento | ONNX nativo C++ â€” sem subprocesso |
| DessincronizaÃ§Ã£o em velocidade alta | Headless capped a 2Ã— + `positionSyncTimer` 400ms |
| QAbstractVideoSurface removido no Qt 6 | SubstituÃ­do por `QVideoSink` + `videoFrameChanged` |
| Suporte Windows 7 / 8 removido | Requer Windows 10/11 (DirectX 12). Qt 6.11.0 + ONNX 1.24.4 |
| Toggle de tema nÃ£o funcionava | `qmldir` ausente em `Theme/` â€” sem ele cada componente recebe instÃ¢ncia separada |
| App iniciava em tema claro | `loadThemePreference()` carregava valor salvo; removido do `Component.onCompleted` |
| TrÃªs SDKs na raiz | Unificado para um Ãºnico `onnxruntime_sdk/` â€” usuÃ¡rio baixa sÃ³ o que precisa |
| NVIDIA sem CUDA Toolkit caÃ­a em erro fatal | `tryCreateSessions()` por provider â€” CUDA falha â†’ tenta DirectML â†’ CPU (cascata automÃ¡tica) |
| ExclusÃ£o no Browser global falhava | ExperimentManager::deleteExperiment aceita contexto; SearchBrowser passa contexto do item |
| Pontos da arena sumiam ao arrastar | Implementado clamp (trava) de coordenadas [0, width/height] no onPositionChanged |
| DistÃ¢ncia/ Tracking congelados | `accumulateExploration` abortava em arranjos sem zonas; Layout CC ajustado para fluir mÃ©tricas genericamente |
| Estabilidade de UI | `BehaviorTimeline` criado para renderizar etogramas com GPU (SceneGraph) evitando drop de frames. |
| CSV Behavior Summary | C++ agora emite o arquivo behavior_summary.csv separando % de tempo no CA/CC automaticamente. |
| Erro `undefined inference` | Corrigido erro onde o QML nÃ£o encontrava o InferenceController em LiveRecording atravÃ©s de um wrapper funcional. |
| Timeline B-SOiD | Implementado `populateTimelines()` nativo para preenchimento ultra-rÃ¡pido de etogramas via SceneGraph. |
| `dayNames` nÃ£o aparecia no popup pÃ³s-sessÃ£o | `readMetadataFromPath()` / `readMetadata()` em C++ nunca retornavam o campo `dayNames`. Adicionado parsing do array em ambas as funÃ§Ãµes. |
| Nomes de dias corrompidos pelo normalizador | `dayNameUtils.js` usava fuzzy matching Levenshtein (distÃ¢ncia â‰¤2) que corrompia nomes customizados ("Teste2"â†’"Teste"). SubstituÃ­do por normalizaÃ§Ã£o simples sem fuzzy. |
| Popups pÃ³s-sessÃ£o inconsistentes | NOR, CA e EI reescritos para o padrÃ£o CC-style com `CampoBlock`, altura dinÃ¢mica e cores por aparato: NOR=#ab3d4c, CA=#3d7aab, CC=#7a3dab, EI=#c8a000. |
| Fim de vÃ­deo nÃ£o abria popup (CA, EI) | Re-entrÃ¢ncia no `displayPlayer` ao chamar `stop()` de dentro de `onMediaStatusChanged`. Corrigido com `Qt.callLater()` em ambos os handlers. |
| Timer nunca encerrava sessÃµes 1/2-campo | `startSession()` resetava `timerStarted` apÃ³s inicializar campos inativos como concluÃ­dos. Linha duplicada removida. |
| Tema EI azul (deveria ser amarelo) | `EIDashboard`, `EISetup` e Excel export (`formatar_mindtrace.py`) atualizados de `#3d7aab` para `#c8a000`. |
| BotÃ£o "Salvar ConfiguraÃ§Ã£o" do CA aparecia amarelo | `EIArenaSetup` tinha cores hardcoded; CA e CC o reutilizam. Adicionadas props `primaryColor`/`secondaryColor`; cada aparato passa sua cor ao instanciar. |
| Popup pÃ³s-sessÃ£o nÃ£o aparecia ao fim do vÃ­deo (CA/CC/EI) | Race condition `onAnalyzingChanged` vs `Qt.callLater`. Corrigido com `_guardedSessionEnded()` + flag `_manualStopRequested` em `LiveRecording.qml`. |
| Aba Dados EI verde em vez de amarelo | `EIDataView.qml` tinha `accentColor: "#2f7a4b"`. Alterado para `"#c8a000"`. |
| Popup EI nunca abria | `EIMetadataDialog` estava com `parent: root` em vez de `parent: Overlay.overlay`. |
| ConfiguraÃ§Ã£o de arena nÃ£o reutilizÃ¡vel entre experimentos | Implementada funÃ§Ã£o **Importar Arena** em `ArenaSetup.qml` e `EIArenaSetup.qml`: detecta incompatibilidade de forma/zona e exibe popup de aviso antes de importar. |
| `startLiveAnalysis` ignora resoluÃ§Ã£o/FPS configurados | `LiveRecording.qml` tem `1920, 1080, 60.0` hardcoded â€” cÃ¢mera sempre solicita 1080p/60fps independente da config DroidCam. **PENDENTE:** passar `0, 0, 0.0` para usar formato padrÃ£o da cÃ¢mera. |
| `BoutEditorPanel is not a type` ao carregar CCDashboard | Componente em `qml/shared/` nÃ£o estava registrado em `qml/shared/qmldir`. Adicionada linha `BoutEditorPanel 1.0 BoutEditorPanel.qml`. Regra: todo `.qml` novo em `shared/` precisa de entrada no `qmldir`. |
---

## 12. Esquiva InibitÃ³ria (EI)

Paradigma de **memÃ³ria aversiva passiva** (step-through) para anÃ¡lise de medo e aprendizado associativo.

### ConfiguraÃ§Ã£o RÃ¡pida

1. **Na tela inicial:** Clique no card âš¡ "Esquiva InibitÃ³ria"
2. **EISetup:**
   - Nome do experimento + diretÃ³rio (opcional)
   - âœ… Tratamento (coluna extra no CSV)
   - ðŸ“… **Editor de dias:** chips editÃ¡veis com nomes livres (padrÃ£o: Treino, E1â€“E5, Teste). Adicione/remova dias com "+ Dia" e "Ã—".
3. **PÃ³s-sessÃ£o:** ComboBox com os dias definidos no setup.

### MÃ©tricas Coletadas

| MÃ©trica | Significado |
|---|---|
| **LatÃªncia (s)** | Tempo atÃ© o primeiro exit da plataforma |
| **Tempo Plataforma (s)** | Acumulado na zona da plataforma |
| **Tempo Grade (s)** | Acumulado na zona da grade |
| **Bouts Plataforma** | Quantas vezes entrou na plataforma |
| **Bouts Grade** | Quantas vezes entrou na grade |
| **DistÃ¢ncia (m)** | LocomoÃ§Ã£o total em metros |
| **Velocidade (m/s)** | Velocidade mÃ©dia durante a sessÃ£o |

### Arena EI

- **Tipo:** Quadrada com 2 zonas retangulares editÃ¡veis
- **Zona 0:** Plataforma (elevated, tipicamente esquerda)
- **Zona 1:** Grade (floor, tipicamente direita)
- **EdiÃ§Ã£o:** Shift+drag para mover, scroll para redimensionar (igual CC)

---




