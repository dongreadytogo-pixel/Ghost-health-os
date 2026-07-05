import Foundation
import GhostlyCore

/// Pure luma-histogram math shared by every `FrameHistogramProviding` adapter.
/// Kept separate and dependency-free so the histogram binning is unit-tested
/// on any platform, while the frame *decoding* lives in platform adapters.
public enum LumaHistogram {
    /// Builds a normalized histogram (bins sum to 1) from luma samples in 0…1.
    /// An empty input yields an all-zero histogram of the requested size.
    public static func normalized(luma: [Double], bins: Int = 16) -> [Double] {
        precondition(bins > 0, "bins must be positive")
        var counts = [Double](repeating: 0, count: bins)
        guard !luma.isEmpty else { return counts }
        for value in luma {
            let clamped = min(max(value, 0), 1)
            // Map [0,1] → [0, bins-1]; 1.0 lands in the last bin.
            let index = min(bins - 1, Int(clamped * Double(bins)))
            counts[index] += 1
        }
        let total = Double(luma.count)
        for i in counts.indices { counts[i] /= total }
        return counts
    }

    /// Convenience for 8-bit grayscale pixel data (0…255).
    public static func normalized(grayscale pixels: [UInt8], bins: Int = 16) -> [Double] {
        normalized(luma: pixels.map { Double($0) / 255.0 }, bins: bins)
    }

    /// Rec. 601 luma from 8-bit RGB triples (interleaved r,g,b,r,g,b,…).
    public static func normalizedRGB(_ rgb: [UInt8], bins: Int = 16) -> [Double] {
        var luma: [Double] = []
        luma.reserveCapacity(rgb.count / 3)
        var i = 0
        while i + 2 < rgb.count {
            let y = 0.299 * Double(rgb[i]) + 0.587 * Double(rgb[i + 1]) + 0.114 * Double(rgb[i + 2])
            luma.append(y / 255.0)
            i += 3
        }
        return normalized(luma: luma, bins: bins)
    }
}

#if canImport(AVFoundation) && canImport(CoreGraphics)
import AVFoundation
import CoreGraphics

/// AVFoundation-backed frame-histogram provider: samples frames at ~`fps`,
/// downscales each to a small grayscale grid, and bins its luma. Compiles on
/// Apple platforms; the binning it relies on is covered by `LumaHistogram`
/// tests on every platform.
public struct AVFrameHistogramProvider: FrameHistogramProviding {
    /// Downscaled sampling grid edge (pixels). Small = fast + robust to noise.
    public var sampleEdge: Int
    public var bins: Int

    public init(sampleEdge: Int = 32, bins: Int = 16) {
        self.sampleEdge = max(4, sampleEdge)
        self.bins = max(2, bins)
    }

    public func lumaHistograms(for url: URL, fps: Double)
        -> (histograms: [[Double]], times: [RationalTime]) {
        // Return type is non-throwing per the protocol; failures yield empties.
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let durationSeconds = CMTimeGetSeconds(asset.duration)
        guard durationSeconds.isFinite, durationSeconds > 0, fps > 0 else { return ([], []) }

        var histograms: [[Double]] = []
        var times: [RationalTime] = []
        let step = 1.0 / fps
        var t = 0.0
        while t < durationSeconds {
            let cmTime = CMTime(seconds: t, preferredTimescale: 600)
            guard let cgImage = try? generator.copyCGImage(at: cmTime, actualTime: nil) else {
                t += step
                continue
            }
            if let luma = Self.grayscaleLuma(from: cgImage, edge: sampleEdge) {
                histograms.append(LumaHistogram.normalized(luma: luma, bins: bins))
                times.append(RationalTime(seconds: t, preferredTimescale: 600))
            }
            t += step
        }
        return (histograms, times)
    }

    /// Renders a CGImage into an `edge × edge` grayscale buffer and returns
    /// its per-pixel luma in 0…1.
    static func grayscaleLuma(from image: CGImage, edge: Int) -> [Double]? {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        var buffer = [UInt8](repeating: 0, count: edge * edge)
        guard let context = CGContext(
            data: &buffer, width: edge, height: edge, bitsPerComponent: 8,
            bytesPerRow: edge, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: edge, height: edge))
        return buffer.map { Double($0) / 255.0 }
    }
}
#endif
