import { describe, it, expect } from 'vitest';
import {
  computeHeartScore,
  computeStressScore,
} from './vitals-score.js';

describe('computeHeartScore', () => {
  it('scores below-baseline resting HR well', () => {
    const score = computeHeartScore({
      restingHeartRate: 54,
      baselineRestingHeartRate: 60,
    });
    expect(score.value).toBeGreaterThan(70);
  });

  it('penalizes elevated resting HR vs baseline', () => {
    const score = computeHeartScore({
      restingHeartRate: 72,
      baselineRestingHeartRate: 60,
    });
    expect(score.value).toBeLessThan(70);
  });

  it('falls back to an absolute band without a baseline', () => {
    const score = computeHeartScore({ restingHeartRate: 55 });
    expect(score.value).toBeGreaterThan(0);
    expect(score.contributions[0]?.factor).toBe('resting_heart_rate');
  });
});

describe('computeStressScore', () => {
  it('inverts the stress level', () => {
    expect(computeStressScore({ stress: 20 }).value).toBe(80);
    expect(computeStressScore({ stress: 90 }).value).toBe(10);
  });
});
