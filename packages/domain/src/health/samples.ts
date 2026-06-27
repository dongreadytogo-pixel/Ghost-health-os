import type { IsoDate, UserId, ProviderId } from '../shared/branded.js';

/**
 * Canonical, provider-agnostic health data shapes.
 *
 * These are the *normalized* types every data source maps into. A Fitbit
 * adapter, an Apple Health adapter, or manual entry all produce these same
 * structures, so no metric or AI agent ever depends on a vendor's schema.
 * This is the contract behind "Never hardcode Fitbit-specific logic."
 */

/** Provenance attached to every sample so we can trust, dedupe, and audit it. */
export interface SampleSource {
  readonly provider: ProviderId;
  /** Vendor's own id for the record, when available (for idempotent upserts). */
  readonly externalId?: string;
  /** When the data was recorded by the source device/app. */
  readonly recordedAt: Date;
}

export interface SampleMeta {
  readonly userId: UserId;
  readonly date: IsoDate;
  readonly source: SampleSource;
}

export type SleepStage = 'awake' | 'light' | 'deep' | 'rem';

export interface SleepSample extends SampleMeta {
  readonly kind: 'sleep';
  /** Total time asleep, in minutes (excludes time awake in bed). */
  readonly asleepMinutes: number;
  /** Time in bed, in minutes (asleep + awake). */
  readonly timeInBedMinutes: number;
  readonly stages: Readonly<Record<SleepStage, number>>;
  /** Optional resting/sleeping heart rate during the session, bpm. */
  readonly restingHeartRate?: number;
}

export interface RecoveryInputs extends SampleMeta {
  readonly kind: 'recovery';
  /** Heart-rate variability (RMSSD), milliseconds. Higher is generally better. */
  readonly hrvMs?: number;
  /** Resting heart rate, bpm. Lower is generally better. */
  readonly restingHeartRate?: number;
  /** Self-reported or device sleep score 0–100, if already computed upstream. */
  readonly sleepScore?: number;
  /** Subjective stress 0–100 (100 = most stressed), if available. */
  readonly stress?: number;
}

export type WorkoutType =
  | 'push'
  | 'pull'
  | 'legs'
  | 'upper'
  | 'lower'
  | 'full_body'
  | 'bodyweight'
  | 'walking'
  | 'running'
  | 'cycling'
  | 'hiit'
  | 'stretching'
  | 'yoga';

export interface WorkoutSample extends SampleMeta {
  readonly kind: 'workout';
  readonly type: WorkoutType;
  readonly durationMinutes: number;
  /** Total load proxy (e.g. sets × reps × weight, or TRIMP). Unit-agnostic. */
  readonly volume?: number;
  /** Average heart rate during the session, bpm. */
  readonly averageHeartRate?: number;
  readonly activeCalories?: number;
}

export interface BloodSugarSample extends SampleMeta {
  readonly kind: 'blood_sugar';
  /** Glucose in mg/dL. We track trends only — never diagnose. */
  readonly mgPerDl: number;
  readonly context?: 'fasting' | 'pre_meal' | 'post_meal' | 'random';
}

export type HealthSample =
  | SleepSample
  | RecoveryInputs
  | WorkoutSample
  | BloodSugarSample;
