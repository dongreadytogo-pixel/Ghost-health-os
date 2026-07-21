import Foundation
import GhostlyCore
import GhostlyDomain

/// A complete render/export recipe: container, codecs, bitrate, and target
/// format. Platform presets encode each destination's current delivery specs
/// so "export for TikTok" is one call, while every field stays overridable.
public struct RenderPreset: Sendable, Codable, Equatable {
    public enum Container: String, Sendable, Codable, CaseIterable {
        case mp4, mov, webm
    }

    public enum VideoCodec: String, Sendable, Codable, CaseIterable {
        case h264, hevc, vp9, proRes422
    }

    public enum AudioCodec: String, Sendable, Codable, CaseIterable {
        case aac, opus, pcm
    }

    public var name: String
    public var container: Container
    public var videoCodec: VideoCodec
    public var audioCodec: AudioCodec
    public var format: VideoFormat
    /// Target video bitrate in kilobits/sec.
    public var videoBitrateKbps: Int
    /// Audio bitrate in kilobits/sec.
    public var audioBitrateKbps: Int
    /// CRF-style quality (lower = better) for codecs that support it; nil uses bitrate.
    public var quality: Int?

    public init(name: String, container: Container, videoCodec: VideoCodec,
                audioCodec: AudioCodec, format: VideoFormat,
                videoBitrateKbps: Int, audioBitrateKbps: Int = 192, quality: Int? = nil) {
        precondition(videoBitrateKbps > 0 && audioBitrateKbps > 0, "bitrates must be positive")
        self.name = name
        self.container = container
        self.videoCodec = videoCodec
        self.audioCodec = audioCodec
        self.format = format
        self.videoBitrateKbps = videoBitrateKbps
        self.audioBitrateKbps = audioBitrateKbps
        self.quality = quality
    }

    // MARK: Platform presets (per each platform's published delivery specs)

    public static let youtube1080p = RenderPreset(
        name: "YouTube 1080p", container: .mp4, videoCodec: .h264, audioCodec: .aac,
        format: .hd1080p30, videoBitrateKbps: 12_000, audioBitrateKbps: 384)

    public static let youtube4K = RenderPreset(
        name: "YouTube 4K", container: .mp4, videoCodec: .hevc, audioCodec: .aac,
        format: .uhd4K30, videoBitrateKbps: 45_000, audioBitrateKbps: 384)

    public static let tiktok = RenderPreset(
        name: "TikTok", container: .mp4, videoCodec: .h264, audioCodec: .aac,
        format: .vertical1080x1920p30, videoBitrateKbps: 8_000, audioBitrateKbps: 192)

    public static let instagramReel = RenderPreset(
        name: "Instagram Reel", container: .mp4, videoCodec: .h264, audioCodec: .aac,
        format: .vertical1080x1920p30, videoBitrateKbps: 9_000, audioBitrateKbps: 256)

    public static let instagramFeed = RenderPreset(
        name: "Instagram Feed", container: .mp4, videoCodec: .h264, audioCodec: .aac,
        format: VideoFormat(width: 1080, height: 1350, frameRate: .fps30),
        videoBitrateKbps: 8_000, audioBitrateKbps: 256)

    /// High-quality intermediate for re-editing / archival.
    public static let proResMaster = RenderPreset(
        name: "ProRes 422 Master", container: .mov, videoCodec: .proRes422, audioCodec: .pcm,
        format: .hd1080p30, videoBitrateKbps: 147_000, audioBitrateKbps: 1_536)

    public static let builtIn: [RenderPreset] = [
        .youtube1080p, .youtube4K, .tiktok, .instagramReel, .instagramFeed, .proResMaster,
    ]

    public static func named(_ name: String) -> RenderPreset? {
        builtIn.first {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
                || $0.name.replacingOccurrences(of: " ", with: "").caseInsensitiveCompare(name) == .orderedSame
        }
    }
}

/// Descriptive metadata embedded into the exported file.
public struct ExportMetadata: Sendable, Codable, Equatable {
    public var title: String?
    public var artist: String?
    public var comment: String?
    public var year: Int?

    public init(title: String? = nil, artist: String? = nil,
                comment: String? = nil, year: Int? = nil) {
        self.title = title
        self.artist = artist
        self.comment = comment
        self.year = year
    }

    public var isEmpty: Bool {
        title == nil && artist == nil && comment == nil && year == nil
    }
}
