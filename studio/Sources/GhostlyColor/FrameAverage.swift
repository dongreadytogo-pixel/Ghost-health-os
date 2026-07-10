import Foundation
import GhostlyCore

/// Pure frame-average math shared by every frame source: mean RGB of raw
/// pixel buffers, the input `AutoWhiteBalance` consumes. The pixel *decoding*
/// lives in platform adapters (below); the math is unit-tested everywhere.
public enum FrameAverage {
    /// Mean color of interleaved 8-bit RGB pixels (r,g,b,r,g,b,…).
    /// Nil for an empty buffer; a trailing partial pixel is ignored.
    public static func mean(rgb8 pixels: [UInt8]) -> RGB? {
        mean(pixels, stride: 3, r: 0, g: 1, b: 2)
    }

    /// Mean color of interleaved 8-bit RGBA pixels (alpha ignored).
    public static func mean(rgba8 pixels: [UInt8]) -> RGB? {
        mean(pixels, stride: 4, r: 0, g: 1, b: 2)
    }

    /// Mean color of interleaved 8-bit BGRA pixels (e.g. CoreVideo buffers).
    public static func mean(bgra8 pixels: [UInt8]) -> RGB? {
        mean(pixels, stride: 4, r: 2, g: 1, b: 0)
    }

    private static func mean(_ pixels: [UInt8], stride: Int,
                             r: Int, g: Int, b: Int) -> RGB? {
        let count = pixels.count / stride
        guard count > 0 else { return nil }
        var sumR = 0.0, sumG = 0.0, sumB = 0.0
        var i = 0
        for _ in 0..<count {
            sumR += Double(pixels[i + r])
            sumG += Double(pixels[i + g])
            sumB += Double(pixels[i + b])
            i += stride
        }
        let n = Double(count) * 255.0
        return RGB(sumR / n, sumG / n, sumB / n)
    }
}

#if canImport(AVFoundation) && canImport(CoreGraphics)
import AVFoundation
import CoreGraphics

/// AVFoundation-backed frame-average provider: samples frames at ~`fps`,
/// downscales each to a small RGBA grid, and averages it. Feeds
/// `AutoWhiteBalance` with real footage on Apple platforms; the averaging
/// math is covered by `FrameAverage` tests on every platform.
public struct AVFrameAverageProvider: Sendable {
    /// Downscaled sampling grid edge (pixels).
    public var sampleEdge: Int

    public init(sampleEdge: Int = 16) {
        self.sampleEdge = max(2, sampleEdge)
    }

    /// Per-sampled-frame mean colors; empty when the media has no video.
    public func frameAverages(for url: URL, fps: Double = 1) -> [RGB] {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true

        let durationSeconds = CMTimeGetSeconds(asset.duration)
        guard durationSeconds.isFinite, durationSeconds > 0, fps > 0 else { return [] }

        var means: [RGB] = []
        var t = 0.0
        while t < durationSeconds {
            let cmTime = CMTime(seconds: t, preferredTimescale: 600)
            if let cgImage = try? generator.copyCGImage(at: cmTime, actualTime: nil),
               let pixels = Self.rgbaPixels(from: cgImage, edge: sampleEdge),
               let mean = FrameAverage.mean(rgba8: pixels) {
                means.append(mean)
            }
            t += 1.0 / fps
        }
        return means
    }

    /// One-call auto white balance for a video file.
    public func autoWhiteBalance(for url: URL, fps: Double = 1) -> ColorAdjustments {
        AutoWhiteBalance.estimate(frameAverages: frameAverages(for: url, fps: fps))
    }

    /// Renders a CGImage into an `edge × edge` RGBA buffer.
    static func rgbaPixels(from image: CGImage, edge: Int) -> [UInt8]? {
        var buffer = [UInt8](repeating: 0, count: edge * edge * 4)
        guard let context = CGContext(
            data: &buffer, width: edge, height: edge, bitsPerComponent: 8,
            bytesPerRow: edge * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: edge, height: edge))
        return buffer
    }
}
#endif
