/**
 * Starter content pack — a small, original, fully-data-driven bundle used by
 * tests, demos and the first playable zone. Every name and number here is
 * authored data; none of it is referenced by the simulation systems directly.
 * Replace or extend it by registering more bundles — nothing in the engine is
 * coupled to these specific ids.
 */

import {
  asAffixDefId,
  asItemDefId,
  asMonsterDefId,
  asMountDefId,
  asSkillDefId,
  asZoneDefId,
} from '../shared/branded.js';
import { deriveStats } from '../stats/stats.js';
import type { ContentBundle } from './registry.js';
import type {
  AffixDefinition,
  ItemDefinition,
  MonsterDefinition,
  ZoneDefinition,
} from './definitions.js';
import type { MountDefinition } from '../mounts/mount.js';
import type { SkillDefinition } from '../skills/skill.js';

const affixes: AffixDefinition[] = [
  {
    id: asAffixDefId('honed'),
    name: 'Honed',
    kind: 'prefix',
    attributeRange: { min: { strength: 1 }, max: { strength: 4 } },
    weight: 10,
    minRarity: 'common',
  },
  {
    id: asAffixDefId('swift'),
    name: 'Swift',
    kind: 'prefix',
    attributeRange: { min: { agility: 1 }, max: { agility: 4 } },
    weight: 10,
    minRarity: 'common',
  },
  {
    id: asAffixDefId('of_the_bear'),
    name: 'of the Bear',
    kind: 'suffix',
    attributeRange: { min: { vitality: 2 }, max: { vitality: 6 } },
    weight: 8,
    minRarity: 'uncommon',
  },
  {
    id: asAffixDefId('of_fortune'),
    name: 'of Fortune',
    kind: 'suffix',
    attributeRange: { min: { luck: 2 }, max: { luck: 8 } },
    weight: 4,
    minRarity: 'rare',
  },
];

const items: ItemDefinition[] = [
  {
    id: asItemDefId('worn_blade'),
    name: 'Worn Blade',
    slot: 'weapon',
    baseRarity: 'common',
    baseAttributes: { strength: 4, dexterity: 2 },
    affixPool: [asAffixDefId('honed'), asAffixDefId('swift')],
    value: 20,
    stackable: false,
  },
  {
    id: asItemDefId('travelers_vest'),
    name: "Traveler's Vest",
    slot: 'armor',
    baseRarity: 'common',
    baseAttributes: { vitality: 3 },
    affixPool: [asAffixDefId('of_the_bear'), asAffixDefId('of_fortune')],
    value: 18,
    stackable: false,
  },
  {
    id: asItemDefId('slime_residue'),
    name: 'Slime Residue',
    slot: 'material',
    baseRarity: 'common',
    baseAttributes: {},
    affixPool: [],
    value: 2,
    stackable: true,
  },
];

const monsters: MonsterDefinition[] = [
  {
    id: asMonsterDefId('meadow_crawler'),
    name: 'Meadow Crawler',
    level: 1,
    stats: deriveStats({
      strength: 3,
      agility: 2,
      vitality: 2,
      intelligence: 0,
      dexterity: 2,
      luck: 1,
    }),
    experienceReward: 12,
    goldReward: { min: 1, max: 4 },
    dropTable: [
      {
        itemId: asItemDefId('slime_residue'),
        chance: 0.6,
        minQuantity: 1,
        maxQuantity: 2,
      },
      {
        itemId: asItemDefId('worn_blade'),
        chance: 0.05,
        minQuantity: 1,
        maxQuantity: 1,
      },
    ],
    isBoss: false,
  },
  {
    id: asMonsterDefId('thicket_stalker'),
    name: 'Thicket Stalker',
    level: 3,
    stats: deriveStats({
      strength: 6,
      agility: 5,
      vitality: 4,
      intelligence: 0,
      dexterity: 5,
      luck: 2,
    }),
    experienceReward: 28,
    goldReward: { min: 3, max: 9 },
    dropTable: [
      {
        itemId: asItemDefId('travelers_vest'),
        chance: 0.08,
        minQuantity: 1,
        maxQuantity: 1,
      },
    ],
    isBoss: false,
  },
];

const zones: ZoneDefinition[] = [
  {
    id: asZoneDefId('verdant_fringe'),
    name: 'Verdant Fringe',
    recommendedLevel: 1,
    spawnTable: [
      { monsterId: asMonsterDefId('meadow_crawler'), weight: 8 },
      { monsterId: asMonsterDefId('thicket_stalker'), weight: 2 },
    ],
  },
];

/**
 * Mounts and skills are not part of the registry's ContentBundle (they are
 * rolled into instances at runtime), so they're exported as plain definition
 * lists for callers to roll from.
 */
export const STARTER_MOUNTS: readonly MountDefinition[] = [
  {
    id: asMountDefId('dawnstrider'),
    name: 'Dawnstrider',
    baseBonus: { agility: 4, strength: 2 },
    baseSpeedBonus: 0.1,
  },
  {
    id: asMountDefId('emberhoof'),
    name: 'Emberhoof',
    baseBonus: { strength: 5, vitality: 2 },
    baseSpeedBonus: 0.06,
  },
];

export const STARTER_SKILLS: readonly SkillDefinition[] = [
  {
    id: asSkillDefId('cleave'),
    name: 'Cleave',
    kind: 'burst',
    baseCooldownTicks: 60,
    basePower: 3,
  },
  {
    id: asSkillDefId('flurry'),
    name: 'Flurry',
    kind: 'multistrike',
    baseCooldownTicks: 45,
    basePower: 0.9,
    hits: 3,
  },
  {
    id: asSkillDefId('siphon'),
    name: 'Siphon Strike',
    kind: 'lifesteal',
    baseCooldownTicks: 50,
    basePower: 2,
    lifestealFraction: 0.5,
  },
  {
    id: asSkillDefId('mend'),
    name: 'Mend',
    kind: 'heal',
    baseCooldownTicks: 90,
    basePower: 0.25,
  },
];

export const STARTER_CONTENT: ContentBundle = { affixes, items, monsters, zones };
