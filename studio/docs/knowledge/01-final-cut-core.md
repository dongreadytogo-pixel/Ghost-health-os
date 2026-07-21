# 01 — Final Cut Pro Core Concepts

Source: Final Cut Pro User Guide (https://support.apple.com/guide/final-cut-pro/).
Domain mapping refers to `studio/Sources/GhostlyDomain`.

## Containment hierarchy

```
Library (.fcpbundle)
└── Event
    ├── Media (clips imported into the event)
    └── Project (one timeline each)
        └── Timeline (sequence)
```

- **Library** — the top-level document; owns events, media references, and
  render files. Maps to `GhostlyDomain.Library`.
- **Event** — an organizational bucket inside a library for media + projects.
  Maps to `GhostlyDomain.Event`.
- **Project** — an editable sequence with a fixed video format (resolution,
  frame rate, color space). Maps to `GhostlyDomain.Project`.
- **Timeline** — the editing surface of a project. Maps to
  `GhostlyDomain.Timeline`.

## Main UI surfaces

- **Browser** — media bin: filter by keyword, rating, media type.
- **Viewer** — playback of the browser selection or timeline.
- **Inspector** — parameters of the selection (video/audio/info panes).
- **Timeline index** — searchable list of clips, tags, and roles.

## The Magnetic Timeline

FCP's defining editing model:

- The **primary storyline** is a single spine of clips with *no gaps and no
  overlaps*; edits ripple automatically (magnetism).
- Explicit **gap clips** occupy intentional empty time.
- **Connected clips** attach to a storyline clip at a timeline position and
  follow it when it moves. Vertical stacking uses **lanes**: positive lanes
  above the spine (video/titles), negative lanes below (audio/music).
- A **secondary storyline** is a container of clips connected as one unit.

Our model mirrors this exactly: `Clip.lane == 0` is the storyline;
`Timeline.validate()` enforces no-gap/no-overlap; the FCPXML writer emits
`gap` elements and nests connected clips inside their anchor clip.

## Clip containers

- **Compound clip** — a nested timeline usable as a single clip (FCPXML
  `ref-clip` referencing a `media` resource).
- **Synchronized clip** — video + external audio aligned by waveform
  (`sync-clip`).
- **Multicam clip** — camera angles switched live (`mc-clip` with angles).
- **Audition** — a set of alternative takes occupying one timeline slot.

## Organization & metadata

- **Roles / subroles** — typed lanes of content: Video, Titles, Dialogue,
  Music, Effects; custom roles allowed (e.g. `music.music-1`). Drive audio
  mixing, export stems, and timeline appearance. Maps to `Role`.
- **Keywords** — ranged tags applied to clip sections (`KeywordRange`).
- **Favorites / Rejects** — ranged ratings for triage; rejected ranges can be
  hidden or excluded from search.
- **Markers** — point annotations: standard, to-do (completed flag), and
  chapter markers (used for YouTube/podcast chapters). Maps to `Marker.Kind`.

## Media management

- **Proxy media** — lightweight transcodes (ProRes Proxy / H.264) for smooth
  editing; toggled per-viewer, relinked at export.
- **Optimized media** — ProRes 422 transcodes for maximum edit performance.
- **Background rendering** — FCP renders timeline segments during idle time;
  render files live in the library bundle.

## Versioning

- **Project snapshots** — frozen copies of a project at a point in time
  (our `GhostlyStorage` snapshots serve the same purpose programmatically).
