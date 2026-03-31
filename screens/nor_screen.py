from PyQt6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QLineEdit, QComboBox, QLabel
)
from PyQt6.QtCore import Qt
from styles import COLORS
from components.buttons import (
    make_accent_button, make_ghost_button, make_separator,
    make_label, make_form_row, make_card_frame,
    make_warning_banner, make_success_banner,
)
from data.manager import start_session


class NORScreen(QWidget):
    """
    Tela de configuração para Reconhecimento de Objetos (NOR).
    Suporta paradigmas dependente e independente de contexto.
    Fases: Habituação, Treino, Teste.
    """

    def __init__(self, go_home):
        super().__init__()
        self._go_home = go_home
        self._feedback_lbl = None
        self._build()

    # ------------------------------------------------------------------
    def _build(self):
        root = QVBoxLayout(self)
        root.setContentsMargins(60, 30, 60, 30)
        root.setSpacing(0)

        # ── Back + header ────────────────────────────────────────────────
        back = make_ghost_button("← Voltar")
        back.setFixedWidth(110)
        back.clicked.connect(self._go_home)
        top_row = QHBoxLayout()
        top_row.addWidget(back)
        top_row.addStretch()
        root.addLayout(top_row)
        root.addSpacing(12)

        h = QHBoxLayout()
        icon = QLabel("🧠")
        icon.setStyleSheet(f"font-size: 26px; color: {COLORS['accent']}; background: transparent;")
        title = QLabel("Reconhecimento de Objetos")
        title.setStyleSheet(f"color: {COLORS['text']}; font-size: 20px; font-weight: bold; background: transparent;")
        h.addWidget(icon); h.addSpacing(10); h.addWidget(title); h.addStretch()
        root.addLayout(h)
        root.addSpacing(4)
        root.addWidget(make_label("Defina o paradigma, fase e identificação do sujeito", size=12, muted=True))
        root.addSpacing(14)
        root.addWidget(make_separator())
        root.addSpacing(20)

        # ── Aviso de contexto (visível apenas quando dependente) ─────────
        self._ctx_warning = make_warning_banner(
            "Paradigma Dependente de Contexto: verifique se as dicas espaciais "
            "(figuras geométricas, texturas, padrões) estão fixadas nas paredes do aparato "
            "antes de iniciar a sessão."
        )
        self._ctx_warning.setVisible(False)
        root.addWidget(self._ctx_warning)
        self._ctx_warning_spacer_visible = False

        # ── Formulário ───────────────────────────────────────────────────
        form = QVBoxLayout()
        form.setContentsMargins(24, 22, 24, 22)
        form.setSpacing(16)

        # Tipo de contexto
        self.w_contexto = QComboBox()
        self.w_contexto.addItems([
            "Independente de Contexto  (arena sem dicas espaciais)",
            "Dependente de Contexto  (dicas espaciais fixadas na parede do aparato)",
        ])
        self.w_contexto.currentIndexChanged.connect(self._on_context_changed)
        form.addLayout(make_form_row("Tipo de Paradigma", self.w_contexto))

        # Fase
        self.w_fase = QComboBox()
        self.w_fase.addItems(["Habituação", "Treino (Aquisição)", "Teste (Retenção)"])
        form.addLayout(make_form_row("Fase da Sessão", self.w_fase))

        # ID animal
        self.w_animal = QLineEdit()
        self.w_animal.setPlaceholderText("Ex: Rato_01_Grupo_Controle")
        form.addLayout(make_form_row("ID do Animal", self.w_animal))

        # Duração
        self.w_duracao = QLineEdit("5")
        form.addLayout(make_form_row("Duração da Sessão (min)", self.w_duracao))

        # Droga
        self.w_droga = QLineEdit()
        self.w_droga.setPlaceholderText("Ex: Salina, Escopolamina 1 mg/kg")
        form.addLayout(make_form_row("Droga Utilizada", self.w_droga))

        # Peso
        self.w_peso = QLineEdit()
        self.w_peso.setPlaceholderText("Ex: 280")
        form.addLayout(make_form_row("Peso do Animal (g)", self.w_peso))

        root.addWidget(make_card_frame(form))
        root.addSpacing(16)

        # ── Feedback de sessão criada ────────────────────────────────────
        self._feedback_lbl = make_success_banner("")
        self._feedback_lbl.setVisible(False)
        root.addWidget(self._feedback_lbl)

        root.addStretch()

        # ── Botão de ação ────────────────────────────────────────────────
        btn = make_accent_button("Iniciar Sessão  →")
        btn.setFixedWidth(200)
        btn.clicked.connect(self._on_start)
        root.addWidget(btn, alignment=Qt.AlignmentFlag.AlignRight)

    # ------------------------------------------------------------------
    def _on_context_changed(self, index):
        self._ctx_warning.setVisible(index == 1)

    def _on_start(self):
        fase_map = {
            "Habituação":         "Habituacao",
            "Treino (Aquisição)": "Treino",
            "Teste (Retenção)":   "Teste",
        }
        fase_raw = self.w_fase.currentText()
        metadata = {
            "aparato":        "Reconhecimento de Objetos",
            "animal_id":      self.w_animal.text().strip() or "Animal",
            "fase":           fase_map.get(fase_raw, fase_raw),
            "paradigma":      self.w_contexto.currentText(),
            "duracao_min":    self.w_duracao.text().strip(),
            "droga":          self.w_droga.text().strip() or "N/A",
            "peso_g":         self.w_peso.text().strip() or "N/A",
        }
        session_path, csv_path = start_session("nor", metadata)
        self._feedback_lbl.setText(
            f"✔  Sessão criada em:\n{session_path.resolve()}\nMetadados salvos em metadata.csv"
        )
        self._feedback_lbl.setVisible(True)
