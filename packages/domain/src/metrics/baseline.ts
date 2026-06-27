import type { IsoDate } from '../shared/branded.js';
import type { RecoveryInputs } from '../health/samples.js';
import type { RecoveryBaseline } from './recovery-score.js';

/**
 * Personal baselines. Recovery is meaningful only *relative to you*, so we
 * compute trailing-window means of HRV and resting heart rate from the user's
 * own history. Days missing a signal are simply skipped for that signal — the
 * HRV mean and RHR mean are computed independently over whatever data exists.
 *
 * Pure and deterministic: feed it the samples, get a baseline back.
 */
export interface BaselineOptions {
  /** Trailing window length in days (default 30). */
  readonly windowDays?: number;
  /** Minimum samples required before a baseline is trusted (default 3). */
  readonly minSamples?: number;
}

const dayMs = 24 * 60 * 60 * 1000;

export function computeRecoveryBaseline(
  samples: readonly RecoveryInputs[],
  asOf: IsoDate,
  options: BaselineOptions = {},
): RecoveryBaseline {
  const windowDays = options.windowDays ?? 30;
  const minSamples = options.minSamples ?? 3;

  const end = Date.parse(asOf);
  const start = end - windowDays * dayMs;

  const hrv: number[] = [];
  const rhr: number[] = [];

  for (const s of samples) {
    const t = Date.parse(s.date);
    if (Number.isNaN(t) || t < start || t >= end) continue; // exclude asOf day itself
    if (s.hrvMs !== undefined) hrv.push(s.hrvMs);
    if (s.restingHeartRate !== undefined) rhr.push(s.restingHeartRate);
  }

  const baseline: { hrvMs?: number; restingHeartRate?: number } = {};
  if (hrv.length >= minSamples) baseline.hrvMs = mean(hrv);
  if (rhr.length >= minSamples) baseline.restingHeartRate = mean(rhr);
  return baseline;
}

function mean(xs: readonly number[]): number {
  return xs.reduce((a, b) => a + b, 0) / xs.length;
}
