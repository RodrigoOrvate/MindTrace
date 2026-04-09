# MindTrace — MemoryLab / UFRN

Sistema de tracking comportamental de ratos em arenas NOR, rodando **nativamente em C++** com ONNX Runtime. Sem subprocesso Python — toda inferência ocorre dentro do `MindTrace.exe`.

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
| ONNX Runtime | 1.24.4 | Baixar pacote DirectML (ver Seção 2) |
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

O projeto inclui um script que baixa e organiza as DLLs e cabeçalhos automaticamente conforme sua GPU:

1. Abra o terminal na pasta `qt/`.
2. Execute o comando:
   ```cmd
   powershell -ExecutionPolicy Bypass -File scripts\setup_onnx.ps1
   ```
3. Escolha entre **DML** (AMD ou Intel) ou **CUDA** (NVIDIA).

> **Atenção:** O `build.bat` também detectará se o SDK está faltando e oferecerá rodar este script automaticamente no primeiro build.

---

### Passo 2 — Configuração Manual (Fallback)

Se o script falhar ou você preferir controle manual, organize os arquivos conforme abaixo:

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
├── onnxruntime_sdk/        ← Raiz do SDK
│   ├── include/            ← Cabeçalhos (.h)
│   └── lib/                ← DLLs e .lib
└── qt/                     ← Código-fonte
```

> **Atenção:** a pasta `qt/` contém o código-fonte. O `onnxruntime_sdk` deve ficar na raiz (`MindTrace/`), não dentro de `qt/`.

Pronto. O build vai encontrar os headers e a lib automaticamente.

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
2. Configura CMake (C++17, NMake Makefiles)
3. Compila e roda `windeployqt`
4. Copia DLLs do ONNX Runtime de `onnxruntime_sdk\lib\` para `build\`
5. Executa `MindTrace.exe`

---

## 5. Detecção de GPU em Runtime

O código detecta automaticamente a GPU via **DXGI** na inicialização — sem necessidade de recompilar:

| GPU detectada | Provider ONNX ativo | Pacote necessário |
|---|---|---|
| NVIDIA | CUDA | `onnxruntime-win-x64-gpu-1.24.4` |
| AMD / Intel | DirectML (DirectX 12) | `onnxruntime-win-x64-1.24.4` |
| Nenhuma | CPU (fallback automático) | qualquer um |

O status é exibido na área de log durante o carregamento do modelo, ex.:  
`"Modo GPU: CUDA ativo (NVIDIA)"` ou `"Modo GPU: DirectML ativo (AMD, DirectX 12)"`.

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
            └── InferenceEngine (QThread)  — inferência ONNX nativa multi-thread
                 ├── DXGI vendor detection → CUDA (NVIDIA) / DirectML (AMD/Intel) / CPU
                 ├── 3× Ort::Session (uma por campo)
                 └── std::thread por campo → inferência paralela
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
```

---

## 9. Estrutura de Pastas

```
MindTrace/
├── onnxruntime_sdk/    ← SDK ONNX Runtime (você baixa e renomeia)
└── qt/
    ├── src/
    │   ├── core/           — main.cpp
    │   ├── manager/        — ExperimentManager.cpp/.h (CRUD, Registry)
    │   ├── models/         — TableModels, ArenaModel, ConfigModels
    │   └── tracking/       — InferenceController, InferenceEngine
    ├── qml/
    │   ├── core/           — Navegação e componentes base (main.qml, GhostButton, Theme/)
    │   ├── shared/         — LiveRecording, SessionResultDialog (comuns)
    │   └── nor/            — NORDashboard, ArenaSetup, NORSetupScreen
    ├── data/               — arenas.json, arena_config_referencia.json
    ├── scripts/            — build.bat
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

---

## 12. Histórico de Problemas Resolvidos

| Problema | Solução |
|---|---|
| p≈0.0001 (modelo cego) | Removida double mean subtraction — modelo já normaliza |
| Tracking desviado | Frame capture nativo + displayPlayer separado |
| `GetInputName` não existe | Usa `GetInputNameAllocated` (ONNX API 1.16+) |
| Subprocesso Python lento | ONNX nativo C++ — sem subprocesso |
| Dessincronização em velocidade alta | Headless capped a 2× + `positionSyncTimer` 400ms |
| QAbstractVideoSurface removido no Qt 6 | Substituído por `QVideoSink` + `videoFrameChanged` |
| Suporte Windows 7 / 8 removido | Requer Windows 10/11 (DirectX 12). Qt 6.11.0 + ONNX 1.24.4 |
| Toggle de tema não funcionava | `qmldir` ausente em `Theme/` — sem ele cada componente recebe instância separada |
| App iniciava em tema claro | `loadThemePreference()` carregava valor salvo; removido do `Component.onCompleted` |
| Três SDKs na raiz | Unificado para um único `onnxruntime_sdk/` — usuário baixa só o que precisa |
