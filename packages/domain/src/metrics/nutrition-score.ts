import { Score, type ScoreContribution } from '../value-objects/score.js';
import { clamp } from '../shared/guard.js';

/**
 * Nutrition score (0–100). For a high-protein, lean-muscle goal the dominant
 * lever is hitting the protein target, so protein is weighted heaviest, with
 * calorie adherence and fiber as supporting factors. Educational, not clinical.
 */
export interface NutritionInput {
  readonly proteinG: number;
  readonly proteinTargetG: number;
  readonly calories?: number;
  readonly calorieTarget?: number;
  readonly fiberG?: number;
  readonly fiberTargetG?: number;
}

export function computeNutritionScore(input: NutritionInput): Score {
  const contributions: ScoreContribution[] = [];

  // Protein — full credit at/above target; partial below; no penalty above.
  const proteinPct =
    input.proteinTargetG > 0
      ? clamp((input.proteinG / input.proteinTargetG) * 100, 0, 100)
      : 0;
  contributions.push({
    factor: 'protein',
    value: proteinPct,
    weight: 0.55,
    explanation: `โปรตีน ${Math.round(input.proteinG)}g จากเป้าหมาย ${Math.round(
      input.proteinTargetG,
    )}g (${proteinPct.toFixed(0)}%).`,
  });

  // Calories — closeness to target in either direction (tolerance ±25%).
  if (input.calories !== undefined && input.calorieTarget && input.calorieTarget > 0) {
    const deviation = Math.abs(input.calories - input.calorieTarget) / input.calorieTarget;
    contributions.push({
      factor: 'calories',
      value: clamp(100 * (1 - deviation / 0.25), 0, 100),
      weight: 0.3,
      explanation: `พลังงาน ${Math.round(input.calories)} kcal เทียบเป้าหมาย ${Math.round(
        input.calorieTarget,
      )} kcal.`,
    });
  }

  // Fiber — supporting factor, full credit at target.
  if (input.fiberG !== undefined && input.fiberTargetG && input.fiberTargetG > 0) {
    contributions.push({
      factor: 'fiber',
      value: clamp((input.fiberG / input.fiberTargetG) * 100, 0, 100),
      weight: 0.15,
      explanation: `ไฟเบอร์ ${Math.round(input.fiberG)}g จากเป้าหมาย ${Math.round(
        input.fiberTargetG,
      )}g.`,
    });
  }

  return Score.weighted(contributions);
}

/**
 * Hydration score (0–100). Full credit at the daily water target; gentle
 * over-target tolerance (no penalty for reasonable extra).
 */
export interface HydrationInput {
  readonly waterMl: number;
  readonly targetMl: number;
}

export function computeHydrationScore(input: HydrationInput): Score {
  const pct =
    input.targetMl > 0 ? clamp((input.waterMl / input.targetMl) * 100, 0, 100) : 0;
  return Score.of(pct, [
    {
      factor: 'water',
      value: pct,
      weight: 1,
      explanation: `ดื่มน้ำ ${Math.round(input.waterMl)}ml จากเป้าหมาย ${Math.round(
        input.targetMl,
      )}ml (${pct.toFixed(0)}%).`,
    },
  ]);
}
