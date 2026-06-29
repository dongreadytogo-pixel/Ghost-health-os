/**
 * Offline progress — fast-forward the World and summarize what happened.
 *
 * This is the payoff of building the whole engine deterministically: when a
 * player returns after hours away, we convert elapsed real time into a tick
 * budget, run that many ticks, and fold the event stream into a compact report
 * for a "while you were away" screen. The same code path is exact whether it
 * runs on the client or is re-verified by a server.
 */

import type { World, WorldEvent } from '../world/world.js';
import type { ItemInstance } from '../loot/loot.js';

export interface OfflineSummary {
  readonly ticks: number;
  readonly kills: number;
  readonly experienceGained: number;
  readonly goldGained: number;
  readonly levelsGained: number;
  readonly defeats: number;
  readonly loot: readonly ItemInstance[];
}

export const ZERO_SUMMARY: OfflineSummary = Object.freeze({
  ticks: 0,
  kills: 0,
  experienceGained: 0,
  goldGained: 0,
  levelsGained: 0,
  defeats: 0,
  loot: [],
});

/** Fold a stream of world events into an offline summary. */
export function summarizeEvents(
  events: readonly WorldEvent[],
  ticks: number,
): OfflineSummary {
  let kills = 0;
  let experienceGained = 0;
  let goldGained = 0;
  let levelsGained = 0;
  let defeats = 0;
  const loot: ItemInstance[] = [];

  for (const e of events) {
    switch (e.type) {
      case 'kill':
        kills += 1;
        experienceGained += e.experience;
        goldGained += e.gold;
        break;
      case 'levelUp':
        levelsGained += e.levelsGained;
        break;
      case 'loot':
        loot.push(...e.items);
        break;
      case 'playerDefeated':
        defeats += 1;
        break;
      default:
        break;
    }
  }

  return { ticks, kills, experienceGained, goldGained, levelsGained, defeats, loot };
}

export interface OfflineConfig {
  /** Real milliseconds represented by one simulation tick. */
  readonly msPerTick: number;
  /** Hard cap on simulated ticks, so a month away can't freeze the device. */
  readonly maxTicks: number;
}

export const DEFAULT_OFFLINE: OfflineConfig = Object.freeze({
  msPerTick: 100, // 10 ticks/second
  maxTicks: 8 * 60 * 60 * 10, // up to 8 hours of accrued progress
});

/**
 * Advance `world` to account for `elapsedMs` of real time, returning the
 * summary. The world is mutated in place (it now reflects the caught-up state).
 */
export function simulateOffline(
  world: World,
  elapsedMs: number,
  config: OfflineConfig = DEFAULT_OFFLINE,
): OfflineSummary {
  const rawTicks = Math.floor(Math.max(0, elapsedMs) / config.msPerTick);
  const ticks = Math.min(rawTicks, config.maxTicks);
  if (ticks <= 0) return ZERO_SUMMARY;
  const events = world.run(ticks);
  return summarizeEvents(events, ticks);
}
