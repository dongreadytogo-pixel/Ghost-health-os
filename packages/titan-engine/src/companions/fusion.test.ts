import { describe, it, expect } from 'vitest';
import { fuse } from './fusion.js';
import {
  companionPower,
  type Companion,
} from './companion.js';
import { makeSkillInstance, type SkillDefinition } from '../skills/skill.js';
import { EntityIdFactory } from '../entities/combatant.js';
import {
  asEntityId,
  asMonsterDefId,
  asSkillDefId,
} from '../shared/branded.js';
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
  id: asEntityId('c'),
  sourceMonsterId: asMonsterDefId('crawler'),
  name: 'Common Crawler',
  baseName: 'Crawler',
  rarity: 'common',
  shiny: false,
  baseStats: base,
  bond: 0,
  ...over,
});

const ids = new EntityIdFactory('f');

describe('fuse', () => {
  it('produces a companion one rarity above the better parent', () => {
    const result = fuse(make({ rarity: 'common' }), make({ rarity: 'rare' }), ids);
    expect(result.rarity).toBe('epic');
  });

  it('caps rarity at mythic', () => {
    const result = fuse(
      make({ rarity: 'mythic' }),
      make({ rarity: 'legendary' }),
      ids,
    );
    expect(result.rarity).toBe('mythic');
  });

  it('keeps shiny lineage if either parent is shiny', () => {
    expect(fuse(make({ shiny: true }), make(), ids).shiny).toBe(true);
    expect(fuse(make(), make(), ids).shiny).toBe(false);
  });

  it('is stronger than either parent', () => {
    const a = make({ rarity: 'rare', bond: 4 });
    const b = make({ rarity: 'uncommon', bond: 2 });
    const fused = fuse(a, b, ids);
    expect(companionPower(fused)).toBeGreaterThan(companionPower(a));
    expect(companionPower(fused)).toBeGreaterThan(companionPower(b));
  });

  it('carries over half the higher bond', () => {
    expect(fuse(make({ bond: 8 }), make({ bond: 3 }), ids).bond).toBe(4);
  });

  it('inherits the more powerful parent skill', () => {
    const cleaveDef: SkillDefinition = {
      id: asSkillDefId('cleave'),
      name: 'Cleave',
      kind: 'burst',
      baseCooldownTicks: 60,
      basePower: 3,
    };
    const weakSkill = makeSkillInstance(cleaveDef, 'common', false);
    const strongSkill = makeSkillInstance(cleaveDef, 'legendary', false);
    const result = fuse(
      make({ skill: weakSkill }),
      make({ skill: strongSkill }),
      ids,
    );
    expect(result.skill!.power).toBe(strongSkill.power);
  });

  it('is deterministic (no RNG): same inputs, same output shape', () => {
    const f = new EntityIdFactory('x');
    const g = new EntityIdFactory('x');
    expect(fuse(make({ rarity: 'rare' }), make(), f)).toEqual(
      fuse(make({ rarity: 'rare' }), make(), g),
    );
  });
});
