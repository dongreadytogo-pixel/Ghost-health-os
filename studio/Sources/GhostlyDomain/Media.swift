import Foundation
import GhostlyCore

/// Strongly-typed entity identifier, so an `AssetID` can never be passed
/// where a `ClipID` is expected.
public struct EntityID<Marker>: Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init() { self.rawValue = UUID().uuidString.lowercased() }

    public var description: String { rawValue }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum AssetIDMarker: Sendable {}
public enum ClipIDMarker: Sendable {}
public enum ProjectIDMarker: Sendable {}

public typealias AssetID = EntityID<AssetIDMarker>
public typealias ClipID = EntityID<ClipIDMarker>
public typealias ProjectID = EntityID<ProjectIDMarker>

/// Pixel dimensions + frame rate + color space of a video format.
public struct VideoFormat: Hashable, Sendable, Codable {
    public var width: Int
    public var height: Int
    public var frameRate: FrameRate
    public var colorSpace: ColorSpace

    public enum ColorSpace: String, Sendable, Codable, CaseIterable {
        case rec709 = "1-1-1 (Rec. 709)"
        case rec2020 = "9-9-9 (Rec. 2020)"
        case rec2020HLG = "9-18-9 (Rec. 2020 HLG)"
        case rec2020PQ = "9-16-9 (Rec. 2020 PQ)"
    }

    public init(width: Int, height: Int, frameRate: FrameRate, colorSpace: ColorSpace = .rec709) {
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.colorSpace = colorSpace
    }

    public static let uhd4K30 = VideoFormat(width: 3840, height: 2160, frameRate: .fps30)
    public static let hd1080p30 = VideoFormat(width: 1920, height: 1080, frameRate: .fps30)
    public static let hd1080p24 = VideoFormat(width: 1920, height: 1080, frameRate: .fps24)
    public static let hd1080p25 = VideoFormat(width: 1920, height: 1080, frameRate: .fps25)
    /// 9:16 vertical for TikTok / Reels / Shorts.
    public static let vertical1080x1920p30 = VideoFormat(width: 1080, height: 1920, frameRate: .fps30)

    public var isVertical: Bool { height > width }
    public var aspectRatio: Double { Double(width) / Double(height) }
}

/// A media file on disk that clips reference.
public struct Asset: Hashable, Sendable, Codable, Identifiable {
    public var id: AssetID
    public var name: String
    public var url: URL
    public var duration: RationalTime
    public var kind: Kind
    public var format: VideoFormat?
    public var tags: Set<String>
    public var favorite: Bool

    public enum Kind: String, Sendable, Codable, CaseIterable {
        case video, audio, image, title, generator
    }

    public init(id: AssetID = AssetID(), name: String, url: URL, duration: RationalTime,
                kind: Kind, format: VideoFormat? = nil, tags: Set<String> = [], favorite: Bool = false) {
        self.id = id
        self.name = name
        self.url = url
        self.duration = duration
        self.kind = kind
        self.format = format
        self.tags = tags
        self.favorite = favorite
    }

    /// Audio and stills have no intrinsic video format.
    public var hasVideo: Bool { kind == .video || kind == .image }
    public var hasAudio: Bool { kind == .video || kind == .audio }
}

/// FCP role, e.g. `dialogue`, `music.music-1`, `effects`.
public struct Role: Hashable, Sendable, Codable, CustomStringConvertible {
    public let name: String
    public let subrole: String?

    public init(_ name: String, subrole: String? = nil) {
        self.name = name
        self.subrole = subrole
    }

    public static let dialogue = Role("dialogue")
    public static let music = Role("music")
    public static let effects = Role("effects")
    public static let video = Role("video")
    public static let titles = Role("titles")

    public var description: String {
        if let subrole { return "\(name).\(subrole)" }
        return name
    }
}

/// Timeline annotation.
public struct Marker: Hashable, Sendable, Codable {
    public var start: RationalTime
    public var duration: RationalTime
    public var text: String
    public var kind: Kind

    public enum Kind: String, Sendable, Codable, CaseIterable {
        case standard, toDo, completed, chapter
    }

    public init(start: RationalTime, duration: RationalTime = RationalTime(value: 1, timescale: 30),
                text: String, kind: Kind = .standard) {
        self.start = start
        self.duration = duration
        self.text = text
        self.kind = kind
    }
}

/// Keyword range applied to a clip or asset.
public struct KeywordRange: Hashable, Sendable, Codable {
    public var range: TimeRange
    public var keywords: [String]

    public init(range: TimeRange, keywords: [String]) {
        self.range = range
        self.keywords = keywords
    }
}
