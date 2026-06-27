import type {
  ScoreBand,
  GhostCategory,
  Score,
} from '@ghost/domain';
import type { DailyScores } from '../use-cases/compute-daily-scores.js';

/**
 * Deterministic Thai daily summary, built purely from a {@link DailyScores}
 * result — no LLM required. This is the spec's "Daily Summary" deliverable and
 * doubles as the grounded context an LLM agent can later rephrase or expand.
 *
 * Being deterministic, it is fully testable and never hallucinates: every line
 * traces back to a computed score and its explanation.
 */

const BAND_LABEL_TH: Record<ScoreBand, string> = {
  critical: 'ต้องดูแลด่วน',
  low: 'ต่ำ',
  fair: 'พอใช้',
  good: 'ดี',
  excellent: 'ยอดเยี่ยม',
};

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

/** Focus-area-specific, educational (non-diagnostic) recommendations. */
const RECOMMENDATION_TH: Record<GhostCategory, string> = {
  sleep: 'ลองเข้านอนเร็วขึ้น 30 นาที และเลี่ยงจอก่อนนอน เพื่อเพิ่มการนอนลึก.',
  recovery: 'วันนี้เน้นฟื้นตัว: ออกกำลังเบา ๆ ดื่มน้ำให้พอ และนอนให้เต็มที่.',
  nutrition: 'เพิ่มโปรตีนให้ถึงเป้าหมาย เช่น เวย์หลังเทรน เพื่อช่วยสร้างกล้ามเนื้อ.',
  workout: 'ปรับโหลดการฝึกให้อยู่ในโซนเหมาะสม อย่าเพิ่มเร็วเกินไป.',
  heart: 'ชีพจรขณะพักสูงกว่าปกติ ลองพักผ่อนและลดคาเฟอีนดู.',
  stress: 'ลองหายใจลึก ๆ หรือเดินเล่นสั้น ๆ เพื่อลดความเครียด.',
  blood_sugar: 'เดินหลังมื้ออาหารและดื่มน้ำให้พอ ช่วยให้แนวโน้มน้ำตาลคงที่ขึ้น (ข้อมูลเชิงแนวโน้มเท่านั้น).',
  hydration: 'ดื่มน้ำให้ถึงเป้าหมายตลอดวัน อย่ารอจนกระหาย.',
  lifestyle: 'รักษากิจวัตรที่ดีให้ต่อเนื่อง.',
  consistency: 'ทำให้ครบทุกวันแม้เพียงเล็กน้อย ความสม่ำเสมอสำคัญกว่าความหนัก.',
};

export interface DailySummaryOptions {
  /** Optional greeting prefix, e.g. a user's name. */
  readonly greeting?: string;
}

export function generateDailySummary(
  daily: DailyScores,
  options: DailySummaryOptions = {},
): string {
  const lines: string[] = [];

  const head = options.greeting ? `🌅 ${options.greeting} ` : '🌅 ';
  lines.push(`${head}สรุปสุขภาพวันที่ ${daily.date}`);
  lines.push('');

  const overallBand = bandOf(daily.ghostScore);
  lines.push(`Ghost Score: ${daily.ghostScore}/100 (${BAND_LABEL_TH[overallBand]})`);

  const entries = Object.entries(daily.categories) as [GhostCategory, Score][];
  if (entries.length > 0) {
    const parts = entries
      .sort((a, b) => b[1].value - a[1].value)
      .map(([cat, score]) => `${CATEGORY_LABEL_TH[cat]} ${score.value}`);
    lines.push('');
    lines.push(`📊 ${parts.join(' · ')}`);
  }

  if (daily.focusArea) {
    const score = daily.categories[daily.focusArea];
    const why = score?.weakestContribution?.explanation;
    lines.push('');
    lines.push(`🎯 ควรโฟกัส: ${CATEGORY_LABEL_TH[daily.focusArea]}`);
    if (why) lines.push(`   ${why}`);
    lines.push(`💡 ${RECOMMENDATION_TH[daily.focusArea]}`);
  }

  if (daily.training) {
    lines.push('');
    lines.push(
      `🏋️ ความพร้อมเทรน: ${daily.training.readiness.value}/100 · โหลด: ${daily.training.risk}`,
    );
  }

  return lines.join('\n');
}

// Mirrors domain Score.bandFor without needing a Score instance.
function bandOf(value: number): ScoreBand {
  if (value < 25) return 'critical';
  if (value < 50) return 'low';
  if (value < 70) return 'fair';
  if (value < 85) return 'good';
  return 'excellent';
}
