import XCTest
import GhostlyCore
@testable import GhostlyDetection

final class WAVTests: XCTestCase {
    // MARK: Round trip

    func testEncodeDecodeRoundTrip() throws {
        let original = AudioFixture(sampleRate: 8000)
            .speech(0.5).silence(0.25).tone(frequency: 880, seconds: 0.5, amplitude: 0.7)
        let decoded = try WAV.decode(original.wavData())
        let source = original.samples()
        XCTAssertEqual(decoded.sampleRate, 8000)
        XCTAssertEqual(decoded.samples.count, source.count)
        for (a, b) in zip(decoded.samples, source) {
            // Worst case = half an LSB of rounding (0.5/32767) plus the
            // encode×32767 / decode÷32768 scale asymmetry (≤ 1/32768).
            XCTAssertEqual(a, b, accuracy: 5.0 / 65536, "16-bit quantization only")
        }
    }

    func testDurationIsExactRationalTime() throws {
        let audio = try WAV.decode(AudioFixture(sampleRate: 16_000).silence(1.5).wavData())
        XCTAssertEqual(audio.duration, RationalTime(value: 24_000, timescale: 16_000))
    }

    // MARK: Format coverage

    func testDecodesStereoByDownmixing() throws {
        // Hand-build a 2-channel 16-bit WAV: L=+0.5, R=-0.5 → mono 0.
        var data = Data()
        func u16(_ v: UInt16) { data.append(UInt8(v & 0xFF)); data.append(UInt8(v >> 8)) }
        func u32(_ v: UInt32) {
            data.append(UInt8(v & 0xFF)); data.append(UInt8((v >> 8) & 0xFF))
            data.append(UInt8((v >> 16) & 0xFF)); data.append(UInt8(v >> 24))
        }
        let frames = 100
        data.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + frames * 4))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); u32(16)
        u16(1); u16(2); u32(8000); u32(8000 * 4); u16(4); u16(16)
        data.append(contentsOf: Array("data".utf8)); u32(UInt32(frames * 4))
        for _ in 0..<frames {
            u16(UInt16(bitPattern: 16384))   // L = +0.5
            u16(UInt16(bitPattern: -16384))  // R = −0.5
        }
        let audio = try WAV.decode(data)
        XCTAssertEqual(audio.samples.count, frames)
        XCTAssertEqual(audio.samples[0], 0, accuracy: 0.001)
    }

    func testDecodesFloat32() throws {
        var data = Data()
        func u16(_ v: UInt16) { data.append(UInt8(v & 0xFF)); data.append(UInt8(v >> 8)) }
        func u32(_ v: UInt32) {
            data.append(UInt8(v & 0xFF)); data.append(UInt8((v >> 8) & 0xFF))
            data.append(UInt8((v >> 16) & 0xFF)); data.append(UInt8(v >> 24))
        }
        let values: [Float] = [0.25, -0.75, 1.0]
        data.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + values.count * 4))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); u32(16)
        u16(3); u16(1); u32(44_100); u32(44_100 * 4); u16(4); u16(32)
        data.append(contentsOf: Array("data".utf8)); u32(UInt32(values.count * 4))
        for v in values { u32(v.bitPattern) }
        let audio = try WAV.decode(data)
        XCTAssertEqual(audio.samples, values)
        XCTAssertEqual(audio.sampleRate, 44_100)
    }

    func testRejectsGarbageTruncatedAndUnsupported() {
        XCTAssertThrowsError(try WAV.decode(Data("not audio".utf8)))
        XCTAssertThrowsError(try WAV.decode(Data(count: 100)), "zeros are not RIFF")
        // Valid header claiming an unsupported 12-bit format.
        var data = AudioFixture(sampleRate: 8000).silence(0.1).wavData()
        data[34] = 12; data[35] = 0 // bitsPerSample = 12
        XCTAssertThrowsError(try WAV.decode(data)) { error in
            guard case StudioError.parseFailure = error else {
                return XCTFail("expected parseFailure, got \(error)")
            }
        }
    }

    // MARK: Determinism

    func testFixtureIsByteDeterministic() {
        XCTAssertEqual(AudioFixture.demo().wavData(), AudioFixture.demo().wavData())
        let a = AudioFixture(sampleRate: 8000).noise(0.5, seed: 42).samples()
        let b = AudioFixture(sampleRate: 8000).noise(0.5, seed: 42).samples()
        XCTAssertEqual(a, b)
        let c = AudioFixture(sampleRate: 8000).noise(0.5, seed: 43).samples()
        XCTAssertNotEqual(a, c, "different seeds must differ")
    }

    // MARK: Detectors run on decoded WAV audio (the real-media path)

    func testSilenceDetectorFindsSpeechInDecodedWAV() throws {
        let wav = AudioFixture(sampleRate: 16_000)
            .silence(1.0).speech(2.0).silence(1.0).wavData()
        let audio = try WAV.decode(wav)
        let ranges = SilenceDetector().speechRanges(samples: audio.samples,
                                                    sampleRate: audio.sampleRate)
        XCTAssertEqual(ranges.count, 1)
        let range = try XCTUnwrap(ranges.first)
        XCTAssertEqual(range.start.seconds, 1.0, accuracy: 0.1)
        XCTAssertEqual(range.end.seconds, 3.0, accuracy: 0.1)
    }

    func testBeatDetectorFindsTempoInDecodedWAV() throws {
        let wav = AudioFixture(sampleRate: 16_000).beats(bpm: 120, seconds: 5).wavData()
        let audio = try WAV.decode(wav)
        let result = BeatDetector().detect(samples: audio.samples,
                                           sampleRate: audio.sampleRate)
        let bpm = try XCTUnwrap(result.bpm)
        XCTAssertEqual(bpm, 120, accuracy: 6, "click track at 120 BPM")
        XCTAssertGreaterThanOrEqual(result.beats.count, 8, "5s at 120 BPM ≈ 10 beats")
    }

    func testDemoFixtureAnalyzesEndToEnd() throws {
        let audio = try WAV.decode(AudioFixture.demo().wavData())
        let speech = SilenceDetector().speechRanges(samples: audio.samples,
                                                    sampleRate: audio.sampleRate)
        XCTAssertGreaterThanOrEqual(speech.count, 2, "two narration bursts (beats may join)")
        let beats = BeatDetector().detect(samples: audio.samples,
                                          sampleRate: audio.sampleRate)
        XCTAssertFalse(beats.beats.isEmpty)
    }
}
