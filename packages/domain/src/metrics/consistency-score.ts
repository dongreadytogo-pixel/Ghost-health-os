import { Score } from '../value-objects/score.js';
import { clamp } from '../shared/guard.js';

/**
 * Consistency score (0–100). Habits compound, so the system rewards showing up:
 * how many of the last N days had logged activity, plus the current streak.
 * Frequency dominates; the streak is a motivational bonus.
 */
export interface ConsistencyInput {
  /** Booleans for the last N days, oldest→newest: did the user log/train? */
  readonly activeDays: readonly boolean[];
  /** Current consecutive-day streak ending today. */
  readonly currentStreak: number;
  /** Streak length considered "fully established" (default 14). */
  readonly streakTarget?: number;
}

export function computeConsistencyScore(input: ConsistencyInput): Score {
  const target = input.streakTarget ?? 14;
  const total = input.activeDays.length;
  const active = input.activeDays.filter(Boolean).length;

  const frequencyValue = total > 0 ? (active / total) * 100 : 0;
  const streakValue = clamp((input.currentStreak / target) * 100, 0, 100);

  return Score.weighted([
    {
      factor: 'frequency',
      value: frequencyValue,
      weight: 0.7,
      explanation: `ทำกิจกรรม ${active}/${total} วันล่าสุด.`,
    },
    {
      factor: 'streak',
      value: streakValue,
      weight: 0.3,
      explanation: `สตรีคปัจจุบัน ${input.currentStreak} วัน (เป้าหมาย ${target}).`,
    },
  ]);
}
