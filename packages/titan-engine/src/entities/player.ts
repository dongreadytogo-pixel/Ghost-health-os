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
import type { MountInstance } from '../mounts/mount.js';
import { effectiveItemAttributes } from '../items/upgrade.js';
import { roundHalfUp } from '../shared/math.js';
import {
  addAttributes,
  deriveStats,
  DEFAULT_STAT_FORMULA,
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
  /** Currently-ridden mount, if any. Contributes attributes and attack speed. */
  readonly mount?: MountInstance;
}

export function effectiveAttributes(build: PlayerBuild): Attributes {
  let total = build.allocated;
  for (const item of Object.values(build.equipment)) {
    if (item) total = addAttributes(total, effectiveItemAttributes(item));
  }
  if (build.mount) total = addAttributes(total, build.mount.bonusAttributes);
  return total;
}

export function playerStats(
  build: PlayerBuild,
  config: StatFormulaConfig = DEFAULT_STAT_FORMULA,
): DerivedStats {
  const stats = deriveStats(effectiveAttributes(build), config);
  if (!build.mount) return stats;
  // A mount also speeds up attacks, on top of the agility it grants.
  return {
    ...stats,
    attackIntervalTicks: Math.max(
      config.minAttackIntervalTicks,
      roundHalfUp(stats.attackIntervalTicks * build.mount.attackSpeedMultiplier),
    ),
  };
}

export const emptyBuild = (allocated: Attributes = ZERO_ATTRIBUTES): PlayerBuild => ({
  allocated,
  equipment: {},
});
