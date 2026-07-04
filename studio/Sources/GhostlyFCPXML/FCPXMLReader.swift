import Foundation
import GhostlyCore
import GhostlyDomain

/// Parses FCPXML (as produced by Final Cut Pro or this engine) back into the
/// domain model. Inverse of `FCPXMLWriter` for the supported element subset.
public struct FCPXMLReader {
    public init() {}

    public func library(from string: String) throws -> Library {
        let root = try XMLDocumentParser.parse(string)
        guard root.name == "fcpxml" else {
            throw StudioError.parseFailure(format: "FCPXML", detail: "root element is <\(root.name)>, expected <fcpxml>")
        }
        let resources = try ResourceIndex(root.first("resources"))

        // FCP emits either a <library> or bare <event>/<project> children.
        let libraryElement = root.first("library")
        let libraryName = libraryElement?[attribute: "name"] ?? "Imported Library"
        let eventElements = libraryElement?.all("event") ?? root.all("event")

        var events: [Event] = []
        for eventElement in eventElements {
            events.append(try event(eventElement, resources: resources))
        }
        return Library(name: libraryName, events: events)
    }

    // MARK: Resources

    struct ResourceIndex {
        var formats: [String: VideoFormat] = [:]
        var assets: [String: Asset] = [:]

        init(_ element: XML?) throws {
            guard let element else { return }
            for formatElement in element.all("format") {
                guard let id = formatElement[attribute: "id"] else { continue }
                formats[id] = Self.videoFormat(formatElement)
            }
            for assetElement in element.all("asset") {
                guard let id = assetElement[attribute: "id"] else { continue }
                let name = assetElement[attribute: "name"] ?? id
                let duration = assetElement[attribute: "duration"]
                    .flatMap(RationalTime.init(fcpxml:)) ?? .zero
                let src = assetElement.first("media-rep")?[attribute: "src"] ?? "file:///missing"
                let hasVideo = assetElement[attribute: "hasVideo"] == "1"
                let hasAudio = assetElement[attribute: "hasAudio"] == "1"
                let kind: Asset.Kind = hasVideo ? .video : (hasAudio ? .audio : .image)
                let format = assetElement[attribute: "format"].flatMap { formats[$0] }
                assets[id] = Asset(id: AssetID(id), name: name,
                                   url: URL(string: src) ?? URL(fileURLWithPath: "/missing"),
                                   duration: duration, kind: kind, format: format)
            }
        }

        static func videoFormat(_ element: XML) -> VideoFormat {
            let width = element[attribute: "width"].flatMap(Int.init) ?? 1920
            let height = element[attribute: "height"].flatMap(Int.init) ?? 1080
            let frameRate: FrameRate
            if let fd = element[attribute: "frameDuration"].flatMap(RationalTime.init(fcpxml:)),
               fd.value > 0 {
                frameRate = FrameRate(frames: fd.timescale, secondsPerBatch: Int32(fd.value))
            } else {
                frameRate = .fps30
            }
            let colorSpace: VideoFormat.ColorSpace
            switch element[attribute: "colorSpace"] {
            case "9-9-9": colorSpace = .rec2020
            case "9-18-9": colorSpace = .rec2020HLG
            case "9-16-9": colorSpace = .rec2020PQ
            default: colorSpace = .rec709
            }
            return VideoFormat(width: width, height: height, frameRate: frameRate, colorSpace: colorSpace)
        }
    }

    // MARK: Structure

    private func event(_ element: XML, resources: ResourceIndex) throws -> Event {
        let name = element[attribute: "name"] ?? "Imported Event"
        var projects: [Project] = []
        for projectElement in element.all("project") {
            projects.append(try project(projectElement, resources: resources))
        }
        return Event(name: name, projects: projects, assets: Array(resources.assets.values))
    }

