import Foundation
import GhostlyCore

/// A deterministic color grade expressed as familiar controls; bake it into
/// a `CubeLUT` for Final Cut / Resolve / ffmpeg, or apply it per pixel.
/// Order of operations matches grading convention:
/// exposure → white balance → contrast → saturation.
public struct ColorAdjustments: Sendable, Equatable, Codable {
    /// Exposure in stops (EV); +1 doubles linear light.
    public var exposureEV: Double
    /// 1 = unchanged; >1 steepens around middle gray (0.18 pivot).
    public var contrast: Double
    /// 1 = unchanged; 0 = grayscale.
    public var saturation: Double
    /// Warm/cool bias in −1…1 (+ warms: more red, less blue).
    public var temperature: Double
    /// Green/magenta bias in −1…1 (+ shifts toward magenta).
    public var tint: Double

    public init(exposureEV: Double = 0, contrast: Double = 1, saturation: Double = 1,
                temperature: Double = 0, tint: Double = 0) {
        self.exposureEV = exposureEV
        self.contrast = contrast
        self.saturation = saturation
        self.temperature = temperature
        self.tint = tint
    }

    public var isIdentity: Bool { self == ColorAdjustments() }

    /// Applies the grade to one linear-light RGB value.
    public func applied(to color: RGB) -> RGB {
        var c = color

        // 1. Exposure: gain in linear light.
        let gain = pow(2, exposureEV)
        c = RGB(c.r * gain, c.g * gain, c.b * gain)

        // 2. White balance: opposing red/blue gains (temperature) and a
        // green gain (tint), scaled gently so ±1 stays plausible.
        let wbR = 1 + 0.25 * temperature
        let wbB = 1 - 0.25 * temperature
        let wbG = 1 - 0.15 * tint
        c = RGB(c.r * wbR, c.g * wbG, c.b * wbB)

        // 3. Contrast: power curve pivoted at middle gray.
        if contrast != 1 {
            let pivot = 0.18
            func curve(_ v: Double) -> Double {
                guard v > 0 else { return 0 }
                return pivot * pow(v / pivot, contrast)
            }
            c = RGB(curve(c.r), curve(c.g), curve(c.b))
        }

        // 4. Saturation: lerp from luma.
        if saturation != 1 {
            let y = c.luma
            c = RGB(y + (c.r - y) * saturation,
                    y + (c.g - y) * saturation,
                    y + (c.b - y) * saturation)
        }
        return c.clamped()
    }

    /// Bakes the grade into a 3D LUT.
    public func lut(size: Int = 17, title: String? = nil) throws -> CubeLUT {
        let identity = try CubeLUT.identity(size: size)
        let graded = identity.table.map(applied(to:))
        return try CubeLUT(title: title ?? "Ghostly Grade", size: size, table: graded)
    }
}
