import Foundation
import GhostlyCore

/// A reversible mutation of a `Timeline`. Commands are the unit of the
/// undo/redo system: each knows how to `apply` itself and how to `revert`
/// the exact change it made. Commands must be deterministic — applying and
/// then reverting returns the timeline to a value equal to the original.
public protocol EditCommand: Sendable {
    /// Human-readable label shown in undo/redo menus ("Append Clip").
    var name: String { get }
    /// Performs the change.
    func apply(to timeline: inout Timeline) throws
    /// Undoes exactly what `apply` did.
    func revert(from timeline: inout Timeline) throws
}

// MARK: Concrete commands

/// Appends a clip to the end of the primary storyline.
public struct AppendClipCommand: EditCommand {
    public let name = "Append Clip"
    public let clip: Clip

    /// - Parameters:
    ///   - assetID/clipName/sourceRange: clip to place; its offset is set to
    ///     the current storyline end at apply time.
    public init(assetID: AssetID, clipName: String, sourceRange: TimeRange,
                role: Role = .video, id: ClipID = ClipID()) {
        self.clip = Clip(id: id, assetID: assetID, name: clipName,
                         offset: .zero, sourceRange: sourceRange, role: role)
    }

    public func apply(to timeline: inout Timeline) throws {
        var placed = clip
        placed.offset = timeline.storylineEnd
        timeline.clips.append(placed)
    }

    public func revert(from timeline: inout Timeline) throws {
        guard let index = timeline.clips.lastIndex(where: { $0.id == clip.id }) else {
            throw StudioError.notFound(entity: "Clip", id: clip.id.rawValue)
        }
        timeline.clips.remove(at: index)
    }
}

/// Inserts an arbitrary clip (any lane/offset) and removes it on revert.
public struct InsertClipCommand: EditCommand {
    public let name = "Insert Clip"
    public let clip: Clip

    public init(clip: Clip) { self.clip = clip }

    public func apply(to timeline: inout Timeline) throws {
        guard !timeline.clips.contains(where: { $0.id == clip.id }) else {
            throw StudioError.invalidInput(field: "clip",
                                           reason: "clip '\(clip.id)' already on timeline")
        }
        timeline.clips.append(clip)
    }

    public func revert(from timeline: inout Timeline) throws {
        guard let index = timeline.clips.firstIndex(where: { $0.id == clip.id }) else {
            throw StudioError.notFound(entity: "Clip", id: clip.id.rawValue)
        }
        timeline.clips.remove(at: index)
    }
}

/// Removes a clip, remembering it (and its position) so revert restores it.
public final class RemoveClipCommand: EditCommand, @unchecked Sendable {
    public let name = "Remove Clip"
    public let clipID: ClipID
    private var removed: (clip: Clip, index: Int)?

    public init(clipID: ClipID) { self.clipID = clipID }

    public func apply(to timeline: inout Timeline) throws {
        guard let index = timeline.clips.firstIndex(where: { $0.id == clipID }) else {
            throw StudioError.notFound(entity: "Clip", id: clipID.rawValue)
        }
        removed = (timeline.clips[index], index)
        timeline.clips.remove(at: index)
    }

    public func revert(from timeline: inout Timeline) throws {
        guard let removed else {
            throw StudioError.invariant(detail: "RemoveClipCommand reverted before apply")
        }
        let index = min(removed.index, timeline.clips.count)
        timeline.clips.insert(removed.clip, at: index)
    }
}

/// Moves a clip to a new timeline offset.
public final class MoveClipCommand: EditCommand, @unchecked Sendable {
    public let name = "Move Clip"
    public let clipID: ClipID
    public let newOffset: RationalTime
    private var previousOffset: RationalTime?

    public init(clipID: ClipID, to newOffset: RationalTime) {
        self.clipID = clipID
        self.newOffset = newOffset
    }

    public func apply(to timeline: inout Timeline) throws {
        guard let index = timeline.clips.firstIndex(where: { $0.id == clipID }) else {
            throw StudioError.notFound(entity: "Clip", id: clipID.rawValue)
        }
        previousOffset = timeline.clips[index].offset
        timeline.clips[index].offset = newOffset
    }

    public func revert(from timeline: inout Timeline) throws {
        guard let previousOffset,
              let index = timeline.clips.firstIndex(where: { $0.id == clipID }) else {
            throw StudioError.invariant(detail: "MoveClipCommand cannot revert")
        }
        timeline.clips[index].offset = previousOffset
    }
}

/// Trims a clip's source range (in/out points).
public final class TrimClipCommand: EditCommand, @unchecked Sendable {
    public let name = "Trim Clip"
    public let clipID: ClipID
    public let newRange: TimeRange
    private var previousRange: TimeRange?

    public init(clipID: ClipID, to newRange: TimeRange) {
        self.clipID = clipID
        self.newRange = newRange
    }

    public func apply(to timeline: inout Timeline) throws {
        guard let index = timeline.clips.firstIndex(where: { $0.id == clipID }) else {
            throw StudioError.notFound(entity: "Clip", id: clipID.rawValue)
        }
        guard !newRange.duration.isZero else {
            throw StudioError.invalidInput(field: "newRange", reason: "trim to zero duration")
        }
        previousRange = timeline.clips[index].sourceRange
        timeline.clips[index].sourceRange = newRange
    }

    public func revert(from timeline: inout Timeline) throws {
        guard let previousRange,
              let index = timeline.clips.firstIndex(where: { $0.id == clipID }) else {
            throw StudioError.invariant(detail: "TrimClipCommand cannot revert")
        }
        timeline.clips[index].sourceRange = previousRange
    }
}

/// Renames a clip.
public final class RenameClipCommand: EditCommand, @unchecked Sendable {
    public let name = "Rename Clip"
    public let clipID: ClipID
    public let newName: String
    private var previousName: String?

    public init(clipID: ClipID, to newName: String) {
        self.clipID = clipID
        self.newName = newName
    }

    public func apply(to timeline: inout Timeline) throws {
        guard let index = timeline.clips.firstIndex(where: { $0.id == clipID }) else {
            throw StudioError.notFound(entity: "Clip", id: clipID.rawValue)
        }
        previousName = timeline.clips[index].name
        timeline.clips[index].name = newName
    }

    public func revert(from timeline: inout Timeline) throws {
        guard let previousName,
              let index = timeline.clips.firstIndex(where: { $0.id == clipID }) else {
            throw StudioError.invariant(detail: "RenameClipCommand cannot revert")
        }
        timeline.clips[index].name = previousName
    }
}

/// Appends a caption; revert removes the last matching caption.
public struct AddCaptionCommand: EditCommand {
    public let name = "Add Caption"
    public let caption: Caption

    public init(caption: Caption) { self.caption = caption }

    public func apply(to timeline: inout Timeline) throws {
        timeline.captions.append(caption)
    }

    public func revert(from timeline: inout Timeline) throws {
        guard let index = timeline.captions.lastIndex(of: caption) else {
            throw StudioError.notFound(entity: "Caption", id: caption.text)
        }
        timeline.captions.remove(at: index)
    }
}

/// Appends a marker; revert removes the last matching marker.
public struct AddMarkerCommand: EditCommand {
    public let name = "Add Marker"
    public let marker: Marker

    public init(marker: Marker) { self.marker = marker }

    public func apply(to timeline: inout Timeline) throws {
        timeline.markers.append(marker)
    }

    public func revert(from timeline: inout Timeline) throws {
        guard let index = timeline.markers.lastIndex(of: marker) else {
            throw StudioError.notFound(entity: "Marker", id: marker.text)
        }
        timeline.markers.remove(at: index)
    }
}
