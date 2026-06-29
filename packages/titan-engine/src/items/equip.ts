/**
 * Equipment & economy helpers — the pure decisions behind auto-equip and
 * auto-sell.
 *
 * `itemPower` gives a single comparable score so the auto-equip system can ask
 * "is this drop better than what I'm wearing?", and `sellValue` prices anything
 * the hero doesn't keep. No state here; the World applies these each kill.
 */

import { roundHalfUp } from '../shared/math.js';
import { rarityRank, totalMultiplier } from '../content/rarity.js';
import type { ItemSlot } from '../content/definitions.js';
import type { ItemInstance } from '../loot/loot.js';
import { effectiveItemAttributes, upgradeLevelOf } from './upgrade.js';
import type { Attributes } from '../stats/stats.js';

/** Slots the hero actually wears (the rest are materials/consumables). */
const EQUIP_SLOTS: ReadonlySet<ItemSlot> = new Set<ItemSlot>([
  'weapon',
  'armor',
  'helm',
  'accessory',
]);

export const isEquippable = (slot: ItemSlot): boolean => EQUIP_SLOTS.has(slot);

const sumAttributes = (a: Attributes): number =>
  a.strength + a.agility + a.vitality + a.intelligence + a.dexterity + a.luck;

/** A single comparable power score for an item, upgrades and rarity included. */
export function itemPower(item: ItemInstance): number {
  return (
    sumAttributes(effectiveItemAttributes(item)) +
    rarityRank(item.rarity) * 5 +
    upgradeLevelOf(item) * 2
  );
}

/** True if `candidate` should replace `current` in its slot. */
export function isUpgradeOver(
  candidate: ItemInstance,
  current: ItemInstance | undefined,
): boolean {
  if (!current) return true;
  return itemPower(candidate) > itemPower(current);
}

/** Gold an item fetches when auto-sold (scales with base value and rarity). */
export function sellValue(item: ItemInstance, baseValue: number): number {
  const upgradeBonus = 1 + upgradeLevelOf(item) * 0.25;
  return roundHalfUp(
    baseValue *
      totalMultiplier(item.rarity, false) *
      upgradeBonus *
      Math.max(1, item.quantity),
  );
}
