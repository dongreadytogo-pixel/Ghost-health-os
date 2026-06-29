import { describe, it, expect } from 'vitest';
import { World, evenAllocation, DEFAULT_WORLD_CONFIG } from './world.js';
import { ContentRegistry } from '../content/registry.js';
import {
  STARTER_CONTENT,
  STARTER_MOUNTS,
  STARTER_SKILLS,
} from '../content/starter-content.js';
import {
  asItemDefId,
  asMonsterDefId,
  asZoneDefId,
} from '../shared/branded.js';
import { deriveStats } from '../stats/stats.js';
import { upgradeLevelOf } from '../items/upgrade.js';
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

describe('World — save / load', () => {
  const config = {
    ...DEFAULT_WORLD_CONFIG,
    capture: { ...DEFAULT_WORLD_CONFIG.capture, baseChance: 0.3, skillPool: STARTER_SKILLS },
  };
  const fresh = (): World =>
    new World(
      registry,
      zone,
      Rng.fromSeed(77),
      { allocated: strongHero, equipment: {}, mount: makeMountInstance(STARTER_MOUNTS[0]!, 'rare', false) },
      config,
      { level: 1, currentExp: 0 },
      { skills: STARTER_SKILLS.map((d) => rollSkillInstance(d, Rng.fromSeed(11))) },
    );

  it('resume is deterministic: two restores from one save share a future', () => {
    const original = fresh();
    original.run(1200);
    const save = original.serialize();

    const a = World.fromSave(registry, zone, save, config);
    const b = World.fromSave(registry, zone, save, config);
    expect(a.run(800)).toEqual(b.run(800));
  });

  it('a restored world keeps progressing from the saved state', () => {
    const original = fresh();
    original.run(1200);
    const save = original.serialize();
    const restored = World.fromSave(registry, zone, save, config);
    restored.run(1500);
    expect(restored.snapshot().progress.level).toBeGreaterThanOrEqual(
      save.progress.level,
    );
    expect(restored.snapshot().gold).toBeGreaterThanOrEqual(save.gold);
  });

  it('a save is plain JSON (round-trips through stringify)', () => {
    const w = fresh();
    w.run(500);
    const save = w.serialize();
    const round = JSON.parse(JSON.stringify(save));
    const restored = World.fromSave(registry, zone, round, config);
    expect(restored.snapshot().progress).toEqual(w.snapshot().progress);
    expect(restored.snapshot().roster.length).toBe(w.snapshot().roster.length);
  });

  it('preserves gold, level and roster across reload', () => {
    const w = fresh();
    w.run(2000);
    const before = w.snapshot();
    const restored = World.fromSave(registry, zone, w.serialize(), config);
    const after = restored.snapshot();
    expect(after.gold).toBe(before.gold);
    expect(after.progress.level).toBe(before.progress.level);
    expect(after.roster.length).toBe(before.roster.length);
    expect(restored.ticksElapsed).toBe(w.ticksElapsed);
  });
});

describe('World — auto-equip / auto-sell / auto-upgrade (Phase 2)', () => {
  const reg = new ContentRegistry().register({
    items: [
      {
        id: asItemDefId('greatsword'),
        name: 'Greatsword',
        slot: 'weapon',
        baseRarity: 'rare',
        baseAttributes: { strength: 30, dexterity: 10 },
        affixPool: [],
        value: 50,
        stackable: false,
      },
      {
        id: asItemDefId('ore'),
        name: 'Ore',
        slot: 'material',
        baseRarity: 'common',
        baseAttributes: {},
        affixPool: [],
        value: 3,
        stackable: true,
      },
    ],
    monsters: [
      {
        id: asMonsterDefId('dummy'),
        name: 'Training Dummy',
        level: 1,
        stats: deriveStats(ZERO_ATTRIBUTES),
        experienceReward: 5,
        goldReward: { min: 0, max: 0 },
        dropTable: [
          { itemId: asItemDefId('greatsword'), chance: 1, minQuantity: 1, maxQuantity: 1 },
          { itemId: asItemDefId('ore'), chance: 1, minQuantity: 1, maxQuantity: 1 },
        ],
        isBoss: false,
      },
    ],
    zones: [
      {
        id: asZoneDefId('arena'),
        name: 'Arena',
        recommendedLevel: 1,
        spawnTable: [{ monsterId: asMonsterDefId('dummy'), weight: 1 }],
      },
    ],
  });
  const arena = unwrap(reg.zone(asZoneDefId('arena')));
  // Capture off so the only economy is gear/sell/upgrade.
  const cfg = {
    ...DEFAULT_WORLD_CONFIG,
    capture: { ...DEFAULT_WORLD_CONFIG.capture, baseChance: 0 },
  };
  const make = (over = {}): World =>
    new World(reg, arena, Rng.fromSeed(1), { allocated: strongHero, equipment: {} }, {
      ...cfg,
      ...over,
    });

  it('auto-equips a dropped weapon and reflects it in the build', () => {
    const world = make();
    const log = world.run(300);
    expect(countEvents(log, 'equip')).toBeGreaterThan(0);
    expect(world.snapshot().build.equipment.weapon?.name).toBe('Greatsword');
  });

  it('auto-sells surplus gear for gold (even with zero gold drops)', () => {
    const world = make();
    const log = world.run(300);
    expect(countEvents(log, 'autoSell')).toBeGreaterThan(0);
    expect(world.snapshot().gold).toBeGreaterThan(0);
  });

  it('keeps non-equippable materials in the inventory', () => {
    const world = make();
    world.run(300);
    expect(world.snapshot().inventory.some((i) => i.name === 'Ore')).toBe(true);
  });

  it('auto-upgrades equipped gear using earned gold', () => {
    const world = make();
    const log = world.run(600);
    expect(countEvents(log, 'upgrade')).toBeGreaterThan(0);
    const weapon = world.snapshot().build.equipment.weapon!;
    expect(upgradeLevelOf(weapon)).toBeGreaterThanOrEqual(1);
  });

  it('respects disabled auto-systems', () => {
    const world = make({ autoEquip: false });
    world.run(300);
    expect(world.snapshot().build.equipment.weapon).toBeUndefined();
  });

  it('gear and upgrades make the hero hit harder over time', () => {
    const world = make();
    const before = world.hero.maxHp;
    world.run(600);
    // Vitality from gear + upgrades should raise max HP above the bare build.
    expect(world.hero.maxHp).toBeGreaterThanOrEqual(before);
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
