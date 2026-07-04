import Foundation
import GhostlyCore

/// Splits an audio signal into speech and silence segments from its RMS
/// envelope. Pure function of samples — no platform dependency — so the same
/// detector runs in tests, on CI, and inside the macOS app.
public struct SilenceDetector: Sendable {
    /// Linear amplitude below which a window counts as silent.
    public var threshold: Double
    /// Analysis window length.
    public var windowDuration: Double
    /// Silences shorter than this are absorbed into surrounding speech
    /// (breathing pauses shouldn't cut a sentence apart).
    public var minimumSilenceDuration: Double
    /// Speech islands shorter than this are treated as noise.
    public var minimumSpeechDuration: Double

    public init(threshold: Double = 0.02, windowDuration: Double = 0.05,
                minimumSilenceDuration: Double = 0.35, minimumSpeechDuration: Double = 0.2) {
        self.threshold = threshold
        self.windowDuration = windowDuration
        self.minimumSilenceDuration = minimumSilenceDuration
        self.minimumSpeechDuration = minimumSpeechDuration
    }

    public struct Segment: Equatable, Sendable {
        public let range: TimeRange
        public let isSpeech: Bool

        public init(range: TimeRange, isSpeech: Bool) {
            self.range = range
            self.isSpeech = isSpeech
        }
    }

    /// - Parameters:
    ///   - samples: mono PCM samples in −1…1.
    ///   - sampleRate: samples per second.
    public func segments(samples: [Float], sampleRate: Int) -> [Segment] {
        guard !samples.isEmpty, sampleRate > 0 else { return [] }
        let windowSize = max(1, Int(Double(sampleRate) * windowDuration))
        let timescale = Int32(sampleRate)

        // 1. Classify each window by RMS.
        var flags: [Bool] = [] // true = speech
        var index = 0
        while index < samples.count {
            let end = min(index + windowSize, samples.count)
            var sum = 0.0
            for i in index..<end {
                let v = Double(samples[i])
                sum += v * v
            }
            let rms = (sum / Double(end - index)).squareRoot()
            flags.append(rms >= threshold)
            index = end
        }

        // 2. Merge consecutive windows into runs.
        var runs: [(isSpeech: Bool, windows: Int)] = []
        for flag in flags {
            if runs.last?.isSpeech == flag {
                runs[runs.count - 1].windows += 1
            } else {
                runs.append((flag, 1))
            }
        }

        // 3. Absorb runs shorter than the configured minimums.
        let windowSeconds = Double(windowSize) / Double(sampleRate)
        var changed = true
        while changed && runs.count > 1 {
            changed = false
            for i in runs.indices {
                let seconds = Double(runs[i].windows) * windowSeconds
                let tooShort = runs[i].isSpeech
                    ? seconds < minimumSpeechDuration
                    : seconds < minimumSilenceDuration
                if tooShort {
                    runs[i].isSpeech.toggle()
                    // Re-merge neighbours.
                    var merged: [(isSpeech: Bool, windows: Int)] = []
                    for run in runs {
                        if merged.last?.isSpeech == run.isSpeech {
                            merged[merged.count - 1].windows += run.windows
                        } else {
                            merged.append(run)
                        }
                    }
                    runs = merged
                    changed = true
                    break
                }
            }
        }

        // 4. Emit segments with exact rational boundaries.
        var out: [Segment] = []
        var windowCursor = 0
        for run in runs {
            let start = RationalTime(value: Int64(windowCursor * windowSize), timescale: timescale)
            let endSample = min((windowCursor + run.windows) * windowSize, samples.count)
            let end = RationalTime(value: Int64(endSample), timescale: timescale)
            if end > start {
                out.append(Segment(range: TimeRange(start: start, end: end), isSpeech: run.isSpeech))
            }
            windowCursor += run.windows
        }
        return out
    }

    /// Only the speech portions — what an auto-editor keeps.
    public func speechRanges(samples: [Float], sampleRate: Int) -> [TimeRange] {
        segments(samples: samples, sampleRate: sampleRate)
            .filter(\.isSpeech).map(\.range)
    }
}
