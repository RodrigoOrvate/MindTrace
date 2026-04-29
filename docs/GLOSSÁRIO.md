# Glossário — Termos Técnicos Explicados

MindTrace usa muitas palavras técnicas. Aqui estão explicadas em português simples.

---

## A

### Arena
Espaço onde o rato é testado. Pode ser quadrada, circular, etc.

**Exemplo:** "Arena 50x50 cm com 4 zonas."

---

## B

### Behavior / Comportamento
Ação que o rato faz: parado, correndo, rearing (levantar), grooming (limpeza), etc.

---

## C

### C++
Linguagem de programação. MindTrace usa para velocidade (análise em tempo real).

### Camera / Câmera
Dispositivo que filma o rato. MindTrace processa vídeo em tempo real.

### CUDA
Tecnologia NVIDIA que usa GPU (chip de vídeo) para calcular rápido.

**Analogia:** GPU é 100x mais rápido que CPU para certos cálculos.

---

## D

### Dashboard
Tela com resultados: gráficos, vídeos, estatísticas.

### DLC
"DeepLabCut" — modelo de IA que detecta pose (esqueleto) do rato.

---

## E

### Epoch / Época
Período de tempo durante experimento. Ex: "Época 1: exploração (5 min), Época 2: teste (5 min)."

---

## G

### GPU / Graphics Processing Unit
Chip especial do vídeo que calcula muito rápido. Faz IA 100x mais rápida.

**Tipos:**
- NVIDIA (melhor para IA)
- AMD (alternativa)
- Intel (alternativa)
- Nenhuma (usa CPU, mais lento)

---

## I

### Inference / Inferência
Uso de modelo de IA para fazer previsões. "Detectar pose" é uma inferência.

### ONNX
Formato de arquivo de modelo de IA. Compatível com qualquer framework.

**Arquivo:** `modelo.onnx` (contém a IA)

---

## M

### Migration / Migração
Mudança nos comportamentos detectados. Ex: novo algoritmo de classificação.

### ML / Machine Learning
Inteligência artificial que aprende com dados.

---

## O

### ONNX Runtime
Biblioteca que roda modelos `.onnx`. Faz IA funcionar.

---

## P

### Paradigm / Paradigma
Tipo de experimento. MindTrace tem 4:
- **NOR** — Novel Object Recognition
- **CA** — Campo Aberto
- **CC** — Comportamento Complexo
- **EI** — Esquiva Inibitória

### Pose
Posição do corpo do rato. MindTrace detecta: cabeça, corpo, 4 patas.

**Analogia:** Como um "esqueleto" em cima do rato.

---

## Q

### Qt
Framework (biblioteca) para fazer interface gráfica (telas, botões, etc.).

**Versão:** Qt 6.11.0

---

## R

### Recording / Gravação
Vídeo sendo capturado em tempo real.

---

## S

### Session / Sessão
Um experimento completo. Gera vídeo + pose + comportamentos.

### Snippet / Clipe
Pedaço pequeno de vídeo. MindTrace extrai clips por comportamento.

---

## T

### Timeline
Gráfico mostrando o que o rato fez em cada momento.

**Exemplo:**
```
0:00 --- Parado ----
1:00 --- Correndo ----
2:00 --- Rearing ---
3:00 --- Parado ---
```

---

## V

### Video Processing / Processamento de Vídeo
Pegar video da câmera, detectar pose, classificar comportamentos.

---

## W

### Workflow / Fluxo de Trabalho
Passos que você segue:
1. Preparar arena
2. Ligar câmera
3. Colocar rato
4. Gravação ao vivo
5. Análise automática
6. Salvar e exportar

---

## Z

### Zone / Zona
Área dividida na arena. Ex: canto 1, canto 2, centro.

---

## Siglas Comuns

| Sigla | Significado |
|-------|-------------|
| **AI** | Artificial Intelligence (IA) |
| **CNN** | Convolutional Neural Network (rede neural para visão) |
| **CPU** | Central Processing Unit (processador) |
| **FPS** | Frames Per Second (quadros por segundo) |
| **GPU** | Graphics Processing Unit (placa de vídeo rápida) |
| **PCA** | Principal Component Analysis (reduzir dimensões) |
| **QML** | Qt Markup Language (linguagem da interface) |

---

## Comparações Úteis

### CPU vs GPU
- **CPU:** Rápido em geral. MindTrace usa para lógica.
- **GPU:** Muito rápido em cálculos paralelos. MindTrace usa para IA.

### CUDA vs DirectML
- **CUDA:** Só NVIDIA. Mais rápido.
- **DirectML:** Qualquer GPU (NVIDIA, AMD, Intel). Mais compatível.

### C++ vs Python
- **C++:** Muito rápido. MindTrace usa para captura + IA.
- **Python:** Mais fácil. Usado para scripts auxiliares.

---

**Palavra não está aqui?** Procure em [README.md](../README.md) ou abra issue!
