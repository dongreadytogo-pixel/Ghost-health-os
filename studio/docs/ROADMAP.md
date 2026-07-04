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

## M1 — Real media I/O 🔜

- 🔜 AVFoundation frame-histogram provider (scene detection on real video)
- 🔜 Whisper transcription adapter (whisper.cpp) → word-timed `SubtitleTrack`
- 🔜 FFmpeg-based providers for Linux/CI media fixtures
- 🔜 `ghostly edit` CLI command: media in → analyzed → FCPXML out
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
