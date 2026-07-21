import XCTest
@testable import GhostlyExport

final class MediaExtractionTests: XCTestCase {
    func testAudioArgumentsProduceAnalysisWAV() {
        let args = MediaExtraction().audioArguments(input: "คลิปไทย.mp4", output: "เสียง.wav")
        XCTAssertEqual(args.first, "-y")
        XCTAssertTrue(args.contains("-vn"), "video must be dropped")
        // Mono at 16 kHz, 16-bit PCM: exactly what WAV.decode + detectors expect.
        assertPair(args, "-ac", "1")
        assertPair(args, "-ar", "16000")
        assertPair(args, "-c:a", "pcm_s16le")
        XCTAssertEqual(args.last, "เสียง.wav")
    }

    func testAudioArgumentsHonorSampleRateAndNoOverwrite() {
        let args = MediaExtraction().audioArguments(
            input: "a.mov", output: "a.wav", sampleRate: 22_050, overwrite: false)
        XCTAssertFalse(args.contains("-y"))
        assertPair(args, "-ar", "22050")
    }

    func testFramesArgumentsDownscaleGrayscale() {
        let args = MediaExtraction().framesArguments(
            input: "a.mp4", outputPattern: "frames/%06d.png")
        assertPair(args, "-vf", "fps=5,scale=-2:90,format=gray")
        XCTAssertTrue(args.contains("-an"), "audio must be dropped")
        XCTAssertEqual(args.last, "frames/%06d.png")
        // Fractional fps stays fractional.
        let ntsc = MediaExtraction().framesArguments(
            input: "a.mp4", outputPattern: "f/%06d.png", fps: 2.5)
        assertPair(ntsc, "-vf", "fps=2.5,scale=-2:90,format=gray")
    }

    func testCommandLinesAreShellQuotedAndDeterministic() {
        let extraction = MediaExtraction()
        let line = extraction.audioCommandLine(input: "my clip.mp4", output: "เสียง ไทย.wav")
        XCTAssertTrue(line.hasPrefix("ffmpeg "))
        XCTAssertTrue(line.contains("'my clip.mp4'"), "spaces must be quoted")
        XCTAssertTrue(line.contains("'เสียง ไทย.wav'"))
        XCTAssertEqual(line, extraction.audioCommandLine(input: "my clip.mp4",
                                                         output: "เสียง ไทย.wav"))
    }

    private func assertPair(_ args: [String], _ flag: String, _ value: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else {
            return XCTFail("missing \(flag)", file: file, line: line)
        }
        XCTAssertEqual(args[index + 1], value, "value for \(flag)", file: file, line: line)
    }
}
