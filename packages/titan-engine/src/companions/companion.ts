/**
 * Companions — monsters you capture in the field that then walk behind you and
 * fight on your side (the "party" the brief asks for).
 *
 * A companion remembers the monster it came from, its rolled rarity (and shiny),
 * a growing **bond** that strengthens it the longer it adventures with you, and
 * an optional random skill. Its live combat stats are the source monster's stats
 * scaled by rarity × bond — so the same species captured twice can be wildly
 * different, and a long-time companion keeps getting better.
 */

import { roundHalfUp } from '../shared/math.js';
import type { EntityId, MonsterDefId } from '../shared/branded.js';
import type { Rarity } from '../content/definitions.js';
import { powerMultiplierFor, SHINY_MULTIPLIER } from '../content/rarity.js';
import type { DerivedStats } from '../stats/stats.js';
import type { SkillInstance } from '../skills/skill.js';

export interface BondConfig {
  readonly maxBond: number;
  /** Fractional stat gain per bond level (0.05 = +5% per level). */
  readonly bonusPerLevel: number;
}

export const DEFAULT_BOND: BondConfig = Object.freeze({
  maxBond: 10,
  bonusPerLevel: 0.05,
});

export interface Companion {
  readonly id: EntityId;
  readonly sourceMonsterId: MonsterDefId;
  /** Display name including rarity/shiny flair. */
  readonly name: string;
  /** The plain source species name, kept stable across re-titling/fusion. */
  readonly baseName: string;
  readonly rarity: Rarity;
  readonly shiny: boolean;
  /** The source monster's authored stats, before rarity/bond scaling. */
  readonly baseStats: DerivedStats;
  readonly bond: number;
  readonly skill?: SkillInstance;
}

/** Display flair: a shiny prefix and a rarity tag, e.g. "✦ Rare Gel Crawler". */
export function companionTitle(
  rarity: Rarity,
  shiny: boolean,
  baseName: string,
): string {
  const tag = rarity[0]!.toUpperCase() + rarity.slice(1);
  return `${shiny ? '✦ ' : ''}${tag} ${baseName}`;
}

/** A scalar power rating, handy for auto-management and fusion comparisons. */
export function companionPower(c: Companion, config = DEFAULT_BOND): number {
  const s = companionStats(c, config);
  return s.maxHp + s.physicalAttack * 4 + s.defense * 2 + s.magicAttack * 4;
}

function scaleStats(stats: DerivedStats, factor: number): DerivedStats {
  return {
    ...stats,
    maxHp: roundHalfUp(stats.maxHp * factor),
    physicalAttack: roundHalfUp(stats.physicalAttack * factor),
    magicAttack: roundHalfUp(stats.magicAttack * factor),
    defense: roundHalfUp(stats.defense * factor),
    accuracy: roundHalfUp(stats.accuracy * factor),
    evasion: roundHalfUp(stats.evasion * factor),
  };
}

/** Live combat stats = base × rarity × shiny × (1 + bond growth). */
export function companionStats(
  c: Companion,
  config: BondConfig = DEFAULT_BOND,
): DerivedStats {
  const rarityMult = powerMultiplierFor(c.rarity) * (c.shiny ? SHINY_MULTIPLIER : 1);
  const bondMult = 1 + Math.min(c.bond, config.maxBond) * config.bonusPerLevel;
  return scaleStats(c.baseStats, rarityMult * bondMult);
}

/** Strengthen the bond (immutably), clamped to the configured maximum. */
export function gainBond(
  c: Companion,
  amount = 1,
  config: BondConfig = DEFAULT_BOND,
): Companion {
  const bond = Math.min(config.maxBond, c.bond + Math.max(0, amount));
  return bond === c.bond ? c : { ...c, bond };
}
