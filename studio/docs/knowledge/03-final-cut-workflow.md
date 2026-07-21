# 03 — Final Cut Pro Workflow

Source: Final Cut Pro User Guide. The studio automates stages of this
pipeline; each stage lists the responsible module.

## 1. Import
Media arrives via File → Import (camera, folder, drag-in). Options: copy
into library vs. leave in place; create proxy/optimized media; audio-channel
analysis. *Studio:* `EditJob.FootageItem` / `AssetItem` describe imported
media to the engines.

## 2. Organize
Events per shoot/day; ranged **keywords** (manual or smart-collection
driven); **favorites/rejects** triage; role assignment at import.
*Studio:* `GhostlyAssets` (AutoTagger, collections, folders, NL search).

## 3. Sync
Dual-system sound → synchronized clips (waveform alignment); multicam clips
from multiple angles (timecode/audio sync).

## 4. Proxy
Generate proxy media for high-res/log footage; edit against proxies, relink
to originals for export.

## 5. Edit
Assemble the primary storyline (append `E`, insert `W`, connect `Q`), then
refine: trim, roll, slip, slide, blade. Connected B-roll, music on negative
lanes, transitions on cut points.
*Studio:* `AutoEditPlanner` produces this assembly from detections;
`EditCommand`/`TimelineDocument` provide undo-safe programmatic edits.

## 6. Audio
Role-based mixing; dialogue repair (noise removal, voice isolation), music
ducking, loudness targets (see 08).
*Studio:* silence/beat detection feeds the planner; volume via
`adjust-volume` in FCPXML.

## 7. Color
Balance → match → creative grade → scopes verification (see 07).

## 8. Motion graphics
Titles, lower thirds, callouts from Motion templates (see 06).
*Studio:* `MotionGraphicsLibrary` → `MotionTitle` → FCPXML `title`.

## 9. Subtitles
Captions (iTT/CEA-608/SRT) authored inline or imported; styled per platform.
*Studio:* `GhostlySubtitles` + `generate_captions` tool.

## 10. Review
Timeline index sweep for to-do markers; full-length playback; client review
exports (H.264 draft).

## 11. Export / Publish
Share destinations (Master file, Apple Devices, YouTube presets…) or Compressor
for custom settings; export XML for interchange; export captions per format.
*Studio:* `GhostlyExport` presets + FFmpeg command builder; `export_command`
MCP tool.

## Interchange loop used by this studio

```
FCP → Export XML → ghostly (analyze / auto-edit / captions) → validated FCPXML → FCP Import XML
```
