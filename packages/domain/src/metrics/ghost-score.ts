import { Score, type ScoreContribution } from '../value-objects/score.js';

/**
 * Ghost Score — the single headline number (0–100) summarizing overall health
 * for the day. It is a weighted blend of category scores. Each category is
 * itself a {@link Score}, so the explanation tree is fully drillable: the UI can
 * show "why is my Ghost Score 72?" → "Recovery 60" → "HRV below baseline".
 *
 * Categories with no data are omitted and the score re-weights across the rest,
 * so the metric degrades gracefully as more data sources come online.
 */

export type GhostCategory =
  | 'sleep'
  | 'recovery'
  | 'nutrition'
  | 'workout'
  | 'heart'
  | 'stress'
  | 'blood_sugar'
  | 'hydration'
  | 'lifestyle'
  | 'consistency';

/** Default category weights (relative; need not sum to 1). */
export const DEFAULT_CATEGORY_WEIGHTS: Readonly<Record<GhostCategory, number>> =
  Object.freeze({
    sleep: 0.18,
    recovery: 0.16,
    workout: 0.12,
    nutrition: 0.12,
    blood_sugar: 0.1,
    heart: 0.08,
    stress: 0.08,
    hydration: 0.06,
    consistency: 0.06,
    lifestyle: 0.04,
  });

export interface CategoryInput {
  readonly category: GhostCategory;
  readonly score: Score;
}

const CATEGORY_LABEL_TH: Record<GhostCategory, string> = {
  sleep: 'การนอน',
  recovery: 'การฟื้นตัว',
  nutrition: 'โภชนาการ',
  workout: 'การออกกำลังกาย',
  heart: 'หัวใจ',
  stress: 'ความเครียด',
  blood_sugar: 'น้ำตาลในเลือด',
  hydration: 'การดื่มน้ำ',
  lifestyle: 'ไลฟ์สไตล์',
  consistency: 'ความสม่ำเสมอ',
};

export interface GhostScoreResult {
  readonly score: Score;
  /** The category dragging the score down most, for "fix this first" coaching. */
  readonly focusArea?: GhostCategory;
}

export function computeGhostScore(
  categories: readonly CategoryInput[],
  weights: Readonly<Record<GhostCategory, number>> = DEFAULT_CATEGORY_WEIGHTS,
): GhostScoreResult {
  const contributions: ScoreContribution[] = categories.map(
    ({ category, score }) => ({
      factor: category,
      value: score.value,
      weight: weights[category],
      explanation: `${CATEGORY_LABEL_TH[category]} ${score.value}/100 (${score.band}).`,
    }),
  );

  const score = Score.weighted(contributions);
  const weakest = score.weakestContribution;

  return {
    score,
    ...(weakest ? { focusArea: weakest.factor as GhostCategory } : {}),
  };
}
