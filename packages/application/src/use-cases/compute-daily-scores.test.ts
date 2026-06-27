import { describe, it, expect } from 'vitest';
import {
  ok,
  type Result,
  type UserId,
  type IsoDate,
  type ProviderId,
  type HealthSample,
  type SleepSample,
  type RecoveryInputs,
  type WorkoutSample,
  type HealthSampleRepository,
  type DateRange,
} from '@ghost/domain';
import { ComputeDailyScores } from './compute-daily-scores.js';

const USER = 'u1' as UserId;
const provider = 'fitbit' as ProviderId;
const src = (date: string) => ({ provider, recordedAt: new Date(`${date}T07:00:00Z`) });

/** Minimal in-memory repo for the use-case under test. */
class FakeRepo implements HealthSampleRepository {
  constructor(private readonly samples: HealthSample[]) {}
  async save(): Promise<Result<{ inserted: number; updated: number }>> {
    return ok({ inserted: 0, updated: 0 });
  }
  async findByDateRange(
    userId: UserId,
    range: DateRange,
  ): Promise<Result<readonly HealthSample[]>> {
    return ok(
      this.samples.filter(
        (s) => s.userId === userId && s.date >= range.start && s.date <= range.end,
      ),
    );
  }
}

const sleep = (date: string, asleep = 440): SleepSample => ({
  userId: USER,
  date: date as IsoDate,
  kind: 'sleep',
  source: src(date),
  asleepMinutes: asleep,
  timeInBedMinutes: asleep + 30,
  stages: { awake: 30, light: asleep - 170, deep: 70, rem: 100 },
});

const recovery = (date: string, hrv = 62, rhr = 58): RecoveryInputs => ({
  userId: USER,
  date: date as IsoDate,
  kind: 'recovery',
  source: src(date),
  hrvMs: hrv,
  restingHeartRate: rhr,
});

const workout = (date: string, volume: number): WorkoutSample => ({
  userId: USER,
  date: date as IsoDate,
  kind: 'workout',
  source: src(date),
  type: 'push',
  durationMinutes: 50,
  volume,
});

describe('ComputeDailyScores', () => {
  it('composes a Ghost Score from the categories the data supports', async () => {
    const repo = new FakeRepo([
      sleep('2026-06-27'),
      recovery('2026-06-27'),
      // history to establish a recovery baseline
      recovery('2026-06-24'),
      recovery('2026-06-25'),
      recovery('2026-06-26'),
    ]);
    const useCase = new ComputeDailyScores(repo);

    const result = await useCase.execute({
      userId: USER,
      date: '2026-06-27' as IsoDate,
    });

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.value.ghostScore).toBeGreaterThan(0);
    expect(result.value.categories.sleep).toBeDefined();
    expect(result.value.categories.recovery).toBeDefined();
    expect(result.value.categories.heart).toBeDefined();
    expect(result.value.categories.consistency).toBeDefined();
  });

  it('includes training load and readiness when workouts exist', async () => {
    const days = Array.from({ length: 28 }, (_, i) => {
      const d = new Date(Date.parse('2026-06-27') - (27 - i) * 86400000)
        .toISOString()
        .slice(0, 10);
      return workout(d, 100);
    });
    const repo = new FakeRepo([...days, recovery('2026-06-27')]);
    const useCase = new ComputeDailyScores(repo);

    const result = await useCase.execute({
      userId: USER,
      date: '2026-06-27' as IsoDate,
    });

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.value.training).toBeDefined();
    expect(result.value.training?.risk).toBe('optimal');
    expect(result.value.categories.workout).toBeDefined();
  });

  it('folds in supplied nutrition and hydration', async () => {
    const repo = new FakeRepo([sleep('2026-06-27')]);
    const useCase = new ComputeDailyScores(repo);

    const result = await useCase.execute({
      userId: USER,
      date: '2026-06-27' as IsoDate,
      nutrition: { proteinG: 160, proteinTargetG: 160 },
      hydration: { waterMl: 3000, targetMl: 3000 },
    });

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.value.categories.nutrition?.value).toBe(100);
    expect(result.value.categories.hydration?.value).toBe(100);
  });

  it('still produces a score with only one data source', async () => {
    const repo = new FakeRepo([sleep('2026-06-27', 460)]);
    const result = await new ComputeDailyScores(repo).execute({
      userId: USER,
      date: '2026-06-27' as IsoDate,
    });
    expect(result.ok).toBe(true);
    if (result.ok) expect(result.value.categories.sleep).toBeDefined();
  });
});
