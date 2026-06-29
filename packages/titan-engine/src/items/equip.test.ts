import { describe, it, expect } from 'vitest';
import { isEquippable, itemPower, isUpgradeOver, sellValue } from './equip.js';
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

describe('isEquippable', () => {
  it('recognises gear slots and rejects materials/consumables', () => {
    expect(isEquippable('weapon')).toBe(true);
    expect(isEquippable('armor')).toBe(true);
    expect(isEquippable('material')).toBe(false);
    expect(isEquippable('consumable')).toBe(false);
  });
});

describe('itemPower', () => {
  it('rises with attributes, rarity and upgrade level', () => {
    const base = itemPower(item());
    expect(itemPower(item({ totalAttributes: { ...ZERO_ATTRIBUTES, strength: 20 } }))).toBeGreaterThan(base);
    expect(itemPower(item({ rarity: 'epic' }))).toBeGreaterThan(base);
    expect(itemPower(item({ upgradeLevel: 5 }))).toBeGreaterThan(base);
  });
});

describe('isUpgradeOver', () => {
  it('always true against an empty slot', () => {
    expect(isUpgradeOver(item(), undefined)).toBe(true);
  });
  it('compares power for occupied slots', () => {
    const weak = item({ totalAttributes: { ...ZERO_ATTRIBUTES, strength: 5 } });
    const strong = item({ totalAttributes: { ...ZERO_ATTRIBUTES, strength: 30 } });
    expect(isUpgradeOver(strong, weak)).toBe(true);
    expect(isUpgradeOver(weak, strong)).toBe(false);
  });
});

describe('sellValue', () => {
  it('scales with base value, rarity, upgrades and quantity', () => {
    expect(sellValue(item({ rarity: 'mythic' }), 10)).toBeGreaterThan(
      sellValue(item({ rarity: 'common' }), 10),
    );
    expect(sellValue(item({ quantity: 5 }), 10)).toBeGreaterThan(
      sellValue(item({ quantity: 1 }), 10),
    );
    expect(sellValue(item({ upgradeLevel: 4 }), 10)).toBeGreaterThan(
      sellValue(item({ upgradeLevel: 0 }), 10),
    );
  });
});
