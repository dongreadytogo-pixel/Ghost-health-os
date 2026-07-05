import Foundation
import GhostlyCore

/// One queued export.
public struct ExportJob: Sendable, Identifiable, Equatable {
    public enum Status: String, Sendable, Equatable {
        case queued, running, completed, failed
    }

    public let id: String
    public var input: String
    public var output: String
    public var preset: RenderPreset
    public var metadata: ExportMetadata
    public var status: Status
    public var detail: String

    public init(id: String = UUID().uuidString, input: String, output: String,
                preset: RenderPreset, metadata: ExportMetadata = ExportMetadata()) {
        self.id = id
        self.input = input
        self.output = output
        self.preset = preset
        self.metadata = metadata
        self.status = .queued
        self.detail = ""
    }
}

/// Executes an export job. The real implementation shells out to FFmpeg;
/// tests inject a stub. Kept as a protocol so the queue never depends on a
/// process being present (important for CI, where no encoder is installed).
public protocol Renderer: Sendable {
    /// Runs the export, throwing `StudioError` on failure.
    func render(_ job: ExportJob) async throws
}

/// A serial, observable export queue — the "render queue" of Phase 16.
/// Background/batch export is expressed by enqueuing multiple jobs; the queue
/// processes them in order and reports status transitions.
public actor RenderQueue {
    private var jobs: [ExportJob] = []
    private let renderer: any Renderer
    private var isProcessing = false
    private var statusHandler: (@Sendable (ExportJob) -> Void)?

    public init(renderer: any Renderer) {
        self.renderer = renderer
    }

    public func onStatusChange(_ handler: @escaping @Sendable (ExportJob) -> Void) {
        statusHandler = handler
    }

    public var allJobs: [ExportJob] { jobs }
    public var pendingCount: Int { jobs.filter { $0.status == .queued || $0.status == .running }.count }

    @discardableResult
    public func enqueue(_ job: ExportJob) -> String {
        jobs.append(job)
        return job.id
    }

    public func enqueue(contentsOf newJobs: [ExportJob]) {
        jobs.append(contentsOf: newJobs)
    }

    /// Processes every queued job in order, returning the final job list.
    /// Failures are recorded on the job and do not stop the batch.
    @discardableResult
    public func processAll() async -> [ExportJob] {
        guard !isProcessing else { return jobs }
        isProcessing = true
        defer { isProcessing = false }

        for index in jobs.indices where jobs[index].status == .queued {
            update(index, status: .running)
            do {
                try await renderer.render(jobs[index])
                update(index, status: .completed)
            } catch {
                let message = (error as? StudioError)?.errorDescription ?? error.localizedDescription
                update(index, status: .failed, detail: message)
            }
        }
        return jobs
    }

    private func update(_ index: Int, status: ExportJob.Status, detail: String = "") {
        jobs[index].status = status
        if !detail.isEmpty { jobs[index].detail = detail }
        statusHandler?(jobs[index])
    }
}

/// FFmpeg-backed renderer. Builds the command via `FFmpegCommandBuilder` and
/// runs it as a subprocess (Apple/Linux). Not exercised in CI (no encoder),
/// but the argument building it relies on is fully tested.
public struct FFmpegRenderer: Renderer {
    private let builder: FFmpegCommandBuilder

    public init(builder: FFmpegCommandBuilder = FFmpegCommandBuilder()) {
        self.builder = builder
    }

    public func render(_ job: ExportJob) async throws {
        #if canImport(Foundation) && !os(iOS) && !os(watchOS) && !os(tvOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [builder.executable] + builder.arguments(
            input: job.input, output: job.output, preset: job.preset, metadata: job.metadata)
        let errorPipe = Pipe()
        process.standardError = errorPipe
        do {
            try process.run()
        } catch {
            throw StudioError.io(path: job.output, detail: "cannot launch ffmpeg: \(error.localizedDescription)")
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                                encoding: .utf8) ?? ""
            throw StudioError.io(path: job.output,
                                 detail: "ffmpeg exited \(process.terminationStatus): \(stderr.suffix(300))")
        }
        #else
        throw StudioError.unsupportedPlatform(operation: "ffmpeg export")
        #endif
    }
}
