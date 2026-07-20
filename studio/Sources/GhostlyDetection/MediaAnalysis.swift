import Foundation
import GhostlyCore
import GhostlyDomain

/// Everything the auto-editor knows about a piece of media. Producers are
/// pluggable: AVFoundation/Vision on Apple platforms, FFmpeg elsewhere,
/// hand-built fixtures in tests.
public struct MediaAnalysis: Sendable, Codable {
    public var assetID: AssetID
    public var duration: RationalTime
    public var speechRanges: [TimeRange]
    public var sceneCuts: [RationalTime]
    public var beats: [RationalTime]
    public var bpm: Double?

    public init(assetID: AssetID, duration: RationalTime,
                speechRanges: [TimeRange] = [], sceneCuts: [RationalTime] = [],
                beats: [RationalTime] = [], bpm: Double? = nil) {
        self.assetID = assetID
        self.duration = duration
        self.speechRanges = speechRanges
        self.sceneCuts = sceneCuts
        self.beats = beats
        self.bpm = bpm
    }
}

/// Source of decoded mono audio for analysis.
public protocol AudioSampleProviding: Sendable {
    /// Mono PCM in −1…1 plus its sample rate.
    func monoSamples(for url: URL) async throws -> (samples: [Float], sampleRate: Int)
}

/// Source of per-frame luma histograms for scene detection.
public protocol FrameHistogramProviding: Sendable {
    /// Normalized histograms sampled at ~`fps` frames per second with their timestamps.
    func lumaHistograms(for url: URL, fps: Double) async throws
        -> (histograms: [[Double]], times: [RationalTime])
}

/// Runs the full detection suite over one asset using injected providers.
public struct MediaAnalyzer: Sendable {
    public var silence: SilenceDetector
    public var beat: BeatDetector
    public var scene: SceneChangeDetector
    private let audio: any AudioSampleProviding
    private let frames: (any FrameHistogramProviding)?

    public init(audio: any AudioSampleProviding,
                frames: (any FrameHistogramProviding)? = nil,
                silence: SilenceDetector = SilenceDetector(),
                beat: BeatDetector = BeatDetector(),
                scene: SceneChangeDetector = SceneChangeDetector()) {
        self.audio = audio
        self.frames = frames
        self.silence = silence
        self.beat = beat
        self.scene = scene
    }

    public func analyze(_ asset: Asset) async throws -> MediaAnalysis {
        var analysis = MediaAnalysis(assetID: asset.id, duration: asset.duration)
        if asset.hasAudio {
            let (samples, rate) = try await audio.monoSamples(for: asset.url)
            analysis.speechRanges = silence.speechRanges(samples: samples, sampleRate: rate)
            let beats = beat.detect(samples: samples, sampleRate: rate)
            analysis.beats = beats.beats
            analysis.bpm = beats.bpm
        }
        if asset.hasVideo, let frames {
            let (histograms, times) = try await frames.lumaHistograms(for: asset.url, fps: 5)
            analysis.sceneCuts = scene.cuts(histograms: histograms, frameTimes: times)
        }
        return analysis
    }
}

#if canImport(AVFoundation)
import AVFoundation

/// AVFoundation-backed audio decoder for Apple platforms.
public struct AVAudioSampleProvider: AudioSampleProviding {
    /// Output rate; 22.05 kHz default balances detector precision and size.
    /// Use 16 kHz when the samples will also feed whisper.cpp.
    public let sampleRate: Int

    public init(sampleRate: Int = 22_050) {
        self.sampleRate = sampleRate
    }

    /// The container's real playback duration (video included) — the length
    /// a multicam angle's clip must span, independent of how much audio
    /// decoded. Zero when it can't be read.
    public func mediaDuration(for url: URL) async -> RationalTime {
        let asset = AVURLAsset(url: url)
        guard let seconds = try? await asset.load(.duration).seconds, seconds.isFinite, seconds > 0 else {
            return .zero
        }
        return RationalTime(seconds: seconds, preferredTimescale: 48_000)
    }

    public func monoSamples(for url: URL) async throws -> (samples: [Float], sampleRate: Int) {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw StudioError.invalidInput(field: "url", reason: "no audio track in \(url.lastPathComponent)")
        }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
        ])
        reader.add(output)
        guard reader.startReading() else {
            throw StudioError.io(path: url.path,
                                 detail: reader.error?.localizedDescription ?? "cannot read audio")
        }
        var samples: [Float] = []
        while let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            guard length >= MemoryLayout<Float>.size else { continue }
            var data = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            _ = data.withUnsafeMutableBytes { ptr in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length,
                                           destination: ptr.baseAddress!)
            }
            samples.append(contentsOf: data)
        }
        if reader.status == .failed {
            throw StudioError.io(path: url.path,
                                 detail: reader.error?.localizedDescription ?? "audio decode failed")
        }
        return (samples, sampleRate)
    }
}
#endif
