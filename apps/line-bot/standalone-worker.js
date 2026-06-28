/**
 * Ghost Health OS — LINE assistant (standalone copy-paste Cloudflare Worker).
 *
 * Dual-mode personal AI on LINE:
 *   • Health coach
 *   • Investment expert with LIVE data — real-time US stock/ETF quotes + news
 *     (Finnhub) and crypto prices (CoinGecko). The bot fetches live data itself
 *     when you ask about a ticker, price, or news, then analyses it in-persona.
 *
 * SECRETS (Worker → Settings → Variables and Secrets):
 *   GEMINI_API_KEY, LINE_CHANNEL_SECRET, LINE_CHANNEL_ACCESS_TOKEN
 *   FINNHUB_API_KEY   (free key from finnhub.io — for live US stock data + news)
 * Optional plain variable: GEMINI_MODEL (default "gemini-2.0-flash")
 * Optional KV binding CHAT_MEMORY → remembers mode + recent messages per user.
 */

const HEALTH_PROMPT = [
  'คุณคือ Ghost โค้ชสุขภาพ AI ส่วนตัว พูดภาษาไทยกระชับ เป็นกันเอง และให้กำลังใจ',
  '- ใช้ข้อมูลจากบทสนทนาก่อนหน้าให้ต่อเนื่อง เช่น น้ำหนัก ส่วนสูง เป้าหมายที่ผู้ใช้เคยบอก',
  '- ตอบเชิงให้ความรู้และการดูแลตัวเอง ตอบให้ครบถ้วน ไม่ห้วน',
  '- ห้ามวินิจฉัยโรค ให้พูดเชิงแนวโน้มเท่านั้น แนะนำให้ปรึกษาแพทย์เมื่อเกี่ยวข้องกับการรักษา',
  '- LINE แสดงตัวหนา/มาร์กดาวน์ไม่ได้ อย่าใช้ ** ## --- ให้ใช้อิโมจิและเว้นบรรทัดแทน',
].join('\n');

const STOCK_PROMPT = [
  'คุณคือ "ผู้เชี่ยวชาญด้านการลงทุนและที่ปรึกษาทางการเงินส่วนตัว" เชี่ยวชาญตลาดหุ้นสหรัฐฯ คริปโต และกองทุน ETF',
  'บุคลิก: เพื่อนนักลงทุนรุ่นใหม่ที่เก่งและจริงใจ กระตือรือร้น ใช้ภาษาง่าย ลงท้าย ครับ/ค่ะ เสมอ กล้าเตือนสติตรงๆ และใช้การเปรียบเทียบให้เห็นภาพ',
  'ความเชี่ยวชาญ: เศรษฐกิจมหภาค/Fed/Bond Yield, IPO & Index Inclusion (Buy the Rumor Sell the News, front-running), Dividend & Options ETFs (YieldMax, Covered Call, กับดักปันผล/NAV erosion, tax drag, DRIP), Technical/Sentiment (smart money, wait & see, limit order ช่วง panic, liquidity sweep), หุ้นเสี่ยงสูง/penny (reverse split, dilution) — เตือนผู้ใช้เด็ดขาด',
  'สำคัญ: ถ้ามีบล็อก "ข้อมูลสดล่าสุด" ให้ใช้ตัวเลข/ข่าวนั้นในการวิเคราะห์ และระบุว่าเป็นราคา ณ ตอนนี้ ถ้าไม่มีข้อมูลสดของสิ่งที่ถาม ให้บอกตรงๆ ว่ายังไม่มีข้อมูลสดและตอบเชิงหลักการแทน',
  'การจัดรูปแบบ (LINE ไม่รองรับมาร์กดาวน์): ห้ามใช้ ** ## --- ให้ใช้อิโมจิหัวข้อ (🚀📉📊⚠️💡), เว้นบรรทัด, เน้นด้วย 「คำ」 หรือตัวเลข กระชับ จบด้วย "💡 สรุปคำแนะนำ:" ที่ทำได้จริง',
  'ข้อจำกัด: ห้ามฟันธง/การันตีกำไร เน้นความน่าจะเป็นเชิงสถิติ/เทคนิค ทุกคำตอบเป็นข้อมูลเพื่อการศึกษา ไม่ใช่คำแนะนำการลงทุน',
].join('\n');

