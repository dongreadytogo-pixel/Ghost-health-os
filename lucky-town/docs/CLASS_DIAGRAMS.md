# Lucky Town — Class Diagrams

Relationships between the main types. Notation is light UML:
`──▶` association/uses, `──|>` inheritance, `◇──` aggregation.

---

## Domain entities

```
RefCounted
   ▲
   ├── Money            (immutable currency value object)
   ├── Citizen          ◇── memory:Dictionary, relationships:Dictionary, stats:Dictionary
   │       │
   │       ├──▶ Personality (by id, via DataRegistry)
   │       ├──▶ Pet*        (by id)
   │       └──▶ PropertyPlot* (by id)
   ├── Pet              ──▶ species def (DataRegistry "pet_species")
   ├── PropertyPlot     ──▶ building def (DataRegistry "buildings")
   ├── Personality
   ├── SlotSpinResult
   └── AiDecision

Resource
   ▲
   ├── SlotSymbol
   └── SlotMachineConfig   ◇── reels, paylines, paytable, scatter_pays
```

`Citizen`, `Pet`, `PropertyPlot` hold **ids**, not object references, to each
other. The id→object resolution is centralised in `GameState`. This keeps
entities serialisable and avoids cyclic references.

---

## Systems (orchestration, mostly static / pure)

```
AiBrain  (static)
   decide(Citizen, Personality, world:Dictionary, rng) ──▶ AiDecision
        │ uses utility scoring over CANDIDATES

AiActuator (static)
   execute(Citizen, AiDecision) ──▶ mutates Economy + GameState, emits EventBus

SlotService (static)
   spin(machine_id, player_id, bet) ──▶ SpinOutcome
        │ uses ──▶ SlotEvaluator (pure)
        └ effects ──▶ Economy, GameState, EventBus

SlotEvaluator (static, pure)
   spin(SlotMachineConfig, rng, bet, jackpot) ──▶ SlotSpinResult
   estimate_rtp(config, rng, iterations) ──▶ float

PetBreeder (static, pure)
   breed(Pet a, Pet b, rng, owner, day) ──▶ Pet
```

The two pure cores — `SlotEvaluator` and `PetBreeder` — have **no autoload
dependency** and are unit-tested directly.

---

## Autoload services (singletons)

```
Node
   ▲
   ├── Log
   ├── EventBus        (signals only — the decoupling hub)
   ├── RngService      ◇── streams: { name → RandomNumberGenerator }
   ├── DataRegistry    ◇── _data: { category → { id → def } }
   ├── GameClock       ──emits──▶ EventBus(hour_ticked, day_started, season_changed)
   ├── Economy         ◇── balances, jackpots, market   ; ──emits──▶ EventBus(money_changed, ...)
   ├── SaveManager     ──▶ SaveBackend ; aggregates *.to_save()/from_save()
   ├── GameState       ◇── citizens, pets, plots
   └── WorldDirector   ──▶ AiBrain, AiActuator, Economy, GameState

SaveBackend (abstract)
   ▲
   └── JsonSaveBackend   (file-per-slot under user://saves)
   (future) SqliteSaveBackend
```

### Save contract

Every stateful singleton implements:

```
to_save()   -> Dictionary
from_save(d: Dictionary) -> void
```

`SaveManager` is the only thing that calls them, so the set of persisted
singletons is declared in exactly one place.

---

## Presentation (Godot nodes)

```
Node3D
   ▲
   ├── CharacterBody3D ──|> PlayerController   (input + motion only)
   └── CharacterBody3D ──|> CitizenAgent       (view bound to Citizen by id)

Area3D ──|> Interactable                       (proximity + dispatch)
              ▲
              └── SlotMachineInteractable       (──▶ EventBus open_slot_ui)

CanvasLayer ──|> Hud                            (subscribes to EventBus)
Control     ──|> SlotUi                         (──▶ SlotService)
```

Views never own rules. `Hud` only *reads* state via signals; `SlotUi` delegates
all maths/money to `SlotService` (the same path the AI uses).

---

## Dependency direction (must always hold)

```
presentation ──▶ systems ──▶ autoload ──▶ domain ──▶ core ──▶ (engine)
```

No arrow ever points left. If a domain class needs an autoload, that is a smell
— pass the data in instead (as `AiBrain` receives a `world` dictionary).
