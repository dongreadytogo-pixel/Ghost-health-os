/**
 * Item upgrade / enchant — spend gold to make a piece of gear stronger.
 *
 * An item's upgrade level multiplies its rolled attributes by a flat bonus per
 * level. Cost grows geometrically with the current level and with rarity, so a
 * Mythic item is expensive to push but worth it. Pure functions throughout; the
 * economy (where the gold comes from) lives in the World's auto-upgrade system.
 */

import { roundHalfUp } from '../shared/math.js';
import { rarityRank } from '../content/rarity.js';
import type { ItemInstance } from '../loot/loot.js';
import type { Attributes } from '../stats/stats.js';

export interface UpgradeConfig {
  /** Fractional attribute bonus per upgrade level (0.1 = +10% per level). */
  readonly bonusPerLevel: number;
  /** Base gold cost for the first upgrade of a common item. */
  readonly baseCost: number;
  /** Geometric cost growth per level. */
  readonly costGrowth: number;
  readonly maxLevel: number;
}

export const DEFAULT_UPGRADE: UpgradeConfig = Object.freeze({
  bonusPerLevel: 0.1,
  baseCost: 40,
  costGrowth: 1.45,
  maxLevel: 20,
});

export const upgradeLevelOf = (item: ItemInstance): number =>
  item.upgradeLevel ?? 0;

/** Gold required to take an item from its current level to the next. */
export function upgradeCost(
  item: ItemInstance,
  config: UpgradeConfig = DEFAULT_UPGRADE,
): number {
  const level = upgradeLevelOf(item);
  const rarityFactor = 1 + rarityRank(item.rarity);
  return roundHalfUp(
    config.baseCost * rarityFactor * Math.pow(config.costGrowth, level),
  );
}

export const canUpgrade = (
  item: ItemInstance,
  config: UpgradeConfig = DEFAULT_UPGRADE,
): boolean => upgradeLevelOf(item) < config.maxLevel;

/** Item attributes with the upgrade bonus applied — what equip math should read. */
export function effectiveItemAttributes(
  item: ItemInstance,
  config: UpgradeConfig = DEFAULT_UPGRADE,
): Attributes {
  const level = upgradeLevelOf(item);
  if (level <= 0) return item.totalAttributes;
  const mult = 1 + level * config.bonusPerLevel;
  const scale = (v: number): number => roundHalfUp(v * mult);
  const a = item.totalAttributes;
  return {
    strength: scale(a.strength),
    agility: scale(a.agility),
    vitality: scale(a.vitality),
    intelligence: scale(a.intelligence),
    dexterity: scale(a.dexterity),
    luck: scale(a.luck),
  };
}

/** Produce a copy of the item one upgrade level higher (no cost check). */
export function upgradeItem(item: ItemInstance): ItemInstance {
  return { ...item, upgradeLevel: upgradeLevelOf(item) + 1 };
}
