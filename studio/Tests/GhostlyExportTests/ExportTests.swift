import XCTest
import GhostlyCore
import GhostlyDomain
@testable import GhostlyExport

final class ExportTests: XCTestCase {
    // MARK: Presets

    func testBuiltInPresetsLookup() {
        XCTAssertNotNil(RenderPreset.named("TikTok"))
        XCTAssertNotNil(RenderPreset.named("tiktok"))
        XCTAssertNotNil(RenderPreset.named("YouTube 4K"))
        XCTAssertNotNil(RenderPreset.named("youtube4k"), "spaces are ignored in lookup")
        XCTAssertNil(RenderPreset.named("nope"))
        XCTAssertEqual(RenderPreset.builtIn.count, 6)
    }

    func testTikTokPresetIsVertical() {
        XCTAssertTrue(RenderPreset.tiktok.format.isVertical)
        XCTAssertEqual(RenderPreset.tiktok.container, .mp4)
        XCTAssertEqual(RenderPreset.tiktok.videoCodec, .h264)
    }

    func testPresetCodableRoundTrip() throws {
        let data = try JSONEncoder().encode(RenderPreset.youtube4K)
        let decoded = try JSONDecoder().decode(RenderPreset.self, from: data)
        XCTAssertEqual(decoded, RenderPreset.youtube4K)
    }

    // MARK: FFmpeg command building

    func testArgumentsIncludeCodecsRateScaleAndFaststart() {
        let args = FFmpegCommandBuilder().arguments(
            input: "in.mov", output: "out.mp4", preset: .youtube1080p)
        XCTAssertEqual(args.first, "-y")
        XCTAssertTrue(contains(args, "-i", "in.mov"))
        XCTAssertTrue(contains(args, "-c:v", "libx264"))
        XCTAssertTrue(contains(args, "-c:a", "aac"))
        XCTAssertTrue(contains(args, "-b:v", "12000k"))
        XCTAssertTrue(contains(args, "-vf", "scale=1920:1080"))
        XCTAssertTrue(contains(args, "-pix_fmt", "yuv420p"))
        XCTAssertTrue(contains(args, "-movflags", "+faststart"))
        XCTAssertEqual(args.last, "out.mp4")
    }

    func testFractionalFrameRateArgForNTSC() {
        let preset = RenderPreset(name: "ntsc", container: .mp4, videoCodec: .h264,
                                  audioCodec: .aac,
                                  format: VideoFormat(width: 1920, height: 1080, frameRate: .fps29_97),
                                  videoBitrateKbps: 10_000)
        let args = FFmpegCommandBuilder().arguments(input: "i", output: "o", preset: preset)
        XCTAssertTrue(contains(args, "-r", "30000/1001"), "NTSC rate must stay exact")
    }

    func testProResUsesProfileNotCRF() {
        let args = FFmpegCommandBuilder().arguments(input: "i", output: "o.mov", preset: .proResMaster)
        XCTAssertTrue(contains(args, "-c:v", "prores_ks"))
        XCTAssertTrue(contains(args, "-profile:v", "2"))
        XCTAssertFalse(args.contains("-crf"))
        XCTAssertTrue(contains(args, "-c:a", "pcm_s16le"))
        XCTAssertFalse(args.contains("-b:a"), "PCM is uncompressed, no audio bitrate")
    }

    func testMetadataArguments() {
        let args = FFmpegCommandBuilder().arguments(
            input: "i", output: "o.mp4", preset: .tiktok,
            metadata: ExportMetadata(title: "My Clip", artist: "Me", year: 2026))
        XCTAssertTrue(contains(args, "-metadata", "title=My Clip"))
        XCTAssertTrue(contains(args, "-metadata", "artist=Me"))
        XCTAssertTrue(contains(args, "-metadata", "date=2026"))
    }

    func testCommandLineIsShellQuoted() {
        let cmd = FFmpegCommandBuilder().commandLine(
            input: "my clip.mov", output: "out.mp4", preset: .tiktok,
            metadata: ExportMetadata(title: "hi there"))
        XCTAssertTrue(cmd.hasPrefix("ffmpeg "))
        XCTAssertTrue(cmd.contains("'my clip.mov'"), "paths with spaces must be quoted")
        XCTAssertTrue(cmd.contains("'title=hi there'"))
    }

    func testArgumentsAreDeterministic() {
        let builder = FFmpegCommandBuilder()
        let a = builder.arguments(input: "i", output: "o.mp4", preset: .instagramReel)
        let b = builder.arguments(input: "i", output: "o.mp4", preset: .instagramReel)
        XCTAssertEqual(a, b)
    }

    func testNoOverwriteOmitsYesFlag() {
        let args = FFmpegCommandBuilder().arguments(
            input: "i", output: "o.mp4", preset: .tiktok, overwrite: false)
        XCTAssertFalse(args.contains("-y"))
    }

    // MARK: Render queue

    /// Records jobs it is asked to render; can be told to fail specific ids.
    actor StubRenderer: Renderer {
        private(set) var rendered: [String] = []
        let failIDs: Set<String>
        init(failIDs: Set<String> = []) { self.failIDs = failIDs }
        func render(_ job: ExportJob) async throws {
            rendered.append(job.id)
            if failIDs.contains(job.id) {
                throw StudioError.io(path: job.output, detail: "stub failure")
            }
        }
    }

    private func job(_ id: String, preset: RenderPreset = .tiktok) -> ExportJob {
        ExportJob(id: id, input: "\(id).mov", output: "\(id).mp4", preset: preset)
    }

    func testQueueProcessesAllInOrder() async {
        let renderer = StubRenderer()
        let queue = RenderQueue(renderer: renderer)
        await queue.enqueue(contentsOf: [job("a"), job("b"), job("c")])
        let result = await queue.processAll()
        XCTAssertEqual(result.map(\.status), [.completed, .completed, .completed])
        let rendered = await renderer.rendered
        XCTAssertEqual(rendered, ["a", "b", "c"])
        let pending = await queue.pendingCount
        XCTAssertEqual(pending, 0)
    }

    func testQueueRecordsFailureButContinues() async {
        let queue = RenderQueue(renderer: StubRenderer(failIDs: ["b"]))
        await queue.enqueue(contentsOf: [job("a"), job("b"), job("c")])
        let result = await queue.processAll()
        XCTAssertEqual(result.map(\.status), [.completed, .failed, .completed])
        XCTAssertTrue(result[1].detail.contains("stub failure"))
    }

    func testQueueEmitsStatusTransitions() async {
        let queue = RenderQueue(renderer: StubRenderer())
        final class Box: @unchecked Sendable { var statuses: [ExportJob.Status] = [] }
        let box = Box()
        await queue.onStatusChange { job in box.statuses.append(job.status) }
        await queue.enqueue(job("a"))
        _ = await queue.processAll()
        XCTAssertEqual(box.statuses, [.running, .completed])
    }

    private func contains(_ args: [String], _ flag: String, _ value: String) -> Bool {
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return false }
        return args[index + 1] == value
    }
}
