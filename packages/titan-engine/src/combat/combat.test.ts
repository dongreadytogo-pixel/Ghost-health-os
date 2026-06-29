import { describe, it, expect } from 'vitest';
import {
  resolveAttack,
  hitChance,
  damageMultiplierFromDefense,
  DEFAULT_COMBAT,
} from './combat.js';
import { Rng } from '../shared/rng.js';
import { deriveStats, type DerivedStats } from '../stats/stats.js';

const fighter: DerivedStats = deriveStats({
  strength: 20,
  agility: 10,
  vitality: 10,
  intelligence: 0,
  dexterity: 30,
  luck: 10,
});

const dummy: DerivedStats = deriveStats({
  strength: 0,
  agility: 0,
  vitality: 5,
  intelligence: 0,
  dexterity: 0,
  luck: 0,
});

describe('hitChance', () => {
  it('rises with accuracy and falls with evasion', () => {
    const accurate = { ...dummy, accuracy: 100 };
    const evasive = { ...dummy, evasion: 100 };
    expect(hitChance(accurate, dummy)).toBeGreaterThan(
      hitChance(dummy, evasive),
    );
  });

  it('stays within configured bounds', () => {
    const v = hitChance({ ...dummy, accuracy: 100000 }, dummy);
    expect(v).toBeLessThanOrEqual(DEFAULT_COMBAT.maxHitChance);
    expect(v).toBeGreaterThanOrEqual(DEFAULT_COMBAT.minHitChance);
  });
});

describe('damageMultiplierFromDefense', () => {
  it('is 1 at zero defense and decreases monotonically', () => {
    expect(damageMultiplierFromDefense(0)).toBe(1);
    expect(damageMultiplierFromDefense(50)).toBeCloseTo(0.5, 5);
    expect(damageMultiplierFromDefense(100)).toBeLessThan(
      damageMultiplierFromDefense(50),
    );
  });
});

describe('resolveAttack', () => {
  it('is deterministic for a given rng seed', () => {
    const a = resolveAttack(fighter, dummy, Rng.fromSeed(1));
    const b = resolveAttack(fighter, dummy, Rng.fromSeed(1));
    expect(a).toEqual(b);
  });

  it('a guaranteed miss deals no damage', () => {
    // Force evasion so high that hit chance floors, then seed a miss.
    const evasive = { ...dummy, evasion: 1_000_000 };
    let sawMiss = false;
    const rng = Rng.fromSeed(123);
    for (let i = 0; i < 200; i++) {
      const out = resolveAttack(fighter, evasive, rng);
      if (!out.hit) {
        expect(out.damage).toBe(0);
        sawMiss = true;
        break;
      }
    }
    expect(sawMiss).toBe(true);
  });

  it('a landed hit always deals at least minDamage', () => {
    const rng = Rng.fromSeed(7);
    for (let i = 0; i < 500; i++) {
      const out = resolveAttack(fighter, dummy, rng);
      if (out.hit) expect(out.damage).toBeGreaterThanOrEqual(DEFAULT_COMBAT.minDamage);
    }
  });

  it('critical hits deal more than the non-crit ceiling', () => {
    // With variance ±10% and crit ×, a crit must beat the best possible non-crit.
    const rng = Rng.fromSeed(2026);
    const power = fighter.physicalAttack;
    const mitigation = damageMultiplierFromDefense(dummy.defense);
    const nonCritCeil = power * (1 + DEFAULT_COMBAT.damageSpread) * mitigation;
    let sawCrit = false;
    for (let i = 0; i < 2000; i++) {
      const out = resolveAttack(fighter, dummy, rng);
      if (out.critical && out.hit) {
        expect(out.damage).toBeGreaterThan(nonCritCeil);
        sawCrit = true;
      }
    }
    expect(sawCrit).toBe(true);
  });

  it('magic attacks use magic power', () => {
    const mage = deriveStats({
      strength: 0,
      agility: 0,
      vitality: 0,
      intelligence: 40,
      dexterity: 50,
      luck: 0,
    });
    const rng = Rng.fromSeed(5);
    let landed = false;
    for (let i = 0; i < 100 && !landed; i++) {
      const out = resolveAttack(mage, dummy, rng, 'magic');
      if (out.hit) {
        expect(out.kind).toBe('magic');
        expect(out.damage).toBeGreaterThan(0);
        landed = true;
      }
    }
    expect(landed).toBe(true);
  });
});
