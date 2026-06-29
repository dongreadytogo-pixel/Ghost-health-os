# Project Titan — Development Roadmap

แผนพัฒนาเป็น **Phase** สำหรับ Idle MMORPG โดยอ้างอิงเฉพาะ *แนวคิด* ของเกมแนว
auto-battle MMO — **ไม่คัดลอกทรัพย์สินทางปัญญา ชื่อ แผนที่ ตัวละคร มอนสเตอร์
เนื้อเรื่อง หรือ asset ที่มีลิขสิทธิ์** ทุกอย่างที่เป็น "เนื้อหา" จะเป็น **data**
ที่ออกแบบเองทั้งหมด

แต่ละ Phase ต้องผ่าน **automated tests** และยังคงหลักการ: *Modular, Plugin-based,
Data-driven, Component-based, SOLID, Clean Architecture, Testable, Expandable.*

The engine is the inner ring. Each later phase is an **outer ring** that depends
inward — the simulation never depends on a renderer, a server, or a database.

---

## ✅ Phase 0 — Foundation (DONE)

- Monorepo package `@titan/engine`, strict TypeScript, vitest, matching the
  house conventions (`Result`/`EngineError`, branded ids).
- Seedable, serializable **deterministic RNG** — the basis of replay, offline
  progress and server validation.

## ✅ Phase 1 — Deterministic Simulation Core (DONE)

The playable, headless game loop — fully unit-tested (67 tests).

- **Stats:** six attributes → derived combat stats via a retunable, data-driven
  formula. Classless / hybrid by construction.
- **Progression:** experience curve + cascading level-ups (absorbs huge offline
  gains in one call), with auto-allocation strategy.
- **Content:** serializable definitions (monster / item / affix / zone) +
  `ContentRegistry` plugin lookup. Starter content pack (original IP).
- **Combat:** `resolveAttack()` — hit/miss (accuracy vs evasion), critical,
  defense-mitigated damage, physical & magic.
- **Loot:** weighted drop tables + random prefix/suffix item generation.
- **World:** the auto-battle idle loop — spawn → auto-attack → loot → exp →
  level-up → repeat, with no input. Emits an event stream.
- **Offline:** fast-forward elapsed real time → "while you were away" summary,
  capped so a long absence can't freeze the device.

**Exit criteria met:** deterministic (same seed ⇒ identical event log),
typechecks clean, all tests green.

## ✅ Phase 1.5 — Mounts, Companions, Random Skills & Rarity (DONE)

The "charm" layer — all rarity-scaled, all deterministic, all unit-tested.

- **Rarity (everything):** one global table (common → mythic) drives power and
  drop weight for items, mounts, companions and skills, plus a rare **shiny /
  prismatic** roll (~1 in 256) that stacks a bonus multiplier on anything.
- **Mounts (ขี่ม้า):** ridden companions granting rarity-scaled attributes and a
  capped attack-speed boost; fold into the player build like gear.
- **Companions (จับมอนสเตอร์เข้าทีม):** defeated monsters can be **tamed** into a
  party that walks behind the hero and fights — each with rolled rarity, a
  growing **bond** that strengthens it, and a chance at an innate random skill.
  Healer companions even heal the hero.
- **Fusion (รวมร่าง/วิวัฒนาการ):** merge two companions into one a tier rarer;
  the world **auto-fuses** duplicate-rarity companions during idle play.
- **Random skills:** rarity-rolled abilities (burst / multistrike / lifesteal /
  heal) the hero and companions **auto-cast** on cooldown in battle.
- **Party synergy:** a team aura buffs damage per companion, with a bonus when
  the whole active party shares one rarity.
- **Performance:** active-party caching + a roster cap keep offline
  fast-forwarding fast even after thousands of captures.

## ✅ Phase 2 (partial) — Auto-storage & Save/Load (DONE)

- **Save/Load:** `World.serialize()` / `World.fromSave()` capture the full state
  *including RNG*, so a reload resumes deterministically. Plain JSON.
- **Auto-storage / auto-recycle:** owned loot and companions are capped
  (oldest/weakest auto-recycled) — keeps memory and save size bounded.

## ✅ Phase 8 (MVP) — Playable Client (DONE)

- **`@titan/web`**: a mobile-first 2D-pixel browser client driving the engine in
  real time — auto-battle, floating damage, party chips, level-ups, **offline
  "welcome back" progress**, and autosave to `localStorage`.
- Verified running in a real (headless Chromium) browser with no console errors;
  static build (one HTML + one JS) hostable anywhere.
- Placeholder emoji sprites with documented drop-in points for licensed 2D art.

---

## ⏭️ Phase 2 (rest) — Inventory, Equipment & Economy (next)

- Inventory model with stacking, capacity, and auto-sort.
- Equip/unequip flow recomputing the player build; **auto-equip** (keep best per
  slot) and **auto-recycle/auto-sell** rules.
- Item upgrade / enchant / socket systems (data-driven success curves).
- Gold & resource sinks; foundation for the later player market.
- *Tests:* equip math, upgrade probability curves, auto-sell selection.

## ⏭️ Phase 3 — Skills & Build Depth

- Data-driven **skill tree** (free, no class lock): passives, active skills,
  chain/combo, interrupt, cooldowns measured in ticks.
- Auto-skill priority list (rotation) integrated into the combat resolver.
- Status effects / buffs / debuffs as composable components.
- *Tests:* skill rotation determinism, effect stacking, cooldown accounting.

## ⏭️ Phase 4 — Pets & Companions

- Capture → tame → evolve → fuse pipeline (data-driven).
- Pet passives/actives, auto-loot, auto-heal hooks into the World loop.
- *Tests:* evolution rules, pet contribution to combat/loot.

## ⏭️ Phase 5 — World Simulation

- Multiple zones / biomes, seamless travel graph, recommended-level routing.
- Day/night, weather, seasons, random world events as deterministic modifiers.
- Boss AI patterns; world-boss schedule.
- *Tests:* spawn distributions, event modifier application, boss phase logic.

## ⏭️ Phase 6 — Persistence & Live Service

- Full `World.snapshot()/restore()` (incl. RNG state) → cloud save adapter.
- Remote configuration (live balance/tuning), analytics & crash-report ports
  (interfaces in this layer, vendors in infrastructure).
- *Tests:* round-trip save/restore reproduces the exact future stream.

## ⏭️ Phase 7 — Online & Multiplayer

- Authoritative server re-runs client ticks to validate (anti-cheat) — enabled
  by Phase 1 determinism.
- Party, guild, raid, PvP/arena, world boss, cross-server.
- Player market / auction with inflation protection.
- *Tests:* server/client replay parity, trade settlement, matchmaking.

## ⏭️ Phase 8 — Presentation

- Mobile-first renderer (PC compatible) consuming the event stream — a thin
  outer ring. **Only permissively-licensed assets** (Kenney CC0, OpenGameArt,
  itch.io free), license verified and recorded before import.

---

### Working agreement

1. One system per slice; land it **with tests** before the next.
2. Keep balance in **data/config**, never in branching code.
3. Add content by **registering bundles**, not by editing systems.
4. A phase is "done" only when it typechecks and every test passes.
