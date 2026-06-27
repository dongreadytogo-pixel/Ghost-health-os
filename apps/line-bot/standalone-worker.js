/**
 * Ghost Health OS — LINE assistant (standalone copy-paste Cloudflare Worker).
 *
 * This is a single self-contained file with no build step or dependencies, made
 * for pasting straight into the Cloudflare dashboard editor. It mirrors the
 * TypeScript Worker in `src/` (same signature verification + free Gemini call +
 * LINE reply); use this when you don't have a local dev environment.
 *
 * Set these three SECRETS in the Cloudflare dashboard
 * (Worker → Settings → Variables and Secrets):
 *   GEMINI_API_KEY              free key from aistudio.google.com
 *   LINE_CHANNEL_SECRET         LINE → Messaging API → Channel secret
 *   LINE_CHANNEL_ACCESS_TOKEN   LINE → Messaging API → Channel access token
 * Optional plain variable:
 *   GEMINI_MODEL               defaults to "gemini-2.0-flash"
 */

const SYSTEM_PROMPT = [
  'คุณคือ Ghost โค้ชสุขภาพ AI ส่วนตัว พูดภาษาไทยกระชับ เป็นกันเอง และให้กำลังใจ',
  'กฎสำคัญ:',
  '- ตอบเชิงให้ความรู้และการดูแลตัวเอง',
  '- ห้ามวินิจฉัยโรค โดยเฉพาะเรื่องน้ำตาลในเลือด ให้พูดเชิงแนวโน้มเท่านั้น',
  '- ถ้าต้องใช้ข้อมูลส่วนตัวที่ยังไม่มี ให้บอกว่ายังไม่ได้เชื่อมต่ออุปกรณ์',
  '- แนะนำให้ปรึกษาแพทย์เมื่อเกี่ยวข้องกับการรักษา',
].join('\n');

const GEMINI_BASE = 'https://generativelanguage.googleapis.com/v1beta';
const LINE_REPLY_URL = 'https://api.line.me/v2/bot/message/reply';

export default {
  async fetch(request, env, ctx) {
    // A browser GET is a simple health check.
    if (request.method !== 'POST') {
      return new Response('Ghost LINE bot is running.', { status: 200 });
    }
    if (!env.GEMINI_API_KEY || !env.LINE_CHANNEL_SECRET || !env.LINE_CHANNEL_ACCESS_TOKEN) {
      return new Response('Server not configured', { status: 500 });
    }

    const raw = await request.text();
    const signature = request.headers.get('x-line-signature');
    if (!(await verifyLineSignature(env.LINE_CHANNEL_SECRET, raw, signature))) {
      return new Response('Invalid signature', { status: 401 });
    }

    let body;
    try {
      body = JSON.parse(raw);
    } catch {
      return new Response('Bad JSON', { status: 400 });
    }

    for (const event of body.events || []) {
      if (
        event.type === 'message' &&
        event.message &&
        event.message.type === 'text' &&
        event.replyToken
      ) {
        ctx.waitUntil(handleMessage(env, event.replyToken, event.message.text));
      }
    }
    return new Response('OK', { status: 200 });
  },
};

async function handleMessage(env, replyToken, text) {
  let answer;
  try {
    answer = await askGemini(env, text);
  } catch {
    answer = 'ขออภัยครับ ตอนนี้ผู้ช่วยตอบไม่ได้ชั่วคราว ลองใหม่อีกครั้งนะครับ 🙏';
  }
  await replyText(env.LINE_CHANNEL_ACCESS_TOKEN, replyToken, answer);
}

async function askGemini(env, question) {
  const model = env.GEMINI_MODEL || 'gemini-2.0-flash';
  const url = `${GEMINI_BASE}/models/${model}:generateContent?key=${env.GEMINI_API_KEY}`;
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      system_instruction: { parts: [{ text: SYSTEM_PROMPT }] },
      contents: [{ role: 'user', parts: [{ text: question }] }],
      generationConfig: { maxOutputTokens: 1024 },
    }),
  });
  if (res.status === 429) {
    return 'วันนี้ใช้ AI ฟรีครบโควต้าแล้วครับ ลองใหม่พรุ่งนี้นะครับ 🙏';
  }
  if (!res.ok) {
    return 'ขออภัยครับ ตอนนี้ระบบ AI ไม่ว่าง ลองใหม่อีกครั้งนะครับ 🙏';
  }
  const data = await res.json();
  const parts =
    data &&
    data.candidates &&
    data.candidates[0] &&
    data.candidates[0].content &&
    data.candidates[0].content.parts;
  const out = Array.isArray(parts)
    ? parts.map((p) => (p && p.text) || '').join('')
    : '';
  return out || 'ขออภัยครับ ผมยังไม่มีคำตอบให้ตอนนี้ ลองถามใหม่นะครับ 🙏';
}

async function replyText(token, replyToken, text) {
  await fetch(LINE_REPLY_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify({
      replyToken,
      messages: [{ type: 'text', text: text.slice(0, 4900) }],
    }),
  });
}

async function verifyLineSignature(channelSecret, rawBody, signature) {
  if (!signature) return false;
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(channelSecret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const mac = await crypto.subtle.sign(
    'HMAC',
    key,
    new TextEncoder().encode(rawBody),
  );
  let binary = '';
  for (const b of new Uint8Array(mac)) binary += String.fromCharCode(b);
  const expected = btoa(binary);
  if (expected.length !== signature.length) return false;
  let mismatch = 0;
  for (let i = 0; i < expected.length; i++) {
    mismatch |= expected.charCodeAt(i) ^ signature.charCodeAt(i);
  }
  return mismatch === 0;
}
