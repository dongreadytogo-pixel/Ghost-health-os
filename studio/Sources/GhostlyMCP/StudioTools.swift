import Foundation
import GhostlyCore
import GhostlyDomain
import GhostlyFCPXML
import GhostlySubtitles
import GhostlyDirector
import GhostlyDetection
import GhostlyLearning
import GhostlyAssets

/// The wire schema for auto-edit jobs submitted by AI agents. Times are in
/// seconds (JSON-friendly); conversion to rational time happens at the edge.
public struct EditJob: Codable, Sendable {
    public var command: String
    public var projectName: String?
    public var footage: [FootageItem]
    public var music: FootageItem?
    public var transcriptSRT: String?

    public struct FootageItem: Codable, Sendable {
        public var name: String
        public var url: String
        public var durationSeconds: Double
        public var kind: String?
        /// [start, end] pairs in seconds.
        public var speechRanges: [[Double]]?
        public var sceneCuts: [Double]?
        public var beats: [Double]?

        public func asset() throws -> Asset {
            guard durationSeconds > 0 else {
                throw StudioError.invalidInput(field: "durationSeconds",
                                               reason: "must be positive for '\(name)'")
            }
            guard let parsed = URL(string: url) ?? URL(string: "file://\(url)") else {
                throw StudioError.invalidInput(field: "url", reason: "unparseable: '\(url)'")
            }
            let assetKind = Asset.Kind(rawValue: kind ?? "video") ?? .video
            return Asset(name: name, url: parsed,
                         duration: RationalTime(seconds: durationSeconds, preferredTimescale: 48_000),
                         kind: assetKind,
                         format: assetKind == .video ? .hd1080p30 : nil)
        }

        public func analysis(for asset: Asset) -> MediaAnalysis {
            let time = { RationalTime(seconds: $0, preferredTimescale: 48_000) }
            return MediaAnalysis(
                assetID: asset.id,
                duration: asset.duration,
                speechRanges: (speechRanges ?? []).compactMap { pair in
                    guard pair.count == 2, pair[1] > pair[0] else { return nil }
                    return TimeRange(start: time(pair[0]), end: time(pair[1]))
                },
                sceneCuts: (sceneCuts ?? []).map(time),
                beats: (beats ?? []).map(time))
        }
    }
}

/// Shared decoding helper for tool arguments.
enum ToolArguments {
    static func decode<T: Decodable>(_ type: T.Type, from json: JSONValue) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: try json.encoded())
        } catch let error as DecodingError {
            throw StudioError.invalidInput(field: "arguments", reason: describe(error))
        }
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case let .keyNotFound(key, _): return "missing required field '\(key.stringValue)'"
        case let .typeMismatch(type, context):
            return "field '\(context.codingPath.map(\.stringValue).joined(separator: "."))' must be \(type)"
        case let .valueNotFound(_, context):
            return "field '\(context.codingPath.map(\.stringValue).joined(separator: "."))' is null"
        case .dataCorrupted: return "arguments are not valid JSON"
        @unknown default: return "undecodable arguments"
        }
    }
}

// MARK: Tools

/// `auto_edit`: natural-language command + analyzed footage → validated FCPXML.
public struct AutoEditTool: MCPTool {
    public let name = "auto_edit"
    public let description = """
    Build a complete Final Cut Pro timeline from footage using a natural-language \
    editing command (e.g. "edit this like Marvel", "create a tiktok with captions"). \
    Returns valid FCPXML ready to import.
    """
    public let inputSchema: JSONValue = .object([
        "type": "object",
        "properties": .object([
            "command": .object(["type": "string", "description": "natural-language editing instruction"]),
            "projectName": .object(["type": "string"]),
            "footage": .object([
                "type": "array",
                "description": "assets with optional detection data (seconds)",
                "items": .object([
                    "type": "object",
                    "properties": .object([
                        "name": .object(["type": "string"]),
                        "url": .object(["type": "string"]),
                        "durationSeconds": .object(["type": "number"]),
                        "kind": .object(["type": "string", "enum": ["video", "audio", "image"]]),
                        "speechRanges": .object(["type": "array"]),
                        "sceneCuts": .object(["type": "array"]),
                        "beats": .object(["type": "array"]),
                    ]),
                    "required": .array(["name", "url", "durationSeconds"]),
                ]),
            ]),
            "music": .object(["type": "object", "description": "optional music asset, same shape as footage items"]),
            "transcriptSRT": .object(["type": "string", "description": "optional SRT transcript for captions"]),
        ]),
        "required": .array(["command", "footage"]),
    ])

