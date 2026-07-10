import Foundation

/// Dictionary-free Thai break-opportunity segmentation. Thai writes without
/// spaces, so naive wrapping cuts mid-word; true word segmentation needs a
/// dictionary, but Thai orthography makes *syllable* boundaries largely
/// recoverable from character classes alone. Wrapping at these boundaries
/// keeps caption lines readable (never a dangling vowel or a split syllable)
/// while staying deterministic across platforms — no ICU, no dictionary.
///
/// Heuristics (on extended grapheme clusters):
/// - Leading vowels เ แ โ ใ ไ start a syllable and bind to what follows.
/// - Clusters carrying combining marks (◌ั ◌ี ◌ุ … tones) start a syllable.
/// - A bare consonant followed by ะ า ๅ starts a syllable (onset + vowel).
/// - ะ า ๅ ๆ ฯ ์ never start a line; they bind to the previous cluster.
/// - Consecutive non-Thai characters (digits, Latin) travel as one unit.
public enum ThaiSegmentation {
    /// True when the text contains at least one Thai code point.
    public static func containsThai(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x0E00...0x0E7F).contains($0.value) }
    }

    /// Splits text into indivisible units; line breaks are legal *between*
    /// units and nowhere else. Joining the units reproduces the text exactly.
    public static func breakUnits(_ text: String) -> [String] {
        let clusters = Array(text)
        guard clusters.count > 1 else { return clusters.map(String.init) }

        var units: [String] = []
        var current = ""
        for (index, cluster) in clusters.enumerated() {
            let next = index + 1 < clusters.count ? clusters[index + 1] : nil
            let previous = index > 0 ? clusters[index - 1] : nil
            if !current.isEmpty, startsUnit(cluster, previous: previous, next: next) {
                units.append(current)
                current = ""
            }
            current.append(cluster)
        }
        if !current.isEmpty { units.append(current) }
        return units
    }

    // MARK: Character classes

    /// เ แ โ ใ ไ — written before the consonant they belong to.
    private static func isLeadingVowel(_ c: Character) -> Bool {
        guard let v = c.unicodeScalars.first?.value else { return false }
        return (0x0E40...0x0E44).contains(v)
    }

    /// ะ า ๅ ๆ ฯ (spacing signs that end a syllable) — never line-initial.
    private static func bindsToPrevious(_ c: Character) -> Bool {
        guard let v = c.unicodeScalars.first?.value else { return false }
        return v == 0x0E30 || v == 0x0E32 || v == 0x0E45 // ะ า ๅ
            || v == 0x0E46 || v == 0x0E2F               // ๆ ฯ
    }

    private static func isThai(_ c: Character) -> Bool {
        guard let v = c.unicodeScalars.first?.value else { return false }
        return (0x0E00...0x0E7F).contains(v)
    }

    /// A Thai cluster whose consonant carries a dependent vowel or tone mark
    /// (◌ั ◌ิ ◌ี … ◌่ ◌้), i.e. the visible start of a written syllable.
    private static func carriesMark(_ c: Character) -> Bool {
        isThai(c) && c.unicodeScalars.count > 1
    }

    private static func startsUnit(_ c: Character, previous: Character?, next: Character?) -> Bool {
        // Script-run boundary: Thai ↔ non-Thai always breaks; inside a
        // non-Thai run (digits, Latin) nothing breaks.
        guard isThai(c) else { return previous.map(isThai) ?? true }
        if let previous, !isThai(previous) { return true }

        if bindsToPrevious(c) { return false }
        if let previous, isLeadingVowel(previous) { return false }
        if isLeadingVowel(c) { return true }
        if carriesMark(c) { return true }
        // Bare consonant opening an onset+vowel pair (e.g. กา, มะ).
        if let next, bindsToPrevious(next), !carriesMark(c) { return true }
        return false
    }
}
