import { describe, it, expect } from 'vitest';
import { GeminiLlmClient } from './gemini-llm-client.js';
import type {
  HttpClient,
  HttpPostRequest,
  HttpResponse,
} from '../http/http-client.js';

const okBody = (text: string) => ({
  candidates: [{ content: { parts: [{ text }] } }],
});

const stubHttp = (
  response: HttpResponse,
  onPost?: (req: HttpPostRequest) => void,
): HttpClient => ({
  get: async () => response,
  post: async (req) => {
    onPost?.(req);
    return response;
  },
});

describe('GeminiLlmClient', () => {
  it('maps system to system_instruction and turns to user/model roles', async () => {
    let captured: HttpPostRequest | undefined;
    const http = stubHttp({ status: 200, body: okBody('เล่นขาวันนี้ครับ') }, (r) => {
      captured = r;
    });
    const client = new GeminiLlmClient({ apiKey: 'free-key', http });

    const result = await client.complete({
      messages: [
        { role: 'system', content: 'คุณคือโค้ช' },
        { role: 'user', content: 'วันนี้เล่นอะไรดี' },
        { role: 'assistant', content: 'เมื่อวานเล่นอก' },
        { role: 'user', content: 'งั้นวันนี้ล่ะ' },
      ],
    });

    expect(result.ok).toBe(true);
    if (result.ok) expect(result.value).toBe('เล่นขาวันนี้ครับ');

    const body = captured?.body as Record<string, unknown>;
    expect((body['system_instruction'] as any).parts[0].text).toBe('คุณคือโค้ช');
    expect((body['contents'] as any[]).map((c) => c.role)).toEqual([
      'user',
      'model',
      'user',
    ]);
    // free-tier key is sent as a query param, not a billed header
    expect(captured?.url).toContain('key=free-key');
  });

  it('maps an auth failure to GEMINI_AUTH', async () => {
    const client = new GeminiLlmClient({
      apiKey: 'bad',
      http: stubHttp({ status: 403, body: {} }),
    });
    const result = await client.complete({
      messages: [{ role: 'user', content: 'hi' }],
    });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error.code).toBe('GEMINI_AUTH');
  });

  it('maps the free-tier limit (429) to GEMINI_RATE_LIMITED', async () => {
    const client = new GeminiLlmClient({
      apiKey: 'k',
      http: stubHttp({ status: 429, body: {} }),
    });
    const result = await client.complete({
      messages: [{ role: 'user', content: 'hi' }],
    });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error.code).toBe('GEMINI_RATE_LIMITED');
  });

  it('reports a safety/empty response as GEMINI_NO_TEXT', async () => {
    const client = new GeminiLlmClient({
      apiKey: 'k',
      http: stubHttp({ status: 200, body: { candidates: [] } }),
    });
    const result = await client.complete({
      messages: [{ role: 'user', content: 'hi' }],
    });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error.code).toBe('GEMINI_NO_TEXT');
  });
});
