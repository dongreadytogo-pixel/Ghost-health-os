import Foundation
import GhostlyCore

/// Music ducking: lowers the music bed while someone speaks and eases it
/// back between sentences. Consumes the same speech ranges the silence
/// detector produces and yields a piecewise-linear gain envelope — the exact
/// shape FCPXML volume keyframes and audio renderers both want.
public struct MusicDucking: Sendable {
    /// Gain applied to music under speech, in dB (negative = quieter).
    public var duckDB: Double
    /// Ramp length into/out of each duck.
    public var fadeSeconds: Double
    /// Speech ranges closer than this merge into one duck (no pumping
    /// between sentences).
    public var mergeGapSeconds: Double

    public init(duckDB: Double = -12, fadeSeconds: Double = 0.3, mergeGapSeconds: Double = 1.0) {
        self.duckDB = duckDB
        self.fadeSeconds = fadeSeconds
        self.mergeGapSeconds = mergeGapSeconds
    }

    public struct Keyframe: Sendable, Equatable {
        public let time: RationalTime
        /// Linear gain 0…1.
        public let gain: Double

        public init(time: RationalTime, gain: Double) {
            self.time = time
            self.gain = gain
        }
    }

    /// Piecewise-linear envelope over `duration`: 1.0 outside speech,
    /// `duckDB` (as linear gain) inside, linear ramps of `fadeSeconds` at
    /// each edge, clamped to the clip bounds. Keyframe times are the ramp
    /// corners; gains are evaluated analytically, so clamping at the clip
    /// edges can never produce contradictory keys. Empty speech yields a
    /// flat unity envelope.
    public func envelope(speechRanges: [TimeRange], duration: RationalTime) -> [Keyframe] {
        let merged = Self.merge(speechRanges.filter { $0.start < duration },
                                gapSeconds: mergeGapSeconds)
        let total = duration.seconds
        var times: Set<Double> = [0, total]
        for range in merged {
            for t in [range.start.seconds - fadeSeconds,
                      range.start.seconds,
                      min(range.end.seconds, total),
                      range.end.seconds + fadeSeconds] {
                times.insert(max(0, min(t, total)))
            }
        }
        return times.sorted().map { seconds in
            Keyframe(time: RationalTime(seconds: seconds, preferredTimescale: 48_000),
                     gain: gainValue(atSeconds: seconds, merged: merged))
        }
    }

    /// Analytic gain at a time: the minimum over all ducks' local shapes.
    private func gainValue(atSeconds t: Double, merged: [TimeRange]) -> Double {
        let duckGain = pow(10, duckDB / 20)
        var gain = 1.0
        for range in merged {
            let start = range.start.seconds
            let end = range.end.seconds
            let local: Double
            if t < start - fadeSeconds || t > end + fadeSeconds {
                local = 1
            } else if t < start, fadeSeconds > 0 {
                let progress = (t - (start - fadeSeconds)) / fadeSeconds
                local = 1 + (duckGain - 1) * progress
            } else if t > end, fadeSeconds > 0 {
                let progress = (t - end) / fadeSeconds
                local = duckGain + (1 - duckGain) * progress
            } else {
                local = duckGain
            }
            gain = min(gain, local)
        }
        return gain
    }

    /// Linear-interpolated gain at a point (for renderers and tests).
    public static func gain(at time: RationalTime, in envelope: [Keyframe]) -> Double {
        guard let first = envelope.first else { return 1 }
        if time <= first.time { return first.gain }
        for (a, b) in zip(envelope, envelope.dropFirst()) where time <= b.time {
            let span = (b.time - a.time).seconds
            guard span > 0 else { return b.gain }
            let t = (time - a.time).seconds / span
            return a.gain + (b.gain - a.gain) * t
        }
        return envelope.last?.gain ?? 1
    }

    /// Renders the envelope onto music samples (mono PCM).
    public func applied(to samples: [Float], sampleRate: Int,
                        speechRanges: [TimeRange]) -> [Float] {
        guard !samples.isEmpty, sampleRate > 0 else { return samples }
        let duration = RationalTime(value: Int64(samples.count), timescale: Int32(sampleRate))
        let env = envelope(speechRanges: speechRanges, duration: duration)
        var out = samples
        for index in out.indices {
            let t = RationalTime(value: Int64(index), timescale: Int32(sampleRate))
            out[index] = Float(Double(out[index]) * Self.gain(at: t, in: env))
        }
        return out
    }

    /// Merges ranges separated by less than `gapSeconds`.
    static func merge(_ ranges: [TimeRange], gapSeconds: Double) -> [TimeRange] {
        let sorted = ranges.sorted { $0.start < $1.start }
        var out: [TimeRange] = []
        for range in sorted {
            if let last = out.last,
               (range.start - last.end).seconds < gapSeconds {
                out[out.count - 1] = TimeRange(start: last.start,
                                               end: max(last.end, range.end))
            } else {
                out.append(range)
            }
        }
        return out
    }
}
