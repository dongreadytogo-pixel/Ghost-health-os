import { describe, it, expect } from 'vitest';
import {
  addAttributes,
  deriveStats,
  DEFAULT_STAT_FORMULA,
  ZERO_ATTRIBUTES,
  type Attributes,
} from './stats.js';

const attrs = (over: Partial<Attributes> = {}): Attributes => ({
  ...ZERO_ATTRIBUTES,
  ...over,
});

describe('addAttributes', () => {
  it('adds component-wise', () => {
    const sum = addAttributes(
      attrs({ strength: 3, luck: 1 }),
      attrs({ strength: 2, agility: 5 }),
    );
    expect(sum.strength).toBe(5);
    expect(sum.agility).toBe(5);
    expect(sum.luck).toBe(1);
  });
});

describe('deriveStats', () => {
  it('produces base values from zero attributes', () => {
    const s = deriveStats(ZERO_ATTRIBUTES);
    expect(s.maxHp).toBe(DEFAULT_STAT_FORMULA.baseHp);
    expect(s.maxMp).toBe(DEFAULT_STAT_FORMULA.baseMp);
    expect(s.physicalAttack).toBe(0);
    expect(s.critChance).toBe(0);
  });

  it('scales hp with vitality and attack with strength', () => {
    const s = deriveStats(attrs({ vitality: 10, strength: 10 }));
    expect(s.maxHp).toBe(50 + 10 * 12);
    expect(s.physicalAttack).toBe(roundExpected(10 * 2.5));
  });

  it('caps crit chance at the configured maximum', () => {
    const s = deriveStats(attrs({ luck: 100000 }));
    expect(s.critChance).toBe(DEFAULT_STAT_FORMULA.maxCritChance);
  });

  it('attack interval shrinks with agility but never below the floor', () => {
    const slow = deriveStats(attrs({ agility: 0 }));
    const fast = deriveStats(attrs({ agility: 50 }));
    const capped = deriveStats(attrs({ agility: 100000 }));
    expect(fast.attackIntervalTicks).toBeLessThan(slow.attackIntervalTicks);
    expect(capped.attackIntervalTicks).toBe(
      DEFAULT_STAT_FORMULA.minAttackIntervalTicks,
    );
  });

  it('honours an overridden config (data-driven retuning)', () => {
    const buffed = deriveStats(attrs({ vitality: 1 }), {
      ...DEFAULT_STAT_FORMULA,
      hpPerVitality: 1000,
    });
    expect(buffed.maxHp).toBe(50 + 1000);
  });
});

function roundExpected(n: number): number {
  return Math.floor(n + 0.5);
}
