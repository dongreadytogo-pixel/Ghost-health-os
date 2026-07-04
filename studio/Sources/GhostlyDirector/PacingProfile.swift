import Foundation
import GhostlyCore
import GhostlyDomain
import GhostlySubtitles

/// Editing rhythm and delivery conventions for a target style. Profiles are
/// data, not code: users and the learning system can derive new ones.
public struct PacingProfile: Sendable, Codable, Equatable {
    public var style: Style
    /// Preferred shot length range (seconds).
    public var minShotLength: Double
    public var maxShotLength: Double
    /// Whether cuts snap to detected music beats.
    public var cutOnBeats: Bool
    /// Transition applied at cuts (nil = hard cut).
    public var transitionName: String?
    public var transitionDuration: Double
    public var captionStyleName: String?
    public var format: VideoFormat
    /// Fraction of detected silence to remove (1 = all of it).
    public var silenceRemoval: Double

    public enum Style: String, Sendable, Codable, CaseIterable {
        case marvel = "Marvel"
        case tiktok = "TikTok"
        case documentary = "Documentary"
        case vlog = "Vlog"
        case podcast = "Podcast"
        case cinematic = "Cinematic"
    }

    public init(style: Style, minShotLength: Double, maxShotLength: Double,
                cutOnBeats: Bool, transitionName: String?, transitionDuration: Double,
                captionStyleName: String?, format: VideoFormat, silenceRemoval: Double) {
        precondition(minShotLength > 0 && maxShotLength >= minShotLength,
                     "shot length range must be positive and ordered")
        self.style = style
        self.minShotLength = minShotLength
        self.maxShotLength = maxShotLength
        self.cutOnBeats = cutOnBeats
        self.transitionName = transitionName
        self.transitionDuration = transitionDuration
        self.captionStyleName = captionStyleName
        self.format = format
        self.silenceRemoval = min(max(silenceRemoval, 0), 1)
    }

    public static func profile(for style: Style) -> PacingProfile {
        switch style {
        case .marvel:
            // Blockbuster action rhythm: short shots, beat-driven, hard cuts.
            return PacingProfile(style: .marvel, minShotLength: 0.8, maxShotLength: 3.0,
                                 cutOnBeats: true, transitionName: nil, transitionDuration: 0,
                                 captionStyleName: nil, format: .hd1080p24, silenceRemoval: 1)
        case .tiktok:
            return PacingProfile(style: .tiktok, minShotLength: 0.6, maxShotLength: 2.5,
                                 cutOnBeats: true, transitionName: nil, transitionDuration: 0,
                                 captionStyleName: CaptionStyle.tiktok.name,
                                 format: .vertical1080x1920p30, silenceRemoval: 1)
        case .documentary:
            return PacingProfile(style: .documentary, minShotLength: 4, maxShotLength: 12,
                                 cutOnBeats: false, transitionName: "Cross Dissolve",
                                 transitionDuration: 1, captionStyleName: CaptionStyle.broadcast.name,
                                 format: .hd1080p25, silenceRemoval: 0.5)
        case .vlog:
            return PacingProfile(style: .vlog, minShotLength: 2, maxShotLength: 6,
                                 cutOnBeats: false, transitionName: nil, transitionDuration: 0,
                                 captionStyleName: CaptionStyle.youtube.name,
                                 format: .hd1080p30, silenceRemoval: 0.9)
        case .podcast:
            return PacingProfile(style: .podcast, minShotLength: 8, maxShotLength: 30,
                                 cutOnBeats: false, transitionName: nil, transitionDuration: 0,
                                 captionStyleName: CaptionStyle.youtube.name,
                                 format: .hd1080p30, silenceRemoval: 0.7)
        case .cinematic:
            return PacingProfile(style: .cinematic, minShotLength: 3, maxShotLength: 8,
                                 cutOnBeats: false, transitionName: "Cross Dissolve",
                                 transitionDuration: 1.5, captionStyleName: nil,
                                 format: .hd1080p24, silenceRemoval: 0.8)
        }
    }

    /// Returns a copy with shot lengths scaled — the implementation of
    /// "make the pacing faster/slower". Factor < 1 speeds up.
    public func scaled(by factor: Double) -> PacingProfile {
        precondition(factor > 0, "pacing factor must be positive")
        var copy = self
        copy.minShotLength = max(0.2, minShotLength * factor)
        copy.maxShotLength = max(copy.minShotLength, maxShotLength * factor)
        return copy
    }
}
