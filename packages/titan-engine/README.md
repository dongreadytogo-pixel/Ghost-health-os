# @titan/engine — Project Titan

A deterministic, data-driven **simulation core for an idle MMORPG**, inspired by
the *ideas* of classic auto-battle MMOs — **never their assets, names, maps,
characters, monsters, lore, or any copyrighted IP**. Everything concrete in the
game (names, numbers, drop tables, zones) lives as **authored data**, not in the
code.

This package is the inner ring of a clean architecture: **pure logic, no I/O, no
rendering, no networking.** A renderer, a server, and a persistence adapter all
depend inward on it — never the reverse. It mirrors the conventions of the rest
of this monorepo (`Result`/`EngineError`, branded ids, strict TS, co-located
vitest).

## Why "deterministic" is the whole point

An idle MMORPG has two hard requirements that fall out of one design decision:

1. **Offline progress** — when a player returns after hours away, we must compute
   what *would* have happened.
2. **Online authority / anti-cheat** — a server must be able to re-run a client's
   actions and get the same result.

Both are solved by making the entire simulation a pure function of **(seed,
content, inputs)**. Every random decision — hit/miss, crit, loot, affixes,
spawns — draws from one seedable [`Rng`](src/shared/rng.ts) whose state is part
of the save. Same seed ⇒ same game, exactly. That is also what makes the engine
exhaustively unit-testable instead of "probably about right".

## Architecture (modular, SOLID, data-driven, component-based)

```
src/
  shared/        Result, branded ids, math, seedable RNG   (kernel)
  stats/         Attributes → DerivedStats (data-driven formula, retunable)
  progression/   experience curve + cascading level-ups
  content/       definitions (data) + ContentRegistry (plugin lookup)
  combat/        resolveAttack(): hit, crit, defense-mitigated damage
  loot/          drop tables + random prefix/suffix item generation
  entities/      Combatant runtime + classless player build
  world/         World: the auto-battle idle loop (emits events)
  simulation/    offline fast-forward + "while you were away" summary
```

Key seams:

- **Data-driven:** all balance lives in config objects (`StatFormulaConfig`,
  `CombatConfig`, `LevelingConfig`) — remote-config / live-balance ready.
- **Plugin content:** systems resolve content by id through `ContentRegistry`;
  register more bundles to add content with zero code changes.
- **Classless / hybrid builds:** there are no fixed classes. A player is just an
  attribute allocation + equipped items, fed through the same `deriveStats`
  formula a monster skips. Any build is valid.
- **Event-sourced loop:** `World.tick()` returns the events it produced, so the
  loop is observable, replayable, and server-verifiable.

## Usage

```ts
import {
  ContentRegistry, STARTER_CONTENT, World, Rng,
  simulateOffline, asZoneDefId, unwrap, ZERO_ATTRIBUTES,
} from '@titan/engine';

const registry = new ContentRegistry().register(STARTER_CONTENT);
const zone = unwrap(registry.zone(asZoneDefId('verdant_fringe')));

const world = new World(registry, zone, Rng.fromString('save-001'), {
  allocated: { ...ZERO_ATTRIBUTES, strength: 18, vitality: 18, dexterity: 16, agility: 12, luck: 8 },
  equipment: {},
});

// Player was away for 2 hours — fast-forward and show the result.
const summary = simulateOffline(world, 2 * 60 * 60 * 1000);
// → { kills, experienceGained, goldGained, levelsGained, loot, defeats, ticks }

// Or drive it live, one tick at a time, reacting to events:
for (const event of world.tick()) {
  // render 'spawn' | 'attack' | 'kill' | 'loot' | 'levelUp' | 'playerDefeated'
}
```

## Tests

```bash
pnpm --filter @titan/engine test       # 67 tests
pnpm --filter @titan/engine typecheck
```

Determinism is asserted directly: identical seeds produce identical event logs;
snapshot/restore reproduces the exact future stream.

## License & assets

Code is MIT (see repo root). Any art/audio integrated later **must** be
permissively licensed (e.g. Kenney CC0, OpenGameArt, itch.io free assets) with
its license verified and recorded before import. No copyrighted assets, ever.

See [ROADMAP.md](./ROADMAP.md) for the phased build plan.
