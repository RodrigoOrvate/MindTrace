# MindTrace — MemoryLab / UFRN

Sistema de tracking comportamental de ratos para paradigmas **NOR (Novel Object Recognition)** e **Campo Aberto (Open Field)**, rodando **nativamente em C++** com ONNX Runtime. Sem subprocesso Python — toda inferência ocorre dentro do `MindTrace.exe`.

> **Sistema operacional:** Windows 10 ou 11 (64-bit) — obrigatório (usa DirectX 12 / DirectML)

---

## 1. Pré-requisitos

### Software obrigatório

| Componente | Versão mínima | Observação |
|---|---|---|
| Windows | 10 / 11 (64-bit) | DirectX 12 nativo — Win 7/8 não suportados |
| Visual Studio | 2022 ou superior | Instalar workload "Desenvolvimento para desktop com C++" |
| CMake | 3.25+ | Adicionar ao PATH durante instalação |
| Qt | 6.11.0 | Ver seção abaixo — instalar via Qt Online Installer |
| ONNX Runtime | 1.24.4 | Configurado automaticamente pelo `build.bat` (ver Seção 2) |
| Python | 3.12+ (opcional) | Apenas para debug/validação do modelo |

### Instalação do Qt 6.11.0

Baixe o **Qt Online Installer** em [qt.io/download](https://www.qt.io/download-open-source) (use conta Qt gratuita).

Durante a instalação, selecione em **Qt 6.11.0 > MSVC 2022 64-bit**:

| Módulo | Obrigatório | Finalidade |
|---|---|---|
| Qt Multimedia | ✅ Sim | QMediaPlayer, QVideoSink — pipeline de vídeo |
| Qt Shader Tools | ✅ Sim | Dependência de renderização de vídeo |

Todos os outros módulos podem ficar **desmarcados**.

Certifique-se de que Qt está instalado em `C:\Qt\6.11.0\msvc2022_64\`.  
Se o caminho for diferente, edite a variável `QT_DIR` no início de `qt\scripts\build.bat`.

---

## 2. ONNX Runtime 1.24.4

> Você só precisa **baixar um pacote** — o que corresponde à sua GPU.  
> O código detecta a GPU automaticamente em runtime (via DXGI) e usa o melhor provider disponível.

### Passo 1 — Configuração Automática (Recomendado)

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

> **Não execute o `setup_onnx.ps1` diretamente.** Use sempre o `build.bat` — ele garante o ambiente MSVC correto antes de qualquer operação.

---

### Passo 2 — Configuração Manual (Fallback)

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
├── onnxruntime_sdk/        — Raiz do SDK
│   ├── include/            — Cabeçalhos (.h)
│   └── lib/                — DLLs e .lib
└── qt/                     — Código-fonte
```

> **Atenção:** a pasta `qt/` contém o código-fonte. O `onnxruntime_sdk` deve ficar na raiz (`MindTrace/`), não dentro de `qt/`.

### Aviso para usuários NVIDIA (CUDA)

O pacote `onnxruntime-win-x64-gpu` **não inclui** os drivers CUDA — apenas o motor de inferência.  
Para que o provider CUDA funcione, você precisa instalar separadamente:

| Dependência | Versão recomendada | Download |
|---|---|---|
| CUDA Toolkit | 12.6.3 | [Baixar CUDA 12.6.3](https://developer.nvidia.com/cuda-12-6-3-download-archive) · [Arquivo completo](https://developer.nvidia.com/cuda-toolkit-archive) |
| cuDNN | 9.x (para CUDA 12) | [Baixar cuDNN](https://developer.nvidia.com/cudnn-downloads) · [Arquivo completo](https://developer.nvidia.com/rdp/cudnn-archive) |

#### Instalando o cuDNN (passo obrigatório após o download)

A partir do **cuDNN 8**, o instalador **não copia mais os arquivos para dentro da pasta do CUDA** — ele instala em um diretório separado. Você precisa copiar as DLLs manualmente.

**1. Localize a pasta do cuDNN instalado:**
```
C:\Program Files\NVIDIA\CUDNN\v9.x\bin\
```
Dentro de `bin\` haverá uma subpasta com a versão do CUDA correspondente (ex: `12.6\`). Use a que bater com a versão do seu CUDA Toolkit.

**2. Copie todas as DLLs dessa subpasta para o `bin\` do CUDA:**

| Origem | Destino |
|---|---|
| `C:\Program Files\NVIDIA\CUDNN\v9.x\bin\12.6\*.dll` | `C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.6\bin\` |

> Se instalou CUDA 13.x em vez de 12.x, o procedimento é o mesmo — use a subpasta `13.x\` do cuDNN e copie para o `bin\` do CUDA 13.

**3. Verifique** que o arquivo `cudnn64_9.dll` está em:
```
C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.6\bin\cudnn64_9.dll
```

Após copiar, rode `scripts\build.bat` e o log do app deve exibir `"Modo GPU: CUDA ativo (NVIDIA)"`.

> **Sem esses drivers, o CUDA falha silenciosamente e o app cai automaticamente para DirectML (DirectX 12).** O comportamento é idêntico ao de placas AMD/Intel — sem perda de funcionalidade, apenas menor desempenho de inferência comparado ao CUDA nativo.  
> Você verá no log: `"Modo GPU: DirectML ativo (NVIDIA, DirectX 12)"` em vez de `"Modo GPU: CUDA ativo (NVIDIA)"`.

---

## 3. Modelo ONNX

Coloque o arquivo `Network-MemoryLab-v2.onnx` em `qt/` (não incluído no repositório por tamanho).

- **Input:** `[1, 240, 360, 3]` — RGB float32, **sem** subtração de média (o grafo já normaliza)
- **Output 0:** `[1, 30, 46, 2]` — scoremap (heatmaps nose/body)
- **Output 1:** `[1, 30, 46, 4]` — locref (offsets sub-pixel)
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

O código detecta automaticamente a GPU via **DXGI** na inicialização e tenta os providers em cascata — sem necessidade de recompilar:

| GPU detectada | Provider tentado (ordem) | Resultado se falhar |
|---|---|---|
| NVIDIA | CUDA → DirectML → CPU | Fallback automático para o próximo |
| AMD / Intel | DirectML → CPU | Fallback automático para CPU |
| Nenhuma | CPU | — |

O status é exibido na área de log durante o carregamento do modelo, ex.:  
`"Modo GPU: CUDA ativo (NVIDIA)"` ou `"Modo GPU: DirectML ativo (NVIDIA, DirectX 12)"`.

---

## 6. Modelo Neural

- **Arquitetura:** ResNet-50 via DeepLabCut (MobileNetV2 em treinamento)
- **Bodyparts:** `nose` (canal 0), `body` (canal 1)
- **Config:** `qt/pose_cfg.yaml` — `stride: 8.0`, `locref_stdev: 7.2801`

---

## 7. Vídeo e Mosaico

- **Fonte:** DVR Intelbras — mosaico 2×2 em arquivo único
- **Resolução:** 720×480 @ ~29.97 fps
- **Campos ativos (3):**
  - Campo 0: Topo-Esquerda `(0, 0)` — 360×240
  - Campo 1: Topo-Direita `(360, 0)` — 360×240
  - Campo 2: Baixo-Esquerda `(0, 240)` — 360×240

---

## 8. Arquitetura do Sistema

```
MindTrace.exe (Qt 6.11.0 / C++17 / ONNX Runtime 1.24.4)
  └── LiveRecording.qml
        └── InferenceController (C++)
             ├── QVideoSink          — recebe cada frame decodificado do QMediaPlayer headless
             │    └── videoFrameChanged → onVideoFrameChanged → enqueueFrame
             └── InferenceEngine (QThread)  — inferência Dual-Model nativa (Pose + Comportamento)
                  ├── DXGI vendor detection → CUDA (NVIDIA) / DirectML / CPU (cascata)
                  ├── BehaviorScanner — extração de métricas espaciais para IA
                  ├── 3× Ort::Session (Pose) + 3× Ort::Session (Comportamento)
                  └── std::thread por campo → inferência paralela via HW Acceleration
```

**Sinais emitidos (`InferenceController` → QML):**

```
readyReceived()                      — modelo carregado, tracking ativo
trackReceived(campo, x, y, p)       — nose — coordenadas em pixels do mosaico
bodyReceived(campo, x, y, p)        — body — coordenadas em pixels do mosaico
dimsReceived(width, height)         — resolução do vídeo
fpsReceived(fps)                    — FPS extraído do metadata
infoReceived(msg)                   — ex: "Modo GPU: DirectML ativo (AMD, DirectX 12)"
errorOccurred(msg)                  — erro fatal
analyzingChanged()                  — bool isAnalyzing
behaviorReceived(campo, labelId)    — id do compartamento SimBA/B-SOiD detectado
```

---

## 9. Estrutura de Pastas

```
MindTrace/
├── onnxruntime_sdk/        — SDK ONNX Runtime (configurado pelo build.bat)
└── qt/
    ├── src/
    │   ├── core/           — main.cpp
    │   ├── manager/        — ExperimentManager.cpp/.h (CRUD, Registry)
    │   ├── models/         — TableModels, ArenaModel, ConfigModels
    │   └── tracking/       — InferenceController, InferenceEngine
    ├── qml/
    │   ├── core/           — Navegação e componentes base (main.qml, GhostButton, Theme/)
    │    │   ├── shared/         — LiveRecording, SessionResultDialog (comuns)
    │   ├── nor/            — NORDashboard, ArenaSetup, NORSetupScreen
    │   ├── ca/             — CADashboard, CAArenaSelection, CASetup, CAMetadataDialog
    │   ├── cc/             — CCDashboard, CCArenaSelection, CCSetup, CCMetadataDialog
    ├── data/               — arenas.json, arena_config_referencia.json
    ├── scripts/            — build.bat, setup_onnx.ps1
    ├── CMakeLists.txt
    └── resources.qrc
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
- **Session Codes:** Use `TR` (Treino), `RA` (Reativação) e `TT` (Teste). O sistema calcula o dia e valida a configuração automaticamente.
- **Excel Fix:** Suporte nativo a acentos em CSVs via UTF-8 BOM.
- **Offline Path:** Preenchimento automático do diretório de vídeo em análises offline.
- **Velocidade:** Análise offline em 1x, 2x ou 4x com sincronização automática entre display e inferência.
- **Motor Comportamental:** Classificação baseada em regras (`BehaviorScanner::classifySimple()`) executada nativamente em C++. Sistema rule-based com detecção de:
  - **Sniffing**: focinho dentro da zona do objeto
  - **Rearing**: focinho bem acima do corpo (>30px) + bordas (parede)
  - **Resting**: velocidade < 0.05 m/s ou corpo parado
  - **Walking**: corpo movendo significativamente
  - **Grooming**: nariz ativo + corpo quase parado
- **Zonas Editáveis (CC)**: Em modo Comportamento Complexo, as zonas podem ser editadas na ArenaSetup (Shift+drag para mover, scroll para redimensionar). Tamanho e posição são salvos/restaurados.

---

## 12. Histórico de Problemas Resolvidos

| Problema | Solução |
|---|---|
| pâ‰ˆ0.0001 (modelo cego) | Removida double mean subtraction — modelo já normaliza |
| Tracking desviado | Frame capture nativo + displayPlayer separado |
| `GetInputName` não existe | Usa `GetInputNameAllocated` (ONNX API 1.16+) |
| Subprocesso Python lento | ONNX nativo C++ — sem subprocesso |
| Dessincronização em velocidade alta | Headless capped a 2× + `positionSyncTimer` 400ms |
| QAbstractVideoSurface removido no Qt 6 | Substituído por `QVideoSink` + `videoFrameChanged` |
| Suporte Windows 7 / 8 removido | Requer Windows 10/11 (DirectX 12). Qt 6.11.0 + ONNX 1.24.4 |
| Toggle de tema não funcionava | `qmldir` ausente em `Theme/` — sem ele cada componente recebe instância separada |
| App iniciava em tema claro | `loadThemePreference()` carregava valor salvo; removido do `Component.onCompleted` |
| Três SDKs na raiz | Unificado para um único `onnxruntime_sdk/` — usuário baixa só o que precisa |
| NVIDIA sem CUDA Toolkit caía em erro fatal | `tryCreateSessions()` por provider — CUDA falha → tenta DirectML → CPU (cascata automática) |
| Exclusão no Browser global falhava | ExperimentManager::deleteExperiment aceita contexto; SearchBrowser passa contexto do item |
| Pontos da arena sumiam ao arrastar | Implementado clamp (trava) de coordenadas [0, width/height] no onPositionChanged |
| Distância/ Tracking congelados | `accumulateExploration` abortava em arranjos sem zonas; Layout CC ajustado para fluir métricas genericamente |
| Estabilidade de UI | `BehaviorTimeline` criado para renderizar etogramas com GPU (SceneGraph) evitando drop de frames. |
| CSV Behavior Summary | C++ agora emite o arquivo behavior_summary.csv separando % de tempo no CA/CC automaticamente. |