import XCTest
import GhostlyCore
import GhostlyDetection
@testable import GhostlyAudio

final class AudioEngineTests: XCTestCase {
    // MARK: Loudness

    func testRMSOfKnownSine() {
        // Amplitude 0.5 sine → RMS 0.5/√2 → ≈ −9.03 dBFS.
        let samples = AudioFixture(sampleRate: 16_000)
            .tone(frequency: 220, seconds: 1, amplitude: 0.5).samples()
        let rms = Loudness.rmsDBFS(of: samples)
        XCTAssertEqual(try XCTUnwrap(rms), 20 * log10(0.5 / 2.0.squareRoot()), accuracy: 0.1)
    }

    func testSilenceHasNoLevel() {
        XCTAssertNil(Loudness.rmsDBFS(of: []))
        XCTAssertNil(Loudness.rmsDBFS(of: [Float](repeating: 0, count: 1000)))
        XCTAssertNil(Loudness.normalizationGain(for: [Float](repeating: 0, count: 1000)))
        // Silence normalizes to itself, not to NaN.
        XCTAssertEqual(Loudness.normalized([0, 0, 0]), [0, 0, 0])
    }

    func testNormalizationHitsTargetRMS() throws {
        let quiet = AudioFixture(sampleRate: 16_000)
            .tone(frequency: 220, seconds: 1, amplitude: 0.05).samples()
        let normalized = Loudness.normalized(quiet, targetDBFS: -16)
        let rms = try XCTUnwrap(Loudness.rmsDBFS(of: normalized))
        XCTAssertEqual(rms, -16, accuracy: 0.2)
    }

    func testNormalizationRespectsPeakCeiling() throws {
        // Loud content + hot target: the peak ceiling must win.
        let loud = AudioFixture(sampleRate: 16_000)
            .tone(frequency: 220, seconds: 1, amplitude: 0.5).samples()
        let normalized = Loudness.normalized(loud, targetDBFS: 0, peakCeilingDBFS: -1)
        let peak = try XCTUnwrap(Loudness.peakDBFS(of: normalized))
        XCTAssertLessThanOrEqual(peak, -0.9, "peak must stay under the ceiling")
    }

    // MARK: LUFS (K-weighted loudness)

    /// Drops the first 0.5 s so the K-weighting filters' transient doesn't
    /// pollute the measurement (same rationale as the de-hum notch tests:
    /// an IIR filter rings before it settles).
    private func steadyState(_ samples: [Float], sampleRate: Int = 16_000) -> [Float] {
        Array(samples.dropFirst(sampleRate / 2))
    }

    func testLUFSSilenceIsNil() {
        XCTAssertNil(Loudness.lufs(of: [], sampleRate: 16_000))
        XCTAssertNil(Loudness.lufs(of: [Float](repeating: 0, count: 1000), sampleRate: 16_000))
        XCTAssertNil(Loudness.lufsNormalizationGain(
            for: [Float](repeating: 0, count: 1000), sampleRate: 16_000))
    }

    func testLUFSDeterministic() {
        let samples = AudioFixture(sampleRate: 16_000)
            .tone(frequency: 440, seconds: 1, amplitude: 0.3).samples()
        XCTAssertEqual(Loudness.lufs(of: samples, sampleRate: 16_000),
                       Loudness.lufs(of: samples, sampleRate: 16_000))
    }

    func testKWeightingDeEmphasizesBass() throws {
        // Same amplitude, different frequency: the RLB high-pass rolls off
        // bass hard, so a 30 Hz tone must read much quieter in LUFS than a
        // 1 kHz tone despite identical RMS.
        let bass = steadyState(AudioFixture(sampleRate: 16_000)
            .tone(frequency: 30, seconds: 2, amplitude: 0.3).samples())
        let mid = steadyState(AudioFixture(sampleRate: 16_000)
            .tone(frequency: 1000, seconds: 2, amplitude: 0.3).samples())
        let bassLUFS = try XCTUnwrap(Loudness.lufs(of: bass, sampleRate: 16_000))
        let midLUFS = try XCTUnwrap(Loudness.lufs(of: mid, sampleRate: 16_000))
        XCTAssertLessThan(bassLUFS, midLUFS - 10,
                          "30 Hz must read at least 10 LU quieter than 1 kHz at equal RMS")
    }

    func testKWeightingEmphasizesPresence() throws {
        // The high-shelf boosts ~+4 dB above ~1.7 kHz, so a tone in that
        // band must read louder in LUFS than the flat midrange reference.
        let presence = steadyState(AudioFixture(sampleRate: 16_000)
            .tone(frequency: 3000, seconds: 2, amplitude: 0.3).samples())
        let mid = steadyState(AudioFixture(sampleRate: 16_000)
            .tone(frequency: 1000, seconds: 2, amplitude: 0.3).samples())
        let presenceLUFS = try XCTUnwrap(Loudness.lufs(of: presence, sampleRate: 16_000))
        let midLUFS = try XCTUnwrap(Loudness.lufs(of: mid, sampleRate: 16_000))
        XCTAssertGreaterThan(presenceLUFS, midLUFS,
                            "high-shelf boost must make the 3 kHz tone read louder")
    }

