/**
 * Mounts (ขี่ม้า) — a ridden companion that makes the hero hit faster and hit
 * harder. A mount contributes rarity-scaled bonus attributes (folded into the
 * player's build exactly like gear) plus a multiplicative attack-speed boost,
 * so a Mythic shiny steed is a meaningful power spike, not just a cosmetic.
 */

import { clamp, roundHalfUp } from '../shared/math.js';
import type { Rng } from '../shared/rng.js';
import type { MountDefId } from '../shared/branded.js';
import type { Rarity } from '../content/definitions.js';
import {
  rollRarity,
  rollShiny,
  totalMultiplier,
  type RarityTier,
} from '../content/rarity.js';
import {
  ZERO_ATTRIBUTES,
  type Attributes,
} from '../stats/stats.js';

export interface MountDefinition {
  readonly id: MountDefId;
  readonly name: string;
  /** Bonus attributes granted at *common* rarity, before scaling. */
  readonly baseBonus: Partial<Attributes>;
  /** Attack-speed reduction fraction at common (0.08 = 8% faster). */
  readonly baseSpeedBonus: number;
}

/** A mount you actually own, with its roll baked in. */
export interface MountInstance {
  readonly defId: MountDefId;
  readonly name: string;
  readonly rarity: Rarity;
  readonly shiny: boolean;
  readonly bonusAttributes: Attributes;
  /** Multiplier applied to the rider's attack interval (<1 = faster). */
  readonly attackSpeedMultiplier: number;
}

/** Cap on how much faster any mount can make you, to protect game balance. */
const MAX_SPEED_BONUS = 0.5;

export function makeMountInstance(
  def: MountDefinition,
  rarity: Rarity,
  shiny: boolean,
  table?: readonly RarityTier[],
): MountInstance {
  const mult = totalMultiplier(rarity, shiny, table);
  const scale = (v: number | undefined): number => roundHalfUp((v ?? 0) * mult);
  const bonusAttributes: Attributes = {
    strength: scale(def.baseBonus.strength),
    agility: scale(def.baseBonus.agility),
    vitality: scale(def.baseBonus.vitality),
    intelligence: scale(def.baseBonus.intelligence),
    dexterity: scale(def.baseBonus.dexterity),
    luck: scale(def.baseBonus.luck),
  };
  const speedBonus = clamp(def.baseSpeedBonus * mult, 0, MAX_SPEED_BONUS);
  return {
    defId: def.id,
    name: def.name,
    rarity,
    shiny,
    bonusAttributes,
    attackSpeedMultiplier: 1 - speedBonus,
  };
}

export function rollMountInstance(
  def: MountDefinition,
  rng: Rng,
  table?: readonly RarityTier[],
  shinyChance?: number,
): MountInstance {
  const rarity = rollRarity(rng, table);
  const shiny = rollShiny(rng, shinyChance);
  return makeMountInstance(def, rarity, shiny, table);
}

export const NO_MOUNT_BONUS: Attributes = ZERO_ATTRIBUTES;
