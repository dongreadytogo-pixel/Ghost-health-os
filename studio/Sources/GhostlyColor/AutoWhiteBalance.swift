import Foundation
import GhostlyCore

/// Gray-world auto white balance: assume the scene averages to neutral, and
/// derive the temperature/tint that make it so. Pure — feed it frame-average
/// colors from any source (AVFoundation, ffmpeg-extracted frames, tests) and
/// bake the result into a LUT via `ColorAdjustments`.
public enum AutoWhiteBalance {
    /// Correction that neutralizes `averageColor` (inverts its color cast).
    /// Near-black/blown inputs return identity — no usable evidence.
    public static func estimate(averageColor: RGB) -> ColorAdjustments {
        let c = averageColor.clamped()
        let mean = (c.r + c.g + c.b) / 3
        guard mean > 0.02, mean < 0.98, c.r > 0.005, c.g > 0.005, c.b > 0.005 else {
            return ColorAdjustments()
        }

        // ColorAdjustments applies wbR = 1+0.25T, wbB = 1−0.25T, wbG = 1−0.15·tint.
        // Solve each channel toward the mean, averaging the two temperature
        // estimates (red-down and blue-up agree on the sign for a warm cast).
        let temperatureFromRed = (mean / c.r - 1) / 0.25
        let temperatureFromBlue = (1 - mean / c.b) / 0.25
        let temperature = clamp((temperatureFromRed + temperatureFromBlue) / 2)
        // Tint references the red/blue average, not the overall mean — the
        // overall mean contains the green cast itself and under-corrects.
        let tint = clamp((1 - ((c.r + c.b) / 2) / c.g) / 0.15)
        return ColorAdjustments(temperature: temperature, tint: tint)
    }

    /// Averages per-frame mean colors first (equal weight per frame).
    public static func estimate(frameAverages: [RGB]) -> ColorAdjustments {
        guard !frameAverages.isEmpty else { return ColorAdjustments() }
        let n = Double(frameAverages.count)
        let sum = frameAverages.reduce(RGB(0, 0, 0)) {
            RGB($0.r + $1.r, $0.g + $1.g, $0.b + $1.b)
        }
        return estimate(averageColor: RGB(sum.r / n, sum.g / n, sum.b / n))
    }

    private static func clamp(_ v: Double) -> Double { min(1, max(-1, v)) }
}
