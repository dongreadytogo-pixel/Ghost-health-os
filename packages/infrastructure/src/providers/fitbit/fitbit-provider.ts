import {
  fail,
  type Result,
  type UserId,
  type HealthSample,
  type HealthDataProvider,
  type ProviderCapabilities,
  type DateRangeQuery,
} from '@ghost/domain';
import type { HttpClient } from '../../http/http-client.js';
import { FITBIT_PROVIDER_ID, mapFitbitSleep } from './fitbit-mapper.js';

export interface FitbitProviderConfig {
  /** Ghost Health OS user this token belongs to. */
  readonly userId: UserId;
  /** OAuth2 bearer access token for the Fitbit Web API. */
  readonly accessToken: string;
  readonly http: HttpClient;
  /** Override for tests; defaults to the public Fitbit API host. */
  readonly baseUrl?: string;
}

const DEFAULT_BASE_URL = 'https://api.fitbit.com';

/**
 * Fitbit adapter implementing the domain's {@link HealthDataProvider} port.
 *
 * M1 covers sleep — the highest-value signal for Recovery and the Ghost Score.
 * Additional endpoints (HRV, resting HR, activity, glucose-capable scales) slot
 * in behind this same interface without changing any caller. Transport and auth
 * failures are returned as `DomainError` results; the adapter never throws
 * across the port.
 */
export class FitbitProvider implements HealthDataProvider {
  readonly id = FITBIT_PROVIDER_ID;
  readonly displayName = 'Fitbit';
  readonly capabilities: ProviderCapabilities = {
    sleep: true,
    recovery: false,
    workouts: false,
    bloodSugar: false,
  };

  private readonly baseUrl: string;

  constructor(private readonly config: FitbitProviderConfig) {
    this.baseUrl = (config.baseUrl ?? DEFAULT_BASE_URL).replace(/\/$/, '');
  }

  async fetch(
    query: DateRangeQuery,
  ): Promise<Result<readonly HealthSample[]>> {
    const url = `${this.baseUrl}/1.2/user/-/sleep/date/${query.start}/${query.end}.json`;

    let response;
    try {
      response = await this.config.http.get({
        url,
        headers: { Authorization: `Bearer ${this.config.accessToken}` },
      });
    } catch (cause) {
      return fail('FITBIT_TRANSPORT', 'Fitbit request failed', {
        message: cause instanceof Error ? cause.message : String(cause),
      });
    }

    if (response.status === 401) {
      return fail('FITBIT_AUTH', 'Fitbit access token is invalid or expired', {
        status: 401,
      });
    }
    if (response.status === 429) {
      return fail('FITBIT_RATE_LIMITED', 'Fitbit rate limit exceeded', {
        status: 429,
      });
    }
    if (response.status < 200 || response.status >= 300) {
      return fail('FITBIT_HTTP', `Unexpected Fitbit status ${response.status}`, {
        status: response.status,
      });
    }

    return mapFitbitSleep(response.body, this.config.userId);
  }
}

export { mapFitbitSleep, FITBIT_PROVIDER_ID };
