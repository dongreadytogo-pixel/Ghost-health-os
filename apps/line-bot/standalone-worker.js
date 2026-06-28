/**
 * Ghost Health OS — LINE assistant (standalone copy-paste Cloudflare Worker).
 *
 * Multi-mode personal AI on LINE: a health coach and an investment expert,
 * switchable with quick-reply buttons. Single self-contained file, no build.
 *
 * SECRETS (Worker → Settings → Variables and Secrets):
 *   GEMINI_API_KEY, LINE_CHANNEL_SECRET, LINE_CHANNEL_ACCESS_TOKEN
 * Optional plain variable: GEMINI_MODEL (default "gemini-2.0-flash")
 * Optional KV binding named CHAT_MEMORY → remembers mode + recent messages
 * per user (6h idle). Without it, the bot still works but won't remember.
 */

const HEALTH_PROMPT = [
  'คุณคือ Ghost โค้ชสุขภาพ AI ส่วนตัว พูดภาษาไทยกระชับ เป็นกันเอง และให้กำลังใจ',
  '- ใช้ข้อมูลจากบทสนทนาก่อนหน้าให้ต่อเนื่อง เช่น น้ำหนัก ส่วนสูง เป้าหมายที่ผู้ใช้เคยบอก',
  '- ตอบเชิงให้ความรู้และการดูแลตัวเอง ตอบให้ครบถ้วน ไม่ห้วน',
  '- ห้ามวินิจฉัยโรค โดยเฉพาะเรื่องน้ำตาลในเลือด ให้พูดเชิงแนวโน้มเท่านั้น',
  '- แนะนำให้ปรึกษาแพทย์เมื่อเกี่ยวข้องกับการรักษา',
  '- LINE แสดงตัวหนา/มาร์กดาวน์ไม่ได้ อย่าใช้ ** ## --- ให้ใช้อิโมจิและเว้นบรรทัดแทน',
].join('\n');

const STOCK_PROMPT = [
  'คุณคือ "ผู้เชี่ยวชาญด้านการลงทุนและที่ปรึกษาทางการเงินส่วนตัว" เชี่ยวชาญตลาดหุ้นสหรัฐฯ คริปโต และกองทุน ETF',
  'บุคลิก: เพื่อนนักลงทุนรุ่นใหม่ที่เก่งและจริงใจ กระตือรือร้น ใช้ภาษาง่าย ลงท้าย ครับ/ค่ะ เสมอ กล้าเตือนสติตรงๆ เมื่อผู้ใช้กำลังตัดสินใจพลาด และใช้การเปรียบเทียบให้เห็นภาพ',
  'ความเชี่ยวชาญ:',
  '- เศรษฐกิจมหภาค/จุลภาค: ดอกเบี้ย เงินเฟ้อ Bond Yield นโยบาย Fed, Global Tech Sell-off',
  '- IPO & Index Inclusion: กลไก IPO, Fast Entry ของ Nasdaq/S&P 500, "Buy the Rumor, Sell the News", front-running ของสถาบัน',
  '- Dividend & Options ETFs (เช่น YieldMax, Covered Call): ปันผลสูง, วัน XD, กับดักปันผล (NAV erosion), ภาระภาษี (tax drag), กลยุทธ์ DRIP ทบต้น',
  '- Technical & Sentiment: กลยุทธ์ smart money, wait & see, ตั้ง limit order ช่วง panic, อ่านแรงขายสถาบัน, liquidity sweep',
  '- หุ้นเสี่ยงสูง/penny stock: หุ้นปั่น พื้นฐานแย่ reverse split หนีตาย, dilution risk — เตือนผู้ใช้อย่างเด็ดขาด',
  'การจัดรูปแบบ (LINE แสดงมาร์กดาวน์ไม่ได้):',
  '- ห้ามใช้ ** ## --- ให้ใช้อิโมจิหัวข้อ (🚀 📉 📊 ⚠️ 💡), เว้นบรรทัด, เน้นด้วย 「คำ」 หรือตัวเลขชัดๆ',
  '- กระชับ เหมาะอ่านบนมือถือ ไม่ยืดยาว',
  '- จบทุกครั้งด้วย "💡 สรุปคำแนะนำ:" ที่ทำได้จริง (เช่น รอดูสถานการณ์ แบ่งไม้ซื้อ โฟกัสทบต้นระยะยาว)',
  'เตือนความเสี่ยง: ถ้าถามเรื่องช้อนซื้อ/รับมีด ตอนตลาดลงแรง หรือหุ้นปั่น ให้เตือนสติชัดเจน พร้อมเสนอทางเลือกที่ปลอดภัยกว่า',
  'ข้อจำกัด:',
  '- ห้ามฟันธงหรือการันตีกำไร เน้นวิเคราะห์ความน่าจะเป็นเชิงสถิติ/เทคนิค',
  '- คุณไม่มีข้อมูลราคาเรียลไทม์ ถ้าถูกถามราคาปัจจุบัน ให้บอกตรงๆ ว่าให้เช็คจากแอปโบรกเกอร์',
  '- ทุกคำตอบเป็นข้อมูลเพื่อการศึกษา ไม่ใช่คำแนะนำการลงทุน',
].join('\n');

const HEALTH_INTRO =
  '💪 เข้าสู่โหมดสุขภาพแล้วครับ!\nถามได้เลย เช่น "ควรกินโปรตีนเท่าไหร่" หรือ "นอนไม่พอทำไงดี"\n(ข้อมูลเพื่อการศึกษา ไม่วินิจฉัยโรคนะครับ)';
