import { fail, ok, type Result } from './result.js';

/**
 * Small, composable validation helpers used by value objects and entity
 * factories. Each returns a Result so callers stay on the explicit-error path.
 */

export const ensureFinite = (
  value: number,
  field: string,
): Result<number> => {
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    return fail('NOT_FINITE', `${field} must be a finite number`, { field, value });
  }
  return ok(value);
};

export const ensureInRange = (
  value: number,
  min: number,
  max: number,
  field: string,
): Result<number> => {
  const finite = ensureFinite(value, field);
  if (!finite.ok) return finite;
  if (value < min || value > max) {
    return fail(
      'OUT_OF_RANGE',
      `${field} must be between ${min} and ${max} (received ${value})`,
      { field, value, min, max },
    );
  }
  return ok(value);
};

export const ensureNonNegative = (
  value: number,
  field: string,
): Result<number> => {
  const finite = ensureFinite(value, field);
  if (!finite.ok) return finite;
  if (value < 0) {
    return fail('NEGATIVE', `${field} must not be negative`, { field, value });
  }
  return ok(value);
};

export const ensureNonEmpty = (
  value: string,
  field: string,
): Result<string> => {
  if (typeof value !== 'string' || value.trim().length === 0) {
    return fail('EMPTY', `${field} must not be empty`, { field });
  }
  return ok(value);
};

/** Clamp a number into [min, max]. Pure, total, never fails. */
export const clamp = (value: number, min: number, max: number): number =>
  Math.min(max, Math.max(min, value));
