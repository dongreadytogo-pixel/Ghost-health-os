# 08 — Audio System

Source: Final Cut Pro User Guide (Audio chapters); Logic effects reference.

## Roles-based mixing
Audio roles (**Dialogue**, **Music**, **Effects** + custom subroles like
`music.music-1`) are FCP's mixer: the timeline index can solo/mute whole
roles, exports can produce **role stems** (broadcast deliverables), and
lane order follows roles. FCPXML: `audioRole` attribute — mapped by
`GhostlyDomain.Role`.

## Repair & enhancement (Audio inspector)
- **Loudness** — one-knob leveler.
- **Noise Removal** — broadband denoise (percentage).
- **Hum Removal** — 50/60 Hz notch.
- **Voice Isolation** (10.6.2+) — ML speech/background separation.
- **EQ presets** + full **Channel EQ**.

## Logic-derived effects
Channel EQ, Compressor, Limiter, DeEsser, Noise Gate, Space Designer
(convolution reverb), Delay Designer — all parameterized in FCPXML via
`filter-audio` + `param`.

## Mixing conventions
- Dialogue anchors around −12 to −6 dBFS peaks; music beds duck 12–20 dB
  under speech (our planner sets music bed volume 0.35 ≈ −9 dB).
- Keyframe or role-based **ducking**; fades via fade handles or
  `adjust-volume` keyframes (FCPXML `param name="volume"` keyframes).
- **Loudness targets**: streaming ≈ −14 LUFS integrated (YouTube/Spotify);
  broadcast: EBU R128 −23 LUFS / ATSC A/85 −24 LKFS; podcasts commonly
  −16 LUFS stereo / −19 mono; true peak ≤ −1 dBTP.

## Beat & rhythm
Music beat detection (our `BeatDetector`: energy-flux onsets + BPM
estimation) drives beat-aligned cuts (`cutOnBeats` profiles) and marker
generation.

## Podcast workflow preset
1. Voice Isolation / Noise Removal on dialogue
2. Channel EQ high-pass ~80 Hz, presence boost 2–5 kHz
3. Compressor ~3:1, −18 dBFS threshold
4. Limiter to −1 dBTP, master to −16 LUFS
5. Chapter markers from our `HighlightPlanner.chapters`

## Silence handling
`SilenceDetector` (RMS + hysteresis + min-duration absorption) marks speech
vs silence; profiles choose full or partial silence removal
(`PacingProfile.silenceRemoval`), keeping breathing room for podcasts.
