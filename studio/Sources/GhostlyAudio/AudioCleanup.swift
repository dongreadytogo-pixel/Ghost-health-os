import Foundation
import GhostlyCore

/// A single biquad (two-pole/two-zero) IIR filter section using the RBJ
/// Audio-EQ-Cookbook coefficients — the workhorse of practical audio
/// cleanup. Pure and deterministic: same samples in, same samples out.
public struct Biquad: Sendable {
    // Coefficients normalized by a0.
    let b0: Double, b1: Double, b2: Double
    let a1: Double, a2: Double

    /// High-pass at `cutoff` Hz (Butterworth-ish at Q = 0.707): removes
    /// rumble, handling noise, and plosive thumps below the voice band.
    public static func highPass(cutoff: Double, sampleRate: Int,
                                q: Double = 0.7071) -> Biquad {
        let w0 = 2 * Double.pi * cutoff / Double(sampleRate)
        let alpha = sin(w0) / (2 * q)
        let cosw0 = cos(w0)
        let a0 = 1 + alpha
        return Biquad(b0: (1 + cosw0) / 2 / a0,
                      b1: -(1 + cosw0) / a0,
                      b2: (1 + cosw0) / 2 / a0,
                      a1: -2 * cosw0 / a0,
                      a2: (1 - alpha) / a0)
    }

    /// Narrow notch at `center` Hz: kills mains hum without touching the
    /// voice around it (higher Q = narrower).
    public static func notch(center: Double, sampleRate: Int,
                             q: Double = 30) -> Biquad {
        let w0 = 2 * Double.pi * center / Double(sampleRate)
        let alpha = sin(w0) / (2 * q)
        let cosw0 = cos(w0)
        let a0 = 1 + alpha
        return Biquad(b0: 1 / a0,
                      b1: -2 * cosw0 / a0,
                      b2: 1 / a0,
                      a1: -2 * cosw0 / a0,
                      a2: (1 - alpha) / a0)
    }

    /// Direct Form I over a whole buffer.
    public func process(_ samples: [Float]) -> [Float] {
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        var out = [Float](repeating: 0, count: samples.count)
        for i in samples.indices {
            let x = Double(samples[i])
            let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x
            y2 = y1; y1 = y
            out[i] = Float(y)
        }
        return out
    }
}

/// Voice cleanup for real recordings ("ลดเสียงรบกวน"): rumble high-pass,
/// mains de-hum (fundamental + two harmonics), and a downward-expander
/// noise gate driven by a peak-follower envelope. Every stage is pure DSP —
/// fixture-tested on CI, applied to WAVs via `ghostly clean-audio`.
public struct AudioCleanup: Sendable {
    /// Rumble cutoff in Hz; nil skips the high-pass.
    public var highPassHz: Double?
    /// Mains frequency (50 in Thailand/Europe, 60 in the US); notches the
    /// fundamental and its 2nd/3rd harmonics. Nil skips de-hum.
    public var humHz: Double?
    /// Gate threshold in dBFS; audio whose envelope falls below fades toward
    /// silence. Nil skips the gate.
    public var gateThresholdDB: Double?
    /// Maximum gate attenuation in dB (floor), keeping ambience natural.
    public var gateFloorDB: Double

    public init(highPassHz: Double? = 80, humHz: Double? = nil,
                gateThresholdDB: Double? = -45, gateFloorDB: Double = -30) {
        self.highPassHz = highPassHz
        self.humHz = humHz
        self.gateThresholdDB = gateThresholdDB
        self.gateFloorDB = gateFloorDB
    }

    public func process(_ samples: [Float], sampleRate: Int) -> [Float] {
        guard !samples.isEmpty, sampleRate > 0 else { return samples }
        var out = samples
        if let highPassHz, highPassHz > 0, highPassHz < Double(sampleRate) / 2 {
            out = Biquad.highPass(cutoff: highPassHz, sampleRate: sampleRate).process(out)
        }
        if let humHz, humHz > 0 {
            for harmonic in 1...3 {
                let center = humHz * Double(harmonic)
                guard center < Double(sampleRate) / 2 else { break }
                out = Biquad.notch(center: center, sampleRate: sampleRate).process(out)
            }
        }
        if let gateThresholdDB {
            out = Self.gate(out, sampleRate: sampleRate,
                            thresholdDB: gateThresholdDB, floorDB: gateFloorDB)
        }
        return out
    }

    /// Downward expander: a peak-follower envelope (fast attack, ~120 ms
    /// release) drives a smoothed gain that fades passages below the
    /// threshold toward the floor instead of chopping them.
    static func gate(_ samples: [Float], sampleRate: Int,
                     thresholdDB: Double, floorDB: Double) -> [Float] {
        let threshold = pow(10, thresholdDB / 20)
        let floorGain = pow(10, floorDB / 20)
        let release = pow(0.5, 1.0 / (0.12 * Double(sampleRate)))  // half-life 120 ms
        let gainSmoothing = pow(0.5, 1.0 / (0.01 * Double(sampleRate))) // 10 ms

        var envelope = 0.0
        var gain = 1.0
        var out = [Float](repeating: 0, count: samples.count)
        for i in samples.indices {
            let magnitude = Double(abs(samples[i]))
            envelope = max(magnitude, envelope * release)
            // 1:4-style downward expansion: (env/threshold)³ below the
            // threshold pushes floor noise down fast (−9 dB below → −27 dB
            // of gain) while staying continuous at the threshold.
            let ratio = envelope / threshold
            let target = ratio >= 1 ? 1.0 : max(floorGain, ratio * ratio * ratio)
            gain = target + (gain - target) * gainSmoothing
            out[i] = Float(Double(samples[i]) * gain)
        }
        return out
    }
}
