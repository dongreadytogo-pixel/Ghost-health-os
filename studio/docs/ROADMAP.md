# Roadmap

The master spec ("Ghostly790k AI Final Cut Studio — Enterprise Technical
Architecture") is sequenced into milestones that each leave the platform
shippable and tested. Built strictly inward-out: domain core first, so later
milestones never force a redesign.

Legend: ✅ done · 🔜 next · 🗺️ planned

## M0 — Engine core ✅

- ✅ `RationalTime` / `TimeRange` / `FrameRate` exact time math
- ✅ Domain model: assets, clips, lanes, timelines, projects, libraries,
  markers, keywords, captions, transitions, roles, typed IDs
- ✅ Timeline structural validation (overlap/gap/cut-point checks)
- ✅ FCPXML writer, reader, and validator with round-trip tests
- ✅ SRT/WebVTT codecs, word-timed cues, platform caption styles
- ✅ Detection engine: silence (RMS + hysteresis), beats (energy flux +
  refractory + BPM), scene changes (histogram distance)
- ✅ AI Director: intent parser, pacing profiles (Marvel/TikTok/Documentary/
  Vlog/Podcast/Cinematic), deterministic auto-edit planner
- ✅ Multi-AI system: Anthropic, OpenAI-compatible (OpenAI/LM Studio/Qwen/
  Mistral/DeepSeek), Gemini, Ollama adapters + capability router w/ fallback
- ✅ Learning system: local preference store, usage stats, recency-decayed
  recommendations
- ✅ MCP server (stdio) with 7 tools; `ghostly` CLI
- ✅ SwiftUI shell: prompt panel, plan view, caption styles, task queue, logs
- ✅ CI: Linux (swift:6.0) + macOS build/test + executable smoke tests

## M0.5 — Editing core deepening ✅

- ✅ Undo/redo command system + `TimelineDocument` + domain events (Phase 1)
- ✅ Highlight / hook / CTA / chapter detection (`HighlightPlanner`, Phase 7)
- ✅ `find_highlights` MCP tool
- ✅ Motion graphics: `MotionTitle` + FCPXML `<title>` emission +
  `MotionGraphicsLibrary` (lower thirds, title cards, callouts, subscribe,
  progress bars) (Phase 8)
- ✅ Subtitle auto-punctuation for raw ASR transcripts (Phase 6)
- ✅ Asset manager: `GhostlyAssets` — auto-tagging, collections/folders/
  favorites, natural-language search, duplicate/unused finders, `search_assets`
  MCP tool (Phase 9)
- ✅ Export: `GhostlyExport` — render presets (YouTube/TikTok/Instagram/ProRes),
  deterministic FFmpeg command builder (exact NTSC rates, faststart, metadata),
  render queue with injectable renderer; `export`/`presets` CLI commands and
  `export_command`/`list_export_presets` MCP tools (Phase 16)
- ✅ Storage: `GhostlyStorage` — `ProjectRepository` port + file-backed store
  (atomic JSON envelopes, schema-version migration hook, bounded version-history
  snapshots, autosave + crash recovery) (Phase 2)
- ✅ Knowledge Base: `docs/knowledge/` — 20 reference documents + index, the
  project's single source of truth (KB Builder spec)
- ✅ Plugin SDK groundwork: `GhostlyPlugin` — semantic versioning, validated
  `plugin.json` manifest, lifecycle state machine, registry with
  studio-version gating and per-kind contribution queries (Phase 13)

## M1 — Real media I/O 🔜

- ✅ Visual-detection model + aggregator (faces/smile/eye-contact/objects/OCR
  → editorial ranges), `VisualDetecting` provider protocol (Phase 4/6
  groundwork; pure aggregator tested, Vision adapter pending)
- ✅ Frame-histogram seam: pure `LumaHistogram` binning (grayscale/RGB→luma,
  normalized) + platform-gated `AVFrameHistogramProvider` (samples + downscales
  frames on Apple platforms) feeding `SceneChangeDetector`
- 🔜 Vision/CoreML `VisualDetecting` adapter (face/object/text on real frames)
- ✅ Whisper seam: `GhostlyTranscription` — whisper.cpp full-JSON parser →
  word-timed `SubtitleTrack` (Thai-tested) + injectable CLI wrapper +
  `ghostly transcribe` (binary runs on user's machine; parser CI-tested)
- ✅ Real-audio seam: dependency-free `WAV` codec (PCM 8/16/24/32-bit +
  float32/64, any channel count downmixed to mono) + deterministic
  `AudioFixture` synthesis (silence/tones/noise/beat clicks) feeding
  `SilenceDetector`/`BeatDetector`; `ghostly analyze-audio` + `demo-audio`
  commands, CI-smoke-tested end-to-end on generated WAV bytes
- 🔜 FFmpeg command recipes for extracting WAV/frames from video on CI
- ✅ `ghostly edit` CLI command: `EditPipeline` — transcript (SRT/VTT) +
  declared duration + natural-language command → auto-edit → Thai captions →
  validated FCPXML (cue timings double as speech ranges, so the whole chain
  is CI-tested without media; pair with `ghostly transcribe` for real audio)
- 🔜 Speaker diarization for multi-speaker captions

## M2 — App experience 🗺️

- 🗺️ Timeline inspector view (render `Timeline` graphically)
- 🗺️ Asset browser with auto-tagging (Vision + `GhostlyAI`)
- 🗺️ Task queue running real analysis jobs with progress
- 🗺️ Settings: provider API keys in Keychain, routing policy UI
- 🗺️ Undo/redo command stack over timeline edits

## M3 — Deep FCP integration 🗺️

- 🗺️ Workflow Extension target (ProExtension) with one-click AI tools
- 🗺️ Apple Events bridge for library automation
- 🗺️ Motion template generation (lower thirds, callouts, progress bars)
- 🗺️ Color engine: LUT parsing/generation, auto white balance via histograms
- 🗺️ Audio engine: loudness normalization, music ducking envelopes

## M4 — Ecosystem 🗺️

- 🗺️ Plugin SDK: manifest, sandboxed lifecycle, tool/profile registration
- 🗺️ Marketplace client: packages, licensing, offline cache
- 🗺️ Agent mode: multi-step workflows (edit → caption → render → export)
- 🗺️ Premiere Pro / Resolve exporters over the same domain model
