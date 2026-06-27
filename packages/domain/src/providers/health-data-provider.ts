import type { IsoDate, ProviderId } from '../shared/branded.js';
import type { Result } from '../shared/result.js';
import type { HealthSample } from '../health/samples.js';

/**
 * The seam that keeps the architecture open to new data sources without ever
 * redesigning it. Fitbit, Apple Health, Garmin, WHOOP, Oura, a CGM, or manual
 * input each ship an adapter implementing this port; the application layer
 * depends only on this interface, never on a concrete vendor SDK.
 */

export interface DateRangeQuery {
  readonly start: IsoDate;
  readonly end: IsoDate;
}

/** What a given provider is actually capable of supplying. */
export interface ProviderCapabilities {
  readonly sleep: boolean;
  readonly recovery: boolean;
  readonly workouts: boolean;
  readonly bloodSugar: boolean;
}

export interface HealthDataProvider {
  readonly id: ProviderId;
  readonly displayName: string;
  readonly capabilities: ProviderCapabilities;

  /**
   * Fetch and normalize all available samples in the range. Implementations are
   * responsible for mapping vendor payloads into canonical {@link HealthSample}s
   * and for surfacing transport/auth failures as a `DomainError` result rather
   * than throwing.
   */
  fetch(query: DateRangeQuery): Promise<Result<readonly HealthSample[]>>;
}
