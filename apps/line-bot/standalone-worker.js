/**
 * Ghost Health OS — LINE assistant (standalone copy-paste Cloudflare Worker).
 *
 * Dual-mode personal AI on LINE (health coach + investment expert), powered by
 * Groq's FREE API (Llama models). Live US stock/ETF quotes + news via Finnhub,
 * crypto via CoinGecko, image analysis (charts / health screens / food).
 *
 * SECRETS (Worker → Settings → Variables and Secrets):
 *   GROQ_API_KEY                free key from console.groq.com (no credit card)
 *   LINE_CHANNEL_SECRET, LINE_CHANNEL_ACCESS_TOKEN
 *   FINNHUB_API_KEY             (optional) free key from finnhub.io for live US stocks
 * Optional plain variables:
 *   GROQ_MODEL          default "llama-3.3-70b-versatile"
 *   GROQ_VISION_MODEL   default "meta-llama/llama-4-scout-17b-16e-instruct"
 * Optional KV binding CHAT_MEMORY → remembers mode + recent messages per user.
 */

const HEALTH_PROMPT = [
  'คุณคือ Ghost โค้ชสุขภาพ AI ส่วนตัว ตอบเป็นภาษาไทยเสมอ กระชับ เป็นกันเอง และให้กำลังใจ',
  '- ใช้ข้อมูลจากบทสนทนาก่อนหน้าให้ต่อเนื่อง เช่น น้ำหนัก ส่วนสูง เป้าหมายที่ผู้ใช้เคยบอก',
  '- ตอบเชิงให้ความรู้และการดูแลตัวเอง ตอบให้ครบถ้วน ไม่ห้วน',
  '- ห้ามวินิจฉัยโรค ให้พูดเชิงแนวโน้มเท่านั้น แนะนำให้ปรึกษาแพทย์เมื่อเกี่ยวข้องกับการรักษา',
  '- LINE แสดงตัวหนา/มาร์กดาวน์ไม่ได้ อย่าใช้ ** ## --- ให้ใช้อิโมจิและเว้นบรรทัดแทน',
].join('\n');

const STOCK_PROMPT = [
  'คุณคือ "ผู้เชี่ยวชาญด้านการลงทุนและที่ปรึกษาทางการเงินส่วนตัว" เชี่ยวชาญตลาดหุ้นสหรัฐฯ คริปโต และกองทุน ETF ตอบเป็นภาษาไทยเสมอ',
  'บุคลิก: เพื่อนนักลงทุนรุ่นใหม่ที่เก่งและจริงใจ กระตือรือร้น ใช้ภาษาง่าย ลงท้าย ครับ/ค่ะ เสมอ กล้าเตือนสติตรงๆ และใช้การเปรียบเทียบให้เห็นภาพ',
  'ความเชี่ยวชาญ: เศรษฐกิจมหภาค/Fed/Bond Yield, IPO & Index Inclusion (Buy the Rumor Sell the News, front-running), Dividend & Options ETFs (YieldMax, Covered Call, กับดักปันผล/NAV erosion, tax drag, DRIP), Technical/Sentiment (smart money, wait & see, limit order ช่วง panic, liquidity sweep), หุ้นเสี่ยงสูง/penny (reverse split, dilution) — เตือนผู้ใช้เด็ดขาด',
  'สำคัญ: ถ้ามีบล็อก "ข้อมูลสดล่าสุด" ให้ใช้ตัวเลข/ข่าวนั้นในการวิเคราะห์ และระบุว่าเป็นราคา ณ ตอนนี้ ถ้าไม่มีข้อมูลสดของสิ่งที่ถาม ให้บอกตรงๆ ว่ายังไม่มีข้อมูลสดและตอบเชิงหลักการแทน',
  'การจัดรูปแบบ (LINE ไม่รองรับมาร์กดาวน์): ห้ามใช้ ** ## --- ให้ใช้อิโมจิหัวข้อ (🚀📉📊⚠️💡), เว้นบรรทัด, เน้นด้วย 「คำ」 หรือตัวเลข กระชับ จบด้วย "💡 สรุปคำแนะนำ:" ที่ทำได้จริง',
  'ข้อจำกัด: ห้ามฟันธง/การันตีกำไร เน้นความน่าจะเป็นเชิงสถิติ/เทคนิค ทุกคำตอบเป็นข้อมูลเพื่อการศึกษา ไม่ใช่คำแนะนำการลงทุน',
].join('\n');

