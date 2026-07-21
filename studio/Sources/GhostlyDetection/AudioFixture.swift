import Foundation
import GhostlyCore

/// Deterministic audio synthesis for tests, CI, and demos: compose silence,
/// speech-like tones, noise, and beat clicks into a sample buffer (or a WAV
/// file) with sample-exact timing. Same recipe → byte-identical output, so
/// detector behavior on "real" audio is pinned by tests without shipping
/// media files in the repository.
public struct AudioFixture: Sendable {
    public enum Segment: Sendable, Equatable {
        /// Digital silence.
        case silence(seconds: Double)
        /// A steady sine tone (speech stand-in for the silence detector).
        case tone(frequency: Double, seconds: Double, amplitude: Double)
        /// Deterministic noise (seeded LCG), e.g. room tone.
        case noise(seconds: Double, amplitude: Double, seed: UInt64)
        /// Decaying clicks on a steady grid — a drum machine for the beat
        /// detector. Quiet between hits.
        case beats(bpm: Double, seconds: Double, amplitude: Double)
    }

    public var sampleRate: Int
    public private(set) var segments: [Segment]

    public init(sampleRate: Int = 16_000, segments: [Segment] = []) {
        self.sampleRate = sampleRate
        self.segments = segments
    }

    // MARK: Builder

    public func silence(_ seconds: Double) -> AudioFixture {
        appending(.silence(seconds: seconds))
    }

    /// 220 Hz sits in the speech fundamental range.
    public func speech(_ seconds: Double, amplitude: Double = 0.4) -> AudioFixture {
        appending(.tone(frequency: 220, seconds: seconds, amplitude: amplitude))
    }

    public func tone(frequency: Double, seconds: Double, amplitude: Double = 0.4) -> AudioFixture {
        appending(.tone(frequency: frequency, seconds: seconds, amplitude: amplitude))
    }

    public func noise(_ seconds: Double, amplitude: Double = 0.3, seed: UInt64 = 1) -> AudioFixture {
        appending(.noise(seconds: seconds, amplitude: amplitude, seed: seed))
    }

    public func beats(bpm: Double, seconds: Double, amplitude: Double = 0.9) -> AudioFixture {
        appending(.beats(bpm: bpm, seconds: seconds, amplitude: amplitude))
    }

    private func appending(_ segment: Segment) -> AudioFixture {
        AudioFixture(sampleRate: sampleRate, segments: segments + [segment])
    }

    // MARK: Rendering

    public var durationSeconds: Double {
        segments.reduce(0) { total, segment in
            switch segment {
            case .silence(let s), .tone(_, let s, _), .noise(let s, _, _), .beats(_, let s, _):
                return total + s
            }
        }
    }

    /// Mono samples in −1…1.
    public func samples() -> [Float] {
        var out: [Float] = []
        out.reserveCapacity(Int(durationSeconds * Double(sampleRate)) + segments.count)
        for segment in segments {
            switch segment {
            case .silence(let seconds):
                out.append(contentsOf: [Float](repeating: 0, count: count(seconds)))

            case .tone(let frequency, let seconds, let amplitude):
                let n = count(seconds)
                let step = 2 * Double.pi * frequency / Double(sampleRate)
                for i in 0..<n {
                    out.append(Float(amplitude * sin(step * Double(i))))
                }

            case .noise(let seconds, let amplitude, let seed):
                var state = seed == 0 ? 0x4d59_5df4_d0f3_3173 : seed
                for _ in 0..<count(seconds) {
                    // Numerical Recipes LCG — deterministic across platforms.
                    state = state &* 6364136223846793005 &+ 1442695040888963407
                    let unit = Double(state >> 11) / Double(1 << 53)
                    out.append(Float((unit * 2 - 1) * amplitude))
                }

            case .beats(let bpm, let seconds, let amplitude):
                let n = count(seconds)
                let period = 60.0 / bpm * Double(sampleRate) // samples per beat
                let clickLength = Int(0.03 * Double(sampleRate))
                var next = 0.0
                var buffer = [Float](repeating: 0, count: n)
                while Int(next) < n {
                    let start = Int(next)
                    let step = 2 * Double.pi * 1000 / Double(sampleRate)
                    for i in 0..<min(clickLength, n - start) {
                        // 1 kHz burst with an exponential decay envelope.
                        let envelope = exp(-Double(i) / (Double(clickLength) / 5))
                        buffer[start + i] = Float(amplitude * envelope * sin(step * Double(i)))
                    }
                    next += period
                }
                out.append(contentsOf: buffer)
            }
        }
        return out
    }

    public func audio() -> WAV.Audio {
        WAV.Audio(samples: samples(), sampleRate: sampleRate)
    }

    /// 16-bit PCM mono WAV bytes — byte-identical for the same recipe.
    public func wavData() -> Data {
        WAV.encode(audio())
    }

    private func count(_ seconds: Double) -> Int {
        max(0, Int((seconds * Double(sampleRate)).rounded()))
    }

    // MARK: Canonical demo

    /// The studio's canonical fixture: a narration-shaped speech/silence
    /// pattern followed by a 120 BPM beat section. Used by `ghostly
    /// demo-audio` and CI smoke tests.
    public static func demo(sampleRate: Int = 16_000) -> AudioFixture {
        AudioFixture(sampleRate: sampleRate)
            .silence(0.6)
            .speech(2.4)
            .silence(0.8)
            .speech(3.2)
            .silence(1.0)
            .beats(bpm: 120, seconds: 4.0)
    }
}
