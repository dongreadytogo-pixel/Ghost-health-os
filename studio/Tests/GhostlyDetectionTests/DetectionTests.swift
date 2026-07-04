import XCTest
import GhostlyCore
import GhostlyDomain
@testable import GhostlyDetection

final class DetectionTests: XCTestCase {
    private let sampleRate = 8000

    /// Builds a signal from (amplitude, seconds) spans.
    private func signal(_ spans: [(amplitude: Float, seconds: Double)]) -> [Float] {
        var out: [Float] = []
        for span in spans {
            let count = Int(span.seconds * Double(sampleRate))
            // Sine so RMS is amplitude/√2 — realistic, not a DC block.
            for i in 0..<count {
                out.append(span.amplitude * sin(Float(i) * 2 * .pi * 220 / Float(sampleRate)))
            }
        }
        return out
    }

    // MARK: Silence

    func testSilenceDetectorFindsSpeechIslands() {
        let samples = signal([(0.0, 1.0), (0.5, 2.0), (0.0, 1.0), (0.5, 1.5), (0.0, 0.5)])
        let detector = SilenceDetector()
        let speech = detector.speechRanges(samples: samples, sampleRate: sampleRate)
        XCTAssertEqual(speech.count, 2)
        XCTAssertEqual(speech[0].start.seconds, 1.0, accuracy: 0.1)
        XCTAssertEqual(speech[0].end.seconds, 3.0, accuracy: 0.1)
        XCTAssertEqual(speech[1].start.seconds, 4.0, accuracy: 0.1)
    }

    func testSilenceDetectorAbsorbsShortPauses() {
        // 100 ms dip inside speech must not split the segment.
        let samples = signal([(0.5, 1.0), (0.0, 0.1), (0.5, 1.0)])
        let speech = SilenceDetector().speechRanges(samples: samples, sampleRate: sampleRate)
        XCTAssertEqual(speech.count, 1)
        XCTAssertEqual(speech[0].duration.seconds, 2.1, accuracy: 0.1)
    }

    func testSilenceDetectorDropsNoiseBlips() {
        // 50 ms spike inside long silence is noise, not speech.
        let samples = signal([(0.0, 2.0), (0.5, 0.05), (0.0, 2.0)])
        let speech = SilenceDetector().speechRanges(samples: samples, sampleRate: sampleRate)
        XCTAssertTrue(speech.isEmpty, "got \(speech)")
    }

    func testSilenceDetectorEdgeCases() {
        XCTAssertTrue(SilenceDetector().segments(samples: [], sampleRate: sampleRate).isEmpty)
        XCTAssertTrue(SilenceDetector().segments(samples: [0.1], sampleRate: 0).isEmpty)
        let allSpeech = SilenceDetector().segments(samples: signal([(0.5, 1.0)]), sampleRate: sampleRate)
        XCTAssertEqual(allSpeech.count, 1)
        XCTAssertTrue(allSpeech[0].isSpeech)
    }

    func testSegmentsTileTheInput() {
        let samples = signal([(0.0, 0.7), (0.5, 1.3), (0.0, 0.9)])
        let segments = SilenceDetector().segments(samples: samples, sampleRate: sampleRate)
        var cursor = RationalTime.zero
        for segment in segments {
            XCTAssertEqual(segment.range.start, cursor, "segments must be contiguous")
            cursor = segment.range.end
        }
        XCTAssertEqual(cursor.seconds, Double(samples.count) / Double(sampleRate), accuracy: 1e-9)
    }

    // MARK: Beats

    /// Quiet bed with sharp bursts every `interval` seconds.
    private func beatSignal(bpm: Double, seconds: Double) -> [Float] {
        let interval = 60.0 / bpm
        var out = [Float](repeating: 0, count: Int(seconds * Double(sampleRate)))
        // Low noise floor.
        for i in out.indices { out[i] = 0.01 * sin(Float(i) * 0.13) }
        var t = 0.25
        while t < seconds {
            let start = Int(t * Double(sampleRate))
            let burst = min(start + sampleRate / 40, out.count) // 25 ms hit
            for i in start..<burst {
                out[i] = 0.9 * sin(Float(i - start) * 2 * .pi * 80 / Float(sampleRate))
            }
            t += interval
        }
        return out
    }

    func testBeatDetectorFindsRegularBeats() throws {
        let result = BeatDetector().detect(samples: beatSignal(bpm: 120, seconds: 10),
                                           sampleRate: sampleRate)
        // 120 bpm over ~9.75 s from t=0.25 → about 20 beats.
        XCTAssertGreaterThanOrEqual(result.beats.count, 15)
        XCTAssertLessThanOrEqual(result.beats.count, 25)
        let bpm = try XCTUnwrap(result.bpm)
        XCTAssertEqual(bpm, 120, accuracy: 8)
    }

