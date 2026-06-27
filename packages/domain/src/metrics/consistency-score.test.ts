import { describe, it, expect } from 'vitest';
import { computeConsistencyScore } from './consistency-score.js';

describe('computeConsistencyScore', () => {
  it('rewards frequent activity and a long streak', () => {
    const score = computeConsistencyScore({
      activeDays: Array.from({ length: 14 }, () => true),
      currentStreak: 14,
    });
    expect(score.value).toBe(100);
  });

  it('scores partial frequency proportionally', () => {
    const score = computeConsistencyScore({
      activeDays: [true, false, true, false, true, false, true, false, true, false],
      currentStreak: 0,
    });
    const freq = score.contributions.find((c) => c.factor === 'frequency');
    expect(freq?.value).toBeCloseTo(50);
  });

  it('handles an empty history without dividing by zero', () => {
    const score = computeConsistencyScore({ activeDays: [], currentStreak: 0 });
    expect(score.value).toBe(0);
  });
});
