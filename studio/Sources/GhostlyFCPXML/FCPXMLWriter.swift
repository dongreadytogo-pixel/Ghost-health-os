import Foundation
import GhostlyCore
import GhostlyDomain

/// Serializes a domain `Library` into Final Cut Pro FCPXML.
///
/// Time semantics honored throughout (the part most generators get wrong):
/// * `offset` of a spine element is in **parent timeline** time.
/// * `start` of a clip is its **source in-point**.
/// * children of a clip (markers, keywords, captions, connected clips) are
///   positioned in the **parent clip's source time**, so a timeline instant
///   `T` on a clip with offset `O` and in-point `S` maps to `T - O + S`.
public struct FCPXMLWriter {
    public let version: String

    public init(version: String = "1.11") {
        self.version = version
    }

    // MARK: Public API

    public func document(for library: Library) throws -> String {
        var resources = ResourceTable()
        let libraryElement = XML("library")
        for event in library.events {
            libraryElement.child(try eventElement(event, resources: &resources))
        }
        let root = XML("fcpxml", [("version", version)])
        root.child(resources.element())
        root.child(libraryElement)
        return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE fcpxml>\n" + root.serialized() + "\n"
    }

    /// Convenience: wraps a single project in a library/event.
    public func document(for project: Project, assets: [Asset], eventName: String = "Ghostly") throws -> String {
        let library = Library(name: "Ghostly Library",
                              events: [Event(name: eventName, projects: [project], assets: assets)])
        return try document(for: library)
    }

    // MARK: Resources

    /// Allocates `r1, r2, …` ids, deduplicating formats/assets/effects.
    struct ResourceTable {
        private var formats: [VideoFormat: String] = [:]
        private var assets: [AssetID: String] = [:]
        private var effects: [String: String] = [:] // uid → id
        private var ordered: [XML] = []
        private var nextID = 1
        private var nextTextStyleID = 1

        mutating func allocateID() -> String {
            defer { nextID += 1 }
            return "r\(nextID)"
        }

        mutating func allocateTextStyleID() -> String {
            defer { nextTextStyleID += 1 }
            return "ts\(nextTextStyleID)"
        }

        mutating func format(_ format: VideoFormat) -> String {
            if let id = formats[format] { return id }
            let id = allocateID()
            formats[format] = id
            ordered.append(
                XML("format", [("id", id)])
                    .attr("frameDuration", format.frameRate.frameDuration.description)
                    .attr("width", String(format.width))
                    .attr("height", String(format.height))
                    .attr("colorSpace", colorSpaceCode(format.colorSpace))
            )
            return id
        }

        mutating func asset(_ asset: Asset, formatID: String?) -> String {
            if let id = assets[asset.id] { return id }
            let id = allocateID()
            assets[asset.id] = id
            let element = XML("asset", [("id", id)])
                .attr("name", asset.name)
                .attr("start", "0s")
                .attr("duration", asset.duration.description)
                .attr("hasVideo", asset.hasVideo ? "1" : nil)
                .attr("hasAudio", asset.hasAudio ? "1" : nil)
                .attr("format", formatID)
            element.child(XML("media-rep", [
                ("kind", "original-media"),
                ("src", asset.url.absoluteString),
            ]))
            ordered.append(element)
            return id
        }

        mutating func effect(name: String, uid: String) -> String {
            if let id = effects[uid] { return id }
            let id = allocateID()
            effects[uid] = id
            ordered.append(XML("effect", [("id", id), ("name", name), ("uid", uid)]))
            return id
        }

        func element() -> XML {
            XML("resources").appendingChildren(ordered)
        }

        private func colorSpaceCode(_ space: VideoFormat.ColorSpace) -> String {
            switch space {
            case .rec709: return "1-1-1"
            case .rec2020: return "9-9-9"
            case .rec2020HLG: return "9-18-9"
            case .rec2020PQ: return "9-16-9"
            }
        }
    }

    // MARK: Structure

