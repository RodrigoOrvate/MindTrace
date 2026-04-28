pragma Singleton
import QtQuick

QtObject {
    id: manager

    // ── STATE ──────────────────────────────────────────────────────────
    property bool isDarkMode: true
    property QtObject currentPalette: ColorPalette.darkTheme
    
    // ── SIGNALS ────────────────────────────────────────────────────────
    signal themeChanged()
    
    // ── THEME CHANGE WATCHER ───────────────────────────────────────────
    onIsDarkModeChanged: {
        updatePalette()
        themeChanged()
    }

    // ── Expose all colors as properties for binding ──────────────────
    // Use conditional expressions to ensure reactivity on isDarkMode changes
    readonly property color background:       isDarkMode ? ColorPalette.darkTheme.background : ColorPalette.lightTheme.background
    readonly property color surface:          isDarkMode ? ColorPalette.darkTheme.surface : ColorPalette.lightTheme.surface
    readonly property color surfaceAlt:       isDarkMode ? ColorPalette.darkTheme.surfaceAlt : ColorPalette.lightTheme.surfaceAlt
    readonly property color surfaceDim:       isDarkMode ? ColorPalette.darkTheme.surfaceDim : ColorPalette.lightTheme.surfaceDim
    readonly property color surfaceHover:     isDarkMode ? ColorPalette.darkTheme.surfaceHover : ColorPalette.lightTheme.surfaceHover
    readonly property color border:           isDarkMode ? ColorPalette.darkTheme.border : ColorPalette.lightTheme.border
    readonly property color borderLight:      isDarkMode ? ColorPalette.darkTheme.borderLight : ColorPalette.lightTheme.borderLight

    readonly property color textPrimary:      isDarkMode ? ColorPalette.darkTheme.textPrimary : ColorPalette.lightTheme.textPrimary
    readonly property color textSecondary:    isDarkMode ? ColorPalette.darkTheme.textSecondary : ColorPalette.lightTheme.textSecondary
    readonly property color textTertiary:     isDarkMode ? ColorPalette.darkTheme.textTertiary : ColorPalette.lightTheme.textTertiary
    readonly property color textPlaceholder:  isDarkMode ? ColorPalette.darkTheme.textPlaceholder : ColorPalette.lightTheme.textPlaceholder

    readonly property color accent:           isDarkMode ? ColorPalette.darkTheme.accent : ColorPalette.lightTheme.accent
    readonly property color accentHover:      isDarkMode ? ColorPalette.darkTheme.accentHover : ColorPalette.lightTheme.accentHover
    readonly property color accentDim:        isDarkMode ? ColorPalette.darkTheme.accentDim : ColorPalette.lightTheme.accentDim

    readonly property color success:          isDarkMode ? ColorPalette.darkTheme.success : ColorPalette.lightTheme.success
    readonly property color successLight:     isDarkMode ? ColorPalette.darkTheme.successLight : ColorPalette.lightTheme.successLight
    readonly property color warning:          isDarkMode ? ColorPalette.darkTheme.warning : ColorPalette.lightTheme.warning
    readonly property color error:            isDarkMode ? ColorPalette.darkTheme.error : ColorPalette.lightTheme.error
    
    readonly property color buttonText:       isDarkMode ? ColorPalette.darkTheme.buttonText : ColorPalette.lightTheme.buttonText

    readonly property color shadowColor:      isDarkMode ? ColorPalette.darkTheme.shadowColor : ColorPalette.lightTheme.shadowColor

    // ── FILE I/O for persistence ───────────────────────────────────
    function saveThemePreference(isDark) {
        // Calls C++ backend to save to JSON
        if (typeof ThemeSettings !== 'undefined') {
            ThemeSettings.saveSetting("isDarkMode", isDark)
        }
    }

    function loadThemePreference() {
        // Calls C++ backend to load from JSON
        if (typeof ThemeSettings !== 'undefined') {
            let saved = ThemeSettings.loadSetting("isDarkMode")
            if (saved !== null && saved !== undefined) {
                manager.isDarkMode = saved === "true" || saved === true
            }
        }
    }

    // ── THEME TOGGLE ──────────────────────────────────────────────────
    function toggleTheme() {
        manager.isDarkMode = !manager.isDarkMode
        manager.saveThemePreference(manager.isDarkMode)
    }

    function setTheme(isDark) {
        if (manager.isDarkMode !== isDark) {
            manager.isDarkMode = isDark
            manager.saveThemePreference(isDark)
        }
    }

    // ── INTERNAL ───────────────────────────────────────────────────────
    function updatePalette() {
        manager.currentPalette = ColorPalette.getPalette(manager.isDarkMode)
    }

    // ── INITIALIZATION ─────────────────────────────────────────────────
    Component.onCompleted: {
        // Does not load saved preference — dark mode is always the default.
        // To enable persistence in future, re-enable loadThemePreference() here.
        manager.updatePalette()
    }
}
