/**
 * World — the deterministic auto-battle idle loop.
 *
 * One `tick()` advances the whole game by a single simulation step and returns
 * the events that happened, so the loop is observable, replayable and
 * server-verifiable. The loop implements the brief's core flow:
 *
 *   spawn a monster → auto-attack on cooldown → on kill: roll loot, grant gold
 *   and experience → level up (auto-allocating awarded points, then healing) →
 *   spawn the next monster — forever, with no player input.
 *
 * All randomness flows through the World's own Rng, whose state is part of the
 * snapshot, so saving and restoring a World reproduces the exact future.
 */

import type { Rng } from '../shared/rng.js';
import { asEntityId } from '../shared/branded.js';
import type { ContentRegistry } from '../content/registry.js';
import type { ZoneDefinition } from '../content/definitions.js';
import {
  resolveAttack,
  DEFAULT_COMBAT,
  type CombatConfig,
  type AttackOutcome,
} from '../combat/combat.js';
import { rollLoot, type ItemInstance } from '../loot/loot.js';
import {
  applyExperience,
  DEFAULT_LEVELING,
  type LevelingConfig,
  type ProgressState,
} from '../progression/leveling.js';
import {
  DEFAULT_STAT_FORMULA,
  addAttributes,
  type Attributes,
  type StatFormulaConfig,
} from '../stats/stats.js';
import {
  createCombatant,
  spawnMonster,
  isAlive,
  EntityIdFactory,
  type Combatant,
} from '../entities/combatant.js';
import { playerStats, type PlayerBuild } from '../entities/player.js';

/** Strategy for spending the attribute points a level-up awards. */
export type AllocationStrategy = (points: number) => Attributes;

/** Default: spread points as evenly as possible across all six attributes. */
export const evenAllocation: AllocationStrategy = (points) => {
  const base = Math.floor(points / 6);
  let remainder = points - base * 6;
  const take = (): number => {
    const extra = remainder > 0 ? 1 : 0;
    remainder -= extra;
    return base + extra;
  };
  return {
    strength: take(),
    agility: take(),
    vitality: take(),
    intelligence: take(),
    dexterity: take(),
    luck: take(),
  };
};

export interface WorldConfig {
  readonly combat: CombatConfig;
  readonly leveling: LevelingConfig;
  readonly statFormula: StatFormulaConfig;
  readonly allocation: AllocationStrategy;
}

export const DEFAULT_WORLD_CONFIG: WorldConfig = {
  combat: DEFAULT_COMBAT,
  leveling: DEFAULT_LEVELING,
  statFormula: DEFAULT_STAT_FORMULA,
  allocation: evenAllocation,
};

export type WorldEvent =
  | { readonly type: 'spawn'; readonly monster: string; readonly hp: number }
  | {
      readonly type: 'attack';
      readonly attacker: 'player' | 'enemy';
      readonly outcome: AttackOutcome;
      readonly targetHpAfter: number;
    }
  | {
      readonly type: 'kill';
      readonly monster: string;
      readonly experience: number;
      readonly gold: number;
    }
  | { readonly type: 'loot'; readonly items: readonly ItemInstance[] }
  | {
      readonly type: 'levelUp';
      readonly level: number;
      readonly levelsGained: number;
    }
  | { readonly type: 'playerDefeated'; readonly byMonster: string };

export interface PlayerSnapshot {
  readonly build: PlayerBuild;
  readonly progress: ProgressState;
  readonly gold: number;
  readonly currentHp: number;
  readonly maxHp: number;
  readonly inventory: readonly ItemInstance[];
}

export class World {
  private player: Combatant;
  private build: PlayerBuild;
  private progress: ProgressState;
  private gold = 0;
  private readonly inventory: ItemInstance[] = [];
  private target: Combatant | undefined;
  private tickCount = 0;
  private readonly ids = new EntityIdFactory('m');
  private readonly playerId = asEntityId('player');

  constructor(
    private readonly registry: ContentRegistry,
    private readonly zone: ZoneDefinition,
    private readonly rng: Rng,
    initialBuild: PlayerBuild,
    private readonly config: WorldConfig = DEFAULT_WORLD_CONFIG,
    initialProgress: ProgressState = { level: 1, currentExp: 0 },
  ) {
    this.build = initialBuild;
    this.progress = initialProgress;
    this.player = this.buildPlayerCombatant(true);
  }

  // --- public surface -------------------------------------------------------