const HEALTH_INTRO = '💪 เข้าสู่โหมดสุขภาพแล้วครับ!\nถามได้เลย เช่น "ควรกินโปรตีนเท่าไหร่" หรือ "นอนไม่พอทำไงดี"\n(ข้อมูลเพื่อการศึกษา ไม่วินิจฉัยโรคนะครับ)';
const STOCK_INTRO = '📈 เข้าสู่โหมดหุ้นมือโปรแล้วครับ! (ดึงราคาสด + ข่าวได้)\nลองถาม เช่น "ราคา TSLA ตอนนี้ มีข่าวอะไร" / "เทียบ NVDA กับ AMD" / "ราคา bitcoin"\n⚠️ ข้อมูลเพื่อการศึกษา ไม่ใช่คำแนะนำการลงทุน';
const WELCOME_TEXT = 'สวัสดีครับ! ผมคือ Ghost ผู้ช่วย AI ส่วนตัวของคุณ 🤖\nกดปุ่มด้านล่างเพื่อเลือกโหมด:\n💪 "โหมดสุขภาพ" — โค้ชสุขภาพ\n📈 "โหมดหุ้น" — ที่ปรึกษาการลงทุน (ราคาสด+ข่าว)\n🔄 "เริ่มใหม่" — ล้างความจำ';

const GEMINI_BASE = 'https://generativelanguage.googleapis.com/v1beta';
const LINE_REPLY_URL = 'https://api.line.me/v2/bot/message/reply';
const FINNHUB_BASE = 'https://finnhub.io/api/v1';
const COINGECKO_BASE = 'https://api.coingecko.com/api/v3';
const MEMORY_TURNS = 12;
const MEMORY_TTL_SECONDS = 6 * 60 * 60;
const RESET_WORDS = ['เริ่มใหม่', 'ล้างความจำ', 'รีเซ็ต', 'reset', 'ลืมไปเลย'];
const STOCK_TRIGGERS = ['โหมดหุ้น', 'โหมดการเงิน', 'โหมดลงทุน'];
const HEALTH_TRIGGERS = ['โหมดสุขภาพ'];

// Uppercase tokens that look like tickers but aren't, so we don't waste lookups.
const TICKER_STOPWORDS = new Set([
  'ETF', 'ETFS', 'USD', 'THB', 'IPO', 'FED', 'NAV', 'XD', 'DRIP', 'CEO', 'CFO',
  'USA', 'AI', 'US', 'GDP', 'CPI', 'PE', 'EPS', 'ATH', 'DCA', 'YOLO', 'NYSE',
  'NASDAQ', 'SET', 'SEC', 'API', 'NFT', 'APR', 'APY', 'ROE', 'ROI', 'AM', 'PM',
  'OK', 'TH', 'EU', 'UK', 'QQQ',
]);
const CRYPTO_MAP = {
  bitcoin: 'bitcoin', btc: 'bitcoin', 'บิทคอยน์': 'bitcoin', 'บิตคอยน์': 'bitcoin',
  ethereum: 'ethereum', eth: 'ethereum', 'อีเธอเรียม': 'ethereum',
  bnb: 'binancecoin', solana: 'solana', sol: 'solana', xrp: 'ripple', ripple: 'ripple',
  dogecoin: 'dogecoin', doge: 'dogecoin', cardano: 'cardano', ada: 'cardano',
};

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
    if (request.method !== 'POST') return new Response('Ghost LINE bot is running.', { status: 200 });
    if (!env.GEMINI_API_KEY || !env.LINE_CHANNEL_SECRET || !env.LINE_CHANNEL_ACCESS_TOKEN) {
      return new Response('Server not configured', { status: 500 });
    }
    const raw = await request.text();
    const signature = request.headers.get('x-line-signature');
    if (!(await verifyLineSignature(env.LINE_CHANNEL_SECRET, raw, signature))) {
      return new Response('Invalid signature', { status: 401 });
    }
    let body;
    try { body = JSON.parse(raw); } catch { return new Response('Bad JSON', { status: 400 }); }
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
    state.mode = 'stock'; state.history = [];
    if (memory) await saveState(memory, key, state);
    await replyText(token, replyToken, STOCK_INTRO);
    return;
  }
  if (isOneOf(trimmed, HEALTH_TRIGGERS)) {
    state.mode = 'health'; state.history = [];
    if (memory) await saveState(memory, key, state);
    await replyText(token, replyToken, HEALTH_INTRO);
    return;
  }

  const systemPrompt = state.mode === 'stock' ? STOCK_PROMPT : HEALTH_PROMPT;
  let userContent = text;
  if (state.mode === 'stock') {
    let live = '';
    try { live = await fetchLiveContext(env, text); } catch { live = ''; }
    if (live) userContent = '📊 ข้อมูลสดล่าสุด (ใช้อ้างอิงในการวิเคราะห์):\n' + live + '\n\n[คำถามของผู้ใช้]: ' + text;
  }

  let result;
  try { result = await askGemini(env, systemPrompt, state.history, userContent); }
  catch { result = { text: 'ขออภัยครับ ตอนนี้ผู้ช่วยตอบไม่ได้ชั่วคราว ลองใหม่อีกครั้งนะครับ 🙏', ok: false }; }
  await replyText(token, replyToken, result.text);

  if (memory && result.ok) {
    state.history.push({ role: 'user', text }); // store original question, not injected data
    state.history.push({ role: 'model', text: result.text });
    if (state.history.length > MEMORY_TURNS) state.history = state.history.slice(state.history.length - MEMORY_TURNS);
    await saveState(memory, key, state);
  }
}

