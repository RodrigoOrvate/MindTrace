## Aplicativo Animal Lifecycle (Integrado ao MindTrace)

Este repositório inclui dois blocos conectados:

- `qt/` (MindTrace): onde os experimentos sao criados.
- `animal-lifecycle-platform/` (backend + app): cadastro de animais, login, historico e timeline.

Fluxo atual:
- O experimento e criado no MindTrace com o campo `responsavel`.
- O responsavel e escolhido a partir dos usuarios pesquisadores (nao-admin) do backend.
- Ao salvar sessoes no MindTrace, a sincronizacao envia os eventos para o aplicativo.
- O aplicativo NAO cria experimento manualmente.

Guia completo de instalacao e seguranca (env, sync, rede local e operacao no PC principal):
- `animal-lifecycle-platform/README.md`
# MindTrace  MemoryLab / UFRN

Sistema de tracking comportamental de ratos para paradigmas **NOR (Novel Object Recognition)**, **Campo Aberto (Open Field)**, **Comportamento Complexo (CC)** e **Esquiva Inibitória (EI)**, rodando **nativamente em C++** com ONNX Runtime. Sem subprocesso Python  toda inferência ocorre dentro do `MindTrace.exe`.

> **Sistema operacional:** Windows 10 ou 11 (64-bit)  obrigatório (usa DirectX 12 / DirectML)

---

## 1. Pré-requisitos

### Software obrigatório

| Componente | Versão mínima | Observação |
|---|---|---|
| Windows | 10 / 11 (64-bit) | DirectX 12 nativo  Win 7/8 não suportados |
| Visual Studio | 2022 ou superior | Ver seção abaixo  workload "Desenvolvimento para desktop com C++" + componentes específicos |
| CMake | 3.25+ | Adicionar ao PATH durante instalação |
| Qt | 6.11.0 | Ver seção abaixo  instalar via Qt Online Installer |
| ONNX Runtime | 1.24.4 | Configurado automaticamente pelo `build.bat` (ver Seção 2) |
| Python | 3.12+ (opcional) | Apenas para debug/validação do modelo |

### Instalação do Visual Studio 2022 (Community ou superior)

