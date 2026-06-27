/**
 * Time as an injectable dependency. Use-cases never call `new Date()` directly;
 * they read the clock, which keeps them deterministic and testable.
 */
export interface Clock {
  now(): Date;
}

/** Real wall-clock implementation for production wiring. */
export const systemClock: Clock = {
  now: () => new Date(),
};
