import Foundation

/// Scores how content-important a spoken Thai sentence is (0…1) — the
/// signal behind "เน้นประโยคสำคัญ" when a transcript exists: benefit and
/// conclusion words, numbers, and emphasis all mark the sentences an
/// interview cut should keep. Deterministic keyword heuristics, no model.
public enum ThaiImportance {
    /// Strong markers: results, conclusions, warnings, benefits.
    static let strongWords = ["หายขาด", "ดีขึ้น", "สำคัญ", "ที่สุด", "สรุป", "เคล็ดลับ",
                              "สาเหตุ", "วิธี", "ผลลัพธ์", "ระวัง", "ห้าม", "แนะนำ",
                              "จำเป็น", "ปลอดภัย", "อันตราย", "คุ้ม", "พิเศษ", "ได้ผล",
                              "เปลี่ยนชีวิต", "ประทับใจ", "แข็งแรง", "หมดไป", "ไม่ปวด"]
    /// Weak markers: causal connectives and intensity.
    static let weakWords = ["เพราะ", "ดังนั้น", "เพราะฉะนั้น", "ปัญหา", "ช่วย", "ต้อง",
                            "มาก", "จริงๆ", "จริง ๆ", "ครั้งแรก", "อยาก", "รู้สึก",
                            "ก่อนหน้านี้", "ตอนนี้", "สุดท้าย"]

    /// 0 = filler, 1 = highly important. Multiple markers stack.
    public static func score(_ text: String) -> Double {
        guard !text.isEmpty else { return 0 }
        var score = 0.0
        for word in strongWords where text.contains(word) { score += 0.35 }
        for word in weakWords where text.contains(word) { score += 0.12 }
        if text.rangeOfCharacter(from: .decimalDigits) != nil { score += 0.2 }
        if text.contains("!") || text.contains("?") { score += 0.15 }
        return min(1, score)
    }
}
