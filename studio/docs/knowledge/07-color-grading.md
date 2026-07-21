# 07 — Color Grading

Source: Final Cut Pro User Guide (Color correction chapters).

## Tools (Inspector → Color, ⌘6)
- **Color Board** — puck-based global/shadow/midtone/highlight adjust.
- **Color Wheels** — master + 3-way wheels with exposure/saturation.
- **Color Curves** — per-channel luma/RGB curves.
- **Hue/Saturation Curves** — hue-vs-hue, hue-vs-sat, hue-vs-luma, sat-vs-sat,
  color-of-interest picks (skin, sky, product isolation).
- **Color Adjustments** (10.6.6+) — slider-based exposure/contrast/etc.
- **Match Color** (⌥⌘M) — statistical match of one shot to another.
- **Auto white balance** — via the Balance Color command (auto or WB picker).
- **Masks + tracking** — every correction accepts shape/color masks; masks
  can follow the Object Tracker.

## Scopes (⌘7)
Waveform (luma/RGB), Vectorscope (skin-tone line ~33°), Histogram, RGB
Parade. Grade to scopes, not to a monitor's mood.

## Color management
- Library color processing: **Standard (Rec. 709)** or **Wide Gamut HDR**.
- FCPXML `colorSpace` codes: `1-1-1` Rec. 709 · `9-9-9` Rec. 2020 ·
  `9-18-9` HLG · `9-16-9` PQ (our `VideoFormat.ColorSpace`).
- **Log footage** — flat, wide-latitude camera encodings (S-Log3, C-Log,
  V-Log, Apple Log). Apply the manufacturer's **Camera LUT** at the clip
  level (Info inspector) before creative grading.
- **LUTs** — 3D lookup tables (`.cube`); *Camera LUT* normalizes to Rec.709,
  *Custom LUT effect* applies creative looks. Order: camera LUT → corrections
  → creative LUT.
- **HDR** — HLG (broadcast, backward compatible) vs PQ/HDR10 (absolute
  nits); use the HDR Tools effect for SDR↔HDR conversion; target ~100 nits
  reference white for HLG graphics.
- **ACES** — interchange color system (scene-linear, IDT/ODT); FCP itself is
  not ACES-native; round-trips go through Resolve/Compressor pipelines.

## Cinema workflow (order of operations)
1. Normalize (camera LUT / log conversion)
2. Balance every shot (exposure, WB) — scopes
3. Shot-match within scenes (Match Color + manual)
4. Creative grade (curves, wheels, look LUT)
5. Secondaries (skin isolation via hue-sat masks, sky, product)
6. Verify broadcast/platform limits

## Studio automation hooks
Histogram statistics from `FrameHistogramProviding` feed auto white balance
and exposure suggestions (roadmap M3); scene-cut detection already uses the
same histograms.