    private func eventElement(_ event: Event, resources: inout ResourceTable) throws -> XML {
        let element = XML("event", [("name", event.name)])
        let assetIndex = Dictionary(uniqueKeysWithValues: event.assets.map { ($0.id, $0) })
        // Register all event assets up front so browser-only media is preserved.
        for asset in event.assets {
            let formatID = asset.format.map { fmt in resources.format(fmt) }
            _ = resources.asset(asset, formatID: formatID)
        }
        for project in event.projects {
            element.child(try projectElement(project, assets: assetIndex, resources: &resources))
        }
        return element
    }

    private func projectElement(_ project: Project, assets: [AssetID: Asset],
                                resources: inout ResourceTable) throws -> XML {
        let timeline = project.timeline
        let formatID = resources.format(timeline.format)
        let sequence = XML("sequence")
            .attr("format", formatID)
            .attr("duration", timeline.format.frameRate.snapped(timeline.duration).description)
            .attr("tcStart", "0s")
            .attr("tcFormat", "NDF")
        sequence.child(try spineElement(timeline, assets: assets, resources: &resources))
        return XML("project", [("name", project.name)]).child(sequence)
    }

    private func spineElement(_ timeline: Timeline, assets: [AssetID: Asset],
                              resources: inout ResourceTable) throws -> XML {
        let spine = XML("spine")
        let story = timeline.storyline
        guard !story.isEmpty else { return spine }

        // Transitions indexed by the cut point they sit on.
        let transitionsByCut = Dictionary(grouping: timeline.transitions, by: \.offset)

        var cursor = RationalTime.zero
        for clip in story {
            if clip.offset > cursor {
                spine.child(XML("gap", [
                    ("name", "Gap"),
                    ("offset", cursor.description),
                    ("duration", (clip.offset - cursor).description),
                ]))
            }
            if let transitions = transitionsByCut[clip.offset] {
                for transition in transitions {
                    spine.child(transitionElement(transition, resources: &resources))
                }
            }
            spine.child(try clipElement(clip, in: timeline, assets: assets, resources: &resources))
            cursor = clip.timelineRange.end
        }
        return spine
    }

    private func transitionElement(_ transition: Transition, resources: inout ResourceTable) -> XML {
        let element = XML("transition")
            .attr("name", transition.name)
            .attr("offset", (transition.offset - transition.duration.scaled(by: 1, over: 2)).description)
            .attr("duration", transition.duration.description)
        if let uid = transition.uid {
            let effectID = resources.effect(name: transition.name, uid: uid)
            element.child(XML("filter-video", [("ref", effectID), ("name", transition.name)]))
        }
        return element
    }

    private func clipElement(_ clip: Clip, in timeline: Timeline, assets: [AssetID: Asset],
                             resources: inout ResourceTable) throws -> XML {
        guard let asset = assets[clip.assetID] else {
            throw StudioError.notFound(entity: "Asset", id: clip.assetID.rawValue)
        }
        let formatID = asset.format.map { fmt in resources.format(fmt) }
        let assetRef = resources.asset(asset, formatID: formatID)

        let element = XML("asset-clip")
            .attr("ref", assetRef)
            .attr("offset", clip.offset.description)
            .attr("name", clip.name)
            .attr("start", clip.sourceRange.start.description)
            .attr("duration", clip.sourceRange.duration.description)
        if clip.lane != 0 { element.attr("lane", String(clip.lane)) }
        if !clip.enabled { element.attr("enabled", "0") }
        switch clip.role.name {
        case Role.dialogue.name, Role.music.name, Role.effects.name:
            element.attr("audioRole", clip.role.description)
        default:
            element.attr("videoRole", clip.role.description)
        }
        if clip.volume != 1.0 {
            element.child(XML("adjust-volume", [("amount", volumeDB(clip.volume))]))
        }
        for effect in clip.effects {
            let effectID = resources.effect(name: effect.name, uid: effect.uid)
            let filter = XML("filter-video", [("ref", effectID), ("name", effect.name)])
            for (key, value) in effect.parameters.sorted(by: { $0.key < $1.key }) {
                filter.child(XML("param", [("name", key), ("value", parameterString(value))]))
            }
            element.child(filter)
        }
        // Clip-local annotations are already in source time.
        for keyword in clip.keywords {
            element.child(XML("keyword", [
                ("start", keyword.range.start.description),
                ("duration", keyword.range.duration.description),
                ("value", keyword.keywords.joined(separator: ", ")),
            ]))
        }
        for marker in clip.markers {
            element.child(markerElement(marker))
        }
        // Timeline-level artifacts anchored inside this clip get converted
        // into the clip's source time.
        if clip.lane == 0 {
            let toLocal = { (t: RationalTime) -> RationalTime in
                t - clip.offset + clip.sourceRange.start
            }
            for connected in timeline.connectedClips
            where clip.timelineRange.contains(connected.offset) {
                var local = connected
                local.offset = toLocal(connected.offset)
                element.child(try clipElement(local, in: Timeline(name: "", format: timeline.format),
                                              assets: assets, resources: &resources))
            }
            for marker in timeline.markers where clip.timelineRange.contains(marker.start) {
                var local = marker
                local.start = toLocal(marker.start)
                element.child(markerElement(local))
            }
            for caption in timeline.captions
            where clip.timelineRange.contains(caption.range.start) {
                element.child(captionElement(caption, offset: toLocal(caption.range.start),
                                             resources: &resources))
            }
            for title in timeline.titles
            where clip.timelineRange.contains(title.range.start) {
                element.child(titleElement(title, offset: toLocal(title.range.start),
                                           resources: &resources))
            }
        }
        return element
    }

