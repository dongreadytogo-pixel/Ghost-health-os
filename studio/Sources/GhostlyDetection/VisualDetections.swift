import Foundation
import GhostlyCore

/// A rectangle in normalized coordinates (0…1, origin top-left) — resolution
/// independent so detections survive reframing/scaling.
public struct NormalizedRect: Hashable, Sendable, Codable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = min(max(x, 0), 1)
        self.y = min(max(y, 0), 1)
        self.width = min(max(width, 0), 1)
        self.height = min(max(height, 0), 1)
    }

    public static let full = NormalizedRect(x: 0, y: 0, width: 1, height: 1)

    public var area: Double { width * height }
    public var centerX: Double { x + width / 2 }
    public var centerY: Double { y + height / 2 }

    public func intersects(_ other: NormalizedRect) -> Bool {
        x < other.x + other.width && other.x < x + width &&
        y < other.y + other.height && other.y < y + height
    }
}

/// A detected face with expression/attention cues used for highlight scoring.
public struct DetectedFace: Hashable, Sendable, Codable {
    public var bounds: NormalizedRect
    public var confidence: Double
    public var isSmiling: Bool
    public var hasEyeContact: Bool

    public init(bounds: NormalizedRect, confidence: Double,
                isSmiling: Bool = false, hasEyeContact: Bool = false) {
        self.bounds = bounds
        self.confidence = min(max(confidence, 0), 1)
        self.isSmiling = isSmiling
        self.hasEyeContact = hasEyeContact
    }
}

/// A detected object/animal/vehicle/product with its class label.
public struct DetectedObject: Hashable, Sendable, Codable {
    public var label: String
    public var bounds: NormalizedRect
    public var confidence: Double

    public init(label: String, bounds: NormalizedRect, confidence: Double) {
        self.label = label
        self.bounds = bounds
        self.confidence = min(max(confidence, 0), 1)
    }
}

/// On-screen text (OCR) or a barcode/QR payload.
public struct DetectedText: Hashable, Sendable, Codable {
    public enum Kind: String, Sendable, Codable { case text, qr, barcode }
    public var string: String
    public var bounds: NormalizedRect
    public var kind: Kind

    public init(string: String, bounds: NormalizedRect, kind: Kind = .text) {
        self.string = string
        self.bounds = bounds
        self.kind = kind
    }
}

/// All detections for a single sampled frame at `time`.
public struct FrameDetections: Sendable, Codable {
    public var time: RationalTime
    public var faces: [DetectedFace]
    public var objects: [DetectedObject]
    public var text: [DetectedText]

    public init(time: RationalTime, faces: [DetectedFace] = [],
                objects: [DetectedObject] = [], text: [DetectedText] = []) {
        self.time = time
        self.faces = faces
        self.objects = objects
        self.text = text
    }
}

/// Produces per-frame visual detections for a media URL. Vision/CoreML on
/// Apple platforms; fixtures/ONNX elsewhere.
public protocol VisualDetecting: Sendable {
    func detections(for url: URL, fps: Double) async throws -> [FrameDetections]
}
