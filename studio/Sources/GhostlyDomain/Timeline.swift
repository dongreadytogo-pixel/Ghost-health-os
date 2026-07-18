import Foundation
import GhostlyCore

/// A volume keyframe on a clip, in the clip's source-time coordinates.
public struct VolumeKeyframe: Hashable, Sendable, Codable {
    public var time: RationalTime
    /// Linear gain; 1 = unity.
    public var gain: Double

    public init(time: RationalTime, gain: Double) {
        self.time = time
        self.gain = gain
    }
}

/// A clip placed on a timeline: a window (`sourceRange`) into an asset,
/// positioned at `offset` on its lane.
public struct Clip: Hashable, Sendable, Codable, Identifiable {
    public var id: ClipID
    public var assetID: AssetID
    public var name: String
    /// Position of the clip's head on the timeline.
    public var offset: RationalTime
    /// The part of the source asset this clip plays.
    public var sourceRange: TimeRange
    /// 0 is the primary storyline; positive lanes stack above, negative below.
    public var lane: Int
    public var role: Role
    public var enabled: Bool
    public var volume: Double
    /// Volume automation (e.g. music ducking); when non-empty these override
    /// the flat `volume` in FCPXML output.
    public var volumeKeyframes: [VolumeKeyframe]
    public var markers: [Marker]
    public var keywords: [KeywordRange]
    /// Effect references (Motion template / built-in effect identifiers).
    public var effects: [EffectReference]

    public init(id: ClipID = ClipID(), assetID: AssetID, name: String,
                offset: RationalTime, sourceRange: TimeRange, lane: Int = 0,
                role: Role = .video, enabled: Bool = true, volume: Double = 1.0,
                volumeKeyframes: [VolumeKeyframe] = [],
                markers: [Marker] = [], keywords: [KeywordRange] = [],
                effects: [EffectReference] = []) {
        self.id = id
        self.assetID = assetID
        self.name = name
        self.offset = offset
        self.sourceRange = sourceRange
        self.lane = lane
        self.role = role
        self.enabled = enabled
        self.volume = volume
        self.volumeKeyframes = volumeKeyframes
        self.markers = markers
        self.keywords = keywords
        self.effects = effects
    }

    private enum CodingKeys: String, CodingKey {
        case id, assetID, name, offset, sourceRange, lane, role, enabled,
             volume, volumeKeyframes, markers, keywords, effects
    }

    /// Tolerant decode: `volumeKeyframes` is absent in documents written
    /// before volume automation existed.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(ClipID.self, forKey: .id)
        assetID = try c.decode(AssetID.self, forKey: .assetID)
        name = try c.decode(String.self, forKey: .name)
        offset = try c.decode(RationalTime.self, forKey: .offset)
        sourceRange = try c.decode(TimeRange.self, forKey: .sourceRange)
        lane = try c.decode(Int.self, forKey: .lane)
        role = try c.decode(Role.self, forKey: .role)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        volume = try c.decode(Double.self, forKey: .volume)
        volumeKeyframes = try c.decodeIfPresent([VolumeKeyframe].self,
                                                forKey: .volumeKeyframes) ?? []
        markers = try c.decode([Marker].self, forKey: .markers)
        keywords = try c.decode([KeywordRange].self, forKey: .keywords)
        effects = try c.decode([EffectReference].self, forKey: .effects)
    }

    public var duration: RationalTime { sourceRange.duration }
    /// The timeline interval this clip occupies.
    public var timelineRange: TimeRange { TimeRange(start: offset, duration: duration) }
}

/// A reference to a video/audio effect applied to a clip.
public struct EffectReference: Hashable, Sendable, Codable {
    public var name: String
    /// FCP effect UID or Motion template identifier.
    public var uid: String
    public var parameters: [String: EffectParameterValue]

    public init(name: String, uid: String, parameters: [String: EffectParameterValue] = [:]) {
        self.name = name
        self.uid = uid
        self.parameters = parameters
    }
}

public enum EffectParameterValue: Hashable, Sendable, Codable {
    case number(Double)
    case text(String)
    case boolean(Bool)
}

