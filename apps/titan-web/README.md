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

## Deploy to Cloudflare Pages

```bash
# one-time: log in (opens a browser) or set CLOUDFLARE_API_TOKEN + CLOUDFLARE_ACCOUNT_ID
npx wrangler login

# build + deploy the static dist/ to a Pages project
pnpm --filter @titan/web deploy
```

`deploy` runs the build then `wrangler pages deploy dist --project-name=project-titan`.
The first run creates the project; later runs publish new versions. No server,
no secrets baked into the bundle — it's pure static files. (Any static host works
the same way: just upload `dist/`.)

## What you'll see

- The hero **auto-walks, auto-attacks, and auto-casts skills** — no input needed.
- HP / EXP bars, floating damage (crits, skills, heals), level-ups.
- A **party** of monsters you **tame** as you fight, each with rarity, bond (♥)
  and a chance at skills; duplicates **auto-fuse** into rarer companions.
- A **mount** (🐎) that speeds you up.
- **Offline progress:** close the tab and come back — a "welcome back" summary
  shows what your party did while you were away.
- **Autosave** every few seconds and on leaving the page.

## Art & audio

- **Sprites** use the **CC0** "DungeonTileset II" by **0x72**
  (`assets/0x72_dungeon.png`, https://0x72.itch.io/dungeontileset-ii) — a
  professional free pixel-art pack. `src/sprites.ts` blits the documented idle
  frames to `<canvas>` and cycles them for animation. To restyle, swap the PNG +
  the `FRAMES` table; archetype names map view → engine, so nothing else
  changes. License recorded in
  [`ATTRIBUTIONS.md`](../../packages/titan-engine/ATTRIBUTIONS.md).
- **SFX** are synthesized with the Web Audio API (`src/audio.ts`) — also
  original. A 🔊/🔇 button toggles sound; audio unlocks on first tap (browser
  autoplay policy).
- **Background music** is left as a slot for the project owner's own licensed
  tracks: drop a file in and call `setMusic('/music/theme.ogg')`. Kept out of
  the engine by design.
