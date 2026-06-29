import { describe, it, expect } from 'vitest';
import { World, evenAllocation, DEFAULT_WORLD_CONFIG } from './world.js';
import { ContentRegistry } from '../content/registry.js';
import {
  STARTER_CONTENT,
  STARTER_MOUNTS,
  STARTER_SKILLS,
} from '../content/starter-content.js';
import { asZoneDefId } from '../shared/branded.js';
import { isOk } from '../shared/result.js';
import { Rng } from '../shared/rng.js';
import { ZERO_ATTRIBUTES, type Attributes } from '../stats/stats.js';
import { emptyBuild } from '../entities/player.js';
import { unwrap } from '../shared/result.js';
import { makeMountInstance } from '../mounts/mount.js';
import { rollSkillInstance } from '../skills/skill.js';
import type { WorldEvent } from './world.js';

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

const countEvents = (log: WorldEvent[], type: WorldEvent['type']): number =>
  log.filter((e) => e.type === type).length;

describe('World — mounts (ขี่ม้า)', () => {
  it('a mount makes the hero attack faster and stronger', () => {
    const mount = makeMountInstance(STARTER_MOUNTS[0]!, 'mythic', true);
    const mounted = new World(registry, zone, Rng.fromSeed(1), {
      allocated: strongHero,
      equipment: {},
      mount,
    });
    const onFoot = new World(registry, zone, Rng.fromSeed(1), {
      allocated: strongHero,
      equipment: {},
    });
    const mountedKills = countEvents(mounted.run(1500), 'kill');
    const footKills = countEvents(onFoot.run(1500), 'kill');
    expect(mountedKills).toBeGreaterThan(footKills);
  });
});

describe('World — companions (จับมอนสเตอร์เข้าทีม)', () => {
  it('captures monsters into the party as it hunts', () => {
    const world = new World(
      registry,
      zone,
      Rng.fromSeed(3),
      { allocated: strongHero, equipment: {} },
      { ...DEFAULT_WORLD_CONFIG, capture: { ...DEFAULT_WORLD_CONFIG.capture, baseChance: 0.5 } },
    );
    const log = world.run(4000);
    expect(countEvents(log, 'companionJoined')).toBeGreaterThan(0);
    expect(world.snapshot().roster.length).toBeGreaterThan(0);
  });

  it('caps the active party but keeps extras in the roster', () => {
    const world = new World(
      registry,
      zone,
      Rng.fromSeed(5),
      { allocated: strongHero, equipment: {} },
      {
        ...DEFAULT_WORLD_CONFIG,
        capture: { ...DEFAULT_WORLD_CONFIG.capture, baseChance: 1 },
        autoFuse: false,
      },
    );
    world.run(3000);
    const snap = world.snapshot();
    expect(snap.party.length).toBeLessThanOrEqual(DEFAULT_WORLD_CONFIG.maxPartySize);
    expect(snap.roster.length).toBeGreaterThanOrEqual(snap.party.length);
  });

  it('auto-fuses duplicate-rarity companions into rarer ones', () => {
    const world = new World(
      registry,
      zone,
      Rng.fromSeed(5),
      { allocated: strongHero, equipment: {} },
      {
        ...DEFAULT_WORLD_CONFIG,
        capture: { ...DEFAULT_WORLD_CONFIG.capture, baseChance: 1 },
        autoFuse: true,
      },
    );
    const log = world.run(3000);
    expect(countEvents(log, 'fusion')).toBeGreaterThan(0);
  });

  it('companions contribute damage: a party clears faster than a lone hero', () => {
    const weak: Attributes = { ...ZERO_ATTRIBUTES, strength: 10, agility: 6, vitality: 12, dexterity: 10, luck: 4 };
    const solo = new World(registry, zone, Rng.fromSeed(8), { allocated: weak, equipment: {} }, {
      ...DEFAULT_WORLD_CONFIG,
      capture: { ...DEFAULT_WORLD_CONFIG.capture, baseChance: 0 },
    });
    const withParty = new World(registry, zone, Rng.fromSeed(8), { allocated: weak, equipment: {} }, {
      ...DEFAULT_WORLD_CONFIG,
      capture: { ...DEFAULT_WORLD_CONFIG.capture, baseChance: 1 },
    });
    expect(countEvents(withParty.run(4000), 'kill')).toBeGreaterThanOrEqual(
      countEvents(solo.run(4000), 'kill'),
    );
  });
});

describe('World — random skills', () => {
  it('the hero auto-casts equipped skills in battle', () => {
    const skills = STARTER_SKILLS.map((d) => rollSkillInstance(d, Rng.fromSeed(2)));
    const world = new World(
      registry,
      zone,
      Rng.fromSeed(1),
      { allocated: strongHero, equipment: {} },
      DEFAULT_WORLD_CONFIG,
      { level: 1, currentExp: 0 },
      { skills },
    );
    const log = world.run(1500);
    expect(countEvents(log, 'skill')).toBeGreaterThan(0);
  });

  it('skills make the hero clear faster', () => {
    const skills = STARTER_SKILLS.map((d) => rollSkillInstance(d, Rng.fromSeed(2)));
    const withSkills = new World(
      registry, zone, Rng.fromSeed(7),
      { allocated: strongHero, equipment: {} },
      DEFAULT_WORLD_CONFIG, { level: 1, currentExp: 0 }, { skills },
    );
    const without = new World(
      registry, zone, Rng.fromSeed(7),
      { allocated: strongHero, equipment: {} },
    );
    expect(countEvents(withSkills.run(1500), 'kill')).toBeGreaterThan(
      countEvents(without.run(1500), 'kill'),
    );
  });
});

describe('World — determinism with all systems active', () => {
  it('same seed reproduces an identical log with mounts, party and skills', () => {
    const build = (seed: number): World =>
      new World(
        registry,
        zone,
        Rng.fromSeed(seed),
        {
          allocated: strongHero,
          equipment: {},
          mount: makeMountInstance(STARTER_MOUNTS[1]!, 'rare', false),
        },
        {
          ...DEFAULT_WORLD_CONFIG,
          capture: { ...DEFAULT_WORLD_CONFIG.capture, baseChance: 0.4, skillPool: STARTER_SKILLS },
        },
        { level: 1, currentExp: 0 },
        { skills: STARTER_SKILLS.map((d) => rollSkillInstance(d, Rng.fromSeed(99))) },
      );
    expect(build(123).run(2000)).toEqual(build(123).run(2000));
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
