# MindTrace - Guidelines de Desenvolvimento

## 🛠 Arquitetura do Projeto

### Camada UI — C++/Qt (QML)

#### Singletons C++ registrados em `main.cpp`
| Tipo QML | Classe C++ | Uso |
|----------|------------|-----|
| `ExperimentManager` | `ExperimentManager` | CRUD de experimentos em disco |
| `ArenaModel` | `ArenaModel` | Lê `arenas.json`; expõe lista de arenas e pares (legado) |
| `ArenaConfigModel` | `ArenaConfigModel` | Persiste configuração visual da arena (zonas, paredes, chão) |

`ExperimentTableModel` é registrado como **tipo instanciável** (não singleton) — criado dentro do QML de cada experimento aberto.

#### Arquivos C++
- **qt/main.cpp** — Inicialização `QApplication`, logger em arquivo (`mindtrace.log`), registro de tipos no motor QML.
- **qt/ExperimentManager.{h,cpp}** — CRUD de experimentos. Veja API abaixo.
- **qt/ExperimentTableModel.{h,cpp}** — `QAbstractTableModel` com lazy-loading (batch de 50 linhas). Lê/salva `tracking_data.csv`.
- **qt/ArenaModel.{h,cpp}** — Carrega `arenas.json` (`.qrc`). Expõe `ArenaListModel` e `PairListModel`.
- **qt/ArenaConfigModel.{h,cpp}** — Persiste `arena_config.json` com posição das zonas (xRatio, yRatio, radiusRatio), polígonos de paredes e chão. Ao abrir um experimento sem `arena_config.json`, carrega automaticamente os valores de `arena_config_referencia.json` (embutido no executável via `.qrc`).

#### Arquivo de referência de arena
- **qt/arena_config_referencia.json** — Configuração calibrada da arena (paredes, chão, zonas). Compilado no binário via `.qrc`. Usado como ponto de partida quando um experimento ainda não tem `arena_config.json`. `pairId` vazio pois é genérico.

#### ExperimentManager — API Q_INVOKABLE completa
```cpp
void        loadContext(context)          // Scan da pasta do contexto → atualiza model
void        loadAllContexts()            // Scan de TODOS os contextos (searchMode)
void        setActiveContext(context)    // Define contexto sem scan (searchMode)
bool        experimentExists(context, name)  // Verifica duplicata antes de criar
bool        createExperiment(name)       // Criação simples (colunas padrão)
bool        createExperimentWithConfig(name, animalCount, columns)
bool        createExperimentFull(name, columns, pair1, pair2, pair3, includeDrug)
void        setFilter(query)             // Filtra ExperimentListModel
QString     experimentPath(name)
bool        deleteExperiment(name)
bool        insertSessionResult(experimentName, rows)  // Append CSV — pós-timer 300s
QVariantMap readMetadata(name)           // Lê metadata.json pelo nome (contexto ativo)
QVariantMap readMetadataFromPath(folderPath)  // Lê metadata.json pelo path completo
```
**Sinais:** `experimentCreated(name, path)`, `experimentDeleted(name)`, `errorOccurred(message)`, `sessionDataInserted(experimentName)`, `activeContextChanged()`.

#### ArenaConfigModel — API Q_INVOKABLE completa
```cpp
void        loadConfig(context, expName)   // Carrega arena_config.json do experimento;
                                           // se não existir, usa arena_config_referencia.json
bool        saveConfig(context, expName, pairId, imageUrl, zones, arenaPointsJson, floorPointsJson)
                                           // pairId = "pair1/pair2/pair3" (ex: "AG/BC/CD")
QString     getArenaPoints()               // Retorna JSON string dos polígonos externos
QString     getFloorPoints()               // Retorna JSON string dos polígonos de chão
QVariantMap zone(index)                    // Retorna zona por índice (0–5)
int         zoneCount()
```
**Sinal:** `configChanged()` — emitido após `loadConfig` e `saveConfig`.

