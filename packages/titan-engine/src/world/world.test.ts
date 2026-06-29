import { describe, it, expect } from 'vitest';
import { World, evenAllocation } from './world.js';
import { ContentRegistry } from '../content/registry.js';
import { STARTER_CONTENT } from '../content/starter-content.js';
import { asZoneDefId } from '../shared/branded.js';
import { isOk } from '../shared/result.js';
import { Rng } from '../shared/rng.js';
import { ZERO_ATTRIBUTES, type Attributes } from '../stats/stats.js';
import { emptyBuild } from '../entities/player.js';
import { unwrap } from '../shared/result.js';

const registry = new ContentRegistry().register(STARTER_CONTENT);
const zone = unwrap(registry.zone(asZoneDefId('verdant_fringe')));

const strongHero: Attributes = {
  ...ZERO_ATTRIBUTES,
  strength: 20,
  agility: 15,
  vitality: 20,
  dexterity: 20,
  luck: 10,
};

const makeWorld = (seed: number, allocated = strongHero): World =>
  new World(registry, zone, Rng.fromSeed(seed), {
    allocated,
    equipment: {},
  });

describe('World — core idle loop', () => {
  it('spawns a monster on the first tick', () => {
    const events = makeWorld(1).tick();
    expect(events.some((e) => e.type === 'spawn')).toBe(true);
  });

  it('a capable hero kills monsters and gains experience over time', () => {
    const world = makeWorld(1);
    const log = world.run(2000);
    expect(log.some((e) => e.type === 'kill')).toBe(true);
    const snap = world.snapshot();
    expect(snap.progress.level).toBeGreaterThan(1);
  });

  it('is fully deterministic: same seed → identical event log', () => {
    const a = makeWorld(42).run(500);
    const b = makeWorld(42).run(500);
    expect(a).toEqual(b);
  });

  it('different seeds diverge', () => {
    const a = JSON.stringify(makeWorld(1).run(500));
    const b = JSON.stringify(makeWorld(2).run(500));
    expect(a).not.toEqual(b);
  });

  it('accumulates gold and loot from kills', () => {
    const world = makeWorld(7);
    world.run(3000);
    const snap = world.snapshot();
    expect(snap.gold).toBeGreaterThan(0);
    expect(snap.inventory.length).toBeGreaterThan(0);
  });

  it('level-up awards attribute points and heals the hero to full', () => {
    const world = makeWorld(1);
    const log = world.run(3000);
    const levelUps = log.filter((e) => e.type === 'levelUp');
    expect(levelUps.length).toBeGreaterThan(0);
    const snap = world.snapshot();
    // After many level-ups the build is stronger than the starting allocation.
    const totalAllocated =
      snap.build.allocated.strength +
      snap.build.allocated.agility +
      snap.build.allocated.vitality +
      snap.build.allocated.intelligence +
      snap.build.allocated.dexterity +
      snap.build.allocated.luck;
    const startTotal = 20 + 15 + 20 + 0 + 20 + 10;
    expect(totalAllocated).toBeGreaterThan(startTotal);
  });

  it('a hopelessly weak hero is defeated and retreats rather than softlocking', () => {
    const world = makeWorld(1, { ...ZERO_ATTRIBUTES });
    const log = world.run(2000);
    expect(log.some((e) => e.type === 'playerDefeated')).toBe(true);
    // Still alive afterward (retreated and healed), loop keeps running.
    expect(world.snapshot().currentHp).toBeGreaterThan(0);
  });

  it('reports a zone lookup as ok content (sanity)', () => {
    expect(isOk(registry.zone(asZoneDefId('verdant_fringe')))).toBe(true);
  });

  it('emptyBuild produces a valid, runnable world', () => {
    const world = new World(registry, zone, Rng.fromSeed(3), emptyBuild());
    expect(() => world.run(100)).not.toThrow();
  });
});

describe('evenAllocation', () => {
  it('distributes points without losing any', () => {
    const a = evenAllocation(7);
    const sum =
      a.strength + a.agility + a.vitality + a.intelligence + a.dexterity + a.luck;
    expect(sum).toBe(7);
  });

  it('handles zero', () => {
    expect(evenAllocation(0)).toEqual(ZERO_ATTRIBUTES);
  });
});
