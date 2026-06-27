import type { HealthSample } from './samples.js';

/**
 * A stable, deterministic identity for a sample, used to make ingestion
 * idempotent: syncing the same day twice must not create duplicates.
 *
 * Preference order:
 *  1. The provider's own record id (`source.externalId`) when present — the most
 *     reliable signal that two payloads describe the same record.
 *  2. A natural key (user + date + provider + kind + a discriminator) otherwise,
 *     so providers that don't expose ids still dedupe sensibly.
 */
export function sampleKey(sample: HealthSample): string {
  const { userId, date, source, kind } = sample;

  if (source.externalId) {
    return `${userId}:${source.provider}:${source.externalId}`;
  }

  const discriminator = sampleDiscriminator(sample);
  return `${userId}:${source.provider}:${date}:${kind}:${discriminator}`;
}

/**
 * Distinguishes multiple same-kind samples on the same day from the same
 * provider (e.g. two workouts, several glucose readings) when no external id is
 * available. Daily-aggregate kinds (sleep, recovery) collapse to one per day.
 */
function sampleDiscriminator(sample: HealthSample): string {
  switch (sample.kind) {
    case 'sleep':
    case 'recovery':
      return 'daily';
    case 'workout':
      return `${sample.type}:${sample.source.recordedAt.toISOString()}`;
    case 'blood_sugar':
      return `${sample.context ?? 'random'}:${sample.source.recordedAt.toISOString()}`;
  }
}
