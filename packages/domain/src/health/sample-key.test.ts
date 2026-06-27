import { describe, it, expect } from 'vitest';
import { sampleKey } from './sample-key.js';
import type {
  SleepSample,
  WorkoutSample,
  BloodSugarSample,
} from './samples.js';
import type { UserId, IsoDate, ProviderId } from '../shared/branded.js';

const base = {
  userId: 'u1' as UserId,
  date: '2026-06-27' as IsoDate,
};

const src = (externalId?: string) => ({
  provider: 'fitbit' as ProviderId,
  recordedAt: new Date('2026-06-27T07:00:00Z'),
  ...(externalId ? { externalId } : {}),
});

describe('sampleKey', () => {
  it('prefers the provider external id when present', () => {
    const a: SleepSample = {
      ...base,
      kind: 'sleep',
      source: src('sleep-123'),
      asleepMinutes: 400,
      timeInBedMinutes: 420,
      stages: { awake: 20, light: 200, deep: 80, rem: 100 },
    };
    expect(sampleKey(a)).toBe('u1:fitbit:sleep-123');
  });

  it('collapses daily-aggregate kinds to one key per day without an id', () => {
    const sleep: SleepSample = {
      ...base,
      kind: 'sleep',
      source: src(),
      asleepMinutes: 400,
      timeInBedMinutes: 420,
      stages: { awake: 20, light: 200, deep: 80, rem: 100 },
    };
    expect(sampleKey(sleep)).toBe('u1:fitbit:2026-06-27:sleep:daily');
  });

  it('distinguishes multiple same-day workouts by type and time', () => {
    const push: WorkoutSample = {
      ...base,
      kind: 'workout',
      source: src(),
      type: 'push',
      durationMinutes: 50,
    };
    const legs: WorkoutSample = { ...push, type: 'legs' };
    expect(sampleKey(push)).not.toBe(sampleKey(legs));
  });

  it('distinguishes glucose readings by context and time', () => {
    const fasting: BloodSugarSample = {
      ...base,
      kind: 'blood_sugar',
      source: src(),
      mgPerDl: 95,
      context: 'fasting',
    };
    const postMeal: BloodSugarSample = { ...fasting, context: 'post_meal' };
    expect(sampleKey(fasting)).not.toBe(sampleKey(postMeal));
  });
});
