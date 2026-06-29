import { describe, it, expect } from 'vitest';
import {
  applyExperience,
  expToNext,
  DEFAULT_LEVELING,
  type ProgressState,
} from './leveling.js';

const start: ProgressState = { level: 1, currentExp: 0 };

describe('expToNext', () => {
  it('increases with level', () => {
    expect(expToNext(2)).toBeGreaterThan(expToNext(1));
    expect(expToNext(10)).toBeGreaterThan(expToNext(9));
  });

  it('is Infinity at and beyond max level', () => {
    expect(expToNext(DEFAULT_LEVELING.maxLevel)).toBe(Infinity);
    expect(expToNext(DEFAULT_LEVELING.maxLevel + 5)).toBe(Infinity);
  });
});

describe('applyExperience', () => {
  it('accumulates without leveling when below the threshold', () => {
    const r = applyExperience(start, 50);
    expect(r.levelsGained).toBe(0);
    expect(r.state).toEqual({ level: 1, currentExp: 50 });
  });

  it('levels up exactly once and carries the remainder', () => {
    const need = expToNext(1);
    const r = applyExperience(start, need + 10);
    expect(r.levelsGained).toBe(1);
    expect(r.state.level).toBe(2);
    expect(r.state.currentExp).toBe(10);
    expect(r.attributePointsAwarded).toBe(
      DEFAULT_LEVELING.attributePointsPerLevel,
    );
  });

  it('cascades through many levels from one large gain (offline catch-up)', () => {
    const r = applyExperience(start, 1_000_000);
    expect(r.state.level).toBeGreaterThan(1);
    expect(r.levelsGained).toBe(r.state.level - 1);
    expect(r.attributePointsAwarded).toBe(
      r.levelsGained * DEFAULT_LEVELING.attributePointsPerLevel,
    );
  });

  it('never exceeds max level and parks excess exp at zero', () => {
    const r = applyExperience(
      { level: 1, currentExp: 0 },
      Number.MAX_SAFE_INTEGER,
    );
    expect(r.state.level).toBe(DEFAULT_LEVELING.maxLevel);
    expect(r.state.currentExp).toBe(0);
  });

  it('is a no-op at max level', () => {
    const maxed: ProgressState = {
      level: DEFAULT_LEVELING.maxLevel,
      currentExp: 0,
    };
    const r = applyExperience(maxed, 999999);
    expect(r.levelsGained).toBe(0);
    expect(r.state).toEqual(maxed);
  });

  it('ignores non-positive gains', () => {
    expect(applyExperience(start, 0).state).toEqual(start);
    expect(applyExperience(start, -100).state).toEqual(start);
  });
});