    private func project(_ element: XML, resources: ResourceIndex) throws -> Project {
        let name = element[attribute: "name"] ?? "Imported Project"
        guard let sequenceElement = element.first("sequence") else {
            throw StudioError.parseFailure(format: "FCPXML", detail: "project '\(name)' has no <sequence>")
        }
        let format = sequenceElement[attribute: "format"]
            .flatMap { resources.formats[$0] } ?? .hd1080p30

        var timeline = Timeline(name: name, format: format)
        if let spine = sequenceElement.first("spine") {
            for child in spine.children {
                switch child.name {
                case "asset-clip", "video", "mc-clip", "sync-clip", "ref-clip", "clip":
                    try appendClip(child, lane: 0, parentOffset: nil,
                                   into: &timeline, resources: resources)
                case "transition":
                    timeline.transitions.append(transition(child))
                case "gap":
                    // Gaps are implicit in the domain model (validated on export),
                    // but captions/markers anchored to a gap are timeline artifacts.
                    try absorbGapChildren(child, into: &timeline, resources: resources)
                default:
                    continue
                }
            }
        }
        return Project(id: ProjectID(), name: name, timeline: timeline)
    }

    /// Parses a clip element (and its connected children) into the timeline.
    private func appendClip(_ element: XML, lane: Int, parentOffset: RationalTime?,
                            into timeline: inout Timeline, resources: ResourceIndex) throws {
        let offset = element[attribute: "offset"].flatMap(RationalTime.init(fcpxml:)) ?? .zero
        let start = element[attribute: "start"].flatMap(RationalTime.init(fcpxml:)) ?? .zero
        let duration = element[attribute: "duration"].flatMap(RationalTime.init(fcpxml:)) ?? .zero
        let name = element[attribute: "name"] ?? "Clip"
        let ref = element[attribute: "ref"]
        let asset = ref.flatMap { resources.assets[$0] }

        let role: Role
        if let audioRole = element[attribute: "audioRole"] {
            role = parseRole(audioRole)
        } else if let videoRole = element[attribute: "videoRole"] {
            role = parseRole(videoRole)
        } else {
            role = .video
        }

        // A child clip's offset is in the parent's source time; convert back
        // to timeline time using the parent's mapping.
        let timelineOffset: RationalTime
        if let parentOffset {
            timelineOffset = parentOffset + offset
        } else {
            timelineOffset = offset
        }

        var clip = Clip(assetID: asset?.id ?? AssetID(ref ?? "missing"),
                        name: name,
                        offset: timelineOffset,
                        sourceRange: TimeRange(start: start, duration: duration),
                        lane: lane,
                        role: role,
                        enabled: element[attribute: "enabled"] != "0")

        // The mapping from this clip's source time back to timeline time,
        // applied to children (markers/captions/connected clips).
        let sourceToTimeline = { (t: RationalTime) -> RationalTime in
            t - start + timelineOffset
        }

        for child in element.children {
            switch child.name {
            case "marker":
                var marker = self.marker(child)
                if lane == 0 {
                    marker.start = sourceToTimeline(marker.start)
                    timeline.markers.append(marker)
                } else {
                    clip.markers.append(marker)
                }
            case "keyword":
                if let range = keywordRange(child) {
                    clip.keywords.append(range)
                }
            case "caption":
                if let caption = caption(child, sourceToTimeline: sourceToTimeline) {
                    timeline.captions.append(caption)
                }
            case "asset-clip", "video", "clip":
                let childLane = child[attribute: "lane"].flatMap(Int.init) ?? 0
                // Child offsets are in this clip's source time; the timeline
                // position of source zero is `timelineOffset - start`.
                try appendClip(child, lane: childLane == 0 ? lane : childLane,
                               parentOffset: timelineOffset - start,
                               into: &timeline, resources: resources)
            default:
                continue
            }
        }
        timeline.clips.append(clip)
    }

