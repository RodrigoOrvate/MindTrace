from PyQt6.QtWidgets import QWidget, QVBoxLayout, QHBoxLayout, QLabel
from PyQt6.QtCore import Qt

from styles import COLORS
from components.buttons import make_ghost_button, make_separator, make_label
from components.cards import ExperimentCard


class NORObjectiveScreen(QWidget):
    """
    Tela de seleção de objetivo para Reconhecimento de Objetos (NOR).
    Apresenta três cards: Habituação, Treino e Teste.
    """

    def __init__(self, go_home, go_nor):
        """
        Parâmetros
        ----------
        go_home : callable
            Navega de volta para a Home.
        go_nor : callable(fase: str)
            Navega para a NORScreen configurada com a fase selecionada.
        """
        super().__init__()
        self._go_home = go_home
        self._go_nor  = go_nor
        self._construir()

    # ------------------------------------------------------------------
    def _construir(self):
        raiz = QVBoxLayout(self)
        raiz.setContentsMargins(60, 30, 60, 30)
        raiz.setSpacing(0)

        # ── Botão Voltar ─────────────────────────────────────────────────
        btn_voltar = make_ghost_button("← Voltar")
        btn_voltar.setFixedWidth(110)
        btn_voltar.clicked.connect(self._go_home)
        linha_topo = QHBoxLayout()
        linha_topo.addWidget(btn_voltar)
        linha_topo.addStretch()
        raiz.addLayout(linha_topo)
        raiz.addSpacing(12)

        # ── Cabeçalho ────────────────────────────────────────────────────
        linha_titulo = QHBoxLayout()
        icone = QLabel("🧠")
        icone.setStyleSheet(
            f"font-size: 26px; color: {COLORS['accent']}; background: transparent;"
        )
        titulo = QLabel("Reconhecimento de Objetos")
        titulo.setStyleSheet(
            f"color: {COLORS['text']}; font-size: 20px; font-weight: bold; background: transparent;"
        )
        linha_titulo.addWidget(icone)
        linha_titulo.addSpacing(10)
        linha_titulo.addWidget(titulo)
        linha_titulo.addStretch()
        raiz.addLayout(linha_titulo)
        raiz.addSpacing(4)
        raiz.addWidget(make_label("Selecione o objetivo da sessão", size=12, muted=True))
        raiz.addSpacing(14)
        raiz.addWidget(make_separator())
        raiz.addStretch(1)

        # ── Cards de objetivo ────────────────────────────────────────────
        OBJETIVOS = [
            (
                "📋",
                "Habituação",
                "Familiarize o animal com o aparato antes das sessões de treino.",
                "Habituação",
            ),
            (
                "🔬",
                "Treino",
                "Sessão de aquisição: apresente os objetos familiares ao animal.",
                "Treino",
            ),
            (
                "🧪",
                "Teste",
                "Sessão de retenção: avalie a discriminação entre objeto familiar e novo.",
                "Teste",
            ),
        ]

        linha_cards = QHBoxLayout()
        linha_cards.setSpacing(22)
        linha_cards.addStretch()
        for icone_txt, titulo_txt, desc_txt, fase in OBJETIVOS:
            card = ExperimentCard(
                icon=icone_txt,
                title=titulo_txt,
                description=desc_txt,
                on_click=lambda f=fase: self._go_nor(f),
            )
            linha_cards.addWidget(card)
        linha_cards.addStretch()
        raiz.addLayout(linha_cards)

        raiz.addStretch(1)

        # ── Rodapé ───────────────────────────────────────────────────────
        rodape = make_label("Passo 1  —  Objetivo da Sessão", size=11, muted=True)
        rodape.setAlignment(Qt.AlignmentFlag.AlignCenter)
        raiz.addWidget(rodape)
