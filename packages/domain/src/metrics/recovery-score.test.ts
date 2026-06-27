import { describe, it, expect } from 'vitest';
import { computeRecoveryScore } from './recovery-score.js';
import type { RecoveryInputs } from '../health/samples.js';
import type { UserId, IsoDate, ProviderId } from '../shared/branded.js';

const meta = {
  userId: 'u1' as UserId,
  date: '2026-06-27' as IsoDate,
  source: {
    provider: 'fitbit' as ProviderId,
    recordedAt: new Date('2026-06-27T07:00:00Z'),
  },
};

const inputs = (o: Partial<RecoveryInputs> = {}): RecoveryInputs => ({
  ...meta,
  kind: 'recovery',
  ...o,
});

describe('computeRecoveryScore', () => {
  it('scores above baseline-neutral (70) when HRV is up and RHR is down', () => {
    const score = computeRecoveryScore(
      inputs({ hrvMs: 66, restingHeartRate: 54 }),
      { hrvMs: 60, restingHeartRate: 60 },
    );
    expect(score.value).toBeGreaterThan(70);
  });

  it('scores below 70 when HRV is suppressed and RHR is elevated', () => {
    const score = computeRecoveryScore(
      inputs({ hrvMs: 48, restingHeartRate: 66 }),
      { hrvMs: 60, restingHeartRate: 60 },
    );
    expect(score.value).toBeLessThan(70);
  });

  it('re-weights gracefully when only sleep is available', () => {
    const score = computeRecoveryScore(inputs({ sleepScore: 90 }));
    expect(score.value).toBe(90);
    expect(score.contributions).toHaveLength(1);
  });

  it('ignores HRV when no baseline is provided', () => {
    const score = computeRecoveryScore(inputs({ hrvMs: 60, sleepScore: 80 }));
    expect(score.contributions.map((c) => c.factor)).toEqual(['sleep']);
  });
});
