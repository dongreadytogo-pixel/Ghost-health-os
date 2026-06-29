import { describe, it, expect } from 'vitest';
import { effectiveAttributes, playerStats, emptyBuild } from './player.js';
import type { ItemInstance } from '../loot/loot.js';
import { asItemDefId } from '../shared/branded.js';
import { ZERO_ATTRIBUTES } from '../stats/stats.js';

const sword: ItemInstance = {
  defId: asItemDefId('sword'),
  name: 'Iron Edge',
  rarity: 'common',
  quantity: 1,
  affixes: [],
  totalAttributes: { ...ZERO_ATTRIBUTES, strength: 10 },
};

describe('effectiveAttributes', () => {
  it('sums allocated points with equipped gear', () => {
    const build = {
      allocated: { ...ZERO_ATTRIBUTES, strength: 5, vitality: 3 },
      equipment: { weapon: sword },
    };
    const attrs = effectiveAttributes(build);
    expect(attrs.strength).toBe(15);
    expect(attrs.vitality).toBe(3);
  });

  it('ignores empty slots', () => {
    expect(effectiveAttributes(emptyBuild())).toEqual(ZERO_ATTRIBUTES);
  });
});

describe('playerStats', () => {
  it('reflects equipment in derived stats', () => {
    const bare = playerStats(emptyBuild());
    const armed = playerStats({
      allocated: ZERO_ATTRIBUTES,
      equipment: { weapon: sword },
    });
    expect(armed.physicalAttack).toBeGreaterThan(bare.physicalAttack);
  });
});
