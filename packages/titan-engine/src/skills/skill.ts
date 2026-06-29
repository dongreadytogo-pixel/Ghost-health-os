/**
 * Skills — random, rarity-scaled abilities the player (and capable companions)
 * auto-cast in battle.
 *
 * A SkillDefinition is authored data; a SkillInstance is what you actually own
 * after a roll — its rarity (and a possible shiny) scale its power and shorten
 * its cooldown, so two copies of the same skill can feel very different. Casting
 * is a pure function over the same combat math as a normal swing, keeping
 * everything deterministic and replayable.
 */

import { roundHalfUp } from '../shared/math.js';
import type { Rng } from '../shared/rng.js';
import type { SkillDefId } from '../shared/branded.js';
import type { Rarity } from '../content/definitions.js';
import {
  rarityRank,
  rollRarity,
  rollShiny,
  totalMultiplier,
  type RarityTier,
} from '../content/rarity.js';
import {
  resolveAttack,
  DEFAULT_COMBAT,
  type AttackOutcome,
  type CombatConfig,
} from '../combat/combat.js';
import type { DerivedStats } from '../stats/stats.js';

export type SkillKind = 'burst' | 'multistrike' | 'lifesteal' | 'heal';

export interface SkillDefinition {
  readonly id: SkillDefId;
  readonly name: string;
  readonly kind: SkillKind;
  /** Cooldown of a *common* roll, in ticks. Rarity shortens it. */
  readonly baseCooldownTicks: number;
  /**
   * Meaning depends on kind:
   *  - burst/multistrike/lifesteal: damage multiplier on the caster's attack
   *  - heal: fraction of the caster's max HP restored
   */
  readonly basePower: number;
  /** Number of hits for `multistrike` (ignored otherwise). */
  readonly hits?: number;
  /** Fraction of damage returned as healing for `lifesteal`. */
  readonly lifestealFraction?: number;
}

export interface SkillInstance {
  readonly defId: SkillDefId;
  readonly name: string;
  readonly kind: SkillKind;
  readonly rarity: Rarity;
  readonly shiny: boolean;
  readonly power: number;
  readonly cooldownTicks: number;
  readonly hits: number;
  readonly lifestealFraction: number;
}

const MIN_COOLDOWN_TICKS = 8;

/** Build an instance at a *given* rarity (used when a companion inherits one). */
export function makeSkillInstance(
  def: SkillDefinition,
  rarity: Rarity,
  shiny: boolean,
  table?: readonly RarityTier[],
): SkillInstance {
  const mult = totalMultiplier(rarity, shiny, table);
  // Higher rarity → shorter cooldown (down to a floor).
  const cooldownTicks = Math.max(
    MIN_COOLDOWN_TICKS,
    roundHalfUp(def.baseCooldownTicks / (1 + 0.12 * rarityRank(rarity))),
  );
  return {
    defId: def.id,
    name: def.name,
    kind: def.kind,
    rarity,
    shiny,
    power: def.basePower * mult,
    cooldownTicks,
    hits: Math.max(1, def.hits ?? 1),
    lifestealFraction: def.lifestealFraction ?? 0,
  };
}

/** Roll a fresh instance: random rarity + shiny, then scale. */
export function rollSkillInstance(
  def: SkillDefinition,
  rng: Rng,
  table?: readonly RarityTier[],
  shinyChance?: number,
): SkillInstance {
  const rarity = rollRarity(rng, table);
  const shiny = rollShiny(rng, shinyChance);
  return makeSkillInstance(def, rarity, shiny, table);
}

export interface SkillCastResult {
  readonly skill: string;
  readonly kind: SkillKind;
  readonly hits: readonly AttackOutcome[];
  readonly totalDamage: number;
  /** HP restored to the caster (heal / lifesteal). */
  readonly heal: number;
}

/** Resolve a skill cast. Damage reuses the normal combat resolver, scaled. */
export function castSkill(
  caster: DerivedStats,
  target: DerivedStats,
  skill: SkillInstance,
  rng: Rng,
  config: CombatConfig = DEFAULT_COMBAT,
): SkillCastResult {
  if (skill.kind === 'heal') {
    return {
      skill: skill.name,
      kind: skill.kind,
      hits: [],
      totalDamage: 0,
      heal: roundHalfUp(caster.maxHp * skill.power),
    };
  }

  const scaled: DerivedStats = {
    ...caster,
    physicalAttack: roundHalfUp(caster.physicalAttack * skill.power),
    magicAttack: roundHalfUp(caster.magicAttack * skill.power),
  };

  const hitCount = skill.kind === 'multistrike' ? skill.hits : 1;
  const outcomes: AttackOutcome[] = [];
  let totalDamage = 0;
  for (let i = 0; i < hitCount; i++) {
    const out = resolveAttack(scaled, target, rng, 'physical', config);
    outcomes.push(out);
    totalDamage += out.damage;
  }

  const heal =
    skill.kind === 'lifesteal'
      ? roundHalfUp(totalDamage * skill.lifestealFraction)
      : 0;

  return {
    skill: skill.name,
    kind: skill.kind,
    hits: outcomes,
    totalDamage,
    heal,
  };
}
