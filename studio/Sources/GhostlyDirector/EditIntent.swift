import Foundation
import GhostlyCore
import GhostlySubtitles

/// A structured editing command, the contract between natural language and
/// the planning engine. The deterministic parser below handles the studio's
/// command vocabulary offline; an LLM adapter can translate free-form
/// language into the same `EditIntent` values.
public enum EditIntent: Equatable, Sendable {
    /// Re-edit with a named style ("edit this like Marvel").
    case applyStyle(PacingProfile.Style)
    /// Produce a platform deliverable ("create a TikTok").
    case createDeliverable(Deliverable)
    /// Adjust pacing relative to current ("make it faster").
    case adjustPacing(direction: PacingAdjustment)
    /// Generate captions in a given style.
    case generateCaptions(styleName: String)
    /// Remove silent passages.
    case removeSilence
    /// Align cuts to the music beat.
    case cutToBeat
    /// Replace/lay in background music.
    case replaceMusic(query: String?)
    /// Add a transition style between all storyline cuts.
    case addTransitions(name: String)
    /// Clean the audio before editing (rumble/hum/noise-floor removal).
    case cleanAudio
    /// Cap the finished edit's length ("ความยาวเหลือไม่เกิน 3 นาที").
    case limitDuration(seconds: Double)
    /// Keep the most interesting sentences when trimming
    /// ("เน้นประโยคสำคัญที่น่าสนใจ").
    case emphasizeHighlights

    public enum Deliverable: String, Equatable, Sendable, CaseIterable {
        case tiktok, youtube, instagram, shorts, reel
    }

    public enum PacingAdjustment: String, Equatable, Sendable {
        case faster, slower
    }
}

/// Deterministic natural-language → `EditIntent` parser.
public struct EditIntentParser: Sendable {
    public init() {}

    /// Parses a user command into one or more intents. Returns an empty
    /// array when nothing in the vocabulary matches (callers may then fall
    /// back to an LLM).
    public func parse(_ command: String) -> [EditIntent] {
        let lowered = command.lowercased()
        var intents: [EditIntent] = []

        // A style applies when the user compares to it ("like marvel",
        // "marvel style"), not on any bare mention ("add tiktok captions"
        // must not restyle the whole edit).
        for style in PacingProfile.Style.allCases {
            let name = style.rawValue.lowercased()
            let patterns = ["like \(name)", "like a \(name)", "like the \(name)",
                            "\(name) style", "as a \(name)", "in \(name) fashion"]
            if patterns.contains(where: lowered.contains) {
                intents.append(.applyStyle(style))
            }
        }

        // Deliverables require a creation verb so "upload to youtube" or
        // "youtube captions" don't spawn a new deliverable.
        let creationVerbs = ["create", "make a", "make me", "make this into",
                             "turn this into", "turn it into", "produce", "generate", "cut a"]
        if creationVerbs.contains(where: lowered.contains) {
            for deliverable in EditIntent.Deliverable.allCases
            where lowered.contains(deliverable.rawValue) {
                intents.append(.createDeliverable(deliverable))
            }
        }

        if containsAny(lowered, ["faster", "quicker", "speed up", "snappier", "tighter"]),
           containsAny(lowered, ["pacing", "pace", "cut", "edit", "it", "this"]) {
            intents.append(.adjustPacing(direction: .faster))
        } else if containsAny(lowered, ["slower", "slow down", "breathe", "relaxed"]) {
            intents.append(.adjustPacing(direction: .slower))
        }

        if containsAny(lowered, ["caption", "subtitle"]) {
            let style = CaptionStyle.builtIn.first {
                lowered.contains($0.name.lowercased())
            } ?? .broadcast
            intents.append(.generateCaptions(styleName: style.name))
        }

        if containsAny(lowered, ["remove silence", "cut silence", "remove the silence",
                                 "cut out silence", "trim silence", "remove pauses", "cut dead air"]) {
            intents.append(.removeSilence)
        }

        if containsAny(lowered, ["to the beat", "on the beat", "beat sync", "cut to beat",
                                 "sync to music", "beat-match"]) {
            intents.append(.cutToBeat)
        }

        if containsAny(lowered, ["replace background music", "replace music", "replace the music",
                                 "new music", "change the music", "swap the music", "different music"]) {
            intents.append(.replaceMusic(query: musicQuery(in: lowered)))
        }

        if containsAny(lowered, ["cross dissolve", "crossfade", "dissolve between"]) {
            intents.append(.addTransitions(name: "Cross Dissolve"))
        }

        if containsAny(lowered, ["clean audio", "clean up the audio", "clean the audio",
                                 "remove noise", "reduce noise", "denoise",
                                 "remove background noise", "remove hum", "fix the audio"]) {
            intents.append(.cleanAudio)
        }

        if containsAny(lowered, ["best moments", "best parts", "most interesting",
                                 "key sentences", "keep the highlights", "only the highlights"]) {
            intents.append(.emphasizeHighlights)
        }

        if let seconds = durationLimit(in: lowered) {
            intents.append(.limitDuration(seconds: seconds))
        }

        intents.append(contentsOf: thaiIntents(in: lowered))
        return dedupe(intents)
    }

