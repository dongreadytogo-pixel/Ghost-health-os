import { CoachAgent } from '@ghost/application';
import { verifyLineSignature } from './signature.js';
import { GeminiClient } from './gemini.js';
import { asTextEvent, replyText, type LineWebhookBody } from './line.js';

/**
 * Ghost Health OS — LINE assistant (Cloudflare Worker).
 *
 * Flow per inbound message:
 *   verify LINE signature → CoachAgent (free Gemini) → reply on LINE.
 *
 * Until a wearable is connected the coach answers general (non-diagnostic)
 * health questions; once `ComputeDailyScores` is wired in, the same CoachAgent
 * will ground answers on the user's real daily scores with no change here.
 *
 * Secrets are injected by the runtime (never hard-coded) — see wrangler.jsonc.
 */
export interface Env {
  readonly GEMINI_API_KEY: string;
  readonly LINE_CHANNEL_SECRET: string;
  readonly LINE_CHANNEL_ACCESS_TOKEN: string;
  readonly GEMINI_MODEL?: string;
}

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    // GET → a simple health check so you can confirm the Worker is live.
    if (request.method !== 'POST') {
      return new Response('Ghost LINE bot is running.', { status: 200 });
    }

    if (!env.GEMINI_API_KEY || !env.LINE_CHANNEL_SECRET || !env.LINE_CHANNEL_ACCESS_TOKEN) {
      return new Response('Server not configured', { status: 500 });
    }

    const rawBody = await request.text();
    const signature = request.headers.get('x-line-signature');
    if (!(await verifyLineSignature(env.LINE_CHANNEL_SECRET, rawBody, signature))) {
      return new Response('Invalid signature', { status: 401 });
    }

    let body: LineWebhookBody;
    try {
      body = JSON.parse(rawBody) as LineWebhookBody;
    } catch {
      return new Response('Bad JSON', { status: 400 });
    }

    const coach = new CoachAgent(
      new GeminiClient(env.GEMINI_API_KEY, env.GEMINI_MODEL),
    );

    // Answer each message; do the slow work in the background so LINE gets a
    // fast 200 (it retries on timeouts).
    for (const rawEvent of body.events ?? []) {
      const event = asTextEvent(rawEvent);
      if (!event || !event.message.text) continue;
      ctx.waitUntil(handleMessage(coach, env, event.replyToken, event.message.text));
    }

    return new Response('OK', { status: 200 });
  },
} satisfies ExportedHandler<Env>;

async function handleMessage(
  coach: CoachAgent,
  env: Env,
  replyToken: string,
  text: string,
): Promise<void> {
  const answer = await coach.ask(text);
  const reply = answer.ok
    ? answer.value
    : 'ขออภัยครับ ตอนนี้ผู้ช่วยตอบไม่ได้ชั่วคราว ลองใหม่อีกครั้งนะครับ 🙏';
  await replyText(env.LINE_CHANNEL_ACCESS_TOKEN, replyToken, reply);
}
