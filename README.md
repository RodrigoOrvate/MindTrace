# MindTrace â€” MemoryLab / UFRN

Sistema de tracking comportamental de ratos para paradigmas **NOR**, **Campo Aberto**, **Comportamento Complexo** e **Esquiva InibitÃ³ria**, rodando nativamente em C++ com ONNX Runtime.

> **Sistema operacional:** Windows 10 ou 11 (64-bit) obrigatÃ³rio

---

## Escolha como deseja usar o MindTrace

| Quero usar o programa | Quero modificar o cÃ³digo |
|---|---|
| [â†’ InstalaÃ§Ã£o via Setup](#instalaÃ§Ã£o-via-setup-para-usuÃ¡rios) | [â†’ InstalaÃ§Ã£o para Desenvolvimento](#instalaÃ§Ã£o-para-desenvolvimento) |

---

## InstalaÃ§Ã£o via Setup (para usuÃ¡rios)

> Nenhum programa adicional Ã© necessÃ¡rio. Basta baixar e instalar.

### Passo 1 â€” Baixar o instalador

Acesse a pÃ¡gina de [Releases do repositÃ³rio](https://github.com/RodrigoOrvate/MindTrace/releases) e baixe o arquivo `MindTrace_Setup.exe` da versÃ£o mais recente.

### Passo 2 â€” Executar o instalador

DÃª duplo clique em `MindTrace_Setup.exe` e siga as instruÃ§Ãµes:

1. Aceite o contrato de licenÃ§a
2. Escolha a pasta de instalaÃ§Ã£o (padrÃ£o: `C:\Program Files\MindTrace`)
3. Clique em **Instalar**
4. Ao final, clique em **Concluir** â€” o MindTrace abrirÃ¡ automaticamente

O instalador copia o executÃ¡vel, todas as bibliotecas necessÃ¡rias e cria um atalho no Menu Iniciar e na Ãrea de Trabalho.

### Passo 3 â€” Modelo ONNX

O modelo de pose jÃ¡ estÃ¡ incluÃ­do no instalador â€” nenhuma aÃ§Ã£o Ã© necessÃ¡ria.

**Para trocar o modelo:** basta substituir o arquivo `.onnx` na pasta de instalaÃ§Ã£o do MindTrace (ex: `C:\Program Files\MindTrace\`) pelo novo modelo. O app carrega automaticamente qualquer arquivo `.onnx` que encontrar na pasta â€” nÃ£o importa o nome.

### Desinstalar

VÃ¡ em **ConfiguraÃ§Ãµes do Windows â†’ Aplicativos â†’ MindTrace â†’ Desinstalar**.

---

## InstalaÃ§Ã£o para Desenvolvimento

Para quem quer modificar o cÃ³digo, testar alteraÃ§Ãµes e compilar o projeto.

> âš ï¸ **PRIMEIRA VEZ?** Se estÃ¡ baixando em um novo computador, leia: **[SETUP_VSCODE.md](SETUP_VSCODE.md)** para um guia passo-a-passo com troubleshooting.

### 1. Instalar o GitHub Desktop e clonar o repositÃ³rio

Baixe o **GitHub Desktop** em [desktop.github.com](https://desktop.github.com/) e instale normalmente.

ApÃ³s instalar:
1. Clique em **File â†’ Clone repository**
2. VÃ¡ na aba **URL** e cole: `https://github.com/RodrigoOrvate/MindTrace`
3. Escolha onde salvar (ex: `C:\MindTrace`) e clique em **Clone**

---

### 2. Instalar os programas necessÃ¡rios

Instale os programas abaixo **nesta ordem**.

---

#### Python 3.12.10
**Download:** [python.org/downloads/release/python-31210](https://www.python.org/downloads/release/python-31210/)

Na instalaÃ§Ã£o:
- âœ… Marque **"Add Python to PATH"** (opÃ§Ã£o no rodapÃ© da tela inicial â€” obrigatÃ³rio)
- Clique em **Install Now**

> Usado pelo script `formatar_mindtrace.py` para exportar dados em `.xlsx`.

---

#### Visual Studio Community
**Download:** [visualstudio.microsoft.com/vs/community](https://visualstudio.microsoft.com/vs/community/)

Na tela de workloads, marque:
- âœ… **"Desenvolvimento para desktop com C++"**

Com esse workload selecionado, confirme que os seguintes componentes estÃ£o marcados na coluna de detalhes Ã  direita:

| Componente | ObrigatÃ³rio |
|---|---|
| Ferramentas de build do MSVC â€” C++ x64/x86 (versÃ£o mais recente) | âœ… Sim |
| Windows 11 SDK (10.0.26100 ou mais recente) | âœ… Sim |
| CMake C++ para Windows | âœ… Sim |

Deixe os demais como padrÃ£o e clique em **Instalar**.

> O `build.bat` detecta automaticamente o Visual Studio â€” nÃ£o Ã© necessÃ¡rio configurar nada manualmente apÃ³s instalar.

---

#### Visual Studio Code *(recomendado)*
**Download:** [code.visualstudio.com](https://code.visualstudio.com/)

InstalaÃ§Ã£o padrÃ£o. Abra a pasta `C:\MindTrace` no VSCode para editar e acompanhar o build com syntax highlighting e IntelliSense.

---

#### Qt 6.11.0
**Download:** [qt.io/download-open-source](https://www.qt.io/download-open-source)

Crie uma conta Qt gratuita se ainda nÃ£o tiver, baixe o **Qt Online Installer** e execute.

Na tela de seleÃ§Ã£o de componentes, expanda **Qt â†’ Qt 6.11.0** e marque **apenas**:

| Componente | ObrigatÃ³rio |
|---|---|
| **MSVC 2022 64-bit** | âœ… Sim â€” compilador usado pelo MindTrace |
| Qt Multimedia | âœ… Sim â€” pipeline de vÃ­deo |
| Qt Shader Tools | âœ… Sim â€” renderizaÃ§Ã£o de vÃ­deo |

Deixe todos os outros componentes **desmarcados**.

Certifique-se de que o Qt serÃ¡ instalado em `C:\Qt\6.11.0\msvc2022_64\`.  
Se escolher outro caminho, edite a variÃ¡vel `QT_DIR` no inÃ­cio do arquivo `qt\scripts\build.bat`.

---

#### CMake 3.25+
**Download:** [cmake.org/download](https://cmake.org/download/)

Baixe o instalador `.msi` para Windows x64. Durante a instalaÃ§Ã£o:
- âœ… Marque **"Add CMake to the system PATH for all users"**

---

### 3. Colocar o modelo ONNX

Copie o arquivo `.onnx` de pose para a pasta `qt\` do repositÃ³rio clonado. O nome do arquivo nÃ£o importa â€” o app carrega o primeiro `.onnx` encontrado na pasta do executÃ¡vel.

---

### 3.1 Primeira vez no VSCode (sem paradoxo de build)

Antes de rodar o CMake no VSCode, execute **uma vez**:

`cmd
qt\scripts\build.bat --deps-only --gpu DML
`

> Use --gpu CUDA se a maquina for NVIDIA. Esse passo cria onnxruntime_sdk/ e evita falha de configuracao do CMake na primeira abertura.
### 4. Executar o build

Navegue atÃ© `qt\scripts\` e dÃª duplo clique em **`build.bat`**.

O que acontece automaticamente:
1. Detecta o Visual Studio instalado
2. Verifica o ONNX Runtime SDK â€” se ausente, pergunta e baixa automaticamente (escolha a opÃ§Ã£o da sua GPU)
3. Configura e compila o projeto com MSBuild em paralelo
4. Copia as DLLs necessÃ¡rias
5. Abre o `MindTrace.exe`

> **Na primeira execuÃ§Ã£o** a compilaÃ§Ã£o demora alguns minutos. Nas prÃ³ximas, apenas os arquivos alterados sÃ£o recompilados â€” muito mais rÃ¡pido.

Para abrir sem recompilar: use `qt\scripts\run.bat`.

---

### LocalizaÃ§Ã£o dos arquivos gerados

| Arquivo | Caminho |
|---|---|
| ExecutÃ¡vel | `build\Release\MindTrace.exe` |
| Log do app | `build\Release\mindtrace.log` |

---

## Sobre o ONNX Runtime

Configurado **automaticamente** pelo `build.bat` na primeira execuÃ§Ã£o. O script detecta se o SDK estÃ¡ ausente e oferece download automÃ¡tico:

```
[1] Sim, para GPU AMD ou Intel (DirectML)
[2] Sim, para GPU NVIDIA (CUDA)
[3] NÃ£o, sair
```

### DetecÃ§Ã£o de GPU em Runtime

| GPU detectada | Ordem de tentativa |
|---|---|
| NVIDIA | CUDA â†’ DirectML â†’ CPU |
| AMD / Intel | DirectML â†’ CPU |
| Nenhuma | CPU |

Fallback automÃ¡tico â€” sem necessidade de recompilar.

---

## Arquitetura do Sistema

```
MindTrace.exe (Qt 6.11.0 / C++17 / ONNX Runtime 1.24.4)
  â””â”€â”€ LiveRecording.qml
        â””â”€â”€ InferenceController (C++)
             â”œâ”€â”€ QVideoSink  â†’ videoFrameChanged â†’ enqueueFrame
             â””â”€â”€ InferenceEngine (QThread)
                  â”œâ”€â”€ DXGI vendor detection â†’ CUDA / DirectML / CPU
                  â”œâ”€â”€ BehaviorScanner[3]   21 features + classifySimple()
                  â””â”€â”€ 3Ã— Ort::Session (Pose DLC) â€” paralelo por campo

  â””â”€â”€ CCDashboard
        â””â”€â”€ BSoidAnalyzer (C++ QObject)
             â”œâ”€â”€ BSoidWorker (QThread)  PCA 21â†’6 + K-Means++ k=7
             â”œâ”€â”€ populateTimelines()   BehaviorTimeline via SceneGraph (GPU)
             â””â”€â”€ extractSnippets()    QProcess (FFmpeg) â†’ clips por cluster
```

---

## Estrutura de Pastas

```
MindTrace/
â”œâ”€â”€ build/                       SaÃ­da do build (gerada automaticamente)
â”‚   â””â”€â”€ Release/
â”‚       â”œâ”€â”€ MindTrace.exe
â”‚       â””â”€â”€ mindtrace.log
â”œâ”€â”€ onnxruntime_sdk/             SDK ONNX Runtime (configurado pelo build.bat)
â””â”€â”€ qt/
    â”œâ”€â”€ src/
    â”‚   â”œâ”€â”€ core/                main.cpp
    â”‚   â”œâ”€â”€ manager/             ExperimentManager
    â”‚   â”œâ”€â”€ models/              TableModels, ArenaModel, ConfigModels
    â”‚   â”œâ”€â”€ tracking/            InferenceController, InferenceEngine, BehaviorScanner
    â”‚   â””â”€â”€ analysis/            BSoidAnalyzer
    â”œâ”€â”€ qml/
    â”‚   â”œâ”€â”€ core/                NavegaÃ§Ã£o e componentes base (main.qml, Theme/)
    â”‚   â”œâ”€â”€ shared/              LiveRecording.qml, DataView.qml, BoutEditorPanel.qml
    â”‚   â”œâ”€â”€ nor/                 NOR Dashboard e Setup
    â”‚   â”œâ”€â”€ ca/                  Campo Aberto Dashboard e Setup
    â”‚   â”œâ”€â”€ cc/                  Comportamento Complexo Dashboard e Setup
    â”‚   â””â”€â”€ ei/                  Esquiva InibitÃ³ria Dashboard e Setup
    â”œâ”€â”€ scripts/                 build.bat, run.bat, setup_onnx.ps1
    â”œâ”€â”€ CMakeLists.txt
    â””â”€â”€ resources.qrc
```

---

## Aplicativo Animal Lifecycle

O Animal Lifecycle Ã© uma plataforma complementar ao MindTrace para cadastro de animais, histÃ³rico e timeline de experimentos. EstÃ¡ sendo migrada para um repositÃ³rio prÃ³prio.

> **RepositÃ³rio:** [github.com/RodrigoOrvate/animal-lifecycle-platform](https://github.com/RodrigoOrvate/animal-lifecycle-platform) *(em breve)*

**IntegraÃ§Ã£o com o MindTrace:**
- O experimento Ã© criado no MindTrace com o campo `responsavel`
- O responsÃ¡vel Ã© escolhido a partir dos usuÃ¡rios cadastrados no backend
- Ao salvar sessÃµes no MindTrace, a sincronizaÃ§Ã£o envia os eventos para o app automaticamente
- O app nÃ£o cria experimentos manualmente

**ConfiguraÃ§Ã£o do backend:** veja o arquivo `animal-lifecycle-platform/backend/.env` â€” contÃ©m todas as variÃ¡veis de ambiente necessÃ¡rias com exemplos e explicaÃ§Ãµes.

