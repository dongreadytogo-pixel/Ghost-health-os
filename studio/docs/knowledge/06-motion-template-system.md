# 06 — Motion Template System

Source: Motion User Guide (https://support.apple.com/guide/motion/) and
FCPXML Reference. Motion is FCP's companion app; almost every title,
generator, transition, and many effects in FCP are Motion projects published
as templates.

## Template types & locations

| Type | Motion project kind | Installs under `~/Movies/Motion Templates.localized/` |
|---|---|---|
| Title | Final Cut Title | `Titles.localized/<Category>/<Name>/<Name>.moti` |
| Generator | Final Cut Generator | `Generators.localized/…/<Name>.motn` |
| Effect | Final Cut Effect | `Effects.localized/…/<Name>.moef` |
| Transition | Final Cut Transition | `Transitions.localized/…/<Name>.motr` |

FCPXML references a template through an `effect` resource whose `uid` is the
template path fragment (e.g.
`.../Titles.localized/Lower Thirds.localized/Basic Lower Third.localized/Basic Lower Third.moti`).
Our `MotionTitle.templateUID` carries exactly this string.

## Published parameters
In Motion, checking **Publish** on a parameter exposes it in FCP's inspector
and in FCPXML as `param name="…" value="…"`. Publishing is the API surface
of a template — our `EffectReference.parameters` writes these.

## Rigs
A **rig** groups parameters behind a single widget (slider / pop-up /
checkbox), letting one published control drive many internal values —
the recommended way to expose "style variants" to FCP users.

## Motion building blocks
- **Behaviors** — procedural animation (Throw, Grow/Shrink, Fade In/Out,
  MotionPath) — no keyframes needed.
- **Emitters / Particles** — particle systems (fire, rain, snow, sparks).
- **Replicator** — pattern duplication of a source layer.
- **Clone layer** — live duplicate of a group.
- **3D Text** — extruded text with materials/lighting.
- **Cameras** — 3D scene framing; required for parallax moves.
- **Generators** — procedural sources (gradients, noise, shapes).

## Template authoring rules for the studio
1. One template = one `.moti/.motn/.moef/.motr` bundle in the proper
   category folder; FCP scans on launch.
2. Keep text layers published for title templates so `title` elements can
   set the string via `text/text-style`.
3. Name published params stably — they are the plugin-facing contract.
4. Drop zones (media wells) publish as image parameters.
5. Our planned Preset Builder generates these bundles; today
   `MotionGraphicsLibrary` targets FCP's built-in templates.
