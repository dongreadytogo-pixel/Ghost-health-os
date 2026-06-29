import { describe, it, expect } from 'vitest';
import {
  companionStats,
  companionPower,
  companionTitle,
  gainBond,
  DEFAULT_BOND,
  type Companion,
} from './companion.js';
import { asEntityId, asMonsterDefId } from '../shared/branded.js';
import { deriveStats } from '../stats/stats.js';

const base = deriveStats({
  strength: 8,
  agility: 4,
  vitality: 6,
  intelligence: 0,
  dexterity: 5,
  luck: 2,
});

const make = (over: Partial<Companion> = {}): Companion => ({
  id: asEntityId('c1'),
  sourceMonsterId: asMonsterDefId('crawler'),
  name: 'Common Crawler',
  baseName: 'Crawler',
  rarity: 'common',
  shiny: false,
  baseStats: base,
  bond: 0,
  ...over,
});

describe('companionTitle', () => {
  it('tags rarity and marks shiny', () => {
    expect(companionTitle('rare', false, 'Crawler')).toBe('Rare Crawler');
    expect(companionTitle('mythic', true, 'Crawler')).toBe('✦ Mythic Crawler');
  });
});

describe('companionStats', () => {
  it('scales up with rarity', () => {
    const common = companionStats(make({ rarity: 'common' }));
    const epic = companionStats(make({ rarity: 'epic' }));
    expect(epic.physicalAttack).toBeGreaterThan(common.physicalAttack);
    expect(epic.maxHp).toBeGreaterThan(common.maxHp);
  });

  it('scales up with bond', () => {
    const fresh = companionStats(make({ bond: 0 }));
    const bonded = companionStats(make({ bond: DEFAULT_BOND.maxBond }));
    expect(bonded.physicalAttack).toBeGreaterThan(fresh.physicalAttack);
  });

  it('shiny adds on top of rarity', () => {
    const plain = companionStats(make({ rarity: 'rare', shiny: false }));
    const shiny = companionStats(make({ rarity: 'rare', shiny: true }));
    expect(shiny.maxHp).toBeGreaterThan(plain.maxHp);
  });
});

describe('gainBond', () => {
  it('increases bond and clamps at the maximum', () => {
    expect(gainBond(make(), 1).bond).toBe(1);
    expect(gainBond(make({ bond: DEFAULT_BOND.maxBond }), 5).bond).toBe(
      DEFAULT_BOND.maxBond,
    );
  });

  it('returns the same reference when already maxed (no churn)', () => {
    const maxed = make({ bond: DEFAULT_BOND.maxBond });
    expect(gainBond(maxed, 1)).toBe(maxed);
  });
});

describe('companionPower', () => {
  it('rises with rarity', () => {
    expect(companionPower(make({ rarity: 'legendary' }))).toBeGreaterThan(
      companionPower(make({ rarity: 'common' })),
    );
  });
});
