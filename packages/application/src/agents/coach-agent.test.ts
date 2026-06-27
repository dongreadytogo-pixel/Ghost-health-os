import { describe, it, expect } from 'vitest';
import { ok, Score, type IsoDate, type GhostCategory } from '@ghost/domain';
import { CoachAgent } from './coach-agent.js';
import type { LlmClient, LlmCompletionRequest } from '../ports/llm.js';
import type { DailyScores } from '../use-cases/compute-daily-scores.js';

const context: DailyScores = {
  date: '2026-06-27' as IsoDate,
  ghostScore: 78,
  categories: { recovery: Score.of(70) } as Partial<Record<GhostCategory, Score>>,
  focusArea: 'recovery',
  training: undefined,
};

/** Records the request and returns a canned answer. */
const spyLlm = () => {
  let captured: LlmCompletionRequest | undefined;
  const llm: LlmClient = {
    complete: async (req) => {
      captured = req;
      return ok('วันนี้ Recovery 70/100 ครับ พักให้พอนะ');
    },
  };
  return { llm, get: () => captured };
};

describe('CoachAgent', () => {
  it('grounds the LLM on the computed daily scores', async () => {
    const { llm, get } = spyLlm();
    const agent = new CoachAgent(llm);

    const result = await agent.ask('วันนี้ Recovery เท่าไร', context);

    expect(result.ok).toBe(true);
    const req = get();
    expect(req).toBeDefined();
    // system prompt enforces non-diagnostic, data-grounded answers
    expect(req?.messages[0]?.role).toBe('system');
    expect(req?.messages[0]?.content).toContain('ห้ามวินิจฉัยโรค');
    // user message embeds the grounding summary and the question
    expect(req?.messages[1]?.content).toContain('Ghost Score: 78/100');
    expect(req?.messages[1]?.content).toContain('วันนี้ Recovery เท่าไร');
  });

  it('returns the LLM answer on success', async () => {
    const { llm } = spyLlm();
    const result = await new CoachAgent(llm).ask('ควรพักไหม', context);
    expect(result.ok).toBe(true);
    if (result.ok) expect(result.value).toContain('Recovery');
  });
});