const HEALTH_INTRO = '💪 เข้าสู่โหมดสุขภาพแล้วครับ!\nถามได้เลย เช่น "ควรกินโปรตีนเท่าไหร่" หรือ "นอนไม่พอทำไงดี"\n📸 แคปหน้าจอแอปสุขภาพ (Google Health/Fitbit) หรือรูปอาหาร ส่งมาให้สรุป+วิเคราะห์ได้เลย\n(ข้อมูลเพื่อการศึกษา ไม่วินิจฉัยโรคนะครับ)';
const STOCK_INTRO = '📈 เข้าสู่โหมดหุ้นมือโปรแล้วครับ! (ดึงราคาสด + ข่าวได้)\nลองถาม เช่น "ราคา TSLA ตอนนี้ มีข่าวอะไร" / "เทียบ NVDA กับ AMD" / "ราคา bitcoin"\n📸 ส่งภาพกราฟ (เช่น TradingView) มาให้วิเคราะห์เทคนิคได้เลย\n⚠️ ข้อมูลเพื่อการศึกษา ไม่ใช่คำแนะนำการลงทุน';
const WELCOME_TEXT = 'สวัสดีครับ! ผมคือ Ghost ผู้ช่วย AI ส่วนตัวของคุณ 🤖\nกดปุ่มด้านล่างเพื่อเลือกโหมด:\n💪 "โหมดสุขภาพ" — โค้ชสุขภาพ\n📈 "โหมดหุ้น" — ที่ปรึกษาการลงทุน (ราคาสด+ข่าว)\n📸 "ส่งภาพ" — วิเคราะห์กราฟ/หน้าจอสุขภาพ/อาหาร\n🔄 "เริ่มใหม่" — ล้างความจำ';

const IMAGE_SYSTEM_PROMPT =
  'คุณคือผู้ช่วย AI ที่เชี่ยวชาญทั้งการวิเคราะห์กราฟการลงทุน สุขภาพ และโภชนาการ ตอบเป็นภาษาไทยเสมอ กระชับ เป็นกันเอง ไม่วินิจฉัยโรค และไม่ฟันธง/การันตีผลการลงทุน';
const UNIVERSAL_IMAGE_PROMPT =
  'ดูรูปนี้ ระบุเองว่าเป็นประเภทไหน แล้ววิเคราะห์ให้เหมาะสม:\n' +
  '1) กราฟราคา/หุ้น/คริปโต (เช่น TradingView): วิเคราะห์เทคนิคแบบมือโปร — เทรนด์, แนวรับ-แนวต้าน (ใส่ตัวเลขถ้าอ่านได้), รูปแบบ/อินดิเคเตอร์, โซนเข้าซื้อ, จุดตัดขาดทุน (stop loss), เป้ากำไร, ความเสี่ยง/risk-reward. จบด้วยบรรทัดนี้เป๊ะ: "⚠️ (นี่ไม่ใช่การแนะนำการลงทุน เป็นเพียงการคาดการณ์เพื่อการศึกษา)"\n' +
  '2) หน้าจอแอปสุขภาพ/ฟิตเนส (Google Health/Fitbit/Apple Health): อ่านตัวเลขที่เห็น (การนอน/หลับลึก-REM, ชีพจรขณะพัก, ก้าว, แคลอรี, คะแนนความพร้อม) สรุป + แนะนำการดูแลตัวเองวันนี้ ไม่วินิจฉัยโรค\n' +
  '3) รูปอาหาร: ประเมินแคลอรี โปรตีน ไขมัน คาร์โบไฮเดรต และไฟเบอร์โดยประมาณ + คำแนะนำสั้นๆ\n' +
  'ตอบภาษาไทยกระชับ ไม่ใช้มาร์กดาวน์ (ห้ามใช้ ** ## ---) ใช้อิโมจิและเว้นบรรทัดแทน';

