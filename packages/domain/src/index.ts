/**
 * @ghost/domain — the pure, provider-agnostic core of Ghost Health OS.
 *
 * Contains no I/O, no framework, and no vendor SDKs. Everything here is
 * deterministic and unit-testable, and every other layer depends inward on it.
 */

// Shared kernel
export * from './shared/result.js';
export * from './shared/branded.js';
export * from './shared/guard.js';

// Value objects
export * from './value-objects/score.js';

// Health data contracts
export * from './health/samples.js';
export * from './health/sample-key.js';
export * from './providers/health-data-provider.js';
export * from './repositories/health-sample-repository.js';

// Metrics (the brain)
export * from './metrics/sleep-score.js';
export * from './metrics/recovery-score.js';
export * from './metrics/ghost-score.js';
