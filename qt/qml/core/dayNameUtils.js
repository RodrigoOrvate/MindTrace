// qml/core/dayNameUtils.js
// Normalizes day-chip names: E+digit codes → ALL CAPS, 2-letter codes → ALL CAPS,
// everything else → first letter capitalized. No fuzzy matching.
.pragma library

function normalizeDayName(raw) {
    var s = raw.trim()
    if (s.length === 0) return s

    // E + digit(s) → uppercase (E1, E2, E10…)
    if (/^[Ee]\d+$/.test(s)) return s.toUpperCase()

    // Exactly 2 alphabetic chars → uppercase code (TR, RA, TT…)
    if (/^[A-Za-z]{2}$/.test(s)) return s.toUpperCase()

    // Default: capitalize first letter only
    return s.charAt(0).toUpperCase() + s.slice(1)
}
