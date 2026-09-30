# Quick Start — Escolha Seu Caminho

MindTrace em 2 minutos. Você quer usar ou modificar?

---

## 🎯 Escolha Sua Rota

### 1️⃣ Vou USAR o programa (não quero mexer no código)

```
┌─────────────────────────────────────┐
│  Sou pesquisador / técnico de lab   │
│  Só quero usar para experimentos    │
│  (não preciso compilar nada)        │
└─────────────────┬───────────────────┘
                  ↓
           ⬇️ Siga "USUÁRIO FINAL"
```

---

### 2️⃣ Vou MODIFICAR o código (quero melhorar / corrigir)

```
┌─────────────────────────────────────┐
│  Sou desenvolvedor C++ / Qt         │
│  Vou fazer mudanças e compilar      │
│  (quero pull requests)              │
└─────────────────┬───────────────────┘
                  ↓
           ⬇️ Siga "DESENVOLVEDOR"
```

---

## 👤 Rota 1: USUÁRIO FINAL

⏱️ **Tempo:** 5 minutos (instalação) + 2 minutos (aprender a usar)

> ⚠️ **Ainda não há instalador publicado.** Enquanto a primeira versão não sai em [Releases](https://github.com/RodrigoOrvate/MindTrace/releases), siga a **Rota 2** para compilar ou peça o instalador a quem mantém o projeto.

### Passo 1 — Baixar o instalador

Vá em [Releases](https://github.com/RodrigoOrvate/MindTrace/releases) e baixe `MindTrace_Setup_<versão>.exe` (ex.: `MindTrace_Setup_1.0.0.exe`).

### Passo 2 — Instalar

Dê duplo clique (precisa de permissão de administrador) e siga as instruções:
1. Escolha a pasta (padrão é `C:\Program Files\MindTrace`)
2. Se quiser, marque **Criar atalho na Área de Trabalho**
3. Clique em **Instalar**
4. Pronto! O MindTrace fica no Menu Iniciar (e abre ao final, se **Iniciar MindTrace agora** estiver marcado)

**Opcional:**
- **Python 3** com **"Add Python to PATH"** — para a exportação sair em `.xlsx` formatado (sem ele, sai só o `.csv`)
- **`ffmpeg.exe`** na pasta do MindTrace ou no PATH — para extrair clipes de vídeo por cluster no Comportamento Complexo

### Passo 3 — Preparar o modelo ONNX

O modelo (IA de pose) já vem incluído. Nenhuma ação necessária.

**Se quiser trocar o modelo:**
- Substitua o `.onnx` em `C:\Program Files\MindTrace\` pelo novo (deixe só um `.onnx` na pasta)
- App carrega automaticamente, qualquer que seja o nome

### Passo 4 — Usar!

Abra MindTrace e escolha seu paradigma:
- **NOR** — Novel Object Recognition
- **Campo Aberto** — Open Field
- **Comportamento Complexo** — Complex Behavior
- **Esquiva Inibitória** — Inhibitory Avoidance

Veja o passo a passo em [🎮 Usando MindTrace](#-usando-mindtrace-tutorial-básico).

### Passo 5 — Sincronizar com Backend (opcional)

Se tem o **backend do [Animal Lifecycle](https://github.com/RodrigoOrvate/animal-lifecycle-platform)** rodando **no mesmo computador**:

1. Defina as variáveis de ambiente do Windows (não há campos na tela de Configurações):
   - `MINDTRACE_SYNC_ENABLED=1`
   - `MINDTRACE_SYNC_SECRET=` o mesmo valor de `SYNC_SECRET` do `backend/.env` (peça ao admin)
   - `MINDTRACE_SYNC_URL` só se o backend não estiver em `http://127.0.0.1:8000` — o MindTrace só aceita `127.0.0.1` ou `localhost`
2. Abra o MindTrace de novo para ele ler as variáveis
3. Cada sessão salva é enviada ao backend ✨

Detalhes em [README → Ativar a sincronização](../README.md#ativar-a-sincronização-no-mindtrace).

---

## 👨‍💻 Rota 2: DESENVOLVEDOR

⏱️ **Tempo:** 20 minutos (primeira vez) + recompilação mais rápida depois

### Passo 1 — Clonar repositório

```bash
git clone https://github.com/RodrigoOrvate/MindTrace
cd MindTrace
```

### Passo 2 — Instalar requisitos (em ordem!)

Veja [README.md → Instalação para Desenvolvimento](../README.md#instalação-para-desenvolvimento):
- Python 3.12.10
- Visual Studio Community (C++ workload)
- Qt 6.11.0 MSVC
- CMake 3.25+
- VSCode (recomendado)

### Passo 3 — Modelo ONNX

Nada a fazer: o modelo (`qt/Network-MemoryLab-v2.onnx`) já vem no repositório e o `build.bat` o copia para `build/Release/`.

### Passo 4 — Compilar

```bash
cd qt/scripts
# Dê duplo clique em build.bat
# (ou: build.bat --gpu DML  /  build.bat --gpu CUDA)
```

Na primeira vez ele baixa o ONNX Runtime (escolha **DML** para AMD/Intel/CPU ou **CUDA** para NVIDIA) e compila tudo — demora 5-10 min.
Depois é rápido (só o que mudou). Para abrir sem compilar: `run.bat`.

### Passo 5 — Modificar e testar

Edite código em `qt/src/` ou `qt/qml/`, salve, compile novamente.

Commit, push, pull request!

Para gerar o instalador: [README → Gerar o instalador](../README.md#gerar-o-instalador).

---

## 🎮 Usando MindTrace (Tutorial Básico)

### Criar um experimento

1. Abra MindTrace e clique em **Criar**
2. Escolha o paradigma (ex: "Reconhecimento de Objetos")
3. Escolha o layout de campos / contexto e clique em **Próximo** (NOR, Campo Aberto e Comportamento Complexo)
4. Dê um nome, preencha as opções do paradigma (ex: pares de objetos no NOR) e clique em **Criar Experimento**

### Analisar um vídeo ou a câmera

1. Na aba **Arena**, clique em **Carregar Vídeo** e escolha **Análise Offline** (vídeo gravado) ou **Análise Ao Vivo** (câmera)
2. Ajuste as zonas sobre o vídeo — ative o **Dev** para arrastar os cantos das paredes, do chão e das zonas — e clique em **Salvar Configuração**
3. Na aba **Gravação**, clique em **Iniciar** — a pose do rato é detectada automaticamente ✨
4. Ao terminar (fim do vídeo ou **Parar**), informe dia e animal e clique em **Salvar Sessão**

### Visualizar resultados

1. A aba **Dados** mostra uma linha por sessão salva
2. **Exportar** gera o `.csv` e, com Python instalado, o `.xlsx` formatado com as métricas (tempo em cada zona, distância, velocidade, etc.)
3. No **Comportamento Complexo**, o dashboard também traz a timeline de comportamentos (regras + B-SOiD) e a extração de clipes por cluster (precisa do FFmpeg)

---

## ❓ Algo Deu Errado?

### "Modelo não carrega"
- Verificar se há um arquivo `.onnx` na pasta do executável (`C:\Program Files\MindTrace\` ou `build\Release\`)
- Extensão deve ser exatamente `.onnx` (não `.pth` ou outro)

### "Tracking atrasado / não acompanha o rato"
- Sem GPU a inferência roda na CPU e pode processar poucos quadros por segundo
- O Log da aba **Gravação** mostra o modo em uso (ex.: "Modo GPU: DirectML ativo" ou "Modo CPU")

### "Câmera não funciona"
- Verificar Configurações do Windows → Privacidade → Câmera
- Ative **Permitir que aplicativos da área de trabalho acessem sua câmera**

### "Exportar não gera o .xlsx"
- Instale o Python 3 marcando **"Add Python to PATH"** e exporte de novo

### "Sincronização não funciona"
- Verificar se `MINDTRACE_SYNC_ENABLED=1` está definida e se o MindTrace foi reaberto depois
- Verificar se o backend está rodando no mesmo computador (`curl http://127.0.0.1:8000/health`)
- Verificar se `MINDTRACE_SYNC_SECRET` é igual ao `SYNC_SECRET` do backend
- Ver `mindtrace.log` na pasta do executável

---

## 📚 Para Saber Mais

- **[GLOSSÁRIO.md](GLOSSÁRIO.md)** — Termos técnicos explicados
- **[README.md](../README.md)** — Documentação técnica completa
- **[AGENTS.md](../AGENTS.md)** — Contexto técnico detalhado do código (arquitetura e pipeline)

---

**Pronto?** Escolha sua rota acima e comece! 🚀
