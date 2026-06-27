import { Score, type ScoreContribution } from '../value-objects/score.js';
import { clamp } from '../shared/guard.js';
import type { SleepSample } from '../health/samples.js';

/**
 * Sleep score (0–100) from a single night.
 *
 * Composed from four evidence-based factors, each scored independently then
 * combined by weight. All thresholds reflect general adult sleep guidance and
 * are intentionally conservative — this is educational, not diagnostic.
 */

const TARGET_ASLEEP_MINUTES = 8 * 60; // 480
const MIN_HEALTHY_ASLEEP_MINUTES = 7 * 60; // 420

/** Score a value that has an ideal target, decaying linearly on either side. */
const scoreAroundTarget = (
  value: number,
  target: number,
  tolerance: number,
): number => {
  const deviation = Math.abs(value - target);
  return clamp(100 * (1 - deviation / tolerance), 0, 100);
};

export function computeSleepScore(sample: SleepSample): Score {
  const { asleepMinutes, timeInBedMinutes, stages } = sample;

  // 1. Duration — capped at target so oversleeping is not "rewarded" past 100,
  //    and decaying *quadratically* below the healthy minimum so that a badly
  //    short night (e.g. 4h) is penalized hard even with good architecture.
  const durationRatio = clamp(
    Math.min(asleepMinutes, TARGET_ASLEEP_MINUTES) / MIN_HEALTHY_ASLEEP_MINUTES,
    0,
    1,
  );
  const durationValue = durationRatio * durationRatio * 100;

  // 2. Efficiency — share of time in bed actually spent asleep (target ~92%).
  const efficiency =
    timeInBedMinutes > 0 ? (asleepMinutes / timeInBedMinutes) * 100 : 0;
  const efficiencyValue = clamp((efficiency / 92) * 100, 0, 100);

  // 3. Deep sleep — target ~15% of sleep.
  const deepShare = asleepMinutes > 0 ? stages.deep / asleepMinutes : 0;
  const deepValue = scoreAroundTarget(deepShare * 100, 15, 15);

  // 4. REM sleep — target ~22% of sleep.
  const remShare = asleepMinutes > 0 ? stages.rem / asleepMinutes : 0;
  const remValue = scoreAroundTarget(remShare * 100, 22, 22);

  const hours = (asleepMinutes / 60).toFixed(1);
  const contributions: ScoreContribution[] = [
    {
      factor: 'duration',
      value: durationValue,
      weight: 0.4,
      explanation: `คุณนอนหลับ ${hours} ชั่วโมง (เป้าหมาย 7–8 ชั่วโมง).`,
    },
    {
      factor: 'efficiency',
      value: efficiencyValue,
      weight: 0.3,
      explanation: `ประสิทธิภาพการนอน ${efficiency.toFixed(
        0,
      )}% ของเวลาบนเตียง (เป้าหมาย ~92%).`,
    },
    {
      factor: 'deep_sleep',
      value: deepValue,
      weight: 0.15,
      explanation: `หลับลึก ${(deepShare * 100).toFixed(
        0,
      )}% ของการนอน (เป้าหมาย ~15%).`,
    },
    {
      factor: 'rem_sleep',
      value: remValue,
      weight: 0.15,
      explanation: `REM ${(remShare * 100).toFixed(
        0,
      )}% ของการนอน (เป้าหมาย ~22%).`,
    },
  ];

  return Score.weighted(contributions);
}