const STOCK_INTRO =
  '📈 เข้าสู่โหมดหุ้น/การลงทุนแล้วครับ!\nถามได้เลย เช่น "ETF ปันผลสูงเสี่ยงไหม" หรือ "Covered Call ทำงานยังไง"\n⚠️ ข้อมูลเพื่อการศึกษา ไม่ใช่คำแนะนำการลงทุน และผมไม่รู้ราคาเรียลไทม์ครับ';
const WELCOME_TEXT =
  'สวัสดีครับ! ผมคือ Ghost ผู้ช่วย AI ส่วนตัวของคุณ 🤖\nเลือกเรื่องที่อยากคุยได้เลย หรือกดปุ่มด้านล่าง:\n💪 "โหมดสุขภาพ" — โค้ชสุขภาพ\n📈 "โหมดหุ้น" — ที่ปรึกษาการลงทุน\n🔄 "เริ่มใหม่" — ล้างความจำ เริ่มเรื่องใหม่';

const GEMINI_BASE = 'https://generativelanguage.googleapis.com/v1beta';
const LINE_REPLY_URL = 'https://api.line.me/v2/bot/message/reply';
const MEMORY_TURNS = 12;
const MEMORY_TTL_SECONDS = 6 * 60 * 60;
const RESET_WORDS = ['เริ่มใหม่', 'ล้างความจำ', 'รีเซ็ต', 'reset', 'ลืมไปเลย'];
const STOCK_TRIGGERS = ['โหมดหุ้น', 'โหมดการเงิน', 'โหมดลงทุน'];
const HEALTH_TRIGGERS = ['โหมดสุขภาพ'];

const QUICK_REPLY = {
  items: [
    quickAction('💪 สุขภาพ', 'โหมดสุขภาพ'),
    quickAction('📈 หุ้น', 'โหมดหุ้น'),
    quickAction('🔄 เริ่มใหม่', 'เริ่มใหม่'),
  ],
};
function quickAction(label, text) {
  return { type: 'action', action: { type: 'message', label, text } };
}

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
      if (event.type === 'follow' && event.replyToken) {
        ctx.waitUntil(replyText(env.LINE_CHANNEL_ACCESS_TOKEN, event.replyToken, WELCOME_TEXT));
      } else if (event.type === 'message' && event.message && event.message.type === 'text' && event.replyToken) {
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
  const token = env.LINE_CHANNEL_ACCESS_TOKEN;
  const trimmed = (text || '').trim();

  let state = memory ? await loadState(memory, key) : { mode: 'health', history: [] };

  if (isOneOf(trimmed, RESET_WORDS)) {
    state.history = [];
    if (memory) await saveState(memory, key, state);
    await replyText(token, replyToken, 'ล้างความจำแล้วครับ เริ่มเรื่องใหม่ได้เลย 😊 (ตอนนี้อยู่' + modeLabel(state.mode) + ')');
    return;
  }
  if (isOneOf(trimmed, STOCK_TRIGGERS)) {
    state.mode = 'stock';
    state.history = [];
    if (memory) await saveState(memory, key, state);
    await replyText(token, replyToken, STOCK_INTRO);
    return;
  }
  if (isOneOf(trimmed, HEALTH_TRIGGERS)) {
    state.mode = 'health';
    state.history = [];
    if (memory) await saveState(memory, key, state);
    await replyText(token, replyToken, HEALTH_INTRO);
    return;
  }

  const systemPrompt = state.mode === 'stock' ? STOCK_PROMPT : HEALTH_PROMPT;
  let result;
  try {
    result = await askGemini(env, systemPrompt, state.history, text);
  } catch {
    result = { text: 'ขออภัยครับ ตอนนี้ผู้ช่วยตอบไม่ได้ชั่วคราว ลองใหม่อีกครั้งนะครับ 🙏', ok: false };
  }
  await replyText(token, replyToken, result.text);

  if (memory && result.ok) {
    state.history.push({ role: 'user', text });
    state.history.push({ role: 'model', text: result.text });
    if (state.history.length > MEMORY_TURNS) state.history = state.history.slice(state.history.length - MEMORY_TURNS);
    await saveState(memory, key, state);
  }
}

function modeLabel(mode) {
  return mode === 'stock' ? 'โหมดหุ้น' : 'โหมดสุขภาพ';
}

function isOneOf(text, list) {
  const t = text.toLowerCase();
  return list.some((w) => t === w.toLowerCase());
}

async function loadState(memory, key) {
  const stored = await memory.get(key);
  if (!stored) return { mode: 'health', history: [] };
  try {
    const p = JSON.parse(stored);
    if (Array.isArray(p)) return { mode: 'health', history: p }; // old format
    return {
      mode: p.mode === 'stock' ? 'stock' : 'health',
      history: Array.isArray(p.history) ? p.history : [],
    };
  } catch {
    return { mode: 'health', history: [] };
  }
}

async function saveState(memory, key, state) {
  await memory.put(key, JSON.stringify(state), { expirationTtl: MEMORY_TTL_SECONDS });
}

async function askGemini(env, systemPrompt, history, question) {
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
      system_instruction: { parts: [{ text: systemPrompt }] },
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
  const parts = data && data.candidates && data.candidates[0] && data.candidates[0].content && data.candidates[0].content.parts;
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
    body: JSON.stringify({
      replyToken,
      messages: [{ type: 'text', text: text.slice(0, 4900), quickReply: QUICK_REPLY }],
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
  const mac = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(rawBody));
  let binary = '';
  for (const b of new Uint8Array(mac)) binary += String.fromCharCode(b);
  const expected = btoa(binary);
  if (expected.length !== signature.length) return false;
  let mismatch = 0;
  for (let i = 0; i < expected.length; i++) mismatch |= expected.charCodeAt(i) ^ signature.charCodeAt(i);
  return mismatch === 0;
}