    public init() {}

    public func call(arguments: JSONValue) async throws -> JSONValue {
        let job = try ToolArguments.decode(EditJob.self, from: arguments)
        let plan = try Director().interpret(job.command)

        var footage: [(Asset, MediaAnalysis)] = []
        for item in job.footage {
            let asset = try item.asset()
            footage.append((asset, item.analysis(for: asset)))
        }
        var music: (Asset, MediaAnalysis)?
        if let item = job.music {
            var audioItem = item
            audioItem.kind = audioItem.kind ?? "audio"
            let asset = try audioItem.asset()
            music = (asset, audioItem.analysis(for: asset))
        }
        let transcript = try job.transcriptSRT.map { try SRT.parse($0) }

        let timeline = try AutoEditPlanner(profile: plan.profile).plan(
            footage: footage, music: music, transcript: transcript,
            projectName: job.projectName ?? "AI Edit")

        let assets = footage.map(\.0) + (music.map { [$0.0] } ?? [])
        let document = try FCPXMLWriter().document(
            for: Project(name: job.projectName ?? "AI Edit", timeline: timeline),
            assets: assets)

        let issues = FCPXMLValidator().validate(document)
        guard !issues.contains(where: { $0.severity == .error }) else {
            throw StudioError.validationFailure(detail: issues.map(\.description).joined(separator: "; "))
        }
        return .string(document)
    }
}

/// `parse_edit_command`: NL command → structured intents and profile.
public struct ParseCommandTool: MCPTool {
    public let name = "parse_edit_command"
    public let description = "Parse a natural-language editing command into structured intents and the resolved pacing profile."
    public let inputSchema: JSONValue = .object([
        "type": "object",
        "properties": .object(["command": .object(["type": "string"])]),
        "required": .array(["command"]),
    ])

    public init() {}

    public func call(arguments: JSONValue) async throws -> JSONValue {
        guard let command = arguments["command"]?.stringValue, !command.isEmpty else {
            throw StudioError.invalidInput(field: "command", reason: "required")
        }
        let plan = try Director().interpret(command)
        let profileData = try JSONEncoder().encode(plan.profile)
        return .object([
            "intents": .array(plan.intents.map { .string(String(describing: $0)) }),
            "profile": try JSONValue(from: profileData),
            "wantsCaptions": .bool(plan.wantsCaptions),
            "wantsMusicReplacement": .bool(plan.wantsMusicReplacement),
            "musicQuery": plan.musicQuery.map(JSONValue.string) ?? .null,
        ])
    }
}

/// `generate_captions`: SRT/VTT content + style → styled captions.
public struct GenerateCaptionsTool: MCPTool {
    public let name = "generate_captions"
    public let description = "Restyle a subtitle file (SRT or VTT) with a platform caption style (TikTok, YouTube, Instagram, Broadcast). Returns the styled track as SRT plus style metadata."
    public let inputSchema: JSONValue = .object([
        "type": "object",
        "properties": .object([
            "subtitles": .object(["type": "string", "description": "SRT or VTT file content"]),
            "style": .object(["type": "string", "enum": ["TikTok", "YouTube", "Instagram", "Broadcast"]]),
            "shiftSeconds": .object(["type": "number", "description": "optional time offset"]),
        ]),
        "required": .array(["subtitles", "style"]),
    ])

    public init() {}

