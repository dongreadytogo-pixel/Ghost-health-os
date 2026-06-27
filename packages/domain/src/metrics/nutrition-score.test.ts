import { describe, it, expect } from 'vitest';
import {
  computeNutritionScore,
  computeHydrationScore,
} from './nutrition-score.js';

describe('computeNutritionScore', () => {
  it('rewards hitting the protein target', () => {
    const score = computeNutritionScore({ proteinG: 160, proteinTargetG: 160 });
    expect(score.value).toBe(100);
  });

  it('scales protein partial credit below target', () => {
    const score = computeNutritionScore({ proteinG: 80, proteinTargetG: 160 });
    const protein = score.contributions.find((c) => c.factor === 'protein');
    expect(protein?.value).toBeCloseTo(50);
  });

  it('penalizes calorie deviation in either direction', () => {
    const over = computeNutritionScore({
      proteinG: 160,
      proteinTargetG: 160,
      calories: 3000,
      calorieTarget: 2400,
    });
    const cal = over.contributions.find((c) => c.factor === 'calories');
    expect(cal?.value).toBeLessThan(100);
  });

  it('omits factors with no data and re-weights', () => {
    const score = computeNutritionScore({ proteinG: 120, proteinTargetG: 160 });
    expect(score.contributions.map((c) => c.factor)).toEqual(['protein']);
  });
});

describe('computeHydrationScore', () => {
  it('caps at 100 once the target is met', () => {
    expect(computeHydrationScore({ waterMl: 3500, targetMl: 3000 }).value).toBe(100);
  });

  it('scales below target', () => {
    expect(computeHydrationScore({ waterMl: 1500, targetMl: 3000 }).value).toBe(50);
  });
});
