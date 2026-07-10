# MCP Server Guide

`ghostly-mcp-server` exposes the studio to AI agents over the Model Context
Protocol (stdio transport, protocol version `2024-11-05`).

## Setup

Claude Code (`.mcp.json` or global config):

```json
{
  "mcpServers": {
    "ghostly": {
      "command": "/path/to/ghostly-mcp-server",
      "env": { "GHOSTLY_HOME": "~/.ghostly" }
    }
  }
}
```

Cursor, VS Code, and any other MCP-capable client use the same shape.
`GHOSTLY_HOME` (optional) controls where the learning system stores
preferences; default is `~/.ghostly`.

## Tools

### `auto_edit`
Natural-language command + analyzed footage → complete, validated FCPXML.

```json
{
  "command": "create a tiktok, remove silence, cut to the beat",
  "projectName": "Episode teaser",
  "footage": [
    {
      "name": "interview",
      "url": "file:///media/interview.mov",
      "durationSeconds": 300,
      "speechRanges": [[2.5, 61.0], [65.2, 190.0]],
      "sceneCuts": [45.0, 120.0]
    }
  ],
  "music": {
    "name": "track", "url": "file:///media/track.wav",
    "durationSeconds": 180, "kind": "audio",
    "beats": [0.5, 1.0, 1.5, 2.0]
  },
  "transcriptSRT": "1\n00:00:02,500 --> 00:00:04,000\nWelcome back\n"
}
```

Times are seconds. Detection data is optional — without `speechRanges` the
planner falls back to scene cuts, then to whole-asset. Pass `"language": "th"`
(BCP-47) to produce Thai captions (character-based wrapping + `ITT.th` role).
The returned FCPXML has already passed the structural validator; import it with
**File → Import → XML** in Final Cut Pro.

### `parse_edit_command`
`{ "command": "edit this like marvel" }` → recognized intents plus the fully
resolved pacing profile (shot lengths, format, captions, beat-cutting).
Useful for previewing what `auto_edit` would do.

### `generate_captions`
`{ "subtitles": "<SRT or VTT content>", "style": "TikTok", "shiftSeconds": 1.0,
"autoPunctuate": true }` → restyled SRT (wrapping, casing) plus style
metadata. Styles: `TikTok`, `YouTube`, `Instagram`, `Broadcast`.
`autoPunctuate` capitalizes and adds terminal punctuation for raw ASR
transcripts (timing preserved; a no-op on Thai/CJK). `language` (BCP-47, e.g.
`th`) makes Thai/CJK wrap by character instead of by spaces and tags the
FCPXML caption role (`ITT.th`).

### `validate_fcpxml`
`{ "fcpxml": "<document>" }` → `{ valid, errors[], warnings[] }`. Checks XML
well-formedness, fcpxml version, resource-reference integrity, rational-time
syntax, and spine continuity.

### `analyze_timeline`
`{ "fcpxml": "<document>" }` → structural report per project: duration, clip
counts, average shot length, captions/markers/transitions, and any domain
problems found.

### `find_highlights`
`{ "footage": { "name": "...", "url": "...", "durationSeconds": 300,
"speechRanges": [[5,35]], "sceneCuts": [15,30], "beats": [...] },
"transcriptSRT": "...", "limit": 5 }` → the strongest opening `hook`, ranked
`highlight` moments, a synthesized `cta` beat, and `chapters` (with
transcript-derived titles when available). Deterministic — ideal for
short-form repurposing and auto-chaptering.

### `search_assets`
`{ "query": "vertical 4k drone clips under 30 seconds", "assets": [ { "name":
"...", "url": "...", "durationSeconds": 12, "kind": "video", "width": 1080,
"height": 1920, "favorite": false } ] }` → auto-tags each asset (resolution,
aspect, duration band, filename tokens) then returns ranked matches with their
derived tags. Understands kinds, favorite/vertical/horizontal, and
"under/over N seconds|minutes" bounds.

### `export_command`
`{ "input": "cut.mov", "output": "final.mp4", "preset": "TikTok", "title":
"...", "artist": "...", "comment": "..." }` → the resolved preset (container,
codec, resolution, fps, bitrate), the FFmpeg argument vector, and a
copy-paste `commandLine`. Presets: `YouTube 1080p`, `YouTube 4K`, `TikTok`,
`Instagram Reel`, `Instagram Feed`, `ProRes 422 Master`. NTSC rates stay exact
(`30000/1001`); MP4/MOV get `+faststart`; metadata is embedded via `-metadata`.

### `list_export_presets`
No arguments → the built-in render presets with container, codec, resolution,
and bitrate.

### `validate_plugin_manifest`
`{ "manifest": "<plugin.json contents>", "studioVersion": "1.0.0" }` →
validates the manifest against the Plugin SDK (semantic versions, reverse-DNS
id, entry point, permissions, contributions) and, when `studioVersion` is
given, reports compatibility. Invalid manifests return `isError: true`.

### `list_caption_styles`
No arguments → the built-in caption presets with fonts, sizes, positions and
animations.

### `analyze_audio`
`{ "audioPath": "/path/clip.wav", "diarize": true }` → duration, speech
ranges, beat onsets + BPM from a real WAV file, and with `diarize` the
speaker turns (`S1`, `S2`, …). Convert other formats first (see
`ghostly extract-audio` for the ffmpeg recipe).

### `edit_from_audio`
`{ "audioPath": "/path/clip.wav", "command": "create a tiktok with captions",
"transcriptSRT": "…", "language": "th", "diarize": true }` → auto-edits a
real recording end-to-end (speech detection → plan → captions → validated
FCPXML). `language` defaults to `th`; `diarize` tags caption cues with
speakers. Returns the FCPXML plus clip/caption/BPM/speaker metadata.

### `recommend`
`{ "category": "transition", "limit": 5 }` → the user's learned favorites for
`font`, `captionStyle`, `transition`, `effect`, `lut`, `exportPreset`,
`asset`, or `pacingStyle`, ranked by recency-weighted usage.

## Error semantics

- Malformed JSON-RPC → protocol error (`-32700` / `-32600` / `-32601`).
- Tool-level failures (bad arguments, validation failures) → **successful**
  JSON-RPC response with `isError: true` and a human-readable message, per
  the MCP specification, so agents can self-correct.

## Logging

The server writes logs to **stderr** exclusively; stdout carries only
newline-delimited JSON-RPC frames.
