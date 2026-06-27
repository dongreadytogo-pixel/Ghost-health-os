import {
  ok,
  type Result,
  type UserId,
  type HealthDataProvider,
  type DateRangeQuery,
  type HealthSampleRepository,
} from '@ghost/domain';

/**
 * SyncHealthData — the M1 ingestion pipeline as a single, transport-agnostic
 * use-case:
 *
 *   provider.fetch(range)  →  normalized samples  →  repository.save (idempotent)
 *
 * It depends only on domain ports, so the same use-case drives a Fitbit sync, an
 * Apple Health sync, or a test with in-memory fakes. Any failure from either
 * port short-circuits and is returned as a `Result` error — nothing throws.
 */
export interface SyncHealthDataRequest {
  readonly userId: UserId;
  readonly range: DateRangeQuery;
}

export interface SyncHealthDataResult {
  readonly fetched: number;
  readonly inserted: number;
  readonly updated: number;
}

export class SyncHealthData {
  constructor(
    private readonly provider: HealthDataProvider,
    private readonly repository: HealthSampleRepository,
  ) {}

  async execute(
    request: SyncHealthDataRequest,
  ): Promise<Result<SyncHealthDataResult>> {
    const fetched = await this.provider.fetch(request.range);
    if (!fetched.ok) return fetched;

    // Guard against an adapter handing back another user's data.
    const samples = fetched.value.filter(
      (s) => s.userId === request.userId,
    );

    const saved = await this.repository.save(samples);
    if (!saved.ok) return saved;

    return ok({
      fetched: samples.length,
      inserted: saved.value.inserted,
      updated: saved.value.updated,
    });
  }
}
