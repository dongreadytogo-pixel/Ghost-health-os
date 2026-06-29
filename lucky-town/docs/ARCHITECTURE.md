# Lucky Town — Architecture

This document explains *how* the game is structured and *why*. The guiding
constraints from the project brief are: **modular, scalable, offline-first,
data-driven, easy to extend, production-ready, and networking-ready without a
rewrite.** Every decision below serves those.

---

## 1. Layered design & dependency rule

Code is organised into layers. The **dependency rule** is absolute: a layer may
only know about layers *below* it.

| Layer | Folder | Knows about | Examples |
| --- | --- | --- | --- |
| Presentation | `scenes/`, `src/ui/`, `src/world/`, `src/player/` | systems, autoload, domain, core | `Hud`, `SlotUi`, `PlayerController` |
| Systems | `src/systems/` | autoload, domain, core | `AiBrain`, `AiActuator`, `SlotService` |
| Autoload | `src/autoload/` | domain, core | `Economy`, `GameState`, `WorldDirector` |
| Domain | `src/domain/` | core | `Citizen`, `Pet`, `PropertyPlot`, `SlotMachineConfig` |
| Core | `src/core/` | (only the engine) | `Money`, `SaveBackend` |

Why it matters: the **domain and core layers contain the rules and have no
dependency on Godot scenes**. They can be unit-tested headlessly and, crucially,
could be lifted onto an authoritative server almost verbatim. The presentation
layer is replaceable (desktop today, mobile or a spectator client tomorrow).

---

## 2. The autoload singletons (global services)

Declared in `project.godot`, loaded in dependency order. Each owns one concern:

```
Log            structured logging
EventBus       global typed signal hub (the decoupling seam)
RngService     named, seedable RNG streams (determinism + fairness)
DataRegistry   loads all JSON content; the data-driven backbone
GameClock      simulation time → emits hour/day/season ticks
Economy        authoritative money ledger + dynamic market + jackpots
SaveManager    snapshot/restore across all stateful singletons
GameState      the world model: citizens, pets, plots
WorldDirector  the "AI Director": ticks AI, pays income, fires events
```

### Why singletons here and not elsewhere

These are genuinely global, single-instance services with clear save/load
contracts (`to_save()` / `from_save()`). Everything *else* (entities, UI) is
instanced and owns no global state, which keeps the global surface tiny and the
save file authoritative.

---

## 3. The event bus pattern

`EventBus` is a node full of typed signals and nothing else. Producers emit;
consumers subscribe. No system holds a reference to another system.

```
Economy ──money_changed──▶ EventBus ──▶ Hud (updates label)
                                     └─▶ WorldDirector (rankings dirty)

SlotService ──slot_spun──▶ EventBus ──▶ Hud / analytics / quests
```

Benefits:
- **Decoupling** — add a quest system that reacts to `slot_jackpot_won` without
  touching the slot code.
- **Networking seam** — a future `NetSync` autoload can subscribe to every
  signal and mirror it to a server, and apply remote events back, with zero
  changes to gameplay.
- **Testability** — assert on emitted signals.

Convention: signals carry **plain data only** (ints, strings, dictionaries,
`RefCounted` value objects) — never scene nodes — so handlers stay portable.

---

## 4. Data-driven content

All *content* lives in `data/<category>/*.json` and is loaded by `DataRegistry`
at boot. Gameplay code asks for definitions by id; it never hard-codes content.

| Category | Drives |
| --- | --- |
| `slot_machines` | every slot theme: reels, paylines, paytable, jackpot |
| `pet_species` | pet genetics, traits, mutations, base value |
| `personalities` | AI archetypes: action weights, risk, frugality |
| `buildings` | build cost, daily income, category |
| `market_items` | base price, supply/demand seed, price bounds |

Adding a Cyberpunk slot theme, a Phoenix pet, or a Casino building is a JSON
file — no recompile. See [`DATA_STRUCTURES.md`](DATA_STRUCTURES.md) for schemas.

