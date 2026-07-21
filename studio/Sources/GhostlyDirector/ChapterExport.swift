import Foundation
import GhostlyCore
import GhostlyDomain

/// Formats chapter markers as a YouTube description chapter list — the
/// timestamps a Thai creator pastes under a video so YouTube renders
/// clickable chapters. Pure and deterministic.
///
/// YouTube's rules, which this enforces:
/// - the first chapter must start at 0:00,
/// - there must be at least three chapters,
/// - each chapter must be at least 10 seconds long.
/// When the input can't satisfy them, `youTubeDescription` returns nil so
/// callers can tell the user why rather than emitting a list YouTube will
/// silently ignore.
public enum ChapterExport {
    /// Builds the "m:ss Title" (or "h:mm:ss" past an hour) block from
    /// chapter-kind markers. Non-chapter markers are ignored. Returns nil
    /// when YouTube's minimums can't be met.
    public static func youTubeDescription(markers: [Marker],
                                          duration: RationalTime) -> String? {
        let chapters = markers
            .filter { $0.kind == .chapter }
            .sorted { $0.start < $1.start }
        guard let first = chapters.first, first.start.seconds < 0.001 else { return nil }
        guard chapters.count >= 3 else { return nil }

        // Every chapter (using the clip end for the last) must be ≥10 s.
        let starts = chapters.map(\.start.seconds)
        for index in starts.indices {
            let end = index + 1 < starts.count ? starts[index + 1] : duration.seconds
            if end - starts[index] < 10 { return nil }
        }

        return chapters.map { "\(timestamp($0.start.seconds)) \($0.text)" }
            .joined(separator: "\n")
    }

    /// "m:ss", or "h:mm:ss" once the time reaches an hour.
    public static func timestamp(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%d:%02d", m, s)
    }
}
