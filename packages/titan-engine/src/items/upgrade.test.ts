import { describe, it, expect } from 'vitest';
import {
  upgradeCost,
  upgradeItem,
  upgradeLevelOf,
  canUpgrade,
  effectiveItemAttributes,
  DEFAULT_UPGRADE,
} from './upgrade.js';
import { asItemDefId } from '../shared/branded.js';
import { ZERO_ATTRIBUTES } from '../stats/stats.js';
import type { ItemInstance } from '../loot/loot.js';

const item = (over: Partial<ItemInstance> = {}): ItemInstance => ({
  defId: asItemDefId('sword'),
  name: 'Sword',
  rarity: 'common',
  quantity: 1,
  affixes: [],
  totalAttributes: { ...ZERO_ATTRIBUTES, strength: 10 },
  ...over,
});

describe('upgradeLevelOf', () => {
  it('defaults to 0 when absent', () => {
    expect(upgradeLevelOf(item())).toBe(0);
    expect(upgradeLevelOf(item({ upgradeLevel: 3 }))).toBe(3);
  });
});

describe('upgradeItem', () => {
  it('increments the level immutably', () => {
    const a = item();
    const b = upgradeItem(a);
    expect(upgradeLevelOf(b)).toBe(1);
    expect(upgradeLevelOf(a)).toBe(0);
  });
});

describe('effectiveItemAttributes', () => {
  it('returns base attributes at level 0', () => {
    expect(effectiveItemAttributes(item()).strength).toBe(10);
  });
  it('scales attributes up with level', () => {
    const up = effectiveItemAttributes(item({ upgradeLevel: 5 }));
    expect(up.strength).toBe(Math.floor(10 * (1 + 5 * DEFAULT_UPGRADE.bonusPerLevel) + 0.5));
  });
});

describe('upgradeCost', () => {
  it('rises with level and rarity', () => {
    expect(upgradeCost(item({ upgradeLevel: 2 }))).toBeGreaterThan(
      upgradeCost(item({ upgradeLevel: 0 })),
    );
    expect(upgradeCost(item({ rarity: 'mythic' }))).toBeGreaterThan(
      upgradeCost(item({ rarity: 'common' })),
    );
  });
});

describe('canUpgrade', () => {
  it('is false at max level', () => {
    expect(canUpgrade(item({ upgradeLevel: DEFAULT_UPGRADE.maxLevel }))).toBe(false);
    expect(canUpgrade(item({ upgradeLevel: 0 }))).toBe(true);
  });
});
