/**
 * Lightweight correlation engine for the analytics module: quantify how two
 * daily series move together (sleep↔recovery, protein↔recovery, stress↔HR,
 * meals↔blood sugar, …) and turn the number into a plain-language insight.
 *
 * Correlation is not causation — the explanations say "เกี่ยวข้อง" (associated),
 * never "ทำให้" (causes).
 */
export type CorrelationStrength = 'none' | 'weak' | 'moderate' | 'strong';

export interface CorrelationInsight {
  /** Pearson r in [-1, 1], or undefined when it can't be computed. */
  readonly coefficient: number | undefined;
  readonly strength: CorrelationStrength;
  readonly direction: 'positive' | 'negative' | 'none';
  readonly sampleSize: number;
  readonly explanation: string;
}

/** Pearson correlation coefficient. Returns undefined if undefined-valued. */
export function pearson(
  xs: readonly number[],
  ys: readonly number[],
): number | undefined {
  const n = Math.min(xs.length, ys.length);
  if (n < 3) return undefined;

  const mx = mean(xs, n);
  const my = mean(ys, n);
  let num = 0;
  let dx2 = 0;
  let dy2 = 0;
  for (let i = 0; i < n; i++) {
    const dx = (xs[i] as number) - mx;
    const dy = (ys[i] as number) - my;
    num += dx * dy;
    dx2 += dx * dx;
    dy2 += dy * dy;
  }
  const denom = Math.sqrt(dx2 * dy2);
  if (denom === 0) return undefined; // a series with no variance
  return num / denom;
}

export interface CorrelationLabels {
  readonly xName: string;
  readonly yName: string;
}

export function analyzeCorrelation(
  xs: readonly number[],
  ys: readonly number[],
  labels: CorrelationLabels,
): CorrelationInsight {
  const n = Math.min(xs.length, ys.length);
  const r = pearson(xs, ys);

  if (r === undefined) {
    return {
      coefficient: undefined,
      strength: 'none',
      direction: 'none',
      sampleSize: n,
      explanation: `ข้อมูลยังไม่พอสำหรับหาความสัมพันธ์ระหว่าง${labels.xName}กับ${labels.yName} (ต้องการอย่างน้อย 3 วัน).`,
    };
  }

  const strength = strengthFor(Math.abs(r));
  const direction = r > 0 ? 'positive' : r < 0 ? 'negative' : 'none';

  return {
    coefficient: r,
    strength,
    direction,
    sampleSize: n,
    explanation: describe(r, strength, direction, labels),
  };
}

function strengthFor(abs: number): CorrelationStrength {
  if (abs < 0.2) return 'none';
  if (abs < 0.4) return 'weak';
  if (abs < 0.7) return 'moderate';
  return 'strong';
}

function describe(
  r: number,
  strength: CorrelationStrength,
  direction: 'positive' | 'negative' | 'none',
  labels: CorrelationLabels,
): string {
  if (strength === 'none') {
    return `${labels.xName}กับ${labels.yName}ดูไม่ค่อยเกี่ยวข้องกันชัดเจน (r=${r.toFixed(2)}).`;
  }
  const dirWord = direction === 'positive' ? 'มากขึ้นด้วยกัน' : 'สวนทางกัน';
  const strWord =
    strength === 'strong' ? 'ชัดเจน' : strength === 'moderate' ? 'พอสมควร' : 'เล็กน้อย';
  return `${labels.xName}กับ${labels.yName}มีแนวโน้ม${dirWord}อย่าง${strWord} (r=${r.toFixed(
    2,
  )}). เป็นความสัมพันธ์ ไม่ใช่สาเหตุโดยตรง.`;
}

function mean(xs: readonly number[], n: number): number {
  let sum = 0;
  for (let i = 0; i < n; i++) sum += xs[i] as number;
  return sum / n;
}