    /// Finds "ไม่เกิน 3 นาที" / "under 2 minutes" / "ภายใน 90 วินาที" …
    /// Returns the cap in seconds, or nil when the command sets no length.
    func durationLimit(in command: String) -> Double? {
        let limitWords = "ไม่เกิน|เหลือ|ภายใน|ให้เหลือ|ยาวสุด|under|within|max|maximum|at most|no more than|no longer than"
        let number = "[0-9]+(?:[.,][0-9]+)?|หนึ่ง|สอง|สาม|สี่|ห้า|หก|เจ็ด|แปด|เก้า|สิบ"
        let unit = "ชั่วโมง|ชม\\.?|นาที|วินาที|วิ|hours?|hrs?|minutes?|mins?|min|seconds?|secs?|sec"
        let pattern = "(?:\(limitWords))\\s*(\(number))\\s*(\(unit))"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: command,
                                           range: NSRange(command.startIndex..., in: command)),
              let numberRange = Range(match.range(at: 1), in: command),
              let unitRange = Range(match.range(at: 2), in: command) else { return nil }

        let thaiNumbers: [String: Double] = ["หนึ่ง": 1, "สอง": 2, "สาม": 3, "สี่": 4, "ห้า": 5,
                                             "หก": 6, "เจ็ด": 7, "แปด": 8, "เก้า": 9, "สิบ": 10]
        let numberText = String(command[numberRange]).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(numberText) ?? thaiNumbers[numberText], value > 0 else { return nil }

