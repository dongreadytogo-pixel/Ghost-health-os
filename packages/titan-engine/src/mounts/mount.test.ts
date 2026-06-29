import { describe, it, expect } from 'vitest';
import { makeMountInstance, rollMountInstance, type MountDefinition } from './mount.js';
import { asMountDefId } from '../shared/branded.js';
import { Rng } from '../shared/rng.js';

const steed: MountDefinition = {
  id: asMountDefId('dawnstrider'),
  name: 'Dawnstrider',
  baseBonus: { agility: 4, strength: 2 },
  baseSpeedBonus: 0.1,
};

describe('makeMountInstance', () => {
  it('scales bonus attributes and speed with rarity', () => {
    const common = makeMountInstance(steed, 'common', false);
    const mythic = makeMountInstance(steed, 'mythic', false);
    expect(mythic.bonusAttributes.agility).toBeGreaterThan(
      common.bonusAttributes.agility,
    );
    // lower multiplier = faster
    expect(mythic.attackSpeedMultiplier).toBeLessThan(
      common.attackSpeedMultiplier,
    );
  });

  it('shiny improves the roll further', () => {
    const plain = makeMountInstance(steed, 'rare', false);
    const shiny = makeMountInstance(steed, 'rare', true);
    expect(shiny.bonusAttributes.agility).toBeGreaterThan(
      plain.bonusAttributes.agility,
    );
  });

  it('caps the speed bonus so it never exceeds 50% faster', () => {
    const insane = makeMountInstance(
      { ...steed, baseSpeedBonus: 5 },
      'mythic',
      true,
    );
    expect(insane.attackSpeedMultiplier).toBeGreaterThanOrEqual(0.5);
  });
});

describe('rollMountInstance', () => {
  it('is deterministic for a seed', () => {
    expect(rollMountInstance(steed, Rng.fromSeed(4))).toEqual(
      rollMountInstance(steed, Rng.fromSeed(4)),
    );
  });
});