    public func call(arguments: JSONValue) async throws -> JSONValue {
        guard let content = arguments["subtitles"]?.stringValue else {
            throw StudioError.invalidInput(field: "subtitles", reason: "required")
        }
        guard let styleName = arguments["style"]?.stringValue,
              let style = CaptionStyle.named(styleName) else {
            throw StudioError.notFound(entity: "CaptionStyle",
                                       id: arguments["style"]?.stringValue ?? "")
        }
        var track = content.hasPrefix("WEBVTT")
            ? try WebVTT.parse(content)
            : try SRT.parse(content)
        if let shift = arguments["shiftSeconds"]?.numberValue, shift != 0 {
            track = track.shifted(by: RationalTime(seconds: shift, preferredTimescale: 1000))
        }
        let styled = style.styled(track)
        return .object([
            "srt": .string(SRT.serialize(styled)),
            "cueCount": .number(Double(styled.cues.count)),
            "style": .string(style.name),
            "position": .string(style.position.rawValue),
            "animation": .string(style.animation.rawValue),
        ])
    }
}

/// `validate_fcpxml`: lint any FCPXML document.
public struct ValidateFCPXMLTool: MCPTool {
    public let name = "validate_fcpxml"
    public let description = "Validate an FCPXML document: XML well-formedness, resource references, time syntax, and spine continuity. Returns issues by severity."
    public let inputSchema: JSONValue = .object([
        "type": "object",
        "properties": .object(["fcpxml": .object(["type": "string"])]),
        "required": .array(["fcpxml"]),
    ])

    public init() {}

    public func call(arguments: JSONValue) async throws -> JSONValue {
        guard let document = arguments["fcpxml"]?.stringValue else {
            throw StudioError.invalidInput(field: "fcpxml", reason: "required")
        }
        let issues = FCPXMLValidator().validate(document)
        return .object([
            "valid": .bool(!issues.contains { $0.severity == .error }),
            "errors": .array(issues.filter { $0.severity == .error }.map { .string($0.message) }),
            "warnings": .array(issues.filter { $0.severity == .warning }.map { .string($0.message) }),
        ])
    }
}

/// `analyze_timeline`: FCPXML → structural report.
public struct AnalyzeTimelineTool: MCPTool {
    public let name = "analyze_timeline"
    public let description = "Analyze an FCPXML document and report its structure: projects, clip counts, durations, captions, markers, and detected issues."
    public let inputSchema: JSONValue = .object([
        "type": "object",
        "properties": .object(["fcpxml": .object(["type": "string"])]),
        "required": .array(["fcpxml"]),
    ])

    public init() {}

    public func call(arguments: JSONValue) async throws -> JSONValue {
        guard let document = arguments["fcpxml"]?.stringValue else {
            throw StudioError.invalidInput(field: "fcpxml", reason: "required")
        }
        let library = try FCPXMLReader().library(from: document)
        let projects = library.events.flatMap(\.projects).map { project -> JSONValue in
            let t = project.timeline
            let averageShot = t.storyline.isEmpty ? 0
                : t.storyline.map(\.duration.seconds).reduce(0, +) / Double(t.storyline.count)
            return .object([
                "name": .string(project.name),
                "durationSeconds": .number(t.duration.seconds),
                "storylineClips": .number(Double(t.storyline.count)),
                "connectedClips": .number(Double(t.connectedClips.count)),
                "averageShotSeconds": .number((averageShot * 100).rounded() / 100),
                "captions": .number(Double(t.captions.count)),
                "markers": .number(Double(t.markers.count)),
                "transitions": .number(Double(t.transitions.count)),
                "problems": .array(t.validate().map(JSONValue.string)),
            ])
        }
        return .object([
            "library": .string(library.name),
            "events": .number(Double(library.events.count)),
            "assets": .number(Double(library.allAssets.count)),
            "projects": .array(projects),
        ])
    }
}

/// Wire schema for an asset submitted to the asset-search tool.
public struct AssetItem: Codable, Sendable {
    public var name: String
    public var url: String
    public var durationSeconds: Double?
    public var kind: String?
    public var tags: [String]?
    public var favorite: Bool?
    public var width: Int?
    public var height: Int?
    public var fps: Double?

