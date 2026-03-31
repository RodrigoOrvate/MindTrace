from PyQt6.QtWidgets import QWidget, QVBoxLayout, QHBoxLayout, QLineEdit, QComboBox, QLabel
from PyQt6.QtCore import Qt
from styles import COLORS
from components.buttons import (
    make_accent_button, make_ghost_button, make_separator,
    make_label, make_form_row, make_card_frame, make_success_banner,
)
from data.manager import start_session


class OpenFieldScreen(QWidget):
    """Tela de configuração para Campo Aberto e Habituação."""

    def __init__(self, go_home):
        super().__init__()
        self._go_home = go_home
        self._build()

    def _build(self):
        root = QVBoxLayout(self)
        root.setContentsMargins(60, 30, 60, 30)
        root.setSpacing(0)

        # ── Back + header ────────────────────────────────────────────────
        back = make_ghost_button("← Voltar")
        back.setFixedWidth(110)
        back.clicked.connect(self._go_home)
        top = QHBoxLayout()
        top.addWidget(back); top.addStretch()
        root.addLayout(top)
        root.addSpacing(12)

        h = QHBoxLayout()
        icon = QLabel("🐀")
        icon.setStyleSheet(f"font-size: 26px; color: {COLORS['accent']}; background: transparent;")
        title = QLabel("Campo Aberto / Habituação")
        title.setStyleSheet(f"color: {COLORS['text']}; font-size: 20px; font-weight: bold; background: transparent;")
        h.addWidget(icon); h.addSpacing(10); h.addWidget(title); h.addStretch()
        root.addLayout(h)
        root.addSpacing(4)
        root.addWidget(make_label("Parâmetros de exploração em campo aberto e habituação ao aparato", size=12, muted=True))
        root.addSpacing(14)
        root.addWidget(make_separator())
        root.addSpacing(20)

        # ── Formulário ───────────────────────────────────────────────────
        form = QVBoxLayout()
        form.setContentsMargins(24, 22, 24, 22)
        form.setSpacing(16)

        self.w_animal = QLineEdit()
        self.w_animal.setPlaceholderText("Ex: Rato_02_Grupo_Experimental")
        form.addLayout(make_form_row("ID do Animal", self.w_animal))

        self.w_sessao = QComboBox()
        self.w_sessao.addItems([
            "Habituação 1",
            "Habituação 2",
            "Habituação 3",
            "Campo Aberto (teste)",
        ])
        form.addLayout(make_form_row("Tipo de Sessão", self.w_sessao))

        self.w_arena = QLineEdit("Arena_A")
        form.addLayout(make_form_row("ID da Arena", self.w_arena))

        self.w_duracao = QLineEdit("10")
        form.addLayout(make_form_row("Duração da Sessão (min)", self.w_duracao))

        self.w_droga = QLineEdit()
        self.w_droga.setPlaceholderText("Ex: Salina, Diazepam 1 mg/kg")
        form.addLayout(make_form_row("Droga Utilizada", self.w_droga))

        self.w_peso = QLineEdit()
        self.w_peso.setPlaceholderText("Ex: 300")
        form.addLayout(make_form_row("Peso do Animal (g)", self.w_peso))

        root.addWidget(make_card_frame(form))
        root.addSpacing(16)

        self._feedback_lbl = make_success_banner("")
        self._feedback_lbl.setVisible(False)
        root.addWidget(self._feedback_lbl)

        root.addStretch()

        btn = make_accent_button("Iniciar Sessão  →")
        btn.setFixedWidth(200)
        btn.clicked.connect(self._on_start)
        root.addWidget(btn, alignment=Qt.AlignmentFlag.AlignRight)

    def _on_start(self):
        sessao_raw = self.w_sessao.currentText()
        fase_key   = sessao_raw.replace(" ", "_").replace("(", "").replace(")", "")
        metadata = {
            "aparato":     "Campo Aberto",
            "animal_id":   self.w_animal.text().strip() or "Animal",
            "fase":        fase_key,
            "arena":       self.w_arena.text().strip() or "Arena_A",
            "duracao_min": self.w_duracao.text().strip(),
            "droga":       self.w_droga.text().strip() or "N/A",
            "peso_g":      self.w_peso.text().strip() or "N/A",
        }
        session_path, _ = start_session("openfield", metadata)
        self._feedback_lbl.setText(
            f"✔  Sessão criada em:\n{session_path.resolve()}"
        )
        self._feedback_lbl.setVisible(True)
