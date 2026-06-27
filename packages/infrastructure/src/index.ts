/**
 * @ghost/infrastructure — concrete adapters behind domain ports.
 * Depends inward on @ghost/domain. Swapping any adapter never touches the core.
 */
export * from './http/http-client.js';
export * from './persistence/in-memory-health-sample-repository.js';
export * from './providers/fitbit/fitbit-provider.js';
export * from './llm/claude-llm-client.js';
export * from './llm/gemini-llm-client.js';
