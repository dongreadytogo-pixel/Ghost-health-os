import { describe, it, expect } from 'vitest';
import type { UserId, IsoDate, SleepSample } from '@ghost/domain';
import type { HttpClient, HttpResponse } from '../../http/http-client.js';
import { FitbitProvider } from './fitbit-provider.js';
import { mapFitbitSleep } from './fitbit-mapper.js';

const USER = 'u1' as UserId;
const range = { start: '2026-06-26' as IsoDate, end: '2026-06-27' as IsoDate };

const SAMPLE_PAYLOAD = {
  sleep: [
    {
      logId: 987654,
      dateOfSleep: '2026-06-27',
      minutesAsleep: 421,
      timeInBed: 455,
      startTime: '2026-06-26T23:12:00.000',
      levels: {
        summary: {
          deep: { minutes: 72 },
          light: { minutes: 219 },
          rem: { minutes: 100 },
          wake: { minutes: 34 },
        },
      },
    },
  ],
};

const stubHttp = (response: HttpResponse): HttpClient => ({
  get: async () => response,
});

describe('mapFitbitSleep', () => {
  it('maps a Fitbit sleep log into a canonical SleepSample', () => {
    const result = mapFitbitSleep(SAMPLE_PAYLOAD, USER);
    expect(result.ok).toBe(true);
    if (!result.ok) return;

    const [sample] = result.value as SleepSample[];
    expect(sample).toMatchObject({
      userId: USER,
      date: '2026-06-27',
      kind: 'sleep',
      asleepMinutes: 421,
      timeInBedMinutes: 455,
      stages: { deep: 72, light: 219, rem: 100, awake: 34 },
    });
    expect(sample?.source.externalId).toBe('987654');
    expect(sample?.source.provider).toBe('fitbit');
  });

  it('rejects a malformed payload as a DomainError', () => {
    const result = mapFitbitSleep({ not: 'sleep' }, USER);
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error.code).toBe('FITBIT_BAD_PAYLOAD');
  });

  it('skips entries with missing or invalid dates and fills missing stages', () => {
    const result = mapFitbitSleep(
      {
        sleep: [
          { logId: 1, dateOfSleep: 'not-a-date', minutesAsleep: 100 },
          { logId: 2, dateOfSleep: '2026-06-27', minutesAsleep: 300, timeInBed: 320 },
        ],
      },
      USER,
    );
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.value).toHaveLength(1);
    expect((result.value[0] as SleepSample).stages).toEqual({
      awake: 0,
      light: 0,
      deep: 0,
      rem: 0,
    });
  });
});

describe('FitbitProvider', () => {
  it('declares its capabilities and id', () => {
    const provider = new FitbitProvider({
      userId: USER,
      accessToken: 't',
      http: stubHttp({ status: 200, body: SAMPLE_PAYLOAD }),
    });
    expect(provider.id).toBe('fitbit');
    expect(provider.capabilities.sleep).toBe(true);
  });

  it('fetches and maps a successful response', async () => {
    const provider = new FitbitProvider({
      userId: USER,
      accessToken: 't',
      http: stubHttp({ status: 200, body: SAMPLE_PAYLOAD }),
    });
    const result = await provider.fetch(range);
    expect(result.ok).toBe(true);
    if (result.ok) expect(result.value).toHaveLength(1);
  });

  it('maps a 401 to a FITBIT_AUTH error', async () => {
    const provider = new FitbitProvider({
      userId: USER,
      accessToken: 'expired',
      http: stubHttp({ status: 401, body: { errors: [] } }),
    });
    const result = await provider.fetch(range);
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error.code).toBe('FITBIT_AUTH');
  });

  it('maps a 429 to a FITBIT_RATE_LIMITED error', async () => {
    const provider = new FitbitProvider({
      userId: USER,
      accessToken: 't',
      http: stubHttp({ status: 429, body: {} }),
    });
    const result = await provider.fetch(range);
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error.code).toBe('FITBIT_RATE_LIMITED');
  });

  it('surfaces transport exceptions as FITBIT_TRANSPORT', async () => {
    const provider = new FitbitProvider({
      userId: USER,
      accessToken: 't',
      http: {
        get: async () => {
          throw new Error('socket hang up');
        },
      },
    });
    const result = await provider.fetch(range);
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error.code).toBe('FITBIT_TRANSPORT');
  });
});