    public func asset() throws -> Asset {
        guard let parsed = URL(string: url) ?? URL(string: "file://\(url)") else {
            throw StudioError.invalidInput(field: "url", reason: "unparseable: '\(url)'")
        }
        let assetKind = Asset.Kind(rawValue: kind ?? "video") ?? .video
        var format: VideoFormat?
        if let width, let height {
            format = VideoFormat(width: width, height: height,
                                 frameRate: FrameRate(frames: Int32((fps ?? 30).rounded()),
                                                      secondsPerBatch: 1))
        }
        return Asset(name: name, url: parsed,
                     duration: RationalTime(seconds: durationSeconds ?? 0, preferredTimescale: 48_000),
                     kind: assetKind, format: format,
                     tags: Set(tags ?? []), favorite: favorite ?? false)
    }
}

/// `search_assets`: natural-language search + auto-tagging over a set of assets.
public struct SearchAssetsTool: MCPTool {
    public let name = "search_assets"
    public let description = """
    Auto-tag a set of media assets and search them with a natural-language \
    query (e.g. "vertical 4k drone clips under 30 seconds", "favorite \
    interview audio"). Returns ranked matches with their derived tags.
    """
    public let inputSchema: JSONValue = .object([
        "type": "object",
        "properties": .object([
            "query": .object(["type": "string"]),
            "assets": .object([
                "type": "array",
                "items": .object([
                    "type": "object",
                    "properties": .object([
                        "name": .object(["type": "string"]),
                        "url": .object(["type": "string"]),
                        "durationSeconds": .object(["type": "number"]),
                        "kind": .object(["type": "string", "enum": ["video", "audio", "image"]]),
                        "tags": .object(["type": "array"]),
                        "favorite": .object(["type": "boolean"]),
                        "width": .object(["type": "number"]),
                        "height": .object(["type": "number"]),
                        "fps": .object(["type": "number"]),
                    ]),
                    "required": .array(["name", "url"]),
                ]),
            ]),
        ]),
        "required": .array(["query", "assets"]),
    ])

    public init() {}

    public func call(arguments: JSONValue) async throws -> JSONValue {
        guard let query = arguments["query"]?.stringValue, !query.isEmpty else {
            throw StudioError.invalidInput(field: "query", reason: "required")
        }
        guard let itemsJSON = arguments["assets"] else {
            throw StudioError.invalidInput(field: "assets", reason: "required")
        }
        let items = try ToolArguments.decode([AssetItem].self, from: itemsJSON)
        var catalog = AssetCatalog()
        for item in items { catalog.add(try item.asset()) }

        let matches = catalog.search(query)
        return .object([
            "query": .string(query),
            "matchCount": .number(Double(matches.count)),
            "results": .array(matches.map { asset in
                .object([
                    "name": .string(asset.name),
                    "url": .string(asset.url.absoluteString),
                    "kind": .string(asset.kind.rawValue),
                    "durationSeconds": .number((asset.duration.seconds * 100).rounded() / 100),
                    "favorite": .bool(asset.favorite),
                    "tags": .array(asset.tags.sorted().map(JSONValue.string)),
                ])
            }),
        ])
    }
}

/// `find_highlights`: analyzed footage → hooks, highlights, and chapters.
public struct FindHighlightsTool: MCPTool {
    public let name = "find_highlights"
    public let description = """
    Find the most engaging moments in analyzed footage — a hook, ranked \
    highlights, a call-to-action beat, and chapter boundaries. Feed in speech \
    ranges, scene cuts, and beats (seconds) plus an optional SRT transcript for \
    labeled moments. Ideal for short-form repurposing and auto-chaptering.
    """
    public let inputSchema: JSONValue = .object([
        "type": "object",
        "properties": .object([
            "footage": .object([
                "type": "object",
                "description": "single asset with detection data (seconds)",
                "properties": .object([
                    "name": .object(["type": "string"]),
                    "url": .object(["type": "string"]),
                    "durationSeconds": .object(["type": "number"]),
                    "speechRanges": .object(["type": "array"]),
                    "sceneCuts": .object(["type": "array"]),
                    "beats": .object(["type": "array"]),
                ]),
                "required": .array(["name", "url", "durationSeconds"]),
            ]),
            "transcriptSRT": .object(["type": "string"]),
            "limit": .object(["type": "number", "description": "max highlights (default 5)"]),
        ]),
        "required": .array(["footage"]),
    ])

