/**
 * Stat system — data-driven.
 *
 * Six primary attributes feed a set of derived combat stats through a pure
 * formula whose coefficients live entirely in `BalanceConfig`. Designers (and a
 * live remote-config service) can retune the whole game without touching code,
 * which is the "Data Driven" requirement for Project Titan. No class is locked:
 * any distribution of attribute points produces a valid hybrid build.
 */

import { clamp, roundHalfUp } from '../shared/math.js';

/** The six primary attributes every combatant has. Generic RPG terms only. */
export interface Attributes {
  readonly strength: number; // physical attack
  readonly agility: number; // attack speed, dodge
  readonly vitality: number; // max hp, defense
  readonly intelligence: number; // magic attack, max mp
  readonly dexterity: number; // accuracy, minor physical
  readonly luck: number; // critical, minor everything
}

export const ZERO_ATTRIBUTES: Attributes = Object.freeze({
  strength: 0,
  agility: 0,
  vitality: 0,
  intelligence: 0,
  dexterity: 0,
  luck: 0,
});

export const addAttributes = (a: Attributes, b: Attributes): Attributes => ({
  strength: a.strength + b.strength,
  agility: a.agility + b.agility,
  vitality: a.vitality + b.vitality,
  intelligence: a.intelligence + b.intelligence,
  dexterity: a.dexterity + b.dexterity,
  luck: a.luck + b.luck,
});

/**
 * Stats produced from attributes. These are what combat actually reads, so a
 * monster authored with flat derived stats and a player built from attributes
 * are interchangeable to the combat resolver.
 */
export interface DerivedStats {
  readonly maxHp: number;
  readonly maxMp: number;
  readonly physicalAttack: number;
  readonly magicAttack: number;
  readonly defense: number;
  readonly accuracy: number;
  readonly evasion: number;
  /** Probability in [0, 1]. */
  readonly critChance: number;
  /** Multiplier applied to a critical hit's damage, e.g. 1.5. */
  readonly critMultiplier: number;
  /**
   * Attack interval in simulation ticks. Lower is faster. Derived from a base
   * interval reduced by agility, floored so attacks can never be instant.
   */
  readonly attackIntervalTicks: number;
}

/** Tunable coefficients for the attribute → derived-stat formula. */
export interface StatFormulaConfig {
  readonly baseHp: number;
  readonly hpPerVitality: number;
  readonly baseMp: number;
  readonly mpPerIntelligence: number;
  readonly physicalAttackPerStrength: number;
  readonly physicalAttackPerDexterity: number;
  readonly magicAttackPerIntelligence: number;
  readonly defensePerVitality: number;
  readonly accuracyPerDexterity: number;
  readonly evasionPerAgility: number;
  readonly critChancePerLuck: number;
  readonly maxCritChance: number;
  readonly baseCritMultiplier: number;
  readonly critMultiplierPerLuck: number;
  readonly baseAttackIntervalTicks: number;
  readonly attackIntervalReductionPerAgility: number;
  readonly minAttackIntervalTicks: number;
}

export const DEFAULT_STAT_FORMULA: StatFormulaConfig = Object.freeze({
  baseHp: 50,
  hpPerVitality: 12,
  baseMp: 20,
  mpPerIntelligence: 6,
  physicalAttackPerStrength: 2.5,
  physicalAttackPerDexterity: 0.5,
  magicAttackPerIntelligence: 2.5,
  defensePerVitality: 1.2,
  accuracyPerDexterity: 1.5,
  evasionPerAgility: 1.2,
  critChancePerLuck: 0.004,
  maxCritChance: 0.75,
  baseCritMultiplier: 1.5,
  critMultiplierPerLuck: 0.005,
  baseAttackIntervalTicks: 20,
  attackIntervalReductionPerAgility: 0.15,
  minAttackIntervalTicks: 5,
});

export function deriveStats(
  attrs: Attributes,
  config: StatFormulaConfig = DEFAULT_STAT_FORMULA,
): DerivedStats {
  return {
    maxHp: roundHalfUp(config.baseHp + attrs.vitality * config.hpPerVitality),
    maxMp: roundHalfUp(
      config.baseMp + attrs.intelligence * config.mpPerIntelligence,
    ),
    physicalAttack: roundHalfUp(
      attrs.strength * config.physicalAttackPerStrength +
        attrs.dexterity * config.physicalAttackPerDexterity,
    ),
    magicAttack: roundHalfUp(
      attrs.intelligence * config.magicAttackPerIntelligence,
    ),
    defense: roundHalfUp(attrs.vitality * config.defensePerVitality),
    accuracy: roundHalfUp(attrs.dexterity * config.accuracyPerDexterity),
    evasion: roundHalfUp(attrs.agility * config.evasionPerAgility),
    critChance: clamp(
      attrs.luck * config.critChancePerLuck,
      0,
      config.maxCritChance,
    ),
    critMultiplier:
      config.baseCritMultiplier + attrs.luck * config.critMultiplierPerLuck,
    attackIntervalTicks: Math.max(
      config.minAttackIntervalTicks,
      roundHalfUp(
        config.baseAttackIntervalTicks -
          attrs.agility * config.attackIntervalReductionPerAgility,
      ),
    ),
  };
}
