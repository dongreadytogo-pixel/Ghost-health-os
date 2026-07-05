# 13 — AI Video Technologies

The models/runtimes behind the studio's AI engines and how each plugs in.

## Speech
- **Whisper** (OpenAI) — robust multilingual ASR with word-level timestamps;
  local via **whisper.cpp** (Metal-accelerated GGUF models: tiny→large-v3).
  Output maps to `SubtitleCue(words:)`; punctuation restored by
  `AutoPunctuator` when using no-punctuation models.
- **Apple Speech** — `SFSpeechRecognizer` alternative (no extra binary).
- **Speaker diarization** — pyannote-style segmentation or clustering of
  speaker embeddings; feeds `SubtitleCue.speaker` and lower-third automation.

## Vision models
- **YOLO family** — realtime object detection (people, vehicles, animals,
  products) → asset tagging + B-roll matching. Runs via CoreML or ONNX.
- **MediaPipe** — face mesh, pose, hands; smile/eye-contact scoring for
  `Highlight` ranking.
- **SAM (Segment Anything)** — promptable segmentation; background removal
  masks (Scene Removal-style) and object mattes.
- **OCR** — Vision `VNRecognizeTextRequest`; on-screen text detection for
  auto-captioning graphics and logo/QR detection (with
  `VNDetectBarcodesRequest`).
- **CLIP** — joint text-image embeddings; powers natural-language asset
  search beyond keywords ("golden hour beach drone") by cosine similarity
  over frame embeddings. Complements `GhostlyAssets` keyword search.

## Runtimes
- **CoreML** — first choice on Apple silicon (ANE/GPU).
- **ONNX Runtime** — cross-platform fallback (CoreML EP on macOS); the
  bridge for models without CoreML conversions.
- **Metal** — custom pre/post-processing kernels.

## Embeddings & retrieval
Text/image embeddings stored per asset → approximate nearest-neighbor
search (SQLite + vector extension or in-memory HNSW) → semantic search and
"more like this" recommendations.

## LLMs
- Cloud: Anthropic Claude, OpenAI, Gemini (adapters in `GhostlyAI`).
- Local: Ollama, LM Studio (OpenAI-compatible), llama.cpp.
- Routed by capability with fallback (`ModelRouter`); prompts centralized in
  `PromptLibrary`. LLM output for edit plans must resolve to typed
  `EditIntent`s — never free-form execution.

## MCP (Model Context Protocol)
Open protocol (JSON-RPC 2.0; stdio/HTTP transports) letting any agent call
tools with JSON-schema'd inputs. Spec: https://modelcontextprotocol.io.
Our server (`GhostlyMCP`, protocol `2024-11-05`) exposes 11 studio tools;
tool errors return `isError: true` content per spec so agents self-correct.
