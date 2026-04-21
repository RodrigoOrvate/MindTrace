# MindTrace - Plano de Implementacao (3 Pontos Prioritarios)

Data: 2026-04-20
Escopo: idioma nas configuracoes, analise ao vivo com celular USB, e evolucao da aba de classificacao (CC/B-SOiD).

## 1) Idioma nas configuracoes (em andamento)

### Objetivo
- Permitir troca de idioma em `Settings` e persistir escolha.

### Entregas
1. Infra de persistencia:
- `LanguageSettings` no C++ para salvar/carregar idioma no `mindtrace_settings.json`.

2. Camada QML:
- `LanguageManager` singleton em `qml/core/Theme/`.
- Opcao de idioma no `SettingsScreen.qml` com `pt-BR`, `en-US`, `es-ES`.

3. Aplicacao progressiva:
- Migrar textos de telas core para `LanguageManager.tr3(...)`.
- Prioridade: `main.qml`, `LandingScreen.qml`, `HomeScreen.qml`, dialogs globais.

### Criterio de aceite
- Alterar idioma em Configuracoes.
- Reiniciar app e manter idioma selecionado.
- Pelo menos telas core com textos principais trocados.

---

## 2) Analise ao vivo com celular via USB (fase 1)

### Premissa
- Celular sera usado como webcam USB (DroidCam/Camo/IVCam/UVC equivalente).

### Objetivo
- Tornar o modo `ao_vivo` funcional ponta a ponta com inferencia e telemetria basica.

### Entregas
1. Fonte de video ao vivo:
- Introduzir pipeline de camera (`QCamera` + `QMediaCaptureSession` + `QVideoSink`) no C++.
- `InferenceController` passa a aceitar:
  - `startAnalysis(videoPath, modelDir)` para offline (atual).
  - `startLiveAnalysis(cameraId, modelDir)` para ao vivo.
  - `listVideoInputs()` para preencher UI de dispositivos.

2. UI de selecao de camera:
- Em `ArenaSetup/EIArenaSetup`, quando `analysisMode == "ao_vivo"`:
  - listar cameras detectadas,
  - salvar camera selecionada por experimento/sessao.

3. Diagnostico live:
- Exibir na `LiveRecording.qml`:
  - camera ativa,
  - resolucao real,
  - FPS estimado,
  - contador de frames recebidos/perdidos.

4. Gravacao (fase seguinte):
- Integrar gravacao do stream ao vivo no caminho de sessao.
- Se gravacao ainda nao estiver pronta, executar inferencia ao vivo com aviso de "sem gravacao".

### Criterio de aceite
- Celular USB aparece na lista de dispositivos.
- Sessao ao vivo inicia e recebe frames continuamente por 20 min.
- Tracking e classificacao atualizam sem travamentos.

### Status atual (2026-04-21)
- Passo 1: OK no momento (sem bloqueios abertos).
- Passo 2: funcional com selecao de camera, preview, inferencia ao vivo e gravacao em arquivo com pasta + nome.
- Pendente do passo 2 (prioridade alta):
  - FPS real em execucao permanece em ~22 FPS no perfil 1920x1080.
  - Request alvo: atingir 60 FPS reais no modo ao vivo.
  - Esta tentativa de otimizacao fica registrada como proxima acao.

---

## 3) Comportamento Complexo - aba Classificacao (B-SOiD)

### Objetivo
- Transformar aba de classificacao em fluxo de revisao e auditoria.

### Entregas (MVP)
1. Painel de explicacao por evento:
- Exibir regra disparada (`classifySimple`) e metrica-chave no momento do evento.

2. Filtros operacionais:
- Filtrar por campo, comportamento e intervalo de tempo.

3. Edicao de bouts:
- Operacoes basicas: split, merge, delete.
- Manter historico "original vs editado".

4. Exportacao de revisao:
- CSV/JSON contendo:
  - timeline original,
  - timeline editada,
  - quem/quando editou (timestamp local).

### Criterio de aceite
- Usuario revisa classificacao e exporta resultado auditavel da sessao.

---

## Ordem recomendada de execucao
1. Fechar textos core no novo sistema de idioma.
2. Ativar modo ao vivo real com camera USB e diagnostico.
3. Entregar MVP da aba Classificacao no CC.

## Riscos e mitigacao
- Risco: variacao de FPS/latencia com celular.
  - Mitigacao: recomendacao de USB, perfil 720p/30fps, painel de diagnostico.
- Risco: regressao em offline ao mexer no controller.
  - Mitigacao: manter APIs separadas `startAnalysis` (offline) e `startLiveAnalysis` (live).
- Risco: complexidade da edicao de bouts.
  - Mitigacao: entregar MVP sem regras automaticas complexas de reconciliacao.
