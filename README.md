# MindTrace - Project Guide (Neuroscience Lab)

## Current Status: Native ONNX Inference (C++) — tracking ao vivo

Sistema de tracking ao vivo que processa o vídeo frame a frame **nativamente em C++** usando ONNX Runtime + `QMediaPlayer` headless com captura de frames via `QAbstractVideoSurface`. Sem subprocesso Python — toda a inferência roda dentro do `MindTrace.exe`.

---

## 1. Modelo Neural

- **Arquitetura:** ResNet-50 via DeepLabCut — exportado para ONNX
- **Bodyparts:** `nose` (canal 0) e `body` (canal 1)
- **Arquivo ONNX:** `qt/Network-MemoryLab-v2.onnx`
  - Input: `[1, 240, 360, 3]` — RGB uint8, **sem** subtracao de media (já embutida no grafo)
  - Output 0 (scoremap): `[1, 30, 46, 2]` — heatmaps nose+body
  - Output 1 (locref): `[1, 30, 46, 4]` — offsets sub-pixel (dx_nose, dy_nose, dx_body, dy_body)
  - **IMPORTANTE:** Nao subtrair `[123.68, 116.779, 103.939]` — modelo já normaliza internamente.
- **pose_cfg.yaml:** `qt/pose_cfg.yaml` — `stride: 8.0`, `locref_stdev: 7.2801`
- **Versão descontinuada:** `Network-MemoryLab-Sigmoidv1.onnx`

---

## 2. Vídeo e Mosaico

- **Câmera:** Intelbras DVR — mosaico 2×2 em arquivo único
- **Resolução:** 720×480 @ ~29.97fps
- **Layout:** 3 gaiolas ativas:
  - Campo 0: Topo-Esquerda `(0,0)`
  - Campo 1: Topo-Direita `(360,0)`
  - Campo 2: Baixo-Esquerda `(0,240)`
- **Crop por campo:** 360×240 — match exato com input do modelo (sem resize).

---

## 3. Arquitetura do Sistema

```
MindTrace.exe (Qt 5.12 / C++ / ONNX Runtime nativo)
  └── LiveRecording.qml
       └── DlcController (C++)
            ├── FrameCaptureSurface     — captura frames do QMediaPlayer headless em CPU memory
            │    └── frameReady → onFrameCaptured → enqueueFrame
            └── OnnxTracker (QThread)  — inferência ONNX nativa multi-thread
                 ├── 3x Ort::Session (uma por campo)
                 └── std::thread por campo → inferência paralela
```

**Sinais emitidos (`DlcController` → QML):**

```
readyReceived()                       — modelo carregado, tracking ativo
trackReceived(campo, x, y, p)        — nose — coordenadas em pixels do mosaico
bodyReceived(campo, x, y, p)         — body — coordenadas em pixels do mosaico
dimsReceived(width, height)          — resolucao do vídeo
fpsReceived(fps)                     — FPS extraído do metadata
errorOccurred(msg)                   — erro fatal
analyzingChanged()                   — estado de análise
```

---

## 4. Componentes Principais (estrutura de pastas)

```
qt/
├── src/                          — todo código C++ (.cpp, .h)
│   ├── main.cpp
│   ├── ExperimentManager.cpp/.h
│   ├── ExperimentTableModel.cpp/.h
│   ├── ArenaModel.cpp/.h
│   ├── ArenaConfigModel.cpp/.h
│   ├── dlc_controller.cpp/.h     — orquestrador: QMediaPlayer headless + OnnxTracker
│   └── onnx_tracker.cpp/.h       — thread de inferência ONNX nativa
├── onnxruntime-win-x64-1.16.3/  — ONNX Runtime C++ SDK (bundled)
│   ├── include/                  — headers da API C++
│   └── lib/                      — onnxruntime.lib + DLLs
├── qml/                          — todos os arquivos QML
├── data/                         — arenas.json, arena_config_referencia.json
├── scripts/                      — build.bat
├── build/                        — output do build (gerado)
├── dlc_processor.py              — [LEGACY] fonte do processor Python
├── dlc_processor.exe             — [LEGACY] binário PyInstaller (nao usado mais)
├── CMakeLists.txt                — build Qt 5.12 MSVC NMake + ONNX Runtime
└── resources.qrc                 — Qt resources
```

### `onnx_tracker.h / .cpp` — Thread de inferência ONNX

