import { describe, it, expect } from 'vitest';
import { rollItemInstance, rollLoot } from './loot.js';
import { ContentRegistry } from '../content/registry.js';
import { Rng } from '../shared/rng.js';
import {
  asAffixDefId,
  asItemDefId,
  asMonsterDefId,
} from '../shared/branded.js';
import { deriveStats, ZERO_ATTRIBUTES } from '../stats/stats.js';
import type {
  AffixDefinition,
  ItemDefinition,
  MonsterDefinition,
} from '../content/definitions.js';

const sharpPrefix: AffixDefinition = {
  id: asAffixDefId('sharp'),
  name: 'Sharp',
  kind: 'prefix',
  attributeRange: { min: { strength: 1 }, max: { strength: 5 } },
  weight: 1,
  minRarity: 'common',
};

const luckySuffix: AffixDefinition = {
  id: asAffixDefId('of_luck'),
  name: 'of Luck',
  kind: 'suffix',
  attributeRange: { min: { luck: 2 }, max: { luck: 2 } },
  weight: 1,
  minRarity: 'rare',
};

const sword: ItemDefinition = {
  id: asItemDefId('sword'),
  name: 'Iron Edge',
  slot: 'weapon',
  baseRarity: 'common',
  baseAttributes: { strength: 3 },
  affixPool: [asAffixDefId('sharp'), asAffixDefId('of_luck')],
  value: 25,
  stackable: false,
};

const monster: MonsterDefinition = {
  id: asMonsterDefId('brute'),
  name: 'Cliff Brute',
  level: 5,
  stats: deriveStats(ZERO_ATTRIBUTES),
  experienceReward: 30,
  goldReward: { min: 10, max: 20 },
  dropTable: [
    {
      itemId: asItemDefId('sword'),
      chance: 1,
      minQuantity: 1,
      maxQuantity: 1,
    },
  ],
  isBoss: false,
};

const registry = new ContentRegistry().register({
  items: [sword],
  affixes: [sharpPrefix, luckySuffix],
  monsters: [monster],
});

describe('rollItemInstance', () => {
  it('applies base attributes plus rolled prefix within range', () => {
    const inst = rollItemInstance(sword, 1, registry, Rng.fromSeed(1));
    // common rarity: prefix is eligible, suffix (minRarity rare) is gated out.
    expect(inst.affixes.some((a) => a.affixId === asAffixDefId('sharp'))).toBe(
      true,
    );
    expect(inst.affixes.some((a) => a.affixId === asAffixDefId('of_luck'))).toBe(
      false,
    );
    // total strength = base 3 + sharp [1..5]
    expect(inst.totalAttributes.strength).toBeGreaterThanOrEqual(4);
    expect(inst.totalAttributes.strength).toBeLessThanOrEqual(8);
  });

  it('allows higher-rarity affixes once the gate is met', () => {
    const epicSword: ItemDefinition = { ...sword, baseRarity: 'epic' };
    const inst = rollItemInstance(epicSword, 1, registry, Rng.fromSeed(3));
    expect(inst.affixes.some((a) => a.affixId === asAffixDefId('of_luck'))).toBe(
      true,
    );
  });

  it('is deterministic for the same seed', () => {
    const a = rollItemInstance(sword, 1, registry, Rng.fromSeed(9));
    const b = rollItemInstance(sword, 1, registry, Rng.fromSeed(9));
    expect(a).toEqual(b);
  });
});

describe('rollLoot', () => {
  it('returns gold within the monster range and the guaranteed drop', () => {
    const loot = rollLoot(monster, registry, Rng.fromSeed(11));
    expect(loot.gold).toBeGreaterThanOrEqual(10);
    expect(loot.gold).toBeLessThanOrEqual(20);
    expect(loot.items).toHaveLength(1);
    expect(loot.items[0]?.defId).toBe(asItemDefId('sword'));
  });

  it('skips entries whose chance roll fails', () => {
    const rare: MonsterDefinition = {
      ...monster,
      dropTable: [
        { itemId: asItemDefId('sword'), chance: 0, minQuantity: 1, maxQuantity: 1 },
      ],
    };
    const loot = rollLoot(rare, registry, Rng.fromSeed(11));
    expect(loot.items).toHaveLength(0);
  });

  it('skips unknown item ids without crashing', () => {
    const broken: MonsterDefinition = {
      ...monster,
      dropTable: [
        {
          itemId: asItemDefId('ghost'),
          chance: 1,
          minQuantity: 1,
          maxQuantity: 1,
        },
      ],
    };
    const loot = rollLoot(broken, registry, Rng.fromSeed(1));
    expect(loot.items).toHaveLength(0);
  });
});
