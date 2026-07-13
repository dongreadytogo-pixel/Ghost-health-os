import Foundation
import GhostlyCore

/// Loudness measurement and peak-safe normalization over mono PCM samples.
/// Two measures are offered:
/// - `rmsDBFS`: flat RMS in dBFS — simple, stable, good enough for basic
///   voice-over/music bed leveling.
/// - `lufs`: K-weighted integrated loudness per the ITU-R BS.1770-4
///   pre-filter and mean-square formula, computed as a single ungated
///   block. This tracks perceived loudness far better than flat RMS (bass
///   is de-emphasized, presence is emphasized, matching human hearing) and
///   is what "LUFS" normally means for clip-length audio. It is *not* full
///   broadcast-certified LUFS: EBU R128 additionally gates out silent and
///   very quiet passages when averaging a multi-minute program, which this
///   does not implement. Documented as K-weighted loudness, not sold as
///   broadcast-gated LUFS.
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

    // MARK: K-weighted loudness (LUFS)

    /// ITU-R BS.1770 K-weighting pre-filter: a high-shelf (+4 dB above
    /// ~1.68 kHz, modeling the head's acoustic effect) followed by a
    /// high-pass (the "RLB" curve, de-emphasizing bass the ear perceives as
    /// less loud). Coefficients are derived from the standard's analog
    /// prototype at any sample rate, not hardcoded 48 kHz values.
    static func kWeighting(sampleRate: Int) -> [Biquad] {
        [Biquad.highShelf(cutoff: 1681.9744509555319, gainDB: 3.99984385397,
                          sampleRate: sampleRate, q: 0.7071752369554193),
         Biquad.highPass(cutoff: 38.13547087613982, sampleRate: sampleRate,
                         q: 0.5003270373238773)]
    }

    /// K-weighted integrated loudness in LUFS (single ungated block; see
    /// the type documentation for what this does and doesn't measure).
    /// Nil for silence/empty input.
    public static func lufs(of samples: [Float], sampleRate: Int) -> Double? {
        guard !samples.isEmpty, sampleRate > 0 else { return nil }
        var weighted = samples
        for filter in kWeighting(sampleRate: sampleRate) {
            weighted = filter.process(weighted)
        }
        var sum = 0.0
        for v in weighted {
            let d = Double(v)
            sum += d * d
        }
        let meanSquare = sum / Double(weighted.count)
        guard meanSquare > 1e-12 else { return nil }
        return -0.691 + 10 * log10(meanSquare)
    }

    /// Linear gain that brings the K-weighted loudness to `targetLUFS`,
    /// reduced if necessary so the peak never exceeds `peakCeilingDBFS`.
    /// Nil when the input is silent.
    public static func lufsNormalizationGain(for samples: [Float], sampleRate: Int,
                                             targetLUFS: Double = -16,
                                             peakCeilingDBFS: Double = -1) -> Double? {
        guard let loudness = lufs(of: samples, sampleRate: sampleRate),
              let peak = peakDBFS(of: samples) else { return nil }
        let wanted = targetLUFS - loudness
        let headroom = peakCeilingDBFS - peak
        return pow(10, min(wanted, headroom) / 20)
    }

    /// Applies `lufsNormalizationGain`; returns the input unchanged when silent.
    public static func lufsNormalized(_ samples: [Float], sampleRate: Int,
                                      targetLUFS: Double = -16,
                                      peakCeilingDBFS: Double = -1) -> [Float] {
        guard let gain = lufsNormalizationGain(for: samples, sampleRate: sampleRate,
                                               targetLUFS: targetLUFS,
                                               peakCeilingDBFS: peakCeilingDBFS) else { return samples }
        let g = Float(gain)
        return samples.map { max(-1, min(1, $0 * g)) }
    }
}
