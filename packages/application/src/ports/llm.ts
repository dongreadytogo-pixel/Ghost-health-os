import type { Result } from '@ghost/domain';

/**
 * LLM port for the AI agents (Conversation Engine, Coaches, Report enhancer).
 * The application depends only on this interface; a Claude-backed adapter lives
 * in @ghost/infrastructure and is injected at the edge. Keeping it abstract
 * means agents are testable with a deterministic fake and the provider is
 * swappable (Claude today, others later) without touching agent logic.
 */
export interface LlmMessage {
  readonly role: 'system' | 'user' | 'assistant';
  readonly content: string;
}

export interface LlmCompletionRequest {
  readonly messages: readonly LlmMessage[];
  readonly maxTokens?: number;
  readonly temperature?: number;
}

export interface LlmClient {
  complete(request: LlmCompletionRequest): Promise<Result<string>>;
}
