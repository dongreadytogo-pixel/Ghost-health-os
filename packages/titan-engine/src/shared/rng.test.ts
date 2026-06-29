import { describe, it, expect } from 'vitest';
import { Rng } from './rng.js';

describe('Rng', () => {
  it('is deterministic: same seed yields the same stream', () => {
    const a = Rng.fromSeed(12345);
    const b = Rng.fromSeed(12345);
    const seqA = Array.from({ length: 10 }, () => a.next());
    const seqB = Array.from({ length: 10 }, () => b.next());
    expect(seqA).toEqual(seqB);
  });

  it('different seeds diverge', () => {
    const a = Rng.fromSeed(1);
    const b = Rng.fromSeed(2);
    expect(a.next()).not.toEqual(b.next());
  });

  it('produces floats in [0, 1)', () => {
    const rng = Rng.fromSeed(99);
    for (let i = 0; i < 1000; i++) {
      const v = rng.next();
      expect(v).toBeGreaterThanOrEqual(0);
      expect(v).toBeLessThan(1);
    }
  });

  it('fromString is stable and platform-independent', () => {
    const a = Rng.fromString('save-001');
    const b = Rng.fromString('save-001');
    expect(a.next()).toEqual(b.next());
    expect(Rng.fromString('save-002').snapshot()).not.toEqual(
      Rng.fromString('save-001').snapshot(),
    );
  });

  it('snapshot + restore reproduces the exact remaining stream', () => {
    const rng = Rng.fromSeed(7);
    rng.next();
    rng.next();
    const snap = rng.snapshot();
    const expected = Array.from({ length: 5 }, () => rng.next());

    const restored = Rng.restore(snap);
    const actual = Array.from({ length: 5 }, () => restored.next());
    expect(actual).toEqual(expected);
  });

  it('clone forks an independent stream from the same point', () => {
    const rng = Rng.fromSeed(42);
    rng.next();
    const fork = rng.clone();
    expect(fork.next()).toEqual(rng.next());
  });

  it('int respects inclusive bounds', () => {
    const rng = Rng.fromSeed(3);
    for (let i = 0; i < 1000; i++) {
      const v = rng.int(5, 10);
      expect(v).toBeGreaterThanOrEqual(5);
      expect(v).toBeLessThanOrEqual(10);
      expect(Number.isInteger(v)).toBe(true);
    }
  });

  it('int(n, n) always returns n', () => {
    const rng = Rng.fromSeed(3);
    expect(rng.int(4, 4)).toBe(4);
  });

  it('chance(0) is never true and chance(1) is always true', () => {
    const rng = Rng.fromSeed(8);
    for (let i = 0; i < 50; i++) {
      expect(rng.chance(0)).toBe(false);
      expect(rng.chance(1)).toBe(true);
    }
  });

  it('chance converges to the requested probability', () => {
    const rng = Rng.fromSeed(2024);
    let hits = 0;
    const n = 20000;
    for (let i = 0; i < n; i++) if (rng.chance(0.3)) hits++;
    expect(hits / n).toBeCloseTo(0.3, 1);
  });

  it('weighted never selects a zero-weight entry and honours weights', () => {
    const rng = Rng.fromSeed(555);
    const counts = { a: 0, b: 0, c: 0 };
    for (let i = 0; i < 20000; i++) {
      const choice = rng.weighted([
        { item: 'a' as const, weight: 1 },
        { item: 'b' as const, weight: 3 },
        { item: 'c' as const, weight: 0 },
      ]);
      if (choice) counts[choice]++;
    }
    expect(counts.c).toBe(0);
    // b should appear roughly 3x as often as a.
    expect(counts.b / counts.a).toBeCloseTo(3, 0);
  });

  it('weighted returns undefined when no positive weight exists', () => {
    const rng = Rng.fromSeed(1);
    expect(rng.weighted([{ item: 'x', weight: 0 }])).toBeUndefined();
    expect(rng.weighted([])).toBeUndefined();
  });

  it('pick returns undefined for an empty list', () => {
    expect(Rng.fromSeed(1).pick([])).toBeUndefined();
  });
});