#### Arquivos QML — telas
| Arquivo | Descrição |
|---------|-----------|
| `main.qml` | Janela raiz + roteador (StackView). Dois fluxos: **Criar** e **Procurar**. |
| `LandingScreen.qml` | Tela inicial: dois cards gigantes (Criar / Procurar). |
| `LandingCard.qml` | Card gigante reutilizável da LandingScreen. |
| `HomeScreen.qml` | Passo 1: seleção de aparato (NOR liberado, demais "Em Breve"). |
| `ArenaSelection.qml` | Passo 2: contexto da arena (Padrão / Contextual) + preview mosaico 2×2. |
| `NORSetupScreen.qml` | Passo 3: nome do experimento + 3× CampoSelector + checkbox Droga. |
| `CampoSelector.qml` | Dois botões de objeto (Objeto 1 / Objeto 2) → popup com 17 letras livres. |
| `MainDashboard.qml` | Dashboard: sidebar de experimentos + tabs Arena / Dados / Gravação. |
| `SessionResultDialog.qml` | Popup pós-timer (300 s): insere linhas (uma por campo) no CSV. |
| `ArenaSetup.qml` | Tab Arena: mosaico 2×2 com paredes/chão/zonas arrastáveis. Dev mode libera edição e exibe alças e px das zonas. Emite `pairsEdited(p1,p2,p3)` ao editar pares. |
| `LiveRecording.qml` | Tab Gravação: placeholder para módulo de análise/gravação (futuro). |

#### Arquivos QML — componentes reutilizáveis
`NORCard.qml`, `GhostButton.qml`, `Toast.qml`, `SelectionCard.qml`

- **qt/resources.qrc** — Todos os arquivos QML, `arenas.json` e `arena_config_referencia.json` compilados no executável.
- **qt/CMakeLists.txt** — Build com Qt 5.12 LTS (requisito: Windows 7).

---

## 🔄 Fluxos de Navegação

### Fluxo Criar
```
LandingScreen → HomeScreen → ArenaSelection → NORSetupScreen → MainDashboard
```
- `ArenaSelection` emite `selectionConfirmed(context, arenaId)` → salvo em `main.qml` como `pendingContext`/`pendingArenaId`.
- `NORSetupScreen` emite `experimentReady(name, cols, pair1, pair2, pair3, includeDrug)`.
  - Se experimento já existe: popup 2 etapas (aviso → digitar nome para confirmar substituição).
  - Caso contrário: `ExperimentManager.createExperimentFull(...)` → sinal `experimentCreated` → push para `MainDashboard`.

### Fluxo Procurar
```
LandingScreen → MainDashboard(searchMode: true)
```
- `Component.onCompleted` chama `ExperimentManager.loadAllContexts()` para listar todos os contextos.
- Ao selecionar experimento: `loadExperiment(name, path)` extrai o contexto do path e chama `setActiveContext`.

---

## 📁 Estrutura de Pastas de Saída
```
~/Documents/MindTrace_Data/Experimentos/<Contexto>/<NomeExperimento>/
    metadata.json        — criado pelo C++ (ExperimentManager), versão 1.1
    tracking_data.csv    — cabeçalhos criados pelo C++, linhas inseridas pós-sessão
    arena_config.json    — criado pelo ArenaConfigModel ao salvar zonas
```

### metadata.json — campos (versão 1.1)
```json
{
  "name":        "NomeDoExperimento",
  "context":     "Padrão",
  "animalCount": 0,
  "columns":     ["Diretório do Vídeo", "Animal", "Campo", "Dia", "Par de Objetos"],
  "pair1":       "AB",
  "pair2":       "AA",
  "pair3":       "BC",
  "includeDrug": true,
  "createdAt":   "2026-04-01T18:09:06",
  "version":     "1.1"
}
```

### arena_config.json — campos
```json
{
  "pairId":      "AB/AA/BC",
  "imageUrl":    "",
  "arenaPoints": "<JSON string com 3 arrays de 4 pontos {x,y} — topo das paredes>",
  "floorPoints": "<JSON string com 3 arrays de 4 pontos {x,y} — chão>",
  "zones": [
    { "xRatio": 0.44, "yRatio": 0.45, "radiusRatio": 0.067, "objectId": "" },
    ...
  ]
}
```
`pairId` concatena os 3 pares com `/` (ex: `"AG/BC/CD"`). `zones` tem sempre 6 entradas (2 por campo).

---

## 🧪 Modelo de Arena (NOR)