  /** Advance the simulation by one tick; returns everything that happened. */
  tick(): WorldEvent[] {
    const events: WorldEvent[] = [];
    this.tickCount += 1;

    this.ensureTarget(events);
    const enemy = this.target;
    if (!enemy) return events; // zone has no spawns

    // Player acts first when its cooldown elapses.
    this.player.ticksUntilAttack -= 1;
    if (this.player.ticksUntilAttack <= 0 && isAlive(enemy)) {
      this.player.ticksUntilAttack = this.player.stats.attackIntervalTicks;
      const outcome = resolveAttack(
        this.player.stats,
        enemy.stats,
        this.rng,
        this.player.attackKind,
        this.config.combat,
      );
      enemy.currentHp = Math.max(0, enemy.currentHp - outcome.damage);
      events.push({
        type: 'attack',
        attacker: 'player',
        outcome,
        targetHpAfter: enemy.currentHp,
      });
      if (!isAlive(enemy)) {
        this.handleKill(enemy, events);
        return events;
      }
    }

    // Enemy retaliates when its own cooldown elapses.
    enemy.ticksUntilAttack -= 1;
    if (enemy.ticksUntilAttack <= 0) {
      enemy.ticksUntilAttack = enemy.stats.attackIntervalTicks;
      const outcome = resolveAttack(
        enemy.stats,
        this.player.stats,
        this.rng,
        enemy.attackKind,
        this.config.combat,
      );
      this.player.currentHp = Math.max(0, this.player.currentHp - outcome.damage);
      events.push({
        type: 'attack',
        attacker: 'enemy',
        outcome,
        targetHpAfter: this.player.currentHp,
      });
      if (!isAlive(this.player)) {
        events.push({ type: 'playerDefeated', byMonster: enemy.name });
        // Idle retreat: recover fully and abandon the current fight.
        this.player.currentHp = this.player.stats.maxHp;
        this.player.ticksUntilAttack = this.player.stats.attackIntervalTicks;
        this.target = undefined;
      }
    }

    return events;
  }

  /** Run `n` ticks, returning the flattened event log. */
  run(n: number): WorldEvent[] {
    const all: WorldEvent[] = [];
    for (let i = 0; i < n; i++) all.push(...this.tick());
    return all;
  }

  snapshot(): PlayerSnapshot {
    return {
      build: this.build,
      progress: this.progress,
      gold: this.gold,
      currentHp: this.player.currentHp,
      maxHp: this.player.stats.maxHp,
      inventory: [...this.inventory],
    };
  }

  get ticksElapsed(): number {
    return this.tickCount;
  }

  // --- internals ------------------------------------------------------------

  private ensureTarget(events: WorldEvent[]): void {
    if (this.target && isAlive(this.target)) return;
    const entry = this.rng.weighted(
      this.zone.spawnTable.map((s) => ({ item: s.monsterId, weight: s.weight })),
    );
    if (!entry) {
      this.target = undefined;
      return;
    }
    const def = this.registry.monster(entry);
    if (!def.ok) {
      this.target = undefined;
      return;
    }
    this.target = spawnMonster(def.value, this.ids);
    events.push({
      type: 'spawn',
      monster: this.target.name,
      hp: this.target.currentHp,
    });
  }

  private handleKill(enemy: Combatant, events: WorldEvent[]): void {
    const def = enemy.sourceId && this.registry.monster(enemy.sourceId);
    const exp = def && def.ok ? def.value.experienceReward : 0;
    const loot =
      def && def.ok
        ? rollLoot(def.value, this.registry, this.rng)
        : { gold: 0, items: [] as ItemInstance[] };

    this.gold += loot.gold;
    this.inventory.push(...loot.items);

    events.push({
      type: 'kill',
      monster: enemy.name,
      experience: exp,
      gold: loot.gold,
    });
    if (loot.items.length > 0) events.push({ type: 'loot', items: loot.items });

    const result = applyExperience(this.progress, exp, this.config.leveling);
    this.progress = result.state;
    if (result.levelsGained > 0) {
      this.build = {
        allocated: addAttributes(
          this.build.allocated,
          this.config.allocation(result.attributePointsAwarded),
        ),
        equipment: this.build.equipment,
      };
      // Rebuild stats from the stronger build and heal to full on level up.
      this.player = this.buildPlayerCombatant(true);
      events.push({
        type: 'levelUp',
        level: this.progress.level,
        levelsGained: result.levelsGained,
      });
    }

    this.target = undefined;
  }

  /**
   * Build the player combatant from the current build. When `healFull` is false
   * the previous current-hp is carried over (clamped to the new max), used when
   * stats change without a heal.
   */
  private buildPlayerCombatant(healFull: boolean): Combatant {
    const stats = playerStats(this.build, this.config.statFormula);
    const previousHp = this.player?.currentHp ?? stats.maxHp;
    const c = createCombatant({
      id: this.playerId,
      name: 'Hero',
      faction: 'player',
      stats,
    });
    c.currentHp = healFull ? stats.maxHp : Math.min(previousHp, stats.maxHp);
    return c;
  }
}
