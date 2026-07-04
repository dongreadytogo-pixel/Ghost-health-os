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

        return dedupe(intents)
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
