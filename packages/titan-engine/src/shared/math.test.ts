import { describe, it, expect } from 'vitest';
import { clamp, lerp, roundHalfUp } from './math.js';

describe('clamp', () => {
  it('clamps below, within, and above range', () => {
    expect(clamp(-5, 0, 10)).toBe(0);
    expect(clamp(5, 0, 10)).toBe(5);
    expect(clamp(50, 0, 10)).toBe(10);
  });
});

describe('lerp', () => {
  it('interpolates and clamps t', () => {
    expect(lerp(0, 100, 0)).toBe(0);
    expect(lerp(0, 100, 0.5)).toBe(50);
    expect(lerp(0, 100, 1)).toBe(100);
    expect(lerp(0, 100, 2)).toBe(100);
    expect(lerp(0, 100, -1)).toBe(0);
  });
});

describe('roundHalfUp', () => {
  it('rounds half upward deterministically', () => {
    expect(roundHalfUp(2.5)).toBe(3);
    expect(roundHalfUp(2.4)).toBe(2);
    expect(roundHalfUp(2.49999)).toBe(2);
  });
});
