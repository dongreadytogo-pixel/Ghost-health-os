# Lucky Town — Assets Policy & Log

The brief requires **free and open** resources wherever practical, and that
every asset's license be verified and attributed before integration. This file
is the policy and the running attribution log.

---

## Policy

1. **License first.** Before any asset enters `assets/`, confirm its license
   permits use in a commercial game (Steam/mobile later) and record it below.
   Prefer **CC0 / public domain**; then permissive (CC-BY, with attribution).
   Avoid **CC-BY-NC** (non-commercial) and **CC-BY-SA** for code-adjacent art
   unless we accept the share-alike obligation.
2. **Attribution captured at import time**, not "later". If a license needs
   credit, add the row to the log in the same commit that adds the file.
3. **Keep sources.** Note the URL and author so assets can be re-sourced or
   updated.
4. **No placeholder lock-in.** Phase 1 uses engine primitives (capsules, boxes).
   Replacing them must not require code changes — meshes are referenced from
   scenes/data, never hard-coded in logic.

---

## Recommended free/open sources

| Source | Content | Typical license |
| --- | --- | --- |
| [Godot Asset Library](https://godotengine.org/asset-library) | plugins, demos | MIT/various |
| [Kenney](https://kenney.nl) | low-poly models, UI, audio | CC0 |
| [Quaternius](https://quaternius.com) | low-poly model packs | CC0 |
| [Poly Pizza](https://poly.pizza) | low-poly models | CC0 / CC-BY |
| [OpenGameArt](https://opengameart.org) | art, audio | varies — check each |
| [Mixamo](https://www.mixamo.com) | character animations | free w/ Adobe account |
| [Freesound](https://freesound.org) | SFX | varies — check each |
| [Pixabay Music](https://pixabay.com/music/) | music | Pixabay license |

Kenney + Quaternius (both CC0) are the recommended default for the city's
low-poly look: no attribution burden and a consistent style.

---

## Attribution log

> Add one row per asset/pack actually used. Phase 1 ships with **zero** external
> assets (engine primitives only), so the log is intentionally empty.

| Asset / pack | Author | Source URL | License | Used in |
| --- | --- | --- | --- | --- |
| _(none yet)_ | | | | |

---

## Planned asset needs by phase

- **Phase 1 → 2 art pass:** low-poly building fronts, a character base mesh, a
  slot-cabinet model, pet creatures, ground/road textures. → Kenney/Quaternius (CC0).
- **Phase 4:** weather particles, skybox variations, street props (lamps,
  benches, trees), simple character animations (Mixamo).
- **Audio (ongoing):** ambient city loop, UI clicks, slot spin/win SFX, jackpot
  fanfare. → Freesound (verify each) / Pixabay Music.

---

## Import checklist

- [ ] License permits commercial use → recorded above
- [ ] Attribution (if required) added to the log in the same commit
- [ ] File placed under the correct `assets/<type>/` subfolder
- [ ] Referenced from a scene/`data` file, not hard-coded in a script
- [ ] Reasonable size/format (e.g. `.glb` models, `.ogg` audio, compressed textures)
```