---

## 5. Determinism & fairness

`RngService` hands out **named** `RandomNumberGenerator` streams, each seeded
from `hash(master_seed, stream_name)`. Consequences:

- A loaded save reproduces the same world (only the master seed is persisted).
- Slot outcomes are auditable: `SlotEvaluator.estimate_rtp()` Monte-Carlos a
  machine's return-to-player from its data alone.
- Tests are deterministic: seed a stream, assert the exact grid.

The slot model is the **virtual-reel** model used by real machines: each reel is
an ordered strip; a spin picks a random stop and reads `rows` consecutive
symbols. Odds are therefore an explicit property of the data.

---

## 6. Model / view separation (the networking key)

A `Citizen` (and `Pet`, `PropertyPlot`) is **pure data**. Its on-screen avatar
(`CitizenAgent`) is a thin node bound by id. Decisions are made by `AiBrain`
(pure) and applied by `AiActuator` (effects via `Economy`/`GameState`).

```
   decide                 apply                  render
AiBrain  ──AiDecision──▶ AiActuator ──mutates──▶ GameState ◀──reads── CitizenAgent
(policy)                 (effect)                (model)              (view)
```

To add **online players later**: replace a citizen's `AiBrain` with remote
input. The actuator, model, economy, save system and rendering are untouched —
which is exactly the brief's requirement that multiplayer not force a rewrite.

Off-screen citizens have **no avatar** but are still fully simulated by
`WorldDirector`, so the city lives everywhere and scales to large populations.

---

## 7. Save system

`SaveManager` assembles one snapshot dictionary from every stateful singleton's
`to_save()`, stamps a schema `version`, and writes it through a `SaveBackend`.

- **`JsonSaveBackend`** (default): one human-readable file per slot, written via
  temp-file-then-rename so a crash can't corrupt an existing save. A tiny
  `.meta.json` sidecar powers the load menu without parsing the whole city.
- **SQLite backend** (future): drop-in replacement implementing the same
  4-method interface — no gameplay change. This satisfies the brief's
  "SQLite + JSON" requirement with a clean migration path.

Multiple manual slots + a dedicated auto-save slot; `_migrate()` upgrades old
saves forward, one step per schema version.

---

## 8. Simulation loop

```
GameClock._process(delta)
   └─ accumulates in-game minutes → emits hour_ticked / day_started

WorldDirector
   ├─ on hour : decay needs for all AI; a round-robin slice makes a decision
   │            (AiBrain.decide → AiActuator.execute)
   └─ on day  : pay building income, age stats, expire & roll world events

SaveManager
   └─ on hour : auto-save every N hours
```

Bounding decisions-per-tick (round-robin) keeps CPU flat regardless of city
size — the "scalable" requirement.

---

## 9. Extension points (where new systems plug in)

| To add… | Do this |
| --- | --- |
| A slot theme | drop a JSON in `data/slot_machines/` |
| A pet species | drop a JSON in `data/pet_species/` |
| An AI archetype | drop a JSON in `data/personalities/` |
| A new AI action | add a candidate in `AiBrain.CANDIDATES` + a case in `AiActuator` |
| A building type | JSON in `data/buildings/` (income/cost are data) |
| A new global system | new autoload with `to_save()`/`from_save()`, wired in `SaveManager` |
| A reaction to gameplay | subscribe to an `EventBus` signal |
| Networking | a `NetSync` autoload mirroring `EventBus`; swap `AiBrain` for remote input |

---

## 10. Non-goals (Phase 1) and why

- **No building interiors** — buildings are management screens, per the brief.
- **No online server** — but every seam above is networking-shaped.
- **No bespoke art pipeline yet** — placeholder primitives; see
  [`ASSETS.md`](ASSETS.md) for the free/open sourcing plan.

These are deferred deliberately, not by accident, and none of them require
re-architecting to add later.
