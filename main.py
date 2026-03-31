import sys
from pathlib import Path

from PyQt6.QtWidgets import QApplication, QMainWindow, QStackedWidget
from PyQt6.QtGui import QColor, QPalette, QIcon

from styles import COLORS, GLOBAL_STYLE
from screens.home_screen import HomeScreen
from screens.nor_objective_screen import NORObjectiveScreen
from screens.nor_screen import NORScreen
from screens.openfield_screen import OpenFieldScreen
from screens.esquiva_screen import EsquivaScreen
from screens.eletrof_screen import EletrofScreen


class MindTrace(QMainWindow):
    """
    Orquestrador principal do MindTrace.
    Gerencia o QStackedWidget e a navegação entre telas.

    Índices do stack:
        0 — Home
        1 — Seleção de Objetivo NOR
        2 — Sessão NOR (com planilha)
        3 — Campo Aberto / Habituação
        4 — Esquiva Inibitória
        5 — Registro Eletrofisiológico
    """

    IDX_HOME          = 0
    IDX_NOR_OBJETIVO  = 1
    IDX_NOR           = 2
    IDX_OPENFIELD     = 3
    IDX_ESQUIVA       = 4
    IDX_ELETROF       = 5

    def __init__(self):
        super().__init__()
        self.setWindowTitle("MindTrace")
        self.resize(980, 700)
        self.setMinimumSize(820, 580)
        self.setStyleSheet(GLOBAL_STYLE)

        self.stack = QStackedWidget()
        self.setCentralWidget(self.stack)

        go_home      = lambda: self.stack.setCurrentIndex(self.IDX_HOME)
        go_objetivos = lambda: self.stack.setCurrentIndex(self.IDX_NOR_OBJETIVO)

        self._nor_screen = NORScreen(go_objectives=go_objetivos)

        def go_nor(fase: str):
            self._nor_screen.configure(fase)
            self.stack.setCurrentIndex(self.IDX_NOR)

        paginas = [
            HomeScreen(navigate_to=self.stack.setCurrentIndex),          # 0
            NORObjectiveScreen(go_home=go_home, go_nor=go_nor),          # 1
            self._nor_screen,                                             # 2
            OpenFieldScreen(go_home=go_home),                            # 3
            EsquivaScreen(go_home=go_home),                              # 4
            EletrofScreen(go_home=go_home),                              # 5
        ]
        for pagina in paginas:
            self.stack.addWidget(pagina)

        self.stack.setCurrentIndex(self.IDX_HOME)


def _aplicar_paleta(app: QApplication) -> None:
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
    _aplicar_paleta(app)

    icon_path = Path(__file__).parent / "memorylab.ico"
    if icon_path.exists():
        app.setWindowIcon(QIcon(str(icon_path)))

    window = MindTrace()
    window.show()
    sys.exit(app.exec())
