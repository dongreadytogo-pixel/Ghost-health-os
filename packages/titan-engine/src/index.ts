/**
 * @titan/engine — Project Titan's deterministic, data-driven idle-MMORPG core.
 *
 * Pure simulation only: no rendering, no networking, no I/O. Every system is
 * seedable and replayable, which is what makes offline progress, server-side
 * validation and exhaustive unit testing possible. Higher layers (a renderer, a
 * server, a persistence adapter) depend inward on this package and never the
 * other way around.
 */

// Shared kernel
export * from './shared/result.js';
export * from './shared/branded.js';
export * from './shared/math.js';
export * from './shared/rng.js';

// Stats & progression
export * from './stats/stats.js';
export * from './progression/leveling.js';

// Content (data-driven definitions + registry)
export * from './content/definitions.js';
export * from './content/rarity.js';
export * from './content/registry.js';
export * from './content/starter-content.js';

// Systems
export * from './combat/combat.js';
export * from './loot/loot.js';
export * from './skills/skill.js';
export * from './mounts/mount.js';
export * from './companions/companion.js';
export * from './companions/capture.js';
export * from './companions/fusion.js';

// Entities
export * from './entities/combatant.js';
export * from './entities/player.js';

// World & simulation
export * from './world/world.js';
export * from './simulation/offline.js';
