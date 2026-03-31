from PyQt6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout,
    QLineEdit, QComboBox, QLabel, QFileDialog
)
from PyQt6.QtCore import Qt
from styles import COLORS
from components.buttons import (
    make_accent_button, make_ghost_button, make_browse_button,
    make_separator, make_label, make_form_row, make_card_frame,
    make_success_banner,
)
from data.manager import start_session


class EletrofScreen(QWidget):
    """Tela de configuração para Registro Eletrofisiológico."""

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
        icon = QLabel("📡")
        icon.setStyleSheet(f"font-size: 26px; color: {COLORS['accent']}; background: transparent;")
        title = QLabel("Registro Eletrofisiológico")
        title.setStyleSheet(f"color: {COLORS['text']}; font-size: 20px; font-weight: bold; background: transparent;")
        h.addWidget(icon); h.addSpacing(10); h.addWidget(title); h.addStretch()
        root.addLayout(h)
        root.addSpacing(4)
        root.addWidget(make_label("Canais, taxa de amostragem e sincronização com vídeo", size=12, muted=True))
        root.addSpacing(14)
        root.addWidget(make_separator())
        root.addSpacing(20)

        # ── Formulário ───────────────────────────────────────────────────
        form = QVBoxLayout()
        form.setContentsMargins(24, 22, 24, 22)
        form.setSpacing(16)

        self.w_animal = QLineEdit()
        self.w_animal.setPlaceholderText("Ex: Rato_04_Implantado_CA1")
        form.addLayout(make_form_row("ID do Animal", self.w_animal))

        self.w_regiao = QComboBox()
        self.w_regiao.addItems([
            "Hipocampo CA1",
            "Hipocampo CA3",
            "Giro Denteado",
            "Córtex Pré-frontal",
            "Amígdala BLA",
            "Outro",
        ])
        form.addLayout(make_form_row("Região de Registro", self.w_regiao))

        self.w_taxa = QComboBox()
        self.w_taxa.addItems(["1 000 Hz", "2 000 Hz", "10 000 Hz", "20 000 Hz", "30 000 Hz"])
        self.w_taxa.setCurrentIndex(3)
        form.addLayout(make_form_row("Taxa de Amostragem", self.w_taxa))

        self.w_canais = QLineEdit("1,2,3,4")
        form.addLayout(make_form_row("Canais Ativos (ex: 1,2,3,4)", self.w_canais))

        self.w_sync = QComboBox()
        self.w_sync.addItems(["Sem sincronização", "TTL via câmera", "TTL manual"])
        form.addLayout(make_form_row("Sincronização com Vídeo", self.w_sync))

        # Diretório do arquivo de registro — linha com campo + botão Browse
        dir_row = QHBoxLayout()
        dir_row.setSpacing(6)
        self.w_arquivo = QLineEdit()
        self.w_arquivo.setPlaceholderText("Caminho para o arquivo .dat / .xml de registro")
        browse_btn = make_browse_button("...")
        browse_btn.clicked.connect(self._browse_file)
        dir_row.addWidget(self.w_arquivo)
        dir_row.addWidget(browse_btn)
        form.addLayout(make_form_row("Arquivo de Registro (.dat/.xml)", _wrap_layout(dir_row)))

        self.w_droga = QLineEdit()
        self.w_droga.setPlaceholderText("Ex: Salina, Tetrodotoxina 0.1 µg/side")
        form.addLayout(make_form_row("Droga Utilizada", self.w_droga))

        self.w_peso = QLineEdit()
        self.w_peso.setPlaceholderText("Ex: 310")
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

    # ------------------------------------------------------------------
    def _browse_file(self):
        path, _ = QFileDialog.getOpenFileName(
            self,
            "Selecionar arquivo de registro",
            "",
            "Arquivos de registro (*.dat *.xml);;Todos os arquivos (*)",
        )
        if path:
            self.w_arquivo.setText(path)

    def _on_start(self):
        metadata = {
            "aparato":       "Eletrofisiologia",
            "animal_id":     self.w_animal.text().strip() or "Animal",
            "fase":          "Registro",
            "regiao":        self.w_regiao.currentText(),
            "taxa_hz":       self.w_taxa.currentText(),
            "canais":        self.w_canais.text().strip(),
            "sync_video":    self.w_sync.currentText(),
            "arquivo_reg":   self.w_arquivo.text().strip() or "N/A",
            "droga":         self.w_droga.text().strip() or "N/A",
            "peso_g":        self.w_peso.text().strip() or "N/A",
        }
        session_path, _ = start_session("eletrof", metadata)
        self._feedback_lbl.setText(
            f"✔  Sessão criada em:\n{session_path.resolve()}"
        )
        self._feedback_lbl.setVisible(True)


# ------------------------------------------------------------------
def _wrap_layout(layout):
    """Wraps a QLayout into a QWidget so it can be used inside make_form_row."""
    from PyQt6.QtWidgets import QWidget as _W
    w = _W()
    w.setStyleSheet("background: transparent;")
    w.setLayout(layout)
    return w
