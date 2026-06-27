import { ok, fail, type Result } from '@ghost/domain';
import type { LlmClient, LlmCompletionRequest } from '@ghost/application';

/**
 * A Worker-native {@link LlmClient} backed by the free-tier Gemini API.
 *
 * Mirrors `@ghost/infrastructure`'s GeminiLlmClient but calls the global `fetch`
 * directly, so the Worker bundle stays tiny and pulls in no Node-only SDKs. The
 * free Google AI Studio key (`GEMINI_API_KEY`) is passed as a query param — no
 * billing header — keeping a personal LINE bot at zero token cost.
 */
const BASE_URL = 'https://generativelanguage.googleapis.com/v1beta';

export class GeminiClient implements LlmClient {
  constructor(
    private readonly apiKey: string,
    private readonly model = 'gemini-2.0-flash',
  ) {}

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

    const url = `${BASE_URL}/models/${this.model}:generateContent?key=${this.apiKey}`;
    const body = {
      ...(system ? { system_instruction: { parts: [{ text: system }] } } : {}),
      contents,
      generationConfig: { maxOutputTokens: request.maxTokens ?? 1024 },
    };

    let response: Response;
    try {
      response = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      });
    } catch (cause) {
      return fail('GEMINI_TRANSPORT', 'Gemini request failed', {
        message: cause instanceof Error ? cause.message : String(cause),
      });
    }

    if (response.status === 429) {
      return fail('GEMINI_RATE_LIMITED', 'Gemini free-tier limit reached');
    }
    if (!response.ok) {
      return fail('GEMINI_HTTP', `Unexpected Gemini status ${response.status}`);
    }

    const payload = (await response.json()) as unknown;
    const text = extractText(payload);
    if (text === undefined) {
      return fail('GEMINI_NO_TEXT', 'Gemini returned no text content');
    }
    return ok(text);
  }
}

function extractText(payload: unknown): string | undefined {
  if (!isRecord(payload) || !Array.isArray(payload['candidates'])) return undefined;
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
