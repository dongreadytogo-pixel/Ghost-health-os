import { describe, it, expect } from 'vitest';
import { pearson, analyzeCorrelation } from './correlation.js';

describe('pearson', () => {
  it('returns +1 for a perfect positive relationship', () => {
    expect(pearson([1, 2, 3, 4], [2, 4, 6, 8])).toBeCloseTo(1);
  });

  it('returns -1 for a perfect negative relationship', () => {
    expect(pearson([1, 2, 3, 4], [8, 6, 4, 2])).toBeCloseTo(-1);
  });

  it('is undefined with too few points', () => {
    expect(pearson([1, 2], [2, 4])).toBeUndefined();
  });

  it('is undefined when a series has no variance', () => {
    expect(pearson([5, 5, 5, 5], [1, 2, 3, 4])).toBeUndefined();
  });
});

describe('analyzeCorrelation', () => {
  const labels = { xName: 'การนอน', yName: 'การฟื้นตัว' };

  it('classifies a strong positive association', () => {
    const insight = analyzeCorrelation(
      [6, 7, 8, 9, 10],
      [60, 70, 78, 88, 99],
      labels,
    );
    expect(insight.strength).toBe('strong');
    expect(insight.direction).toBe('positive');
    expect(insight.explanation).toContain('ไม่ใช่สาเหตุ');
  });

  it('reports insufficient data clearly', () => {
    const insight = analyzeCorrelation([1, 2], [2, 4], labels);
    expect(insight.coefficient).toBeUndefined();
    expect(insight.strength).toBe('none');
  });
});
