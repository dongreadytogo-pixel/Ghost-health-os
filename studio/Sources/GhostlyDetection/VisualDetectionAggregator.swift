import Foundation
import GhostlyCore

/// Collapses noisy per-frame detections into stable, editorially useful
/// summaries: contiguous face-presence ranges, dominant object tags, on-screen
/// text ranges, and smile/eye-contact windows. Pure — deterministic function
/// of its input frames, so it is fully unit-testable without a vision backend.
public struct VisualDetectionAggregator: Sendable {
    /// Minimum confidence for a detection to count.
    public var minimumConfidence: Double
    /// Frames without a detection shorter than this gap don't break a range
    /// (debounces flicker).
    public var maxGapToBridge: Double

    public init(minimumConfidence: Double = 0.5, maxGapToBridge: Double = 0.5) {
        self.minimumConfidence = minimumConfidence
        self.maxGapToBridge = maxGapToBridge
    }

    public struct Summary: Sendable, Equatable {
        /// Ranges where at least one face is present.
        public var facePresenceRanges: [TimeRange]
        /// Ranges where a face is smiling (subset of presence).
        public var smileRanges: [TimeRange]
        /// Ranges where a face makes eye contact with camera.
        public var eyeContactRanges: [TimeRange]
        /// Object labels by total on-screen time (seconds), descending.
        public var objectPrevalence: [(label: String, seconds: Double)]
        /// Ranges where any on-screen text/QR/barcode appears.
        public var textRanges: [TimeRange]
        /// Distinct recognized text strings (deduped, in first-seen order).
        public var recognizedText: [String]

        public init(facePresenceRanges: [TimeRange] = [], smileRanges: [TimeRange] = [],
                    eyeContactRanges: [TimeRange] = [],
                    objectPrevalence: [(label: String, seconds: Double)] = [],
                    textRanges: [TimeRange] = [], recognizedText: [String] = []) {
            self.facePresenceRanges = facePresenceRanges
            self.smileRanges = smileRanges
            self.eyeContactRanges = eyeContactRanges
            self.objectPrevalence = objectPrevalence
            self.textRanges = textRanges
            self.recognizedText = recognizedText
        }

        public static func == (lhs: Summary, rhs: Summary) -> Bool {
            lhs.facePresenceRanges == rhs.facePresenceRanges &&
            lhs.smileRanges == rhs.smileRanges &&
            lhs.eyeContactRanges == rhs.eyeContactRanges &&
            lhs.textRanges == rhs.textRanges &&
            lhs.recognizedText == rhs.recognizedText &&
            lhs.objectPrevalence.map(\.label) == rhs.objectPrevalence.map(\.label) &&
            zip(lhs.objectPrevalence, rhs.objectPrevalence).allSatisfy {
                abs($0.seconds - $1.seconds) < 1e-9
            }
        }
    }

    public func summarize(_ frames: [FrameDetections]) -> Summary {
        let sorted = frames.sorted { $0.time < $1.time }
        let step = frameStep(sorted)

        let facePresence = ranges(in: sorted, step: step) { !confidentFaces($0).isEmpty }
        let smiles = ranges(in: sorted, step: step) { confidentFaces($0).contains(where: \.isSmiling) }
        let eyeContact = ranges(in: sorted, step: step) { confidentFaces($0).contains(where: \.hasEyeContact) }
        let textRanges = ranges(in: sorted, step: step) { !$0.text.isEmpty }

        return Summary(
            facePresenceRanges: facePresence,
            smileRanges: smiles,
            eyeContactRanges: eyeContact,
            objectPrevalence: objectPrevalence(sorted, step: step),
            textRanges: textRanges,
            recognizedText: recognizedText(sorted))
    }

    // MARK: Internals

    private func confidentFaces(_ frame: FrameDetections) -> [DetectedFace] {
        frame.faces.filter { $0.confidence >= minimumConfidence }
    }

    /// Estimated seconds each sampled frame represents (median inter-frame gap).
    private func frameStep(_ frames: [FrameDetections]) -> Double {
        guard frames.count > 1 else { return 0.2 }
        var gaps = zip(frames.dropFirst(), frames).map { ($0.time - $1.time).seconds }
        gaps.sort()
        let median = gaps[gaps.count / 2]
        return median > 0 ? median : 0.2
    }

    /// Builds contiguous ranges of frames satisfying `predicate`, bridging
    /// gaps up to `maxGapToBridge`.
    private func ranges(in frames: [FrameDetections], step: Double,
                        where predicate: (FrameDetections) -> Bool) -> [TimeRange] {
        var out: [TimeRange] = []
        var runStart: RationalTime?
        var lastHitEnd: RationalTime?

        for frame in frames {
            let frameEnd = frame.time + RationalTime(seconds: step, preferredTimescale: 48_000)
            if predicate(frame) {
                if let start = runStart, let last = lastHitEnd,
                   (frame.time - last).seconds > maxGapToBridge {
                    out.append(TimeRange(start: start, end: last))
                    runStart = frame.time
                } else if runStart == nil {
                    runStart = frame.time
                }
                lastHitEnd = frameEnd
            }
        }
        if let start = runStart, let last = lastHitEnd {
            out.append(TimeRange(start: start, end: last))
        }
        return out
    }

    private func objectPrevalence(_ frames: [FrameDetections], step: Double)
        -> [(label: String, seconds: Double)] {
        var totals: [String: Double] = [:]
        var firstSeen: [String: Int] = [:]
        for (index, frame) in frames.enumerated() {
            let labels = Set(frame.objects
                .filter { $0.confidence >= minimumConfidence }
                .map(\.label))
            for label in labels {
                totals[label, default: 0] += step
                if firstSeen[label] == nil { firstSeen[label] = index }
            }
        }
        return totals
            .map { (label: $0.key, seconds: $0.value) }
            .sorted {
                $0.seconds != $1.seconds ? $0.seconds > $1.seconds
                    : (firstSeen[$0.label] ?? 0) < (firstSeen[$1.label] ?? 0)
            }
    }

    private func recognizedText(_ frames: [FrameDetections]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for frame in frames {
            for text in frame.text {
                let trimmed = text.string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, seen.insert(trimmed).inserted {
                    out.append(trimmed)
                }
            }
        }
        return out
    }
}
