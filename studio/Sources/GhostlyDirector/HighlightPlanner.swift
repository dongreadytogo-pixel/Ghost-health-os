import Foundation
import GhostlyCore
import GhostlyDomain
import GhostlyDetection
import GhostlySubtitles

/// A notable moment discovered in analyzed footage.
public struct Highlight: Sendable, Equatable {
    public enum Kind: String, Sendable {
        /// The strongest opening moment — what a short should lead with.
        case hook
        /// A generally high-energy segment worth keeping.
        case highlight
        /// A synthesized call-to-action beat near the end.
        case cta
    }

    public let range: TimeRange
    public let kind: Kind
    /// Relative strength in 0…1.
    public let score: Double
    public let label: String

    public init(range: TimeRange, kind: Kind, score: Double, label: String) {
        self.range = range
        self.kind = kind
        self.score = score
        self.label = label
    }
}

/// Finds hooks, highlights, and chapter boundaries from media analysis and an
/// optional transcript — the engine behind "find the best moments",
/// "auto-chapter this", and short-form hook selection (Phase 7).
///
/// Deterministic: identical analysis yields identical highlights.
public struct HighlightPlanner: Sendable {
    /// Sliding scoring window length (seconds).
    public var windowDuration: Double
    /// Minimum gap between reported highlights (seconds).
    public var minimumSpacing: Double
    /// Minimum chapter length (seconds).
    public var minimumChapterDuration: Double

    public init(windowDuration: Double = 5, minimumSpacing: Double = 8,
                minimumChapterDuration: Double = 10) {
        self.windowDuration = windowDuration
        self.minimumSpacing = minimumSpacing
        self.minimumChapterDuration = minimumChapterDuration
    }

    // MARK: Highlights

    /// Ranks the top `limit` moments. The earliest strong highlight inside the
    /// first third is promoted to a `hook`; a `cta` is appended near the end.
    public func highlights(from analysis: MediaAnalysis,
                           transcript: SubtitleTrack? = nil,
                           visual: VisualDetectionAggregator.Summary? = nil,
                           limit: Int = 5) -> [Highlight] {
        let total = analysis.duration.seconds
        guard total > 0 else { return [] }

        let window = min(windowDuration, total)
        let step = max(window / 2, 0.5)
        var scored: [(start: Double, score: Double)] = []
        var t = 0.0
        while t < total {
            let end = min(t + window, total)
            scored.append((t, score(from: t, to: end, analysis: analysis,
                                    transcript: transcript, visual: visual)))
            t += step
        }

        // Greedy non-overlapping selection by descending score.
        let ranked = scored.filter { $0.score > 0 }.sorted { $0.score > $1.score }
        var picked: [(start: Double, score: Double)] = []
        for candidate in ranked {
            guard picked.allSatisfy({ abs($0.start - candidate.start) >= minimumSpacing })
            else { continue }
            picked.append(candidate)
            if picked.count >= limit { break }
        }
        picked.sort { $0.start < $1.start }

        let maxScore = picked.map(\.score).max() ?? 1
        var out: [Highlight] = picked.map { item in
            let range = timeRange(item.start, min(item.start + window, total))
            return Highlight(range: range, kind: .highlight,
                             score: normalize(item.score, max: maxScore),
                             label: labelForTime(item.start, transcript: transcript) ?? "Highlight")
        }

        // Promote the earliest strong moment in the first third to a hook.
        if let hookIndex = out.firstIndex(where: { $0.range.start.seconds <= total / 3 }) {
            let h = out[hookIndex]
            out[hookIndex] = Highlight(range: h.range, kind: .hook, score: h.score,
                                       label: "Hook: \(h.label)")
        }

        // Synthesize a CTA in the final window.
        let ctaStart = max(0, total - window)
        out.append(Highlight(range: timeRange(ctaStart, total), kind: .cta,
                             score: 0.5, label: "Call to action"))
        return out
    }

    // MARK: Chapters

