# styles.py
COLORS = {
    "bg":            "#0f0f1a",
    "card":          "#1a1a2e",
    "card_border":   "#2d2d4a",
    "accent":        "#ab3d4c",
    "accent_hover":  "#c9505f",
    "accent_dark":   "#8a2e3b",
    "danger":        "#ff4757",
    "danger_hover":  "#ff6b7a",
    "text":          "#e8e8f0",
    "text_muted":    "#8888aa",
    "input_bg":      "#12122a",
    "input_border":  "#3a3a5c",
    "input_focus":   "#ab3d4c",
    "surface":       "#16162e",
    "success":       "#ab3d4c",
    "warning":       "#ffa502",
    "scroll_bg":     "#1a1a2e",
    "scroll_handle": "#3a3a5c",
}

GLOBAL_STYLE = f"""
    QMainWindow, QWidget {{
        background-color: {COLORS['bg']};
        color: {COLORS['text']};
        font-family: 'Segoe UI', sans-serif;
    }}
    QLabel {{
        color: {COLORS['text']};
        background: transparent;
    }}
    QComboBox {{
        background-color: {COLORS['input_bg']};
        color: {COLORS['text']};
        border: 1px solid {COLORS['input_border']};
        border-radius: 6px;
        padding: 6px 10px;
        font-size: 13px;
        min-height: 32px;
    }}
    QComboBox:focus {{
        border: 1px solid {COLORS['input_focus']};
    }}
    QComboBox::drop-down {{
        border: none;
        width: 24px;
    }}
    QComboBox QAbstractItemView {{
        background-color: {COLORS['card']};
        color: {COLORS['text']};
        border: 1px solid {COLORS['card_border']};
        selection-background-color: {COLORS['accent']};
        outline: none;
    }}
    QLineEdit {{
        background-color: {COLORS['input_bg']};
        color: {COLORS['text']};
        border: 1px solid {COLORS['input_border']};
        border-radius: 6px;
        padding: 6px 10px;
        font-size: 13px;
        min-height: 32px;
    }}
    QLineEdit:focus {{
        border: 1px solid {COLORS['input_focus']};
    }}
    QScrollBar:vertical {{
        background: {COLORS['scroll_bg']};
        width: 8px;
        border-radius: 4px;
        margin: 0;
    }}
    QScrollBar::handle:vertical {{
        background: {COLORS['scroll_handle']};
        border-radius: 4px;
        min-height: 30px;
    }}
    QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {{
        height: 0px;
    }}
    QScrollBar:horizontal {{
        background: {COLORS['scroll_bg']};
        height: 8px;
        border-radius: 4px;
    }}
    QScrollBar::handle:horizontal {{
        background: {COLORS['scroll_handle']};
        border-radius: 4px;
    }}
    QScrollBar::add-line:horizontal, QScrollBar::sub-line:horizontal {{
        width: 0px;
    }}
"""