/// A transition between two adjacent storyline clips.
public struct Transition: Hashable, Sendable, Codable {
    public var name: String
    /// FCP transition UID (e.g. `FxPlug:...` or Motion template path).
    public var uid: String?
    /// Timeline position where the transition is centered.
    public var offset: RationalTime
    public var duration: RationalTime

    public init(name: String, uid: String? = nil, offset: RationalTime, duration: RationalTime) {
        self.name = name
        self.uid = uid
        self.offset = offset
        self.duration = duration
    }

    public static func crossDissolve(offset: RationalTime, duration: RationalTime) -> Transition {
        Transition(name: "Cross Dissolve",
                   uid: "FxPlug:4731E73A-8DAC-4113-9A30-AE85B1761265",
                   offset: offset, duration: duration)
    }
}

/// A caption on the timeline (FCP caption element, not a burned-in title).
public struct Caption: Hashable, Sendable, Codable {
    public var text: String
    public var range: TimeRange
    public var speaker: String?
    public var format: CaptionFormat
    public var styleName: String?
    /// BCP-47 language code (e.g. "en", "th"); drives the FCPXML caption role.
    public var language: String

    public enum CaptionFormat: String, Sendable, Codable, CaseIterable {
        case itt = "ITT"
        case cea608 = "CEA-608"
        case srt = "SRT"
    }

    public init(text: String, range: TimeRange, speaker: String? = nil,
                format: CaptionFormat = .itt, styleName: String? = nil,
                language: String = "en") {
        self.text = text
        self.range = range
        self.speaker = speaker
        self.format = format
        self.styleName = styleName
        self.language = language
    }

    private enum CodingKeys: String, CodingKey {
        case text, range, speaker, format, styleName, language
    }

    /// Custom decode so captions serialized before `language` existed still
    /// decode (defaulting to "en").
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decode(String.self, forKey: .text)
        range = try c.decode(TimeRange.self, forKey: .range)
        speaker = try c.decodeIfPresent(String.self, forKey: .speaker)
        format = try c.decodeIfPresent(CaptionFormat.self, forKey: .format) ?? .itt
        styleName = try c.decodeIfPresent(String.self, forKey: .styleName)
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? "en"
    }
}

/// A motion-graphics overlay backed by a Motion title template — lower
/// thirds, title cards, callouts, subscribe animations, and progress bars.
/// Rendered as an FCPXML `<title>` connected above the storyline.
public struct MotionTitle: Hashable, Sendable, Codable {
    public enum Kind: String, Sendable, Codable, CaseIterable {
        case lowerThird, titleCard, callout, subscribe, progressBar
        /// A subtitle cue rendered as a stylable Title overlay
        /// ("ซับแบบ Title") instead of / alongside a closed caption.
        case subtitle
    }

    public enum Position: String, Sendable, Codable, CaseIterable {
        case top, center, lowerThird, bottomLeft, bottomCenter
    }

    public var text: String
    public var range: TimeRange
    /// Connected lane (positive = above the storyline).
    public var lane: Int
    public var kind: Kind
    /// Motion template display name and its FCP resource UID.
    public var templateName: String
    public var templateUID: String
    public var fontName: String
    public var fontSize: Double
    public var position: Position

    public init(text: String, range: TimeRange, lane: Int = 1, kind: Kind = .lowerThird,
                templateName: String = "Basic Title",
                templateUID: String = ".../Titles.localized/Build In:Build Out.localized/Basic Title.localized/Basic Title.moti",
                fontName: String = "Helvetica Neue", fontSize: Double = 63,
                position: Position = .lowerThird) {
        self.text = text
        self.range = range
        self.lane = lane
        self.kind = kind
        self.templateName = templateName
        self.templateUID = templateUID
        self.fontName = fontName
        self.fontSize = fontSize
        self.position = position
    }
}

/// An editable sequence: ordered storyline clips plus connected lanes,
/// transitions, captions, titles and markers.
public struct Timeline: Sendable, Codable {
    public var name: String
    public var format: VideoFormat
    public var clips: [Clip]
    public var transitions: [Transition]
    public var captions: [Caption]
    public var markers: [Marker]
    /// Motion-graphics overlays. Defaulted so older serialized timelines decode.
    public var titles: [MotionTitle] = []

