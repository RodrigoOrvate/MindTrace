from PyQt6.QtWidgets import QFrame, QVBoxLayout, QLabel, QGraphicsDropShadowEffect
from PyQt6.QtCore import Qt, QTimer
from PyQt6.QtGui import QCursor, QColor
from styles import COLORS

# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------

def _lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t

def _lerp_channel(a: int, b: int, t: float) -> int:
    return max(0, min(255, int(a + (b - a) * t)))

def _lerp_color(hex_a: str, hex_b: str, t: float) -> str:
    """Linearly interpolate between two hex colours."""
    a = tuple(int(hex_a.lstrip("#")[i:i+2], 16) for i in (0, 2, 4))
    b = tuple(int(hex_b.lstrip("#")[i:i+2], 16) for i in (0, 2, 4))
    r, g, bv = (_lerp_channel(a[i], b[i], t) for i in range(3))
    return f"#{r:02x}{g:02x}{bv:02x}"

def _smoothstep(t: float) -> float:
    """CSS-like ease-in-out curve."""
    t = max(0.0, min(1.0, t))
    return t * t * (3.0 - 2.0 * t)

# Colours for interpolation (normal → hover)
_BG_NORMAL     = COLORS["card"]       # #1a1a2e
_BG_HOVER      = "#222240"
_BORDER_NORMAL = COLORS["card_border"]  # #2d2d4a
_BORDER_HOVER  = COLORS["accent"]       # #ab3d4c
_SHADOW_NORMAL = "#000000"
_SHADOW_HOVER  = COLORS["accent"]

# Shadow parameters
_BLUR_MIN, _BLUR_MAX     = 10, 32
_ALPHA_MIN, _ALPHA_MAX   = 60, 150
_OFFSET_Y_MIN, _OFFSET_Y_MAX = 4, 8

_LABEL_RESET = "background: transparent; border: none; padding: 0; margin: 0;"

_ANIMATION_FPS  = 60
_ANIMATION_STEP = 1 / (_ANIMATION_FPS * 0.22)   # ~220 ms total


class ExperimentCard(QFrame):
    """
    Clickable card with smooth 60 fps hover animation.

    A single QGraphicsDropShadowEffect is kept alive for the card's
    lifetime and its properties are mutated in-place — avoids the
    'wrapped C/C++ object deleted' crash caused by setGraphicsEffect
    destroying the old object.
    """

    def __init__(self, icon: str, title: str, description: str, on_click):
        super().__init__()
        self.setObjectName("ExperimentCard")
        self._on_click = on_click
        self.setCursor(QCursor(Qt.CursorShape.PointingHandCursor))
        self.setFixedSize(215, 275)

        # Animation state
        self._t = 0.0          # 0 = fully normal, 1 = fully hovered
        self._target = 0.0
        self._timer = QTimer(self)
        self._timer.setInterval(1000 // _ANIMATION_FPS)
        self._timer.timeout.connect(self._tick)

        # Create ONE shadow effect — never replaced, only mutated
        self._fx = QGraphicsDropShadowEffect(self)
        self._fx.setOffset(0, _OFFSET_Y_MIN)
        self._fx.setBlurRadius(_BLUR_MIN)
        c = QColor(_SHADOW_NORMAL)
        c.setAlpha(_ALPHA_MIN)
        self._fx.setColor(c)
        self.setGraphicsEffect(self._fx)

        # Apply initial stylesheet
        self._apply(0.0)

        # ── Layout ───────────────────────────────────────────────────
        layout = QVBoxLayout(self)
        layout.setContentsMargins(22, 30, 22, 22)
        layout.setSpacing(0)
        layout.setAlignment(Qt.AlignmentFlag.AlignTop)

        # Icon — horizontally centred, large
        icon_lbl = QLabel(icon)
        icon_lbl.setAlignment(Qt.AlignmentFlag.AlignHCenter)
        icon_lbl.setStyleSheet(
            f"font-size: 40px; color: {COLORS['accent']}; {_LABEL_RESET}"
        )
        layout.addWidget(icon_lbl)
        layout.addSpacing(20)

        # Title
        title_lbl = QLabel(title)
        title_lbl.setAlignment(Qt.AlignmentFlag.AlignHCenter)
        title_lbl.setWordWrap(True)
        title_lbl.setStyleSheet(
            f"color: {COLORS['text']}; font-size: 14px; font-weight: bold; {_LABEL_RESET}"
        )
        layout.addWidget(title_lbl)
        layout.addSpacing(12)

        # Description
        desc_lbl = QLabel(description)
        desc_lbl.setAlignment(Qt.AlignmentFlag.AlignHCenter)
        desc_lbl.setWordWrap(True)
        desc_lbl.setStyleSheet(
            f"color: {COLORS['text_muted']}; font-size: 11px; {_LABEL_RESET}"
        )
        layout.addWidget(desc_lbl)
        layout.addStretch()

        # Bottom accent bar
        bar = QFrame()
        bar.setFixedHeight(3)
        bar.setStyleSheet(
            f"background: {COLORS['accent_dark']}; border: none; border-radius: 2px;"
        )
        layout.addWidget(bar)

    # ── Animation ────────────────────────────────────────────────────

    def _tick(self):
        step = _ANIMATION_STEP
        if self._t < self._target:
            self._t = min(self._target, self._t + step)
        else:
            self._t = max(self._target, self._t - step)

        self._apply(self._t)

        if abs(self._t - self._target) < 0.001:
            self._t = self._target
            self._timer.stop()

    def _apply(self, t: float):
        s = _smoothstep(t)

        # Background + border (stylesheet)
        bg     = _lerp_color(_BG_NORMAL, _BG_HOVER, s)
        border = _lerp_color(_BORDER_NORMAL, _BORDER_HOVER, s)
        self.setStyleSheet(f"""
            QFrame#ExperimentCard {{
                background-color: {bg};
                border: 1.5px solid {border};
                border-radius: 16px;
            }}
        """)

        # Shadow (mutate existing effect — no recreation)
        blur    = _lerp(_BLUR_MIN,     _BLUR_MAX,     s)
        alpha   = _lerp(_ALPHA_MIN,    _ALPHA_MAX,    s)
        offset  = _lerp(_OFFSET_Y_MIN, _OFFSET_Y_MAX, s)
        color   = _lerp_color(_SHADOW_NORMAL, _SHADOW_HOVER, s)
        c = QColor(color)
        c.setAlpha(int(alpha))
        self._fx.setColor(c)
        self._fx.setBlurRadius(blur)
        self._fx.setOffset(0, offset)

    # ── Mouse events ─────────────────────────────────────────────────

    def enterEvent(self, event):
        self._target = 1.0
        self._timer.start()
        super().enterEvent(event)

    def leaveEvent(self, event):
        self._target = 0.0
        self._timer.start()
        super().leaveEvent(event)

    def mousePressEvent(self, event):
        if event.button() == Qt.MouseButton.LeftButton:
            self._on_click()
