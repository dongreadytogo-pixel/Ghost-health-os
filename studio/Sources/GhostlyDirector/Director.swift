import Foundation
import GhostlyCore
import GhostlyDomain
import GhostlySubtitles

/// Resolves parsed intents into a concrete editing configuration, applying
/// them in order on top of a base profile.
public struct Director: Sendable {
    public var parser: EditIntentParser

    public init(parser: EditIntentParser = EditIntentParser()) {
        self.parser = parser
    }

    public struct Plan: Sendable, Equatable {
        public var profile: PacingProfile
        public var wantsCaptions: Bool
        public var wantsMusicReplacement: Bool
        public var musicQuery: String?
        /// Clean the audio (rumble/hum/noise) before detection and editing.
        public var wantsAudioCleanup: Bool
        /// Intents recognized from the command, in application order.
        public var intents: [EditIntent]
    }

    /// Interprets a natural-language command. Throws when nothing was
    /// recognized so callers can route to an LLM instead of silently
    /// doing nothing.
    public func interpret(_ command: String,
                          base: PacingProfile = .profile(for: .vlog)) throws -> Plan {
        let intents = parser.parse(command)
        guard !intents.isEmpty else {
            throw StudioError.invalidInput(field: "command",
                reason: "no editing intent recognized in '\(command)'")
        }
        return resolve(intents, base: base)
    }

    public func resolve(_ intents: [EditIntent], base: PacingProfile) -> Plan {
        var profile = base
        var wantsCaptions = profile.captionStyleName != nil
        var wantsMusic = false
        var musicQuery: String?
        var wantsCleanup = false

        for intent in intents {
            switch intent {
            case .applyStyle(let style):
                profile = .profile(for: style)
                wantsCaptions = profile.captionStyleName != nil
            case .createDeliverable(let deliverable):
                switch deliverable {
                case .tiktok, .reel, .shorts:
                    profile = .profile(for: .tiktok)
                case .instagram:
                    profile = .profile(for: .tiktok)
                    profile.captionStyleName = CaptionStyle.instagram.name
                case .youtube:
                    profile = .profile(for: .vlog)
                }
                wantsCaptions = true
            case .adjustPacing(let direction):
                profile = profile.scaled(by: direction == .faster ? 0.7 : 1.4)
            case .generateCaptions(let styleName):
                profile.captionStyleName = styleName
                wantsCaptions = true
            case .removeSilence:
                profile.silenceRemoval = 1
            case .cutToBeat:
                profile.cutOnBeats = true
            case .replaceMusic(let query):
                wantsMusic = true
                musicQuery = query
            case .addTransitions(let name):
                profile.transitionName = name
                if profile.transitionDuration <= 0 { profile.transitionDuration = 1 }
            case .cleanAudio:
                wantsCleanup = true
            }
        }
        return Plan(profile: profile, wantsCaptions: wantsCaptions,
                    wantsMusicReplacement: wantsMusic, musicQuery: musicQuery,
                    wantsAudioCleanup: wantsCleanup,
                    intents: intents)
    }
}
