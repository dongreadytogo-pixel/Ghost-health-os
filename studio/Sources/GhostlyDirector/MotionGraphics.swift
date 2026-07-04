import Foundation
import GhostlyCore
import GhostlyDomain

/// Factory for common motion-graphics overlays (Phase 8). Produces
/// `MotionTitle` values ready to drop onto a timeline lane — the studio's
/// "add a lower third / title card / subscribe animation" primitives.
///
/// Template UIDs point at Final Cut's built-in Motion titles; callers can
/// override them to target custom Motion templates without changing call sites.
public struct MotionGraphicsLibrary: Sendable {
    /// Lane used for graphics overlays (above the storyline).
    public var lane: Int

    public init(lane: Int = 2) {
        self.lane = lane
    }

    private func range(start: Double, duration: Double) -> TimeRange {
        TimeRange(start: RationalTime(seconds: start, preferredTimescale: 48_000),
                  duration: RationalTime(seconds: duration, preferredTimescale: 48_000))
    }

    /// Name-over-title lower third (e.g. an interviewee's name & role).
    public func lowerThird(name: String, subtitle: String? = nil,
                           start: Double, duration: Double = 4) -> MotionTitle {
        let text = subtitle.map { "\(name)\n\($0)" } ?? name
        return MotionTitle(text: text, range: range(start: start, duration: duration),
                           lane: lane, kind: .lowerThird,
                           templateName: "Lower Third",
                           templateUID: ".../Titles.localized/Lower Thirds.localized/Basic Lower Third.localized/Basic Lower Third.moti",
                           fontSize: 48, position: .lowerThird)
    }

    /// Full-screen title card / opener.
    public func titleCard(_ text: String, start: Double, duration: Double = 3) -> MotionTitle {
        MotionTitle(text: text, range: range(start: start, duration: duration),
                    lane: lane, kind: .titleCard,
                    templateName: "Basic Title",
                    templateUID: ".../Titles.localized/Build In:Build Out.localized/Basic Title.localized/Basic Title.moti",
                    fontSize: 96, position: .center)
    }

    /// Callout label anchored to a point of interest.
    public func callout(_ text: String, start: Double, duration: Double = 3,
                        position: MotionTitle.Position = .top) -> MotionTitle {
        MotionTitle(text: text, range: range(start: start, duration: duration),
                    lane: lane, kind: .callout,
                    templateName: "Callout",
                    templateUID: ".../Titles.localized/Callouts.localized/Basic Callout.localized/Basic Callout.moti",
                    fontSize: 42, position: position)
    }

    /// Subscribe/like prompt, usually near the end.
    public func subscribeAnimation(start: Double, duration: Double = 4,
                                   label: String = "SUBSCRIBE") -> MotionTitle {
        MotionTitle(text: label, range: range(start: start, duration: duration),
                    lane: lane, kind: .subscribe,
                    templateName: "Subscribe",
                    templateUID: ".../Titles.localized/Social.localized/Subscribe.localized/Subscribe.moti",
                    fontSize: 54, position: .bottomCenter)
    }

    /// Progress bar spanning a range (e.g. across a chapter).
    public func progressBar(start: Double, duration: Double) -> MotionTitle {
        MotionTitle(text: "", range: range(start: start, duration: duration),
                    lane: lane, kind: .progressBar,
                    templateName: "Progress Bar",
                    templateUID: ".../Titles.localized/Elements.localized/Progress Bar.localized/Progress Bar.moti",
                    fontSize: 24, position: .bottomCenter)
    }

    /// Builds lower thirds from a speaker-labeled transcript: one per speaker
    /// change, placed at the moment that speaker starts talking.
    public func lowerThirdsForSpeakers(names: [(speaker: String, start: Double)],
                                       duration: Double = 4) -> [MotionTitle] {
        var lastSpeaker: String?
        var out: [MotionTitle] = []
        for entry in names.sorted(by: { $0.start < $1.start }) where entry.speaker != lastSpeaker {
            out.append(lowerThird(name: entry.speaker, start: entry.start, duration: duration))
            lastSpeaker = entry.speaker
        }
        return out
    }
}
