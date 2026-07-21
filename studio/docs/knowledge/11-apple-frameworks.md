# 11 — Apple Frameworks

Source: https://developer.apple.com/documentation/. What each framework does
and where the studio uses (or will use) it.

- **AVFoundation** — media I/O: `AVAsset`/`AVAssetReader` (decode),
  `AVAssetWriter` (encode), `AVAssetExportSession`, `AVAudioEngine`.
  *Used:* `AVAudioSampleProvider` decodes mono PCM for detection.
  *Planned:* frame extraction for scene detection (M1).
- **Vision** — image analysis: `VNDetectFaceRectanglesRequest`,
  `VNRecognizeTextRequest` (OCR), `VNDetectBarcodesRequest`,
  `VNGenerateOpticalFlowRequest`, human/animal detection, tracking.
  *Planned:* face/smile/object detection providers (M2).
- **CoreML** — on-device model execution (`MLModel`, compiled `.mlmodelc`);
  Vision wraps CoreML for image models; supports quantized LLM/embedding
  models. *Planned:* emotion classification, CLIP embeddings.
- **CoreImage** — GPU image filters (`CIFilter`), color cubes (LUT
  application via `CIColorCube`), histograms (`CIAreaHistogram`).
  *Planned:* auto white balance, LUT preview.
- **CoreGraphics** — 2D drawing; thumbnail/proxy rendering.
- **Metal** — GPU compute/render; backs CoreImage/CoreML; custom kernels
  for waveform/histogram extraction at scale.
- **Speech** — `SFSpeechRecognizer` on-device transcription with word
  timestamps. *Alternative:* whisper.cpp (see 13); both produce our
  word-timed `SubtitleCue`s.
- **Accelerate / vDSP** — SIMD DSP: FFT, RMS, convolution — the native
  fast path for `SilenceDetector`/`BeatDetector` math on Apple platforms.
- **SwiftUI** — declarative UI; the studio shell (`GhostlyApp`) —
  NavigationSplitView, Observation. Dark/light mode automatic.
- **AppKit** — needed for pro-app niceties SwiftUI lacks (panels, precise
  drag, NSDocument); interop via `NSViewRepresentable`.
- **Combine** — reactive pipelines; largely superseded by async/await +
  AsyncSequence in this codebase (structured concurrency preferred).
- **Accessibility** — `accessibilityLabel`/traits on all controls;
  VoiceOver navigation of timeline/task queue is a release requirement.
- **Apple Events / ScriptingBridge** — automation channel to control Final
  Cut Pro (open library, trigger share). Requires
  `NSAppleEventsUsageDescription` + automation TCC prompt. *Planned:* M3.
- **ProExtension / Workflow Extensions** — the official FCP extension point:
  an app extension appearing inside FCP's window with share-destination
  driven round-trips. Distributed inside a host app; sandboxed. *Planned:* M3.
- **ExtensionKit / XPC** — process isolation for the Plugin SDK sandbox.
