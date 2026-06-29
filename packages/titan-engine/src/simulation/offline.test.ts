import { describe, it, expect } from 'vitest';
import {
  simulateOffline,
  summarizeEvents,
  DEFAULT_OFFLINE,
  ZERO_SUMMARY,
} from './offline.js';
import { World } from '../world/world.js';
import { ContentRegistry } from '../content/registry.js';
import { STARTER_CONTENT } from '../content/starter-content.js';
import { asZoneDefId } from '../shared/branded.js';
import { unwrap } from '../shared/result.js';
import { Rng } from '../shared/rng.js';
import { ZERO_ATTRIBUTES } from '../stats/stats.js';

const registry = new ContentRegistry().register(STARTER_CONTENT);
const zone = unwrap(registry.zone(asZoneDefId('verdant_fringe')));

const makeWorld = (seed: number): World =>
  new World(registry, zone, Rng.fromSeed(seed), {
    allocated: {
      ...ZERO_ATTRIBUTES,
      strength: 20,
      agility: 15,
      vitality: 20,
      dexterity: 20,
      luck: 10,
    },
    equipment: {},
  });

describe('summarizeEvents', () => {
  it('folds kills, gold, exp, levels and loot', () => {
    const log = makeWorld(1).run(3000);
    const summary = summarizeEvents(log, 3000);
    expect(summary.ticks).toBe(3000);
    expect(summary.kills).toBeGreaterThan(0);
    expect(summary.goldGained).toBeGreaterThan(0);
    expect(summary.experienceGained).toBeGreaterThan(0);
  });
});

describe('simulateOffline', () => {
  it('returns the zero summary for no elapsed time', () => {
    expect(simulateOffline(makeWorld(1), 0)).toEqual(ZERO_SUMMARY);
    expect(simulateOffline(makeWorld(1), -500)).toEqual(ZERO_SUMMARY);
  });

  it('converts elapsed time into ticks and progresses the world', () => {
    const world = makeWorld(5);
    const oneHourMs = 60 * 60 * 1000;
    const summary = simulateOffline(world, oneHourMs);
    expect(summary.ticks).toBe(oneHourMs / DEFAULT_OFFLINE.msPerTick);
    expect(summary.kills).toBeGreaterThan(0);
    expect(world.ticksElapsed).toBe(summary.ticks);
  });

  it('caps simulated ticks so an enormous absence cannot freeze the device', () => {
    const world = makeWorld(5);
    const oneYearMs = 365 * 24 * 60 * 60 * 1000;
    const summary = simulateOffline(world, oneYearMs);
    expect(summary.ticks).toBe(DEFAULT_OFFLINE.maxTicks);
  });

  it('is deterministic: same seed and elapsed time give the same summary', () => {
    const a = simulateOffline(makeWorld(9), 600_000);
    const b = simulateOffline(makeWorld(9), 600_000);
    expect(a).toEqual(b);
  });
});