    private func titleElement(_ title: MotionTitle, offset: RationalTime,
                              resources: inout ResourceTable) -> XML {
        let effectID = resources.effect(name: title.templateName, uid: title.templateUID)
        let styleID = resources.allocateTextStyleID()
        let element = XML("title")
            .attr("ref", effectID)
            .attr("lane", String(title.lane))
            .attr("offset", offset.description)
            .attr("name", title.text.isEmpty ? title.templateName : title.text)
            .attr("duration", title.range.duration.description)
        element.child(
            XML("text").child(XML("text-style", [("ref", styleID)], text: title.text))
        )
        element.child(
            XML("text-style-def", [("id", styleID)])
                .child(XML("text-style", [
                    ("font", title.fontName),
                    ("fontSize", String(format: "%.0f", title.fontSize)),
                    ("fontColor", "1 1 1 1"),
                    ("alignment", title.position == .bottomLeft ? "left" : "center"),
                ]))
        )
        return element
    }

    private func markerElement(_ marker: Marker) -> XML {
        let element = XML("marker")
            .attr("start", marker.start.description)
            .attr("duration", marker.duration.description)
            .attr("value", marker.text)
        switch marker.kind {
        case .toDo: element.attr("completed", "0")
        case .completed: element.attr("completed", "1")
        case .chapter, .standard: break
        }
        return element
    }

    private func captionElement(_ caption: Caption, offset: RationalTime,
                                resources: inout ResourceTable) -> XML {
        let styleID = resources.allocateTextStyleID()
        let roleFormat: String
        switch caption.format {
        case .itt: roleFormat = "iTT?captionFormat=ITT.en"
        case .cea608: roleFormat = "captions?captionFormat=CEA-608.en"
        case .srt: roleFormat = "captions?captionFormat=SRT.en"
        }
        let element = XML("caption")
            .attr("role", roleFormat)
            .attr("offset", offset.description)
            .attr("duration", caption.range.duration.description)
        element.child(
            XML("text").child(XML("text-style", [("ref", styleID)], text: caption.text))
        )
        element.child(
            XML("text-style-def", [("id", styleID)])
                .child(XML("text-style", [
                    ("font", ".AppleSystemUIFont"),
                    ("fontSize", "63"),
                    ("fontColor", "1 1 1 1"),
                    ("backgroundColor", "0 0 0 0.7"),
                    ("alignment", "center"),
                ]))
        )
        return element
    }

    private func volumeDB(_ linear: Double) -> String {
        guard linear > 0 else { return "-96dB" }
        let db = 20 * log10(linear)
        return String(format: "%.1fdB", db)
    }

    private func parameterString(_ value: EffectParameterValue) -> String {
        switch value {
        case .number(let n):
            return n == n.rounded() ? String(Int(n)) : String(n)
        case .text(let s): return s
        case .boolean(let b): return b ? "1" : "0"
        }
    }
}
