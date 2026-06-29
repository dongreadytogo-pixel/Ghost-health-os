/**
 * Player build — composes a player's effective attributes (and thus stats) from
 * a free-form attribute allocation plus equipped item instances.
 *
 * There is no fixed class: the player simply distributes attribute points and
 * equips gear. Total attributes = allocated + every equipped item's rolled
 * totals, which then flow through the same `deriveStats` formula monsters skip.
 * This is the data-driven, classless, hybrid-build core the brief calls for.
 */

import type { ItemSlot } from '../content/definitions.js';
import type { ItemInstance } from '../loot/loot.js';
import {
  addAttributes,
  deriveStats,
  ZERO_ATTRIBUTES,
  type Attributes,
  type DerivedStats,
  type StatFormulaConfig,
} from '../stats/stats.js';

/** Equipment is a slot → item map; only attribute-bearing slots matter here. */
export type Equipment = Partial<Record<ItemSlot, ItemInstance>>;

export interface PlayerBuild {
  readonly allocated: Attributes;
  readonly equipment: Equipment;
}

export function effectiveAttributes(build: PlayerBuild): Attributes {
  let total = build.allocated;
  for (const item of Object.values(build.equipment)) {
    if (item) total = addAttributes(total, item.totalAttributes);
  }
  return total;
}

export function playerStats(
  build: PlayerBuild,
  config?: StatFormulaConfig,
): DerivedStats {
  return deriveStats(effectiveAttributes(build), config);
}

export const emptyBuild = (allocated: Attributes = ZERO_ATTRIBUTES): PlayerBuild => ({
  allocated,
  equipment: {},
});
