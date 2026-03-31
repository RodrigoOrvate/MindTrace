"""
components/experiment_table.py
-------------------------------
Planilha interativa para registro de experimentos NOR.
Suporta adição/remoção de colunas e linhas, edição manual de células,
drag-and-drop de arquivos de vídeo e persistência em CSV.
"""

import csv
from pathlib import Path

from PyQt6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout,
    QTableWidget, QTableWidgetItem,
    QHeaderView, QAbstractItemView,
    QInputDialog, QLabel,
)
from PyQt6.QtCore import Qt

from styles import COLORS
from components.buttons import make_ghost_button


# ── Subclasse com suporte a drag-and-drop de arquivos ────────────────────────

class _TabelaArrastavel(QTableWidget):
    """QTableWidget que aceita arrastar arquivos de vídeo para as células."""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.setAcceptDrops(True)
        self.setDragDropMode(QAbstractItemView.DragDropMode.DropOnly)
        self.callback_soltar = None  # fn(row: int, caminhos: list[str])

    def dragEnterEvent(self, event):          # noqa: N802
        if event.mimeData().hasUrls():
            event.acceptProposedAction()
        else:
            super().dragEnterEvent(event)

    def dragMoveEvent(self, event):           # noqa: N802
        if event.mimeData().hasUrls():
            event.acceptProposedAction()
        else:
            super().dragMoveEvent(event)

    def dropEvent(self, event):               # noqa: N802
        urls = event.mimeData().urls()
        if not urls:
            super().dropEvent(event)
            return
        pos = event.position().toPoint()
        linha = self.rowAt(pos.y())
        if self.callback_soltar:
            self.callback_soltar(linha, [u.toLocalFile() for u in urls])
        event.acceptProposedAction()


# ── Widget principal ──────────────────────────────────────────────────────────

