import Foundation

/// Frame-accurate rational time, the unit of currency across the whole studio.
///
/// FCPXML expresses every temporal value as a rational number of seconds
/// (`"3003/3000s"`). Floating-point seconds drift after a few thousand edits;
/// rational arithmetic never does. All timeline math in Ghostly is performed
/// on `RationalTime` and only converted to `Double` at presentation edges.
public struct RationalTime: Hashable, Sendable, Codable {
    /// Numerator in `timescale`-ths of a second. May be negative for offsets.
    public let value: Int64
    /// Ticks per second. Always positive.
    public let timescale: Int32

    public static let zero = RationalTime(value: 0, timescale: 1)

    public init(value: Int64, timescale: Int32) {
        precondition(timescale > 0, "timescale must be positive")
        let g = Self.gcd(abs(value), Int64(timescale))
        if g > 1 {
            self.value = value / g
            self.timescale = Int32(Int64(timescale) / g)
        } else {
            self.value = value
            self.timescale = timescale
        }
    }

    /// Whole seconds convenience.
    public init(seconds: Int) {
        self.init(value: Int64(seconds), timescale: 1)
    }

    /// Converts floating seconds by snapping to the given timescale.
    public init(seconds: Double, preferredTimescale: Int32 = 48_000) {
        self.init(value: Int64((seconds * Double(preferredTimescale)).rounded()),
                  timescale: preferredTimescale)
    }

    public var seconds: Double { Double(value) / Double(timescale) }
    public var isNegative: Bool { value < 0 }
    public var isZero: Bool { value == 0 }

    // MARK: Arithmetic (exact; common denominator reduced afterwards)

    public static func + (lhs: RationalTime, rhs: RationalTime) -> RationalTime {
        let (lv, rv, ts) = commonTerms(lhs, rhs)
        return RationalTime(value: lv + rv, timescale: ts)
    }

    public static func - (lhs: RationalTime, rhs: RationalTime) -> RationalTime {
        let (lv, rv, ts) = commonTerms(lhs, rhs)
        return RationalTime(value: lv - rv, timescale: ts)
    }

    public static func * (lhs: RationalTime, rhs: Int) -> RationalTime {
        RationalTime(value: lhs.value * Int64(rhs), timescale: lhs.timescale)
    }

    /// Scales by a rational factor (used for retiming).
    public func scaled(by numerator: Int, over denominator: Int) -> RationalTime {
        precondition(denominator > 0, "scale denominator must be positive")
        // Reduce cross-factors first to keep intermediates small.
        let g = Self.gcd(abs(value), Int64(denominator))
        let v = value / g
        let d = Int64(denominator) / g
        return RationalTime(value: v * Int64(numerator),
                            timescale: Int32(Int64(timescale) * d))
    }

    private static func commonTerms(_ a: RationalTime, _ b: RationalTime) -> (Int64, Int64, Int32) {
        if a.timescale == b.timescale { return (a.value, b.value, a.timescale) }
        let g = gcd(Int64(a.timescale), Int64(b.timescale))
        let lcm = Int64(a.timescale) / g * Int64(b.timescale)
        let la = a.value * (lcm / Int64(a.timescale))
        let lb = b.value * (lcm / Int64(b.timescale))
        return (la, lb, Int32(lcm))
    }

    private static func gcd(_ a: Int64, _ b: Int64) -> Int64 {
        var (a, b) = (a, b)
        while b != 0 { (a, b) = (b, a % b) }
        return max(a, 1)
    }
}

extension RationalTime: Comparable {
    public static func < (lhs: RationalTime, rhs: RationalTime) -> Bool {
        let (lv, rv, _) = commonTerms(lhs, rhs)
        return lv < rv
    }
}

extension RationalTime: CustomStringConvertible {
    /// FCPXML textual form: `0s`, `5s`, or `3003/3000s`.
    public var description: String {
        if value == 0 { return "0s" }
        if timescale == 1 { return "\(value)s" }
        return "\(value)/\(timescale)s"
    }

    /// Parses the FCPXML time syntax (`"3003/3000s"`, `"5s"`, `"0s"`, `"-1001/3000s"`).
    public init?(fcpxml string: String) {
        guard string.hasSuffix("s") else { return nil }
        let body = string.dropLast()
        if let slash = body.firstIndex(of: "/") {
            guard let num = Int64(body[..<slash]),
                  let den = Int32(body[body.index(after: slash)...]),
                  den > 0 else { return nil }
            self.init(value: num, timescale: den)
        } else {
            guard let num = Int64(body) else { return nil }
            self.init(value: num, timescale: 1)
        }
    }
}

/// A half-open time interval `[start, start+duration)`.
public struct TimeRange: Hashable, Sendable, Codable {
    public var start: RationalTime
    public var duration: RationalTime

    public init(start: RationalTime, duration: RationalTime) {
        precondition(!duration.isNegative, "duration must be non-negative")
        self.start = start
        self.duration = duration
    }

    public init(start: RationalTime, end: RationalTime) {
        precondition(end >= start, "end must not precede start")
        self.init(start: start, duration: end - start)
    }

    public var end: RationalTime { start + duration }

    public func contains(_ time: RationalTime) -> Bool {
        time >= start && time < end
    }

    public func overlaps(_ other: TimeRange) -> Bool {
        start < other.end && other.start < end
    }

    public func intersection(_ other: TimeRange) -> TimeRange? {
        let s = max(start, other.start)
        let e = min(end, other.end)
        guard e > s else { return nil }
        return TimeRange(start: s, end: e)
    }
}

/// Video frame rate expressed exactly (NTSC rates are non-integer rationals).
public struct FrameRate: Hashable, Sendable, Codable {
    /// Frames per `secondsPerBatch` seconds, e.g. 30000/1001 for 29.97.
    public let frames: Int32
    public let secondsPerBatch: Int32

    public static let fps23_976 = FrameRate(frames: 24_000, secondsPerBatch: 1001)
    public static let fps24 = FrameRate(frames: 24, secondsPerBatch: 1)
    public static let fps25 = FrameRate(frames: 25, secondsPerBatch: 1)
    public static let fps29_97 = FrameRate(frames: 30_000, secondsPerBatch: 1001)
    public static let fps30 = FrameRate(frames: 30, secondsPerBatch: 1)
    public static let fps50 = FrameRate(frames: 50, secondsPerBatch: 1)
    public static let fps59_94 = FrameRate(frames: 60_000, secondsPerBatch: 1001)
    public static let fps60 = FrameRate(frames: 60, secondsPerBatch: 1)

    public init(frames: Int32, secondsPerBatch: Int32) {
        precondition(frames > 0 && secondsPerBatch > 0, "frame rate terms must be positive")
        self.frames = frames
        self.secondsPerBatch = secondsPerBatch
    }

    /// Duration of a single frame — the FCPXML `frameDuration` attribute.
    public var frameDuration: RationalTime {
        RationalTime(value: Int64(secondsPerBatch), timescale: frames)
    }

    public var nominalFPS: Double { Double(frames) / Double(secondsPerBatch) }

    /// Snaps a time onto this rate's frame boundary (toward zero), as FCP
    /// requires all edit points to be frame-aligned.
    public func snapped(_ time: RationalTime) -> RationalTime {
        let framesCount = (time.value * Int64(frames)) / (Int64(time.timescale) * Int64(secondsPerBatch))
        return frameDuration * Int(framesCount)
    }
}
