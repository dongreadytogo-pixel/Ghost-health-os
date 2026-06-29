# Lucky Town

> An offline-first 3D life-simulation game where **slot machines are just one
> activity** inside a living, AI-driven city. Explore, gamble, trade, build,
> breed pets, and grow from a tiny house into the richest citizen in town.

Built with **Godot Engine 4.x** and **GDScript**, designed from day one to be
modular, data-driven, and ready for online multiplayer to be added later
without rewriting the core.

---

## Status

**Phase 1 — Minimal playable foundation (in progress).**

| System | State |
| --- | --- |
| Modular autoload architecture (event bus, clock, economy, save, world director) | ✅ implemented |
| Deterministic, data-driven slot engine (themes, paylines, scatters, wilds, jackpot) | ✅ implemented |
| Central economy ledger + dynamic supply/demand market | ✅ implemented |
| AI citizens: personalities, needs, memory, utility-based brain, headless simulation | ✅ implemented |
| Pets: genetics, traits, mutations, breeding, market value | ✅ implemented |
| Property: finite land grid, ownership, buildings, passive income | ✅ implemented |
| Save system: JSON backend, multiple slots, auto-save, schema migration | ✅ implemented |
| 3D world: player walking, interactables, HUD, slot UI | ✅ playable vertical slice |
| Unit tests for pure logic (money, slots, genetics) | ✅ headless runner |

See [`docs/ROADMAP.md`](docs/ROADMAP.md) for Phases 2–5.

---

## Running the game

1. Install [Godot 4.2+](https://godotengine.org/download) (standard, GDScript build).
2. Open `lucky-town/project.godot` in the Godot editor.
3. Press **F5** (Play). The boot scene loads data and opens the main menu.
4. **New Game** drops you into the city.

### Controls

| Action | Key |
| --- | --- |
| Move | `W` `A` `S` `D` |
| Interact (e.g. play a slot machine) | `E` |
| Quick save (slot 1) | `F5` |
| Back to menu | `Esc` |

### Running the tests

No plugins required — just the Godot binary. On a fresh checkout, import once
first so Godot builds its global class cache, then run the suite:

```bash
# 1. One-time per checkout: generate .godot/ (import cache + class registry)
godot --headless --path lucky-town --import

# 2. Run the tests (exits non-zero on failure → CI-ready)
godot --headless --path lucky-town --script res://tests/run_tests.gd
```

This is exactly what [`.github/workflows/lucky-town-ci.yml`](../.github/workflows/lucky-town-ci.yml)
does on every change under `lucky-town/`.

---

## Architecture at a glance

The game is split into clean layers with a strict dependency direction
(*outer depends on inner, never the reverse*):

```
        ┌──────────────────────────────────────────────┐
        │  scenes / ui            (Godot nodes, views)  │
        ├──────────────────────────────────────────────┤
        │  systems                (slot, ai, ...)        │  orchestration
        ├──────────────────────────────────────────────┤
        │  autoload               (singletons / state)   │  global services
        ├──────────────────────────────────────────────┤
        │  domain                 (citizen, pet, ...)     │  entities (pure data)
        ├──────────────────────────────────────────────┤
        │  core                   (money, save, ...)      │  engine-light logic
        └──────────────────────────────────────────────┘
```

Key ideas:

- **Data-driven.** Slot themes, pets, buildings, personalities and market goods
  are JSON under [`data/`](data/). Adding content needs **no code change**.
- **Event bus.** Systems publish facts to [`EventBus`](src/autoload/event_bus.gd)
  and never hold hard references to each other — the seam a future network layer
  plugs into.
- **Deterministic RNG.** All randomness flows through named streams in
  [`RngService`](src/autoload/rng_service.gd), so saves reproduce exactly and
  slot fairness is auditable.
- **Model / view split.** A `Citizen` is pure data; its avatar is a thin node.
  A networked player can later *inhabit* a citizen by swapping its brain — and
  nothing else changes.

Full detail in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

---

## Repository layout

```
lucky-town/
├── project.godot          # engine config + autoloads + input map
├── data/                  # data-driven content (JSON)
├── scenes/                # boot, menu, world (.tscn)
├── src/
│   ├── autoload/          # global singletons (services + state)
│   ├── core/              # engine-light value objects (money, save)
│   ├── domain/            # game entities (citizen, pet, property, slot)
│   ├── systems/           # orchestration (ai brain/actuator, slot service)
│   ├── player/            # player controller
│   ├── world/             # interactables, citizen avatars
│   └── ui/                # hud, slot screen
├── tests/                 # headless unit tests
└── docs/                  # architecture, data structures, roadmap, assets
```

A per-directory breakdown is in [`docs/FOLDER_STRUCTURE.md`](docs/FOLDER_STRUCTURE.md).

---

## License & assets

Code is under the repository's existing license. All third-party assets must be
free/open and license-compatible; see [`docs/ASSETS.md`](docs/ASSETS.md) for the
sourcing policy and attribution log.
