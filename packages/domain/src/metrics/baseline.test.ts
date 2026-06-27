import { describe, it, expect } from 'vitest';
import { computeRecoveryBaseline } from './baseline.js';
import type { RecoveryInputs } from '../health/samples.js';
import type { UserId, IsoDate, ProviderId } from '../shared/branded.js';

const rec = (date: string, hrvMs?: number, rhr?: number): RecoveryInputs => ({
  userId: 'u1' as UserId,
  date: date as IsoDate,
  kind: 'recovery',
  source: {
    provider: 'fitbit' as ProviderId,
    recordedAt: new Date(`${date}T07:00:00Z`),
  },
  ...(hrvMs !== undefined ? { hrvMs } : {}),
  ...(rhr !== undefined ? { restingHeartRate: rhr } : {}),
});

describe('computeRecoveryBaseline', () => {
  it('averages HRV and RHR within the trailing window', () => {
    const samples = [
      rec('2026-06-01', 60, 58),
      rec('2026-06-02', 62, 60),
      rec('2026-06-03', 64, 62),
    ];
    const baseline = computeRecoveryBaseline(samples, '2026-06-10' as IsoDate);
    expect(baseline.hrvMs).toBeCloseTo(62);
    expect(baseline.restingHeartRate).toBeCloseTo(60);
  });

  it('excludes the asOf day itself and anything outside the window', () => {
    const samples = [
      rec('2026-05-01', 99, 99), // outside 30d window
      rec('2026-06-07', 60, 58),
      rec('2026-06-08', 62, 60),
      rec('2026-06-09', 64, 62),
      rec('2026-06-10', 200, 200), // asOf day, excluded
    ];
    const baseline = computeRecoveryBaseline(samples, '2026-06-10' as IsoDate, {
      windowDays: 30,
      minSamples: 3,
    });
    expect(baseline.hrvMs).toBeCloseTo(62);
  });

  it('omits a signal that has fewer than minSamples', () => {
    const samples = [rec('2026-06-08', 60), rec('2026-06-09', 62)];
    const baseline = computeRecoveryBaseline(samples, '2026-06-10' as IsoDate, {
      minSamples: 3,
    });
    expect(baseline.hrvMs).toBeUndefined();
  });
});
