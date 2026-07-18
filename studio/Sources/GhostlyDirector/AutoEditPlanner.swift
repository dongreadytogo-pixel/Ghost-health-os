import Foundation
import GhostlyCore
import GhostlyDomain
import GhostlyDetection
import GhostlySubtitles
import GhostlyAudio

/// Turns media analysis + a pacing profile into a finished timeline: the
/// heart of "AI auto editing". Deterministic and pure — same inputs, same
/// edit — which makes edits reproducible and testable.
public struct AutoEditPlanner: Sendable {
    public var profile: PacingProfile

    public init(profile: PacingProfile) {
        self.profile = profile
    }

    /// Builds a timeline from analyzed footage.
    ///
    /// - Parameters:
    ///   - footage: assets with their analyses, in narrative order.
    ///   - music: optional music asset (with beat analysis) laid under the cut.
    ///   - transcript: optional subtitle track to attach as captions.
    ///   - projectName: name for the resulting timeline.
    public func plan(footage: [(asset: Asset, analysis: MediaAnalysis)],
                     music: (asset: Asset, analysis: MediaAnalysis)? = nil,
                     transcript: SubtitleTrack? = nil,
                     projectName: String = "AI Edit") throws -> Timeline {
        guard !footage.isEmpty else {
            throw StudioError.invalidInput(field: "footage", reason: "no assets to edit")
        }
        var timeline = Timeline(name: projectName, format: profile.format)
        let frameRate = profile.format.frameRate

        // 1. Collect keepable source ranges (speech, or whole scenes when no speech).
        for (asset, analysis) in footage {
            let keeps = keepRanges(for: analysis)
            for keep in keeps {
                // 2. Chop ranges longer than maxShotLength into profile-sized shots.
                for shot in shots(from: keep) {
                    let snappedStart = frameRate.snapped(shot.start)
                    let snappedDuration = frameRate.snapped(shot.duration)
                    guard snappedDuration.seconds >= max(0.2, profile.minShotLength * 0.5) else { continue }
                    timeline.appendToStoryline(
                        assetID: asset.id, name: asset.name,
                        sourceRange: TimeRange(start: snappedStart, duration: snappedDuration))
                }
            }
        }

        guard !timeline.clips.isEmpty else {
            throw StudioError.validationFailure(detail: "no usable segments found in footage")
        }

        // 2b. Length cap ("ความยาวเหลือไม่เกิน 3 นาที"): keep the
        // highest-scoring shots that fit the budget, chronological order
        // preserved. Scoring prefers interesting sentences when the command
        // asked to (เน้นประโยคสำคัญ).
        if let budget = profile.maxTotalDuration,
           timeline.duration.seconds > budget {
            applyDurationBudget(&timeline, budget: budget,
                                footage: footage, transcript: transcript)
        }

        // 3. Beat alignment: nudge cut points onto the nearest music beat.
        if profile.cutOnBeats, let music, !music.analysis.beats.isEmpty {
            alignCutsToBeats(&timeline, beats: music.analysis.beats, frameRate: frameRate)
        }

        // 4. Transitions.
        if let transitionName = profile.transitionName, profile.transitionDuration > 0 {
            addTransitions(&timeline, name: transitionName,
                           duration: RationalTime(seconds: profile.transitionDuration,
                                                  preferredTimescale: Int32(frameRate.frames)))
        }

        // 5. Music bed on the lane below, trimmed to the edit, ducked under
        // the storyline (which carries the narration after silence removal).
        // Keyframe gains bake the 0.35 bed level in, so the flat `volume`
        // stays the fallback for apps that ignore automation.
        if let music {
            let duration = min(timeline.duration, music.asset.duration)
            let bedLevel = 0.35
            let ducking = MusicDucking(duckDB: -9, fadeSeconds: 0.4)
            let keyframes = ducking
                .envelope(speechRanges: timeline.storyline.map(\.timelineRange),
                          duration: duration)
                .map { VolumeKeyframe(time: $0.time, gain: $0.gain * bedLevel) }
            timeline.clips.append(Clip(
                assetID: music.asset.id, name: music.asset.name,
                offset: .zero,
                sourceRange: TimeRange(start: .zero, duration: duration),
                lane: -1, role: .music, volume: bedLevel,
                volumeKeyframes: keyframes))
            for beat in music.analysis.beats where beat < timeline.duration {
                timeline.markers.append(Marker(start: beat, text: "beat"))
            }
        }

        // 6. Captions from the transcript.
        if let transcript {
            let styled: SubtitleTrack
            if let styleName = profile.captionStyleName,
               let style = CaptionStyle.named(styleName) {
                styled = style.styled(transcript)
            } else {
                styled = transcript
            }
            timeline.captions = styled
                .captions(styleName: profile.captionStyleName)
                .filter { $0.range.start < timeline.duration }
        }

        return timeline
    }

