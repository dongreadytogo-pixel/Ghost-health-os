/**
 * Branded (nominal) types. TypeScript is structurally typed, so a raw `string`
 * entity id is interchangeable with any other string. Branding prevents passing,
 * say, a MonsterDefId where an ItemDefId is expected — at zero runtime cost.
 */

declare const brand: unique symbol;

export type Brand<T, B extends string> = T & { readonly [brand]: B };

/** Runtime instance of an entity living in a World (player, spawned monster). */
export type EntityId = Brand<string, 'EntityId'>;

/** Stable content identifiers, authored as data and looked up in the registry. */
export type MonsterDefId = Brand<string, 'MonsterDefId'>;
export type ItemDefId = Brand<string, 'ItemDefId'>;
export type AffixDefId = Brand<string, 'AffixDefId'>;
export type ZoneDefId = Brand<string, 'ZoneDefId'>;
export type SkillDefId = Brand<string, 'SkillDefId'>;

export const asMonsterDefId = (value: string): MonsterDefId =>
  value as MonsterDefId;
export const asItemDefId = (value: string): ItemDefId => value as ItemDefId;
export const asAffixDefId = (value: string): AffixDefId => value as AffixDefId;
export const asZoneDefId = (value: string): ZoneDefId => value as ZoneDefId;
export const asSkillDefId = (value: string): SkillDefId => value as SkillDefId;
export const asEntityId = (value: string): EntityId => value as EntityId;
