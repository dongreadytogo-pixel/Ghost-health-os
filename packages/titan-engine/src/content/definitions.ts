/**
 * Content definitions — the authored, data-driven "content" of the game.
 *
 * Nothing here is behaviour; these are plain, serializable records that a
 * designer (or a JSON file, or a remote-config service) provides. The engine's
 * systems read them. This is the boundary that keeps content expandable without
 * code changes and keeps all original IP — names, lore, numbers — as data, never
 * baked into the simulation.
 */

import type {
  AffixDefId,
  ItemDefId,
  MonsterDefId,
  ZoneDefId,
} from '../shared/branded.js';
import type { Attributes, DerivedStats } from '../stats/stats.js';

export type ItemSlot =
  | 'weapon'
  | 'armor'
  | 'helm'
  | 'accessory'
  | 'material'
  | 'consumable';

export type Rarity =
  | 'common'
  | 'uncommon'
  | 'rare'
  | 'epic'
  | 'legendary'
  | 'mythic';

/** An affix (random prefix/suffix) that an item instance can roll. */
export interface AffixDefinition {
  readonly id: AffixDefId;
  readonly name: string;
  readonly kind: 'prefix' | 'suffix';
  /** Attribute bonuses granted; rolled between min and max at instance time. */
  readonly attributeRange: {
    readonly min: Partial<Attributes>;
    readonly max: Partial<Attributes>;
  };
  /** Relative likelihood of this affix being chosen from a pool. */
  readonly weight: number;
  /** Minimum item rarity required for this affix to appear. */
  readonly minRarity: Rarity;
}

export interface ItemDefinition {
  readonly id: ItemDefId;
  readonly name: string;
  readonly slot: ItemSlot;
  readonly baseRarity: Rarity;
  /** Flat attribute bonus before affixes (e.g. a base weapon's power). */
  readonly baseAttributes: Partial<Attributes>;
  /** Affix pools this item may draw prefixes/suffixes from. */
  readonly affixPool: readonly AffixDefId[];
  /** Approximate gold value, used by the economy / auto-sell systems. */
  readonly value: number;
  readonly stackable: boolean;
}

/** A single weighted entry in a monster's loot table. */
export interface DropEntry {
  readonly itemId: ItemDefId;
  /** Independent drop probability in [0, 1]. */
  readonly chance: number;
  readonly minQuantity: number;
  readonly maxQuantity: number;
}

export interface MonsterDefinition {
  readonly id: MonsterDefId;
  readonly name: string;
  readonly level: number;
  /** Combat stats are authored directly for monsters (no attribute build). */
  readonly stats: DerivedStats;
  readonly experienceReward: number;
  readonly goldReward: { readonly min: number; readonly max: number };
  readonly dropTable: readonly DropEntry[];
  readonly isBoss: boolean;
}

/** A weighted spawn entry for a zone. */
export interface SpawnEntry {
  readonly monsterId: MonsterDefId;
  readonly weight: number;
}

export interface ZoneDefinition {
  readonly id: ZoneDefId;
  readonly name: string;
  readonly recommendedLevel: number;
  readonly spawnTable: readonly SpawnEntry[];
}
