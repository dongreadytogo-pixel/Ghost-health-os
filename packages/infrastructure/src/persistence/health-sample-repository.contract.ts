import { describe, it, expect, beforeEach } from 'vitest';
import {
  type UserId,
  type IsoDate,
  type ProviderId,
  type SleepSample,
  type HealthSampleRepository,
} from '@ghost/domain';

/**
 * A reusable contract every {@link HealthSampleRepository} implementation must
 * satisfy. Run it against each concrete store (in-memory today, Supabase later)
 * to guarantee they are truly interchangeable — the whole point of the port.
 *
 * @param name  label for the test block
 * @param makeRepository  fresh, empty repository per test
 */
export function testHealthSampleRepositoryContract(
  name: string,
  makeRepository: () => HealthSampleRepository,
): void {
  describe(`HealthSampleRepository contract: ${name}`, () => {
    let repo: HealthSampleRepository;
    const user = 'u1' as UserId;

    const sleep = (
      date: string,
      externalId: string,
      asleepMinutes = 420,
    ): SleepSample => ({
      userId: user,
      date: date as IsoDate,
      kind: 'sleep',
      source: {
        provider: 'fitbit' as ProviderId,
        externalId,
        recordedAt: new Date(`${date}T07:00:00Z`),
      },
      asleepMinutes,
      timeInBedMinutes: 450,
      stages: { awake: 30, light: 220, deep: 70, rem: 100 },
    });

    beforeEach(() => {
      repo = makeRepository();
    });

    it('inserts new samples and reports them as inserted', async () => {
      const result = await repo.save([sleep('2026-06-01', 'a')]);
      expect(result.ok).toBe(true);
      if (result.ok) expect(result.value).toEqual({ inserted: 1, updated: 0 });
    });

    it('is idempotent: re-saving the same key updates, never duplicates', async () => {
      await repo.save([sleep('2026-06-01', 'a', 400)]);
      const second = await repo.save([sleep('2026-06-01', 'a', 480)]);

      expect(second.ok).toBe(true);
      if (second.ok) expect(second.value).toEqual({ inserted: 0, updated: 1 });

      const read = await repo.findByDateRange(user, {
        start: '2026-06-01' as IsoDate,
        end: '2026-06-01' as IsoDate,
      });
      expect(read.ok).toBe(true);
      if (read.ok) {
        expect(read.value).toHaveLength(1);
        expect((read.value[0] as SleepSample).asleepMinutes).toBe(480); // updated
      }
    });

    it('filters reads by inclusive date range', async () => {
      await repo.save([
        sleep('2026-06-01', 'a'),
        sleep('2026-06-03', 'b'),
        sleep('2026-06-10', 'c'),
      ]);

      const read = await repo.findByDateRange(user, {
        start: '2026-06-01' as IsoDate,
        end: '2026-06-05' as IsoDate,
      });

      expect(read.ok).toBe(true);
      if (read.ok) expect(read.value.map((s) => s.date)).toEqual([
        '2026-06-01',
        '2026-06-03',
      ]);
    });

    it('isolates data between users', async () => {
      const other = 'u2' as UserId;
      await repo.save([{ ...sleep('2026-06-01', 'a'), userId: other }]);

      const read = await repo.findByDateRange(user, {
        start: '2026-06-01' as IsoDate,
        end: '2026-06-30' as IsoDate,
      });
      expect(read.ok).toBe(true);
      if (read.ok) expect(read.value).toHaveLength(0);
    });
  });
}
