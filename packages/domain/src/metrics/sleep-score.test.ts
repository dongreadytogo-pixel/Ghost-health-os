import { describe, it, expect } from 'vitest';
import { computeSleepScore } from './sleep-score.js';
import type { SleepSample } from '../health/samples.js';
import type { UserId, IsoDate, ProviderId } from '../shared/branded.js';

const baseMeta = {
  userId: 'u1' as UserId,
  date: '2026-06-27' as IsoDate,
  source: {
    provider: 'fitbit' as ProviderId,
    recordedAt: new Date('2026-06-27T07:00:00Z'),
  },
};

const sleep = (overrides: Partial<SleepSample> = {}): SleepSample => ({
  ...baseMeta,
  kind: 'sleep',
  asleepMinutes: 450,
  timeInBedMinutes: 480,
  stages: { awake: 30, light: 250, deep: 70, rem: 100 },
  ...overrides,
});

describe('computeSleepScore', () => {
  it('rewards a solid 7.5h night with good architecture', () => {
    const score = computeSleepScore(sleep());
    expect(score.value).toBeGreaterThanOrEqual(80);
    expect(score.contributions).toHaveLength(4);
  });

  it('penalizes a very short night', () => {
    const score = computeSleepScore(
      sleep({
        asleepMinutes: 240,
        timeInBedMinutes: 300,
        stages: { awake: 60, light: 150, deep: 40, rem: 50 },
      }),
    );
    expect(score.value).toBeLessThan(70);
    expect(score.weakestContribution?.factor).toBe('duration');
  });

  it('does not reward oversleeping past the cap', () => {
    const eightHours = computeSleepScore(
      sleep({ asleepMinutes: 480, timeInBedMinutes: 500 }),
    );
    const tenHours = computeSleepScore(
      sleep({ asleepMinutes: 600, timeInBedMinutes: 620 }),
    );
    const dur8 = eightHours.contributions.find((c) => c.factor === 'duration');
    const dur10 = tenHours.contributions.find((c) => c.factor === 'duration');
    expect(dur10?.value).toBeLessThanOrEqual(dur8?.value ?? 0);
  });

  it('handles a degenerate zero-sleep sample without throwing', () => {
    const score = computeSleepScore(
      sleep({
        asleepMinutes: 0,
        timeInBedMinutes: 0,
        stages: { awake: 0, light: 0, deep: 0, rem: 0 },
      }),
    );
    expect(score.value).toBe(0);
  });
});