        let unitText = String(command[unitRange])
        let multiplier: Double
        if unitText.hasPrefix("ชั่วโมง") || unitText.hasPrefix("ชม")
            || unitText.hasPrefix("hour") || unitText.hasPrefix("hr") {
            multiplier = 3600
        } else if unitText.hasPrefix("นาที") || unitText.hasPrefix("min") {
            multiplier = 60
        } else {
            multiplier = 1
        }
        return value * multiplier
    }

    // MARK: Thai vocabulary (Thai-first per the Workflow Constitution)

    /// Understands natural Thai instructions — "ตัดช่วงเงียบออก",
    /// "ทำเป็นคลิป YouTube", "ใส่คำบรรยาย", "เร่งจังหวะ" — as first-class
    /// commands, not translations. Thai needs no lowercasing but mixed
    /// Thai-English commands arrive already lowercased.
    private func thaiIntents(in command: String) -> [EditIntent] {
        var intents: [EditIntent] = []

        // Styles: "แนวหนัง", "สไตล์สารคดี", "เหมือน marvel" …
        let thaiStyleWords: [(words: [String], style: PacingProfile.Style)] = [
            (["แบบหนัง", "เหมือนหนัง", "โทนหนัง", "แนวหนัง", "ให้ดูเป็นหนัง"], .cinematic),
            (["สารคดี"], .documentary),
            (["วล็อก", "วีล็อก", "บล็อกท่องเที่ยว"], .vlog),
            (["พอดแคสต์", "พอดคาสต์", "รายการพูดคุย"], .podcast),
        ]
        for (words, style) in thaiStyleWords where containsAny(command, words) {
            intents.append(.applyStyle(style))
        }
        if containsAny(command, ["สไตล์", "แนว", "เหมือน", "แบบ"]) {
            for style in PacingProfile.Style.allCases {
                let name = style.rawValue.lowercased()
                if ["สไตล์ \(name)", "สไตล์\(name)", "แนว \(name)", "แนว\(name)",
                    "เหมือน \(name)", "เหมือน\(name)", "แบบ \(name)", "แบบ\(name)"]
                    .contains(where: command.contains) {
                    intents.append(.applyStyle(style))
                }
            }
        }

        // Deliverables: Thai creation verbs + Thai or English platform names.
        let thaiCreationVerbs = ["ทำเป็น", "ทำคลิป", "สร้างคลิป", "ตัดเป็น",
                                 "ทำให้เป็น", "เอาไปลง", "ตัดคลิป", "ทำวิดีโอ"]
        if containsAny(command, thaiCreationVerbs) {
            let platformNames: [(words: [String], deliverable: EditIntent.Deliverable)] = [
                (["ติ๊กต๊อก", "ติ๊กตอก", "tiktok"], .tiktok),
                (["ยูทูบ", "ยูทูป", "youtube"], .youtube),
                (["ชอร์ตส์", "ชอร์ต", "shorts"], .shorts),
                (["รีล", "reel"], .reel),
                (["ไอจี", "อินสตาแกรม", "instagram"], .instagram),
            ]
            for (words, deliverable) in platformNames where containsAny(command, words) {
                intents.append(.createDeliverable(deliverable))
            }
        }

        // Pacing: "เร่งจังหวะ" / "ช้าลง".
        if containsAny(command, ["เร่งจังหวะ", "เร็วขึ้น", "ให้ไวขึ้น", "กระชับขึ้น",
                                 "ตัดให้ไว", "ให้กระชับ"]) {
            intents.append(.adjustPacing(direction: .faster))
        } else if containsAny(command, ["ช้าลง", "ผ่อนจังหวะ", "ให้ช้ากว่านี้", "ใจเย็นขึ้น"]) {
            intents.append(.adjustPacing(direction: .slower))
        }

        // Captions: "ใส่คำบรรยาย" / "ใส่ซับ" (+ Thai platform style names).
        if containsAny(command, ["คำบรรยาย", "ซับไตเติล", "ซับไตเติ้ล", "ใส่ซับ",
                                 "ทำซับ", "มีซับ", "พร้อมซับ", "แคปชั่น", "แคปชัน"]) {
            let style: CaptionStyle
            if containsAny(command, ["ติ๊กต๊อก", "ติ๊กตอก"]) {
                style = .tiktok
            } else if containsAny(command, ["ยูทูบ", "ยูทูป"]) {
                style = .youtube
            } else if containsAny(command, ["ไอจี", "อินสตาแกรม"]) {
                style = .instagram
            } else {
                style = CaptionStyle.builtIn.first { command.contains($0.name.lowercased()) }
                    ?? .broadcast
            }
            intents.append(.generateCaptions(styleName: style.name))
        }

        // Silence removal: "ตัดช่วงเงียบออก" — and the everyday editor
        // phrasing "คัตเสียงคลิปนี้" (cut/tighten the talk track).
        // "ตัดเสียง" alone counts too, but "ตัดเสียงรบกวน" is audio cleanup.
        if containsAny(command, ["ตัดช่วงเงียบ", "ตัดเงียบ", "ลบช่วงเงียบ",
                                 "เอาช่วงเงียบออก", "ตัดช่วงที่ไม่พูด", "ตัดช่วงว่าง",
                                 "คัตเสียง", "คัทเสียง"])
            || (command.contains("ตัดเสียง") && !command.contains("ตัดเสียงรบกวน")) {
            intents.append(.removeSilence)
        }

        // Highlight emphasis: "เน้นประโยคสำคัญที่น่าสนใจ", "เอาเฉพาะช่วงเด่น".
        if containsAny(command, ["เน้นประโยคสำคัญ", "ประโยคที่น่าสนใจ", "ประโยคสำคัญ",
                                 "เน้นช่วงสำคัญ", "ช่วงที่น่าสนใจ", "เฉพาะช่วงเด่น",
                                 "เน้นจุดสำคัญ", "ไฮไลต์", "ไฮไลท์", "ช่วงเด็ด"]) {
            intents.append(.emphasizeHighlights)
        }

        // Beat cutting: "ตัดตามจังหวะเพลง".
        if containsAny(command, ["ตัดตามจังหวะ", "ตามจังหวะเพลง", "ตัดตามบีต",
                                 "เข้าจังหวะเพลง", "ตัดเข้าเพลง"]) {
            intents.append(.cutToBeat)
        }

        // Music: "เปลี่ยนเพลง" / "ใส่เพลงประกอบ".
        if containsAny(command, ["เปลี่ยนเพลง", "เพลงใหม่", "ใส่เพลงประกอบ",
                                 "เปลี่ยนดนตรี", "เปลี่ยนเสียงเพลง"]) {
            intents.append(.replaceMusic(query: nil))
        }

        // Transitions: "ใส่ทรานสิชั่น".
        if containsAny(command, ["ทรานสิชั่น", "ทรานซิชัน", "ครอสดิสโซลฟ์", "เฟดภาพ"]) {
            intents.append(.addTransitions(name: "Cross Dissolve"))
        }

        // Audio cleanup: "ลดเสียงรบกวน".
        if containsAny(command, ["ลดเสียงรบกวน", "ตัดเสียงรบกวน", "เอาเสียงรบกวนออก",
                                 "แก้เสียงฮัม", "ลบเสียงซ่า", "เสียงให้สะอาด"]) {
            intents.append(.cleanAudio)
        }

        return intents
    }

    private func containsAny(_ haystack: String, _ needles: [String]) -> Bool {
        needles.contains { haystack.contains($0) }
    }

    /// Extracts a descriptor after "music" phrases: "replace music with epic rock" → "epic rock".
    private func musicQuery(in command: String) -> String? {
        guard let range = command.range(of: "music with ") else { return nil }
        let query = command[range.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))
        return query.isEmpty ? nil : query
    }

    private func dedupe(_ intents: [EditIntent]) -> [EditIntent] {
        var seen: [EditIntent] = []
        for intent in intents where !seen.contains(intent) {
            seen.append(intent)
        }
        return seen
    }
}