    // MARK: Steps

    /// Speech ranges thinned by the profile's silence-removal factor; falls
    /// back to scene ranges, then the whole asset.
    func keepRanges(for analysis: MediaAnalysis) -> [TimeRange] {
        if !analysis.speechRanges.isEmpty {
            if profile.silenceRemoval >= 1 { return analysis.speechRanges }
            // Partial removal: extend each speech range by a share of the
            // following silence so the cut keeps some breathing room.
            var out: [TimeRange] = []
            for (index, range) in analysis.speechRanges.enumerated() {
                let nextStart = index + 1 < analysis.speechRanges.count
                    ? analysis.speechRanges[index + 1].start
                    : analysis.duration
                let silence = nextStart - range.end
                guard !silence.isNegative else {
                    out.append(range)
                    continue
                }
                let keptSilence = silence.scaled(by: Int((1 - profile.silenceRemoval) * 100), over: 100)
                out.append(TimeRange(start: range.start, duration: range.duration + keptSilence))
            }
            return out
        }
        if !analysis.sceneCuts.isEmpty {
            return SceneChangeDetector().scenes(cuts: analysis.sceneCuts, duration: analysis.duration)
        }
        return [TimeRange(start: .zero, duration: analysis.duration)]
    }

    /// Splits a source range into shots within the profile's length band.
    func shots(from range: TimeRange) -> [TimeRange] {
        let maxLen = profile.maxShotLength
        if range.duration.seconds <= maxLen { return [range] }
        var out: [TimeRange] = []
        var cursor = range.start
        let shotDuration = RationalTime(seconds: maxLen, preferredTimescale: 48_000)
        while cursor < range.end {
            let remaining = range.end - cursor
            let d = min(shotDuration, remaining)
            // Avoid a stub shorter than minShotLength at the end: fold it in.
            if (remaining - d).seconds < profile.minShotLength && remaining.seconds <= maxLen * 1.5 {
                out.append(TimeRange(start: cursor, duration: remaining))
                break
            }
            out.append(TimeRange(start: cursor, duration: d))
            cursor = cursor + d
        }
        return out
    }

    /// Keeps the best storyline shots that fit `budget` seconds: each shot is
    /// scored like a highlight (beat energy, scene activity, transcript
    /// emphasis — weighted higher with `emphasizeHighlights`), picked greedily
    /// by score, then laid back down in chronological order. When even the
    /// single best shot exceeds the budget it is trimmed to fit.
    func applyDurationBudget(_ timeline: inout Timeline, budget: Double,
                             footage: [(asset: Asset, analysis: MediaAnalysis)],
                             transcript: SubtitleTrack?) {
        let analyses = Dictionary(uniqueKeysWithValues: footage.map { ($0.asset.id, $0.analysis) })
        let story = timeline.storyline
        guard !story.isEmpty, budget > 0 else { return }

        // Rank shots by score (ties → earlier shot wins, keeping the hook).
        let scored = story.enumerated().map { index, clip in
            (index: index, clip: clip,
             score: shotScore(clip, analysis: analyses[clip.assetID], transcript: transcript))
        }.sorted { $0.score == $1.score ? $0.index < $1.index : $0.score > $1.score }

        var keptIndices: [Int] = []
        var remaining = budget
        for candidate in scored where candidate.clip.duration.seconds <= remaining {
            keptIndices.append(candidate.index)
            remaining -= candidate.clip.duration.seconds
        }
        if keptIndices.isEmpty, let best = scored.first {
            // Nothing fits whole: trim the strongest shot to the budget.
            var clip = best.clip
            let trimmed = RationalTime(seconds: budget, preferredTimescale: 48_000)
            clip.sourceRange = TimeRange(start: clip.sourceRange.start,
                                         duration: min(clip.sourceRange.duration, trimmed))
            keptIndices = [best.index]
            timeline.clips = [clip] + timeline.connectedClips
        } else {
            let keep = Set(keptIndices)
            timeline.clips = story.enumerated()
                .filter { keep.contains($0.offset) }
                .map(\.element) + timeline.connectedClips
        }

        // Re-lay the surviving shots back to back.
        var cursor = RationalTime.zero
        var relaid = timeline.storyline
        for index in relaid.indices {
            relaid[index].offset = cursor
            cursor = cursor + relaid[index].duration
        }
        timeline.clips = relaid + timeline.connectedClips
    }