const GROQ_URL = 'https://api.groq.com/openai/v1/chat/completions';
const GROQ_TEXT_MODEL = 'llama-3.3-70b-versatile';
const GROQ_VISION_MODEL = 'meta-llama/llama-4-scout-17b-16e-instruct';
const LINE_REPLY_URL = 'https://api.line.me/v2/bot/message/reply';
const FINNHUB_BASE = 'https://finnhub.io/api/v1';
const COINGECKO_BASE = 'https://api.coingecko.com/api/v3';
const MEMORY_TURNS = 12;
const MEMORY_TTL_SECONDS = 6 * 60 * 60;
const RESET_WORDS = ['เริ่มใหม่', 'ล้างความจำ', 'รีเซ็ต', 'reset', 'ลืมไปเลย'];
const STOCK_TRIGGERS = ['โหมดหุ้น', 'โหมดการเงิน', 'โหมดลงทุน'];
const HEALTH_TRIGGERS = ['โหมดสุขภาพ'];

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

const QUOTA_MSG =
  '⏳ ตอนนี้ AI ใช้งานเยอะ ถึงลิมิตชั่วคราวครับ ลองใหม่อีกครั้งใน 1-2 นาทีนะครับ 🙏';

const QUICK_REPLY = {
  items: [
    quickAction('💪 สุขภาพ', 'โหมดสุขภาพ'),
    quickAction('📈 หุ้น', 'โหมดหุ้น'),
    quickCameraRoll('📸 ส่งภาพ'),
    quickAction('🔄 เริ่มใหม่', 'เริ่มใหม่'),
  ],
};
function quickAction(label, text) {
  return { type: 'action', action: { type: 'message', label, text } };
}
function quickCameraRoll(label) {
  return { type: 'action', action: { type: 'cameraRoll', label } };
}

