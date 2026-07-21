# 09 — Video Editing Theory

The vocabulary the AI Director's planning decisions are grounded in.

## Cut types
- **J cut** — audio of the next shot leads under the current picture
  (audio earlier than video). Natural conversation flow.
- **L cut** — audio of the current shot trails over the next picture.
- **Jump cut** — same framing, time visibly skipped. Rough by accident,
  energetic on purpose (vlogs, silence-removal edits — exactly what our
  silence remover produces; Flow transition can smooth it).
- **Match cut** — action/shape/sound matched across a cut for continuity or
  metaphor.
- **Cutaway / insert** — B-roll covering a jump or adding context.
- **Cross cutting / parallel editing** — alternating between simultaneous
  storylines to build tension.
- **Montage** — compressed time via a sequence of short shots, usually
  music-driven (beat-aligned cutting).

## Rhythm & pacing
- **Pacing** = distribution of shot lengths. Action ≈ 0.8–3 s per shot;
  documentary ≈ 4–12 s; podcast ≈ 8–30 s. Encoded in `PacingProfile`
  (`minShotLength`/`maxShotLength` per style).
- **Rhythm** = the *pattern* of cuts, often locked to music beats
  (`cutOnBeats`) or dialogue phrasing.
- Vary pacing deliberately: sameness reads as monotony; acceleration builds
  energy toward a climax.

## Structure
- **Story arc** — setup → rising tension → climax → resolution; even a
  60-second short benefits from this shape.
- **Hook** — the first 1–3 s must earn attention (platform algorithms watch
  early retention). `HighlightPlanner` promotes the strongest early moment
  to `Highlight.Kind.hook`.
- **CTA** — call to action (subscribe/follow/link) near the end; synthesized
  by the planner as a `cta` beat + `subscribeAnimation` overlay.
- **Chapters** — topic boundaries; from scene cuts or even-split fallback
  (`HighlightPlanner.chapters` → chapter markers → YouTube chapters).

## A-roll / B-roll
- **A-roll** — primary content (talking head, interview).
- **B-roll** — supporting visuals cut over A-roll audio; hides jump cuts,
  adds information, controls pacing. Placed on connected lanes above the
  storyline (positive `Clip.lane`).

## Continuity rules of thumb
- 180° rule (screen direction), 30° rule (change angle enough between cuts
  of the same subject), cut on action, motivate every cut (new information).
