/**
 * Combatant — a runtime fighting entity living inside a World.
 *
 * It carries resolved `DerivedStats` plus the mutable battle state the
 * simulation advances each tick (current hp, ticks until the next swing). A
 * player and a monster are the same shape, so the combat loop treats them
 * symmetrically; only how their stats are produced differs.
 */

import type { EntityId, MonsterDefId } from '../shared/branded.js';
import { asEntityId } from '../shared/branded.js';
import type { DerivedStats } from '../stats/stats.js';
import type { AttackKind } from '../combat/combat.js';
import type { MonsterDefinition } from '../content/definitions.js';

export type Faction = 'player' | 'enemy';

export interface Combatant {
  readonly id: EntityId;
  readonly name: string;
  readonly faction: Faction;
  readonly stats: DerivedStats;
  readonly attackKind: AttackKind;
  /** Set for spawned monsters; identifies the source definition for loot/exp. */
  readonly sourceId?: MonsterDefId;
  currentHp: number;
  /** Ticks remaining before this combatant may attack again. */
  ticksUntilAttack: number;
}

export const isAlive = (c: Combatant): boolean => c.currentHp > 0;

/** Monotonic id factory so spawned entities never collide within a run. */
export class EntityIdFactory {
  private n = 0;
  constructor(private readonly prefix = 'e') {}
  next(): EntityId {
    this.n += 1;
    return asEntityId(`${this.prefix}-${this.n}`);
  }
}

export function spawnMonster(
  def: MonsterDefinition,
  idFactory: EntityIdFactory,
): Combatant {
  return {
    id: idFactory.next(),
    name: def.name,
    faction: 'enemy',
    stats: def.stats,
    attackKind: 'physical',
    sourceId: def.id,
    currentHp: def.stats.maxHp,
    // Monsters get a head-start equal to one interval so the player strikes first.
    ticksUntilAttack: def.stats.attackIntervalTicks,
  };
}

export function createCombatant(args: {
  id: EntityId;
  name: string;
  faction: Faction;
  stats: DerivedStats;
  attackKind?: AttackKind;
}): Combatant {
  return {
    id: args.id,
    name: args.name,
    faction: args.faction,
    stats: args.stats,
    attackKind: args.attackKind ?? 'physical',
    currentHp: args.stats.maxHp,
    ticksUntilAttack: args.stats.attackIntervalTicks,
  };
}
