/**
 * Ghost Health OS — LINE assistant (standalone copy-paste Cloudflare Worker).
 *
 * Single self-contained file, no build step. Paste into the Cloudflare editor.
 *
 * SECRETS (Worker → Settings → Variables and Secrets):
 *   GEMINI_API_KEY              free key from aistudio.google.com
 *   LINE_CHANNEL_SECRET         LINE → Messaging API → Channel secret
 *   LINE_CHANNEL_ACCESS_TOKEN   LINE → Messaging API → Channel access token
 * Optional plain variable:
 *   GEMINI_MODEL                defaults to "gemini-2.0-flash"
 *
 * OPTIONAL conversation memory — bind a KV namespace named CHAT_MEMORY
 * (Worker → Settings → Bindings → KV namespace). When bound, the bot remembers
 * the last few messages per user until they say "เริ่มใหม่" or go idle ~6h.
 * Without it, the bot still works statelessly.
 */

const SYSTEM_PROMPT = [
  'คุณคือ Ghost โค้ชสุขภาพ AI ส่วนตัว พูดภาษาไทยกระชับ เป็นกันเอง และให้กำลังใจ',
  'กฎสำคัญ:',
  '- ใช้ข้อมูลจากบทสนทนาก่อนหน้าให้ต่อเนื่อง เช่น น้ำหนัก ส่วนสูง เป้าหมายที่ผู้ใช้เคยบอก',
  '- ตอบเชิงให้ความรู้และการดูแลตัวเอง ตอบให้ครบถ้วน ไม่ห้วน',
  '- ห้ามวินิจฉัยโรค โดยเฉพาะเรื่องน้ำตาลในเลือด ให้พูดเชิงแนวโน้มเท่านั้น',
  '- แนะนำให้ปรึกษาแพทย์เมื่อเกี่ยวข้องกับการรักษา',
].join('\n');

const GEMINI_BASE = 'https://generativelanguage.googleapis.com/v1beta';
const LINE_REPLY_URL = 'https://api.line.me/v2/bot/message/reply';
const MEMORY_TURNS = 12; // remember ~6 exchanges (user + bot = 2 per exchange)
const MEMORY_TTL_SECONDS = 6 * 60 * 60; // forget after 6h idle
const RESET_WORDS = ['เริ่มใหม่', 'ล้างความจำ', 'รีเซ็ต', 'reset', 'ลืมไปเลย', 'เปลี่ยนเรื่อง'];

export default {
  async fetch(request, env, ctx) {
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
      if (event.type === 'message' && event.message && event.message.type === 'text' && event.replyToken) {
        const userId = event.source && event.source.userId;
        ctx.waitUntil(handleMessage(env, event.replyToken, userId, event.message.text));
      }
    }
    return new Response('OK', { status: 200 });
  },
};

async function handleMessage(env, replyToken, userId, text) {
  const memory = env.CHAT_MEMORY && userId ? env.CHAT_MEMORY : null;
  const key = userId ? 'chat:' + userId : null;

  // "เริ่มใหม่" clears the conversation memory.
  if (memory && isResetCommand(text)) {
    await memory.delete(key);
    await replyText(env.LINE_CHANNEL_ACCESS_TOKEN, replyToken, 'ล้างความจำแล้วครับ เริ่มเรื่องใหม่ได้เลย 😊');
    return;
  }

  let history = [];
  if (memory) {
    const stored = await memory.get(key);
    if (stored) {
      try {
        history = JSON.parse(stored);
      } catch {
        history = [];
      }
    }
  }

  let result;
  try {
    result = await askGemini(env, history, text);
  } catch {
    result = { text: 'ขออภัยครับ ตอนนี้ผู้ช่วยตอบไม่ได้ชั่วคราว ลองใหม่อีกครั้งนะครับ 🙏', ok: false };
  }

  await replyText(env.LINE_CHANNEL_ACCESS_TOKEN, replyToken, result.text);

  // Only remember real answers, not error/quota messages.
  if (memory && result.ok) {
    history.push({ role: 'user', text });
    history.push({ role: 'model', text: result.text });
    if (history.length > MEMORY_TURNS) {
      history = history.slice(history.length - MEMORY_TURNS);
    }
    await memory.put(key, JSON.stringify(history), { expirationTtl: MEMORY_TTL_SECONDS });
  }
}

function isResetCommand(text) {
  const t = (text || '').trim().toLowerCase();
  return RESET_WORDS.some((w) => t === w.toLowerCase());
}

async function askGemini(env, history, question) {
  const model = env.GEMINI_MODEL || 'gemini-2.0-flash';
  const url = `${GEMINI_BASE}/models/${model}:generateContent?key=${env.GEMINI_API_KEY}`;

  const contents = [];
  for (const h of history) {
    if (h && (h.role === 'user' || h.role === 'model') && h.text) {
      contents.push({ role: h.role, parts: [{ text: h.text }] });
    }
  }
  contents.push({ role: 'user', parts: [{ text: question }] });

  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      system_instruction: { parts: [{ text: SYSTEM_PROMPT }] },
      contents,
      generationConfig: { maxOutputTokens: 2048 },
    }),
  });

  if (res.status === 429) {
    return { text: 'วันนี้ใช้ AI ฟรีครบโควต้าแล้วครับ ลองใหม่อีกสักครู่นะครับ 🙏', ok: false };
  }
  if (!res.ok) {
    return { text: 'ขออภัยครับ ตอนนี้ระบบ AI ไม่ว่าง ลองใหม่อีกครั้งนะครับ 🙏', ok: false };
  }

  const data = await res.json();
  const parts =
    data && data.candidates && data.candidates[0] && data.candidates[0].content && data.candidates[0].content.parts;
  const out = Array.isArray(parts) ? parts.map((p) => (p && p.text) || '').join('') : '';
  if (!out) {
    return { text: 'ขออภัยครับ ผมยังไม่มีคำตอบให้ตอนนี้ ลองถามใหม่นะครับ 🙏', ok: false };
  }
  return { text: out, ok: true };
}

async function replyText(token, replyToken, text) {
  await fetch(LINE_REPLY_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ replyToken, messages: [{ type: 'text', text: text.slice(0, 4900) }] }),
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
  const mac = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(rawBody));
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
