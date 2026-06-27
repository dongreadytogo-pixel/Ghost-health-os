import type { Result } from '@ghost/domain';
import type { LlmClient, LlmMessage } from '../ports/llm.js';
import type { DailyScores } from '../use-cases/compute-daily-scores.js';
import { generateDailySummary } from '../reporting/daily-summary.js';

/**
 * CoachAgent — the Conversation Engine. It answers natural Thai questions
 * ("วันนี้ควรเล่นอะไร", "Recovery เท่าไร") by grounding an LLM on the day's
 * *computed* scores, so answers stay tied to real data rather than invention.
 *
 * The grounding context is the deterministic daily summary plus a strict system
 * prompt: stay non-diagnostic, never invent numbers, speak Thai. The agent
 * depends only on the {@link LlmClient} port, so it is fully testable with a
 * fake and provider-agnostic.
 */
const SYSTEM_PROMPT = [
  'คุณคือ Ghost โค้ชสุขภาพ AI ส่วนตัว พูดภาษาไทยกระชับ เป็นกันเอง และให้กำลังใจ',
  'กฎสำคัญ:',
  '- ตอบโดยอ้างอิงเฉพาะข้อมูลที่ให้ไว้ ห้ามเดาตัวเลขเอง',
  '- ห้ามวินิจฉัยโรค โดยเฉพาะเรื่องน้ำตาลในเลือด ให้พูดเชิงแนวโน้มและการดูแลตัวเองเท่านั้น',
  '- ถ้าข้อมูลไม่พอ ให้บอกตรง ๆ ว่ายังไม่มีข้อมูล',
  '- แนะนำให้ปรึกษาแพทย์เมื่อเกี่ยวข้องกับการรักษา',
].join('\n');

export class CoachAgent {
  constructor(private readonly llm: LlmClient) {}

  /**
   * Answer a question. When `context` (the day's computed scores) is provided,
   * the answer is grounded on it; otherwise the agent acts as a general health
   * coach — useful before any wearable data is connected.
   */
  async ask(
    question: string,
    context?: DailyScores,
  ): Promise<Result<string>> {
    const userContent = context
      ? [
          'ข้อมูลสุขภาพวันนี้ (ใช้อ้างอิงเท่านั้น):',
          '"""',
          generateDailySummary(context),
          '"""',
          '',
          `คำถาม: ${question}`,
        ].join('\n')
      : [
          'ยังไม่มีข้อมูลสุขภาพที่ซิงค์เข้ามา ตอบเป็นคำแนะนำทั่วไปเชิงให้ความรู้',
          'และถ้าจำเป็นต้องใช้ข้อมูลส่วนตัว ให้บอกว่ายังไม่ได้เชื่อมต่ออุปกรณ์.',
          '',
          `คำถาม: ${question}`,
        ].join('\n');

    const messages: LlmMessage[] = [
      { role: 'system', content: SYSTEM_PROMPT },
      { role: 'user', content: userContent },
    ];

    return this.llm.complete({ messages, temperature: 0.4, maxTokens: 1024 });
  }
}
