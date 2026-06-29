/**
 * Result<T, E> — explicit success/failure container.
 *
 * The engine never throws for *expected* failures (unknown content id, invalid
 * config, business-rule violations). Throwing is reserved for true programmer
 * errors. Mirrors the convention used across the Ghost monorepo so the two
 * codebases read the same.
 */

export type Result<T, E = EngineError> =
  | { readonly ok: true; readonly value: T }
  | { readonly ok: false; readonly error: E };

export const ok = <T>(value: T): Result<T, never> => ({ ok: true, value });

export const err = <E>(error: E): Result<never, E> => ({ ok: false, error });

export const isOk = <T, E>(
  result: Result<T, E>,
): result is { ok: true; value: T } => result.ok;

export const isErr = <T, E>(
  result: Result<T, E>,
): result is { ok: false; error: E } => !result.ok;

/** Unwrap a successful value or throw. Use only when failure is impossible. */
export const unwrap = <T, E>(result: Result<T, E>): T => {
  if (result.ok) return result.value;
  throw new Error(
    `Called unwrap() on an error result: ${JSON.stringify(result.error)}`,
  );
};

/**
 * A structured engine error. `code` is machine-readable and stable (safe to map
 * to telemetry keys or client error codes); `message` is human-readable.
 */
export class EngineError extends Error {
  readonly code: string;
  readonly details: Readonly<Record<string, unknown>>;

  constructor(
    code: string,
    message: string,
    details: Record<string, unknown> = {},
  ) {
    super(message);
    this.name = 'EngineError';
    this.code = code;
    this.details = Object.freeze({ ...details });
  }
}

export const fail = (
  code: string,
  message: string,
  details?: Record<string, unknown>,
): Result<never, EngineError> => err(new EngineError(code, message, details));