// ---------- live market data ----------

async function fetchLiveContext(env, text) {
  const blocks = [];
  const wantsNews = /ข่าว|news/i.test(text);

  // US stocks / ETFs — validated by Finnhub (only kept if a real price comes back)
  if (env.FINNHUB_API_KEY) {
    const candidates = extractTickers(text).slice(0, 3);
    for (const sym of candidates) {
      const q = await finnhubQuote(env, sym);
      if (q && typeof q.c === 'number' && q.c > 0) {
        blocks.push(formatQuote(sym, q));
        if (wantsNews) {
          const news = await finnhubCompanyNews(env, sym);
          if (news) blocks.push(news);
        }
      }
    }
    // general market news when asked but no specific ticker found
    if (wantsNews && blocks.length === 0) {
      const market = await finnhubMarketNews(env);
      if (market) blocks.push(market);
    }
  }

  // Crypto via CoinGecko (no key needed)
  const cryptoIds = extractCrypto(text).slice(0, 3);
  if (cryptoIds.length) {
    const prices = await coingeckoPrices(cryptoIds);
    if (prices) blocks.push(prices);
  }

  return blocks.join('\n\n');
}

function extractTickers(text) {
  const found = new Set();
  for (const m of text.matchAll(/\$([A-Za-z]{1,5})/g)) found.add(m[1].toUpperCase());
  for (const m of text.matchAll(/\b[A-Z]{2,5}\b/g)) {
    const t = m[0].toUpperCase();
    if (!TICKER_STOPWORDS.has(t)) found.add(t);
  }
  return [...found];
}

function extractCrypto(text) {
  const t = text.toLowerCase();
  const ids = new Set();
  for (const k in CRYPTO_MAP) {
    const ascii = /^[a-z]+$/.test(k);
    const hit = ascii ? new RegExp('\\b' + k + '\\b').test(t) : t.includes(k);
    if (hit) ids.add(CRYPTO_MAP[k]);
  }
  return [...ids];
}

async function finnhubQuote(env, symbol) {
  try {
    const res = await fetch(`${FINNHUB_BASE}/quote?symbol=${encodeURIComponent(symbol)}&token=${env.FINNHUB_API_KEY}`);
    if (!res.ok) return null;
    return await res.json();
  } catch {
    return null;
  }
}

function formatQuote(sym, q) {
  const sign = q.d >= 0 ? '+' : '';
  const dp = typeof q.dp === 'number' ? q.dp.toFixed(2) : '?';
  return `📊 ${sym}: $${q.c} (${sign}${dp}% วันนี้)\nเปิด $${q.o} | สูง $${q.h} | ต่ำ $${q.l} | ปิดก่อนหน้า $${q.pc}`;
}

async function finnhubCompanyNews(env, symbol) {
  try {
    const to = new Date();
    const from = new Date(to.getTime() - 7 * 24 * 60 * 60 * 1000);
    const fmt = (d) => d.toISOString().slice(0, 10);
    const res = await fetch(`${FINNHUB_BASE}/company-news?symbol=${encodeURIComponent(symbol)}&from=${fmt(from)}&to=${fmt(to)}&token=${env.FINNHUB_API_KEY}`);
    if (!res.ok) return null;
    const arr = await res.json();
    if (!Array.isArray(arr) || arr.length === 0) return null;
    const items = arr.slice(0, 3).map((n) => `• ${n.headline}`);
    return `📰 ข่าว ${symbol} ล่าสุด:\n${items.join('\n')}`;
  } catch {
    return null;
  }
}

