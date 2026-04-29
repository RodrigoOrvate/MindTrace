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

### Passo 1 — Baixar o instalador

Vá em [Releases](https://github.com/RodrigoOrvate/MindTrace/releases) e baixe `MindTrace_Setup.exe`.

### Passo 2 — Instalar

Dê duplo clique e siga as instruções:
1. Aceite o contrato
2. Escolha pasta (padrão é `C:\Program Files\MindTrace`)
3. Clique em **Instalar**
4. Pronto! Ícone aparece na Área de Trabalho

### Passo 3 — Preparar o modelo ONNX

O modelo (IA de pose) já vem incluído. Nenhuma ação necessária.

**Se quiser trocar o modelo:**
- Copie seu arquivo `.onnx` para `C:\Program Files\MindTrace\`
- App carrega automaticamente

### Passo 4 — Usar!

Abra MindTrace e escolha seu paradigma:
- **NOR** — Novel Object Recognition
- **Campo Aberto** — Open Field
- **Comportamento Complexo** — Complex Behavior
- **Esquiva Inibitória** — Inhibitory Avoidance

### Passo 5 — Sincronizar com Backend (opcional)

Se tem um **Backend da Animal Lifecycle** rodando:

1. Settings → Backend URL
2. Digite: `http://192.168.1.10:8000` (substitua pelo IP real)
3. Settings → SYNC_SECRET (copie do admin)
4. Ao finalizar experimento, dados sincronizam automaticamente ✨

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

### Passo 3 — Colocar modelo ONNX

Copie arquivo `.onnx` para `qt/` (raiz do repositório clonado).

### Passo 4 — Compilar

```bash
cd qt/scripts
# Dê duplo clique em build.bat
```

Na primeira vez demora 5-10 min (tudo é compilado).
Depois é rápido (só o que mudou).

### Passo 5 — Modificar e testar

Edite código em `qt/src/` ou `qt/qml/`, salve, compile novamente.

Comit, push, pull request!

---

## 🎮 Usando MindTrace (Tutorial Básico)

### Criar um experimento

1. Abra MindTrace
2. Escolha paradigma (ex: "NOR")
3. Configure arena (tamanho, câmera)
4. Clique em **Live Recording**
5. Vídeo da câmera aparece ao vivo
6. Pose do rato é detectada automaticamente ✨
7. Ao terminar, clique **Stop** e **Save**

### Visualizar resultados

1. Dashboard aparece com:
   - Timeline de comportamentos
   - Clips de vídeo (extraídos automaticamente)
   - Estatísticas (tempo em cada zona, etc.)

2. Exportar para Excel:
   ```bash
   python scripts/formatar_mindtrace.py
   ```

---

## ❓ Algo Deu Errado?

### "Modelo não carrega"
- Verificar se arquivo `.onnx` está em `C:\Program Files\MindTrace\`
- Extensão deve ser exatamente `.onnx` (não `.pth` ou outro)

### "Câmera não funciona"
- Verificar Configurações do Windows → Privacidade → Câmera
- Marque MindTrace como permitido

### "Sincronização não funciona"
- Verificar se backend está rodando (curl http://192.168.1.10:8000/health)
- Verificar SYNC_SECRET está correto (mesma senha do backend)
- Ver logs em `C:\Program Files\MindTrace\mindtrace.log`

---

## 📚 Para Saber Mais

- **[GLOSSÁRIO.md](GLOSSÁRIO.md)** — Termos técnicos explicados
- **[README.md](../README.md)** — Documentação técnica completa
- **[AGENTS.md](AGENTS.md)** — Código dos agentes (análise)

---

**Pronto?** Escolha sua rota acima e comece! 🚀
