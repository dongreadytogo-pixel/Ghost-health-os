import { describe, it, expect } from 'vitest';
import { computeGhostScore } from './ghost-score.js';
import { Score } from '../value-objects/score.js';

describe('computeGhostScore', () => {
  it('blends category scores by weight', () => {
    const result = computeGhostScore([
      { category: 'sleep', score: Score.of(90) },
      { category: 'recovery', score: Score.of(60) },
      { category: 'workout', score: Score.of(80) },
    ]);
    expect(result.score.value).toBeGreaterThan(60);
    expect(result.score.value).toBeLessThan(90);
  });

  it('surfaces the weakest category as the focus area', () => {
    const result = computeGhostScore([
      { category: 'sleep', score: Score.of(90) },
      { category: 'blood_sugar', score: Score.of(40) },
      { category: 'workout', score: Score.of(85) },
    ]);
    expect(result.focusArea).toBe('blood_sugar');
  });

  it('produces a drillable explanation tree', () => {
    const result = computeGhostScore([
      { category: 'sleep', score: Score.of(90) },
    ]);
    expect(result.score.contributions[0]?.factor).toBe('sleep');
    expect(result.score.contributions[0]?.explanation).toContain('การนอน');
  });

  it('returns no focus area when there are no categories', () => {
    const result = computeGhostScore([]);
    expect(result.focusArea).toBeUndefined();
    expect(result.score.value).toBe(0);
  });
});
