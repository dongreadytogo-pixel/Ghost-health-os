import Foundation
import GhostlyCore

/// Finds the time offset between two recordings of the same event — the
/// engine behind multicam angle sync ("ซิงก์มุมกล้อง"): every camera hears
/// the same scene, so correlating their audio recovers when each one
/// started recording, no clapboard needed.
///
/// Level/codec differences don't matter: correlation runs over mean-removed
/// RMS envelopes, coarse-to-fine (10 Hz to bracket the lag, 100 Hz to
/// refine it), so hour-long clips align in well under a second of CPU.
public struct AudioAligner: Sendable {
    /// Largest lead/lag considered between two cameras (seconds).
    public var maxLagSeconds: Double

    public init(maxLagSeconds: Double = 120) {
        self.maxLagSeconds = maxLagSeconds
    }

    /// Seconds by which `other`'s camera started recording LATER than
    /// `reference`'s (negative = it started earlier). To lay angles on a
    /// shared timeline, place each clip at `offset - min(allOffsets, 0)`.
    public func offsetSeconds(reference: WAV.Audio, other: WAV.Audio) -> Double {
        let coarseHz = 10.0
        let fineHz = 100.0
        let coarseLag = bestLag(ref: envelope(reference, rate: coarseHz),
                                other: envelope(other, rate: coarseHz),
                                maxLag: Int(maxLagSeconds * coarseHz),
                                centeredAt: 0)
        let center = Int((Double(coarseLag) / coarseHz * fineHz).rounded())
        let fineLag = bestLag(ref: envelope(reference, rate: fineHz),
                              other: envelope(other, rate: fineHz),
                              maxLag: Int(2 * fineHz),
                              centeredAt: center)
        return Double(fineLag) / fineHz
    }

    /// Mean-removed RMS envelope at `rate` Hz.
    func envelope(_ audio: WAV.Audio, rate: Double) -> [Float] {
        guard audio.sampleRate > 0, !audio.samples.isEmpty else { return [] }
        let window = max(1, Int(Double(audio.sampleRate) / rate))
        var out: [Float] = []
        out.reserveCapacity(audio.samples.count / window + 1)
        var index = 0
        while index < audio.samples.count {
            let end = min(index + window, audio.samples.count)
            var sum: Float = 0
            for i in index..<end { sum += audio.samples[i] * audio.samples[i] }
            out.append((sum / Float(end - index)).squareRoot())
            index = end
        }
        let mean = out.reduce(0, +) / Float(max(out.count, 1))
        return out.map { $0 - mean }
    }

    /// Envelope-step lag maximizing normalized cross-correlation; positive
    /// lag = `other` delayed relative to `ref`.
    private func bestLag(ref: [Float], other: [Float], maxLag: Int, centeredAt center: Int) -> Int {
        guard !ref.isEmpty, !other.isEmpty else { return 0 }
        var best = center
        var bestScore = -Float.infinity
        for lag in (center - maxLag)...(center + maxLag) {
            let tStart = max(0, lag)
            let tEnd = min(ref.count, other.count + lag)
            guard tEnd - tStart > 8 else { continue }
            var dot: Float = 0, refSq: Float = 0, otherSq: Float = 0
            var t = tStart
            while t < tEnd {
                let r = ref[t]
                let o = other[t - lag]
                dot += r * o
                refSq += r * r
                otherSq += o * o
                t += 1
            }
            guard refSq > 0, otherSq > 0 else { continue }
            let score = dot / (refSq.squareRoot() * otherSq.squareRoot())
            if score > bestScore {
                bestScore = score
                best = lag
            }
        }
        return best
    }
}
