/**
 * @ghost/application — use-cases that orchestrate the domain over ports.
 * Depends inward on @ghost/domain only; receives concrete adapters via DI.
 */
export * from './ports/clock.js';
export * from './ports/llm.js';
export * from './use-cases/sync-health-data.js';
export * from './use-cases/compute-daily-scores.js';
export * from './reporting/daily-summary.js';
export * from './agents/coach-agent.js';
