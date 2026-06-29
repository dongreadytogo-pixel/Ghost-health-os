import { describe, it, expect } from 'vitest';
import { ContentRegistry } from './registry.js';
import { asItemDefId, asMonsterDefId } from '../shared/branded.js';
import { isErr, isOk } from '../shared/result.js';
import type { ItemDefinition, MonsterDefinition } from './definitions.js';
import { deriveStats, ZERO_ATTRIBUTES } from '../stats/stats.js';

const slime: MonsterDefinition = {
  id: asMonsterDefId('slime'),
  name: 'Gel Crawler',
  level: 1,
  stats: deriveStats(ZERO_ATTRIBUTES),
  experienceReward: 10,
  goldReward: { min: 1, max: 3 },
  dropTable: [],
  isBoss: false,
};

const potion: ItemDefinition = {
  id: asItemDefId('potion'),
  name: 'Minor Vitality Draught',
  slot: 'consumable',
  baseRarity: 'common',
  baseAttributes: {},
  affixPool: [],
  value: 5,
  stackable: true,
};

describe('ContentRegistry', () => {
  it('registers and resolves content by id', () => {
    const reg = new ContentRegistry().register({
      monsters: [slime],
      items: [potion],
    });
    const m = reg.monster(asMonsterDefId('slime'));
    expect(isOk(m)).toBe(true);
    if (isOk(m)) expect(m.value.name).toBe('Gel Crawler');
    expect(reg.counts).toEqual({ monsters: 1, items: 1, affixes: 0, zones: 0 });
  });

  it('returns a typed error for unknown ids', () => {
    const reg = new ContentRegistry();
    const r = reg.monster(asMonsterDefId('missing'));
    expect(isErr(r)).toBe(true);
    if (isErr(r)) expect(r.error.code).toBe('UNKNOWN_MONSTER');
  });

  it('later registrations override earlier ones by id', () => {
    const reg = new ContentRegistry()
      .register({ monsters: [slime] })
      .register({ monsters: [{ ...slime, name: 'Reskinned Gel' }] });
    const m = reg.monster(asMonsterDefId('slime'));
    if (isOk(m)) expect(m.value.name).toBe('Reskinned Gel');
    expect(reg.counts.monsters).toBe(1);
  });

  it('resolveAffixes skips unknown ids rather than throwing', () => {
    const reg = new ContentRegistry();
    expect(reg.resolveAffixes([])).toEqual([]);
  });
});
