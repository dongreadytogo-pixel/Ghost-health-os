import { Score } from '../value-objects/score.js';
import { clamp } from '../shared/guard.js';

/**
 * Training-load model based on the acute:chronic workload ratio (ACWR), a
 * well-established way to balance fitness against injury/overtraining risk.
 *
 *   acute   = mean daily load over the last 7 days
 *   chronic = mean daily load over the last 28 days
 *   ACWR    = acute / chronic
 *
 * The "sweet spot" is roughly 0.8–1.3: enough stimulus to progress without
 * spiking risk. Below ~0.8 suggests detraining; above ~1.5 suggests elevated
 * overtraining risk. Load is unit-agnostic (sets×reps×weight, TRIMP, …).
 */
export type OvertrainingRisk = 'detraining' | 'optimal' | 'elevated' | 'high';

export interface TrainingLoadInput {
  /** Daily load values, oldest→newest, ending with today. Up to 28 entries. */
  readonly dailyLoads: readonly number[];
}

export interface TrainingLoadResult {
  readonly acute: number;
  readonly chronic: number;
  /** undefined when there is not enough chronic history to be meaningful. */
  readonly acwr: number | undefined;
  readonly risk: OvertrainingRisk;
  /** Workout-category score: peaks in the optimal band, falls off either side. */
  readonly score: Score;
}

export function computeTrainingLoad(
  input: TrainingLoadInput,
): TrainingLoadResult {
  const loads = input.dailyLoads.filter((l) => Number.isFinite(l) && l >= 0);
  const acute = mean(loads.slice(-7));
  const chronic = mean(loads.slice(-28));

  const acwr = chronic > 0 ? acute / chronic : undefined;
  const risk = riskFor(acwr);

  return { acute, chronic, acwr, risk, score: scoreFor(acwr) };
}

function riskFor(acwr: number | undefined): OvertrainingRisk {
  if (acwr === undefined) return 'optimal';
  if (acwr < 0.8) return 'detraining';
  if (acwr <= 1.3) return 'optimal';
  if (acwr <= 1.5) return 'elevated';
  return 'high';
}

function scoreFor(acwr: number | undefined): Score {
  // Without chronic history we cannot judge balance; stay neutral.
  if (acwr === undefined) {
    return Score.of(60, [
      {
        factor: 'training_balance',
        value: 60,
        weight: 1,
        explanation: 'ยังมีข้อมูลการฝึกไม่พอสำหรับประเมินสมดุลโหลด (ACWR).',
      },
    ]);
  }

  // Peak at the center of the optimal band (~1.05), decay outward.
  const distance = Math.abs(acwr - 1.05);
  const value = clamp(100 * (1 - distance / 0.6), 0, 100);
  return Score.of(value, [
    {
      factor: 'training_balance',
      value,
      weight: 1,
      explanation: `ACWR ${acwr.toFixed(2)} (โซนเหมาะสม 0.8–1.3). ${riskMessage(
        riskFor(acwr),
      )}`,
    },
  ]);
}

function riskMessage(risk: OvertrainingRisk): string {
  switch (risk) {
    case 'detraining':
      return 'โหลดต่ำ อาจถดถอย ลองเพิ่มความเข้มข้น.';
    case 'optimal':
      return 'สมดุลดี ฝึกต่อได้.';
    case 'elevated':
      return 'โหลดเริ่มสูง ระวังการพักฟื้น.';
    case 'high':
      return 'โหลดสูงมาก เสี่ยง overtraining ควรพัก.';
  }
}

/**
 * Training readiness (0–100): how prepared the body is to train hard today.
 * Combines recovery (dominant) with how much room is left before overload.
 */
export function computeReadiness(
  recoveryScore: Score,
  load: TrainingLoadResult,
): Score {
  const loadHeadroom =
    load.risk === 'high' ? 20 : load.risk === 'elevated' ? 55 : 90;
  return Score.weighted([
    {
      factor: 'recovery',
      value: recoveryScore.value,
      weight: 0.7,
      explanation: `การฟื้นตัว ${recoveryScore.value}/100.`,
    },
    {
      factor: 'load_headroom',
      value: loadHeadroom,
      weight: 0.3,
      explanation: `สถานะโหลดการฝึก: ${load.risk}.`,
    },
  ]);
}

function mean(xs: readonly number[]): number {
  return xs.length === 0 ? 0 : xs.reduce((a, b) => a + b, 0) / xs.length;
}
