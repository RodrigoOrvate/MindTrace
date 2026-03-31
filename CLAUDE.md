# MindTrace - Guidelines de Desenvolvimento

## 🛠 Arquitetura do Projeto
- **main.py**: Orquestrador principal (QStackedWidget e navegação).
- **styles.py**: Contém o dicionário `COLORS` e o `GLOBAL_STYLE`.
- **components/**: Widgets reutilizáveis (ExperimentCard, CustomButtons, Header).
- **screens/**: Uma classe por arquivo para cada experimento (NOR, OpenField, etc.).
- **data/**: Gerenciador de IO (Input/Output). Criação de pastas e arquivos Excel.

## 📁 Estrutura de Pastas de Saída (Data Management)
O sistema deve seguir o padrão:
`MindTrace_Results/ <Aparato> / <Sessao_Animal_Data> /`
Arquivos gerados: `metadata.csv`, `tracking_data.csv`, `video_output.mp4`.

## 🎨 Padrões Visuais
- **Accent Color**: #ab3d4c (Vinho/Cereja).
- **Cards**: #1a1a2e com bordas de 1px.
- **Inputs**: Fundo #12122a, borda accent no focus.

## 📝 Regras de Código
- Usar `pathlib` para manipulação de caminhos.
- Cada tela de experimento deve herdar de `QWidget`.
- Manter o `on_click` do ExperimentCard como disparador de troca de página no Stack.