// qml/core/dayNameUtils.js
// Normalizes day-chip names entered by the user:
//   - Short 2-letter codes (TR, RA, TT) and E+number codes (E1, E2…) → ALL CAPS
//   - Known name typos within edit-distance 2 → corrected canonical form
//   - Everything else → first letter capitalized
.pragma library

function _levenshtein(a, b) {
    var m = a.length, n = b.length
    var prev = [], curr = []
    var j
    for (j = 0; j <= n; j++) prev[j] = j
    for (var i = 1; i <= m; i++) {
        curr[0] = i
        for (j = 1; j <= n; j++) {
            if (a[i-1] === b[j-1])
                curr[j] = prev[j-1]
            else
                curr[j] = 1 + Math.min(prev[j-1], prev[j], curr[j-1])
        }
        var tmp = prev; prev = curr; curr = tmp
    }
    return prev[n]
}

var _canonical = ["Treino", "Teste", "Reativação", "Extinção"]

function normalizeDayName(raw) {
    var s = raw.trim()
    if (s.length === 0) return s

    // E + digit(s) → uppercase (E1, E2, E10…)
    if (/^[Ee]\d+$/.test(s)) return s.toUpperCase()

    // Exactly 2 alphabetic chars → uppercase code (TR, RA, TT…)
    if (/^[A-Za-z]{2}$/.test(s)) return s.toUpperCase()

    // Fuzzy match against canonical names (max edit-distance 2)
    var lc = s.toLowerCase()
    var bestMatch = null, bestDist = 3
    for (var i = 0; i < _canonical.length; i++) {
        var d = _levenshtein(lc, _canonical[i].toLowerCase())
        if (d < bestDist) { bestDist = d; bestMatch = _canonical[i] }
    }
    if (bestMatch !== null) return bestMatch

    // Default: capitalize first letter only
    return s.charAt(0).toUpperCase() + s.slice(1)
}
