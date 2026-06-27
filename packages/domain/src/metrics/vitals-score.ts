import { Score } from '../value-objects/score.js';
import { clamp } from '../shared/guard.js';

/**
 * Heart score (0–100) from resting heart rate relative to personal baseline.
 * Lower-than-baseline RHR scores well; elevated RHR (a general sign of strain,
 * illness, or under-recovery) scores lower. Educational, non-diagnostic.
 */
export interface HeartInput {
  readonly restingHeartRate: number;
  readonly baselineRestingHeartRate?: number;
}

export function computeHeartScore(input: HeartInput): Score {
  const baseline = input.baselineRestingHeartRate;
  if (baseline === undefined || baseline <= 0) {
    // No baseline: map absolute RHR onto a broad healthy-adult band (40–90).
    const value = clamp(100 * (1 - (input.restingHeartRate - 40) / 50), 0, 100);
    return Score.of(value, [
      {
        factor: 'resting_heart_rate',
        value,
        weight: 1,
        explanation: `ชีพจรขณะพัก ${Math.round(input.restingHeartRate)} bpm.`,
      },
    ]);
  }

  const ratio = (input.restingHeartRate - baseline) / baseline; // +ve = elevated
  const value = clamp(70 - (ratio / 0.1) * 30, 0, 100);
  return Score.of(value, [
    {
      factor: 'resting_heart_rate',
      value,
      weight: 1,
      explanation: `ชีพจรขณะพัก ${Math.round(
        input.restingHeartRate,
      )} bpm เทียบค่าเฉลี่ย ${Math.round(baseline)} bpm.`,
    },
  ]);
}

/**
 * Stress score (0–100). Input is a 0–100 stress level (100 = most stressed); the
 * score simply inverts it so "more calm" reads as a higher, better score.
 */
export interface StressInput {
  readonly stress: number;
}

export function computeStressScore(input: StressInput): Score {
  const value = clamp(100 - input.stress, 0, 100);
  return Score.of(value, [
    {
      factor: 'stress',
      value,
      weight: 1,
      explanation: `ระดับความเครียด ${Math.round(input.stress)}/100 (ยิ่งต่ำยิ่งดี).`,
    },
  ]);
}
