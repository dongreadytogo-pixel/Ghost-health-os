import { describe, it, expect } from 'vitest';
import {
  ensureInRange,
  ensureNonNegative,
  ensureNonEmpty,
  ensureFinite,
  clamp,
} from './guard.js';

describe('guards', () => {
  it('ensureFinite rejects NaN and Infinity', () => {
    expect(ensureFinite(Number.NaN, 'x').ok).toBe(false);
    expect(ensureFinite(Infinity, 'x').ok).toBe(false);
    expect(ensureFinite(3, 'x').ok).toBe(true);
  });

  it('ensureInRange enforces bounds and reports details', () => {
    const out = ensureInRange(5, 0, 3, 'glucose');
    expect(out.ok).toBe(false);
    if (!out.ok) {
      expect(out.error.code).toBe('OUT_OF_RANGE');
      expect(out.error.details).toMatchObject({ min: 0, max: 3, value: 5 });
    }
    expect(ensureInRange(2, 0, 3, 'glucose').ok).toBe(true);
  });

  it('ensureNonNegative rejects negatives', () => {
    expect(ensureNonNegative(-1, 'reps').ok).toBe(false);
    expect(ensureNonNegative(0, 'reps').ok).toBe(true);
  });

  it('ensureNonEmpty rejects blank strings', () => {
    expect(ensureNonEmpty('   ', 'name').ok).toBe(false);
    expect(ensureNonEmpty('ok', 'name').ok).toBe(true);
  });

  it('clamp is total', () => {
    expect(clamp(5, 0, 3)).toBe(3);
    expect(clamp(-5, 0, 3)).toBe(0);
    expect(clamp(2, 0, 3)).toBe(2);
  });
});
