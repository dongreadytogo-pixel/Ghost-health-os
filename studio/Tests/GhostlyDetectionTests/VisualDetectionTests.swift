import XCTest
import GhostlyCore
@testable import GhostlyDetection

final class VisualDetectionTests: XCTestCase {
    private func t(_ s: Double) -> RationalTime { RationalTime(seconds: s, preferredTimescale: 48_000) }

    private func frame(_ s: Double, faces: [DetectedFace] = [],
                       objects: [DetectedObject] = [], text: [DetectedText] = []) -> FrameDetections {
        FrameDetections(time: t(s), faces: faces, objects: objects, text: text)
    }

    private func face(_ smiling: Bool = false, eyeContact: Bool = false,
                      confidence: Double = 0.9) -> DetectedFace {
        DetectedFace(bounds: NormalizedRect(x: 0.3, y: 0.2, width: 0.4, height: 0.5),
                     confidence: confidence, isSmiling: smiling, hasEyeContact: eyeContact)
    }

    // MARK: NormalizedRect

    func testRectClampsAndGeometry() {
        let r = NormalizedRect(x: -0.5, y: 0.5, width: 2, height: 0.5)
        XCTAssertEqual(r.x, 0)
        XCTAssertEqual(r.width, 1)
        XCTAssertEqual(r.centerY, 0.75, accuracy: 1e-9)
        XCTAssertEqual(r.area, 0.5, accuracy: 1e-9)
    }

    func testRectIntersects() {
        let a = NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.5)
        XCTAssertTrue(a.intersects(NormalizedRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)))
        XCTAssertFalse(a.intersects(NormalizedRect(x: 0.6, y: 0.6, width: 0.2, height: 0.2)))
    }

    // MARK: Face presence

    func testFacePresenceRangesWithGapBridging() {
        // Faces at 0,0.2,0.4 … drop at 0.6 (short gap, bridged) … resume 0.8.
        let frames = [
            frame(0.0, faces: [face()]), frame(0.2, faces: [face()]),
            frame(0.4, faces: [face()]), frame(0.6), frame(0.8, faces: [face()]),
        ]
        let summary = VisualDetectionAggregator(maxGapToBridge: 0.5).summarize(frames)
        XCTAssertEqual(summary.facePresenceRanges.count, 1, "0.4→0.8 gap is within bridge tolerance")
    }

    func testFacePresenceBreaksOnLongGap() {
        let frames = [
            frame(0.0, faces: [face()]), frame(0.2, faces: [face()]),
            frame(3.0, faces: [face()]), frame(3.2, faces: [face()]),
        ]
        let summary = VisualDetectionAggregator(maxGapToBridge: 0.5).summarize(frames)
        XCTAssertEqual(summary.facePresenceRanges.count, 2)
    }

    func testLowConfidenceFacesIgnored() {
        let frames = [frame(0.0, faces: [face(confidence: 0.2)]), frame(0.2, faces: [face(confidence: 0.1)])]
        let summary = VisualDetectionAggregator(minimumConfidence: 0.5).summarize(frames)
        XCTAssertTrue(summary.facePresenceRanges.isEmpty)
    }

    func testSmileAndEyeContactRangesAreSubsets() {
        let frames = [
            frame(0.0, faces: [face(false, eyeContact: false)]),
            frame(0.2, faces: [face(true, eyeContact: true)]),
            frame(0.4, faces: [face(true, eyeContact: false)]),
            frame(0.6, faces: [face(false, eyeContact: false)]),
        ]
        let summary = VisualDetectionAggregator().summarize(frames)
        XCTAssertFalse(summary.smileRanges.isEmpty)
        XCTAssertFalse(summary.eyeContactRanges.isEmpty)
        // Smile window (0.2–0.6) sits inside overall presence (0.0–0.8).
        XCTAssertGreaterThanOrEqual(summary.smileRanges[0].start.seconds, 0.2 - 1e-6)
    }

    // MARK: Objects

    func testObjectPrevalenceRankedByOnScreenTime() {
        func obj(_ label: String) -> DetectedObject {
            DetectedObject(label: label, bounds: .full, confidence: 0.9)
        }
        let frames = [
            frame(0.0, objects: [obj("person"), obj("dog")]),
            frame(0.2, objects: [obj("person")]),
            frame(0.4, objects: [obj("person"), obj("car")]),
        ]
        let summary = VisualDetectionAggregator().summarize(frames)
        XCTAssertEqual(summary.objectPrevalence.first?.label, "person")
        XCTAssertEqual(Set(summary.objectPrevalence.map(\.label)), ["person", "dog", "car"])
    }

    // MARK: Text / OCR

    func testTextRangesAndDedup() {
        // Regularly sampled every 0.2 s so the frame step is unambiguous; text
        // present at 0.0/0.2 and again at 2.0, empty in between.
        var frames: [FrameDetections] = []
        var s = 0.0
        while s <= 2.0 + 1e-9 {
            if s < 0.3 {
                frames.append(frame(s, text: [DetectedText(string: "SALE", bounds: .full)]))
            } else if abs(s - 2.0) < 1e-9 {
                frames.append(frame(s, text: [DetectedText(string: "https://x.co", bounds: .full, kind: .qr)]))
            } else {
                frames.append(frame(s))
            }
            s += 0.2
        }
        let summary = VisualDetectionAggregator(maxGapToBridge: 0.3).summarize(frames)
        XCTAssertEqual(summary.recognizedText, ["SALE", "https://x.co"])
        XCTAssertEqual(summary.textRanges.count, 2, "the long gap before 2.0 exceeds the bridge tolerance")
    }

    // MARK: Determinism & edge cases

    func testEmptyInput() {
        let summary = VisualDetectionAggregator().summarize([])
        XCTAssertTrue(summary.facePresenceRanges.isEmpty)
        XCTAssertTrue(summary.objectPrevalence.isEmpty)
        XCTAssertTrue(summary.recognizedText.isEmpty)
    }

    func testDeterministic() {
        let frames = [
            frame(0.0, faces: [face(true, eyeContact: true)],
                  objects: [DetectedObject(label: "person", bounds: .full, confidence: 0.9)]),
            frame(0.2, faces: [face()], text: [DetectedText(string: "HI", bounds: .full)]),
        ]
        let a = VisualDetectionAggregator().summarize(frames)
        let b = VisualDetectionAggregator().summarize(frames.reversed())
        XCTAssertEqual(a, b, "summary must not depend on input frame order")
    }

    func testCodableRoundTrip() throws {
        let frame = FrameDetections(time: t(1), faces: [face(true, eyeContact: true)],
                                    objects: [DetectedObject(label: "car", bounds: .full, confidence: 0.8)],
                                    text: [DetectedText(string: "STOP", bounds: .full, kind: .text)])
        let data = try JSONEncoder().encode(frame)
        let decoded = try JSONDecoder().decode(FrameDetections.self, from: data)
        XCTAssertEqual(decoded.faces.first?.isSmiling, true)
        XCTAssertEqual(decoded.objects.first?.label, "car")
        XCTAssertEqual(decoded.text.first?.kind, .text)
    }
}
