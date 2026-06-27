import { describe, it, expect } from 'vitest';
import { Score } from './score.js';

describe('Score', () => {
  it('clamps and rounds to an integer in [0, 100]', () => {
    expect(Score.of(150).value).toBe(100);
    expect(Score.of(-5).value).toBe(0);
    expect(Score.of(72.6).value).toBe(73);
  });

  it('maps values to qualitative bands', () => {
    expect(Score.of(10).band).toBe('critical');
    expect(Score.of(40).band).toBe('low');
    expect(Score.of(60).band).toBe('fair');
    expect(Score.of(80).band).toBe('good');
    expect(Score.of(95).band).toBe('excellent');
  });

  it('composes a weighted score from contributions', () => {
    const score = Score.weighted([
      { factor: 'a', value: 100, weight: 1, explanation: '' },
      { factor: 'b', value: 0, weight: 1, explanation: '' },
    ]);
    expect(score.value).toBe(50);
  });

  it('re-weights automatically when factors are omitted', () => {
    const score = Score.weighted([
      { factor: 'a', value: 80, weight: 0.4, explanation: '' },
    ]);
    expect(score.value).toBe(80);
  });

  it('returns 0 with no positive weight', () => {
    expect(Score.weighted([]).value).toBe(0);
  });

  it('identifies the weakest contribution', () => {
    const score = Score.weighted([
      { factor: 'a', value: 80, weight: 1, explanation: '' },
      { factor: 'b', value: 30, weight: 1, explanation: '' },
    ]);
    expect(score.weakestContribution?.factor).toBe('b');
  });
});
