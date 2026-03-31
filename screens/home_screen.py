from PyQt6.QtWidgets import QWidget, QVBoxLayout, QHBoxLayout, QLabel
from PyQt6.QtCore import Qt
from styles import COLORS
from components.buttons import make_separator, make_label
from components.cards import ExperimentCard


class HomeScreen(QWidget):
    IDX_NOR       = 1
    IDX_OPENFIELD = 2
    IDX_ESQUIVA   = 3
    IDX_ELETROF   = 4

    def __init__(self, navigate_to):
        super().__init__()
        self._nav = navigate_to
        self._build()

    def _build(self):
        root = QVBoxLayout(self)
        root.setContentsMargins(40, 50, 40, 40)
        root.setSpacing(0)

        # ── Header ──────────────────────────────────────────────────────
        title = QLabel("OuroScan")
        title.setAlignment(Qt.AlignmentFlag.AlignCenter)
        title.setStyleSheet(
            f"color: {COLORS['text']}; font-size: 30px; font-weight: bold; "
            f"background: transparent; border: none; letter-spacing: 1px;"
        )

        subtitle = QLabel("Selecione o paradigma experimental para iniciar a configuração da sessão")
        subtitle.setAlignment(Qt.AlignmentFlag.AlignCenter)
        subtitle.setStyleSheet(
            f"color: {COLORS['text_muted']}; font-size: 13px; "
            f"background: transparent; border: none;"
        )

        root.addWidget(title)
        root.addSpacing(6)
        root.addWidget(subtitle)
        root.addSpacing(16)
        root.addWidget(make_separator())

        # ── Cards row (single horizontal line, centred) ──────────────────
        root.addStretch(1)

        CARDS = [
            ("🧠", "Reconhecimento\nde Objetos",
             "Paradigma NOR dependente ou independente de contexto",
             lambda: self._nav(self.IDX_NOR)),
            ("🐀", "Campo Aberto\n/ Habituação",
             "Exploração em campo aberto e habituação ao aparato",
             lambda: self._nav(self.IDX_OPENFIELD)),
            ("⚡", "Esquiva\nInibitória",
             "Memória aversiva passiva (step-through inhibitory avoidance)",
             lambda: self._nav(self.IDX_ESQUIVA)),
            ("📡", "Registro\nEletrofisiológico",
             "Canais, taxa de amostragem e sincronização com vídeo",
             lambda: self._nav(self.IDX_ELETROF)),
        ]

        cards_row = QHBoxLayout()
        cards_row.setSpacing(22)
        cards_row.addStretch()
        for icon, title_c, desc, fn in CARDS:
            cards_row.addWidget(ExperimentCard(icon, title_c, desc, fn))
        cards_row.addStretch()

        root.addLayout(cards_row)
        root.addStretch(1)

        # ── Footer ───────────────────────────────────────────────────────
        footer = make_label("Passo 0  —  Definição do Experimento", size=11, muted=True)
        footer.setAlignment(Qt.AlignmentFlag.AlignCenter)
        root.addWidget(footer)