    func testBeatDetectorRespectsRefractoryPeriod() {
        let result = BeatDetector(refractoryPeriod: 0.4)
            .detect(samples: beatSignal(bpm: 240, seconds: 5), sampleRate: sampleRate)
        for (a, b) in zip(result.beats, result.beats.dropFirst()) {
            XCTAssertGreaterThan((b - a).seconds, 0.4)
        }
    }

    func testBeatDetectorHandlesFlatSignal() {
        let flat = [Float](repeating: 0.2, count: sampleRate * 3)
        let result = BeatDetector().detect(samples: flat, sampleRate: sampleRate)
        XCTAssertTrue(result.beats.isEmpty)
        XCTAssertNil(result.bpm)
        XCTAssertTrue(BeatDetector().detect(samples: [], sampleRate: sampleRate).beats.isEmpty)
    }

    func testBPMFoldsIntoMusicalRange() {
        let detector = BeatDetector()
        // 30 bpm intervals (2 s) should fold to 60; 400 bpm folds to 100.
        let slow = stride(from: 0.0, to: 20, by: 2.0).map { RationalTime(seconds: $0, preferredTimescale: 1000) }
        XCTAssertEqual(detector.estimateBPM(beats: slow) ?? 0, 60, accuracy: 1)
        let fast = stride(from: 0.0, to: 3, by: 0.15).map { RationalTime(seconds: $0, preferredTimescale: 1000) }
        let bpm = detector.estimateBPM(beats: fast) ?? 0
        XCTAssertTrue((60...180).contains(bpm), "\(bpm)")
    }

    // MARK: Scene changes

    private func histogram(peak: Int, bins: Int = 16) -> [Double] {
        var h = [Double](repeating: 0.02, count: bins)
        h[peak] = 1.0
        let sum = h.reduce(0, +)
        return h.map { $0 / sum }
    }

    func testSceneChangeDetectorFindsCuts() {
        // 3 s of scene A, 3 s of scene B sampled at 5 fps.
        var histograms: [[Double]] = []
        var times: [RationalTime] = []
        for frame in 0..<30 {
            histograms.append(histogram(peak: frame < 15 ? 2 : 12))
            times.append(RationalTime(value: Int64(frame), timescale: 5))
        }
        let cuts = SceneChangeDetector().cuts(histograms: histograms, frameTimes: times)
        XCTAssertEqual(cuts, [RationalTime(value: 15, timescale: 5)])
    }

    func testSceneChangeDetectorMinimumSceneDuration() {
        // Flicker every frame; only spaced cuts may be reported.
        var histograms: [[Double]] = []
        var times: [RationalTime] = []
        for frame in 0..<20 {
            histograms.append(histogram(peak: frame % 2 == 0 ? 2 : 12))
            times.append(RationalTime(value: Int64(frame), timescale: 5))
        }
        let cuts = SceneChangeDetector(minimumSceneDuration: 1.0)
            .cuts(histograms: histograms, frameTimes: times)
        for (a, b) in zip(cuts, cuts.dropFirst()) {
            XCTAssertGreaterThanOrEqual((b - a).seconds, 1.0)
        }
    }

    func testScenesFromCuts() {
        let detector = SceneChangeDetector()
        let scenes = detector.scenes(cuts: [RationalTime(seconds: 2), RationalTime(seconds: 5)],
                                     duration: RationalTime(seconds: 9))
        XCTAssertEqual(scenes.count, 3)
        XCTAssertEqual(scenes[0].duration.seconds, 2)
        XCTAssertEqual(scenes[2].range.start.seconds, 5)
        XCTAssertEqual(scenes[2].end.seconds, 9)
    }

    // MARK: Analyzer orchestration

    struct StubAudio: AudioSampleProviding {
        let samples: [Float]
        let rate: Int
        func monoSamples(for url: URL) async throws -> (samples: [Float], sampleRate: Int) {
            (samples, rate)
        }
    }

    func testMediaAnalyzerCombinesDetectors() async throws {
        let samples = signal([(0.0, 1.0), (0.5, 2.0), (0.0, 1.0)])
        let analyzer = MediaAnalyzer(audio: StubAudio(samples: samples, rate: sampleRate))
        let asset = Asset(name: "clip", url: URL(fileURLWithPath: "/x.mov"),
                          duration: RationalTime(seconds: 4), kind: .video, format: .hd1080p30)
        let analysis = try await analyzer.analyze(asset)
        XCTAssertEqual(analysis.assetID, asset.id)
        XCTAssertEqual(analysis.speechRanges.count, 1)
        XCTAssertTrue(analysis.sceneCuts.isEmpty, "no frame provider was injected")
    }
}
