import { describe, it, expect } from 'vitest';
import {
  computeTrainingLoad,
  computeReadiness,
} from './training-load.js';
import { Score } from '../value-objects/score.js';

describe('computeTrainingLoad', () => {
  it('reports optimal balance for steady load', () => {
    const result = computeTrainingLoad({
      dailyLoads: Array.from({ length: 28 }, () => 100),
    });
    expect(result.acwr).toBeCloseTo(1);
    expect(result.risk).toBe('optimal');
    expect(result.score.value).toBeGreaterThan(80);
  });

  it('flags high overtraining risk on an acute spike', () => {
    const base = Array.from({ length: 21 }, () => 50);
    const spike = Array.from({ length: 7 }, () => 200);
    const result = computeTrainingLoad({ dailyLoads: [...base, ...spike] });
    expect(result.acwr ?? 0).toBeGreaterThan(1.5);
    expect(result.risk).toBe('high');
  });

  it('flags detraining when load drops off', () => {
    const base = Array.from({ length: 21 }, () => 100);
    const taper = Array.from({ length: 7 }, () => 20);
    const result = computeTrainingLoad({ dailyLoads: [...base, ...taper] });
    expect(result.risk).toBe('detraining');
  });

  it('stays neutral without enough chronic history', () => {
    const result = computeTrainingLoad({ dailyLoads: [] });
    expect(result.acwr).toBeUndefined();
    expect(result.risk).toBe('optimal');
  });
});

describe('computeReadiness', () => {
  it('is dominated by recovery but discounted by high load', () => {
    const recovery = Score.of(90);
    const optimal = computeTrainingLoad({
      dailyLoads: Array.from({ length: 28 }, () => 100),
    });
    const overloaded = computeTrainingLoad({
      dailyLoads: [
        ...Array.from({ length: 21 }, () => 50),
        ...Array.from({ length: 7 }, () => 200),
      ],
    });
    const fresh = computeReadiness(recovery, optimal);
    const strained = computeReadiness(recovery, overloaded);
    expect(fresh.value).toBeGreaterThan(strained.value);
  });
});
