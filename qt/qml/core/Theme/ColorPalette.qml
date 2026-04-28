pragma Singleton
import QtQuick

QtObject {
    id: palette

    // ── DARK THEME ─────────────────────────────────────────────────────
    readonly property QtObject darkTheme: QtObject {
        readonly property color background:       "#0f0f1a"
        readonly property color surface:          "#16162e"  // cards, panels
        readonly property color surfaceAlt:       "#1a1a2e"  // secondary surface
        readonly property color surfaceDim:       "#12122a"  // input fields, darker surface
        readonly property color surfaceHover:     "#1f0d10"  // hover states on rows
        readonly property color border:           "#2d2d4a"
        readonly property color borderLight:      "#3a3a5c"

        readonly property color textPrimary:      "#e8e8f0"
        readonly property color textSecondary:    "#8888aa"
        readonly property color textTertiary:     "#555577"
        readonly property color textPlaceholder:  "#444466"

        readonly property color accent:           "#ab3d4c"
        readonly property color accentHover:      "#8a2e3b"   // darker hover state
        readonly property color accentDim:        "#6a1f28"

        readonly property color success:          "#3a8a50"
        readonly property color successLight:     "#5aaa70"
        readonly property color warning:          "#aa6600"
        readonly property color error:            "#aa1111"
        
        readonly property color buttonText:       "#ffffff"   // branco puro em dark mode
        readonly property color shadowColor:      "#000000"
    }

    // ── LIGHT THEME ────────────────────────────────────────────────────
    readonly property QtObject lightTheme: QtObject {
        readonly property color background:       "#e8e3d8"     // bege acentuado, notavelmente fora do branco
        readonly property color surface:          "#edeae0"     // cards - tom areia suave
        readonly property color surfaceAlt:       "#e0dcd0"     // secondary surface - mais escuro
        readonly property color surfaceDim:       "#ddd8cc"     // input fields, ainda mais escuro
        readonly property color surfaceHover:     "#d5d0c4"     // hover states on rows
        readonly property color border:           "#c2bcae"     // visible borders
        readonly property color borderLight:      "#cec8bb"     // light borders

        readonly property color textPrimary:      "#2a2a2a"
        readonly property color textSecondary:    "#7a7a88"
        readonly property color textTertiary:     "#a0a0b0"
        readonly property color textPlaceholder:  "#9a9aaa"

        readonly property color accent:           "#ab3d4c"     // keep warm accent
        readonly property color accentHover:      "#c04d5c"     // darker hover state
        readonly property color accentDim:        "#f0d0d5"

        readonly property color success:          "#2a7a3a"
        readonly property color successLight:     "#4a9a5a"
        readonly property color warning:          "#cc7700"
        readonly property color error:            "#cc2222"
        
        readonly property color buttonText:       "#e8e8f0"    // soft white/light text (not blinding)
        readonly property color shadowColor:      "#000000"
    }

    function getPalette(isDark) {
        return isDark ? darkTheme : lightTheme
    }
}
