import type { IsoDate, UserId } from '../shared/branded.js';
import type { Result } from '../shared/result.js';
import type { HealthSample } from '../health/samples.js';

/**
 * Persistence port for normalized health samples. The domain owns the
 * *interface*; concrete stores (in-memory, Supabase/PostgreSQL, …) live in the
 * infrastructure layer and are injected into use-cases.
 *
 * Implementations MUST be idempotent on {@link sampleKey}: saving the same
 * sample twice updates in place rather than duplicating. This is what makes
 * re-syncing a date range safe.
 */
export interface SaveSummary {
  readonly inserted: number;
  readonly updated: number;
}

export interface DateRange {
  readonly start: IsoDate;
  readonly end: IsoDate;
}

export interface HealthSampleRepository {
  /** Idempotent bulk upsert keyed on the domain's `sampleKey`. */
  save(samples: readonly HealthSample[]): Promise<Result<SaveSummary>>;

  /** Read back samples for a user within an inclusive date range. */
  findByDateRange(
    userId: UserId,
    range: DateRange,
  ): Promise<Result<readonly HealthSample[]>>;
}
