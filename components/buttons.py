from PyQt6.QtWidgets import QPushButton, QLabel, QFrame, QHBoxLayout
from PyQt6.QtCore import Qt
from PyQt6.QtGui import QCursor
from styles import COLORS


def make_accent_button(text, small=False):
    btn = QPushButton(text)
    size = "11px" if small else "13px"
    pad  = "6px 14px" if small else "9px 22px"
    btn.setStyleSheet(f"""
        QPushButton {{
            background-color: {COLORS['accent']};
            color: {COLORS['text']};
            border: none;
            border-radius: 7px;
            padding: {pad};
            font-size: {size};
            font-weight: bold;
        }}
        QPushButton:hover {{
            background-color: {COLORS['accent_hover']};
        }}
        QPushButton:pressed {{
            background-color: {COLORS['accent_dark']};
        }}
        QPushButton:disabled {{
            background-color: {COLORS['card_border']};
            color: {COLORS['text_muted']};
        }}
    """)
    btn.setCursor(QCursor(Qt.CursorShape.PointingHandCursor))
    return btn


def make_ghost_button(text):
    btn = QPushButton(text)
    btn.setStyleSheet(f"""
        QPushButton {{
            background-color: transparent;
            color: {COLORS['text_muted']};
            border: 1px solid {COLORS['card_border']};
            border-radius: 7px;
            padding: 7px 18px;
            font-size: 12px;
        }}
        QPushButton:hover {{
            color: {COLORS['text']};
            border-color: {COLORS['accent']};
        }}
        QPushButton:pressed {{
            background-color: {COLORS['surface']};
        }}
    """)
    btn.setCursor(QCursor(Qt.CursorShape.PointingHandCursor))
    return btn


def make_browse_button(text="..."):
    btn = QPushButton(text)
    btn.setFixedWidth(40)
    btn.setStyleSheet(f"""
        QPushButton {{
            background-color: {COLORS['surface']};
            color: {COLORS['text_muted']};
            border: 1px solid {COLORS['input_border']};
            border-radius: 6px;
            padding: 6px;
            font-size: 13px;
        }}
        QPushButton:hover {{
            border-color: {COLORS['accent']};
            color: {COLORS['text']};
        }}
    """)
    btn.setCursor(QCursor(Qt.CursorShape.PointingHandCursor))
    return btn


def make_separator():
    line = QFrame()
    line.setFrameShape(QFrame.Shape.HLine)
    line.setStyleSheet(
        f"background: {COLORS['card_border']}; border: none; max-height: 1px;"
    )
    return line


def make_label(text, size=13, muted=False, bold=False):
    lbl = QLabel(text)
    color  = COLORS["text_muted"] if muted else COLORS["text"]
    weight = "bold" if bold else "normal"
    lbl.setStyleSheet(
        f"color: {color}; font-size: {size}px; font-weight: {weight}; background: transparent;"
    )
    return lbl


def make_form_row(label_text, widget):
    """Returns a QHBoxLayout with a fixed-width muted label and the given widget."""
    row = QHBoxLayout()
    row.setSpacing(12)
    lbl = make_label(label_text, size=12, muted=True)
    lbl.setFixedWidth(210)
    lbl.setAlignment(Qt.AlignmentFlag.AlignVCenter | Qt.AlignmentFlag.AlignLeft)
    row.addWidget(lbl)
    row.addWidget(widget)
    return row


def make_card_frame(inner_layout):
    """Wraps a layout inside a styled QFrame card."""
    frame = QFrame()
    frame.setStyleSheet(f"""
        QFrame {{
            background-color: {COLORS['card']};
            border: 1px solid {COLORS['card_border']};
            border-radius: 10px;
        }}
    """)
    frame.setLayout(inner_layout)
    return frame


def make_warning_banner(text):
    """Yellow-tinted banner for in-screen alerts."""
    lbl = QLabel(f"⚠  {text}")
    lbl.setWordWrap(True)
    lbl.setStyleSheet(f"""
        QLabel {{
            background-color: rgba(255, 165, 2, 0.12);
            border: 1px solid {COLORS['warning']};
            border-radius: 7px;
            color: {COLORS['warning']};
            font-size: 12px;
            padding: 10px 14px;
        }}
    """)
    return lbl


def make_success_banner(text):
    """Accent-tinted banner for success feedback."""
    lbl = QLabel(f"✔  {text}")
    lbl.setWordWrap(True)
    lbl.setStyleSheet(f"""
        QLabel {{
            background-color: rgba(171, 61, 76, 0.15);
            border: 1px solid {COLORS['accent']};
            border-radius: 7px;
            color: {COLORS['accent_hover']};
            font-size: 12px;
            padding: 10px 14px;
        }}
    """)
    return lbl
