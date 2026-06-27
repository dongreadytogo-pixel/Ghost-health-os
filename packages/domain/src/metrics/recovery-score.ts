import { Score, type ScoreContribution } from '../value-objects/score.js';
import { clamp } from '../shared/guard.js';
import type { RecoveryInputs } from '../health/samples.js';

/**
 * Recovery / readiness score (0–100).
 *
 * Recovery is inherently relative to *your own* baseline — an HRV of 60ms is
 * great for one person and mediocre for another — so the calculator accepts a
 * personal baseline. Factors with no data are omitted and the score re-weights
 * across whatever signal is available (see {@link Score.weighted}).
 */

export interface RecoveryBaseline {
  /** Personal mean HRV (RMSSD, ms) over a trailing window, e.g. 30 days. */
  readonly hrvMs?: number;
  /** Personal mean resting heart rate (bpm). */
  readonly restingHeartRate?: number;
}

/** Map a deviation-from-baseline ratio into 0–100, centered at baseline = 70. */
const scoreDeviation = (
  current: number,
  baseline: number,
  higherIsBetter: boolean,
  sensitivity: number,
): number => {
  if (baseline <= 0) return 50;
  const ratio = (current - baseline) / baseline; // e.g. +0.1 = 10% above
  const directed = higherIsBetter ? ratio : -ratio;
  return clamp(70 + (directed / sensitivity) * 30, 0, 100);
};

export function computeRecoveryScore(
  inputs: RecoveryInputs,
  baseline: RecoveryBaseline = {},
): Score {
  const contributions: ScoreContribution[] = [];

  if (inputs.hrvMs !== undefined && baseline.hrvMs !== undefined) {
    contributions.push({
      factor: 'hrv',
      value: scoreDeviation(inputs.hrvMs, baseline.hrvMs, true, 0.2),
      weight: 0.4,
      explanation: `HRV ${inputs.hrvMs.toFixed(0)}ms เทียบกับค่าเฉลี่ยส่วนตัว ${baseline.hrvMs.toFixed(
        0,
      )}ms.`,
    });
  }

  if (
    inputs.restingHeartRate !== undefined &&
    baseline.restingHeartRate !== undefined
  ) {
    contributions.push({
      factor: 'resting_heart_rate',
      value: scoreDeviation(
        inputs.restingHeartRate,
        baseline.restingHeartRate,
        false,
        0.1,
      ),
      weight: 0.3,
      explanation: `ชีพจรขณะพัก ${inputs.restingHeartRate.toFixed(
        0,
      )} bpm เทียบกับค่าเฉลี่ย ${baseline.restingHeartRate.toFixed(0)} bpm.`,
    });
  }

  if (inputs.sleepScore !== undefined) {
    contributions.push({
      factor: 'sleep',
      value: clamp(inputs.sleepScore, 0, 100),
      weight: 0.2,
      explanation: `คะแนนการนอนเมื่อคืน ${Math.round(inputs.sleepScore)}/100.`,
    });
  }

  if (inputs.stress !== undefined) {
    contributions.push({
      factor: 'stress',
      value: clamp(100 - inputs.stress, 0, 100),
      weight: 0.1,
      explanation: `ระดับความเครียด ${Math.round(inputs.stress)}/100 (ยิ่งต่ำยิ่งดี).`,
    });
  }

  return Score.weighted(contributions);
}
