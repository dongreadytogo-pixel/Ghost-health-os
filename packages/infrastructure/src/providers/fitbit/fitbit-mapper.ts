import {
  ok,
  fail,
  isIsoDate,
  type Result,
  type UserId,
  type IsoDate,
  type ProviderId,
  type SleepSample,
} from '@ghost/domain';

export const FITBIT_PROVIDER_ID = 'fitbit' as ProviderId;

/**
 * Maps Fitbit's sleep-log payload into canonical {@link SleepSample}s. This is a
 * pure function — no I/O — so the vendor-specific quirks live in one tested
 * place and never leak past the adapter boundary.
 *
 * Shape (Fitbit "Get Sleep Log by Date Range"):
 *   { sleep: [ { logId, dateOfSleep, minutesAsleep, timeInBed,
 *                levels: { summary: { deep/light/rem/wake: { minutes } } },
 *                startTime } ] }
 *
 * Unknown/optional fields default safely; a malformed top-level shape is a
 * `DomainError` rather than a throw.
 */
export function mapFitbitSleep(
  payload: unknown,
  userId: UserId,
): Result<readonly SleepSample[]> {
  if (!isRecord(payload) || !Array.isArray(payload['sleep'])) {
    return fail('FITBIT_BAD_PAYLOAD', 'Expected a { sleep: [...] } object', {
      received: typeof payload,
    });
  }

  const samples: SleepSample[] = [];

  for (const raw of payload['sleep']) {
    if (!isRecord(raw)) continue;

    const date = raw['dateOfSleep'];
    if (typeof date !== 'string' || !isIsoDate(date)) continue;

    const summary = getSummary(raw);
    const recordedAt = parseDate(raw['startTime']) ?? new Date(`${date}T00:00:00Z`);

    samples.push({
      userId,
      date: date as IsoDate,
      kind: 'sleep',
      source: {
        provider: FITBIT_PROVIDER_ID,
        recordedAt,
        ...(raw['logId'] !== undefined
          ? { externalId: String(raw['logId']) }
          : {}),
      },
      asleepMinutes: numberOr(raw['minutesAsleep'], 0),
      timeInBedMinutes: numberOr(raw['timeInBed'], 0),
      stages: {
        awake: summary.wake,
        light: summary.light,
        deep: summary.deep,
        rem: summary.rem,
      },
    });
  }

  return ok(samples);
}

interface StageSummary {
  deep: number;
  light: number;
  rem: number;
  wake: number;
}

function getSummary(raw: Record<string, unknown>): StageSummary {
  const levels = isRecord(raw['levels']) ? raw['levels'] : {};
  const summary = isRecord(levels['summary']) ? levels['summary'] : {};
  const minutes = (key: string): number => {
    const stage = summary[key];
    return isRecord(stage) ? numberOr(stage['minutes'], 0) : 0;
  };
  return {
    deep: minutes('deep'),
    light: minutes('light'),
    rem: minutes('rem'),
    wake: minutes('wake'),
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function numberOr(value: unknown, fallback: number): number {
  return typeof value === 'number' && Number.isFinite(value) ? value : fallback;
}

function parseDate(value: unknown): Date | undefined {
  if (typeof value !== 'string') return undefined;
  const ms = Date.parse(value);
  return Number.isNaN(ms) ? undefined : new Date(ms);
}
