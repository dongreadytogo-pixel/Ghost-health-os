/**
 * Branded (nominal) types. TypeScript is structurally typed, so a raw `string`
 * user id is interchangeable with any other string. Branding prevents passing,
 * say, a SleepSessionId where a UserId is expected — at zero runtime cost.
 */

declare const brand: unique symbol;

export type Brand<T, B extends string> = T & { readonly [brand]: B };

export type UserId = Brand<string, 'UserId'>;
export type DeviceId = Brand<string, 'DeviceId'>;
export type ProviderId = Brand<string, 'ProviderId'>;

/** ISO-8601 calendar date, e.g. "2026-06-27". No time component. */
export type IsoDate = Brand<string, 'IsoDate'>;

const ISO_DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

export const isIsoDate = (value: string): value is IsoDate =>
  ISO_DATE_RE.test(value) && !Number.isNaN(Date.parse(value));

/** Construct an IsoDate from a Date in UTC. */
export const toIsoDate = (date: Date): IsoDate =>
  date.toISOString().slice(0, 10) as IsoDate;
