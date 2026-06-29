/** Small, dependency-free numeric helpers used throughout the engine. */

export const clamp = (value: number, min: number, max: number): number =>
  value < min ? min : value > max ? max : value;

export const lerp = (a: number, b: number, t: number): number =>
  a + (b - a) * clamp(t, 0, 1);

/** Round half-up to the nearest integer; stable for the simulation. */
export const roundHalfUp = (value: number): number => Math.floor(value + 0.5);
