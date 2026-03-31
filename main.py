import sys
from pathlib import Path

from PyQt6.QtWidgets import QApplication, QMainWindow, QStackedWidget
from PyQt6.QtGui import QColor, QPalette, QIcon

from styles import COLORS, GLOBAL_STYLE
from screens.home_screen import HomeScreen
from screens.nor_screen import NORScreen
from screens.openfield_screen import OpenFieldScreen
from screens.esquiva_screen import EsquivaScreen
from screens.eletrof_screen import EletrofScreen


class OuroScan(QMainWindow):
    """
    Orquestrador principal.
    Gerencia o QStackedWidget e a navegação entre telas.

    Índices do stack:
        0 — Home
        1 — Reconhecimento de Objetos (NOR)
        2 — Campo Aberto / Habituação
        3 — Esquiva Inibitória
        4 — Registro Eletrofisiológico
    """

    def __init__(self):
        super().__init__()
        self.setWindowTitle("OuroScan")
        self.resize(980, 660)
        self.setMinimumSize(820, 560)
        self.setStyleSheet(GLOBAL_STYLE)

        self.stack = QStackedWidget()
        self.setCentralWidget(self.stack)

        go_home = lambda: self.stack.setCurrentIndex(0)

        pages = [
            HomeScreen(navigate_to=self.stack.setCurrentIndex),
            NORScreen(go_home=go_home),
            OpenFieldScreen(go_home=go_home),
            EsquivaScreen(go_home=go_home),
            EletrofScreen(go_home=go_home),
        ]
        for page in pages:
            self.stack.addWidget(page)

        self.stack.setCurrentIndex(0)


def _apply_palette(app: QApplication) -> None:
    app.setStyle("Fusion")
    p = QPalette()
    p.setColor(QPalette.ColorRole.Window,          QColor(COLORS["bg"]))
    p.setColor(QPalette.ColorRole.WindowText,      QColor(COLORS["text"]))
    p.setColor(QPalette.ColorRole.Base,            QColor(COLORS["input_bg"]))
    p.setColor(QPalette.ColorRole.AlternateBase,   QColor(COLORS["card"]))
    p.setColor(QPalette.ColorRole.Text,            QColor(COLORS["text"]))
    p.setColor(QPalette.ColorRole.Button,          QColor(COLORS["card"]))
    p.setColor(QPalette.ColorRole.ButtonText,      QColor(COLORS["text"]))
    p.setColor(QPalette.ColorRole.Highlight,       QColor(COLORS["accent"]))
    p.setColor(QPalette.ColorRole.HighlightedText, QColor(COLORS["text"]))
    p.setColor(QPalette.ColorRole.ToolTipBase,     QColor(COLORS["surface"]))
    p.setColor(QPalette.ColorRole.ToolTipText,     QColor(COLORS["text"]))
    app.setPalette(p)


if __name__ == "__main__":
    app = QApplication(sys.argv)
    _apply_palette(app)

    # Ícone da janela (memorylab.ico na raiz do projeto)
    icon_path = Path(__file__).parent / "memorylab.ico"
    if icon_path.exists():
        app.setWindowIcon(QIcon(str(icon_path)))

    window = OuroScan()
    window.show()
    sys.exit(app.exec())
