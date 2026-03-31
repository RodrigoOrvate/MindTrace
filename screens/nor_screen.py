from PyQt6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QLineEdit, QComboBox, QLabel,
    QScrollArea,
)
from PyQt6.QtCore import Qt

from styles import COLORS
from components.buttons import (
    make_accent_button, make_ghost_button, make_separator,
    make_label, make_form_row, make_card_frame,
    make_warning_banner, make_success_banner,
)
from components.experiment_table import ExperimentTable
from data.manager import start_session


class NORScreen(QWidget):
    """
    Tela de sessão NOR com planilha interativa.

    Exibe campos de metadados (paradigma, animal, duração, droga, peso)
    e uma planilha editável para registro dos animais da sessão.
    Na fase "Teste", colunas extras para Objeto Familiar e Objeto Novo
    são adicionadas automaticamente.
    """

    def __init__(self, go_objectives):
        """
        Parâmetros
        ----------
        go_objectives : callable
            Navega de volta para a NORObjectiveScreen.
        """
        super().__init__()
        self._go_objectives = go_objectives
        self._fase          = "Habituação"
        self._session_path  = None
        self._tabela        = None
        self._construir()

    # ------------------------------------------------------------------
    def configure(self, fase: str):
        """Configura a tela para a fase selecionada na NORObjectiveScreen."""
        self._fase = fase
        self._session_path = None

        # Atualiza rótulo de fase no cabeçalho
        self._lbl_fase.setText(f"Fase: {fase}")

        # Troca a tabela pela versão correspondente à nova fase
        if self._tabela is not None:
            self._tabela.setParent(None)
            self._tabela.deleteLater()

        self._tabela = ExperimentTable(fase=self._fase)
        self._container_tabela.addWidget(self._tabela)

        # Atualiza o combo de fase para refletir a seleção
        mapa_combo = {
            "Habituação": "Habituação",
            "Treino":     "Treino (Aquisição)",
            "Teste":      "Teste (Retenção)",
        }
        idx = self.w_fase.findText(mapa_combo.get(fase, fase))
        if idx >= 0:
            self.w_fase.setCurrentIndex(idx)

        # Esconde banner de feedback anterior
        self._feedback_lbl.setVisible(False)

        # Reseta aviso de contexto
        self._ctx_warning.setVisible(self.w_contexto.currentIndex() == 1)

    # ------------------------------------------------------------------
    def _construir(self):
        # Área rolável para suportar janelas menores
        scroll = QScrollArea(self)
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QScrollArea.Shape.NoFrame)

        conteudo = QWidget()
        scroll.setWidget(conteudo)

        outer = QVBoxLayout(self)
        outer.setContentsMargins(0, 0, 0, 0)
        outer.addWidget(scroll)

        raiz = QVBoxLayout(conteudo)
        raiz.setContentsMargins(60, 30, 60, 30)
        raiz.setSpacing(0)

        # ── Botão Voltar + cabeçalho ─────────────────────────────────────
        btn_voltar = make_ghost_button("← Voltar")
        btn_voltar.setFixedWidth(110)
        btn_voltar.clicked.connect(self._go_objectives)
        linha_topo = QHBoxLayout()
        linha_topo.addWidget(btn_voltar)
        linha_topo.addStretch()
        raiz.addLayout(linha_topo)
        raiz.addSpacing(12)

        linha_titulo = QHBoxLayout()
        icone = QLabel("🧠")
        icone.setStyleSheet(
            f"font-size: 26px; color: {COLORS['accent']}; background: transparent;"
        )
        titulo = QLabel("Reconhecimento de Objetos")
        titulo.setStyleSheet(
            f"color: {COLORS['text']}; font-size: 20px; font-weight: bold; background: transparent;"
        )
        self._lbl_fase = QLabel(f"Fase: {self._fase}")
        self._lbl_fase.setStyleSheet(
            f"color: {COLORS['accent']}; font-size: 14px; font-weight: bold; "
            f"background: transparent; padding: 2px 10px;"
        )
        linha_titulo.addWidget(icone)
        linha_titulo.addSpacing(10)
        linha_titulo.addWidget(titulo)
        linha_titulo.addSpacing(16)
        linha_titulo.addWidget(self._lbl_fase)
        linha_titulo.addStretch()
        raiz.addLayout(linha_titulo)
        raiz.addSpacing(4)
        raiz.addWidget(make_label("Preencha os metadados e registre os animais na planilha", size=12, muted=True))
        raiz.addSpacing(14)
        raiz.addWidget(make_separator())
        raiz.addSpacing(20)

        # ── Aviso de contexto dependente ─────────────────────────────────
        self._ctx_warning = make_warning_banner(
            "Paradigma Dependente de Contexto: verifique se as dicas espaciais "
            "(figuras geométricas, texturas, padrões) estão fixadas nas paredes do aparato "
            "antes de iniciar a sessão."
        )
        self._ctx_warning.setVisible(False)
        raiz.addWidget(self._ctx_warning)

        # ── Formulário de metadados ───────────────────────────────────────
        form = QVBoxLayout()
        form.setContentsMargins(24, 22, 24, 22)
        form.setSpacing(16)

        self.w_contexto = QComboBox()
        self.w_contexto.addItems([
            "Independente de Contexto  (arena sem dicas espaciais)",
            "Dependente de Contexto  (dicas espaciais fixadas na parede do aparato)",
        ])
        self.w_contexto.currentIndexChanged.connect(self._ao_mudar_contexto)
        form.addLayout(make_form_row("Tipo de Paradigma", self.w_contexto))

        self.w_fase = QComboBox()
        self.w_fase.addItems(["Habituação", "Treino (Aquisição)", "Teste (Retenção)"])
        form.addLayout(make_form_row("Fase da Sessão", self.w_fase))

        self.w_animal = QLineEdit()
        self.w_animal.setPlaceholderText("Ex: Rato_01_Grupo_Controle")
        form.addLayout(make_form_row("ID do Animal / Lote", self.w_animal))

        self.w_duracao = QLineEdit("5")
        form.addLayout(make_form_row("Duração da Sessão (min)", self.w_duracao))

        self.w_droga = QLineEdit()
        self.w_droga.setPlaceholderText("Ex: Salina, Escopolamina 1 mg/kg")
        form.addLayout(make_form_row("Droga Utilizada", self.w_droga))

        self.w_peso = QLineEdit()
        self.w_peso.setPlaceholderText("Ex: 280")
        form.addLayout(make_form_row("Peso do Animal (g)", self.w_peso))

        raiz.addWidget(make_card_frame(form))
        raiz.addSpacing(20)

        # ── Planilha interativa ───────────────────────────────────────────
        raiz.addWidget(make_label("Planilha da Sessão", size=13, bold=True))
        raiz.addSpacing(8)

        self._container_tabela = QVBoxLayout()
        self._tabela = ExperimentTable(fase=self._fase)
        self._container_tabela.addWidget(self._tabela)
        raiz.addLayout(self._container_tabela)
        raiz.addSpacing(16)

        # ── Banner de feedback ────────────────────────────────────────────
        self._feedback_lbl = make_success_banner("")
        self._feedback_lbl.setVisible(False)
        raiz.addWidget(self._feedback_lbl)

        raiz.addSpacing(16)

        # ── Botão de ação ────────────────────────────────────────────────
        btn_iniciar = make_accent_button("Iniciar Sessão  →")
        btn_iniciar.setFixedWidth(200)
        btn_iniciar.clicked.connect(self._ao_iniciar)
        raiz.addWidget(btn_iniciar, alignment=Qt.AlignmentFlag.AlignRight)

    # ------------------------------------------------------------------
    def _ao_mudar_contexto(self, index):
        self._ctx_warning.setVisible(index == 1)

    def _ao_iniciar(self):
        mapa_fase = {
            "Habituação":         "Habituacao",
            "Treino (Aquisição)": "Treino",
            "Teste (Retenção)":   "Teste",
        }
        fase_raw = self.w_fase.currentText()
        metadata = {
            "aparato":      "Reconhecimento de Objetos",
            "animal_id":    self.w_animal.text().strip() or "Animal",
            "fase":         mapa_fase.get(fase_raw, fase_raw),
            "paradigma":    self.w_contexto.currentText(),
            "duracao_min":  self.w_duracao.text().strip(),
            "droga":        self.w_droga.text().strip() or "N/A",
            "peso_g":       self.w_peso.text().strip() or "N/A",
        }

        self._session_path, csv_path = start_session("nor", metadata)

        # Conecta a tabela à sessão e salva os dados
        self._tabela.set_caminho_sessao(self._session_path)
        caminho_tabela = self._tabela.salvar_csv()

        linhas_extras = ""
        if caminho_tabela:
            linhas_extras = f"\nPlanilha salva em: {caminho_tabela.name}"

        self._feedback_lbl.setText(
            f"✔  Sessão criada em:\n{self._session_path.resolve()}"
            f"\nMetadados salvos em metadata.csv{linhas_extras}"
        )
        self._feedback_lbl.setVisible(True)
