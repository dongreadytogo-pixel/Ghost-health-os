import Foundation

/// Reads Arabic/Thai numerals aloud in Thai — e.g. `150 → "หนึ่งร้อยห้าสิบ"`,
/// `21 → "ยี่สิบเอ็ด"`. Useful for normalizing captions/voiceover text so
/// numbers are spoken naturally. Pure and deterministic.
public enum ThaiNumber {
    private static let digitWords = ["ศูนย์", "หนึ่ง", "สอง", "สาม", "สี่",
                                     "ห้า", "หก", "เจ็ด", "แปด", "เก้า"]
    /// Place suffixes for positions 0…5 within a below-million group.
    private static let places = ["", "สิบ", "ร้อย", "พัน", "หมื่น", "แสน"]

    /// Spells a non-negative integer in Thai. Negative values are prefixed
    /// with "ลบ".
    public static func spell(_ number: Int) -> String {
        if number == 0 { return "ศูนย์" }
        if number < 0 { return "ลบ" + spell(-number) }

        // Split into groups of six digits; each group is followed by one
        // "ล้าน" per power of a million.
        var groups: [Int] = []
        var n = number
        while n > 0 {
            groups.append(n % 1_000_000)
            n /= 1_000_000
        }
        var parts: [String] = []
        for index in stride(from: groups.count - 1, through: 0, by: -1) {
            let group = groups[index]
            guard group != 0 else { continue }
            parts.append(spellGroup(group))
            parts.append(String(repeating: "ล้าน", count: index))
        }
        return parts.joined()
    }

    /// Spells 0 < n < 1,000,000 with the Thai place rules (เอ็ด / ยี่สิบ / สิบ).
    private static func spellGroup(_ n: Int) -> String {
        let s = Array(String(n))
        let len = s.count
        var out = ""
        for (idx, ch) in s.enumerated() {
            guard let d = ch.wholeNumberValue else { continue }
            let place = len - idx - 1
            if d == 0 { continue }
            if place == 0 && d == 1 && len > 1 {
                out += "เอ็ด"                       // ...1 after a higher digit
            } else if place == 1 && d == 1 {
                out += "สิบ"                        // 10s: no "หนึ่ง"
            } else if place == 1 && d == 2 {
                out += "ยี่สิบ"                      // 20s
            } else {
                out += digitWords[d] + places[place]
            }
        }
        return out
    }

    /// Replaces every numeric run in the text with its Thai spoken form.
    /// Integers become full readings; decimals read the integer part, then
    /// "จุด", then each fractional digit individually (e.g. 3.5 → "สามจุดห้า").
    /// Thai digits (๐–๙) are recognized as well as Arabic ones.
    public static func verbalize(_ text: String) -> String {
        let scalars = Array(text)
        var out = ""
        var i = 0
        while i < scalars.count {
            guard digitValue(scalars[i]) != nil else {
                out.append(scalars[i]); i += 1; continue
            }
            // Consume the integer part.
            var intDigits = ""
            while i < scalars.count, let d = digitValue(scalars[i]) {
                intDigits.append(Character(String(d))); i += 1
            }
            // Optional single decimal point followed by digits.
            var fracDigits = ""
            if i + 1 < scalars.count, scalars[i] == ".", digitValue(scalars[i + 1]) != nil {
                i += 1
                while i < scalars.count, let d = digitValue(scalars[i]) {
                    fracDigits.append(Character(String(d))); i += 1
                }
            }
            out += spell(Int(intDigits) ?? 0)
            if !fracDigits.isEmpty {
                out += "จุด"
                for ch in fracDigits {
                    if let d = ch.wholeNumberValue { out += digitWords[d] }
                }
            }
        }
        return out
    }

    /// Maps an Arabic (0–9) or Thai (๐–๙) digit character to its value.
    private static func digitValue(_ ch: Character) -> Int? {
        if let v = ch.wholeNumberValue, (0...9).contains(v),
           ch.isNumber, ch.unicodeScalars.count == 1 {
            let scalar = ch.unicodeScalars.first!.value
            if (0x30...0x39).contains(scalar) || (0x0E50...0x0E59).contains(scalar) {
                return v
            }
        }
        return nil
    }
}
