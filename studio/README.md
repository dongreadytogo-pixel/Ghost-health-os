# Ghostly790k AI Final Cut Studio

An AI-native companion for Final Cut Pro: natural-language editing, automatic
timeline construction, subtitle generation, media analysis, a learning system,
and an MCP server so any AI agent (Claude Code, Cursor, VS Code, local models)
can drive the studio.

The platform is a Swift package. The engines are pure cross-platform Swift —
they build and test on macOS **and** Linux — while the SwiftUI presentation
layer activates on macOS.

## What works today

| Capability | Module | Status |
|---|---|---|
| Frame-accurate rational time & timeline model | `GhostlyCore`, `GhostlyDomain` | ✅ tested |
| FCPXML generate / parse / validate (v1.9–1.13) | `GhostlyFCPXML` | ✅ tested, round-trip |
| SRT + WebVTT parse/serialize, word timings | `GhostlySubtitles` | ✅ tested |
| Platform caption styles (TikTok/YouTube/Instagram/Broadcast) | `GhostlySubtitles` | ✅ tested |
| Silence, beat, and scene-change detection | `GhostlyDetection` | ✅ tested (pure DSP) |
| Natural-language edit commands → edit plans | `GhostlyDirector` | ✅ tested |
| AI auto-editor (silence removal, beat cuts, music bed, captions) | `GhostlyDirector` | ✅ tested |
| Highlight / hook / CTA / chapter detection | `GhostlyDirector` | ✅ tested |
| Motion graphics (lower thirds, titles, callouts…) → FCPXML `<title>` | `GhostlyDirector` + `GhostlyFCPXML` | ✅ tested |
| Subtitle auto-punctuation for raw ASR | `GhostlySubtitles` | ✅ tested |
| Asset manager (auto-tagging, collections, NL search) | `GhostlyAssets` | ✅ tested |
| Undo/redo command system + domain events | `GhostlyDomain` | ✅ tested |
| MCP server with 8 studio tools | `GhostlyMCP` | ✅ tested |
| Multi-AI router (Claude, OpenAI-compatible, Gemini, Ollama, LM Studio) | `GhostlyAI` | ✅ tested |
| Local learning system (preferences, usage, recommendations) | `GhostlyLearning` | ✅ tested |
| `ghostly` CLI | `GhostlyCLI` | ✅ CI smoke-tested |
| SwiftUI studio shell (prompt panel, task queue, styles, logs) | `GhostlyApp` | ✅ builds on macOS |

See [docs/ROADMAP.md](docs/ROADMAP.md) for what's next.

## Installation

Requirements: Swift 6 toolchain (Xcode 16+ on macOS, or `swift:6.0` on Linux).

```sh
cd studio
swift build -c release
swift test                       # full suite
```

Binaries land in `.build/release/`:

- `ghostly` — command-line toolbox
- `ghostly-mcp-server` — MCP stdio server

## Quick start

### Natural-language editing (CLI)

```sh
ghostly intent "edit this like marvel and cut to the beat"
ghostly captions talk.srt --style TikTok --out styled.srt
ghostly validate export.fcpxml
ghostly analyze export.fcpxml
ghostly styles
```

### Drive it from an AI agent (MCP)

Add to your MCP client config (Claude Code shown):

```json
{
  "mcpServers": {
    "ghostly": { "command": "/path/to/ghostly-mcp-server" }
  }
}
```

Exposed tools: `auto_edit`, `parse_edit_command`, `generate_captions`,
`validate_fcpxml`, `analyze_timeline`, `find_highlights`, `search_assets`,
`list_caption_styles`, `recommend`.
See [docs/MCP.md](docs/MCP.md) for schemas and examples.

### As a library

```swift
import GhostlyDirector
import GhostlyFCPXML

let plan = try Director().interpret("create a tiktok, remove silence")
let timeline = try AutoEditPlanner(profile: plan.profile)
    .plan(footage: analyzedFootage, transcript: transcript)
let fcpxml = try FCPXMLWriter().document(
    for: Project(name: "Short", timeline: timeline), assets: assets)
```

Import the generated `.fcpxml` into Final Cut Pro via **File → Import → XML**.

## Architecture

Clean Architecture with strictly layered, independently testable modules —
see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Dependency direction:

```
GhostlyApp (SwiftUI, macOS)   GhostlyCLI   GhostlyMCPServer
        └──────────────┬─────────┴───────────────┘
                 GhostlyMCP  GhostlyAI  GhostlyLearning
                       └──────┬───────────┘
        GhostlyDirector ── GhostlyDetection ── GhostlySubtitles
                       └──────┬───────────┘
                 GhostlyFCPXML ── GhostlyDomain ── GhostlyCore
```

## Development

- `swift test --parallel` runs ~90 unit/integration tests.
- CI (`.github/workflows/studio-ci.yml`) builds and tests on Linux
  (`swift:6.0` container) and macOS, and smoke-tests both executables
  including a live MCP handshake.
- All logging goes through `GhostlyCore.Logger`; the MCP server logs to
  stderr only (stdout is the protocol channel).

## License

MIT (same as the repository).
