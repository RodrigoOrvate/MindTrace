# MindTrace — MemoryLab / UFRN

Sistema de tracking comportamental de ratos para paradigmas **NOR**, **Campo Aberto**, **Comportamento Complexo** e **Esquiva Inibitória**, rodando nativamente em C++ com ONNX Runtime.

> **Sistema operacional:** Windows 10 ou 11 (64-bit) obrigatório

---

## Escolha como deseja usar o MindTrace

| Quero usar o programa | Quero modificar o código |
|---|---|
| [→ Instalação via Setup](#instalação-via-setup-para-usuários) | [→ Instalação para Desenvolvimento](#instalação-para-desenvolvimento) |

---

## Instalação via Setup (para usuários)

> Nenhum programa adicional é necessário. Basta baixar e instalar.

### Passo 1 — Baixar o instalador

Acesse a página de [Releases do repositório](https://github.com/RodrigoOrvate/MindTrace/releases) e baixe o arquivo `MindTrace_Setup.exe` da versão mais recente.

### Passo 2 — Executar o instalador

Dê duplo clique em `MindTrace_Setup.exe` e siga as instruções:

1. Aceite o contrato de licença
2. Escolha a pasta de instalação (padrão: `C:\Program Files\MindTrace`)
3. Clique em **Instalar**
4. Ao final, clique em **Concluir** — o MindTrace abrirá automaticamente

O instalador copia o executável, todas as bibliotecas necessárias e cria um atalho no Menu Iniciar e na Área de Trabalho.

### Passo 3 — Modelo ONNX

O modelo de pose já está incluído no instalador — nenhuma ação é necessária.

**Para trocar o modelo:** basta substituir o arquivo `.onnx` na pasta de instalação do MindTrace (ex: `C:\Program Files\MindTrace\`) pelo novo modelo. O app carrega automaticamente qualquer arquivo `.onnx` que encontrar na pasta — não importa o nome.

### Desinstalar

Vá em **Configurações do Windows → Aplicativos → MindTrace → Desinstalar**.

---

## Instalação para Desenvolvimento

Para quem quer modificar o código, testar alterações e compilar o projeto.

### 1. Instalar o GitHub Desktop e clonar o repositório

Baixe o **GitHub Desktop** em [desktop.github.com](https://desktop.github.com/) e instale normalmente.

Após instalar:
1. Clique em **File → Clone repository**
2. Vá na aba **URL** e cole: `https://github.com/RodrigoOrvate/MindTrace`
3. Escolha onde salvar (ex: `C:\MindTrace`) e clique em **Clone**

---

### 2. Instalar os programas necessários

Instale os programas abaixo **nesta ordem**.

---

#### Python 3.12.10
**Download:** [python.org/downloads/release/python-31210](https://www.python.org/downloads/release/python-31210/)

Na instalação:
- ✅ Marque **"Add Python to PATH"** (opção no rodapé da tela inicial — obrigatório)
- Clique em **Install Now**

> Usado pelo script `formatar_mindtrace.py` para exportar dados em `.xlsx`.

---

#### Visual Studio Community
**Download:** [visualstudio.microsoft.com/vs/community](https://visualstudio.microsoft.com/vs/community/)

Na tela de workloads, marque:
- ✅ **"Desenvolvimento para desktop com C++"**

Com esse workload selecionado, confirme que os seguintes componentes estão marcados na coluna de detalhes à direita:

| Componente | Obrigatório |
|---|---|
| Ferramentas de build do MSVC — C++ x64/x86 (versão mais recente) | ✅ Sim |
| Windows 11 SDK (10.0.26100 ou mais recente) | ✅ Sim |
| CMake C++ para Windows | ✅ Sim |

Deixe os demais como padrão e clique em **Instalar**.

> O `build.bat` detecta automaticamente o Visual Studio — não é necessário configurar nada manualmente após instalar.

---

#### Visual Studio Code *(recomendado)*
**Download:** [code.visualstudio.com](https://code.visualstudio.com/)

Instalação padrão. Abra a pasta `C:\MindTrace` no VSCode para editar e acompanhar o build com syntax highlighting e IntelliSense.

---

#### Qt 6.11.0
**Download:** [qt.io/download-open-source](https://www.qt.io/download-open-source)

Crie uma conta Qt gratuita se ainda não tiver, baixe o **Qt Online Installer** e execute.

Na tela de seleção de componentes, expanda **Qt → Qt 6.11.0** e marque **apenas**:

| Componente | Obrigatório |
|---|---|
| **MSVC 2022 64-bit** | ✅ Sim — compilador usado pelo MindTrace |
| Qt Multimedia | ✅ Sim — pipeline de vídeo |
| Qt Shader Tools | ✅ Sim — renderização de vídeo |

Deixe todos os outros componentes **desmarcados**.

Certifique-se de que o Qt será instalado em `C:\Qt\6.11.0\msvc2022_64\`.  
Se escolher outro caminho, edite a variável `QT_DIR` no início do arquivo `qt\scripts\build.bat`.

---

#### CMake 3.25+
**Download:** [cmake.org/download](https://cmake.org/download/)

Baixe o instalador `.msi` para Windows x64. Durante a instalação:
- ✅ Marque **"Add CMake to the system PATH for all users"**

---

### 3. Colocar o modelo ONNX

Copie o arquivo `.onnx` de pose para a pasta `qt\` do repositório clonado. O nome do arquivo não importa — o app carrega o primeiro `.onnx` encontrado na pasta do executável.

---

### 4. Executar o build

Na primeira vez, navegue até `qt\scripts\` e dê duplo clique em **`build.bat`**.

O que acontece automaticamente:
1. Detecta o Visual Studio instalado
2. Verifica o ONNX Runtime SDK — se ausente, pergunta e baixa automaticamente (escolha a opção da sua GPU)
3. Configura e compila o projeto com MSBuild em paralelo
4. Copia as DLLs necessárias
5. Abre o `MindTrace.exe`

> **Na primeira execução** a compilação demora alguns minutos. Nas próximas, apenas os arquivos alterados são recompilados — muito mais rápido.

Para abrir sem recompilar: use `qt\scripts\run.bat`.

---

### Localização dos arquivos gerados

| Arquivo | Caminho |
|---|---|
| Executável | `build\Release\MindTrace.exe` |
| Log do app | `build\Release\mindtrace.log` |

---

## Sobre o ONNX Runtime

Configurado **automaticamente** pelo `build.bat` na primeira execução. O script detecta se o SDK está ausente e oferece download automático:

```
[1] Sim, para GPU AMD ou Intel (DirectML)
[2] Sim, para GPU NVIDIA (CUDA)
[3] Não, sair
```

### Detecção de GPU em Runtime

| GPU detectada | Ordem de tentativa |
|---|---|
| NVIDIA | CUDA → DirectML → CPU |
| AMD / Intel | DirectML → CPU |
| Nenhuma | CPU |

Fallback automático — sem necessidade de recompilar.

---

## Arquitetura do Sistema

```
MindTrace.exe (Qt 6.11.0 / C++17 / ONNX Runtime 1.24.4)
  └── LiveRecording.qml
        └── InferenceController (C++)
             ├── QVideoSink  → videoFrameChanged → enqueueFrame
             └── InferenceEngine (QThread)
                  ├── DXGI vendor detection → CUDA / DirectML / CPU
                  ├── BehaviorScanner[3]   21 features + classifySimple()
                  └── 3× Ort::Session (Pose DLC) — paralelo por campo

  └── CCDashboard
        └── BSoidAnalyzer (C++ QObject)
             ├── BSoidWorker (QThread)  PCA 21→6 + K-Means++ k=7
             ├── populateTimelines()   BehaviorTimeline via SceneGraph (GPU)
             └── extractSnippets()    QProcess (FFmpeg) → clips por cluster
```

---

## Estrutura de Pastas

```
MindTrace/
├── build/                       Saída do build (gerada automaticamente)
│   └── Release/
│       ├── MindTrace.exe
│       └── mindtrace.log
├── onnxruntime_sdk/             SDK ONNX Runtime (configurado pelo build.bat)
└── qt/
    ├── src/
    │   ├── core/                main.cpp
    │   ├── manager/             ExperimentManager
    │   ├── models/              TableModels, ArenaModel, ConfigModels
    │   ├── tracking/            InferenceController, InferenceEngine, BehaviorScanner
    │   └── analysis/            BSoidAnalyzer
    ├── qml/
    │   ├── core/                Navegação e componentes base (main.qml, Theme/)
    │   ├── shared/              LiveRecording.qml, DataView.qml, BoutEditorPanel.qml
    │   ├── nor/                 NOR Dashboard e Setup
    │   ├── ca/                  Campo Aberto Dashboard e Setup
    │   ├── cc/                  Comportamento Complexo Dashboard e Setup
    │   └── ei/                  Esquiva Inibitória Dashboard e Setup
    ├── scripts/                 build.bat, run.bat, setup_onnx.ps1
    ├── CMakeLists.txt
    └── resources.qrc
```

---

## Aplicativo Animal Lifecycle

O Animal Lifecycle é uma plataforma complementar ao MindTrace para cadastro de animais, histórico e timeline de experimentos. Está sendo migrada para um repositório próprio.

> **Repositório:** [github.com/RodrigoOrvate/animal-lifecycle-platform](https://github.com/RodrigoOrvate/animal-lifecycle-platform) *(em breve)*

**Integração com o MindTrace:**
- O experimento é criado no MindTrace com o campo `responsavel`
- O responsável é escolhido a partir dos usuários cadastrados no backend
- Ao salvar sessões no MindTrace, a sincronização envia os eventos para o app automaticamente
- O app não cria experimentos manualmente

**Configuração do backend:** veja o arquivo `animal-lifecycle-platform/backend/.env` — contém todas as variáveis de ambiente necessárias com exemplos e explicações.


