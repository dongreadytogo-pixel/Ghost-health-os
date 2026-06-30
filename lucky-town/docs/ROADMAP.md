# Lucky Town — Roadmap

Phased delivery. Each phase ends in something playable; nothing is left at
"prototype". The architecture for later phases already exists in skeleton so no
phase forces a rewrite of an earlier one.

Legend: ✅ done · 🟡 partial · ⬜ planned

---

## Phase 1 — Minimal playable foundation

Goal: walk a city, gamble, earn, own land/pets, save — with real AI citizens.

- ✅ Layered, modular architecture + autoload services
- ✅ Event bus, deterministic RNG, data registry
- ✅ Slot engine: themes, paylines, wilds, scatters, progressive jackpot, RTP tool
- ✅ Economy ledger + dynamic supply/demand market
- ✅ AI citizens: personalities, needs, memory, utility brain, headless sim
- ✅ Pets: genetics, traits, mutations, breeding, value
- ✅ Property: finite grid, ownership, buildings, passive income
- ✅ Save: JSON backend, slots, auto-save, migration
- ✅ 3D world: player walking, interactables, HUD, slot UI
- ✅ Quests: data-driven daily missions + auto recovery mission (anti-bankruptcy)
- ✅ Player actions service (work/buy land/build/adopt/sell/breed) — same rules as AI
- ✅ Town Board UI: net worth, city rankings, quests + claim, odd jobs, pet shop
- ✅ Unit tests for pure logic (money, slots, genetics, quests)
- 🟡 Dedicated screens for property/pet detail (board covers the basics; detail next)
- ⬜ Art pass replacing placeholder primitives (free/open assets)

---

## Phase 2 — Economy, buildings, decorations

- ⬜ Building management screens (upgrade levels, set rents)
- ⬜ Player shops vs. NPC shops competing for the same market
- ⬜ Decoration placement (trees, lamps, benches, billboards) with happiness/value effects
- ⬜ Property market UI: buy/sell/list, appraisal history
- ⬜ Jobs as data (`data/jobs/`) with schedules and wages
- ⬜ Data-authoring tool: validate all JSON + report slot RTP per machine

Architecture already present: building income, market repricing, plot ownership.

---

## Phase 3 — Pet depth, auction, dynamic economy

- ✅ Auction house (escrowed bid/buy/sell) for pets & property, with AI rivals
- ✅ Pet farms: automatic breeding from farm/pet-shop buildings (idle offspring)
- ✅ Building upgrades: levels raise daily income (player + via PlayerActions)
- 🟡 Genetics UI: inspect alleles, plan pairings, track bloodlines (next)
- ⬜ Item rarity + crafting feeding the market
- ⬜ Economy events with longer arcs (booms, busts, shortages)

Architecture already present: `PetBreeder`, `quality()/market_value()`, market shocks.

---

## Phase 4 — Living city

- ✅ Day/night visuals driven by `GameClock.day_fraction()` (`WorldAtmosphere`)
- ✅ Weather (clear/cloudy/rain/fog), season-biased, with a light economic nudge
- ✅ City rankings UI — richest, most land, most pets, luckiest (Town Board)
- ✅ Festivals/events surfaced via HUD toasts; weather + season on the HUD
- 🟡 Advanced AI: long-term goals, rivalries, reputation (memory groundwork done)
- ⬜ Traffic & pathfinding (NavigationServer) for avatars
- 🟡 Quests — daily + recovery done; main story & weekly/achievements next

Architecture already present: `WorldDirector` events, seasons, rankings, AI memory.

---

## Phase 5 — Networking readiness (no gameplay change)

The whole point of the model/view + event-bus design. Target: add online play
**without rewriting the core**.

- ⬜ `NetSync` autoload mirroring `EventBus` signals to/from a server
- ⬜ Authoritative-server mode: domain/core layers run server-side unchanged
- ⬜ Replace a citizen's `AiBrain` with remote player input (citizens *become* players)
- ⬜ Save → server persistence (swap `SaveBackend` for a network backend)
- ⬜ Deterministic RNG → server-seeded for fair shared slots/jackpots
- ⬜ Cloud saves

No Phase 1–4 system needs to change its public shape for this to land.

---

## Cross-cutting, ongoing

- ⬜ Player customization (clothing, hair, accessories, emotes, titles)
- ⬜ Achievements & statistics screens
- ⬜ Audio (music + SFX) from free/open sources
- ⬜ Localization (UI strings already isolated from ids)
- ⬜ Platform packaging: Windows → Steam → Android → iOS
- ⬜ Performance: object pooling for avatars, LOD for far districts
- ⬜ Expand test coverage to economy/AI integration via GUT scenes
