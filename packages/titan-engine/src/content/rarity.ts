/**
 * Rarity — the cross-cutting "how special is this" axis applied to *everything*
 * the game rolls: items, mounts, companions and skills. Centralizing it here
 * means one tuning table governs the whole game's power-and-excitement curve,
 * and every system scales identically.
 *
 * Two charming extras live here too:
 *  - a higher rarity is rarer *and* stronger (weight ↓, power ↑), and
 *  - a tiny "shiny / prismatic" roll that, win or lose, is independent of rarity
 *    and stacks a bonus multiplier on top — the classic "1 in a few hundred"
 *    thrill that makes a drop worth screenshotting.
 */

import type { Rng } from '../shared/rng.js';
import type { Rarity } from './definitions.js';

export const RARITY_ORDER: readonly Rarity[] = [
  'common',
  'uncommon',
  'rare',
  'epic',
  'legendary',
  'mythic',
];

export const rarityRank = (r: Rarity): number => RARITY_ORDER.indexOf(r);

/** The next tier up, capped at mythic (used by fusion / evolution). */
export const nextRarity = (r: Rarity): Rarity =>
  RARITY_ORDER[Math.min(rarityRank(r) + 1, RARITY_ORDER.length - 1)] ?? r;

export interface RarityTier {
  readonly rarity: Rarity;
  /** Relative likelihood of rolling this tier. */
  readonly weight: number;
  /** Multiplier applied to base power/stats at this tier. */
  readonly powerMultiplier: number;
}

/** Default global rarity table — steeper power, scarcer tiers as you climb. */
export const DEFAULT_RARITY_TABLE: readonly RarityTier[] = Object.freeze([
  { rarity: 'common', weight: 1000, powerMultiplier: 1.0 },
  { rarity: 'uncommon', weight: 450, powerMultiplier: 1.25 },
  { rarity: 'rare', weight: 180, powerMultiplier: 1.6 },
  { rarity: 'epic', weight: 60, powerMultiplier: 2.1 },
  { rarity: 'legendary', weight: 18, powerMultiplier: 2.8 },
  { rarity: 'mythic', weight: 4, powerMultiplier: 4.0 },
]);

/** Odds of a shiny / prismatic variant on any roll (homage to "1 in 256"). */
export const DEFAULT_SHINY_CHANCE = 1 / 256;
/** Multiplier a shiny variant stacks on top of its rarity multiplier. */
export const SHINY_MULTIPLIER = 1.5;

export function powerMultiplierFor(
  rarity: Rarity,
  table: readonly RarityTier[] = DEFAULT_RARITY_TABLE,
): number {
  return table.find((t) => t.rarity === rarity)?.powerMultiplier ?? 1;
}

/** Roll a rarity tier from the table (weighted). Defaults to common. */
export function rollRarity(
  rng: Rng,
  table: readonly RarityTier[] = DEFAULT_RARITY_TABLE,
): Rarity {
  return (
    rng.weighted(table.map((t) => ({ item: t.rarity, weight: t.weight }))) ??
    'common'
  );
}

export function rollShiny(rng: Rng, chance = DEFAULT_SHINY_CHANCE): boolean {
  return rng.chance(chance);
}

/** Combined multiplier from a rarity plus an optional shiny bonus. */
export function totalMultiplier(
  rarity: Rarity,
  shiny: boolean,
  table: readonly RarityTier[] = DEFAULT_RARITY_TABLE,
): number {
  return powerMultiplierFor(rarity, table) * (shiny ? SHINY_MULTIPLIER : 1);
}
