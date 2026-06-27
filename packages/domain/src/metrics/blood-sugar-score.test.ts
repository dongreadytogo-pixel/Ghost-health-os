import { describe, it, expect } from 'vitest';
import { computeBloodSugarTrendScore } from './blood-sugar-score.js';

describe('computeBloodSugarTrendScore', () => {
  it('scores steady readings higher than volatile ones', () => {
    const steady = computeBloodSugarTrendScore({
      readings: [100, 102, 99, 101, 100],
    });
    const volatile = computeBloodSugarTrendScore({
      readings: [80, 160, 90, 200, 70],
    });
    expect(steady.value).toBeGreaterThan(volatile.value);
  });

  it('returns a neutral, data-needed score with too few readings', () => {
    const score = computeBloodSugarTrendScore({ readings: [100] });
    expect(score.value).toBe(50);
    expect(score.contributions[0]?.factor).toBe('data');
  });

  it('keeps language non-diagnostic', () => {
    const score = computeBloodSugarTrendScore({ readings: [100, 105, 98] });
    const text = score.contributions.map((c) => c.explanation).join(' ');
    expect(text).toContain('ไม่ใช่การวินิจฉัย');
  });
});
