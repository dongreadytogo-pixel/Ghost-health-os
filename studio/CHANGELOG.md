# Changelog

## Unreleased

### Added
- **Task queue runs real Workflow jobs (M2)**: the Director panel gains a
  WAV file picker and "รันเวิร์กโฟลว์" button — `StudioModel.runWorkflow()`
  decodes the file and runs the actual `Workflow.run(_:memory:)` chain
  (analyze → auto-edit → captions → export command) off the main thread,
  with AI memory when the local preference store is available. The task
  queue shows live progress: queued → running (ProgressView) → done (clip/
  caption/duration/preset summary) or failed (error detail), and the
  workflow's step trace is written to the log panel.
- **Settings + Keychain (M2)**: `SecretsStoring` port with a macOS
  `KeychainStore` (generic-password items) and an `InMemorySecretsStore`
  for CI; `SettingsViewModel` validates keys (trim, reject whitespace),
  masks them ("••••1234"), and lists AI providers (Anthropic, OpenAI-
  compatible, Gemini, Ollama) with Thai status labels. New "การตั้งค่า"
  panel edits keys — stored in the Keychain only, never files or
  preferences (per the Constitution). Eight tests cover save/mask/validate/
  remove against the in-memory store.
- **Thai UI across the whole app shell**: sidebar sections and remaining
  panels now read in Thai — สไตล์คำบรรยาย, คิวงาน ("ยังไม่มีงาน /
  คำสั่งที่รันจะแสดงที่นี่"), บันทึกการทำงาน — completing the
  Constitution v5 Thai-UI requirement for every existing panel.
- **Asset browser (M2)**: `AssetBrowserViewModel` ranks the library with the
  Thai-aware `AssetQuery` (synonym-bridged Thai search, favorite-first
  ranking, Thai kind labels วิดีโอ/เสียง/รูปภาพ, m:ss durations, Thai result
  summaries) — pure and CI-tested — plus a "คลังคลิป" sidebar panel with a
  Thai search field over a demo library until project loading arrives.
  ROADMAP M2 asset-browser data layer done.
- **Thai-first Director panel**: the app's prompt panel speaks Thai —
  "บอกสตูดิโอว่าอยากตัดต่อแบบไหน", Thai example commands, Thai plan labels
  (สไตล์/ขนาดภาพ/ความยาวช็อต/ตัดตามจังหวะ/คำบรรยาย) — and the plan readout
  now shows the ลดเสียงรบกวน (audio cleanup) flag.
- The studio app gains a **"ไทม์ไลน์" sidebar section**: the Thai
  vertical-short fixture renders live in the new inspector, so the GUI
  shows a real auto-edited timeline (clips, ducked music, Thai captions,
  markers) before project loading arrives. `ThaiShortsExample.Result` now
  exposes the planned `timeline` for reuse.
- `TimelineInspectorView` (GhostlyApp, macOS): SwiftUI renderer over
  `TimelineViewModel` — ruler with m:ss ticks and marker flags, role-colored
  lane rows with volume-automation badges, caption chips with speaker
  prefixes; Thai-first labels ("แนวตั้ง 9:16", "ซับ … มาร์กเกอร์ …"). All
  layout math lives in the CI-tested view model; the view only draws.
- **M2 GUI groundwork**: new `GhostlyViewModels` module — `TimelineViewModel`
  turns a `Timeline` into pure presentation data (lanes of clip blocks with
  0…1 normalized geometry, caption chips with speaker/language, marker
  flags, auto-scaled m:ss ruler ticks, volume-automation badges). No
  SwiftUI/platform types, so the inspector's logic is CI-tested on Linux;
  the macOS view layer just draws it.
- **Thai date/time formatting** (Workflow Constitution v5): `ThaiDate` —
  Buddhist-era years (+543), Thai month/weekday names, four styles
  ("วันเสาร์ที่ 11 กรกฎาคม พ.ศ. 2569" → "11/07/2569"), 24-hour "น." clock
  time, and a log/notification timestamp; Asia/Bangkok default with
  explicit-timezone support. Pure component math + hardcoded names — no
  ICU/locale differences between platforms; tested including timezone
  boundaries and a leap day.
- **One-click audio cleanup in the edit chain**: the "ลดเสียงรบกวน" /
  "clean audio" intent (new `EditIntent.cleanAudio`, Thai + English
  vocabulary) makes `EditPipeline`/`Workflow` run `AudioCleanup` *before*
  detection — constant hum otherwise reads as speech and masks every pause,
  so silence removal couldn't bite. Also exposed explicitly as
  `ghostly edit/workflow --clean` and `cleanAudio` on the
  `edit_from_audio`/`run_workflow` MCP tools; the workflow step trace
  reports the cleanup. Behavioral test: a hum-drenched two-burst recording
  keeps its full length without cleanup and loses its silences with it.
- **Thai sentence grouping** (Workflow Constitution v5 — "Proper sentence
  grouping"): `SubtitleTrack.groupedIntoSentences` merges word-fragment ASR
  cues into natural sentence-sized subtitles using pauses and Thai
  sentence-final particles — a breath (≥0.6 s) always splits, a particle
  (ครับ/ค่ะ/คะ/จ้า/…) splits after a short beat (≥0.25 s) so mid-greeting
  "สวัสดีครับทุกคน" stays whole, a readability cap splits run-on speech, and
  a speaker change always splits. Thai fragments re-join without spaces,
  mixed Thai-English keeps its space, word timings concatenate.
  `ghostly transcribe --sentences` applies it after Whisper transcription.
- **AI Audio Cleanup** (Workflow Constitution v5 — "ลดเสียงรบกวน"):
  `Biquad` RBJ filter sections (high-pass, narrow notch) and `AudioCleanup`,
  a pure-DSP chain of rumble high-pass (80 Hz), mains de-hum (50/60 Hz
  fundamental + 2 harmonics), and a cubic downward-expander noise gate with
  peak-follower envelope and smoothed gain. `ghostly clean-audio` applies it
  to WAVs and reports before/after RMS. Tests measure actual attenuation on
  synthesized fixtures: rumble −17 dB, hum −20+ dB, floor noise −20+ dB,
  voice band within 1.5 dB, plus determinism and Nyquist-safety edges.
- **AI memory for the workflow** (Workflow Constitution v5 — "ใช้ค่าที่เคยใช้"):
  `Workflow.run(_:memory:)` pre-fills an unspecified export preset from the
  editor's learned favorites (falling back to format inference when the
  favorite no longer exists) and records the used export preset, caption
  style, pacing style, and command into the local `PreferenceStore` — so
  nothing is configured twice and `recommend` keeps improving. Exposed as
  `ghostly workflow --remember` (store at `~/.ghostly` or `GHOSTLY_HOME`)
  and `run_workflow {"useMemory": true}` over MCP.
  `EditPipeline.Output` now reports the attached `captionStyleName`.
- **Thai asset search** (Workflow Constitution v5): `AssetQuery` understands
  Thai queries — kinds ("คลิป/เสียง/รูปภาพ"), favorites ("รายการโปรด"),
  orientation ("แนวตั้ง/แนวนอน"), duration bounds ("ไม่เกิน 30 วินาที",
  "ยาวกว่า 2 นาที") — and matches Thai concepts against English auto-tags
  via a curated Thai↔English synonym map ("แมว"→cat, "ทะเล"→sea/beach,
  "พระอาทิตย์ตก"→sunset, "คนกำลังยิ้ม"→people/smiling, …). Glued
  conversational queries work ("หาคลิปแมวตอนกลางคืนให้หน่อย"): command
  words strip away and every embedded concept expands. English queries
  behave exactly as before. Reaches CLI/MCP through the existing
  `search_assets` tool.
- **Thai natural-language commands** (Workflow Constitution v5.0): the
  intent parser now understands conversational Thai as first-class
  vocabulary — "ตัดช่วงเงียบออก", "ทำเป็นคลิป YouTube" / "ทำเป็นติ๊กต๊อก",
  "ใส่คำบรรยาย" / "ใส่ซับสไตล์ติ๊กต๊อก", "เร่งจังหวะ" / "ช้าลง",
  "ตัดตามจังหวะเพลง", "เปลี่ยนเพลง", "ใส่ทรานสิชั่น", "แนวหนัง/สารคดี" —
  driving the same intents, profiles, and pipelines as English. Compound
  Thai sentences parse to multiple intents; Thai platform names select
  caption styles. Seven test suites' worth of examples pinned, including
  the constitution's own sample commands, plus a Thai CLI smoke line.
- **Personal Workflow Constitution v5.0** recorded in the Knowledge Base:
  the studio is a personal Thai-first editing assistant for one
  professional editor — commercial features (marketplace, licensing,
  multi-user) are descoped; automation, AI memory, and simplicity rank
  above feature count. ROADMAP updated accordingly.
- Performance baselines (Phase 17): best-of-N wall-time suites (generous
  budgets; corelibs XCTest's `measure {}` fails noisy CI runs on >10%
  deviation, so it is deliberately not used) for RationalTime accumulation
  across mixed timescales (100k additions), NTSC frame snapping,
  silence/beat detector throughput on 60 s fixtures, WAV decode of a minute
  of audio, and FCPXML generation/validation on a 1,000-clip timeline with
  200 Thai captions — each asserts correctness alongside the timing so
  slowdowns and wrong output both surface. README capability table now
  lists GhostlyColor, GhostlyAudio, and the agent workflow (15 MCP tools).
- Frame-average seam (GhostlyColor): `FrameAverage` — mean RGB from raw
  8-bit RGB/RGBA/BGRA pixel buffers (pure, cross-platform-tested) plus the
  platform-gated `AVFrameAverageProvider` that samples/downscales real video
  frames and offers one-call `autoWhiteBalance(for:)`. Completes the auto-WB
  chain on Apple platforms: video → frame means → gray-world correction →
  `.cube` LUT.
- Auto white balance (GhostlyColor): `AutoWhiteBalance` — gray-world
  estimate turning frame-average colors into the `ColorAdjustments`
  temperature/tint that neutralize the cast (tint referenced to the R/B
  average so green casts fully correct; black/blown frames yield identity).
  `ghostly lut --neutralize "r g b"` bakes the correction into a .cube LUT.
- Music beds in auto-edits now **duck under the narration in FCPXML**:
  `Clip` gains `volumeKeyframes` (tolerant decode for older documents), the
  FCPXML writer emits `adjust-volume → param(amount) → keyframeAnimation`
  with dB values, and `AutoEditPlanner` bakes a `MusicDucking` envelope
  (−9 dB under storyline content, 0.4 s ramps, 0.35 bed level baked into
  keyframe gains with the flat volume kept as fallback).
- Audio engine core: new `GhostlyAudio` module — `Loudness` (RMS/peak in
  dBFS, peak-ceiling-aware normalization gain; silence-safe) and
  `MusicDucking` (speech ranges → piecewise-linear gain envelope with merge
  gaps and edge-clamped fades, evaluated analytically so keyframes can never
  contradict; applies to samples for rendering). CLI:
  `ghostly normalize-audio` levels a track to a target RMS without clipping;
  CI smoke normalizes and re-analyzes the generated demo WAV. Nine tests
  pin known-sine math, target/ceiling behavior, duck/recover/merge shapes,
  clip-start clamping, and rendered attenuation.
- Color engine core: new `GhostlyColor` module — Adobe `.cube` 3D LUT
  parser/serializer with exact round-trip, trilinear sampling, identity
  generation, and `ColorAdjustments` (exposure EV, contrast pivoted at
  middle gray, saturation, temperature, tint) that bakes any grade into a
  LUT importable by Final Cut/Resolve/ffmpeg. CLI: `ghostly lut` (generate)
  and `ghostly lut-info` (inspect/validate); both CI-smoke-tested.
- **Thai syllable-boundary wrapping**: `ThaiSegmentation` — dictionary-free
  break-opportunity segmentation from Thai orthography (leading vowels bind
  forward; ะ า ๅ ๆ ฯ bind backward; marked clusters and onset+vowel pairs
  start syllables; digit/Latin runs travel whole). Un-timed Thai captions now
  wrap at written-syllable boundaries instead of fixed character counts — no
  more mid-word cuts like "รีวิวก|ล้อง". Deterministic on every platform
  (no ICU); wrapped lines still join back to the original text exactly.
- **Agent mode**: `Workflow` (GhostlyDirector) chains the whole delivery in
  one deterministic call — analyze (WAV or transcript) → auto-edit → captions
  → validated FCPXML → render-preset selection (inferred from the edit's
  format unless named) → the exact ffmpeg export command — and reports a
  human-readable step trace. Exposed as `ghostly workflow` (CLI) and
  `run_workflow` (MCP, 15 tools now). GhostlyDirector now depends on
  GhostlyExport for preset/command building.
- MCP audio tools: `analyze_audio` (WAV → speech ranges, beats/BPM, optional
  speaker turns) and `edit_from_audio` (WAV + command [+ transcript] →
  validated FCPXML with Thai-default captions and optional speaker tagging) —
  AI agents now drive the same real-audio pipeline as `ghostly analyze-audio`
  and `ghostly edit --wav`. Server now exposes 14 tools.
- Speaker diarization (GhostlyDetection): `SpeakerDiarizer` attributes each
  speech range to a voice by clustering autocorrelation pitch + energy
  features — pure, deterministic, capped speaker count, unvoiced ranges
  attributed to the previous speaker. `ghostly edit --wav --diarize` tags
  caption cues with S1/S2/… (ready for lower-thirds), reports the speaker
  count in the edit summary, and `ghostly analyze-audio --diarize` prints
  per-range speakers. Tested with alternating-voice fixtures (stable labels,
  determinism, max-speaker folding, 220 Hz pitch accuracy).
- `MediaExtraction` (GhostlyExport) + `ghostly extract-audio` — deterministic
  ffmpeg recipes for the *input* direction: pull a mono 16 kHz 16-bit WAV (or
  downscaled grayscale frames for scene analysis) out of any video, printed as
  a shell-quoted command so nothing assumes ffmpeg is installed. Completes the
  no-Mac-required bridge: `extract-audio` → `edit --wav` → FCPXML.
- `ghostly edit --wav clip.wav` — auto-edit **real recordings**:
  `EditPipeline.AudioInput` decodes WAV audio, finds speech with the
  `SilenceDetector`, tempo with the `BeatDetector`, and needs no transcript
  at all (pass an SRT/VTT too and Thai captions attach as before). The edit
  summary reports the detected BPM. Rejects empty/pure-silence audio with
  typed errors; covered by four new tests plus CI smoke lines that edit a
  generated WAV end-to-end.
- Real-audio analysis seam (GhostlyDetection): dependency-free `WAV` codec —
  decodes PCM 8/16/24/32-bit and IEEE float 32/64 WAVs on any platform,
  downmixing multichannel to mono, with typed parse errors — plus
  `AudioFixture`, a deterministic synthesizer (silence, speech-band tones,
  seeded noise, BPM click tracks) whose byte-identical WAV output pins
  detector behavior in CI without media files in the repo. New CLI commands:
  `ghostly analyze-audio <file.wav>` (speech ranges + beat onsets/BPM from
  real audio) and `ghostly demo-audio` (writes the canonical demo WAV);
  both smoke-tested on CI.
- `EditPipeline` (GhostlyDirector) + **`ghostly edit`** command — the first
  end-to-end editing entry point: a transcript (SRT/WebVTT) plus a declared
  clip duration and a natural-language command go through intent parsing,
  pacing, auto-edit planning, and caption attachment to a **validated FCPXML
  document** in one call. Cue timings double as speech ranges, so the entire
  chain is deterministic and CI-tested without media; `--lang` defaults to
  `th` (Thai-first). Cues past the declared duration are clamped/dropped;
  out-of-range inputs fail with typed errors. Pairs with `ghostly transcribe`
  for the audio → SRT step on a real machine.
- `GhostlyTranscription`: new module — the Whisper seam. `Transcribing`
  protocol, `WhisperJSONParser` (whisper.cpp full-JSON → word-timed
  `SubtitleTrack`, millisecond-exact offsets, control tokens like `[_BEG_]`
  filtered, detected language carried through — fixture-tested with Thai
  output), and `WhisperCLITranscriber` (injectable-runner CLI wrapper with
  token-level timestamps via --max-len 1). New `ghostly transcribe` command:
  audio → Thai/any-language SRT with a local whisper.cpp model.
- `ThaiNumber` — Thai numeral verbalization for captions/voiceover text:
  `spell` (150 → "หนึ่งร้อยห้าสิบ", เอ็ด/ยี่สิบ/ล้าน rules) and `verbalize`
  (rewrites Arabic and Thai digits inside text, decimals read as "จุด…"),
  plus `SubtitleTrack.verbalizingThaiNumbers()` (timing-preserving).
- `auto_edit` MCP tool accepts a `language` argument (BCP-47) so agents can
  request Thai (or CJK) captions in a single call — tags the caption track,
  driving character-based wrapping and the `ITT.th` FCPXML role.
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
