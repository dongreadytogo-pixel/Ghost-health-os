import { Score, type ScoreContribution } from '../value-objects/score.js';
import { clamp } from '../shared/guard.js';

/**
 * Blood-sugar *trend* score (0–100).
 *
 * ⚠️ Non-diagnostic by design. This NEVER classifies readings as high/low or
 * implies a medical condition. It only rewards *stability* — lower day-to-day
 * variability — because steadier trends are a general wellness signal the user
 * can act on through sleep, walking, hydration, and meal timing. All language is
 * educational. Diagnosis belongs to a qualified clinician.
 */
export interface BloodSugarTrendInput {
  /** Recent glucose readings (mg/dL), oldest→newest. Stored as trends only. */
  readonly readings: readonly number[];
}

export function computeBloodSugarTrendScore(
  input: BloodSugarTrendInput,
): Score {
  const readings = input.readings.filter((r) => Number.isFinite(r) && r > 0);
  if (readings.length < 2) {
    return Score.of(50, [
      {
        factor: 'data',
        value: 50,
        weight: 1,
        explanation: 'ข้อมูลน้ำตาลยังไม่พอสำหรับวิเคราะห์แนวโน้ม (ต้องการอย่างน้อย 2 ค่า).',
      },
    ]);
  }

  const avg = mean(readings);
  const sd = stdDev(readings, avg);
  // Coefficient of variation: lower = steadier. CV ≤ ~10% is very stable.
  const cv = avg > 0 ? sd / avg : 1;
  const stabilityValue = clamp(100 * (1 - cv / 0.2), 0, 100);

  const contributions: ScoreContribution[] = [
    {
      factor: 'stability',
      value: stabilityValue,
      weight: 1,
      explanation: `ความแปรปรวนของน้ำตาลช่วงนี้ ~${(cv * 100).toFixed(
        0,
      )}% (ยิ่งคงที่ยิ่งดี). ข้อมูลเชิงแนวโน้มเท่านั้น ไม่ใช่การวินิจฉัย.`,
    },
  ];

  return Score.weighted(contributions);
}

function mean(xs: readonly number[]): number {
  return xs.reduce((a, b) => a + b, 0) / xs.length;
}

function stdDev(xs: readonly number[], avg: number): number {
  const variance = xs.reduce((sum, x) => sum + (x - avg) ** 2, 0) / xs.length;
  return Math.sqrt(variance);
}
