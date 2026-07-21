import Foundation
import GhostlyCore
import GhostlyDomain

/// Pure presentation model for the timeline inspector (M2): everything a
/// view needs to draw a `Timeline` — lanes of clip blocks, caption chips,
/// marker flags, and ruler ticks — as plain data with geometry normalized
/// to 0…1 of the timeline width. No SwiftUI, no platform types: computed
/// and tested on CI, rendered by a dumb view on macOS.
public struct TimelineViewModel: Sendable, Equatable {
    public struct ClipBlock: Sendable, Equatable, Identifiable {
        public let id: ClipID
        public let name: String
        /// Normalized 0…1 position and width on the timeline.
        public let x: Double
        public let width: Double
        public let roleName: String
        public let volume: Double
        public let hasVolumeAutomation: Bool
    }

    public struct Lane: Sendable, Equatable {
        /// 0 = primary storyline; positive above, negative below.
        public let index: Int
        public let blocks: [ClipBlock]
    }

    public struct CaptionChip: Sendable, Equatable {
        public let text: String
        public let x: Double
        public let width: Double
        public let speaker: String?
        public let language: String
    }

    public struct MarkerFlag: Sendable, Equatable {
        public let x: Double
        public let text: String
    }

    public struct RulerTick: Sendable, Equatable {
        public let x: Double
        /// "m:ss" label, e.g. "1:05".
        public let label: String
    }

    public let name: String
    public let durationSeconds: Double
    public let isVertical: Bool
    /// Sorted top-to-bottom: highest lane first, music lanes last.
    public let lanes: [Lane]
    public let captions: [CaptionChip]
    public let markers: [MarkerFlag]
    public let ticks: [RulerTick]

    public init(timeline: Timeline) {
        name = timeline.name
        let total = max(timeline.duration.seconds, 0.001)
        durationSeconds = timeline.duration.seconds
        isVertical = timeline.format.isVertical

        func normalized(_ range: TimeRange) -> (x: Double, width: Double) {
            let x = min(max(range.start.seconds / total, 0), 1)
            let width = min(max(range.duration.seconds / total, 0), 1 - x)
            return (x, width)
        }

        var byLane: [Int: [ClipBlock]] = [:]
        for clip in timeline.clips {
            let geo = normalized(clip.timelineRange)
            byLane[clip.lane, default: []].append(ClipBlock(
                id: clip.id, name: clip.name, x: geo.x, width: geo.width,
                roleName: clip.role.name, volume: clip.volume,
                hasVolumeAutomation: !clip.volumeKeyframes.isEmpty))
        }
        lanes = byLane.keys.sorted(by: >).map { index in
            Lane(index: index,
                 blocks: byLane[index]!.sorted { $0.x < $1.x })
        }

        captions = timeline.captions.map { caption in
            let geo = normalized(caption.range)
            return CaptionChip(text: caption.text, x: geo.x, width: geo.width,
                               speaker: caption.speaker, language: caption.language)
        }

        markers = timeline.markers.map {
            MarkerFlag(x: min(max($0.start.seconds / total, 0), 1), text: $0.text)
        }

        ticks = Self.rulerTicks(durationSeconds: timeline.duration.seconds)
    }

    /// Picks a readable tick interval (at most ~8 divisions) and lays out
    /// "m:ss" labels; an empty timeline gets a lone zero tick.
    static func rulerTicks(durationSeconds: Double) -> [RulerTick] {
        guard durationSeconds > 0 else { return [RulerTick(x: 0, label: "0:00")] }
        let candidates: [Double] = [1, 2, 5, 10, 15, 30, 60, 120, 300, 600]
        let interval = candidates.first { durationSeconds / $0 <= 8 } ?? 600
        var out: [RulerTick] = []
        var t = 0.0
        while t <= durationSeconds {
            let minutes = Int(t) / 60
            let seconds = Int(t) % 60
            out.append(RulerTick(x: t / durationSeconds,
                                 label: String(format: "%d:%02d", minutes, seconds)))
            t += interval
        }
        return out
    }
}
