/**
 * Progression — experience curve and level-up resolution.
 *
 * The curve is a pure function of a small config so it can be retuned live and
 * computed for any level without a lookup table. `applyExperience` is written to
 * absorb arbitrarily large gains in one call — essential for idle games, where
 * a returning player may need to level up many times from a single batch of
 * offline experience.
 */

import { roundHalfUp } from '../shared/math.js';

export interface LevelingConfig {
  /** Experience required to go from level 1 to level 2. */
  readonly baseExp: number;
  /** Growth exponent; >1 makes each level progressively longer. */
  readonly exponent: number;
  /** Levels are capped here; excess experience is retained but unspent. */
  readonly maxLevel: number;
  /** Attribute points awarded per level, fed back into the build system. */
  readonly attributePointsPerLevel: number;
}

export const DEFAULT_LEVELING: LevelingConfig = Object.freeze({
  baseExp: 100,
  exponent: 1.5,
  maxLevel: 99,
  attributePointsPerLevel: 5,
});

/** Experience needed to advance *from* `level` to `level + 1`. */
export function expToNext(level: number, config = DEFAULT_LEVELING): number {
  if (level < 1) level = 1;
  if (level >= config.maxLevel) return Infinity;
  return roundHalfUp(config.baseExp * Math.pow(level, config.exponent));
}

export interface ProgressState {
  readonly level: number;
  /** Experience accumulated toward the next level (always < expToNext). */
  readonly currentExp: number;
}

export interface LevelUpResult {
  readonly state: ProgressState;
  /** Number of levels gained in this application (0 if none). */
  readonly levelsGained: number;
  /** Attribute points awarded for the levels gained. */
  readonly attributePointsAwarded: number;
}

/**
 * Apply an experience gain, cascading through as many levels as the amount
 * affords. At max level experience stops accumulating (returns level cap with
 * zero progress) so the UI never shows a half-filled, unspendable bar.
 */
export function applyExperience(
  state: ProgressState,
  gained: number,
  config = DEFAULT_LEVELING,
): LevelUpResult {
  if (gained <= 0 || state.level >= config.maxLevel) {
    return {
      state:
        state.level >= config.maxLevel
          ? { level: config.maxLevel, currentExp: 0 }
          : state,
      levelsGained: 0,
      attributePointsAwarded: 0,
    };
  }

  let level = state.level;
  let exp = state.currentExp + gained;
  let levelsGained = 0;

  while (level < config.maxLevel) {
    const need = expToNext(level, config);
    if (exp < need) break;
    exp -= need;
    level += 1;
    levelsGained += 1;
  }

  if (level >= config.maxLevel) exp = 0;

  return {
    state: { level, currentExp: exp },
    levelsGained,
    attributePointsAwarded: levelsGained * config.attributePointsPerLevel,
  };
}
