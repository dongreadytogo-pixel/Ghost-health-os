/**
 * Deterministic, seedable pseudo-random number generator.
 *
 * This is the single most important primitive in an idle/online game: every
 * stochastic decision — hit/miss, critical, loot, affix rolls, spawns — draws
 * from here. Because the generator is fully determined by its seed and the
 * number of draws taken, the entire simulation is *replayable*:
 *
 *   - Offline progress can be fast-forwarded and reproduced exactly.
 *   - A server can re-run a client's reported actions to validate them.
 *   - Tests assert exact outcomes instead of statistical approximations.
 *
 * Algorithm: mulberry32 — a compact, well-distributed 32-bit generator. It is
 * not cryptographically secure (and must never be used for security), but it is
 * fast, has a long period, and is trivially serializable via its `state`.
 */

export interface RngState {
  readonly state: number;
}

export class Rng {
  private s: number;

  private constructor(state: number) {
    // Coerce to an unsigned 32-bit integer so behaviour is identical whether
    // restored from a serialized state or freshly seeded.
    this.s = state >>> 0;
  }

  /** Seed from any 32-bit-ish number. */
  static fromSeed(seed: number): Rng {
    return new Rng(Math.trunc(seed) >>> 0);
  }

  /** Derive a stable seed from a string (e.g. a save id), then construct. */
  static fromString(seed: string): Rng {
    // FNV-1a 32-bit hash — deterministic across platforms.
    let h = 0x811c9dc5;
    for (let i = 0; i < seed.length; i++) {
      h ^= seed.charCodeAt(i);
      h = Math.imul(h, 0x01000193);
    }
    return new Rng(h >>> 0);
  }

  /** Restore a generator from a previously captured state. */
  static restore(snapshot: RngState): Rng {
    return new Rng(snapshot.state);
  }

  /** Capture the current internal state for serialization / save games. */
  snapshot(): RngState {
    return { state: this.s };
  }

  /** A fresh, independent generator at the same point in the stream. */
  clone(): Rng {
    return new Rng(this.s);
  }

  /** Next float in [0, 1). */
  next(): number {
    this.s = (this.s + 0x6d2b79f5) >>> 0;
    let t = this.s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  }

  /** Integer in [min, max] inclusive. */
  int(min: number, max: number): number {
    if (max < min) [min, max] = [max, min];
    return min + Math.floor(this.next() * (max - min + 1));
  }

  /** Float in [min, max). */
  float(min: number, max: number): number {
    return min + this.next() * (max - min);
  }

  /** True with probability `p` (clamped to [0, 1]). */
  chance(p: number): boolean {
    if (p <= 0) return false;
    if (p >= 1) return true;
    return this.next() < p;
  }

  /** Uniformly pick one element; returns undefined for an empty list. */
  pick<T>(items: readonly T[]): T | undefined {
    if (items.length === 0) return undefined;
    return items[this.int(0, items.length - 1)];
  }

  /**
   * Weighted pick. Each entry contributes `weight` to the total; an entry with
   * weight <= 0 can never be chosen. Returns undefined if no positive weight.
   */
  weighted<T>(entries: readonly { item: T; weight: number }[]): T | undefined {
    let total = 0;
    for (const e of entries) if (e.weight > 0) total += e.weight;
    if (total <= 0) return undefined;
    let roll = this.next() * total;
    for (const e of entries) {
      if (e.weight <= 0) continue;
      roll -= e.weight;
      if (roll < 0) return e.item;
    }
    // Floating-point edge: return the last positive-weight entry.
    for (let i = entries.length - 1; i >= 0; i--) {
      const entry = entries[i];
      if (entry && entry.weight > 0) return entry.item;
    }
    return undefined;
  }
}
