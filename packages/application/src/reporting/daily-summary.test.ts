import { describe, it, expect } from 'vitest';
import { Score, type GhostCategory } from '@ghost/domain';
import { generateDailySummary } from './daily-summary.js';
import type { DailyScores } from '../use-cases/compute-daily-scores.js';
import type { IsoDate } from '@ghost/domain';

const daily = (overrides: Partial<DailyScores> = {}): DailyScores => ({
  date: '2026-06-27' as IsoDate,
  ghostScore: 78,
  categories: {
    sleep: Score.of(92),
    recovery: Score.weighted([
      { factor: 'hrv', value: 60, weight: 1, explanation: 'HRV ต่ำกว่าค่าเฉลี่ย.' },
    ]),
  } as Partial<Record<GhostCategory, Score>>,
  focusArea: 'recovery',
  training: undefined,
  ...overrides,
});

describe('generateDailySummary', () => {
  it('includes the Ghost Score, band, and category line', () => {
    const text = generateDailySummary(daily());
    expect(text).toContain('Ghost Score: 78/100');
    expect(text).toContain('ดี'); // band label for 78
    expect(text).toContain('การนอน 92');
  });

  it('surfaces the focus area with its reason and a recommendation', () => {
    const text = generateDailySummary(daily());
    expect(text).toContain('ควรโฟกัส: การฟื้นตัว');
    expect(text).toContain('HRV ต่ำกว่าค่าเฉลี่ย.');
    expect(text).toContain('💡');
  });

  it('adds a greeting when provided', () => {
    const text = generateDailySummary(daily(), { greeting: 'สวัสดีตอนเช้า' });
    expect(text).toContain('สวัสดีตอนเช้า');
  });

  it('renders training readiness when present', () => {
    const text = generateDailySummary(
      daily({
        training: {
          acute: 100,
          chronic: 100,
          acwr: 1,
          risk: 'optimal',
          score: Score.of(90),
          readiness: Score.of(85),
        },
      }),
    );
    expect(text).toContain('ความพร้อมเทรน: 85/100');
    expect(text).toContain('optimal');
  });
});
