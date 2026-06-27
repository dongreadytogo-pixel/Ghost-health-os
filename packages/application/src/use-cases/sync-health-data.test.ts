import { describe, it, expect } from 'vitest';
import {
  ok,
  fail,
  type Result,
  type UserId,
  type IsoDate,
  type ProviderId,
  type HealthSample,
  type SleepSample,
  type HealthDataProvider,
  type HealthSampleRepository,
  type SaveSummary,
} from '@ghost/domain';
import { SyncHealthData } from './sync-health-data.js';

const USER = 'u1' as UserId;
const range = { start: '2026-06-01' as IsoDate, end: '2026-06-07' as IsoDate };

const sleepFor = (userId: UserId): SleepSample => ({
  userId,
  date: '2026-06-01' as IsoDate,
  kind: 'sleep',
  source: {
    provider: 'fitbit' as ProviderId,
    externalId: 's-1',
    recordedAt: new Date('2026-06-01T07:00:00Z'),
  },
  asleepMinutes: 420,
  timeInBedMinutes: 450,
  stages: { awake: 30, light: 220, deep: 70, rem: 100 },
});

/** A provider that returns a fixed payload (or an error). */
const stubProvider = (
  payload: Result<readonly HealthSample[]>,
): HealthDataProvider => ({
  id: 'fitbit' as ProviderId,
  displayName: 'Stub',
  capabilities: { sleep: true, recovery: false, workouts: false, bloodSugar: false },
  fetch: async () => payload,
});

/** A repository spy that records what it was asked to save. */
const spyRepository = (
  saveResult: Result<SaveSummary> = ok({ inserted: 0, updated: 0 }),
) => {
  const saved: HealthSample[][] = [];
  const repo: HealthSampleRepository = {
    save: async (samples) => {
      saved.push([...samples]);
      return saveResult;
    },
    findByDateRange: async () => ok([]),
  };
  return { repo, saved };
};

describe('SyncHealthData', () => {
  it('fetches from the provider and persists the result', async () => {
    const { repo, saved } = spyRepository(ok({ inserted: 1, updated: 0 }));
    const useCase = new SyncHealthData(
      stubProvider(ok([sleepFor(USER)])),
      repo,
    );

    const result = await useCase.execute({ userId: USER, range });

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.value).toEqual({ fetched: 1, inserted: 1, updated: 0 });
    }
    expect(saved[0]).toHaveLength(1);
  });

  it('short-circuits and returns the error when the provider fails', async () => {
    const { repo, saved } = spyRepository();
    const useCase = new SyncHealthData(
      stubProvider(fail('FITBIT_AUTH', 'token expired')),
      repo,
    );

    const result = await useCase.execute({ userId: USER, range });

    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error.code).toBe('FITBIT_AUTH');
    expect(saved).toHaveLength(0); // never attempted to save
  });

  it('drops samples that belong to a different user', async () => {
    const other = 'intruder' as UserId;
    const { repo, saved } = spyRepository(ok({ inserted: 1, updated: 0 }));
    const useCase = new SyncHealthData(
      stubProvider(ok([sleepFor(USER), sleepFor(other)])),
      repo,
    );

    const result = await useCase.execute({ userId: USER, range });

    expect(result.ok).toBe(true);
    if (result.ok) expect(result.value.fetched).toBe(1);
    expect(saved[0]?.every((s) => s.userId === USER)).toBe(true);
  });

  it('propagates a repository failure', async () => {
    const { repo } = spyRepository(fail('DB_WRITE', 'connection lost'));
    const useCase = new SyncHealthData(
      stubProvider(ok([sleepFor(USER)])),
      repo,
    );

    const result = await useCase.execute({ userId: USER, range });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error.code).toBe('DB_WRITE');
  });
});