    public init(name: String, format: VideoFormat, clips: [Clip] = [],
                transitions: [Transition] = [], captions: [Caption] = [], markers: [Marker] = [],
                titles: [MotionTitle] = []) {
        self.name = name
        self.format = format
        self.clips = clips
        self.transitions = transitions
        self.captions = captions
        self.markers = markers
        self.titles = titles
    }

    private enum CodingKeys: String, CodingKey {
        case name, format, clips, transitions, captions, markers, titles
    }

    /// Custom decoder so every collection section is optional: timelines
    /// serialized before a field existed (e.g. `titles`) still decode, and
    /// minimal payloads need only supply `name` and `format`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        format = try c.decode(VideoFormat.self, forKey: .format)
        clips = try c.decodeIfPresent([Clip].self, forKey: .clips) ?? []
        transitions = try c.decodeIfPresent([Transition].self, forKey: .transitions) ?? []
        captions = try c.decodeIfPresent([Caption].self, forKey: .captions) ?? []
        markers = try c.decodeIfPresent([Marker].self, forKey: .markers) ?? []
        titles = try c.decodeIfPresent([MotionTitle].self, forKey: .titles) ?? []
    }

    /// Clips on the primary storyline (lane 0), in timeline order.
    public var storyline: [Clip] {
        clips.filter { $0.lane == 0 }.sorted { $0.offset < $1.offset }
    }

    /// Clips connected above/below the storyline.
    public var connectedClips: [Clip] {
        clips.filter { $0.lane != 0 }.sorted { $0.offset < $1.offset }
    }

    public var duration: RationalTime {
        clips.map(\.timelineRange.end).max() ?? .zero
    }

    /// Appends a clip to the end of the primary storyline.
    @discardableResult
    public mutating func appendToStoryline(assetID: AssetID, name: String,
                                           sourceRange: TimeRange, role: Role = .video) -> Clip {
        let clip = Clip(assetID: assetID, name: name,
                        offset: storylineEnd, sourceRange: sourceRange, role: role)
        clips.append(clip)
        return clip
    }

    /// End of the last storyline clip (where the next append lands).
    public var storylineEnd: RationalTime {
        storyline.last.map(\.timelineRange.end) ?? .zero
    }

    /// Validates structural invariants; returns human-readable problems.
    public func validate() -> [String] {
        var problems: [String] = []
        let story = storyline
        for (a, b) in zip(story, story.dropFirst()) {
            if a.timelineRange.end > b.offset {
                problems.append("storyline clips '\(a.name)' and '\(b.name)' overlap")
            }
            if a.timelineRange.end < b.offset {
                problems.append("gap between storyline clips '\(a.name)' and '\(b.name)' (FCP requires explicit gap elements)")
            }
        }
        for clip in clips where clip.duration.isZero {
            problems.append("clip '\(clip.name)' has zero duration")
        }
        for caption in captions where caption.text.isEmpty {
            problems.append("caption at \(caption.range.start) is empty")
        }
        for transition in transitions {
            let cutPoints = Set(story.dropFirst().map(\.offset))
            if !cutPoints.contains(transition.offset) {
                problems.append("transition '\(transition.name)' at \(transition.offset) is not on a cut point")
            }
        }
        return problems
    }
}

/// Container hierarchy mirroring FCP: Library → Event → Project (timeline).
public struct Project: Sendable, Codable, Identifiable {
    public var id: ProjectID
    public var name: String
    public var timeline: Timeline

    public init(id: ProjectID = ProjectID(), name: String, timeline: Timeline) {
        self.id = id
        self.name = name
        self.timeline = timeline
    }
}

public struct Event: Sendable, Codable {
    public var name: String
    public var projects: [Project]
    public var assets: [Asset]

    public init(name: String, projects: [Project] = [], assets: [Asset] = []) {
        self.name = name
        self.projects = projects
        self.assets = assets
    }
}

public struct Library: Sendable, Codable {
    public var name: String
    public var events: [Event]

    public init(name: String, events: [Event] = []) {
        self.name = name
        self.events = events
    }

    public var allAssets: [Asset] { events.flatMap(\.assets) }
}