    public init() {}

    public func call(arguments: JSONValue) async throws -> JSONValue {
        guard let footageJSON = arguments["footage"] else {
            throw StudioError.invalidInput(field: "footage", reason: "required")
        }
        let item = try ToolArguments.decode(EditJob.FootageItem.self, from: footageJSON)
        let asset = try item.asset()
        let analysis = item.analysis(for: asset)
        let transcript = try (arguments["transcriptSRT"]?.stringValue).map { try SRT.parse($0) }
        let limit = arguments["limit"]?.intValue ?? 5

        let planner = HighlightPlanner()
        let highlights = planner.highlights(from: analysis, transcript: transcript, limit: limit)
        let chapters = planner.chapters(from: analysis, transcript: transcript)

        return .object([
            "highlights": .array(highlights.map { h in
                .object([
                    "kind": .string(h.kind.rawValue),
                    "startSeconds": .number((h.range.start.seconds * 100).rounded() / 100),
                    "endSeconds": .number((h.range.end.seconds * 100).rounded() / 100),
                    "score": .number((h.score * 100).rounded() / 100),
                    "label": .string(h.label),
                ])
            }),
            "chapters": .array(chapters.map { c in
                .object([
                    "startSeconds": .number((c.start.seconds * 100).rounded() / 100),
                    "title": .string(c.text),
                ])
            }),
        ])
    }
}

/// `list_caption_styles`: enumerate built-in caption styles.
public struct ListCaptionStylesTool: MCPTool {
    public let name = "list_caption_styles"
    public let description = "List the built-in caption style presets with their key attributes."
    public let inputSchema: JSONValue = .object(["type": "object", "properties": .object([:])])

    public init() {}

    public func call(arguments: JSONValue) async throws -> JSONValue {
        .array(CaptionStyle.builtIn.map { style in
            .object([
                "name": .string(style.name),
                "font": .string(style.fontName),
                "fontSize": .number(style.fontSize),
                "position": .string(style.position.rawValue),
                "animation": .string(style.animation.rawValue),
                "allCaps": .bool(style.allCaps),
                "maxCharactersPerLine": .number(Double(style.maxCharactersPerLine)),
            ])
        })
    }
}

/// `recommend`: learning-system recommendations for a category.
public struct RecommendTool: MCPTool {
    public let name = "recommend"
    public let description = "Recommend the user's favorite values for a category (font, captionStyle, transition, effect, lut, exportPreset, asset, pacingStyle) based on locally-learned usage."
    public let inputSchema: JSONValue = .object([
        "type": "object",
        "properties": .object([
            "category": .object(["type": "string"]),
            "limit": .object(["type": "number"]),
        ]),
        "required": .array(["category"]),
    ])

    private let store: PreferenceStore

    public init(store: PreferenceStore) {
        self.store = store
    }

    public func call(arguments: JSONValue) async throws -> JSONValue {
        guard let raw = arguments["category"]?.stringValue,
              let category = UserPreferences.Category(rawValue: raw) else {
            throw StudioError.invalidInput(field: "category",
                reason: "must be one of \(UserPreferences.Category.allCases.map(\.rawValue).joined(separator: ", "))")
        }
        let limit = arguments["limit"]?.intValue ?? 5
        let values = await store.recommendations(for: category, limit: limit)
        return .object([
            "category": .string(raw),
            "recommendations": .array(values.map(JSONValue.string)),
        ])
    }
}

/// Assembles the standard Ghostly MCP server with every studio tool.
public enum GhostlyMCPFactory {
    public static func makeServer(preferencesDirectory: URL) async throws -> MCPServer {
        let store = try PreferenceStore(directory: preferencesDirectory)
        let server = MCPServer()
        await server.register(AutoEditTool())
        await server.register(ParseCommandTool())
        await server.register(GenerateCaptionsTool())
        await server.register(ValidateFCPXMLTool())
        await server.register(AnalyzeTimelineTool())
        await server.register(FindHighlightsTool())
        await server.register(SearchAssetsTool())
        await server.register(ListCaptionStylesTool())
        await server.register(RecommendTool(store: store))
        return server
    }
}
