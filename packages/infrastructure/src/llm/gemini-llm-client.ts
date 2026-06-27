import { ok, fail, type Result } from '@ghost/domain';
import type { LlmClient, LlmCompletionRequest } from '@ghost/application';
import type { HttpClient } from '../http/http-client.js';

/**
 * Gemini-backed implementation of the application's {@link LlmClient} port.
 *
 * Targets the Google AI Studio "Generative Language" REST API, which offers a
 * genuinely free tier (a free API key with generous per-day limits) — ideal for
 * a personal LINE assistant that should cost nothing to run. Because it speaks
 * the same {@link LlmClient} port as the Claude adapter, swapping the AI
 * provider is a one-line wiring change with zero impact on agents or the domain.
 *
 * The port's `system` messages become Gemini's `system_instruction`; user/
 * assistant turns map to Gemini's `user`/`model` roles. Uses the injectable
 * {@link HttpClient}, so it is fully unit-testable without a key or network.
 */
const DEFAULT_MODEL = 'gemini-2.0-flash';
const DEFAULT_BASE_URL = 'https://generativelanguage.googleapis.com/v1beta';

export interface GeminiLlmClientConfig {
  /** Free API key from Google AI Studio (aistudio.google.com). */
  readonly apiKey: string;
  readonly http: HttpClient;
  readonly model?: string;
  readonly baseUrl?: string;
}

export class GeminiLlmClient implements LlmClient {
  private readonly model: string;
  private readonly baseUrl: string;

  constructor(private readonly config: GeminiLlmClientConfig) {
    this.model = config.model ?? DEFAULT_MODEL;
    this.baseUrl = (config.baseUrl ?? DEFAULT_BASE_URL).replace(/\/$/, '');
  }

  async complete(request: LlmCompletionRequest): Promise<Result<string>> {
    const system = request.messages
      .filter((m) => m.role === 'system')
      .map((m) => m.content)
      .join('\n\n');

    const contents = request.messages
      .filter((m) => m.role !== 'system')
      .map((m) => ({
        role: m.role === 'assistant' ? 'model' : 'user',
        parts: [{ text: m.content }],
      }));

    const url = `${this.baseUrl}/models/${this.model}:generateContent?key=${this.config.apiKey}`;
    const body = {
      ...(system ? { system_instruction: { parts: [{ text: system }] } } : {}),
      contents,
      generationConfig: {
        maxOutputTokens: request.maxTokens ?? 1024,
        ...(request.temperature !== undefined
          ? { temperature: request.temperature }
          : {}),
      },
    };

    let response;
    try {
      response = await this.config.http.post({
        url,
        headers: { 'Content-Type': 'application/json' },
        body,
      });
    } catch (cause) {
      return fail('GEMINI_TRANSPORT', 'Gemini request failed', {
        message: cause instanceof Error ? cause.message : String(cause),
      });
    }

    if (response.status === 401 || response.status === 403) {
      return fail('GEMINI_AUTH', 'Gemini API key is invalid', {
        status: response.status,
      });
    }
    if (response.status === 429) {
      return fail('GEMINI_RATE_LIMITED', 'Gemini free-tier limit reached', {
        status: response.status,
      });
    }
    if (response.status < 200 || response.status >= 300) {
      return fail('GEMINI_HTTP', `Unexpected Gemini status ${response.status}`, {
        status: response.status,
      });
    }

    const text = extractText(response.body);
    if (text === undefined) {
      // No text part usually means a safety block or an empty candidate.
      return fail('GEMINI_NO_TEXT', 'Gemini returned no text content');
    }
    return ok(text);
  }
}

/** Pull the joined text out of a Gemini generateContent response, safely. */
function extractText(payload: unknown): string | undefined {
  if (!isRecord(payload) || !Array.isArray(payload['candidates'])) {
    return undefined;
  }
  const first = payload['candidates'][0];
  if (!isRecord(first) || !isRecord(first['content'])) return undefined;
  const parts = first['content']['parts'];
  if (!Array.isArray(parts)) return undefined;

  const text = parts
    .map((p) => (isRecord(p) && typeof p['text'] === 'string' ? p['text'] : ''))
    .join('');
  return text.length > 0 ? text : undefined;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}
