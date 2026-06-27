import {
  ok,
  sampleKey,
  type Result,
  type UserId,
  type HealthSample,
  type HealthSampleRepository,
  type SaveSummary,
  type DateRange,
} from '@ghost/domain';

/**
 * An in-memory {@link HealthSampleRepository}. It is the reference
 * implementation: it defines the exact idempotency semantics every other store
 * (Supabase/PostgreSQL) must reproduce, and the shared contract test suite runs
 * against it. Also handy for local dev and use-case tests.
 */
export class InMemoryHealthSampleRepository implements HealthSampleRepository {
  private readonly store = new Map<string, HealthSample>();

  async save(
    samples: readonly HealthSample[],
  ): Promise<Result<SaveSummary>> {
    let inserted = 0;
    let updated = 0;

    for (const sample of samples) {
      const key = sampleKey(sample);
      if (this.store.has(key)) updated += 1;
      else inserted += 1;
      this.store.set(key, sample);
    }

    return ok({ inserted, updated });
  }

  async findByDateRange(
    userId: UserId,
    range: DateRange,
  ): Promise<Result<readonly HealthSample[]>> {
    const matches = [...this.store.values()]
      .filter(
        (s) =>
          s.userId === userId &&
          s.date >= range.start &&
          s.date <= range.end,
      )
      .sort((a, b) => a.date.localeCompare(b.date));

    return ok(matches);
  }

  /** Test/debug helper — total number of stored samples. */
  get size(): number {
    return this.store.size;
  }
}
