# 18 — Glossary

- **A-roll / B-roll** — primary footage / supporting overlay footage.
- **Appcast** — Sparkle's update feed (XML).
- **Asset** — a media file (video/audio/image) referenced by clips.
- **Audition** — FCP container of alternate takes in one timeline slot.
- **Chapter marker** — marker kind that becomes a chapter (YouTube/podcast).
- **Compound clip** — nested timeline used as a single clip.
- **Connected clip** — clip attached above/below the primary storyline
  (non-zero lane) that moves with its anchor.
- **CTA** — call to action; closing prompt (subscribe/follow/buy).
- **Drop frame (DF/NDF)** — timecode counting convention for 29.97 fps;
  FCPXML `tcFormat`.
- **FCPXML** — Final Cut Pro's XML interchange format (see 02).
- **Frame duration** — length of one frame as a rational (`1001/30000s`).
- **Gap clip** — explicit empty region in the storyline.
- **Hook** — the attention-grabbing opening seconds.
- **HDR / HLG / PQ** — high dynamic range; broadcast-compatible transfer /
  absolute-nits transfer.
- **J cut / L cut** — audio leads picture / audio trails picture.
- **Keyword range** — tag applied to a time range of a clip.
- **Lane** — vertical position relative to the storyline (0 = spine).
- **Library / Event / Project** — FCP containment hierarchy (see 01).
- **Loudness (LUFS/LKFS)** — perceptual program loudness units.
- **LUT** — color lookup table (`.cube`); camera vs creative.
- **Magnetic timeline** — FCP's ripple-by-default, gapless storyline model.
- **Marker** — point annotation (standard / to-do / chapter).
- **MCP** — Model Context Protocol; agent↔tool JSON-RPC standard.
- **Motion template** — Motion project published as FCP title/effect/
  generator/transition.
- **Multicam clip** — synchronized camera angles switchable in the viewer.
- **NTSC rates** — 23.976/29.97/59.94 fps (×1000/1001) rational rates.
- **Optimized / proxy media** — ProRes transcode for editing / lightweight
  editing copy.
- **Primary storyline / spine** — the central clip sequence of a timeline.
- **Published parameter** — Motion parameter exposed to FCP's inspector.
- **Rational time** — exact time as integer numerator/denominator seconds.
- **Rig** — Motion widget grouping multiple parameters.
- **Ripple / roll / slip / slide** — trim types: move edit & shift
  downstream / move edit between neighbors / change content keeping
  position / move clip between neighbors.
- **Role / subrole** — typed content lane (Dialogue, Music…, `music.m-1`).
- **Secondary storyline** — connected container holding its own clip run.
- **Snapshot** — frozen copy of a project (versioning).
- **Spine** — FCPXML element holding the storyline sequence.
- **Storyline end** — timeline position after the last spine clip.
- **Synchronized clip** — video + external audio aligned as one clip.
- **Timecode (tcStart)** — sequence start timestamp.
- **True peak (dBTP)** — inter-sample peak level limit.
- **Word timing** — per-word start/end times in a transcript (karaoke
  captions).
