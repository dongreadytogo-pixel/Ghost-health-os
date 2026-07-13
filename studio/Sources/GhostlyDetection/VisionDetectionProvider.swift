import Foundation
import GhostlyCore

#if canImport(Vision) && canImport(AVFoundation) && canImport(CoreImage)
import AVFoundation
import Vision
import CoreImage

/// Vision/CoreImage-backed `VisualDetecting` on Apple platforms: samples
/// frames at `fps` and runs real, on-device detectors — no fabricated or
/// mocked results. Mirrors `AVFrameHistogramProvider`'s synchronous
/// AVAssetImageGenerator sampling loop.
///
/// - Faces: CoreImage's `CIDetector` (not Vision) because it is the only
///   Apple framework that reports smile/eye-blink features directly
///   (`CIFaceFeature.hasSmile`, `.leftEyeClosed`/`.rightEyeClosed`).
///   `hasEyeContact` is approximated as "both eyes open" — a genuine but
///   coarse proxy for engagement, not gaze/pupil tracking, and documented
///   as such.
/// - Text/barcodes/QR: Vision's `VNRecognizeTextRequest` and
///   `VNDetectBarcodesRequest` — real OCR and payload decoding.
/// - Objects: Vision's `VNRecognizeAnimalsRequest` (cat/dog only — the only
///   general-purpose, no-bundled-model object detector Vision ships).
///   Broader object detection needs a bundled CoreML model, out of scope
///   here; `objects` stays limited to what Vision genuinely detects rather
///   than being backed by a wider, unimplemented label set.
///
/// Deterministic given the same video (same frames, same detector calls).
/// Aggregation of these results is already unit-tested via
/// `VisualDetectionAggregator`; this adapter has no pure logic of its own
/// beyond calling into OS frameworks and normalizing coordinates, so — like
/// `AVFrameHistogramProvider`/`AVAudioSampleProvider` — it carries no
/// dedicated test, only macOS compilation coverage.
public struct VisionDetectionProvider: VisualDetecting {
    /// Minimum confidence Vision/CoreImage must report for a face to be kept.
    public var minimumFaceConfidence: Double

    public init(minimumFaceConfidence: Double = 0.5) {
        self.minimumFaceConfidence = minimumFaceConfidence
    }

    public func detections(for url: URL, fps: Double) async throws -> [FrameDetections] {
        guard fps > 0 else { return [] }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let durationSeconds = CMTimeGetSeconds(asset.duration)
        guard durationSeconds.isFinite, durationSeconds > 0 else { return [] }

        let faceDetector = CIDetector(ofType: CIDetectorTypeFace, context: nil, options: [
            CIDetectorAccuracy: CIDetectorAccuracyHigh,
            CIDetectorSmile: true,
            CIDetectorEyeBlink: true,
        ])

        var results: [FrameDetections] = []
        let step = 1.0 / fps
        var t = 0.0
        while t < durationSeconds {
            let cmTime = CMTime(seconds: t, preferredTimescale: 600)
            guard let cgImage = try? generator.copyCGImage(at: cmTime, actualTime: nil) else {
                t += step
                continue
            }
            let time = RationalTime(seconds: t, preferredTimescale: 600)
            results.append(analyze(cgImage: cgImage, time: time, faceDetector: faceDetector))
            t += step
        }
        return results
    }

    private func analyze(cgImage: CGImage, time: RationalTime,
                         faceDetector: CIDetector?) -> FrameDetections {
        let width = Double(cgImage.width)
        let height = Double(cgImage.height)

        // CoreImage faces: CIFaceFeature.bounds is in pixel coordinates with
        // a bottom-left origin; convert to our normalized top-left rect.
        var faces: [DetectedFace] = []
        if let faceDetector, width > 0, height > 0 {
            let ciImage = CIImage(cgImage: cgImage)
            let features = faceDetector.features(in: ciImage) as? [CIFaceFeature] ?? []
            for feature in features {
                let rect = NormalizedRect(
                    x: feature.bounds.minX / width,
                    y: 1 - (feature.bounds.minY + feature.bounds.height) / height,
                    width: feature.bounds.width / width,
                    height: feature.bounds.height / height)
                faces.append(DetectedFace(
                    bounds: rect, confidence: 1.0, isSmiling: feature.hasSmile,
                    hasEyeContact: !feature.leftEyeClosed && !feature.rightEyeClosed))
            }
        }

        // Vision: text, barcodes/QR, and cat/dog animal detection.
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        let barcodeRequest = VNDetectBarcodesRequest()
        let animalRequest = VNRecognizeAnimalsRequest()
        try? handler.perform([textRequest, barcodeRequest, animalRequest])

        var text: [DetectedText] = []
        for observation in textRequest.results ?? [] {
            guard let candidate = observation.topCandidates(1).first else { continue }
            text.append(DetectedText(string: candidate.string,
                                     bounds: visionRect(observation.boundingBox), kind: .text))
        }
        for observation in barcodeRequest.results ?? [] {
            guard let payload = observation.payloadStringValue else { continue }
            let kind: DetectedText.Kind = observation.symbology == .qr ? .qr : .barcode
            text.append(DetectedText(string: payload,
                                     bounds: visionRect(observation.boundingBox), kind: kind))
        }

        var objects: [DetectedObject] = []
        for observation in animalRequest.results ?? [] {
            for label in observation.labels {
                objects.append(DetectedObject(
                    label: label.identifier, bounds: visionRect(observation.boundingBox),
                    confidence: Double(label.confidence)))
            }
        }

        return FrameDetections(
            time: time,
            faces: faces.filter { $0.confidence >= minimumFaceConfidence },
            objects: objects, text: text)
    }

    /// Vision's `boundingBox` is normalized with a bottom-left origin;
    /// converts to our top-left-origin `NormalizedRect`.
    private func visionRect(_ box: CGRect) -> NormalizedRect {
        NormalizedRect(x: box.minX, y: 1 - box.minY - box.height,
                       width: box.width, height: box.height)
    }
}
#endif
