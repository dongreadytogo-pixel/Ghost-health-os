/**
 * ContentRegistry — the single lookup surface for all authored content.
 *
 * Systems never import content directly; they resolve it by id through this
 * registry. That keeps content a swappable plugin: a test registers three
 * monsters, production loads thousands from data, and neither the combat nor
 * loot systems change. Lookups return Result so an unknown id is a typed,
 * recoverable error rather than an `undefined` that explodes later.
 */

import type {
  AffixDefId,
  ItemDefId,
  MonsterDefId,
  ZoneDefId,
} from '../shared/branded.js';
import { fail, ok, type Result } from '../shared/result.js';
import type {
  AffixDefinition,
  ItemDefinition,
  MonsterDefinition,
  ZoneDefinition,
} from './definitions.js';

export interface ContentBundle {
  readonly monsters?: readonly MonsterDefinition[];
  readonly items?: readonly ItemDefinition[];
  readonly affixes?: readonly AffixDefinition[];
  readonly zones?: readonly ZoneDefinition[];
}

export class ContentRegistry {
  private readonly monsters = new Map<MonsterDefId, MonsterDefinition>();
  private readonly items = new Map<ItemDefId, ItemDefinition>();
  private readonly affixes = new Map<AffixDefId, AffixDefinition>();
  private readonly zones = new Map<ZoneDefId, ZoneDefinition>();

  /** Register a bundle of content. Later definitions override earlier ones by id. */
  register(bundle: ContentBundle): this {
    for (const m of bundle.monsters ?? []) this.monsters.set(m.id, m);
    for (const i of bundle.items ?? []) this.items.set(i.id, i);
    for (const a of bundle.affixes ?? []) this.affixes.set(a.id, a);
    for (const z of bundle.zones ?? []) this.zones.set(z.id, z);
    return this;
  }

  monster(id: MonsterDefId): Result<MonsterDefinition> {
    const def = this.monsters.get(id);
    return def
      ? ok(def)
      : fail('UNKNOWN_MONSTER', `No monster registered with id "${id}".`, {
          id,
        });
  }

  item(id: ItemDefId): Result<ItemDefinition> {
    const def = this.items.get(id);
    return def
      ? ok(def)
      : fail('UNKNOWN_ITEM', `No item registered with id "${id}".`, { id });
  }

  affix(id: AffixDefId): Result<AffixDefinition> {
    const def = this.affixes.get(id);
    return def
      ? ok(def)
      : fail('UNKNOWN_AFFIX', `No affix registered with id "${id}".`, { id });
  }

  zone(id: ZoneDefId): Result<ZoneDefinition> {
    const def = this.zones.get(id);
    return def
      ? ok(def)
      : fail('UNKNOWN_ZONE', `No zone registered with id "${id}".`, { id });
  }

  /** Resolve a list of affix ids, skipping any that are unknown. */
  resolveAffixes(ids: readonly AffixDefId[]): AffixDefinition[] {
    const out: AffixDefinition[] = [];
    for (const id of ids) {
      const def = this.affixes.get(id);
      if (def) out.push(def);
    }
    return out;
  }

  get counts(): Readonly<Record<string, number>> {
    return {
      monsters: this.monsters.size,
      items: this.items.size,
      affixes: this.affixes.size,
      zones: this.zones.size,
    };
  }
}
