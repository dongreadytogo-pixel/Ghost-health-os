import Foundation
import GhostlyCore

/// Onset/beat detection from an audio energy envelope.
///
/// Algorithm: short-window energy → positive energy flux (half-wave
/// rectified derivative) → peaks above a moving adaptive threshold, with a
/// refractory period so one drum hit yields one beat. From the detected
/// onsets a tempo estimate is derived via inter-onset-interval clustering.
public struct BeatDetector: Sendable {
    /// Analysis window (seconds). 1024 samples @ 44.1 kHz ≈ 23 ms is typical.
    public var windowDuration: Double
    /// Multiplier over the local mean flux a peak must exceed.
    public var sensitivity: Double
    /// Minimum spacing between reported beats.
    public var refractoryPeriod: Double

    public init(windowDuration: Double = 0.023, sensitivity: Double = 1.5,
                refractoryPeriod: Double = 0.25) {
        self.windowDuration = windowDuration
        self.sensitivity = sensitivity
        self.refractoryPeriod = refractoryPeriod
    }

    public struct Result: Sendable, Equatable {
        public let beats: [RationalTime]
        /// Estimated tempo in beats per minute; nil when too few onsets.
        public let bpm: Double?
    }

    public func detect(samples: [Float], sampleRate: Int) -> Result {
        guard sampleRate > 0 else { return Result(beats: [], bpm: nil) }
        let windowSize = max(1, Int(Double(sampleRate) * windowDuration))
        guard samples.count >= windowSize * 4 else { return Result(beats: [], bpm: nil) }

        // 1. Window energies.
        var energies: [Double] = []
        var index = 0
        while index + windowSize <= samples.count {
            var sum = 0.0
            for i in index..<(index + windowSize) {
                let v = Double(samples[i])
                sum += v * v
            }
            energies.append(sum)
            index += windowSize
        }

        // 2. Half-wave-rectified flux.
        var flux: [Double] = [0]
        for i in 1..<energies.count {
            flux.append(max(0, energies[i] - energies[i - 1]))
        }

        // 3. Adaptive threshold: mean of a centred neighbourhood × sensitivity.
        let neighbourhood = 10
        let windowSeconds = Double(windowSize) / Double(sampleRate)
        let refractoryWindows = Int(refractoryPeriod / windowSeconds)
        var beats: [RationalTime] = []
        var lastBeatWindow = -refractoryWindows - 1
        for i in flux.indices {
            let lo = max(0, i - neighbourhood)
            let hi = min(flux.count - 1, i + neighbourhood)
            let localMean = flux[lo...hi].reduce(0, +) / Double(hi - lo + 1)
            let isPeak = flux[i] > localMean * sensitivity
                && flux[i] > 1e-9
                && (i == 0 || flux[i] >= flux[i - 1])
                && (i == flux.count - 1 || flux[i] >= flux[i + 1])
            if isPeak, i - lastBeatWindow > refractoryWindows {
                beats.append(RationalTime(value: Int64(i * windowSize), timescale: Int32(sampleRate)))
                lastBeatWindow = i
            }
        }

        return Result(beats: beats, bpm: estimateBPM(beats: beats))
    }

    /// Median inter-onset interval → BPM, folded into the 60–180 range
    /// (half/double-time ambiguity is resolved toward the musical middle).
    func estimateBPM(beats: [RationalTime]) -> Double? {
        guard beats.count >= 4 else { return nil }
        var intervals = zip(beats.dropFirst(), beats).map { ($0 - $1).seconds }
        intervals.sort()
        let median = intervals[intervals.count / 2]
        guard median > 0 else { return nil }
        var bpm = 60.0 / median
        while bpm < 60 { bpm *= 2 }
        while bpm > 180 { bpm /= 2 }
        return bpm
    }
}

/// Scene-change detection from per-frame feature vectors (e.g. luma
/// histograms produced by any frame source — AVFoundation, FFmpeg, tests).
public struct SceneChangeDetector: Sendable {
    /// Normalized histogram distance (0…1) above which a cut is reported.
    public var threshold: Double
    /// Minimum scene length; cuts closer than this to the previous one are ignored.
    public var minimumSceneDuration: Double

    public init(threshold: Double = 0.35, minimumSceneDuration: Double = 0.5) {
        self.threshold = threshold
        self.minimumSceneDuration = minimumSceneDuration
    }

    /// - Parameters:
    ///   - histograms: one normalized (sums to 1) histogram per sampled frame.
    ///   - frameTimes: timestamp of each histogram, same count.
    public func cuts(histograms: [[Double]], frameTimes: [RationalTime]) -> [RationalTime] {
        precondition(histograms.count == frameTimes.count, "histogram/time count mismatch")
        guard histograms.count > 1 else { return [] }
        var out: [RationalTime] = []
        var lastCut: RationalTime? = nil
        for i in 1..<histograms.count {
            let distance = l1Distance(histograms[i], histograms[i - 1]) / 2 // 0…1
            guard distance >= threshold else { continue }
            let time = frameTimes[i]
            if let last = lastCut, (time - last).seconds < minimumSceneDuration { continue }
            out.append(time)
            lastCut = time
        }
        return out
    }

    /// Scene ranges implied by the cuts over `[0, duration)`.
    public func scenes(cuts: [RationalTime], duration: RationalTime) -> [TimeRange] {
        var boundaries = [RationalTime.zero] + cuts.sorted() + [duration]
        boundaries = boundaries.filter { $0 <= duration }
        var out: [TimeRange] = []
        for (a, b) in zip(boundaries, boundaries.dropFirst()) where b > a {
            out.append(TimeRange(start: a, end: b))
        }
        return out
    }

    private func l1Distance(_ a: [Double], _ b: [Double]) -> Double {
        var sum = 0.0
        for i in 0..<min(a.count, b.count) {
            sum += abs(a[i] - b[i])
        }
        return sum
    }
}
