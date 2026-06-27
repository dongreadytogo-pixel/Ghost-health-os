import {
  ok,
  toIsoDate,
  computeSleepScore,
  computeRecoveryScore,
  computeRecoveryBaseline,
  computeHeartScore,
  computeStressScore,
  computeTrainingLoad,
  computeReadiness,
  computeBloodSugarTrendScore,
  computeNutritionScore,
  computeHydrationScore,
  computeConsistencyScore,
  computeGhostScore,
  Score,
  type Result,
  type UserId,
  type IsoDate,
  type HealthSample,
  type SleepSample,
  type RecoveryInputs,
  type WorkoutSample,
  type BloodSugarSample,
  type HealthSampleRepository,
  type GhostCategory,
  type TrainingLoadResult,
  type NutritionInput,
  type HydrationInput,
} from '@ghost/domain';

/**
 * ComputeDailyScores — the M2 scoring pipeline. For a given user and day it:
 *
 *   1. reads a trailing window of samples from the repository,
 *   2. derives the user's personal recovery baseline,
 *   3. computes every category score the available data supports,
 *   4. composes them into the headline Ghost Score with a focus area.
 *
 * Categories with no data are simply absent — the Ghost Score re-weights over
 * whatever exists, so the result is meaningful from day one and only sharpens as
 * more sources come online. Nutrition and hydration, which aren't yet synced
 * from a wearable, can be supplied directly on the request.
 */
export interface ComputeDailyScoresRequest {
  readonly userId: UserId;
  readonly date: IsoDate;
  /** Trailing window for baselines, load, and trends (default 30 days). */
  readonly windowDays?: number;
  /** Optional manually-supplied inputs for categories not yet synced. */
  readonly nutrition?: NutritionInput;
  readonly hydration?: HydrationInput;
}

export interface DailyScores {
  readonly date: IsoDate;
  readonly ghostScore: number;
  readonly categories: Partial<Record<GhostCategory, Score>>;
  readonly focusArea: GhostCategory | undefined;
  /** Training-load detail (ACWR, risk, readiness) when workouts exist. */
  readonly training:
    | (TrainingLoadResult & { readonly readiness: Score })
    | undefined;
}

const dayMs = 24 * 60 * 60 * 1000;

export class ComputeDailyScores {
  constructor(private readonly repository: HealthSampleRepository) {}

  async execute(
    request: ComputeDailyScoresRequest,
  ): Promise<Result<DailyScores>> {
    const windowDays = request.windowDays ?? 30;
    const start = toIsoDate(
      new Date(Date.parse(request.date) - windowDays * dayMs),
    );

    const read = await this.repository.findByDateRange(request.userId, {
      start,
      end: request.date,
    });
    if (!read.ok) return read;

    const window = read.value;
    const today = window.filter((s) => s.date === request.date);

    const categories: Partial<Record<GhostCategory, Score>> = {};

    // --- Sleep -------------------------------------------------------------
    const sleep = firstOfKind<SleepSample>(today, 'sleep');
    if (sleep) categories.sleep = computeSleepScore(sleep);

    // --- Recovery / heart / stress (share the recovery sample + baseline) --
    const recovery = firstOfKind<RecoveryInputs>(today, 'recovery');
    const baseline = computeRecoveryBaseline(
      window.filter(isKind<RecoveryInputs>('recovery')),
      request.date,
      { windowDays },
    );
    if (recovery) {
      const enriched: RecoveryInputs =
        categories.sleep && recovery.sleepScore === undefined
          ? { ...recovery, sleepScore: categories.sleep.value }
          : recovery;
      categories.recovery = computeRecoveryScore(enriched, baseline);

      if (recovery.restingHeartRate !== undefined) {
        categories.heart = computeHeartScore({
          restingHeartRate: recovery.restingHeartRate,
          ...(baseline.restingHeartRate !== undefined
            ? { baselineRestingHeartRate: baseline.restingHeartRate }
            : {}),
        });
      }
      if (recovery.stress !== undefined) {
        categories.stress = computeStressScore({ stress: recovery.stress });
      }
    }

    // --- Workout / training load ------------------------------------------
    const workouts = window.filter(isKind<WorkoutSample>('workout'));
    let training: DailyScores['training'];
    if (workouts.length > 0) {
      const load = computeTrainingLoad({
        dailyLoads: dailyLoadSeries(workouts, request.date, windowDays),
      });
      categories.workout = load.score;
      const readiness = computeReadiness(
        categories.recovery ?? Score.of(60),
        load,
      );
      training = { ...load, readiness };
    }

    // --- Blood sugar (trend only, non-diagnostic) -------------------------
    const glucose = window
      .filter(isKind<BloodSugarSample>('blood_sugar'))
      .filter((s) => withinDays(s.date, request.date, 7))
      .map((s) => s.mgPerDl);
    if (glucose.length >= 2) {
      categories.blood_sugar = computeBloodSugarTrendScore({ readings: glucose });
    }

    // --- Nutrition / hydration (supplied on the request) ------------------
    if (request.nutrition) {
      categories.nutrition = computeNutritionScore(request.nutrition);
    }
    if (request.hydration) {
      categories.hydration = computeHydrationScore(request.hydration);
    }

    // --- Consistency -------------------------------------------------------
    categories.consistency = computeConsistencyScore(
      consistencyInput(window, request.date, windowDays),
    );

    // --- Compose -----------------------------------------------------------
    const ghost = computeGhostScore(
      (Object.entries(categories) as [GhostCategory, Score][]).map(
        ([category, score]) => ({ category, score }),
      ),
    );

    return ok({
      date: request.date,
      ghostScore: ghost.score.value,
      categories,
      focusArea: ghost.focusArea,
      training,
    });
  }
}

// --- helpers -------------------------------------------------------------

function isKind<T extends HealthSample>(kind: T['kind']) {
  return (s: HealthSample): s is T => s.kind === kind;
}

function firstOfKind<T extends HealthSample>(
  samples: readonly HealthSample[],
  kind: T['kind'],
): T | undefined {
  return samples.find(isKind<T>(kind));
}

function withinDays(date: IsoDate, asOf: IsoDate, days: number): boolean {
  const diff = Date.parse(asOf) - Date.parse(date);
  return diff >= 0 && diff <= days * dayMs;
}

/** A per-day total-load series ending on `asOf`, length `windowDays`. */
function dailyLoadSeries(
  workouts: readonly WorkoutSample[],
  asOf: IsoDate,
  windowDays: number,
): number[] {
  const byDay = new Map<string, number>();
  for (const w of workouts) {
    const load = w.volume ?? w.durationMinutes;
    byDay.set(w.date, (byDay.get(w.date) ?? 0) + load);
  }
  const series: number[] = [];
  const end = Date.parse(asOf);
  for (let i = windowDays - 1; i >= 0; i--) {
    const day = toIsoDate(new Date(end - i * dayMs));
    series.push(byDay.get(day) ?? 0);
  }
  return series;
}

function consistencyInput(
  window: readonly HealthSample[],
  asOf: IsoDate,
  windowDays: number,
) {
  const daysWithData = new Set(window.map((s) => s.date));
  const activeDays: boolean[] = [];
  const end = Date.parse(asOf);
  for (let i = windowDays - 1; i >= 0; i--) {
    activeDays.push(daysWithData.has(toIsoDate(new Date(end - i * dayMs))));
  }

  // Current streak: consecutive active days ending today.
  let currentStreak = 0;
  for (let i = activeDays.length - 1; i >= 0 && activeDays[i]; i--) {
    currentStreak += 1;
  }

  return { activeDays, currentStreak };
}
