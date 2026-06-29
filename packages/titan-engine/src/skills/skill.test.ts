import { describe, it, expect } from 'vitest';
import {
  makeSkillInstance,
  rollSkillInstance,
  castSkill,
  type SkillDefinition,
} from './skill.js';
import { asSkillDefId } from '../shared/branded.js';
import { Rng } from '../shared/rng.js';
import { deriveStats } from '../stats/stats.js';

const burst: SkillDefinition = {
  id: asSkillDefId('cleave'),
  name: 'Cleave',
  kind: 'burst',
  baseCooldownTicks: 60,
  basePower: 3,
};

const triple: SkillDefinition = {
  id: asSkillDefId('triple'),
  name: 'Triple Jab',
  kind: 'multistrike',
  baseCooldownTicks: 40,
  basePower: 1,
  hits: 3,
};

const leech: SkillDefinition = {
  id: asSkillDefId('leech'),
  name: 'Leech',
  kind: 'lifesteal',
  baseCooldownTicks: 50,
  basePower: 2,
  lifestealFraction: 0.5,
};

const mend: SkillDefinition = {
  id: asSkillDefId('mend'),
  name: 'Mend',
  kind: 'heal',
  baseCooldownTicks: 80,
  basePower: 0.3,
};

const attacker = deriveStats({
  strength: 30,
  agility: 10,
  vitality: 20,
  intelligence: 0,
  dexterity: 30,
  luck: 10,
});
const target = deriveStats({
  strength: 0,
  agility: 0,
  vitality: 5,
  intelligence: 0,
  dexterity: 0,
  luck: 0,
});

describe('skill instances scale with rarity', () => {
  it('higher rarity yields more power and shorter cooldown', () => {
    const common = makeSkillInstance(burst, 'common', false);
    const mythic = makeSkillInstance(burst, 'mythic', false);
    expect(mythic.power).toBeGreaterThan(common.power);
    expect(mythic.cooldownTicks).toBeLessThan(common.cooldownTicks);
  });

  it('shiny stacks more power', () => {
    const plain = makeSkillInstance(burst, 'rare', false);
    const shiny = makeSkillInstance(burst, 'rare', true);
    expect(shiny.power).toBeGreaterThan(plain.power);
  });

  it('rollSkillInstance is deterministic for a seed', () => {
    const a = rollSkillInstance(burst, Rng.fromSeed(3));
    const b = rollSkillInstance(burst, Rng.fromSeed(3));
    expect(a).toEqual(b);
  });

  it('cooldown never drops below the floor', () => {
    const inst = makeSkillInstance(
      { ...burst, baseCooldownTicks: 10 },
      'mythic',
      true,
    );
    expect(inst.cooldownTicks).toBeGreaterThanOrEqual(8);
  });
});

describe('castSkill', () => {
  it('burst deals scaled single-hit damage', () => {
    const inst = makeSkillInstance(burst, 'common', false);
    const result = castSkill(attacker, target, inst, Rng.fromSeed(1));
    expect(result.hits.length).toBe(1);
    expect(result.totalDamage).toBeGreaterThan(0);
  });

  it('multistrike produces the configured number of hits', () => {
    const inst = makeSkillInstance(triple, 'common', false);
    const result = castSkill(attacker, target, inst, Rng.fromSeed(1));
    expect(result.hits.length).toBe(3);
  });

  it('lifesteal heals a fraction of damage dealt', () => {
    const inst = makeSkillInstance(leech, 'common', false);
    const result = castSkill(attacker, target, inst, Rng.fromSeed(2));
    expect(result.heal).toBe(Math.floor(result.totalDamage * 0.5 + 0.5));
  });

  it('heal restores a fraction of max HP and deals no damage', () => {
    const inst = makeSkillInstance(mend, 'common', false);
    const result = castSkill(attacker, target, inst, Rng.fromSeed(2));
    expect(result.totalDamage).toBe(0);
    expect(result.heal).toBe(Math.floor(attacker.maxHp * 0.3 + 0.5));
  });

  it('is deterministic for a given seed', () => {
    const inst = makeSkillInstance(triple, 'epic', false);
    const a = castSkill(attacker, target, inst, Rng.fromSeed(9));
    const b = castSkill(attacker, target, inst, Rng.fromSeed(9));
    expect(a).toEqual(b);
  });
});