class ExperimentTable(QWidget):
    """
    Planilha interativa para registro de sessões NOR.

    Parâmetros
    ----------
    fase : str
        "Habituação", "Treino" ou "Teste".
        Na fase "Teste", colunas extras ("Objeto Familiar", "Objeto Novo")
        são adicionadas automaticamente.
    caminho_sessao : Path | None
        Diretório da sessão onde o CSV será salvo.
        Pode ser definido depois com set_caminho_sessao().
    """

    COLUNAS_PADRAO = ["Animal ID", "Fase", "Droga", "Peso (g)", "Vídeo"]
    COLUNAS_TESTE  = ["Objeto Familiar", "Objeto Novo"]

    def __init__(self, fase: str, caminho_sessao: Path | None = None, parent=None):
        super().__init__(parent)
        self._fase          = fase
        self._caminho_sessao = caminho_sessao
        self._construir()

    # ------------------------------------------------------------------
    def _construir(self):
        raiz = QVBoxLayout(self)
        raiz.setContentsMargins(0, 0, 0, 0)
        raiz.setSpacing(8)

        # ── Barra de ferramentas ─────────────────────────────────────────
        barra = QHBoxLayout()

        btn_add_coluna = make_ghost_button("＋ Coluna")
        btn_add_coluna.clicked.connect(self._adicionar_coluna)
        barra.addWidget(btn_add_coluna)

        btn_add_linha = make_ghost_button("＋ Linha")
        btn_add_linha.clicked.connect(self._adicionar_linha)
        barra.addWidget(btn_add_linha)

        btn_rem_linha = make_ghost_button("✕ Remover Linha")
        btn_rem_linha.clicked.connect(self._remover_linha_selecionada)
        barra.addWidget(btn_rem_linha)

        barra.addStretch()

        lbl_dica = QLabel("Arraste vídeos (.mp4, .avi) diretamente para a coluna Vídeo")
        lbl_dica.setStyleSheet(
            f"color: {COLORS['text_muted']}; font-size: 11px; background: transparent;"
        )
        barra.addWidget(lbl_dica)

        raiz.addLayout(barra)

        # ── Tabela ───────────────────────────────────────────────────────
        colunas = list(self.COLUNAS_PADRAO)
        if self._fase == "Teste":
            colunas += self.COLUNAS_TESTE

        self._tabela = _TabelaArrastavel(0, len(colunas))
        self._tabela.setHorizontalHeaderLabels(colunas)
        self._tabela.horizontalHeader().setSectionResizeMode(
            QHeaderView.ResizeMode.Interactive
        )
        self._tabela.horizontalHeader().setStretchLastSection(True)
        self._tabela.horizontalHeader().setMinimumSectionSize(80)
        self._tabela.verticalHeader().setDefaultSectionSize(32)
        self._tabela.setAlternatingRowColors(True)
        self._tabela.setStyleSheet(self._estilo_tabela())
        self._tabela.callback_soltar = self._ao_soltar_video

        raiz.addWidget(self._tabela)

        # Linha inicial vazia
        self._adicionar_linha()

    # ------------------------------------------------------------------
    def _estilo_tabela(self) -> str:
        return f"""
            QTableWidget {{
                background-color: {COLORS['card']};
                color: {COLORS['text']};
                border: 1px solid {COLORS['card_border']};
                border-radius: 6px;
                gridline-color: {COLORS['card_border']};
                font-size: 13px;
            }}
            QTableWidget::item {{
                padding: 4px 8px;
            }}
            QTableWidget::item:selected {{
                background-color: {COLORS['accent']};
                color: {COLORS['text']};
            }}
            QTableWidget::item:alternate {{
                background-color: {COLORS['surface']};
            }}
            QHeaderView::section {{
                background-color: {COLORS['input_bg']};
                color: {COLORS['text_muted']};
                border: none;
                border-right: 1px solid {COLORS['card_border']};
                border-bottom: 1px solid {COLORS['card_border']};
                padding: 4px 8px;
                font-size: 12px;
                font-weight: bold;
            }}
        """

    # ------------------------------------------------------------------
    def _adicionar_coluna(self):
        nome, ok = QInputDialog.getText(self, "Nova Coluna", "Nome da coluna:")
        if ok and nome.strip():
            col = self._tabela.columnCount()
            self._tabela.insertColumn(col)
            self._tabela.setHorizontalHeaderItem(col, QTableWidgetItem(nome.strip()))
            for linha in range(self._tabela.rowCount()):
                self._tabela.setItem(linha, col, QTableWidgetItem(""))

    def _adicionar_linha(self):
        linha = self._tabela.rowCount()
        self._tabela.insertRow(linha)
        for col in range(self._tabela.columnCount()):
            self._tabela.setItem(linha, col, QTableWidgetItem(""))

    def _remover_linha_selecionada(self):
        selecionados = self._tabela.selectedItems()
        if not selecionados:
            return
        linhas = sorted(
            {item.row() for item in selecionados}, reverse=True
        )
        for linha in linhas:
            self._tabela.removeRow(linha)

    def _ao_soltar_video(self, linha_alvo: int, caminhos: list):
        """Preenche a coluna Vídeo a partir de arquivos arrastados."""
        col_video = self._encontrar_coluna("Vídeo")
        if col_video < 0:
            return
        for i, caminho in enumerate(caminhos):
            linha = linha_alvo + i
            while linha >= self._tabela.rowCount():
                self._adicionar_linha()
            self._tabela.setItem(linha, col_video, QTableWidgetItem(caminho))

    def _encontrar_coluna(self, nome: str) -> int:
        for col in range(self._tabela.columnCount()):
            cabecalho = self._tabela.horizontalHeaderItem(col)
            if cabecalho and cabecalho.text() == nome:
                return col
        return -1

    # ------------------------------------------------------------------  API pública

    def set_caminho_sessao(self, caminho: Path):
        self._caminho_sessao = caminho

    def salvar_csv(self) -> Path | None:
        """Salva os dados da tabela em experiment_data.csv na pasta da sessão."""
        if not self._caminho_sessao:
            return None
        cabecalhos = [
            self._tabela.horizontalHeaderItem(col).text()
            for col in range(self._tabela.columnCount())
        ]
        linhas = []
        for linha in range(self._tabela.rowCount()):
            dados_linha = []
            for col in range(self._tabela.columnCount()):
                item = self._tabela.item(linha, col)
                dados_linha.append(item.text() if item else "")
            linhas.append(dados_linha)

        caminho_csv = self._caminho_sessao / "experiment_data.csv"
        with open(caminho_csv, "w", newline="", encoding="utf-8") as f:
            escritor = csv.writer(f)
            escritor.writerow(cabecalhos)
            escritor.writerows(linhas)
        return caminho_csv

    def obter_dados(self) -> list[dict]:
        """Retorna os dados da tabela como lista de dicionários."""
        cabecalhos = [
            self._tabela.horizontalHeaderItem(col).text()
            for col in range(self._tabela.columnCount())
        ]
        resultado = []
        for linha in range(self._tabela.rowCount()):
            linha_dict = {}
            for col, cab in enumerate(cabecalhos):
                item = self._tabela.item(linha, col)
                linha_dict[cab] = item.text() if item else ""
            resultado.append(linha_dict)
        return resultado
