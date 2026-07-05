# 05 — Effect Library

Source: Final Cut Pro User Guide (Effects/Transitions chapters). In FCPXML,
every applied effect is a `filter-video`/`filter-audio` referencing an
`effect` resource by `uid` — built-ins use `FxPlug:` UIDs, Motion templates
use their bundle path (see 06).

## Transitions
Cross Dissolve (default, `FxPlug:4731E73A-8DAC-4113-9A30-AE85B1761265`),
Fade to Color, Wipes, Slides, Spins, Object transitions, Flow (optical-flow
morph for jump cuts), Audio crossfade. Both neighbors need media handles at
least as long as the transition; `AutoEditPlanner.addTransitions` skips cuts
without handles.

## Generators
Placeholder, Timecode, Shapes, Solids/Color, Gradients, Custom (Motion).
FCPXML: `video ref` to a generator `effect` resource.

## Titles & callouts
Build In/Out titles, Lower Thirds, Social templates, Callouts (arrows,
shapes). All are Motion titles → our `MotionTitle.Kind` catalog.

## Masks & keyers
- **Shape Mask / Draw Mask** — per-effect or per-clip alpha regions.
- **Scene Removal Mask** (FCP 10.6+) — ML background removal without green
  screen.
- **Keyer** — chroma key with automatic sampling; **Luma Keyer**.

## Stylize / look categories
Blur (Gaussian, Directional, Zoom, Prism), Distortion (Earthquake, Water,
Fisheye), Light (Glow, Bloom, Highlights), Looks (film stocks, vintage,
comic), Noise/Grain, Tiling, Camera Shake ("Handheld").
The studio's planned Effects Generator maps prompt terms → these categories
(glow, neon, fire, rain, snow, film grain, camera shake, light leak,
vintage, cyberpunk).

## Color effects
Color Wheels, Color Board, Curves, Hue/Saturation Curves, Color Adjustments
— see 07.

## Tracking
- **Object Tracker** (FCP 10.6+): machine-learning point/face tracking;
  drag any effect/title onto a tracked target in the viewer.
- Trackers serialize in FCPXML as `object-tracker`/`tracking-shape`
  elements attached to the clip.

## Audio effects
Logic-derived: Channel EQ, Compressor, Limiter, DeEsser, Noise Gate, Space
Designer reverb; FCP audio enhancements (Loudness, Noise Removal, Hum
Removal, Voice Isolation) — see 08.

## Applying effects programmatically
Our `EffectReference` (name, uid, `[String: EffectParameterValue]`) becomes
`filter-video` + `param` children. Parameter names must match the effect's
published parameter names exactly (case-sensitive).
