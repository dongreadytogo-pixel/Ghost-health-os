# Architecture

Ghostly790k AI Final Cut Studio follows Clean Architecture: inner layers know
nothing about outer layers, every module is an independent SwiftPM target with
its own test suite, and all cross-module contracts are value types + protocols.

## Layers and targets

| Layer | Target | Responsibility | Depends on |
|---|---|---|---|
| Core | `GhostlyCore` | Rational time math, `TimeRange`, `FrameRate`, `StudioError`, pluggable `Logger` | — |
| Domain | `GhostlyDomain` | Entities: `Asset`, `Clip`, `Timeline`, `Project/Event/Library`, `Caption`, `Marker`, `Transition`, `Role`, typed IDs | Core |
| Infrastructure | `GhostlyFCPXML` | FCPXML writer/reader/validator + deterministic XML DOM | Core, Domain |
| Infrastructure | `GhostlySubtitles` | SRT/WebVTT codecs, word-timed cues, `CaptionStyle` presets | Core, Domain, FCPXML |
| AI Engine | `GhostlyDetection` | Silence/beat/scene detection (pure DSP) + provider protocols + AVFoundation adapter (Apple only) | Core, Domain |
| Application | `GhostlyAssets` | Auto-tagging, collections/folders/favorites, natural-language search, duplicate/unused finders | Core, Domain |
| Application | `GhostlyExport` | Render presets, FFmpeg command builder, injectable-renderer render queue | Core, Domain |
| Infrastructure | `GhostlyStorage` | `ProjectRepository` port + file-backed store: atomic JSON envelopes, schema migration, bounded snapshots, autosave/recovery | Core, Domain |
| Ecosystem | `GhostlyPlugin` | Plugin manifest (`plugin.json`), semantic versioning, lifecycle state machine, registry with contribution queries | Core |
| Application | `GhostlyDirector` | `EditIntentParser`, `PacingProfile`, `Director`, `AutoEditPlanner` | Core, Domain, Detection, FCPXML, Subtitles |
| AI Engine | `GhostlyAI` | `LLMProvider` protocol, Anthropic/OpenAI-compatible/Gemini/Ollama adapters, `ModelRouter` | Core, Domain |
| Application | `GhostlyLearning` | `PreferenceStore` (local JSON, atomic writes), usage stats, recommendations | Core, Domain |
| Interface | `GhostlyMCP` | JSON-RPC 2.0, MCP server core, 7 studio tools | all engines |
| Presentation | `GhostlyApp` | SwiftUI shell (`#if canImport(SwiftUI)`) | Director, MCP, Learning, AI |
| Executables | `GhostlyCLI`, `GhostlyMCPServer` | Terminal + agent entry points | engines |

## Key design decisions

### Rational time everywhere
FCPXML times are rational (`3003/3000s`). `RationalTime` (Int64/Int32,
auto-reduced) is used for **all** timeline math; float seconds appear only at
UI/JSON edges. Exact accumulation is covered by a 10,000-frame drift test.

### Time-coordinate discipline in FCPXML
The subtle part of FCPXML is that children of a clip are positioned in the
clip's **source** time, not timeline time. `FCPXMLWriter`/`FCPXMLReader`
centralize the `timeline ↔ source` mapping (`T − offset + start`) and the
round-trip is tested with non-zero in-points.

### Determinism as a feature
The XML serializer orders attributes stably and the auto-editor is a pure
function of its inputs, so the same command over the same analysis yields
byte-identical FCPXML — testable, diffable, cacheable.

### Detection is pure, extraction is pluggable
Detectors (`SilenceDetector`, `BeatDetector`, `SceneChangeDetector`) operate
on plain arrays. Media decoding is behind `AudioSampleProviding` /
`FrameHistogramProviding`; the AVFoundation implementation activates on Apple
platforms, tests inject fixtures, and an FFmpeg provider can be added without
touching detector code.

### Multi-AI routing
`ModelRouter` routes by capability (`editing`, `vision`, `fast`, `local`, …)
with priority ordering, local-first policy, and automatic fallback across
providers on failure. Provider adapters share an injectable `HTTPTransport`,
so they are fully unit-tested without network.

### MCP tool failures are results
Per the MCP spec, tool errors return `isError: true` content instead of
JSON-RPC protocol errors, so agents can read and react to the message.

### Learning stays local
`PreferenceStore` persists to `~/.ghostly/preferences.json` atomically,
quarantines corrupt files instead of crashing, and ranks recommendations by
frequency with a 30-day half-life recency decay. Nothing is transmitted.

## Error handling

One error currency: `StudioError` (typed cases + stable machine codes).
Modules map external failures into it at their boundary; UI/MCP/CLI render it
uniformly.

## Concurrency

Actors own mutable state (`ModelRouter`, `PreferenceStore`, `MCPServer`);
everything else is `Sendable` value types. Swift 6 strict-concurrency clean.

## Extension points (future work)

- **Whisper transcription**: produces `SubtitleTrack` with word timings — the
  caption pipeline is already word-timing aware.
- **Plugin SDK**: plugins will register `MCPTool`s and `PacingProfile`s; the
  registry pattern in `MCPServer.register` is the seam.
- **Premiere/Resolve export**: implement a new writer over the same
  `Timeline` domain model.
