import Anthropic from '@anthropic-ai/sdk';
import { ok, fail, type Result } from '@ghost/domain';
import type { LlmClient, LlmCompletionRequest } from '@ghost/application';

/**
 * Claude-backed implementation of the application's {@link LlmClient} port.
 *
 * Uses the official Anthropic SDK with the latest Opus model and adaptive
 * thinking (the current API surface — `budget_tokens`, `temperature`, etc. are
 * not sent, as Opus 4.8 rejects them). System messages from the port are hoisted
 * into the API's top-level `system` field; user/assistant turns map directly.
 *
 * Transport is injectable so the mapping logic is unit-testable without a live
 * API key or network. A `refusal` stop reason is surfaced as a typed
 * `DomainError` rather than an empty string.
 */
const DEFAULT_MODEL = 'claude-opus-4-8';
const DEFAULT_MAX_TOKENS = 1024;

export interface ClaudeCallParams {
  readonly model: string;
  readonly maxTokens: number;
  readonly system: string | undefined;
  readonly messages: readonly { role: 'user' | 'assistant'; content: string }[];
}

export interface ClaudeCallResult {
  readonly text: string;
  readonly refused: boolean;
}

export type ClaudeTransport = (
  params: ClaudeCallParams,
) => Promise<ClaudeCallResult>;

export interface ClaudeLlmClientConfig {
  /** API key for the default SDK transport. Ignored if `transport` is given. */
  readonly apiKey?: string;
  readonly model?: string;
  /** Inject to test or to supply a pre-configured client; defaults to the SDK. */
  readonly transport?: ClaudeTransport;
}

export class ClaudeLlmClient implements LlmClient {
  private readonly transport: ClaudeTransport;
  private readonly model: string;

  constructor(config: ClaudeLlmClientConfig = {}) {
    this.model = config.model ?? DEFAULT_MODEL;
    this.transport =
      config.transport ??
      sdkTransport(new Anthropic({ apiKey: config.apiKey }));
  }

  async complete(request: LlmCompletionRequest): Promise<Result<string>> {
    const system = request.messages
      .filter((m) => m.role === 'system')
      .map((m) => m.content)
      .join('\n\n');

    const messages = request.messages
      .filter((m): m is { role: 'user' | 'assistant'; content: string } =>
        m.role !== 'system',
      )
      .map((m) => ({ role: m.role, content: m.content }));

    try {
      const result = await this.transport({
        model: this.model,
        maxTokens: request.maxTokens ?? DEFAULT_MAX_TOKENS,
        system: system.length > 0 ? system : undefined,
        messages,
      });
      if (result.refused) {
        return fail('LLM_REFUSAL', 'The model declined to respond');
      }
      return ok(result.text);
    } catch (cause) {
      return fail('LLM_ERROR', 'Claude request failed', {
        message: cause instanceof Error ? cause.message : String(cause),
      });
    }
  }
}

/** Default transport backed by the official Anthropic SDK. */
function sdkTransport(client: Anthropic): ClaudeTransport {
  return async ({ model, maxTokens, system, messages }) => {
    // NOTE: `thinking` is omitted (valid on Opus 4.8) — the pinned SDK predates
    // adaptive thinking. Add `thinking: { type: 'adaptive' }` once the SDK is
    // upgraded to a version whose types include it.
    const response = await client.messages.create({
      model,
      max_tokens: maxTokens,
      ...(system ? { system } : {}),
      messages: messages.map((m) => ({ role: m.role, content: m.content })),
    });

    const text = response.content
      .filter((b): b is Anthropic.TextBlock => b.type === 'text')
      .map((b) => b.text)
      .join('');

    return { text, refused: response.stop_reason === 'refusal' };
  };
}
