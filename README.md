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
| ONNX Runtime | 1.24.4 | Bundled no repositório (ver seção 2) |
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

Baixe em [github.com/microsoft/onnxruntime/releases/tag/v1.24.4](https://github.com/microsoft/onnxruntime/releases/tag/v1.24.4):

| GPU | Arquivo | Provider ativo |
|---|---|---|
| AMD / Intel | `onnxruntime-win-x64-1.24.4.zip` | DirectML → CPU |
| NVIDIA | `onnxruntime-win-x64-gpu-1.24.4.zip` | CUDA → CPU |

Extraia **dentro de** `qt/` de forma que o resultado seja:

```
qt/onnxruntime-win-x64-1.24.4/
    include/
    lib/
        onnxruntime.lib
        onnxruntime.dll
        onnxruntime_providers_shared.dll
        ...
```

O provider de GPU é detectado automaticamente em runtime via DXGI (sem recompilar).

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
4. Copia DLLs do ONNX Runtime e o modelo para `build/`
5. Executa `MindTrace.exe`

---

## 5. Modelo Neural

- **Arquitetura:** ResNet-50 via DeepLabCut (MobileNetV2 em treinamento)
- **Bodyparts:** `nose` (canal 0), `body` (canal 1)
- **Config:** `qt/pose_cfg.yaml` — `stride: 8.0`, `locref_stdev: 7.2801`

---

## 6. Vídeo e Mosaico

- **Fonte:** DVR Intelbras — mosaico 2×2 em arquivo único
- **Resolução:** 720×480 @ ~29.97 fps
- **Campos ativos (3):**
  - Campo 0: Topo-Esquerda `(0, 0)` — 360×240
  - Campo 1: Topo-Direita `(360, 0)` — 360×240
  - Campo 2: Baixo-Esquerda `(0, 240)` — 360×240

---

## 7. Arquitetura do Sistema

```
MindTrace.exe (Qt 6.11.0 / C++17 / ONNX Runtime 1.24.4)
  └── LiveRecording.qml
       └── DlcController (C++)
            ├── QVideoSink          — recebe cada frame decodificado do QMediaPlayer headless
            │    └── videoFrameChanged → onVideoFrameChanged → enqueueFrame
            └── OnnxTracker (QThread)  — inferência ONNX nativa multi-thread
                 ├── DXGI vendor detection → CUDA (NVIDIA) / DirectML (AMD/Intel) / CPU
                 ├── 3× Ort::Session (uma por campo)
                 └── std::thread por campo → inferência paralela
```

**Sinais emitidos (`DlcController` → QML):**

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

## 8. Estrutura de Pastas

```
qt/
├── src/
│   ├── main.cpp
│   ├── ExperimentManager.cpp/.h
│   ├── ExperimentTableModel.cpp/.h
│   ├── ArenaModel.cpp/.h
│   ├── ArenaConfigModel.cpp/.h
│   ├── dlc_controller.cpp/.h       — QVideoSink + QMediaPlayer headless → OnnxTracker
│   └── onnx_tracker.cpp/.h         — QThread de inferência ONNX (DXGI + CUDA/DML/CPU)
├── onnxruntime-win-x64-1.24.4/     — ONNX Runtime C++ SDK (bundled)
│   ├── include/
│   └── lib/
├── qml/                            — todos os arquivos QML (Qt 6, version-less imports)
├── data/                           — arenas.json, arena_config_referencia.json
├── scripts/
│   └── build.bat                   — build completo (CMake + windeployqt + DLLs)
├── CMakeLists.txt
└── resources.qrc
```

---

## 9. Modos de Análise

| Modo | Input | Timer | Velocidade |
|---|---|---|---|
| Offline | Vídeo pré-gravado | Escala com speed | 1×, 2×, 4× |
| Ao vivo | Câmera | 1:1 real-time | Fixo 1× |

---

## 10. Histórico de Problemas Resolvidos

| Problema | Solução |
|---|---|
| p≈0.0001 (modelo cego) | Removida double mean subtraction — modelo já normaliza |
| Tracking desviado | Frame capture nativo + displayPlayer separado |
| `GetInputName` não existe | Usa `GetInputNameAllocated` (ONNX API 1.16+) |
| Subprocesso Python lento | ONNX nativo C++ — sem subprocesso |
| Dessincronização em velocidade alta | Headless capped a 2× + `positionSyncTimer` 400ms |
| QAbstractVideoSurface removido no Qt 6 | Substituído por `QVideoSink` + `videoFrameChanged` |
| Windows 7 / 8 removidos | Requer Windows 10/11 (DirectX 12). Qt 6.11.0 + ONNX 1.24.4 |
