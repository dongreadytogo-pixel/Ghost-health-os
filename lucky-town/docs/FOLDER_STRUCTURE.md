# Lucky Town — Folder Structure

Every directory has one job. New code goes in the layer that matches its
dependencies (see [`ARCHITECTURE.md`](ARCHITECTURE.md) §1).

```
lucky-town/
├── project.godot            Engine config: autoloads, input map, rendering.
├── icon.svg                 App icon.
│
├── data/                    DATA-DRIVEN CONTENT (JSON). No code. Designer-owned.
│   ├── slot_machines/         fantasy.json, ghost.json, cyberpunk.json …
│   ├── pet_species/           common.json, fantasy.json …
│   ├── personalities/         archetypes.json
│   ├── buildings/             buildings.json
│   └── market_items/          goods.json
│
├── scenes/                  COMPOSED SCENES (.tscn) + their controller scripts.
│   ├── boot/                  boot.tscn / boot.gd  — entry point & routing
│   ├── menu/                  main_menu.tscn / main_menu.gd
│   └── world/                 world, player, citizen_agent, slot_machine
│
├── src/                     SOURCE CODE, by layer (inner = fewer deps).
│   ├── autoload/              Global singletons (services + global state):
│   │     log, event_bus, rng_service, data_registry, game_clock,
│   │     economy, save_manager, game_state, world_director
│   │
│   ├── core/                  Engine-light value objects & infrastructure:
│   │   ├── money/               money.gd
│   │   └── save/                save_backend.gd, json_save_backend.gd
│   │
│   ├── domain/                Game entities (pure data + rules, no scenes):
│   │   ├── citizen/             citizen.gd, personality.gd
│   │   ├── pet/                 pet.gd, pet_breeder.gd
│   │   ├── property/            property_plot.gd
│   │   └── slot/                slot_symbol.gd, slot_machine_config.gd,
│   │                            slot_evaluator.gd, slot_spin_result.gd
│   │
│   ├── systems/               Orchestration (glue rules + effects):
│   │   ├── ai/                  ai_brain.gd, ai_actuator.gd, ai_decision.gd
│   │   └── slot/                slot_service.gd
│   │
│   ├── player/                player_controller.gd
│   ├── world/                 interactable.gd, slot_machine_interactable.gd,
│   │                          citizen_agent.gd
│   └── ui/                    Views (subscribe to EventBus, never own rules):
│       ├── hud/                 hud.gd / hud.tscn
│       └── slot/                slot_ui.gd / slot_ui.tscn
│
├── tests/                   Headless unit tests (run_tests.gd).
│
├── assets/                  Art, audio, fonts. Free/open only (see ASSETS.md).
│   ├── models/  ├── textures/  ├── audio/  └── fonts/   (created as needed)
│
└── docs/                    This documentation set.
```

## Conventions

- **Files**: `snake_case.gd`. **Classes**: `PascalCase` via `class_name`.
- **Scenes** pair with a controller script of the same name in the same folder
  (`world.tscn` ↔ `world.gd`).
- **One class per file.** Shared helpers live in the lowest layer that needs
  them.
- **Static typing everywhere** (`func f(x: int) -> void`) — catches errors at
  parse time and documents intent.
- **No content in code.** If a number describes *game content* (a price, a
  payout, a pet stat) it belongs in `data/`, not a constant.

## Where does my new code go?

| I'm adding… | Folder |
| --- | --- |
| A reusable value object with no game knowledge | `src/core/` |
| A new game entity or its rules | `src/domain/<entity>/` |
| Logic that coordinates entities + side effects | `src/systems/<system>/` |
| A global, single-instance service | `src/autoload/` (+ register in `project.godot`) |
| A screen or HUD element | `src/ui/<screen>/` |
| Something the player walks up to | `src/world/` (extend `Interactable`) |
| A whole new place/level | `scenes/<area>/` |
| Tunable content | `data/<category>/*.json` |
```