    /// Highlight-style score for one storyline shot, in its source timebase.
    private func shotScore(_ clip: Clip, analysis: MediaAnalysis?,
                           transcript: SubtitleTrack?) -> Double {
        let window = clip.sourceRange
        let length = window.duration.seconds
        guard length > 0 else { return 0 }
        var score = 0.0
        if let analysis {
            let beats = analysis.beats.filter { window.contains($0) }.count
            score += min(1, Double(beats) / (length * 2)) * 0.3
            if analysis.sceneCuts.contains(where: { window.contains($0) }) { score += 0.15 }
        }
        if let transcript {
            let hits = transcript.cues.filter { $0.range.overlaps(window) }
            let emphasisWeight = profile.emphasizeHighlights ? 0.6 : 0.25
            if hits.contains(where: { $0.text.contains("!") || $0.text.contains("?") }) {
                score += emphasisWeight
            }
            // Longer sentences over a shot ≈ denser narration: small boost,
            // stronger when the command asked for the key sentences.
            let coverage = hits.reduce(0.0) {
                $0 + ($1.range.intersection(window)?.duration.seconds ?? 0)
            } / length
            score += min(1, coverage) * (profile.emphasizeHighlights ? 0.4 : 0.2)
        }
        // Slight early bonus keeps openings competitive on ties.
        score += max(0, 0.1 - Double(clip.offset.seconds) * 0.001)
        return score
    }

    /// Retimes storyline clips so each cut lands on the nearest beat, within
    /// the profile's shot-length constraints.
    func alignCutsToBeats(_ timeline: inout Timeline, beats: [RationalTime], frameRate: FrameRate) {
        let sortedBeats = beats.sorted()
        var story = timeline.storyline
        guard story.count > 1 else { return }
        var cursor = RationalTime.zero
        for index in story.indices {
            var clip = story[index]
            clip.offset = cursor
            var end = cursor + clip.duration
            // Snap this cut to the nearest beat if the resulting shot stays legal.
            if index < story.count - 1,
               let beat = nearestBeat(to: end, in: sortedBeats) {
                let snapped = frameRate.snapped(beat)
                let newDuration = snapped - cursor
                if newDuration.seconds >= profile.minShotLength * 0.75,
                   newDuration.seconds <= profile.maxShotLength * 1.25,
                   newDuration <= clip.sourceRange.duration + (clip.sourceRange.duration.scaled(by: 1, over: 4)) {
                    let clamped = min(newDuration, clip.sourceRange.duration)
                    clip.sourceRange = TimeRange(start: clip.sourceRange.start, duration: clamped)
                    end = cursor + clamped
                }
            }
            story[index] = clip
            cursor = end
        }
        timeline.clips = story + timeline.connectedClips
    }

    private func nearestBeat(to time: RationalTime, in beats: [RationalTime]) -> RationalTime? {
        beats.min { abs(($0 - time).seconds) < abs(($1 - time).seconds) }
    }

    /// Inserts a transition at every interior cut.
    func addTransitions(_ timeline: inout Timeline, name: String, duration: RationalTime) {
        let story = timeline.storyline
        guard story.count > 1 else { return }
        timeline.transitions = story.dropFirst().compactMap { clip in
            // The transition needs media handles on both sides; skip cuts
            // where either clip is shorter than the transition.
            guard clip.duration > duration else { return nil }
            if name == "Cross Dissolve" {
                return .crossDissolve(offset: clip.offset, duration: duration)
            }
            return Transition(name: name, offset: clip.offset, duration: duration)
        }
    }
}