export default {
  async fetch(request, env, ctx) {
    if (request.method !== 'POST') return new Response('Ghost LINE bot is running.', { status: 200 });
    if (!env.GROQ_API_KEY || !env.LINE_CHANNEL_SECRET || !env.LINE_CHANNEL_ACCESS_TOKEN) {
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
      } else if (event.type === 'message' && event.message && event.message.type === 'image' && event.replyToken) {
        const userId = event.source && event.source.userId;
        ctx.waitUntil(handleImage(env, event.replyToken, userId, event.message.id));
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
  try { result = await askLLM(env, systemPrompt, state.history, userContent); }
  catch { result = { text: 'ขออภัยครับ ตอนนี้ผู้ช่วยตอบไม่ได้ชั่วคราว ลองใหม่อีกครั้งนะครับ 🙏', ok: false }; }
  await replyText(token, replyToken, result.text);

  if (memory && result.ok) {
    state.history.push({ role: 'user', text });
    state.history.push({ role: 'model', text: result.text });
    if (state.history.length > MEMORY_TURNS) state.history = state.history.slice(state.history.length - MEMORY_TURNS);
    await saveState(memory, key, state);
  }
}

async function handleImage(env, replyToken, userId, messageId) {
  const memory = env.CHAT_MEMORY && userId ? env.CHAT_MEMORY : null;
  const key = userId ? 'chat:' + userId : null;
  const token = env.LINE_CHANNEL_ACCESS_TOKEN;
  const state = memory ? await loadState(memory, key) : { mode: 'health', history: [] };

  const img = await getLineImage(token, messageId);
  if (!img) {
    await replyText(token, replyToken, 'ขออภัยครับ โหลดรูปไม่สำเร็จ ลองส่งใหม่อีกครั้งนะครับ 🙏');
    return;
  }

  let result;
  try {
    result = await askLLMVision(env, IMAGE_SYSTEM_PROMPT, UNIVERSAL_IMAGE_PROMPT, img.base64, img.mimeType);
  } catch {
    result = { text: 'ขออภัยครับ วิเคราะห์รูปไม่ได้ชั่วคราว ลองใหม่อีกครั้งนะครับ 🙏', ok: false };
  }
  await replyText(token, replyToken, result.text);

  if (memory && result.ok) {
    state.history.push({ role: 'user', text: '[ผู้ใช้ส่งรูปมาให้วิเคราะห์]' });
    state.history.push({ role: 'model', text: result.text });
    if (state.history.length > MEMORY_TURNS) state.history = state.history.slice(state.history.length - MEMORY_TURNS);
    await saveState(memory, key, state);
  }
}

async function getLineImage(token, messageId) {
  try {
    const res = await fetch(`https://api-data.line.me/v2/bot/message/${messageId}/content`, {
      headers: { Authorization: 'Bearer ' + token },
    });
    if (!res.ok) return null;
    const buf = await res.arrayBuffer();
    let mime = res.headers.get('content-type') || 'image/jpeg';
    if (!/^image\//.test(mime)) mime = 'image/jpeg';
    return { base64: arrayBufferToBase64(buf), mimeType: mime };
  } catch {
    return null;
  }
}

function arrayBufferToBase64(buffer) {
  const bytes = new Uint8Array(buffer);
  let binary = '';
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
  }
  return btoa(binary);
}

// ---------- live market data ----------

async function fetchLiveContext(env, text) {
  const blocks = [];
  const wantsNews = /ข่าว|news/i.test(text);
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
    if (wantsNews && blocks.length === 0) {
      const market = await finnhubMarketNews(env);
      if (market) blocks.push(market);
    }
  }
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

// ---------- LLM (Groq, free) ----------

async function askLLM(env, systemPrompt, history, userContent) {
  const messages = [{ role: 'system', content: systemPrompt }];
  for (const h of history) {
    if (h && (h.role === 'user' || h.role === 'model') && h.text) {
      messages.push({ role: h.role === 'model' ? 'assistant' : 'user', content: h.text });
    }
  }
  messages.push({ role: 'user', content: userContent });
  return callGroq(env, env.GROQ_MODEL || GROQ_TEXT_MODEL, messages);
}

async function askLLMVision(env, systemPrompt, promptText, base64, mimeType) {
  const messages = [
    { role: 'system', content: systemPrompt },
    {
      role: 'user',
      content: [
        { type: 'text', text: promptText },
        { type: 'image_url', image_url: { url: `data:${mimeType};base64,${base64}` } },
      ],
    },
  ];
  return callGroq(env, env.GROQ_VISION_MODEL || GROQ_VISION_MODEL, messages);
}

async function callGroq(env, model, messages) {
  let res;
  try {
    res = await fetch(GROQ_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + env.GROQ_API_KEY },
      body: JSON.stringify({ model, messages, max_tokens: 2048, temperature: 0.5 }),
    });
  } catch (cause) {
    return { text: 'ขออภัยครับ เชื่อมต่อ AI ไม่ได้ ลองใหม่อีกครั้งนะครับ 🙏', ok: false };
  }
  if (res.status === 429) {
    const d = await llmErrorDetail(res);
    return { text: QUOTA_MSG + (d ? '\n\n🔧 (debug) ' + d.slice(0, 350) : ''), ok: false };
  }
  if (!res.ok) {
    const d = await llmErrorDetail(res);
    return { text: 'ขออภัยครับ ระบบ AI มีปัญหา (สถานะ ' + res.status + ')' + (d ? '\n🔧 (debug) ' + d.slice(0, 350) : ''), ok: false };
  }
  const data = await res.json();
  const out = data && data.choices && data.choices[0] && data.choices[0].message && data.choices[0].message.content;
  if (!out) return { text: 'ขออภัยครับ ผมยังไม่มีคำตอบให้ตอนนี้ ลองถามใหม่นะครับ 🙏', ok: false };
  return { text: out, ok: true };
}

async function llmErrorDetail(res) {
  try {
    const e = await res.json();
    return (e && e.error && e.error.message) || '';
  } catch {
    return '';
  }
}

async function replyText(token, replyToken, text) {
  await fetch(LINE_REPLY_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + token },
    body: JSON.stringify({ replyToken, messages: [{ type: 'text', text: String(text).slice(0, 4900), quickReply: QUICK_REPLY }] }),
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