    func testLUFSNormalizationHitsTarget() throws {
        let quiet = steadyState(AudioFixture(sampleRate: 16_000)
            .tone(frequency: 1000, seconds: 2, amplitude: 0.05).samples())
        let normalized = Loudness.lufsNormalized(quiet, sampleRate: 16_000, targetLUFS: -16)
        let measured = try XCTUnwrap(Loudness.lufs(of: normalized, sampleRate: 16_000))
        XCTAssertEqual(measured, -16, accuracy: 0.2)
    }

    func testLUFSNormalizationRespectsPeakCeiling() throws {
        let loud = steadyState(AudioFixture(sampleRate: 16_000)
            .tone(frequency: 1000, seconds: 2, amplitude: 0.5).samples())
        let normalized = Loudness.lufsNormalized(loud, sampleRate: 16_000,
                                                  targetLUFS: 0, peakCeilingDBFS: -1)
        let peak = try XCTUnwrap(Loudness.peakDBFS(of: normalized))
        XCTAssertLessThanOrEqual(peak, -0.9, "peak ceiling must win over the loudness target")
    }

    // MARK: Ducking envelope

    private let speech = [
        TimeRange(start: RationalTime(seconds: 2), end: RationalTime(seconds: 4)),
        TimeRange(start: RationalTime(seconds: 4.5), end: RationalTime(seconds: 6)),
        TimeRange(start: RationalTime(seconds: 10), end: RationalTime(seconds: 12)),
    ]
    private let clipEnd = RationalTime(seconds: 15)

    func testEnvelopeDucksUnderSpeechAndRecovers() {
        let ducking = MusicDucking(duckDB: -12, fadeSeconds: 0.3, mergeGapSeconds: 1)
        let env = ducking.envelope(speechRanges: speech, duration: clipEnd)
        let duckGain = pow(10, -12.0 / 20)

        func gain(_ seconds: Double) -> Double {
            MusicDucking.gain(at: RationalTime(seconds: seconds), in: env)
        }
        XCTAssertEqual(gain(0), 1, accuracy: 1e-6, "unity before speech")
        XCTAssertEqual(gain(3), duckGain, accuracy: 1e-3, "ducked mid-speech")
        XCTAssertEqual(gain(5.2), duckGain, accuracy: 1e-3,
                       "0.5s gap merges — no pumping between sentences")
        XCTAssertEqual(gain(8), 1, accuracy: 1e-3, "recovered between ducks")
        XCTAssertEqual(gain(11), duckGain, accuracy: 1e-3)
        XCTAssertEqual(gain(14), 1, accuracy: 1e-3, "unity after last speech")
        // Ramp midpoint sits halfway between unity and duck.
        XCTAssertEqual(gain(2 - 0.15), (1 + duckGain) / 2, accuracy: 0.02)
    }

    func testEnvelopeKeyframesSortedUniqueAndBounded() {
        let env = MusicDucking().envelope(speechRanges: speech, duration: clipEnd)
        for (a, b) in zip(env, env.dropFirst()) {
            XCTAssertLessThan(a.time, b.time, "keyframes must be strictly increasing")
        }
        XCTAssertEqual(env.first?.time, .zero)
        XCTAssertEqual(env.last?.time.seconds ?? 0, 15, accuracy: 1e-6)
        for key in env {
            XCTAssertGreaterThanOrEqual(key.gain, pow(10, -12.0 / 20) - 1e-9)
            XCTAssertLessThanOrEqual(key.gain, 1)
        }
    }

    func testNoSpeechMeansFlatUnity() {
        let env = MusicDucking().envelope(speechRanges: [], duration: clipEnd)
        XCTAssertEqual(env.map(\.gain), [1, 1])
    }

    func testSpeechAtClipStartClampsCleanly() {
        // Speech starting at 0 must not create contradictory keyframes.
        let early = [TimeRange(start: .zero, end: RationalTime(seconds: 2))]
        let env = MusicDucking(duckDB: -12, fadeSeconds: 0.5).envelope(
            speechRanges: early, duration: clipEnd)
        for (a, b) in zip(env, env.dropFirst()) {
            XCTAssertLessThan(a.time, b.time)
        }
        XCTAssertEqual(MusicDucking.gain(at: .zero, in: env), pow(10, -12.0 / 20),
                       accuracy: 1e-3, "already ducked at t=0")
    }

    func testAppliedAttenuatesMusicDuringSpeechOnly() throws {
        let sampleRate = 8000
        let music = AudioFixture(sampleRate: sampleRate)
            .tone(frequency: 110, seconds: 8, amplitude: 0.4).samples()
        let speech = [TimeRange(start: RationalTime(seconds: 3), end: RationalTime(seconds: 5))]
        let ducked = MusicDucking(duckDB: -12, fadeSeconds: 0.2)
            .applied(to: music, sampleRate: sampleRate, speechRanges: speech)

        func rms(_ range: Range<Int>, _ buffer: [Float]) -> Double {
            Loudness.rmsDBFS(of: Array(buffer[range])) ?? -120
        }
        let before = rms(8000..<16000, ducked) - rms(8000..<16000, music)
        let during = rms(28000..<36000, ducked) - rms(28000..<36000, music)
        XCTAssertEqual(before, 0, accuracy: 0.1, "untouched before speech")
        XCTAssertEqual(during, -12, accuracy: 0.5, "−12 dB under speech")
    }
}
