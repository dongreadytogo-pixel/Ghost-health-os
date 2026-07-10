import Foundation
import GhostlyCore

/// Loudness measurement and peak-safe normalization over mono PCM samples.
/// Measures RMS level in dBFS (a deliberate simplification of EBU R128 —
/// no K-weighting — which is stable, deterministic, and close enough for
/// voice-over/music bed leveling; documented as such, not sold as LUFS).
public enum Loudness {
    /// RMS level in dBFS; nil for silence/empty input.
    public static func rmsDBFS(of samples: [Float]) -> Double? {
        guard !samples.isEmpty else { return nil }
        var sum = 0.0
        for v in samples {
            let d = Double(v)
            sum += d * d
        }
        let rms = (sum / Double(samples.count)).squareRoot()
        guard rms > 1e-9 else { return nil }
        return 20 * log10(rms)
    }

    /// Peak level in dBFS; nil for silence/empty input.
    public static func peakDBFS(of samples: [Float]) -> Double? {
        guard let peak = samples.map({ abs(Double($0)) }).max(), peak > 1e-9 else { return nil }
        return 20 * log10(peak)
    }

    /// Linear gain that brings the RMS level to `targetDBFS`, reduced if
    /// necessary so the peak never exceeds `peakCeilingDBFS`. Nil when the
    /// input is silent (nothing to normalize).
    public static func normalizationGain(for samples: [Float],
                                         targetDBFS: Double = -16,
                                         peakCeilingDBFS: Double = -1) -> Double? {
        guard let rms = rmsDBFS(of: samples), let peak = peakDBFS(of: samples) else { return nil }
        let wanted = targetDBFS - rms
        let headroom = peakCeilingDBFS - peak
        return pow(10, min(wanted, headroom) / 20)
    }

    /// Applies `normalizationGain`; returns the input unchanged when silent.
    public static func normalized(_ samples: [Float],
                                  targetDBFS: Double = -16,
                                  peakCeilingDBFS: Double = -1) -> [Float] {
        guard let gain = normalizationGain(for: samples,
                                           targetDBFS: targetDBFS,
                                           peakCeilingDBFS: peakCeilingDBFS) else { return samples }
        let g = Float(gain)
        return samples.map { max(-1, min(1, $0 * g)) }
    }
}
