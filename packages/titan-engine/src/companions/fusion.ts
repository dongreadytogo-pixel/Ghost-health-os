/**
 * Fusion (รวมร่าง / วิวัฒนาการ) — merge two companions into a stronger one.
 *
 * The result jumps one rarity tier above the better parent, inherits the
 * stronger statline plus a slice of the weaker one, keeps any shiny lineage,
 * carries over half the higher bond, and inherits the more powerful of the two
 * parents' skills. Fusion is deterministic given the inputs (no RNG needed),
 * which keeps it safe to validate server-side.
 */

import { roundHalfUp } from '../shared/math.js';
import type { EntityIdFactory } from '../entities/combatant.js';
import { nextRarity, rarityRank } from '../content/rarity.js';
import type { DerivedStats } from '../stats/stats.js';
import type { SkillInstance } from '../skills/skill.js';
import {
  companionPower,
  companionTitle,
  type Companion,
} from './companion.js';

/** Fraction of the weaker parent's base stats folded into the fusion. */
const ABSORB_FRACTION = 0.25;

function mergeStats(strong: DerivedStats, weak: DerivedStats): DerivedStats {
  const blend = (a: number, b: number): number =>
    roundHalfUp(a + b * ABSORB_FRACTION);
  return {
    ...strong,
    maxHp: blend(strong.maxHp, weak.maxHp),
    physicalAttack: blend(strong.physicalAttack, weak.physicalAttack),
    magicAttack: blend(strong.magicAttack, weak.magicAttack),
    defense: blend(strong.defense, weak.defense),
    accuracy: blend(strong.accuracy, weak.accuracy),
    evasion: blend(strong.evasion, weak.evasion),
  };
}

function betterSkill(
  a: SkillInstance | undefined,
  b: SkillInstance | undefined,
): SkillInstance | undefined {
  if (!a) return b;
  if (!b) return a;
  return a.power >= b.power ? a : b;
}

export function fuse(
  a: Companion,
  b: Companion,
  idFactory: EntityIdFactory,
): Companion {
  // Pick the stronger parent as the stat/lineage base.
  const [strong, weak] = companionPower(a) >= companionPower(b) ? [a, b] : [b, a];

  const baseRarity =
    rarityRank(a.rarity) >= rarityRank(b.rarity) ? a.rarity : b.rarity;
  const rarity = nextRarity(baseRarity);
  const shiny = a.shiny || b.shiny;
  const bond = Math.floor(Math.max(a.bond, b.bond) / 2);
  const skill = betterSkill(a.skill, b.skill);

  return {
    id: idFactory.next(),
    sourceMonsterId: strong.sourceMonsterId,
    name: companionTitle(rarity, shiny, strong.baseName),
    baseName: strong.baseName,
    rarity,
    shiny,
    baseStats: mergeStats(strong.baseStats, weak.baseStats),
    bond,
    ...(skill ? { skill } : {}),
  };
}
