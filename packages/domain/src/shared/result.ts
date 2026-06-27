/**
 * Result<T, E> — an explicit success/failure container.
 *
 * The domain never throws for *expected* failures (invalid input, business-rule
 * violations). Throwing is reserved for true programmer errors. This keeps the
 * application layer in full control of error flow and makes every failure path
 * type-checked at compile time.
 */

export type Result<T, E = DomainError> =
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
 * A structured domain error. `code` is machine-readable and stable (safe to map
 * to i18n keys or API error codes); `message` is human-readable for logs.
 */
export class DomainError extends Error {
  readonly code: string;
  readonly details: Readonly<Record<string, unknown>>;

  constructor(
    code: string,
    message: string,
    details: Record<string, unknown> = {},
  ) {
    super(message);
    this.name = 'DomainError';
    this.code = code;
    this.details = Object.freeze({ ...details });
  }
}

export const fail = (
  code: string,
  message: string,
  details?: Record<string, unknown>,
): Result<never, DomainError> => err(new DomainError(code, message, details));
