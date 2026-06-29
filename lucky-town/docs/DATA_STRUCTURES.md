# Lucky Town — Data Structures

This is the authoring reference for the data-driven content under `data/` and
the in-memory/save shapes of the core entities. Designers edit JSON here;
programmers map it to typed objects in `src/`.

---

## 1. Slot machine (`data/slot_machines/*.json`)

```jsonc
{
  "id": "slot_fantasy",            // unique id, referenced by props & saves
  "display_name": "Fantasy Fortune",
  "theme": "fantasy",
  "rows": 3,                        // visible grid height; width = reels.length
  "reels": [                        // one "strip" (ordered symbol ids) per reel
    ["gem", "potion", "sword", ...],
    ...
  ],
  "paylines": [                     // each line = row index per reel
    [1,1,1,1,1],                    //   middle row
    [0,1,2,1,0]                     //   a V shape
  ],
  "paytable": {                     // symbol → multiplier for a run of (index+1)
    "gem":    [0, 0, 1, 2, 5],      //   3-of-a-kind pays 1×bet, 5-of-a-kind 5×
    "dragon": [0, 0, 10, 40, 200]
  },
  "scatter_pays": {                 // pay anywhere on the grid, by count
    "chest": { "3": 5, "4": 20, "5": 100 }
  },
  "wild_ids":    ["rune"],          // substitute for any non-scatter symbol
  "scatter_ids": ["chest"],         // counted anywhere, ignore paylines
  "min_bet": 10, "max_bet": 1000, "bet_step": 10,
  "jackpot_contribution": 0.01,     // fraction of each bet feeding the pot
  "jackpot_symbol": "dragon",
  "jackpot_line_length": 5
}
```

**Maths model.** Multipliers are *per bet*: payout = `multiplier × bet`. A reel
spin chooses a random stop on the strip and reads `rows` consecutive symbols
(wrapping). Because the strip composition fixes the symbol frequencies, the
machine's return-to-player is fully determined by this data and verifiable via
`SlotEvaluator.estimate_rtp()`.

**Validation.** `SlotMachineConfig.validate()` checks: reels non-empty, each
strip ≥ `rows`, every payline covers every reel, sane bet bounds. Run it in
tooling/tests when authoring a new theme.

---

## 2. Pet species (`data/pet_species/*.json`)

```jsonc
{
  "id": "dragon",
  "display_name": "Dragon",
  "category": "legendary",
  "base_value": 2500,               // baseline market price
  "genes": ["power", "wingspan", "scale_shine", "rarity", "elemental"],
  "traits": [                       // unlocked when a gene crosses a threshold
    { "name": "elder_wyrm", "gene": "power", "threshold": 0.95 }
  ],
  "mutation_chance": 0.08,          // chance to roll a mutation at birth
  "mutation_pool": ["void", "celestial", "molten", "frost"]
}
```

**Genetics.** Each individual pet stores a float allele in `[0,1]` per gene.
Breeding (`PetBreeder.breed`) blends parents' alleles and adds Gaussian
mutation, so dedicated breeders can push a bloodline toward higher quality over
generations. `quality()` aggregates genes + trait/mutation bonuses; it drives
`market_value()`.

---

## 3. Personality (`data/personalities/*.json`)

```jsonc
{
  "id": "gambler",
  "display_name": "Gambler",
  "risk_tolerance": 0.85,           // 0 cautious … 1 thrill-seeking
  "frugality": 0.2,                 // 0 spendthrift … 1 saver
  "sociability": 0.5,
  "action_weights": {               // base desire per action id
    "gamble": 1.0, "eat": 0.6, "sleep": 0.6, "work": 0.4
  }
}
```

Action ids must match `AiBrain.CANDIDATES`. Weights are *desires*; the brain
combines them with need pressure, affordability and memory to pick an action.

---

## 4. Building (`data/buildings/*.json`)

```jsonc
{ "id": "casino", "display_name": "Casino",
  "build_cost": 8000, "daily_income": 700,
  "category": "entertainment", "max_level": 5 }
```

`PropertyPlot.daily_income()` = `daily_income × building_level`. Income is paid
by `WorldDirector` on each `day_started`.

---

## 5. Market item (`data/market_items/*.json`)

```jsonc
{ "id": "furniture", "display_name": "Furniture",
  "base_price": 220, "min_price": 80, "max_price": 900,
  "supply": 80, "demand": 90, "category": "decor" }
```

`Economy` reprices as `base × clamp(demand/supply)`. Buying raises demand,
selling raises supply; both relax toward baseline each day so shocks fade.

---

## 6. Entity save shapes

Produced by each entity's `to_dict()`; consumed by `from_dict()`. The full game
snapshot (`SaveManager`):

```jsonc
{
  "version": 1,
  "meta":    { "saved_at", "day", "player_name", "net_worth", "citizen_count" },
  "rng":     { "master_seed" },
  "clock":   { "total_minutes" },
  "economy": { "balances", "jackpots", "market", "transaction_seq" },
  "world":   { "player_id", "citizens": [...], "pets": [...], "plots": [...] }
}
```

### Citizen
```jsonc
{ "id", "citizen_name", "age", "personality_id", "is_player",
  "hunger", "energy", "happiness", "social",
  "pet_ids", "plot_ids", "inventory", "job_id", "home_plot_id",
  "memory": { "slot_wins", "slot_losses", "net_gambling", "favourite_slot", ... },
  "relationships": { "<other_id>": 0.4 },
  "stats": { "days_lived", "total_earned", "total_spent", "pets_bred", "buildings_built" } }
```

### Pet
```jsonc
{ "id", "species_id", "nickname", "level", "experience",
  "genes": { "<gene>": 0.0..1.0 }, "traits": [...], "mutations": [...],
  "happiness", "birth_day", "owner_id" }
```

### PropertyPlot
```jsonc
{ "id", "grid_x", "grid_y", "owner_id", "building_id", "building_level",
  "base_value", "value", "for_sale", "list_price" }
```

---

## 7. Versioning & forward-compatibility

- Every snapshot carries a `version`. `SaveManager._migrate()` upgrades old
  saves one step at a time.
- Loaders use `data.get(key, default)` everywhere, so adding a field never
  breaks old saves.
- `DataRegistry` ignores unknown JSON keys, so content files can adopt new
  fields ahead of code.