    private func absorbGapChildren(_ gap: XML, into timeline: inout Timeline,
                                   resources: ResourceIndex) throws {
        let offset = gap[attribute: "offset"].flatMap(RationalTime.init(fcpxml:)) ?? .zero
        let start = gap[attribute: "start"].flatMap(RationalTime.init(fcpxml:)) ?? .zero
        let sourceToTimeline = { (t: RationalTime) -> RationalTime in t - start + offset }
        for child in gap.children {
            switch child.name {
            case "caption":
                if let caption = caption(child, sourceToTimeline: sourceToTimeline) {
                    timeline.captions.append(caption)
                }
            case "marker":
                var marker = self.marker(child)
                marker.start = sourceToTimeline(marker.start)
                timeline.markers.append(marker)
            case "asset-clip", "video", "clip":
                let childLane = child[attribute: "lane"].flatMap(Int.init) ?? 1
                try appendClip(child, lane: childLane, parentOffset: offset - start,
                               into: &timeline, resources: resources)
            default:
                continue
            }
        }
    }

    // MARK: Leaf elements

    private func transition(_ element: XML) -> Transition {
        let duration = element[attribute: "duration"].flatMap(RationalTime.init(fcpxml:)) ?? .zero
        let leadingEdge = element[attribute: "offset"].flatMap(RationalTime.init(fcpxml:)) ?? .zero
        return Transition(name: element[attribute: "name"] ?? "Transition",
                          uid: element.first("filter-video")?[attribute: "ref"],
                          offset: leadingEdge + duration.scaled(by: 1, over: 2),
                          duration: duration)
    }

    private func marker(_ element: XML) -> Marker {
        let kind: Marker.Kind
        switch element[attribute: "completed"] {
        case "0": kind = .toDo
        case "1": kind = .completed
        default: kind = .standard
        }
        return Marker(
            start: element[attribute: "start"].flatMap(RationalTime.init(fcpxml:)) ?? .zero,
            duration: element[attribute: "duration"].flatMap(RationalTime.init(fcpxml:))
                ?? RationalTime(value: 1, timescale: 30),
            text: element[attribute: "value"] ?? "",
            kind: kind
        )
    }

    private func keywordRange(_ element: XML) -> KeywordRange? {
        guard let value = element[attribute: "value"] else { return nil }
        let start = element[attribute: "start"].flatMap(RationalTime.init(fcpxml:)) ?? .zero
        let duration = element[attribute: "duration"].flatMap(RationalTime.init(fcpxml:)) ?? .zero
        return KeywordRange(range: TimeRange(start: start, duration: duration),
                            keywords: value.components(separatedBy: ", "))
    }

    private func caption(_ element: XML,
                         sourceToTimeline: (RationalTime) -> RationalTime) -> Caption? {
        let offset = element[attribute: "offset"].flatMap(RationalTime.init(fcpxml:)) ?? .zero
        let duration = element[attribute: "duration"].flatMap(RationalTime.init(fcpxml:)) ?? .zero
        let textParts = element.first("text")?.descendantsText() ?? []
        let text = textParts.joined(separator: " ")
        guard !text.isEmpty else { return nil }
        let format: Caption.CaptionFormat
        let role = element[attribute: "role"] ?? ""
        if role.contains("CEA-608") { format = .cea608 }
        else if role.contains("SRT") { format = .srt }
        else { format = .itt }
        return Caption(text: text,
                       range: TimeRange(start: sourceToTimeline(offset), duration: duration),
                       format: format)
    }

    private func parseRole(_ string: String) -> Role {
        let parts = string.split(separator: ".", maxSplits: 1).map(String.init)
        if parts.count == 2 { return Role(parts[0], subrole: parts[1]) }
        return Role(string)
    }
}

extension XML {
    /// All text content in this subtree, in document order.
    func descendantsText() -> [String] {
        var out: [String] = []
        if let text, !text.isEmpty { out.append(text) }
        for child in children { out.append(contentsOf: child.descendantsText()) }
        return out
    }
}
