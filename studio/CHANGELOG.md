# Changelog

## Unreleased

### Added
- **Thai vertical-short demo**: `ThaiShortsExample` runs the whole pipeline
  end-to-end from fixtures (analyze → plan a 9:16 TikTok edit → attach Thai
  captions → emit validated FCPXML with the `ITT.th` role), exposed as the
  `ghostly demo-thai` CLI command and CI-smoke-tested; no real media needed.
- **Thai-first captions** (per the Constitution's language policy):
  `TextScript` detects spaceless scripts (Thai/Lao/Khmer/Myanmar/CJK/kana/
  Hangul); `SubtitleTrack.wrapped` now wraps spaceless scripts by grapheme and
  re-joins timed Thai tokens without inserting spaces, while spaced languages
  still wrap on word boundaries; `Caption` gains a BCP-47 `language` (tolerant
  decode) that the FCPXML writer/reader map to the caption role (`ITT.th`);
  `AutoPunctuator` is a no-op on non-Latin text; the `generate_captions` MCP
  tool accepts a `language` argument. Tested with real Thai text.
- `GhostlyDetection`: `LumaHistogram` — pure, dependency-free normalized
  luma-histogram binning (from 0…1 luma, 8-bit grayscale, or Rec.601 RGB) that
  every histogram provider shares, plus a platform-gated
  `AVFrameHistogramProvider` (AVAssetImageGenerator sampling + grayscale
  downscale) that feeds `SceneChangeDetector` on real video.
- `GhostlyDetection`: visual-detection layer — `NormalizedRect`,
  `DetectedFace` (smile/eye-contact cues), `DetectedObject`, `DetectedText`
  (text/QR/barcode), per-frame `FrameDetections`, a `VisualDetecting`
  provider protocol, and a pure `VisualDetectionAggregator` that collapses
  noisy per-frame results into face-presence / smile / eye-contact ranges,
  time-ranked object prevalence, and deduped on-screen text with gap
  bridging (Phase 4/6 groundwork; Vision/CoreML adapter to follow).

### Changed
- `GhostlyDirector`: `HighlightPlanner` now accepts an optional
  `VisualDetectionAggregator.Summary` — smile / eye-contact / face-presence
  windows additively boost highlight and hook ranking (a no-op when absent,
  so existing behavior is unchanged).
- `GhostlyMCP`: `generate_captions` gains an `autoPunctuate` option (runs the
  `AutoPunctuator` over the track); new `validate_plugin_manifest` tool lints
  a `plugin.json` against the Plugin SDK and checks studio-version
  compatibility (14 tools total).

### Fixed
- `GhostlyStorage`: persist dates with millisecond precision
  (`millisecondsSince1970`) — ISO-8601 whole-second encoding made an
  autosave written < 1 s after a save appear no newer, breaking recovery.

### Added
- `GhostlyPlugin`: new module — `SemanticVersion` (string-codable),
  `PluginManifest` (`plugin.json` contract with reverse-DNS id, entry-point,
  permission and contribution validation), `PluginState` lifecycle state
  machine (discovered → validated → loaded → activated ⇄ deactivated →
  unloaded, with failure capture), and the `PluginRegistry` actor
  (duplicate-id rejection, studio-version compatibility gating, per-kind
  contribution queries over active plugins).
- Knowledge Base: `docs/knowledge/` — 20 reference documents (FCP core,
  FCPXML spec, workflows, shortcuts, effects, Motion templates, color,
  audio, editing theory, per-genre workflows, Apple frameworks, macOS
  development, AI video technologies, plugin SDK spec, marketplace spec,
  testing guidelines, commercial release playbook, glossary, best
  practices, binding development rules) + index. The project's single
  source of truth.
- `GhostlyStorage`: new module — `ProjectRepository` port and `FileProjectStore`
  (actor): atomic JSON envelopes with a `schemaVersion` + migration hook,
  bounded per-project version-history snapshots, project summaries/list/delete,
  and autosave with crash recovery (only offered when newer than the last save).
- `GhostlyExport`: new module — `RenderPreset` (YouTube 1080p/4K, TikTok,
  Instagram Reel/Feed, ProRes 422 Master), `FFmpegCommandBuilder` (deterministic
  argument vectors with exact NTSC frame rates, `+faststart`, pixel-format and
  metadata handling, shell-quoted command line), and a `RenderQueue` actor with
  an injectable `Renderer` protocol (FFmpeg-backed in production, stubbed in
  tests). Wired to `ghostly export`/`presets` CLI commands and the
  `export_command` / `list_export_presets` MCP tools.
- `GhostlyAssets`: new module — `AutoTagger` (resolution/aspect/duration/
  filename tags), `AssetQuery` (natural-language → structured filter with
  kind, favorite, vertical/horizontal, and duration bounds), and `AssetCatalog`
  (collections, folders, favorites, ranked search, tag frequencies, duplicate
  and unused-asset finders). Exposed via the `search_assets` MCP tool.
- `GhostlyDomain` + `GhostlyFCPXML`: `MotionTitle` overlay model and FCPXML
  `<title>` emission (nested in source time, backed by Motion title effect
  resources) — lower thirds, title cards, callouts, subscribe, progress bars.
- `GhostlyDirector`: `MotionGraphicsLibrary` factory for those overlays,
  including speaker-driven lower thirds.
- `GhostlySubtitles`: `AutoPunctuator` — rule-based capitalization + terminal
  punctuation for raw ASR transcripts, timing-preserving.
- `GhostlyDomain`: reversible `EditCommand` system (append/insert/remove/move/
  trim/rename clip, add caption/marker) and `TimelineDocument` aggregate root
  with bounded undo/redo history and `DomainEvent` change notifications.
- `GhostlyDirector`: `HighlightPlanner` — deterministic hook, highlight, CTA,
  and chapter detection from media analysis + optional transcript, with
  timeline annotation.
- `GhostlyMCP`: `find_highlights` tool (8 tools total).

## 1.0.0 — 2026-07-04

Initial release of the engine core (milestone M0).

### Added
- `GhostlyCore`: exact rational time (`RationalTime`, `TimeRange`,
  `FrameRate` incl. NTSC rates), `StudioError`, pluggable structured logging.
- `GhostlyDomain`: full timeline domain model — assets, clips, lanes,
  transitions, captions, markers, keywords, roles, projects/events/libraries —
  with structural validation.
- `GhostlyFCPXML`: deterministic FCPXML writer (resources dedup, gaps,
  transitions, connected clips, captions, markers, keywords, volume, effects),
  reader (inverse mapping incl. source-time conversion), and validator
  (references, time syntax, spine continuity, versions 1.9–1.13).
- `GhostlySubtitles`: SRT and WebVTT parse/serialize, speaker detection,
  word-level timings, wrapping, shifting, and caption style presets
  (TikTok, YouTube, Instagram, Broadcast).
- `GhostlyDetection`: silence detection (RMS + hysteresis + minimum-duration
  absorption), beat detection (energy-flux onsets, refractory period, BPM
  estimation), scene-change detection (histogram distance), provider
  protocols, AVFoundation audio provider on Apple platforms.
- `GhostlyDirector`: natural-language edit-intent parser, six pacing
  profiles, intent resolution, and the deterministic auto-edit planner
  (silence removal, shot chopping, beat alignment, music bed, transitions,
  styled captions).
- `GhostlyAI`: provider adapters for Anthropic, OpenAI-compatible engines
  (OpenAI, LM Studio, Qwen, Mistral, DeepSeek, vLLM), Google Gemini, and
  Ollama; capability-based `ModelRouter` with priorities, local-first policy,
  and automatic fallback; injectable HTTP transport.
- `GhostlyLearning`: atomic local preference store with corrupt-file
  quarantine, bounded prompt history, and recency-decayed recommendations.
- `GhostlyMCP`: JSON-RPC 2.0 + MCP server core and seven tools
  (`auto_edit`, `parse_edit_command`, `generate_captions`, `validate_fcpxml`,
  `analyze_timeline`, `list_caption_styles`, `recommend`).
- Executables: `ghostly` CLI (intent/captions/validate/analyze/styles) and
  `ghostly-mcp-server` (stdio).
- `GhostlyApp`: SwiftUI studio shell (macOS) — prompt panel, latest-plan
  inspector, caption style browser, task queue, session logs.
- CI: Linux (`swift:6.0` container) and macOS jobs; ~90 tests; release-build
  smoke tests for both executables including a live MCP handshake.
