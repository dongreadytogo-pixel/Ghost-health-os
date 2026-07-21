import Foundation
import GhostlyCore

/// Visual style for rendered/animated captions. Platform presets encode the
/// current conventions of each destination so "make TikTok captions" is one
/// call, while every field stays user-overridable.
public struct CaptionStyle: Hashable, Sendable, Codable {
    public var name: String
    public var fontName: String
    public var fontSize: Double
    /// RGBA 0…1.
    public var fontColor: ColorValue
    public var strokeColor: ColorValue?
    public var strokeWidth: Double
    public var backgroundColor: ColorValue?
    public var cornerRadius: Double
    public var allCaps: Bool
    public var maxCharactersPerLine: Int
    public var position: VerticalPosition
    public var animation: Animation
    /// Highlight color for the currently spoken word (karaoke mode).
    public var activeWordColor: ColorValue?

    public struct ColorValue: Hashable, Sendable, Codable {
        public var red: Double
        public var green: Double
        public var blue: Double
        public var alpha: Double

        public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
            self.red = min(max(red, 0), 1)
            self.green = min(max(green, 0), 1)
            self.blue = min(max(blue, 0), 1)
            self.alpha = min(max(alpha, 0), 1)
        }

        public static let white = ColorValue(red: 1, green: 1, blue: 1)
        public static let black = ColorValue(red: 0, green: 0, blue: 0)
        public static let yellow = ColorValue(red: 1, green: 0.92, blue: 0.23)
        public static let tiktokCyan = ColorValue(red: 0.15, green: 0.96, blue: 0.93)

        /// FCPXML color string: "r g b a".
        public var fcpxml: String {
            [red, green, blue, alpha].map { String(format: "%.4g", $0) }.joined(separator: " ")
        }
    }

    public enum VerticalPosition: String, Sendable, Codable, CaseIterable {
        case top, middle, lowerThird, bottom
    }

    public enum Animation: String, Sendable, Codable, CaseIterable {
        case none
        case popIn
        case karaoke      // word-by-word highlight
        case typewriter   // word-by-word reveal
        case slideUp
    }

    public init(name: String, fontName: String, fontSize: Double,
                fontColor: ColorValue = .white, strokeColor: ColorValue? = nil,
                strokeWidth: Double = 0, backgroundColor: ColorValue? = nil,
                cornerRadius: Double = 0, allCaps: Bool = false,
                maxCharactersPerLine: Int = 42, position: VerticalPosition = .bottom,
                animation: Animation = .none, activeWordColor: ColorValue? = nil) {
        self.name = name
        self.fontName = fontName
        self.fontSize = fontSize
        self.fontColor = fontColor
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
        self.backgroundColor = backgroundColor
        self.cornerRadius = cornerRadius
        self.allCaps = allCaps
        self.maxCharactersPerLine = maxCharactersPerLine
        self.position = position
        self.animation = animation
        self.activeWordColor = activeWordColor
    }

    // MARK: Platform presets

    /// Bold, center-screen, karaoke-highlighted short captions.
    public static let tiktok = CaptionStyle(
        name: "TikTok", fontName: "Proxima Nova Semibold", fontSize: 90,
        fontColor: .white, strokeColor: .black, strokeWidth: 4,
        allCaps: true, maxCharactersPerLine: 18, position: .middle,
        animation: .karaoke, activeWordColor: .tiktokCyan)

    /// Classic readable bottom captions with a translucent backing box.
    public static let youtube = CaptionStyle(
        name: "YouTube", fontName: "Roboto Medium", fontSize: 64,
        fontColor: .white,
        backgroundColor: ColorValue(red: 0, green: 0, blue: 0, alpha: 0.75),
        cornerRadius: 8, maxCharactersPerLine: 42, position: .bottom,
        animation: .none)

    /// Chunky pop-in captions in the lower third.
    public static let instagram = CaptionStyle(
        name: "Instagram", fontName: "Helvetica Neue Bold", fontSize: 76,
        fontColor: .white, backgroundColor: ColorValue(red: 0, green: 0, blue: 0, alpha: 0.6),
        cornerRadius: 12, allCaps: false, maxCharactersPerLine: 24,
        position: .lowerThird, animation: .popIn)

    /// Neutral broadcast style.
    public static let broadcast = CaptionStyle(
        name: "Broadcast", fontName: ".AppleSystemUIFont", fontSize: 63,
        fontColor: .white, backgroundColor: ColorValue(red: 0, green: 0, blue: 0, alpha: 0.7),
        maxCharactersPerLine: 37, position: .bottom, animation: .none)

    public static let builtIn: [CaptionStyle] = [.tiktok, .youtube, .instagram, .broadcast]

    public static func named(_ name: String) -> CaptionStyle? {
        builtIn.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Applies this style's text transformations to a track (case, wrapping).
    public func styled(_ track: SubtitleTrack) -> SubtitleTrack {
        var wrapped = track.wrapped(maxCharactersPerLine: maxCharactersPerLine)
        guard allCaps else { return wrapped }
        wrapped.cues = wrapped.cues.map { cue in
            var c = cue
            c.text = cue.text.uppercased()
            c.words = cue.words.map { word in
                var w = word
                w.text = word.text.uppercased()
                return w
            }
            return c
        }
        return wrapped
    }
}