- Herda `QThread` — roda em background thread dedicado
- **3 × `Ort::Session`** — uma sessao por campo para inferência paralela
- `enqueueFrame()` — thread-safe, single-slot queue (sempre processa frame mais recente)
- `processJob()` — crops preparados na main thread, depois `std::thread` por campo
- `inferCrop()` — monta tensor float32 `[1, H, W, 3]`, roda ONNX, aplica locref, emite sinais
- Modelo carregado dentro de `run()` via `loadModel()` (antes de `start()`)

### `dlc_controller.h / .cpp` — Orquestrador

- `FrameCaptureSurface` (herda `QAbstractVideoSurface`) — força QMediaPlayer a decodificar em CPU memory (sem DXVA), entregando frames para inferência
- Headless `QMediaPlayer` — player dedicado à captura, sem exibição visual
- QML usa `MediaPlayer` separado para exibição (`displayPlayer`)
- `startAnalysis()` — inicia `OnnxTracker` + headless player simultaneamente
- Sinais do tracker chegam via `QueuedConnection` (thread-safe para QML)

### `LiveRecording.qml`
- Canvas overlay: linha skeleton body→nose + ponto vermelho (nose) + laranja (body)
- Timer de sessão 300s independente por campo, inicia na 1ª detecção com `p > 0.5`
- Zona de exploração com bout counting + índice de discriminação

### `build.bat`
- Limpa `build/` automaticamente
- Usa `vswhere` para detectar MSVC (VS 2017/2019/2022)
- CMake + NMake (C++17, Qt 5.12)
- Copia DLLs do ONNX Runtime (`onnxruntime.dll`, `onnxruntime_providers_shared.dll`)
- Copia modelo ONNX + `pose_cfg.yaml` para `build/`

---

## 5. Build

```cmd
cd "C:\MindTrace - Copia\qt"
scripts\build.bat
```

Isto: configura CMake (C++17, Qt 5.12 MSVC), compila, roda windeployqt, copia DLLs do ONNX Runtime + modelo ONNX para `build/`, executa MindTrace.exe.

### Dependências de build

| Componente | Versão | Nota |
|---|---|---|
| Qt | 5.12.12 LTS | MSVC 2017 64-bit (compatível Win7) |
| CMake | 3.12+ | NMake Makefiles generator |
| MSVC | 14.2+ (VS 2019+) | ONNX Runtime C++ API exige `constexpr` (VS 14.1 falha) |
| ONNX Runtime | 1.16.3 | CPU Execution Provider, bundled |

---

## 6. Comandos de Debug

```bash
cd "C:\MindTrace - Copia\qt"

# Teste rápido de confiança do modelo (Python isolado)
venv_lab38\Scripts\activate
python -c "
import cv2, numpy as np, onnxruntime as ort
sess = ort.InferenceSession('Network-MemoryLab-v2.onnx', providers=['CPUExecutionProvider'])
inp = sess.get_inputs()[0].name
cap = cv2.VideoCapture('TT 1-2-4.MPG')
cap.set(cv2.CAP_PROP_POS_FRAMES, 200); _, f = cap.read()
rgb = cv2.resize(cv2.cvtColor(f, cv2.COLOR_BGR2RGB), (360,240)).astype(np.float32)
p = sess.run([sess.get_outputs()[0].name], {inp: np.expand_dims(rgb, 0)})[0][0,:,:,0].max()
print(f'p={p:.4f}  (esperado >0.9)')
"

# Diagnóstico visual
python debug_prediction.py --video "TT 1-2-4.MPG" --model Network-MemoryLab-v2.onnx --frame 200
```

---

## 7. Problemas Conhecidos — Histórico

| Problema | Status |
|---|---|
| p≈0.0001 (modelo cego) | **Resolvido** — removida double mean subtraction |
| Stride X errado | **Resolvido** — usa pose_cfg.yaml (stride=8.0) |
| Julia VideoIO lê frames diferentes do OpenCV | **Resolvido** — removido Julia do pipeline |
| Tracking desviado/aparece antes do rato | **Resolvido** — processor com sleep(1/fps) |
| `GetInputName` não é membro de `Ort::Session` | **Resolvido** — usa `GetInputNameAllocated` (API 1.16+) |
| Lento com subprocesso Python + PyInstaller | **Resolvido** — ONNX nativo C++, sem subprocesso |
| Tracking sem sincronia espaciotemporal | **Resolvido** — frame capture nativo + displayPlayer separado |