Baixe o instalador em [visualstudio.microsoft.com](https://visualstudio.microsoft.com/pt-br/downloads/).

Na tela de workloads, marque **"Desenvolvimento para desktop com C++"**.

Dentro desse workload, os itens marcados por padrão já cobrem o básico, mas confirme que os seguintes estão selecionados na coluna de detalhes à direita:

**Obrigatórios para o MindTrace:**

| Componente | Por que é necessário |
|---|---|
| Ferramentas de build do MSVC v143  VS 2022 C++ x64/x86 (versão mais recente) | Compilador C++ (cl.exe)  obrigatório |
| Windows 11 SDK (10.0.26100 ou mais recente) | Headers e libs do sistema  obrigatório |
| CMake C++ para Windows | Gerador de projeto  obrigatório |
| Suporte a C++ para Windows XP (NÃO marcar) | Desnecessário  deixar desmarcado |

**Opcionais recomendados (marcar manualmente):**

| Componente | Localização no instalador | Por que marcar |
|---|---|---|
| Suporte de depuração Just-In-Time | Detalhes do workload | Útil para depurar crashes do MindTrace.exe |
| Ferramentas do Analisador de Gráficos e DirectX | Detalhes do workload | Diagnóstico de problemas com DirectML/DirectX 12 |
| Adaptadores de teste do C++ para Boost.Test / Google Test | Detalhes do workload | Opcional  só se quiser rodar testes unitários C++ |
| IntelliCode | Detalhes do workload | Sugestões de código inteligentes no editor |

**Opcionais que podem ser deixados desmarcados** (economizam espaço, não afetam o build):

- Suporte a C++ para Linux e Mac
- Ferramentas do Clang/LLVM
- Suporte a C++/CLI (não usamos .NET)
- Desenvolvimento de Jogos com C++ (workload separado)
- Módulos ATL / MFC / C++/WinRT

> **Dica de espaço:** o workload completo com as seleções acima ocupa ~810 GB. Se o disco for limitado, desmarque os SDKs de versões antigas do Windows (ex: SDK 10.0.19041)  deixe apenas o SDK mais recente.

Após instalar, o `build.bat` detecta automaticamente o Visual Studio via `vswhere.exe` (incluído no instalador)  não é necessário configurar nada manualmente.

---

### Instalação do Qt 6.11.0

Baixe o **Qt Online Installer** em [qt.io/download](https://www.qt.io/download-open-source) (use conta Qt gratuita).

Durante a instalação, selecione em **Qt 6.11.0 > MSVC 2022 64-bit**:

| Módulo | Obrigatório | Finalidade |
|---|---|---|
| Qt Multimedia | ✅ Sim | QMediaPlayer, QVideoSink  pipeline de vídeo |
| Qt Shader Tools | ✅ Sim | Dependência de renderização de vídeo |

Todos os outros módulos podem ficar **desmarcados**.

Certifique-se de que Qt está instalado em `C:\Qt\6.11.0\msvc2022_64\`.  
Se o caminho for diferente, edite a variável `QT_DIR` no início de `qt\scripts\build.bat`.

---

## 2. ONNX Runtime 1.24.4

> Você só precisa **baixar um pacote**  o que corresponde à sua GPU.  
> O código detecta a GPU automaticamente em runtime (via DXGI) e usa o melhor provider disponível.

### Passo 1  Configuração Automática (Recomendado)

O `build.bat` detecta automaticamente se o SDK está faltando e oferece baixá-lo:

```cmd
cd qt
scripts\build.bat
```

Na primeira execução sem o SDK, ele perguntará:
```
[1] Sim, para GPU AMD ou Intel (DirectML)
[2] Sim, para GPU NVIDIA (CUDA)
[3] Não, sair
```

Selecione a opção correspondente à sua GPU. O script baixa e organiza tudo automaticamente.

> **Não execute o `setup_onnx.ps1` diretamente.** Use sempre o `build.bat`  ele garante o ambiente MSVC correto antes de qualquer operação.

---

### Passo 2  Configuração Manual (Fallback)

Se o download automático falhar, organize os arquivos manualmente:

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
├── onnxruntime_sdk/         Raiz do SDK
│   ├── include/             Cabeçalhos (.h)
│   └── lib/                 DLLs e .lib
└── qt/                      Código-fonte
```

> **Atenção:** a pasta `qt/` contém o código-fonte. O `onnxruntime_sdk` deve ficar na raiz (`MindTrace/`), não dentro de `qt/`.

### Aviso para usuários NVIDIA (CUDA)

O pacote `onnxruntime-win-x64-gpu` **não inclui** os drivers CUDA  apenas o motor de inferência.  
Para que o provider CUDA funcione, você precisa instalar separadamente:

| Dependência | Versão recomendada | Download |
|---|---|---|
| CUDA Toolkit | 12.6.3 | [Baixar CUDA 12.6.3](https://developer.nvidia.com/cuda-12-6-3-download-archive) · [Arquivo completo](https://developer.nvidia.com/cuda-toolkit-archive) |
| cuDNN | 9.x (para CUDA 12) | [Baixar cuDNN](https://developer.nvidia.com/cudnn-downloads) · [Arquivo completo](https://developer.nvidia.com/rdp/cudnn-archive) |

#### Instalando o cuDNN (passo obrigatório após o download)

A partir do **cuDNN 8**, o instalador **não copia mais os arquivos para dentro da pasta do CUDA**  ele instala em um diretório separado. Você precisa copiar as DLLs manualmente.

**1. Localize a pasta do cuDNN instalado:**
```
C:\Program Files\NVIDIA\CUDNN\v9.x\bin\
```
Dentro de `bin\` haverá uma subpasta com a versão do CUDA correspondente (ex: `12.6\`). Use a que bater com a versão do seu CUDA Toolkit.

**2. Copie todas as DLLs dessa subpasta para o `bin\` do CUDA:**

| Origem | Destino |
|---|---|
| `C:\Program Files\NVIDIA\CUDNN\v9.x\bin\12.6\*.dll` | `C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.6\bin\` |

> Se instalou CUDA 13.x em vez de 12.x, o procedimento é o mesmo  use a subpasta `13.x\` do cuDNN e copie para o `bin\` do CUDA 13.

**3. Verifique** que o arquivo `cudnn64_9.dll` está em:
```
C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.6\bin\cudnn64_9.dll
```

Após copiar, rode `scripts\build.bat` e o log do app deve exibir `"Modo GPU: CUDA ativo (NVIDIA)"`.

> **Sem esses drivers, o CUDA falha silenciosamente e o app cai automaticamente para DirectML (DirectX 12).** O comportamento é idêntico ao de placas AMD/Intel  sem perda de funcionalidade, apenas menor desempenho de inferência comparado ao CUDA nativo.  
> Você verá no log: `"Modo GPU: DirectML ativo (NVIDIA, DirectX 12)"` em vez de `"Modo GPU: CUDA ativo (NVIDIA)"`.

---

## 3. Modelo ONNX

Coloque o arquivo `Network-MemoryLab-v2.onnx` em `qt/` (não incluído no repositório por tamanho).

- **Input:** `[1, 240, 360, 3]`  RGB float32, **sem** subtração de média (o grafo já normaliza)
- **Output 0:** `[1, 30, 46, 2]`  scoremap (heatmaps nose/body)
- **Output 1:** `[1, 30, 46, 4]`  locref (offsets sub-pixel)
- **Stride:** 8.0 · **Locref stdev:** 7.2801

---

## 4. Build

```cmd
cd qt
scripts\build.bat
```

O script:
1. Detecta o Visual Studio instalado via `vswhere`
2. Verifica o SDK ONNX e oferece download automático se ausente
3. Configura CMake (C++17, NMake Makefiles)
4. Compila e roda `windeployqt`
5. Copia DLLs do ONNX Runtime de `onnxruntime_sdk\lib\` para `build\`
6. Executa `MindTrace.exe`

---

## 5. Detecção de GPU em Runtime

O código detecta automaticamente a GPU via **DXGI** na inicialização e tenta os providers em cascata  sem necessidade de recompilar:

| GPU detectada | Provider tentado (ordem) | Resultado se falhar |
|---|---|---|
| NVIDIA | CUDA → DirectML → CPU | Fallback automático para o próximo |
| AMD / Intel | DirectML → CPU | Fallback automático para CPU |
| Nenhuma | CPU |  |

O status é exibido na área de log durante o carregamento do modelo, ex.:  
`"Modo GPU: CUDA ativo (NVIDIA)"` ou `"Modo GPU: DirectML ativo (NVIDIA, DirectX 12)"`.

---

## 6. Modelo Neural

- **Arquitetura:** ResNet-50 via DeepLabCut (MobileNetV2 em treinamento)
- **Bodyparts:** `nose` (canal 0), `body` (canal 1)
- **Config:** `qt/pose_cfg.yaml`  `stride: 8.0`, `locref_stdev: 7.2801`

---

## 7. Vídeo e Mosaico

- **Fonte:** DVR Intelbras  mosaico 2×2 em arquivo único
- **Resolução:** 720×480 @ ~29.97 fps
- **Campos ativos (3):**
  - Campo 0: Topo-Esquerda `(0, 0)`  360×240
  - Campo 1: Topo-Direita `(360, 0)`  360×240
  - Campo 2: Baixo-Esquerda `(0, 240)`  360×240

---

## 8. Arquitetura do Sistema

```
MindTrace.exe (Qt 6.11.0 / C++17 / ONNX Runtime 1.24.4)
  └── LiveRecording.qml
        └── InferenceController (C++)
             ├── QVideoSink           recebe cada frame decodificado do QMediaPlayer headless
             │    └── videoFrameChanged → onVideoFrameChanged → enqueueFrame
             └── InferenceEngine (QThread)   inferência nativa (Pose + Comportamento rule-based)
                  ├── DXGI vendor detection → CUDA (NVIDIA) / DirectML / CPU (cascata)
                  ├── BehaviorScanner[3]   extração de 21 features + classifySimple() + _frameHistory
                  ├── 3× Ort::Session (Pose DLC)
                  └── std::thread por campo → inferência paralela via HW Acceleration

  └── CCDashboard (Comportamento Complexo)
        └── BSoidAnalyzer (C++ QObject)
             ├── BSoidWorker (QThread)  PCA 21→6 + K-Means++ k=7
             ├── populateTimelines()   preenche BehaviorTimeline (Regras + B-SOiD) de C++
             └── extractSnippets()    QThread + QProcess (FFmpeg) → clips por cluster
```

**Sinais emitidos (`InferenceController` → QML):**

```
readyReceived()                       modelo carregado, tracking ativo
trackReceived(campo, x, y, p)        nose  coordenadas em pixels do mosaico
bodyReceived(campo, x, y, p)         body  coordenadas em pixels do mosaico
dimsReceived(width, height)          resolução do vídeo
fpsReceived(fps)                     FPS extraído do metadata
infoReceived(msg)                    ex: "Modo GPU: DirectML ativo (AMD, DirectX 12)"
errorOccurred(msg)                   erro fatal
analyzingChanged()                   bool isAnalyzing
behaviorReceived(campo, labelId)     id do compartamento SimBA/B-SOiD detectado
```

---

## 9. Estrutura de Pastas

```
MindTrace/
├── onnxruntime_sdk/         SDK ONNX Runtime (configurado pelo build.bat)
└── qt/
    ├── src/
    │   ├── core/            main.cpp (registro de tipos QML)
    │   ├── manager/         ExperimentManager.cpp/.h (CRUD, Registry)
    │   ├── models/          TableModels, ArenaModel, ConfigModels
    │   ├── tracking/        InferenceController, InferenceEngine, BehaviorScanner, BehaviorTimeline
    │   └── analysis/        BSoidAnalyzer.h/cpp (PCA + K-Means + snippets)
    ├── qml/
    │   ├── core/            Navegação e componentes base (main.qml, GhostButton, Theme/)
    │   ├── shared/          LiveRecording.qml, SessionResultDialog.qml, BoutEditorPanel.qml, **DataView.qml + 5 aparato-views**
    │   ├── nor/             NORDashboard, ArenaSetup, NORSetupScreen
    │   ├── ca/              CADashboard, CAArenaSelection, CASetup, CAMetadataDialog
    │   ├── cc/              CCDashboard, CCArenaSelection, CCSetup, CCMetadataDialog
    │   └── ei/              EIDashboard, EISetup, EIMetadataDialog
    ├── data/                arenas.json, arena_config_referencia.json
    ├── scripts/             build.bat, setup_onnx.ps1
    ├── CMakeLists.txt
    └── resources.qrc
```

**Saída por experimento:**
```
<experimento>/
├── tracking_data.csv            coordenadas nose/body por frame
├── behavior_summary.csv         % de tempo por comportamento (rule-based)
├── sessions/
│   └── session_<ts>.json        metadados ricos (bouts, DI, por minuto)
└── bsoid_snippets/              gerado pelo BSoidAnalyzer após análise
    ├── grupo_1/
    │   ├── clip_1.mp4           segmento representativo (máx. 5s)
    │   └── timestamps.csv       start/end de cada clip
    └── grupo_N/
        └── ...
```

---

## 10. Sistema de Temas (Dark / Light)

O app suporta dark mode e light mode via `ThemeManager` (singleton QML em `qml/core/Theme/`).

- **Ativar/desativar:** botão de configurações (⚙) no canto superior direito de qualquer tela
- **Padrão:** dark mode (sempre inicia em dark)
- Todas as telas respondem ao tema em tempo real com animações suaves

---

## 11. Funcionalidades Principais

- **Registry System:** Salve experimentos em qualquer HD/Partição; o MindTrace gerencia o atalho no `registry.json`.
- **Sistema de Dias Customizável:** Na criação de qualquer experimento (NOR, CA, CC, EI), defina os nomes dos dias livremente via editor de chips (ex.: "Treino", "E1", "E2", "Teste"). O popup pós-sessão apresenta um ComboBox com esses nomes para seleção. Experimentos antigos são compatíveis via fallback automático.
- **Tratamento (ex-Droga):** Campo renomeado de "Droga" para "Tratamento" em todos os formulários e CSVs.
- **Excel Fix:** Suporte nativo a acentos em CSVs via UTF-8 BOM.
- **Offline Path:** Preenchimento automático do diretório de vídeo em análises offline.
- **Câmera Padrão (Ao Vivo):** Defina uma câmera padrão em Configurações para o modo ao vivo. O fluxo de arena tenta usar essa câmera automaticamente ao confirmar "Carregar Vídeo"; se ela não estiver disponível, o popup de seleção é exibido normalmente.
- **Velocidade:** Análise offline em 1x, 2x ou 4x com sincronização automática entre display e inferência.
- **Motor Comportamental:** Classificação baseada em regras (`BehaviorScanner::classifySimple()`) executada nativamente em C++. Sistema rule-based com detecção de:
  - **Sniffing**: focinho dentro da zona do objeto
  - **Rearing**: focinho bem acima do corpo (>30px) + bordas (parede)
  - **Resting**: velocidade < 0.05 m/s ou corpo parado
  - **Walking**: corpo movendo significativamente
  - **Grooming**: nariz ativo + corpo quase parado
- **Análise B-SOiD (Não-Supervisionada):** Descoberta de padrões comportamentais via clustering nativo (PCA + K-Means).
  - **Timeline Dupla:** Visualização comparativa entre Regras (supervisionadas) e B-SOiD (descobertas).
  - **Extração de Clips:** Segmentação automática de vídeo para validação visual dos grupos descobertos.
- **Abas de Dados com Tema Aparato-Específico:** Cada dashboard (NOR, CA, CC, EI) possui uma aba "Dados" que exibe os resultados com **detecção automática de aparato** e **theming único**:
  - **NOR:** Tema vermelho (#ab3d4c)  Vídeo, Animal, Campo, Dia, Par de Objetos, Tratamento
  - **CA:** Tema azul (#3d7aab)  Animal, Campo, Dia, Distância Total, Velocidade Média, Tratamento
  - **CC:** Tema roxo (#7a3dab)  Comportamento Complexo com locomoção e velocidade
  - **EI:** Dashboard/Setup/popup e Aba Dados (`EIDataView`) todos em tema **amarelo (#c8a000)** com color-coding semântico nas células: Latência (vermelho), Tempo Plataforma (verde), Tempo Grade (azul)
  - **Detecção automática:** Componente `DataView` escaneia headers CSV e renderiza view apropriada sem intervenção manual
  - **Recursos:** Botões Exportar/Salvar, BusyIndicator, scroll, edição de células, legends contextualizadas
- **Zonas Editáveis (CC)**: Em modo Comportamento Complexo, as zonas podem ser editadas na ArenaSetup (Shift+drag para mover, scroll para redimensionar). Tamanho e posição são salvos/restaurados.
- **Importar Arena**: Botão "📥 Importar Arena" nas telas de configuração (`ArenaSetup.qml` e `EIArenaSetup.qml`). Selecione a pasta de outro experimento para copiar sua configuração de arena. Aviso automático se houver incompatibilidade de forma (quadrada ↔ retangular) ou tipo de zona (objetos / plataforma-grade / padrão).
- **Revisão de Bouts (BoutEditorPanel):** Painel de revisão pós-sessão integrado ao CCDashboard na aba Comportamento. Carrega o histórico de frames classificados e permite editar labels, dividir bouts, mesclar bouts adjacentes, desfazer (undo 30 níveis) e exportar a revisão como CSV ou JSON. Exportação via `XMLHttpRequest PUT` diretamente do QML, sem backend C++.

---

## 12. Fluxo de Análise B-SOiD

Para realizar a descoberta de novos comportamentos após uma sessão de Comportamento Complexo (CC):

1.  **Finalização da Sessão:** Complete a análise offline ou ao vivo.
2.  **Exportação de Features:** Na aba "Comportamento" do CCDashboard, clique em "Analisar B-SOiD". O sistema exportará as 21 features cinemáticas por frame.
3.  **Processamento Nativo:** O motor `BSoidAnalyzer` executa a redução de dimensionalidade (PCA) e o agrupamento (K-Means) em background.
4.  **Linha do Tempo:** Explore os grupos gerados na `BehaviorTimeline` de SceneGraph (GPU).
5.  **Extração de Snippets:** Clique em "Extrair Clips" para gerar vídeos curtos (FFmpeg) de cada grupo comportamental na pasta `bsoid_snippets/` do experimento.

---

## 13. Histórico de Problemas Resolvidos

| Problema | Solução |
|---|---|
| p≈0.0001 (modelo cego) | Removida double mean subtraction  modelo já normaliza |
| Tracking desviado | Frame capture nativo + displayPlayer separado |
| `GetInputName` não existe | Usa `GetInputNameAllocated` (ONNX API 1.16+) |
| Subprocesso Python lento | ONNX nativo C++  sem subprocesso |
| Dessincronização em velocidade alta | Headless capped a 2× + `positionSyncTimer` 400ms |
| QAbstractVideoSurface removido no Qt 6 | Substituído por `QVideoSink` + `videoFrameChanged` |
| Suporte Windows 7 / 8 removido | Requer Windows 10/11 (DirectX 12). Qt 6.11.0 + ONNX 1.24.4 |
| Toggle de tema não funcionava | `qmldir` ausente em `Theme/`  sem ele cada componente recebe instância separada |
| App iniciava em tema claro | `loadThemePreference()` carregava valor salvo; removido do `Component.onCompleted` |
| Três SDKs na raiz | Unificado para um único `onnxruntime_sdk/`  usuário baixa só o que precisa |
| NVIDIA sem CUDA Toolkit caía em erro fatal | `tryCreateSessions()` por provider  CUDA falha → tenta DirectML → CPU (cascata automática) |
| Exclusão no Browser global falhava | ExperimentManager::deleteExperiment aceita contexto; SearchBrowser passa contexto do item |
| Pontos da arena sumiam ao arrastar | Implementado clamp (trava) de coordenadas [0, width/height] no onPositionChanged |
| Distância/ Tracking congelados | `accumulateExploration` abortava em arranjos sem zonas; Layout CC ajustado para fluir métricas genericamente |
| Estabilidade de UI | `BehaviorTimeline` criado para renderizar etogramas com GPU (SceneGraph) evitando drop de frames. |
| CSV Behavior Summary | C++ agora emite o arquivo behavior_summary.csv separando % de tempo no CA/CC automaticamente. |
| Erro `undefined inference` | Corrigido erro onde o QML não encontrava o InferenceController em LiveRecording através de um wrapper funcional. |
| Timeline B-SOiD | Implementado `populateTimelines()` nativo para preenchimento ultra-rápido de etogramas via SceneGraph. |
| `dayNames` não aparecia no popup pós-sessão | `readMetadataFromPath()` / `readMetadata()` em C++ nunca retornavam o campo `dayNames`. Adicionado parsing do array em ambas as funções. |
| Nomes de dias corrompidos pelo normalizador | `dayNameUtils.js` usava fuzzy matching Levenshtein (distância ≤2) que corrompia nomes customizados ("Teste2"→"Teste"). Substituído por normalização simples sem fuzzy. |
| Popups pós-sessão inconsistentes | NOR, CA e EI reescritos para o padrão CC-style com `CampoBlock`, altura dinâmica e cores por aparato: NOR=#ab3d4c, CA=#3d7aab, CC=#7a3dab, EI=#c8a000. |
| Fim de vídeo não abria popup (CA, EI) | Re-entrância no `displayPlayer` ao chamar `stop()` de dentro de `onMediaStatusChanged`. Corrigido com `Qt.callLater()` em ambos os handlers. |
| Timer nunca encerrava sessões 1/2-campo | `startSession()` resetava `timerStarted` após inicializar campos inativos como concluídos. Linha duplicada removida. |
| Tema EI azul (deveria ser amarelo) | `EIDashboard`, `EISetup` e Excel export (`formatar_mindtrace.py`) atualizados de `#3d7aab` para `#c8a000`. |
| Botão "Salvar Configuração" do CA aparecia amarelo | `EIArenaSetup` tinha cores hardcoded; CA e CC o reutilizam. Adicionadas props `primaryColor`/`secondaryColor`; cada aparato passa sua cor ao instanciar. |
| Popup pós-sessão não aparecia ao fim do vídeo (CA/CC/EI) | Race condition `onAnalyzingChanged` vs `Qt.callLater`. Corrigido com `_guardedSessionEnded()` + flag `_manualStopRequested` em `LiveRecording.qml`. |
| Aba Dados EI verde em vez de amarelo | `EIDataView.qml` tinha `accentColor: "#2f7a4b"`. Alterado para `"#c8a000"`. |
| Popup EI nunca abria | `EIMetadataDialog` estava com `parent: root` em vez de `parent: Overlay.overlay`. |
| Configuração de arena não reutilizável entre experimentos | Implementada função **Importar Arena** em `ArenaSetup.qml` e `EIArenaSetup.qml`: detecta incompatibilidade de forma/zona e exibe popup de aviso antes de importar. |
| `startLiveAnalysis` ignora resolução/FPS configurados | `LiveRecording.qml` tem `1920, 1080, 60.0` hardcoded  câmera sempre solicita 1080p/60fps independente da config DroidCam. **PENDENTE:** passar `0, 0, 0.0` para usar formato padrão da câmera. |
| Seleção de câmera repetida no modo ao vivo | Adicionada configuração de câmera padrão no `SettingsScreen.qml` (`defaultLiveCameraId`) com persistência em `mindtrace_settings.json`; `ArenaSetup.qml` e `EIArenaSetup.qml` aplicam automaticamente e fazem fallback para popup se indisponível. |
| `BoutEditorPanel is not a type` ao carregar CCDashboard | Componente em `qml/shared/` não estava registrado em `qml/shared/qmldir`. Adicionada linha `BoutEditorPanel 1.0 BoutEditorPanel.qml`. Regra: todo `.qml` novo em `shared/` precisa de entrada no `qmldir`. |
---

## 12. Esquiva Inibitória (EI)

Paradigma de **memória aversiva passiva** (step-through) para análise de medo e aprendizado associativo.

### Configuração Rápida

1. **Na tela inicial:** Clique no card ⚡ "Esquiva Inibitória"
2. **EISetup:**
   - Nome do experimento + diretório (opcional)
   - ✅ Tratamento (coluna extra no CSV)
   - 📅 **Editor de dias:** chips editáveis com nomes livres (padrão: Treino, E1E5, Teste). Adicione/remova dias com "+ Dia" e "×".
3. **Pós-sessão:** ComboBox com os dias definidos no setup.

### Métricas Coletadas

| Métrica | Significado |
|---|---|
| **Latência (s)** | Tempo até o primeiro exit da plataforma |
| **Tempo Plataforma (s)** | Acumulado na zona da plataforma |
| **Tempo Grade (s)** | Acumulado na zona da grade |
| **Bouts Plataforma** | Quantas vezes entrou na plataforma |
| **Bouts Grade** | Quantas vezes entrou na grade |
| **Distância (m)** | Locomoção total em metros |
| **Velocidade (m/s)** | Velocidade média durante a sessão |

### Arena EI

- **Tipo:** Quadrada com 2 zonas retangulares editáveis
- **Zona 0:** Plataforma (elevated, tipicamente esquerda)
- **Zona 1:** Grade (floor, tipicamente direita)
- **Edição:** Shift+drag para mover, scroll para redimensionar (igual CC)

---






## Atualizacao recente (Animal Lifecycle)

Foram adicionados recursos novos no aplicativo (mobile/web), mantendo integracao com o MindTrace:

- Busca de animais aceita ID e data de entrada (`YYYY-MM-DD` ou `DD/MM/YYYY`).
- Novo atalho de configuracao (icone de engrenagem) no topo da interface.
- Preferencias por usuario: tema (`light`/`dark`) e idioma (`pt`/`en`/`es`).
- Controle global de formato de data para todos os usuarios, alterado apenas por admin local.

Importante:
- Nenhum segredo deve ser colocado em README.
- Segredos continuam apenas em arquivos `.env` locais.
- Veja os detalhes operacionais em `animal-lifecycle-platform/README.md`.
