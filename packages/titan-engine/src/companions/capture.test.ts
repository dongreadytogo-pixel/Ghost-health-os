import { describe, it, expect } from 'vitest';
import { tryCapture, captureChance, DEFAULT_CAPTURE } from './capture.js';
import { EntityIdFactory } from '../entities/combatant.js';
import { asMonsterDefId, asSkillDefId } from '../shared/branded.js';
import { Rng } from '../shared/rng.js';
import { deriveStats, ZERO_ATTRIBUTES } from '../stats/stats.js';
import type { MonsterDefinition } from '../content/definitions.js';
import type { SkillDefinition } from '../skills/skill.js';

const crawler: MonsterDefinition = {
  id: asMonsterDefId('crawler'),
  name: 'Gel Crawler',
  level: 1,
  stats: deriveStats(ZERO_ATTRIBUTES),
  experienceReward: 10,
  goldReward: { min: 1, max: 2 },
  dropTable: [],
  isBoss: false,
};

const boss: MonsterDefinition = { ...crawler, name: 'Gel King', isBoss: true };

const cleave: SkillDefinition = {
  id: asSkillDefId('cleave'),
  name: 'Cleave',
  kind: 'burst',
  baseCooldownTicks: 60,
  basePower: 3,
};

describe('captureChance', () => {
  it('is lower for bosses', () => {
    expect(captureChance(boss)).toBeLessThan(captureChance(crawler));
  });
});

describe('tryCapture', () => {
  it('returns undefined when the roll fails (guaranteed via zero chance)', () => {
    const result = tryCapture(crawler, Rng.fromSeed(1), new EntityIdFactory('c'), {
      ...DEFAULT_CAPTURE,
      baseChance: 0,
    });
    expect(result).toBeUndefined();
  });

  it('always captures with chance 1 and produces a valid companion', () => {
    const c = tryCapture(crawler, Rng.fromSeed(1), new EntityIdFactory('c'), {
      ...DEFAULT_CAPTURE,
      baseChance: 1,
    });
    expect(c).toBeDefined();
    expect(c!.sourceMonsterId).toBe(asMonsterDefId('crawler'));
    expect(c!.baseName).toBe('Gel Crawler');
    expect(c!.bond).toBe(0);
    expect(c!.name).toContain('Gel Crawler');
  });

  it('can roll an innate skill from the pool', () => {
    const c = tryCapture(crawler, Rng.fromSeed(4), new EntityIdFactory('c'), {
      ...DEFAULT_CAPTURE,
      baseChance: 1,
      innateSkillChance: 1,
      skillPool: [cleave],
    });
    expect(c!.skill).toBeDefined();
    expect(c!.skill!.defId).toBe(asSkillDefId('cleave'));
  });

  it('is deterministic for a seed', () => {
    const a = tryCapture(crawler, Rng.fromSeed(9), new EntityIdFactory('c'), {
      ...DEFAULT_CAPTURE,
      baseChance: 1,
    });
    const b = tryCapture(crawler, Rng.fromSeed(9), new EntityIdFactory('c'), {
      ...DEFAULT_CAPTURE,
      baseChance: 1,
    });
    expect(a).toEqual(b);
  });
});
