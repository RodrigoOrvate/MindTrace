# MindTrace - Project Guide (Neuroscience Lab)

## Current Status: DeepLabCut ONNX Integration — tracking ao vivo (PyInstaller dlc_processor.exe)

Sistema de tracking ao vivo que processa o vídeo frame a frame enquanto o vídeo rola no Qt player. O `dlc_processor.exe` (PyInstaller) roda como subprocesso separado, sincronizado ao FPS do vídeo via `time.sleep()`.

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
MindTrace.exe (Qt 5.12 / C++)
  └── LiveRecording.qml
       └── DlcController (C++)         — manage QProcess + parse STDOUT
            └── dlc_processor.exe      — PyInstaller subprocess (onnxruntime+cv2+numpy)
```

**Protocolo STDOUT (`dlc_processor.py` → C++):**

```
FPS,<fps>                         — video FPS, ex: FPS,29.9700
DIMS,<W>,<H>                      — video resolution, ex: DIMS,720,480
TRACK,<campo>,<x>,<y>,<p>,<frame> — nose coords em pixels do mosaico
BODY,<campo>,<x>,<y>,<p>,<frame>  — body coords em pixels do mosaico
ERRO,<msg>                        — fatal error
FIM                               — video processado
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
│   └── dlc_controller.cpp/.h     — wrapper QProcess para dlc_processor
├── qml/                          — todos os arquivos QML
├── data/                         — arenas.json, arena_config_referencia.json
├── debug/                        — debug_prediction.py
├── scripts/                      — build.bat, run.bat
├── build/                        — output do build (gerado)
├── dlc_processor.py              — fonte do processor (atualizado)
├── dlc_processor.exe             — binário PyInstaller (62MB, com tudo embutido)
├── CMakeLists.txt                — build Qt 5.12 MSVC NMake
└── resources.qrc                 — Qt resources
```

### `dlc_processor.py`
- Varre vídeo frame a frame **ao vivo**
- Processa 3 crops (3 campos) por frame
- Aplica locref sub-pixel
- **`time.sleep(1/fps)`** entre frames para sincronizar com velocidade do vídeo
- Envia TRACK/BODY com frame number via STDOUT

### `dlc_controller.cpp` / `dlc_controller.h`
- Prioriza `dlc_processor.exe` (PyInstaller) → tem tudo embutido
- Fallback: `venv_lab38/Scripts/python.exe` + `dlc_processor.py`
- Bufferiza resultados por frame → `getTrackingsForFrame(frameNum)`
- Sinais emitidos: `fpsReceived`, `dimsReceived`, `trackReceived`, `bodyReceived`, `analyzingChanged`

### `LiveRecording.qml`
- Canvas overlay: linha skeleton body→nose + ponto vermelho (nose) + laranja (body)
- Timer de sessão 300s independente por campo, inicia na 1ª detecção com `p > 0.5`
- Zona de exploração com bout counting + índice de discriminação

### `build.bat`
- Limpa `build/`, salva `dlc_processor.exe` antes se existir
- Copia de volta depois do rebuild
- Qt 5.12 + MSVC via NMake

---

## 5. Ambiente Python

- **venv correto:** `venv_lab38` (Python 3.8)
- **Nao usar:** `venv_lab` (Python 3.11 — deps incompatíveis)
- **Dependências:** `onnxruntime`, `opencv-python`, `numpy`, `pyyaml`, `pyinstaller`

---

## 6. Build

```cmd
cd "C:\MindTrace - Copia\qt"
scripts\build.bat
```

Isto: compila C++, roda windeployqt, copia `dlc_processor.exe` + modelo ONNX para `build/`, executa MindTrace.exe.

**Reconstruir `dlc_processor.exe`** (quando alterar `dlc_processor.py`):
```cmd
cd "C:\MindTrace - Copia\qt"
venv_lab38\Scripts\python.exe -m PyInstaller --onefile dlc_processor.py --distpath build/venv_build --workpath build/pytmp --noconfirm
copy /y build\venv_build\dlc_processor.exe dlc_processor.exe
```

---

## 7. Comandos de Debug

```bash
cd "C:\MindTrace - Copia\qt"
venv_lab38\Scripts\activate

# Teste rápido de confiança
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

# Processor isolado (stdout mostra TRACK/BODY)
python dlc_processor.py --video "TT 1-2-4.MPG" --model Network-MemoryLab-v2.onnx
```

---

## 8. Problemas Conhecidos — Histórico

| Problema | Status |
|---|---|
| p≈0.0001 (modelo cego) | **Resolvido** — removida double mean subtraction |
| Stride X errado | **Resolvido** — usa pose_cfg.yaml (stride=8.0) |
| Julia VideoIO lê frames diferentes do OpenCV | **Resolvido** — removido Julia do pipeline |
| Tracking desviado/aparece antes do rato | **Resolvido** — processor com sleep(1/fps) + frame number no output |
