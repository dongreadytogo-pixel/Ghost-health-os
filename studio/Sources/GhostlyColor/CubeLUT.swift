import Foundation
import GhostlyCore

/// Linear-light RGB triple in 0…1 (LUT domain).
public struct RGB: Sendable, Equatable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    public func clamped() -> RGB {
        RGB(min(1, max(0, r)), min(1, max(0, g)), min(1, max(0, b)))
    }

    /// Rec.709 luma of the triple.
    public var luma: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }
}

/// A 3D color lookup table in Adobe/Resolve `.cube` format — the exchange
/// currency of color grading (Final Cut, Resolve, Premiere, ffmpeg all read
/// it). Pure value type: parse, serialize, and sample with trilinear
/// interpolation, identically on every platform.
public struct CubeLUT: Sendable, Equatable {
    public var title: String?
    /// Edge length N; the table holds N³ entries, red fastest (cube order).
    public let size: Int
    public private(set) var table: [RGB]

    public init(title: String? = nil, size: Int, table: [RGB]) throws {
        guard size >= 2, size <= 256 else {
            throw StudioError.invalidInput(field: "size", reason: "LUT size must be 2…256")
        }
        guard table.count == size * size * size else {
            throw StudioError.invalidInput(
                field: "table",
                reason: "need \(size * size * size) entries for size \(size), got \(table.count)")
        }
        self.title = title
        self.size = size
        self.table = table
    }

    /// The identity LUT: sampling returns the input unchanged.
    public static func identity(size: Int = 17) throws -> CubeLUT {
        let n = size
        var table: [RGB] = []
        table.reserveCapacity(n * n * n)
        for b in 0..<n {
            for g in 0..<n {
                for r in 0..<n {
                    let d = Double(n - 1)
                    table.append(RGB(Double(r) / d, Double(g) / d, Double(b) / d))
                }
            }
        }
        return try CubeLUT(title: "Identity", size: n, table: table)
    }

    // MARK: Sampling

    /// Trilinear-interpolated lookup. Input is clamped to 0…1.
    public func sample(_ color: RGB) -> RGB {
        let c = color.clamped()
        let n = size
        let scale = Double(n - 1)

        func axis(_ v: Double) -> (lo: Int, hi: Int, t: Double) {
            let x = v * scale
            let lo = min(n - 2, Int(x))
            return (lo, lo + 1, x - Double(lo))
        }
        let (r0, r1, tr) = axis(c.r)
        let (g0, g1, tg) = axis(c.g)
        let (b0, b1, tb) = axis(c.b)

        func at(_ r: Int, _ g: Int, _ b: Int) -> RGB {
            table[(b * n + g) * n + r]
        }
        func lerp(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
            RGB(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t)
        }

        let c00 = lerp(at(r0, g0, b0), at(r1, g0, b0), tr)
        let c10 = lerp(at(r0, g1, b0), at(r1, g1, b0), tr)
        let c01 = lerp(at(r0, g0, b1), at(r1, g0, b1), tr)
        let c11 = lerp(at(r0, g1, b1), at(r1, g1, b1), tr)
        return lerp(lerp(c00, c10, tg), lerp(c01, c11, tg), tb)
    }

    // MARK: .cube codec

    /// Parses Adobe `.cube` text (3D LUTs; comments and DOMAIN lines allowed).
    public static func parse(_ text: String) throws -> CubeLUT {
        func bail(_ detail: String) -> StudioError {
            .parseFailure(format: "cube LUT", detail: detail)
        }
        var title: String?
        var size: Int?
        var entries: [RGB] = []

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let upper = line.uppercased()
            if upper.hasPrefix("TITLE") {
                title = line.dropFirst("TITLE".count)
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                continue
            }
            if upper.hasPrefix("LUT_3D_SIZE") {
                guard let n = Int(line.split(separator: " ").last ?? "") else {
                    throw bail("bad LUT_3D_SIZE line: \(line)")
                }
                size = n
                continue
            }
            if upper.hasPrefix("LUT_1D_SIZE") {
                throw bail("1D LUTs are not supported; use a 3D LUT")
            }
            if upper.hasPrefix("DOMAIN_MIN") || upper.hasPrefix("DOMAIN_MAX") {
                continue // standard 0…1 domain assumed
            }
            let parts = line.split(separator: " ").compactMap { Double($0) }
            guard parts.count == 3 else {
                throw bail("expected 'r g b' floats, got: \(line.prefix(60))")
            }
            entries.append(RGB(parts[0], parts[1], parts[2]))
        }

        guard let size else { throw bail("missing LUT_3D_SIZE") }
        return try CubeLUT(title: title, size: size, table: entries)
    }

    /// Serializes to `.cube` text; `parse(serialized())` round-trips exactly.
    public func serialized() -> String {
        var out = ""
        if let title { out += "TITLE \"\(title)\"\n" }
        out += "LUT_3D_SIZE \(size)\n"
        for rgb in table {
            out += String(format: "%.6f %.6f %.6f\n", rgb.r, rgb.g, rgb.b)
        }
        return out
    }
}
