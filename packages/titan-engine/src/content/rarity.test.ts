import { describe, it, expect } from 'vitest';
import {
  RARITY_ORDER,
  rarityRank,
  nextRarity,
  rollRarity,
  rollShiny,
  powerMultiplierFor,
  totalMultiplier,
  SHINY_MULTIPLIER,
  DEFAULT_RARITY_TABLE,
} from './rarity.js';
import { Rng } from '../shared/rng.js';

describe('rarity ordering', () => {
  it('ranks ascend and power multipliers increase with rank', () => {
    for (let i = 1; i < RARITY_ORDER.length; i++) {
      const lo = RARITY_ORDER[i - 1]!;
      const hi = RARITY_ORDER[i]!;
      expect(rarityRank(hi)).toBeGreaterThan(rarityRank(lo));
      expect(powerMultiplierFor(hi)).toBeGreaterThan(powerMultiplierFor(lo));
    }
  });

  it('nextRarity steps up and caps at mythic', () => {
    expect(nextRarity('common')).toBe('uncommon');
    expect(nextRarity('mythic')).toBe('mythic');
  });
});

describe('rollRarity', () => {
  it('is deterministic and favours common over mythic', () => {
    const rng = Rng.fromSeed(2026);
    const counts = new Map<string, number>();
    for (let i = 0; i < 50000; i++) {
      const r = rollRarity(rng);
      counts.set(r, (counts.get(r) ?? 0) + 1);
    }
    expect(counts.get('common')!).toBeGreaterThan(counts.get('mythic') ?? 0);
    // Same seed reproduces the exact first draw.
    expect(rollRarity(Rng.fromSeed(1))).toBe(rollRarity(Rng.fromSeed(1)));
  });

  it('only ever returns table tiers', () => {
    const rng = Rng.fromSeed(5);
    for (let i = 0; i < 1000; i++) {
      expect(DEFAULT_RARITY_TABLE.map((t) => t.rarity)).toContain(
        rollRarity(rng),
      );
    }
  });
});

describe('shiny', () => {
  it('is rare but occurs over many rolls', () => {
    const rng = Rng.fromSeed(7);
    let shinies = 0;
    for (let i = 0; i < 20000; i++) if (rollShiny(rng)) shinies++;
    expect(shinies).toBeGreaterThan(0);
    expect(shinies).toBeLessThan(20000 / 50); // clearly rare
  });

  it('stacks its multiplier on top of rarity', () => {
    expect(totalMultiplier('rare', true)).toBeCloseTo(
      powerMultiplierFor('rare') * SHINY_MULTIPLIER,
      5,
    );
    expect(totalMultiplier('rare', false)).toBe(powerMultiplierFor('rare'));
  });
});
