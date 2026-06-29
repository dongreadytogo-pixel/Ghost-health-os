/**
 * World — the deterministic auto-battle idle loop.
 *
 * One `tick()` advances the whole game by a single simulation step and returns
 * the events that happened, so the loop is observable, replayable and
 * server-verifiable. The loop implements the brief's core flow plus its party
 * fantasy:
 *
 *   spawn a monster → the hero (riding a mount) and the companions walking
 *   behind it auto-attack and auto-cast skills on their own cooldowns → on kill:
 *   roll loot, grant gold & experience, level up, deepen the party's bond, maybe
 *   tame the fallen monster into a new companion, and auto-fuse duplicates into
 *   something rarer → spawn the next monster — forever, with no player input.
 *
 * All randomness flows through the World's own Rng, whose state is part of the
 * snapshot, so saving and restoring a World reproduces the exact future.
 */

import { Rng, type RngState } from '../shared/rng.js';
import {
  asEntityId,
  type EntityId,
  type ZoneDefId,
} from '../shared/branded.js';
import { roundHalfUp } from '../shared/math.js';
import type { ContentRegistry } from '../content/registry.js';
import type {
  MonsterDefinition,
  Rarity,
  ZoneDefinition,
} from '../content/definitions.js';
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
import { castSkill, type SkillInstance } from '../skills/skill.js';
import {
  companionStats,
  companionPower,
  gainBond,
  DEFAULT_BOND,
  type BondConfig,
  type Companion,
} from '../companions/companion.js';
import {
  tryCapture,
  DEFAULT_CAPTURE,
  type CaptureConfig,
} from '../companions/capture.js';
import { fuse } from '../companions/fusion.js';

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
  readonly capture: CaptureConfig;
  readonly bond: BondConfig;
  /** How many companions can actively fight beside the hero. */
  readonly maxPartySize: number;
  /** Outgoing-damage bonus per active companion (team aura). */
  readonly synergyPerCompanion: number;
  /** Extra damage bonus when the whole active party shares one rarity. */
  readonly sameRaritySynergyBonus: number;
  /** Auto-fuse duplicate-rarity companions into a rarer one during play. */
  readonly autoFuse: boolean;
  /** Hard cap on owned companions; weakest are auto-recycled beyond it. */
  readonly maxRosterSize: number;
  /** Hard cap on stored loot; oldest items are auto-recycled beyond it. */
  readonly maxInventorySize: number;
}

export const DEFAULT_WORLD_CONFIG: WorldConfig = {
  combat: DEFAULT_COMBAT,
  leveling: DEFAULT_LEVELING,
  statFormula: DEFAULT_STAT_FORMULA,
  allocation: evenAllocation,
  capture: DEFAULT_CAPTURE,
  bond: DEFAULT_BOND,
  maxPartySize: 3,
  synergyPerCompanion: 0.05,
  sameRaritySynergyBonus: 0.15,
  autoFuse: true,
  maxRosterSize: 24,
  maxInventorySize: 200,
};

export interface WorldSetup {
  /** The hero's auto-cast skill loadout. */
  readonly skills?: readonly SkillInstance[];
  /** Companions already owned at the start (e.g. restored from a save). */
  readonly party?: readonly Companion[];
  /** Starting gold (used when restoring a save). */
  readonly gold?: number;
  /** Starting inventory (used when restoring a save). */
  readonly inventory?: readonly ItemInstance[];
  /** Ticks already elapsed (used when restoring a save). */
  readonly ticksElapsed?: number;
}

/** A complete, JSON-serializable snapshot of a World for cloud/local save. */
export interface WorldSave {
  readonly version: 1;
  readonly zoneId: ZoneDefId;
  readonly rngState: RngState;
  readonly build: PlayerBuild;
  readonly progress: ProgressState;
  readonly gold: number;
  readonly inventory: readonly ItemInstance[];
  readonly skills: readonly SkillInstance[];
  readonly roster: readonly Companion[];
  readonly ticksElapsed: number;
}

