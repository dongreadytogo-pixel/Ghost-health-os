# @titan/web — Project Titan playable client

A mobile-first (PC-compatible) **2D pixel** web client that runs
[`@titan/engine`](../../packages/titan-engine) in the browser. It is a thin
presentation layer: it renders the engine's deterministic idle loop and persists
to `localStorage` — no game logic lives here.

## Play it

```bash
# from the repo root
pnpm --filter @titan/web build     # bundles to dist/ (app.js + index.html)

# then serve the static files (any static server works)
cd apps/titan-web/dist && python3 -m http.server 8099
# open http://localhost:8099 on your phone or desktop browser
```

Or live-develop with hot rebuild + a dev server:

```bash
pnpm --filter @titan/web dev       # esbuild serve on http://localhost:8000
```

The build output in `dist/` is fully static (HTML + one JS file) — host it on any
static host (GitHub Pages, Cloudflare Pages, itch.io, …).

## What you'll see

- The hero **auto-walks, auto-attacks, and auto-casts skills** — no input needed.
- HP / EXP bars, floating damage (crits, skills, heals), level-ups.
- A **party** of monsters you **tame** as you fight, each with rarity, bond (♥)
  and a chance at skills; duplicates **auto-fuse** into rarer companions.
- A **mount** (🐎) that speeds you up.
- **Offline progress:** close the tab and come back — a "welcome back" summary
  shows what your party did while you were away.
- **Autosave** every few seconds and on leaving the page.

## Swapping in real art

Sprites are placeholder emoji today. To use the licensed 2D pixel art from
[`../../packages/titan-engine/ASSETS.md`](../../packages/titan-engine/ASSETS.md):

- Replace the entries in `MONSTER_SPRITES` (and the hero/mount glyphs) in
  `src/main.ts` with `<img>` / CSS-sprite lookups keyed by the content name.
- Because content is data-driven, no engine code changes — just the view.

Background music: the project owner supplies their own licensed BGM; drop it in
and wire an `<audio>` element (kept out of the engine by design).
