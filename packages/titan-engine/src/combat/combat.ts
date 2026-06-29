/**
 * Combat resolution — a pure function of (attacker, defender, rng).
 *
 * One call resolves one swing: roll to hit (accuracy vs evasion), roll for a
 * critical, then compute defense-mitigated damage. It mutates nothing and reads
 * only `DerivedStats`, so a player built from attributes and a monster authored
 * with flat stats are handled identically. All randomness comes from the passed
 * Rng, keeping every fight replayable.
 */

import { clamp, roundHalfUp } from '../shared/math.js';
import type { Rng } from '../shared/rng.js';
import type { DerivedStats } from '../stats/stats.js';

export interface CombatConfig {
  /** Damage variance: actual damage is base × [1 - spread, 1 + spread]. */
  readonly damageSpread: number;
  /** Softening constant in the defense formula; higher = defense matters less. */
  readonly defenseConstant: number;
  /** Baseline hit chance before accuracy/evasion adjust it. */
  readonly baseHitChance: number;
  /** How strongly each point of accuracy-minus-evasion shifts hit chance. */
  readonly hitChancePerNetAccuracy: number;
  readonly minHitChance: number;
  readonly maxHitChance: number;
  /** Damage is never below this (a hit always stings at least a little). */
  readonly minDamage: number;
}

export const DEFAULT_COMBAT: CombatConfig = Object.freeze({
  damageSpread: 0.1,
  defenseConstant: 50,
  baseHitChance: 0.9,
  hitChancePerNetAccuracy: 0.01,
  minHitChance: 0.05,
  maxHitChance: 1,
  minDamage: 1,
});

export type AttackKind = 'physical' | 'magic';

export interface AttackOutcome {
  readonly hit: boolean;
  readonly critical: boolean;
  /** Damage actually dealt (0 on a miss), already mitigated and floored. */
  readonly damage: number;
  readonly kind: AttackKind;
}

/** Chance for `attacker` to land a hit on `defender`. */
export function hitChance(
  attacker: DerivedStats,
  defender: DerivedStats,
  config: CombatConfig = DEFAULT_COMBAT,
): number {
  const net = attacker.accuracy - defender.evasion;
  return clamp(
    config.baseHitChance + net * config.hitChancePerNetAccuracy,
    config.minHitChance,
    config.maxHitChance,
  );
}

/** Fraction of damage that gets through `defense` (1 = no mitigation). */
export function damageMultiplierFromDefense(
  defense: number,
  config: CombatConfig = DEFAULT_COMBAT,
): number {
  const d = Math.max(0, defense);
  return config.defenseConstant / (config.defenseConstant + d);
}

export function resolveAttack(
  attacker: DerivedStats,
  defender: DerivedStats,
  rng: Rng,
  kind: AttackKind = 'physical',
  config: CombatConfig = DEFAULT_COMBAT,
): AttackOutcome {
  if (!rng.chance(hitChance(attacker, defender, config))) {
    return { hit: false, critical: false, damage: 0, kind };
  }

  const power =
    kind === 'physical' ? attacker.physicalAttack : attacker.magicAttack;

  const critical = rng.chance(attacker.critChance);
  const critFactor = critical ? attacker.critMultiplier : 1;
  const variance = 1 + rng.float(-config.damageSpread, config.damageSpread);
  const mitigation = damageMultiplierFromDefense(defender.defense, config);

  const raw = power * critFactor * variance * mitigation;
  const damage = Math.max(config.minDamage, roundHalfUp(raw));

  return { hit: true, critical, damage, kind };
}
