# 🧠 MindTrace

O **MindTrace** é uma plataforma de software desenvolvida em **C++/Qt (QML)** projetada para a gestão e análise de experimentos de neurociência comportamental, com foco inicial no teste de **Reconhecimento de Objetos (NOR - Novel Object Recognition)**.

O sistema foi construído para ser robusto, suportando **Windows 7** através do **Qt 5.12 LTS**, e oferece uma interface moderna para calibração de arenas 3D e coleta de dados.

## 🚀 Funcionalidades Principais

* **Arquitetura Híbrida**: Interface fluida em QML com lógica de performance (I/O de arquivos e processamento) em C++.
* **Calibração de Arena 3D**: Configuração visual de paredes, chão e zonas de interesse (ROI) com correção de perspectiva.
* **Gestão de Experimentos (CRUD)**: Criação, listagem e exclusão de experimentos salvos diretamente na pasta de Documentos do usuário.
* **Modo de Edição (Dev Mode)**: Ferramentas de arrastar e redimensionar zonas e quinas de polígonos em tempo real.
* **Coleta de Dados Inteligente**: Registro automático de sessões (Treino, Reativação, Testes) com preenchimento automático de dias e pares de objetos.
* **Mosaico 2×2**: Visualização simultânea de até 3 campos experimentais.

## 🛠 Arquitetura Técnica

### Tecnologias
* **Linguagem**: C++11 / QML.
* **Framework**: Qt 5.12.12 LTS.
* **Sistema de Build**: CMake.
* **Persistência**: JSON (Metadados e Configurações) e CSV (Dados de Tracking).

### Estrutura de Dados (`~/Documents/MindTrace_Data`)
Os dados são organizados hierarquicamente para facilitar o backup e a análise externa:
* `metadata.json`: Informações do protocolo (objetos, grupos, drogas).
* `arena_config.json`: Coordenadas geométricas da calibração da arena.
* `tracking_data.csv`: Tabela de resultados brutos das sessões.

## 📂 Organização do Projeto

| Diretório/Arquivo | Descrição |
|-------------------|-----------|
| `qt/main.cpp` | Ponto de entrada e registro de Singletons C++. |
| `qt/ExperimentManager` | Lógica de sistema de arquivos e gerenciamento de contextos. |
| `qt/ArenaConfigModel` | Motor de persistência das zonas e polígonos de visão. |
| `qt/ExperimentTableModel` | Modelo de tabela com *lazy-loading* para CSVs grandes. |
| `qml/` | Telas da interface (Dashboard, Setup, Arena, etc). |
| `qml/components/` | Botões, Toasts e cards reutilizáveis. |

## 🎮 Fluxos de Trabalho

### 1. Criar Novo Experimento
`Landing` → `Seleção de Aparato` → `Definição de Contexto` → `Configuração NOR` (Nomes e Objetos) → `Dashboard`.

### 2. Calibração da Arena
No Dashboard, acesse a aba **Arena**. Ative o **Dev Mode** para ajustar as quinas das paredes (Ctrl+Drag), do chão (Alt+Drag) e as zonas dos objetos (Shift+Drag/Scroll).

### 3. Registro de Sessão
Após o timer de 300 segundos, o sistema solicita os dados do animal e insere automaticamente as linhas no CSV baseadas no contexto e nos objetos configurados.

## 🎨 Padrões Visuais
* **Fundo**: `#0f0f1a` (Dark).
* **Destaque (Accent)**: `#ab3d4c` (Vinho/Cereja).
* **Tipografia**: Textos principais em `#e8e8f0`.

## ⚠️ Requisitos de Desenvolvimento
* **Qt 5.12 LTS**: Devido à compatibilidade com Windows 7, não utilize funcionalidades de versões superiores (como `HorizontalHeaderView` ou sintaxes QML modernas de `id` inline).
* **Build**: Certifique-se de que o compilador MSVC ou MinGW compatível com Qt 5.12 está configurado no CMake.

---
*MindTrace - Desenvolvido para pesquisadores, por pesquisadores.*
