# 02 — FCPXML Specification

Source: Apple FCPXML Reference
(https://developer.apple.com/documentation/professional-video-applications/fcpxml-reference).
Implementation: `studio/Sources/GhostlyFCPXML` (writer/reader/validator).

## Versions

| fcpxml version | Introduced with | Notes |
|---|---|---|
| 1.8 | FCP 10.4.1 | legacy baseline |
| 1.9 | FCP 10.4.9 | |
| 1.10 | FCP 10.6 | `fcpxmld` bundle format added |
| 1.11 | FCP 10.6.6 | our default output version |
| 1.12 | FCP 10.7 | |
| 1.13 | FCP 11 | |

FCP imports older versions; it exports only the current one. A `.fcpxmld`
bundle is a folder containing `Info.fcpxml`. Our validator accepts 1.9–1.13.

## Document shape

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE fcpxml>
<fcpxml version="1.11">
  <resources> … </resources>
  <library>
    <event name="…">
      <project name="…">
        <sequence format="r1" duration="…" tcStart="0s" tcFormat="NDF">
          <spine> … </spine>
        </sequence>
      </project>
    </event>
  </library>
</fcpxml>
```

## Time syntax (critical)

All times are **rational seconds**: `"3003/3000s"`, `"5s"`, `"0s"`. Never
floating point. Edit points must be frame-aligned (multiples of the format's
`frameDuration`). Implemented exactly by `GhostlyCore.RationalTime`
(`init?(fcpxml:)` / `description`).

Frame rates are rational too: 29.97 fps → `frameDuration="1001/30000s"`.

## Time attributes & coordinate rules

- `offset` — element position **in its parent's timeline**.
- `start` — the clip's **source in-point** (where in the media it begins).
- `duration` — length.
- Children of a clip (markers, keywords, captions, connected clips, titles)
  are positioned in the **parent clip's source time**: timeline instant `T`
  inside a clip with offset `O` and start `S` maps to `T − O + S`.
  This is the most common generator bug; round-trip tested in
  `FCPXMLTests.testRoundTripSourceTimeConversionForNonZeroInPoint`.

## Resources

- `format` — `frameDuration`, `width`, `height`, `colorSpace`
  (`1-1-1` Rec. 709, `9-9-9` Rec. 2020, `9-18-9` HLG, `9-16-9` PQ).
- `asset` — media file: `start`, `duration`, `hasVideo`, `hasAudio`,
  `format`, plus `media-rep` child with `kind="original-media"` and file URL.
- `media` — container for compound-clip/multicam innards.
- `effect` — a Motion template or built-in effect: `name`, `uid`.
- Resource ids are document-unique strings, conventionally `r1, r2 …`.
  Every `ref` must resolve — our validator enforces this.

## Story elements (inside `spine`)

- `asset-clip` — a clip referencing an `asset` (`ref`); attributes above plus
  `enabled`, `lane`, `audioRole`/`videoRole`, `tcFormat`.
- `gap` — explicit empty spine time; the spine must tile `[0, duration)`
  contiguously (validator checks).
- `transition` — sits between spine clips; `offset` is its leading edge;
  optional `filter-video ref` selects the effect (default cross dissolve).
  Both neighbors need media handles ≥ the transition duration.
- `clip`, `video`, `audio` — lower-level clip forms.
- `ref-clip` — compound clip instance; `mc-clip` — multicam; `sync-clip` —
  synchronized clip.
- `title` — Motion title instance (`ref` → `effect` resource) with `text` and
  `text-style-def` children. Emitted by our writer for `MotionTitle`.
- `caption` — closed caption in a role like `iTT?captionFormat=ITT.en`;
  contains `text`/`text-style` and is anchored to its parent clip in source
  time. CEA-608 and SRT caption roles also exist.
- `marker` (`start`, `duration`, `value`, optional `completed` for to-dos),
  `keyword` (`start`, `duration`, `value` comma-separated),
  `metadata` — arbitrary key/value annotations.
- `audio-role-source`, `adjust-volume` (dB), `filter-video`/`filter-audio`
  with `param` children — per-clip adjustments/effects.

## Import/export rules

- FCP requires resources to be declared before use; unknown elements are
  ignored on import but invalid *references* fail the import.
- Captions must be children of the clip they overlap.
- Import: File → Import → XML. Export: File → Export XML (choose version).

## Best practices (enforced by our engine)

1. Emit rational times only; snap edit points to `frameDuration`.
2. Keep the spine contiguous; use explicit `gap`s.
3. Deduplicate `format`/`asset`/`effect` resources (our `ResourceTable`).
4. Escape XML entities in names/text (`XML.escape`).
5. Validate before offering a file to FCP (`FCPXMLValidator`).
