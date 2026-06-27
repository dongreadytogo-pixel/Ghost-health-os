import { describe, it, expect, vi } from 'vitest';
import {
  ClaudeLlmClient,
  type ClaudeCallParams,
  type ClaudeCallResult,
} from './claude-llm-client.js';

describe('ClaudeLlmClient', () => {
  it('hoists system messages into the system field and maps turns', async () => {
    let captured: ClaudeCallParams | undefined;
    const transport = async (
      params: ClaudeCallParams,
    ): Promise<ClaudeCallResult> => {
      captured = params;
      return { text: 'สวัสดีครับ', refused: false };
    };
    const client = new ClaudeLlmClient({ transport });

    const result = await client.complete({
      messages: [
        { role: 'system', content: 'คุณคือโค้ช' },
        { role: 'user', content: 'วันนี้ควรเล่นอะไร' },
      ],
    });

    expect(result.ok).toBe(true);
    if (result.ok) expect(result.value).toBe('สวัสดีครับ');
    expect(captured?.system).toBe('คุณคือโค้ช');
    expect(captured?.messages).toEqual([
      { role: 'user', content: 'วันนี้ควรเล่นอะไร' },
    ]);
  });

  it('returns a typed error on refusal', async () => {
    const client = new ClaudeLlmClient({
      transport: async () => ({ text: '', refused: true }),
    });
    const result = await client.complete({
      messages: [{ role: 'user', content: 'hi' }],
    });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error.code).toBe('LLM_REFUSAL');
  });

  it('maps transport exceptions to LLM_ERROR', async () => {
    const client = new ClaudeLlmClient({
      transport: vi.fn().mockRejectedValue(new Error('429 rate limited')),
    });
    const result = await client.complete({
      messages: [{ role: 'user', content: 'hi' }],
    });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error.code).toBe('LLM_ERROR');
      expect(result.error.details).toMatchObject({ message: '429 rate limited' });
    }
  });
});