    /// Derives chapter markers from scene cuts (falling back to even spacing
    /// over speech when there are no cuts), enforcing a minimum chapter length.
    public func chapters(from analysis: MediaAnalysis,
                         transcript: SubtitleTrack? = nil) -> [Marker] {
        let total = analysis.duration.seconds
        guard total > 0 else { return [] }

        var boundaries: [Double] = [0]
        for cut in analysis.sceneCuts.map(\.seconds).sorted() {
            if let last = boundaries.last, cut - last >= minimumChapterDuration, cut < total {
                boundaries.append(cut)
            }
        }
        // Fallback: no usable cuts → split into even chapters of ~minChapter*3.
        if boundaries.count == 1 && total > minimumChapterDuration * 2 {
            let chapterLength = max(minimumChapterDuration * 3, total / 6)
            var t = chapterLength
            while t < total - minimumChapterDuration {
                boundaries.append(t)
                t += chapterLength
            }
        }

        return boundaries.enumerated().map { index, start in
            let time = RationalTime(seconds: start, preferredTimescale: 48_000)
            let title = labelForTime(start, transcript: transcript) ?? "Chapter \(index + 1)"
            return Marker(start: time, text: title, kind: .chapter)
        }
    }

    /// Adds chapter markers plus hook/highlight markers to a timeline copy.
    public func annotate(_ timeline: Timeline, analysis: MediaAnalysis,
                         transcript: SubtitleTrack? = nil,
                         visual: VisualDetectionAggregator.Summary? = nil) -> Timeline {
        var copy = timeline
        copy.markers.append(contentsOf: chapters(from: analysis, transcript: transcript))
        for highlight in highlights(from: analysis, transcript: transcript, visual: visual)
        where highlight.kind != .cta {
            copy.markers.append(Marker(start: highlight.range.start,
                                       text: highlight.label,
                                       kind: highlight.kind == .hook ? .chapter : .standard))
        }
        return copy
    }

    // MARK: Scoring

    private func score(from start: Double, to end: Double,
                       analysis: MediaAnalysis, transcript: SubtitleTrack?,
                       visual: VisualDetectionAggregator.Summary?) -> Double {
        let window = timeRange(start, end)
        let length = end - start
        guard length > 0 else { return 0 }

        // Speech coverage fraction in this window.
        let speechSeconds = analysis.speechRanges.reduce(0.0) { sum, range in
            sum + (range.intersection(window)?.duration.seconds ?? 0)
        }
        let speechFraction = speechSeconds / length

        // Beat density normalized to ~2 beats/sec being "busy".
        let beats = analysis.beats.filter { window.contains($0) }.count
        let beatDensity = min(1, Double(beats) / (length * 2))

        // Scene activity: a cut inside the window signals visual interest.
        let hasCut = analysis.sceneCuts.contains { window.contains($0) } ? 1.0 : 0.0

        // Transcript emphasis: exclamation/question marks near this time.
        let emphasis = transcript.map { track -> Double in
            let hits = track.cues.filter { window.overlaps($0.range) }
            let punchy = hits.contains { $0.text.contains("!") || $0.text.contains("?") }
            return punchy ? 1 : 0
        } ?? 0

        let base = speechFraction * 0.5 + beatDensity * 0.25 + hasCut * 0.15 + emphasis * 0.1

        // Visual engagement is additive on top of the base signal so it only
        // ever *promotes* a moment (and is a no-op when no vision data exists):
        // a smiling, camera-facing subject is prime highlight/hook material.
        return base + visualBoost(window: window, visual: visual)
    }

    /// 0 when no visual summary; otherwise up to +0.6 for a smiling,
    /// eye-contact, face-present window.
    private func visualBoost(window: TimeRange,
                             visual: VisualDetectionAggregator.Summary?) -> Double {
        guard let visual else { return 0 }
        func overlapsAny(_ ranges: [TimeRange]) -> Bool {
            ranges.contains { $0.overlaps(window) }
        }
        var boost = 0.0
        if overlapsAny(visual.smileRanges) { boost += 0.3 }
        if overlapsAny(visual.eyeContactRanges) { boost += 0.2 }
        if overlapsAny(visual.facePresenceRanges) { boost += 0.1 }
        return boost
    }

    private func labelForTime(_ seconds: Double, transcript: SubtitleTrack?) -> String? {
        guard let track = transcript else { return nil }
        let time = RationalTime(seconds: seconds, preferredTimescale: 1000)
        guard let cue = track.cues.first(where: { $0.range.contains(time) })
            ?? track.cues.first(where: { $0.range.start.seconds >= seconds }) else { return nil }
        let words = cue.text.split(separator: " ").prefix(6).joined(separator: " ")
        return words.isEmpty ? nil : words
    }

    private func normalize(_ value: Double, max: Double) -> Double {
        max > 0 ? min(1, value / max) : 0
    }

    private func timeRange(_ start: Double, _ end: Double) -> TimeRange {
        TimeRange(start: RationalTime(seconds: start, preferredTimescale: 48_000),
                  end: RationalTime(seconds: max(start, end), preferredTimescale: 48_000))
    }
}