export type WorldEvent =
  | { readonly type: 'spawn'; readonly monster: string; readonly hp: number }
  | {
      readonly type: 'attack';
      readonly attacker: 'player' | 'enemy';
      readonly outcome: AttackOutcome;
      readonly targetHpAfter: number;
    }
  | {
      readonly type: 'companionAttack';
      readonly companion: string;
      readonly outcome: AttackOutcome;
      readonly targetHpAfter: number;
    }
  | {
      readonly type: 'skill';
      readonly caster: string;
      readonly skill: string;
      readonly damage: number;
      readonly heal: number;
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
  | {
      readonly type: 'companionJoined';
      readonly companion: string;
      readonly rarity: Rarity;
      readonly shiny: boolean;
    }
  | {
      readonly type: 'fusion';
      readonly result: string;
      readonly rarity: Rarity;
      readonly shiny: boolean;
    }
  | { readonly type: 'playerDefeated'; readonly byMonster: string };

export interface PlayerSnapshot {
  readonly build: PlayerBuild;
  readonly progress: ProgressState;
  readonly gold: number;
  readonly currentHp: number;
  readonly maxHp: number;
  readonly inventory: readonly ItemInstance[];
  readonly skills: readonly SkillInstance[];
  /** Companions currently fighting (top by power, up to maxPartySize). */
  readonly party: readonly Companion[];
  /** Every companion owned (active + reserve). */
  readonly roster: readonly Companion[];
}

export class World {
  private player: Combatant;
  private build: PlayerBuild;
  private progress: ProgressState;
  private gold = 0;
  private readonly inventory: ItemInstance[] = [];
  private readonly skills: SkillInstance[];
  private readonly skillCooldowns: number[];
  private roster: Companion[];
  private readonly companionAttackCd = new Map<EntityId, number>();
  private readonly companionSkillCd = new Map<EntityId, number>();
  // Active-party cache: the party only changes when the roster does, so we
  // recompute the (sorted) party and synergy multiplier lazily rather than on
  // every friendly hit — critical for fast offline fast-forwarding.
  private rosterVersion = 0;
  private cacheVersion = -1;
  private cachedParty: Companion[] = [];
  private cachedMult = 1;
  private target: Combatant | undefined;
  private tickCount = 0;
  private readonly ids = new EntityIdFactory('m');
  private readonly companionIds = new EntityIdFactory('c');
  private readonly playerId = asEntityId('player');

  constructor(
    private readonly registry: ContentRegistry,
    private readonly zone: ZoneDefinition,
    private readonly rng: Rng,
    initialBuild: PlayerBuild,
    private readonly config: WorldConfig = DEFAULT_WORLD_CONFIG,
    initialProgress: ProgressState = { level: 1, currentExp: 0 },
    setup: WorldSetup = {},
  ) {
    this.build = initialBuild;
    this.progress = initialProgress;
    this.skills = setup.skills ? [...setup.skills] : [];
    this.skillCooldowns = this.skills.map(() => 0);
    this.roster = setup.party ? [...setup.party] : [];
    this.gold = setup.gold ?? 0;
    if (setup.inventory) this.inventory.push(...setup.inventory);
    this.tickCount = setup.ticksElapsed ?? 0;
    this.player = this.buildPlayerCombatant(true);
  }

  /** Reconstruct a World from a saved snapshot (resumes the exact stream). */
  static fromSave(
    registry: ContentRegistry,
    zone: ZoneDefinition,
    save: WorldSave,
    config: WorldConfig = DEFAULT_WORLD_CONFIG,
  ): World {
    return new World(
      registry,
      zone,
      Rng.restore(save.rngState),
      save.build,
      config,
      save.progress,
      {
        skills: save.skills,
        party: save.roster,
        gold: save.gold,
        inventory: save.inventory,
        ticksElapsed: save.ticksElapsed,
      },
    );
  }

  // --- public surface -------------------------------------------------------

  /** Advance the simulation by one tick; returns everything that happened. */
  tick(): WorldEvent[] {
    const events: WorldEvent[] = [];
    this.tickCount += 1;

    // Skill cooldowns tick down every step, fight or not.
    for (let i = 0; i < this.skillCooldowns.length; i++) {
      const cd = this.skillCooldowns[i] ?? 0;
      if (cd > 0) this.skillCooldowns[i] = cd - 1;
    }

    this.ensureTarget(events);
    const enemy = this.target;
    if (!enemy) return events; // zone has no spawns

    // 1) Hero basic attack.
    this.player.ticksUntilAttack -= 1;
    if (this.player.ticksUntilAttack <= 0 && isAlive(enemy)) {
      this.player.ticksUntilAttack = this.player.stats.attackIntervalTicks;
      const raw = resolveAttack(
        this.player.stats,
        enemy.stats,
        this.rng,
        this.player.attackKind,
        this.config.combat,
      );
      const outcome = this.dealToEnemy(enemy, raw);
      events.push({
        type: 'attack',
        attacker: 'player',
        outcome,
        targetHpAfter: enemy.currentHp,
      });
      if (!isAlive(enemy)) return this.finishKill(enemy, events);
    }

    // 2) Hero auto-casts at most one ready skill.
    if (isAlive(enemy)) {
      this.castReadyPlayerSkill(enemy, events);
      if (!isAlive(enemy)) return this.finishKill(enemy, events);
    }

    // 3) Companions attack / cast on their own cadence.
    if (isAlive(enemy)) {
      this.runCompanions(enemy, events);
      if (!isAlive(enemy)) return this.finishKill(enemy, events);
    }

    // 4) Enemy retaliates against the hero (companions stay out of reach).
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
      skills: [...this.skills],
      party: [...this.activeParty()],
      roster: [...this.roster],
    };
  }

  get ticksElapsed(): number {
    return this.tickCount;
  }

  /** Lightweight hero vitals for rendering (no allocation of the full snapshot). */
  get hero(): { readonly currentHp: number; readonly maxHp: number } {
    return { currentHp: this.player.currentHp, maxHp: this.player.stats.maxHp };
  }

  /** Cheap, allocation-light vitals for a high-frequency render loop. */
  get vitals(): {
    readonly level: number;
    readonly currentExp: number;
    readonly gold: number;
    readonly inventoryCount: number;
    readonly party: readonly Companion[];
    readonly roster: readonly Companion[];
    readonly mount: PlayerBuild['mount'];
  } {
    return {
      level: this.progress.level,
      currentExp: this.progress.currentExp,
      gold: this.gold,
      inventoryCount: this.inventory.length,
      party: [...this.activeParty()],
      roster: [...this.roster],
      mount: this.build.mount,
    };
  }

  /** The monster currently being fought, for rendering, or undefined. */
  get enemy():
    | { readonly name: string; readonly currentHp: number; readonly maxHp: number }
    | undefined {
    return this.target
      ? {
          name: this.target.name,
          currentHp: this.target.currentHp,
          maxHp: this.target.stats.maxHp,
        }
      : undefined;
  }

  /** Capture a complete, JSON-serializable save (includes RNG state). */
  serialize(): WorldSave {
    return {
      version: 1,
      zoneId: this.zone.id,
      rngState: this.rng.snapshot(),
      build: this.build,
      progress: this.progress,
      gold: this.gold,
      inventory: [...this.inventory],
      skills: [...this.skills],
      roster: [...this.roster],
      ticksElapsed: this.tickCount,
    };
  }

  // --- combat helpers -------------------------------------------------------

  /** Mark the roster as changed so the party cache is rebuilt on next read. */
  private touchRoster(): void {
    this.rosterVersion += 1;
  }

  private refreshPartyCache(): void {
    if (this.cacheVersion === this.rosterVersion) return;
    this.cachedParty = this.computeActiveParty();
    this.cachedMult = this.computeDamageMultiplier(this.cachedParty);
    this.cacheVersion = this.rosterVersion;
  }

  private computeActiveParty(): Companion[] {
    if (this.roster.length <= this.config.maxPartySize) return [...this.roster];
    return [...this.roster]
      .sort(
        (a, b) =>
          companionPower(b, this.config.bond) - companionPower(a, this.config.bond),
      )
      .slice(0, this.config.maxPartySize);
  }

  private computeDamageMultiplier(party: readonly Companion[]): number {
    let mult = 1 + party.length * this.config.synergyPerCompanion;
    if (party.length >= 2 && party.every((c) => c.rarity === party[0]!.rarity)) {
      mult += this.config.sameRaritySynergyBonus;
    }
    return mult;
  }

  /** The companions currently strong enough to fight (top N by power). */
  private activeParty(): Companion[] {
    this.refreshPartyCache();
    return this.cachedParty;
  }

  /** Team-aura multiplier applied to all friendly outgoing damage. */
  private partyDamageMultiplier(): number {
    this.refreshPartyCache();
    return this.cachedMult;
  }

  /** Apply a friendly hit's damage (with synergy) to the enemy. */
  private dealToEnemy(enemy: Combatant, raw: AttackOutcome): AttackOutcome {
    const damage = roundHalfUp(raw.damage * this.partyDamageMultiplier());
    enemy.currentHp = Math.max(0, enemy.currentHp - damage);
    return { ...raw, damage };
  }

  private castReadyPlayerSkill(enemy: Combatant, events: WorldEvent[]): void {
    for (let i = 0; i < this.skills.length; i++) {
      if ((this.skillCooldowns[i] ?? 0) > 0) continue;
      const skill = this.skills[i]!;
      this.castSkillInstance(this.player.stats, 'player', skill, enemy, events);
      this.skillCooldowns[i] = skill.cooldownTicks;
      return; // one skill per tick keeps bursts in check
    }
  }

  private runCompanions(enemy: Combatant, events: WorldEvent[]): void {
    for (const c of this.activeParty()) {
      const stats = companionStats(c, this.config.bond);

      let cd = this.companionAttackCd.get(c.id) ?? stats.attackIntervalTicks;
      cd -= 1;
      if (cd <= 0) {
        this.companionAttackCd.set(c.id, stats.attackIntervalTicks);
        const raw = resolveAttack(stats, enemy.stats, this.rng, 'physical', this.config.combat);
        const outcome = this.dealToEnemy(enemy, raw);
        events.push({
          type: 'companionAttack',
          companion: c.name,
          outcome,
          targetHpAfter: enemy.currentHp,
        });
        if (!isAlive(enemy)) return;
      } else {
        this.companionAttackCd.set(c.id, cd);
      }

      if (c.skill) {
        let scd = this.companionSkillCd.get(c.id) ?? c.skill.cooldownTicks;
        scd -= 1;
        if (scd <= 0 && isAlive(enemy)) {
          this.companionSkillCd.set(c.id, c.skill.cooldownTicks);
          this.castSkillInstance(stats, c.name, c.skill, enemy, events);
          if (!isAlive(enemy)) return;
        } else {
          this.companionSkillCd.set(c.id, scd);
        }
      }
    }
  }

  /** Resolve a skill cast: damage hits the enemy, any healing goes to the hero. */
  private castSkillInstance(
    casterStats: Combatant['stats'],
    casterLabel: string,
    skill: SkillInstance,
    enemy: Combatant,
    events: WorldEvent[],
  ): void {
    const result = castSkill(casterStats, enemy.stats, skill, this.rng, this.config.combat);
    const damage = roundHalfUp(result.totalDamage * this.partyDamageMultiplier());
    enemy.currentHp = Math.max(0, enemy.currentHp - damage);
    if (result.heal > 0) {
      this.player.currentHp = Math.min(
        this.player.stats.maxHp,
        this.player.currentHp + result.heal,
      );
    }
    events.push({
      type: 'skill',
      caster: casterLabel,
      skill: result.skill,
      damage,
      heal: result.heal,
    });
  }

  // --- spawning & kills -----------------------------------------------------

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

  /** Wrapper so each early-return site both resolves the kill and ends the tick. */
  private finishKill(enemy: Combatant, events: WorldEvent[]): WorldEvent[] {
    this.handleKill(enemy, events);
    return events;
  }

  private handleKill(enemy: Combatant, events: WorldEvent[]): void {
    const def = enemy.sourceId ? this.registry.monster(enemy.sourceId) : undefined;
    const monsterDef = def && def.ok ? def.value : undefined;
    const exp = monsterDef ? monsterDef.experienceReward : 0;
    const loot = monsterDef
      ? rollLoot(monsterDef, this.registry, this.rng)
      : { gold: 0, items: [] as ItemInstance[] };

    this.gold += loot.gold;
    this.inventory.push(...loot.items);
    if (this.inventory.length > this.config.maxInventorySize) {
      this.inventory.splice(0, this.inventory.length - this.config.maxInventorySize);
    }

    events.push({
      type: 'kill',
      monster: enemy.name,
      experience: exp,
      gold: loot.gold,
    });
    if (loot.items.length > 0) events.push({ type: 'loot', items: loot.items });

    this.grantExperience(exp, events);
    this.deepenBonds();
    if (monsterDef) this.attemptCapture(monsterDef, events);

    this.target = undefined;
  }

  private grantExperience(exp: number, events: WorldEvent[]): void {
    const result = applyExperience(this.progress, exp, this.config.leveling);
    this.progress = result.state;
    if (result.levelsGained <= 0) return;
    this.build = {
      ...this.build,
      allocated: addAttributes(
        this.build.allocated,
        this.config.allocation(result.attributePointsAwarded),
      ),
    };
    // Rebuild stats from the stronger build and heal to full on level up.
    this.player = this.buildPlayerCombatant(true);
    events.push({
      type: 'levelUp',
      level: this.progress.level,
      levelsGained: result.levelsGained,
    });
  }

  private deepenBonds(): void {
    if (this.roster.length === 0) return;
    const active = new Set(this.activeParty().map((c) => c.id));
    let changed = false;
    this.roster = this.roster.map((c) => {
      if (!active.has(c.id)) return c;
      const grown = gainBond(c, 1, this.config.bond);
      if (grown !== c) changed = true;
      return grown;
    });
    if (changed) this.touchRoster();
  }

  private attemptCapture(
    monsterDef: MonsterDefinition,
    events: WorldEvent[],
  ): void {
    const captured = tryCapture(
      monsterDef,
      this.rng,
      this.companionIds,
      this.config.capture,
    );
    if (!captured) return;
    this.roster.push(captured);
    this.touchRoster();
    events.push({
      type: 'companionJoined',
      companion: captured.name,
      rarity: captured.rarity,
      shiny: captured.shiny,
    });
    if (this.config.autoFuse) this.tryAutoFuse(events);
    this.enforceRosterCap();
  }

  /** Auto-recycle the weakest companions once the roster exceeds its cap. */
  private enforceRosterCap(): void {
    if (this.roster.length <= this.config.maxRosterSize) return;
    this.roster.sort(
      (a, b) =>
        companionPower(b, this.config.bond) - companionPower(a, this.config.bond),
    );
    for (const dropped of this.roster.splice(this.config.maxRosterSize)) {
      this.companionAttackCd.delete(dropped.id);
      this.companionSkillCd.delete(dropped.id);
    }
    this.touchRoster();
  }

  /** Fuse the two lowest-power companions of the lowest shared rarity, if any. */
  private tryAutoFuse(events: WorldEvent[]): void {
    const byRarity = new Map<Rarity, Companion[]>();
    for (const c of this.roster) {
      const list = byRarity.get(c.rarity) ?? [];
      list.push(c);
      byRarity.set(c.rarity, list);
    }
    // Walk rarities low → high so we promote duplicates upward gradually.
    const rarities: Rarity[] = [
      'common',
      'uncommon',
      'rare',
      'epic',
      'legendary',
    ];
    for (const rarity of rarities) {
      const group = byRarity.get(rarity);
      if (!group || group.length < 2) continue;
      group.sort((a, b) => companionPower(a, this.config.bond) - companionPower(b, this.config.bond));
      const [a, b] = [group[0]!, group[1]!];
      const fused = fuse(a, b, this.companionIds);
      this.roster = this.roster.filter((c) => c.id !== a.id && c.id !== b.id);
      this.companionAttackCd.delete(a.id);
      this.companionAttackCd.delete(b.id);
      this.companionSkillCd.delete(a.id);
      this.companionSkillCd.delete(b.id);
      this.roster.push(fused);
      this.touchRoster();
      events.push({
        type: 'fusion',
        result: fused.name,
        rarity: fused.rarity,
        shiny: fused.shiny,
      });
      return; // at most one fusion per kill
    }
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
