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
    /// Cap on the finished edit's length in seconds (nil = no cap) —
    /// "ความยาวเหลือไม่เกิน 3 นาที". The planner keeps the highest-scoring
    /// segments that fit.
    public var maxTotalDuration: Double?
    /// Prefer the most interesting sentences when trimming
    /// ("เน้นประโยคสำคัญที่น่าสนใจ") — boosts transcript emphasis in scoring.
    public var emphasizeHighlights: Bool

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
                captionStyleName: String?, format: VideoFormat, silenceRemoval: Double,
                maxTotalDuration: Double? = nil, emphasizeHighlights: Bool = false) {
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
        self.maxTotalDuration = maxTotalDuration
        self.emphasizeHighlights = emphasizeHighlights
    }

    // Tolerant decoding: profiles serialized before these fields existed
    // (learning-system exports, saved plans) must keep loading.
    private enum CodingKeys: String, CodingKey {
        case style, minShotLength, maxShotLength, cutOnBeats, transitionName,
             transitionDuration, captionStyleName, format, silenceRemoval,
             maxTotalDuration, emphasizeHighlights
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.style = try c.decode(Style.self, forKey: .style)
        self.minShotLength = try c.decode(Double.self, forKey: .minShotLength)
        self.maxShotLength = try c.decode(Double.self, forKey: .maxShotLength)
        self.cutOnBeats = try c.decode(Bool.self, forKey: .cutOnBeats)
        self.transitionName = try c.decodeIfPresent(String.self, forKey: .transitionName)
        self.transitionDuration = try c.decode(Double.self, forKey: .transitionDuration)
        self.captionStyleName = try c.decodeIfPresent(String.self, forKey: .captionStyleName)
        self.format = try c.decode(VideoFormat.self, forKey: .format)
        self.silenceRemoval = try c.decode(Double.self, forKey: .silenceRemoval)
        self.maxTotalDuration = try c.decodeIfPresent(Double.self, forKey: .maxTotalDuration)
        self.emphasizeHighlights = try c.decodeIfPresent(Bool.self, forKey: .emphasizeHighlights) ?? false
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