### Arena — apenas quadrada (60×60 cm)
| ID | Contexto |
|----|----------|
| `sq_padrao` | Padrão |
| `sq_contextual` | Contextual |

A preview de arena em `ArenaSelection.qml` é um mosaico 2×2: Campo 1 (topo-esq), Campo 2 (topo-dir), Campo 3 (baixo-esq), célula ignorada (baixo-dir).

### Pares de objetos — seleção livre por campo
O usuário escolhe dois objetos por campo (Objeto 1 / Objeto 2) via picker com as letras:
`A B C D E F G H I J L M N O P R S`

O par resultante é armazenado como string de 2 letras: `"AB"`, `"AA"`, `"BC"`, etc.

**Regra de nomeação de IDs no tracking:**
- Par assimétrico (letras diferentes, ex.: `"AB"`) → `OBJA`, `OBJB`
- Par simétrico (mesma letra, ex.: `"AA"`) → `OBJA`, `OBJA1`

Os pares podem ser editados na tab Arena a qualquer momento via botão "✏ Editar Pares". O sinal `pairsEdited(p1,p2,p3)` propaga a mudança para `workArea.pair1/2/3` no dashboard, atualizando simultaneamente a tab Dados e o `SessionResultDialog`.

### Dev Mode (ArenaSetup)
- **Desativado (padrão):** paredes, chão e zonas são exibidos, mas não é possível arrastar nada.
- **Ativado:** alças brancas nas quinas aparecem; Shift+drag move zonas; Ctrl+drag move quinas da parede; Alt+drag move quinas do chão; Shift+Scroll redimensiona zonas; exibe diâmetro em px.

### Tipos de sessão e Dia automático
| Tipo de Sessão | Dia no CSV |
|---------------|------------|
| Treino | 1 |
| Reativação | 2 |
| Teste D2 | 2 |
| Teste D3 | 3 |

O tipo de sessão persiste entre rodadas. O timer de 300 s ao zerar abre `SessionResultDialog` pedindo apenas o número do animal (e droga, se `includeDrug`). Objetos e campos são preenchidos automaticamente.

### Inserção pós-sessão (SessionResultDialog)
Constrói linhas (uma por campo) e chama `ExperimentManager.insertSessionResult(name, rows)`. Cada linha tem a ordem das colunas do CSV:
```
[diretórioVídeo, animal, campo, dia, parDeObjetos, droga(opcional)]
```

---

## 🎨 Padrões Visuais
| Elemento | Cor |
|----------|-----|
| Accent / destaque | `#ab3d4c` (Vinho/Cereja) |
| Accent borda selecionada | `#7a2030` (contraste sobre fundo accent) |
| Background | `#0f0f1a` |
| Cards / Sidebar | `#1a1a2e` com borda `#2d2d4a` |
| Inputs | fundo `#12122a`, borda accent no focus |
| Hover | `#222240` / `#16162e` |
| Texto principal | `#e8e8f0` |
| Texto secundário | `#8888aa` |
| Texto desabilitado | `#555577` |

---

## 📝 Regras de Código

### Qt 5.12 LTS — restrições obrigatórias
- **Proibido:** `component X: Y {}` inline, `HorizontalHeaderView`, `Connections { function on...() }`, `Style=Basic`.
- **Imports QML:** `QtQuick 2.12`, `QtQuick.Controls 2.12`, `QtQuick.Layouts 1.3`, `QtGraphicalEffects 1.0`.
- **Q_INVOKABLE** não suporta argumentos com default value — use overloads separados.
- Popups que têm altura dinâmica: usar `anchors { left, right, top; margins }` no `ColumnLayout` interno (sem `bottom`), e calcular `height: mainLayout.implicitHeight + padding`.

### Estrutura de arquivos
- Toda nova tela QML → arquivo `.qml` próprio + entrada em `resources.qrc`.
- Componentes sem janela própria (ex.: `CampoSelector`) também ficam em arquivos separados.

---

## 🔮 Trabalho Futuro (não implementado)
- Motor de análise DeepLabCut/OpenCV para tracking live em vídeo 2×2 (`LiveRecording.qml`).
- Módulo de gravação de vídeo.
- Lógica de detecção snout-only (círculo de detecção por câmera).
- Número de animais por rodada (atualmente fixo em 3 campos); campos sem rato marcados como `"X"`.
