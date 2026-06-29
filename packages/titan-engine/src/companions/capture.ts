/**
 * Capture — the chance, on defeating a monster, to tame it into a Companion.
 *
 * Every successful capture rolls its own rarity, a shiny chance, and a small
 * chance to be born already knowing a random skill. Bosses are far harder to
 * tame. All rolls flow through the passed Rng so a kill's capture outcome is
 * reproducible.
 */

import type { Rng } from '../shared/rng.js';
import { rollRarity, rollShiny, type RarityTier } from '../content/rarity.js';
import type { MonsterDefinition } from '../content/definitions.js';
import type { EntityIdFactory } from '../entities/combatant.js';
import {
  makeSkillInstance,
  type SkillDefinition,
  type SkillInstance,
} from '../skills/skill.js';
import { companionTitle, type Companion } from './companion.js';

export interface CaptureConfig {
  /** Base probability of taming a normal monster on kill. */
  readonly baseChance: number;
  /** Multiplier applied to a boss's capture chance (usually << 1). */
  readonly bossChanceMultiplier: number;
  /** Probability a captured companion is born knowing a skill. */
  readonly innateSkillChance: number;
  /** Skill definitions a newborn companion may roll from. */
  readonly skillPool: readonly SkillDefinition[];
  readonly rarityTable?: readonly RarityTier[];
  readonly shinyChance?: number;
}

export const DEFAULT_CAPTURE: CaptureConfig = Object.freeze({
  baseChance: 0.08,
  bossChanceMultiplier: 0.25,
  innateSkillChance: 0.25,
  skillPool: [],
});

export function captureChance(
  monster: MonsterDefinition,
  config: CaptureConfig = DEFAULT_CAPTURE,
): number {
  return monster.isBoss
    ? config.baseChance * config.bossChanceMultiplier
    : config.baseChance;
}

/**
 * Attempt to capture the just-defeated monster. Returns a fully-rolled Companion
 * on success, or undefined if the capture roll failed.
 */
export function tryCapture(
  monster: MonsterDefinition,
  rng: Rng,
  idFactory: EntityIdFactory,
  config: CaptureConfig = DEFAULT_CAPTURE,
): Companion | undefined {
  if (!rng.chance(captureChance(monster, config))) return undefined;

  const rarity = rollRarity(rng, config.rarityTable);
  const shiny = rollShiny(rng, config.shinyChance);

  let skill: SkillInstance | undefined;
  if (config.skillPool.length > 0 && rng.chance(config.innateSkillChance)) {
    const def = rng.pick(config.skillPool);
    if (def) skill = makeSkillInstance(def, rarity, shiny, config.rarityTable);
  }

  const companion: Companion = {
    id: idFactory.next(),
    sourceMonsterId: monster.id,
    name: companionTitle(rarity, shiny, monster.name),
    baseName: monster.name,
    rarity,
    shiny,
    baseStats: monster.stats,
    bond: 0,
    ...(skill ? { skill } : {}),
  };
  return companion;
}
