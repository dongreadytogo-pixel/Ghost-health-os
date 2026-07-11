import XCTest
import GhostlyCore
import GhostlyDetection
@testable import GhostlyAudio

/// AI Audio Cleanup (Workflow Constitution v5 — "ลดเสียงรบกวน"): every stage
/// verified on synthesized fixtures with measured attenuation.
final class CleanupTests: XCTestCase {
    private let rate = 16_000

    private func rmsDB(_ samples: [Float]) -> Double {
        Loudness.rmsDBFS(of: samples) ?? -120
    }

    private func tone(_ hz: Double, seconds: Double = 1, amplitude: Double = 0.4) -> [Float] {
        AudioFixture(sampleRate: rate)
            .tone(frequency: hz, seconds: seconds, amplitude: amplitude).samples()
    }

    // MARK: Filters

    func testHighPassKillsRumbleKeepsVoice() {
        let filter = Biquad.highPass(cutoff: 80, sampleRate: rate)
        let rumbleDrop = rmsDB(filter.process(tone(30))) - rmsDB(tone(30))
        XCTAssertLessThan(rumbleDrop, -12, "30 Hz rumble must drop hard")
        let voiceDrop = rmsDB(filter.process(tone(220))) - rmsDB(tone(220))
        XCTAssertGreaterThan(voiceDrop, -1.5, "220 Hz voice must pass, got \(voiceDrop) dB")
    }

    func testNotchKillsHumKeepsVoice() {
        let filter = Biquad.notch(center: 50, sampleRate: rate)
        let humDrop = rmsDB(filter.process(tone(50))) - rmsDB(tone(50))
        XCTAssertLessThan(humDrop, -20, "50 Hz hum must vanish, got \(humDrop) dB")
        let voiceDrop = rmsDB(filter.process(tone(220))) - rmsDB(tone(220))
        XCTAssertGreaterThan(voiceDrop, -1.0, "voice must pass the narrow notch")
    }

    // MARK: Gate

    func testGateFadesFloorNoiseKeepsSpeech() {
        // Quiet hiss, then speech, then hiss.
        let fixture = AudioFixture(sampleRate: rate)
            .noise(1.0, amplitude: 0.002, seed: 3)
            .tone(frequency: 220, seconds: 2, amplitude: 0.4)
            .noise(1.0, amplitude: 0.002, seed: 4)
        let samples = fixture.samples()
        let gated = AudioCleanup.gate(samples, sampleRate: rate,
                                      thresholdDB: -45, floorDB: -30)

        func segment(_ from: Double, _ to: Double, of buffer: [Float]) -> [Float] {
            Array(buffer[Int(from * Double(rate))..<Int(to * Double(rate))])
        }
        // Skip edges: envelope release needs a moment to settle.
        let noiseDrop = rmsDB(segment(0.3, 0.9, of: gated))
            - rmsDB(segment(0.3, 0.9, of: samples))
        XCTAssertLessThan(noiseDrop, -20, "floor noise must fade toward the floor")
        let speechDrop = rmsDB(segment(1.3, 2.7, of: gated))
            - rmsDB(segment(1.3, 2.7, of: samples))
        XCTAssertGreaterThan(speechDrop, -0.5, "speech must pass untouched")
    }

    // MARK: Full chain

    func testCleanupChainScrubsHumFromNarration() {
        // Narration polluted with 50 Hz mains hum and rumble.
        let voice = tone(220, seconds: 2, amplitude: 0.35)
        let hum = tone(50, seconds: 2, amplitude: 0.15)
        let rumble = tone(25, seconds: 2, amplitude: 0.1)
        let dirty = zip(zip(voice, hum), rumble).map { $0.0 + $0.1 + $1 }

        let cleaned = AudioCleanup(highPassHz: 80, humHz: 50, gateThresholdDB: nil)
            .process(dirty, sampleRate: rate)

        // Isolate what each stage removed by re-measuring the components.
        let humResidue = Biquad.notch(center: 50, sampleRate: rate)
            .process(Biquad.highPass(cutoff: 80, sampleRate: rate).process(hum))
        XCTAssertLessThan(rmsDB(humResidue) - rmsDB(hum), -20)
        // Voice level survives the chain.
        let voiceThrough = AudioCleanup(highPassHz: 80, humHz: 50, gateThresholdDB: nil)
            .process(voice, sampleRate: rate)
        XCTAssertGreaterThan(rmsDB(voiceThrough) - rmsDB(voice), -1.5)
        // And the cleaned mix is quieter than the dirty one (junk removed).
        XCTAssertLessThan(rmsDB(cleaned), rmsDB(dirty))
    }

    func testCleanupIsDeterministicAndSafeOnEdgeCases() {
        let fixture = AudioFixture(sampleRate: rate)
            .noise(0.5, seed: 9).speech(0.5).samples()
        let a = AudioCleanup(humHz: 50).process(fixture, sampleRate: rate)
        let b = AudioCleanup(humHz: 50).process(fixture, sampleRate: rate)
        XCTAssertEqual(a, b)
        XCTAssertEqual(AudioCleanup().process([], sampleRate: rate), [])
        // Nyquist-unsafe settings are skipped, not exploded.
        let silly = AudioCleanup(highPassHz: 20_000, humHz: 7_000)
        XCTAssertEqual(silly.process(fixture, sampleRate: rate).count, fixture.count)
    }
}
