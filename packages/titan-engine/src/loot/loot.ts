/**
 * Loot — deterministic drop resolution and random-affix item generation.
 *
 * Killing a monster rolls its drop table (independent per-entry chances) and a
 * gold amount; equipment additionally rolls a prefix and/or suffix from its
 * affix pools, each with attribute values drawn between the affix's min and max.
 * Every roll uses the passed Rng, so the same kill with the same generator state
 * always yields the same loot — the foundation for server-validated drops.
 */

import type { Attributes } from '../stats/stats.js';
import { addAttributes, ZERO_ATTRIBUTES } from '../stats/stats.js';
import type { Rng } from '../shared/rng.js';
import type { AffixDefId, ItemDefId } from '../shared/branded.js';
import type { ContentRegistry } from '../content/registry.js';
import type {
  AffixDefinition,
  ItemDefinition,
  MonsterDefinition,
  Rarity,
} from '../content/definitions.js';
import { rarityRank } from '../content/rarity.js';

export interface RolledAffix {
  readonly affixId: AffixDefId;
  readonly name: string;
  readonly attributes: Attributes;
}

/** A concrete, rolled item ready to drop into an inventory. */
export interface ItemInstance {
  readonly defId: ItemDefId;
  readonly name: string;
  readonly rarity: Rarity;
  readonly quantity: number;
  readonly affixes: readonly RolledAffix[];
  /** base attributes + all affix attributes, precomputed for equip math. */
  readonly totalAttributes: Attributes;
}

export interface LootResult {
  readonly gold: number;
  readonly items: readonly ItemInstance[];
}

const partialToAttributes = (p: Partial<Attributes>): Attributes => ({
  ...ZERO_ATTRIBUTES,
  ...p,
});

/** Roll each attribute value of an affix uniformly between its min and max. */
function rollAffix(def: AffixDefinition, rng: Rng): RolledAffix {
  const min = partialToAttributes(def.attributeRange.min);
  const max = partialToAttributes(def.attributeRange.max);
  const roll = (k: keyof Attributes): number =>
    min[k] === max[k] ? min[k] : rng.int(min[k], max[k]);
  const attributes: Attributes = {
    strength: roll('strength'),
    agility: roll('agility'),
    vitality: roll('vitality'),
    intelligence: roll('intelligence'),
    dexterity: roll('dexterity'),
    luck: roll('luck'),
  };
  return { affixId: def.id, name: def.name, attributes };
}

/**
 * Build a concrete item instance, rolling affixes if the item is eligible.
 * Picks at most one prefix and one suffix from the item's pool, respecting each
 * affix's minimum-rarity gate.
 */
export function rollItemInstance(
  def: ItemDefinition,
  quantity: number,
  registry: ContentRegistry,
  rng: Rng,
): ItemInstance {
  const pool = registry
    .resolveAffixes(def.affixPool)
    .filter((a) => rarityRank(def.baseRarity) >= rarityRank(a.minRarity));

  const prefixes = pool.filter((a) => a.kind === 'prefix');
  const suffixes = pool.filter((a) => a.kind === 'suffix');

  const chosen: AffixDefinition[] = [];
  const prefix = rng.weighted(prefixes.map((a) => ({ item: a, weight: a.weight })));
  if (prefix) chosen.push(prefix);
  const suffix = rng.weighted(suffixes.map((a) => ({ item: a, weight: a.weight })));
  if (suffix) chosen.push(suffix);

  const affixes = chosen.map((a) => rollAffix(a, rng));

  let total = partialToAttributes(def.baseAttributes);
  for (const a of affixes) total = addAttributes(total, a.attributes);

  return {
    defId: def.id,
    name: def.name,
    rarity: def.baseRarity,
    quantity,
    affixes,
    totalAttributes: total,
  };
}

/** Roll a monster's full loot: gold plus every dropped item instance. */
export function rollLoot(
  monster: MonsterDefinition,
  registry: ContentRegistry,
  rng: Rng,
): LootResult {
  const gold = rng.int(monster.goldReward.min, monster.goldReward.max);
  const items: ItemInstance[] = [];

  for (const entry of monster.dropTable) {
    if (!rng.chance(entry.chance)) continue;
    const def = registry.item(entry.itemId);
    if (!def.ok) continue; // unknown item id — skip rather than crash
    const quantity = rng.int(entry.minQuantity, entry.maxQuantity);
    if (quantity <= 0) continue;
    items.push(rollItemInstance(def.value, quantity, registry, rng));
  }

  return { gold, items };
}