async function finnhubMarketNews(env) {
  try {
    const res = await fetch(`${FINNHUB_BASE}/news?category=general&token=${env.FINNHUB_API_KEY}`);
    if (!res.ok) return null;
    const arr = await res.json();
    if (!Array.isArray(arr) || arr.length === 0) return null;
    const items = arr.slice(0, 4).map((n) => `• ${n.headline}`);
    return `📰 ข่าวตลาดล่าสุด:\n${items.join('\n')}`;
  } catch {
    return null;
  }
}

async function coingeckoPrices(ids) {
  try {
    const res = await fetch(`${COINGECKO_BASE}/simple/price?ids=${ids.join(',')}&vs_currencies=usd,thb&include_24hr_change=true`);
    if (!res.ok) return null;
    const data = await res.json();
    const lines = [];
    for (const id of ids) {
      const d = data[id];
      if (!d) continue;
      const ch = typeof d.usd_24h_change === 'number' ? d.usd_24h_change.toFixed(2) : '?';
      const sign = d.usd_24h_change >= 0 ? '+' : '';
      lines.push(`🪙 ${id}: $${d.usd} (${sign}${ch}% 24ชม.) | ≈ ฿${d.thb}`);
    }
    return lines.length ? lines.join('\n') : null;
  } catch {
    return null;
  }
}

// ---------- state ----------

function modeLabel(mode) { return mode === 'stock' ? 'โหมดหุ้น' : 'โหมดสุขภาพ'; }
function isOneOf(text, list) { const t = text.toLowerCase(); return list.some((w) => t === w.toLowerCase()); }

async function loadState(memory, key) {
  const stored = await memory.get(key);
  if (!stored) return { mode: 'health', history: [] };
  try {
    const p = JSON.parse(stored);
    if (Array.isArray(p)) return { mode: 'health', history: p };
    return { mode: p.mode === 'stock' ? 'stock' : 'health', history: Array.isArray(p.history) ? p.history : [] };
  } catch { return { mode: 'health', history: [] }; }
}
async function saveState(memory, key, state) {
  await memory.put(key, JSON.stringify(state), { expirationTtl: MEMORY_TTL_SECONDS });
}

// ---------- Gemini + LINE ----------

async function askGemini(env, systemPrompt, history, userContent) {
  const model = env.GEMINI_MODEL || 'gemini-2.0-flash';
  const url = `${GEMINI_BASE}/models/${model}:generateContent?key=${env.GEMINI_API_KEY}`;
  const contents = [];
  for (const h of history) {
    if (h && (h.role === 'user' || h.role === 'model') && h.text) contents.push({ role: h.role, parts: [{ text: h.text }] });
  }
  contents.push({ role: 'user', parts: [{ text: userContent }] });
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ system_instruction: { parts: [{ text: systemPrompt }] }, contents, generationConfig: { maxOutputTokens: 2048 } }),
  });
  if (res.status === 429) return { text: 'วันนี้ใช้ AI ฟรีครบโควต้าแล้วครับ ลองใหม่อีกสักครู่นะครับ 🙏', ok: false };
  if (!res.ok) return { text: 'ขออภัยครับ ตอนนี้ระบบ AI ไม่ว่าง ลองใหม่อีกครั้งนะครับ 🙏', ok: false };
  const data = await res.json();
  const parts = data && data.candidates && data.candidates[0] && data.candidates[0].content && data.candidates[0].content.parts;
  const out = Array.isArray(parts) ? parts.map((p) => (p && p.text) || '').join('') : '';
  if (!out) return { text: 'ขออภัยครับ ผมยังไม่มีคำตอบให้ตอนนี้ ลองถามใหม่นะครับ 🙏', ok: false };
  return { text: out, ok: true };
}

async function replyText(token, replyToken, text) {
  await fetch(LINE_REPLY_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ replyToken, messages: [{ type: 'text', text: text.slice(0, 4900), quickReply: QUICK_REPLY }] }),
  });
}

async function verifyLineSignature(channelSecret, rawBody, signature) {
  if (!signature) return false;
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(channelSecret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const mac = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(rawBody));
  let binary = '';
  for (const b of new Uint8Array(mac)) binary += String.fromCharCode(b);
  const expected = btoa(binary);
  if (expected.length !== signature.length) return false;
  let mismatch = 0;
  for (let i = 0; i < expected.length; i++) mismatch |= expected.charCodeAt(i) ^ signature.charCodeAt(i);
  return mismatch === 0;
}
