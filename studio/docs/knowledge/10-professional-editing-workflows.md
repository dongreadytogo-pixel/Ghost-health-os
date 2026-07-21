# 10 — Professional Editing Workflows by Genre

Delivery conventions the studio's pacing profiles and export presets encode.

| Genre | Shot rhythm | Structure | Deliverable |
|---|---|---|---|
| Film / cinematic | 3–8 s, motivated cuts, transitions sparse | three-act; scene-based | ProRes master, 24 fps |
| Commercial | 1–3 s, beat-locked | hook → product → CTA in 15/30/60 s | broadcast specs, loudness-compliant |
| Podcast | 8–30 s, cut on speaker turns | cold open → segments → outro | -16 LUFS audio, chapters |
| Documentary | 4–12 s, interview + B-roll | narration/interview spine | 25p broadcast or streaming |
| Interview | speaker-turn cuts, L/J cuts | question-driven segments | multicam angles, lower thirds |
| Tutorial | screen + face, chaptered | steps with callouts | 1080p/4K 30 fps, chapters |
| YouTube | 2–6 s, jump-cut friendly | hook ≤ 15 s → segments → CTA | 12 Mbps 1080p / 45 Mbps 4K (see presets) |
| TikTok / Reels / Shorts | 0.6–2.5 s, beat-driven | instant hook, captions always on | 9:16 1080×1920, ≤ 60–90 s |
| Instagram feed | ≤ 2.5 s, loopable | visual-first | 4:5 1080×1350 |

Mapped in code:
- `PacingProfile.Style` (marvel/tiktok/documentary/vlog/podcast/cinematic)
  sets shot lengths, beat-cutting, transitions, caption style, format,
  silence removal.
- `RenderPreset` encodes the delivery container/codec/bitrate/format per
  platform (YouTube 1080p/4K, TikTok, IG Reel/Feed, ProRes master).
- `CaptionStyle` per platform (TikTok karaoke caps, YouTube boxed bottom,
  Instagram lower-third pop-in, Broadcast).

## Platform delivery notes
- **YouTube**: H.264/HEVC MP4, +faststart; chapters from `00:00`-style
  timestamps or chapter markers; end screens need ~20 s tail.
- **TikTok**: vertical, burned-in captions expected, hook in first second;
  keep key content inside center-safe area (UI overlays both edges).
- **Instagram Reels**: as TikTok; feed video 4:5 crops best.
- **Broadcast**: role stems, −23/−24 LUFS, legal video levels.

## Multi-deliverable strategy
Cut a master timeline first, then derive: vertical reframe (crop + follow
subject), short highlights (from `find_highlights`), captioned variants.
The studio's `auto_edit` + `find_highlights` + `export_command` chain
automates this derivation.
