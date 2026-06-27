import { clamp } from '../shared/guard.js';

/**
 * A normalized 0–100 score with a qualitative band. Every score in Ghost Health
 * OS — Ghost Score, Recovery, Sleep, each sub-category — is expressed as this
 * value object so the UI and the AI agents can treat them uniformly.
 */

export type ScoreBand = 'critical' | 'low' | 'fair' | 'good' | 'excellent';

export interface ScoreContribution {
  /** Stable identifier of the contributing factor, e.g. "deep_sleep". */
  readonly factor: string;
  /** This factor's own normalized 0–100 sub-score. */
  readonly value: number;
  /** Relative weight applied when composing the parent score (0–1). */
  readonly weight: number;
  /** Human-readable, non-diagnostic explanation of the contribution. */
  readonly explanation: string;
}

export class Score {
  /** Always an integer in [0, 100]. */
  readonly value: number;
  readonly band: ScoreBand;
  readonly contributions: readonly ScoreContribution[];

  private constructor(value: number, contributions: ScoreContribution[]) {
    this.value = Math.round(clamp(value, 0, 100));
    this.band = Score.bandFor(this.value);
    this.contributions = Object.freeze([...contributions]);
  }

  static of(value: number, contributions: ScoreContribution[] = []): Score {
    return new Score(value, contributions);
  }

  /**
   * Compose a score from weighted contributions. Weights are normalized, so the
   * caller need not make them sum to exactly 1 — only their ratios matter. When
   * a factor has no data it should simply be omitted, and the remaining factors
   * are re-weighted automatically.
   */
  static weighted(contributions: ScoreContribution[]): Score {
    const totalWeight = contributions.reduce((sum, c) => sum + c.weight, 0);
    if (totalWeight <= 0) return new Score(0, contributions);
    const value =
      contributions.reduce((sum, c) => sum + c.value * c.weight, 0) /
      totalWeight;
    return new Score(value, contributions);
  }

  static bandFor(value: number): ScoreBand {
    if (value < 25) return 'critical';
    if (value < 50) return 'low';
    if (value < 70) return 'fair';
    if (value < 85) return 'good';
    return 'excellent';
  }

  /** The single biggest drag on this score, useful for "what to fix first". */
  get weakestContribution(): ScoreContribution | undefined {
    if (this.contributions.length === 0) return undefined;
    return [...this.contributions].sort((a, b) => a.value - b.value)[0];
  }
}
