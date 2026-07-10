import Foundation
import GhostlyCore

/// One contiguous stretch of speech attributed to one speaker.
public struct SpeakerTurn: Sendable, Equatable {
    public let range: TimeRange
    /// Stable label in order of first appearance: "S1", "S2", …
    public let speaker: String

    public init(range: TimeRange, speaker: String) {
        self.range = range
        self.speaker = speaker
    }
}

/// Lightweight speaker diarization: attributes each detected speech range to
/// a speaker by clustering per-range voice features (autocorrelation pitch +
/// energy). Pure and deterministic — same audio, same turns — which keeps
/// multi-speaker caption attribution testable on CI. It is intentionally a
/// coarse voice-similarity model, not identification: two very similar
/// voices may merge, which downstream UI can correct.
public struct SpeakerDiarizer: Sendable {
    /// Clusters never exceed this; extra voices fold into the nearest.
    public var maxSpeakers: Int
    /// Feature distance below which a range joins an existing speaker.
    /// Dominated by pitch measured in octaves (0.35 ≈ a third of an octave).
    public var joinThreshold: Double

    public init(maxSpeakers: Int = 4, joinThreshold: Double = 0.35) {
        self.maxSpeakers = maxSpeakers
        self.joinThreshold = joinThreshold
    }

    /// - Parameters:
    ///   - samples: mono PCM in −1…1 (the same buffer the detectors use).
    ///   - sampleRate: samples per second.
    ///   - speechRanges: speech segments, e.g. from `SilenceDetector`.
    public func turns(samples: [Float], sampleRate: Int,
                      speechRanges: [TimeRange]) -> [SpeakerTurn] {
        guard !samples.isEmpty, sampleRate > 0 else { return [] }

        struct Cluster { var pitchLog: Double; var energyLog: Double; var count: Int }
        var clusters: [Cluster] = []
        var out: [SpeakerTurn] = []

        for range in speechRanges {
            let lo = max(0, Int(range.start.seconds * Double(sampleRate)))
            let hi = min(samples.count, Int(range.end.seconds * Double(sampleRate)))
            guard hi > lo else { continue }
            let slice = samples[lo..<hi]
            guard let pitch = Self.fundamental(of: slice, sampleRate: sampleRate) else {
                // Unvoiced/noisy range: attribute to the previous speaker to
                // avoid inventing phantom voices for coughs and claps.
                out.append(SpeakerTurn(range: range, speaker: out.last?.speaker ?? "S1"))
                continue
            }
            let energy = Self.rms(of: slice)
            let pitchLog = log2(pitch)
            let energyLog = log10(max(energy, 1e-6))

            // Nearest cluster by pitch distance (octaves) + damped energy term.
            var bestIndex = -1
            var bestDistance = Double.greatestFiniteMagnitude
            for (index, cluster) in clusters.enumerated() where cluster.count > 0 {
                let distance = abs(cluster.pitchLog - pitchLog)
                    + 0.2 * abs(cluster.energyLog - energyLog)
                if distance < bestDistance {
                    bestDistance = distance
                    bestIndex = index
                }
            }

            let index: Int
            if bestIndex >= 0,
               bestDistance < joinThreshold || clusters.count >= maxSpeakers {
                index = bestIndex
                // Update running centroid.
                let c = clusters[index]
                let n = Double(c.count)
                clusters[index] = Cluster(
                    pitchLog: (c.pitchLog * n + pitchLog) / (n + 1),
                    energyLog: (c.energyLog * n + energyLog) / (n + 1),
                    count: c.count + 1)
            } else {
                clusters.append(Cluster(pitchLog: pitchLog, energyLog: energyLog, count: 1))
                index = clusters.count - 1
            }
            out.append(SpeakerTurn(range: range, speaker: "S\(index + 1)"))
        }
        return out
    }

    /// Number of distinct speakers in a set of turns.
    public static func speakerCount(_ turns: [SpeakerTurn]) -> Int {
        Set(turns.map(\.speaker)).count
    }

    // MARK: Voice features

    /// Fundamental frequency (Hz) via normalized autocorrelation over the
    /// human speech range (70–400 Hz); nil when the range is unvoiced.
    static func fundamental(of slice: ArraySlice<Float>, sampleRate: Int) -> Double? {
        // Analyze up to 4096 samples from the middle of the range, where the
        // voice is steadiest.
        let window = min(4096, slice.count)
        guard window >= sampleRate / 50 else { return nil } // need ≥ 20 ms
        let mid = slice.startIndex + (slice.count - window) / 2
        let x = Array(slice[mid..<(mid + window)]).map(Double.init)

        var energy = 0.0
        for v in x { energy += v * v }
        guard energy > 1e-8 else { return nil }

        let minLag = max(2, sampleRate / 400)
        let maxLag = min(window - 1, sampleRate / 70)
        guard maxLag > minLag else { return nil }

        var bestLag = 0
        var bestScore = 0.0
        for lag in minLag...maxLag {
            var sum = 0.0
            for i in 0..<(window - lag) {
                sum += x[i] * x[i + lag]
            }
            let score = sum / energy
            if score > bestScore {
                bestScore = score
                bestLag = lag
            }
        }
        // A voiced sound correlates strongly with itself one period later.
        guard bestScore > 0.4, bestLag > 0 else { return nil }
        return Double(sampleRate) / Double(bestLag)
    }

    static func rms(of slice: ArraySlice<Float>) -> Double {
        guard !slice.isEmpty else { return 0 }
        var sum = 0.0
        for v in slice {
            let d = Double(v)
            sum += d * d
        }
        return (sum / Double(slice.count)).squareRoot()
    }
}
