# SUBTITLE Cover — เอกสารส่งมอบฉบับสมบูรณ์ (สำหรับนำไปรวมกับโปรเจกต์อื่น)

> เอกสารนี้เขียนขึ้นเพื่อให้ Claude Code (หรือ AI/นักพัฒนาคนอื่น) นำโปรแกรมนี้ไปรวมกับ
> โปรเจกต์อื่นได้โดย **ไม่ตกหล่นความรู้ใดๆ** ที่สั่งสมมาจากการลองผิดลองถูกจริงหลายสิบรอบ
> ทั้งโค้ดเต็ม 100%, ค่าคงที่ทุกตัวพร้อมที่มา, กฎ FCPXML ที่ไม่มีเอกสารทางการไหนบอก,
> และ **บั๊กที่ยังแก้ไม่เสร็จ ณ ตอนส่งมอบ** (สำคัญมาก — อย่าข้าม อยู่หัวข้อท้ายสุด)

---

## 1. โปรแกรมนี้คืออะไร / ทำอะไร

**SUBTITLE Cover** เป็นแอป macOS (Python + Tkinter, แพ็กเป็น `.app`) ที่:

1. อ่านไฟล์ **FCPXML** ที่ export จากโปรเจกต์ **Final Cut Pro** (คลิปรีวิวสินค้าสุขภาพ แนวตั้ง TikTok/9:16)
2. หา **ซับไตเติ้ลเดิม** (title ที่ผู้ใช้พิมพ์ไว้ในไทม์ไลน์แล้ว ตรงเวลากับเสียงพูด)
3. สำหรับซับแต่ละอัน แบ่งข้อความเป็น **2 บรรทัด** อัตโนมัติแบบ "ฉลาด" (ไม่ตัดกลางคำ, ดันคำเด่นไปบรรทัดล่าง)
   หรือ **1 บรรทัดเดียว** ถ้าประโยคสั้น
4. สร้าง **เลเยอร์ไฮไลต์ใหม่** (Pop-up Text 2 อัน แยกกัน — บรรทัดบนสีขาว, บรรทัดล่างสีส้ม)
   วางซ้อนเหนือซับเดิม **ตรงเวลาเป๊ะ** พร้อมแอนิเมชันป๊อบอัพ (เด้งเข้า-ออก)
5. เขียนเป็นไฟล์ FCPXML ใหม่ (`{ชื่อโปรเจกต์}_cover.fcpxml`) — **ซับเดิมในไฟล์ต้นฉบับไม่ถูกแตะต้องเลย**
6. ผู้ใช้ import ไฟล์นี้กลับเข้า FCP (`File → Import → XML → Keep Both`) จะได้โปรเจกต์สำเนาที่มีทั้งซับเดิม + ไฮไลต์ใหม่ซ้อนกัน

**เป้าหมายการออกแบบ**: ระบบต้อง "ฉลาดเหมือนกราฟิกดีไซเนอร์มืออาชีพ" — ขนาดตัวอักษรเต็มเฟรมแต่ไม่ล้น
ไม่ทับกันแต่ก็ไม่ห่างเกิน ตัดคำไม่เสียอรรถรส และ **ตรวจสอบตัวเองก่อนเขียนไฟล์เสมอ** (ห้ามส่งงานพลาดออกไป)

---

## 2. โครงสร้างไฟล์ทั้งหมด (สำเนาปัจจุบัน)

```
SUBTITLE Cover/
├── HANDOFF_FOR_CLAUDE_CODE.md      <- ไฟล์นี้
├── README.md                        <- คู่มือผู้ใช้ (ภาษาไทย)
└── SUBTITLE Cover.app/
    └── Contents/
        ├── Info.plist                          <- metadata ของแอป
        ├── MacOS/
        │   └── SUBTITLE Cover                  <- launcher script (bash)
        └── Resources/
            ├── cover_subtitles.py               <- แกนหลัก (อ่าน XML + สร้าง cover + ตรวจสอบ)
            └── cover_gui.py                     <- หน้าตาโปรแกรม (Tkinter GUI)
```

**สำคัญ**: โค้ดจริงต้องอยู่ **ข้างใน `.app` bundle** (ที่ `Contents/Resources/`) ไม่ใช่ไฟล์ลอยข้างนอก
เหตุผลอยู่ในหัวข้อ 6 (macOS/packaging gotchas)

---

## 3. โค้ดเต็ม — `cover_subtitles.py` (แกนหลัก, ไม่มี dependency บน GUI)

ไฟล์นี้ **ไม่ผูกกับ Tkinter เลย** — เป็น pure Python + `xml.etree.ElementTree` + `pythainlp`
ถ้าจะย้ายไปทำ backend ภาษาอื่น (Node.js, Swift ฯลฯ) หัวข้อ 7 มีสรุปอัลกอริทึมแบบ pseudocode ที่ port ได้ง่ายกว่า
แต่ถ้าจะ **คงไว้เป็น Python module** ก็ก็อปไฟล์นี้ไปใช้ได้เลยทั้งดุ้น:

```python
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
cover_subtitles.py  — SUBTITLE Cover v1.3
อ่านซับไตเติ้ลธรรมดา (title ที่ไม่ใช่ตัวหนา — ไม่ว่าจะเป็น Pop-up Text หรือ Custom title
ของ FCP เอง) จากไฟล์ XML ที่ export จากโปรเจกต์ FCP
แล้วเพิ่ม "เลเยอร์ Cover" = ไฮไลต์ Pop-up 2 บรรทัด (บนขาว/ล่างส้ม) ตรงเวลาซับเป๊ะ
ขนาด auto-fit พอดีขอบจอ + แอนิเมชันป๊อบอัพ (Build In/Out)

*** ซับเดิมไม่ถูกแตะต้อง *** — cover เป็น connected clip lane บน anchor เข้ากับ clip แม่
นำเข้าแล้ว (เลือก Keep Both) จะได้โปรเจกต์สำเนาที่มี cover ทับซับ — ไล่ลบเองได้ ต้นฉบับอยู่ครบ

ใช้:  python3 cover_subtitles.py "/path/exported.fcpxml"   (รับ .fcpxml หรือ .fcpxmld)
ผล:  output_cover.fcpxml
"""
import os, sys
import xml.etree.ElementTree as ET

try:
    from pythainlp import word_tokenize as _th_tok
    HAS_THAI = True
except Exception:
    HAS_THAI = False

C_WHITE   = "0.999995 1 1 1"
C_ORANGE  = "0.972616 0.300689 0.0428142 1"
GLOBAL_POS = "0.497087 0.378268"
# ตำแหน่ง X เกือบกลาง (alignment=center), Y คำนวณแบบไดนามิกตามขนาดฟอนต์
X_WHITE, X_ORANGE = "6.5699", "6.8484"
# ยึดขอบล่างของบรรทัดส้มให้อยู่ "เหนือซับไตเติ้ล" คงที่เสมอ (ไม่ลอยเข้าใกล้กลางจอตอนตัวใหญ่)
# บรรทัดขาวค่อยต่อขึ้นไปด้านบนจากบรรทัดส้ม — ยิ่งตัวใหญ่ยิ่งขยายขึ้นบนอย่างเดียว ไม่ดันลงมาทับซับ
BOTTOM_EDGE = 55          # ขอบล่างของบรรทัดส้ม (เหนือซับไตเติ้ลพอดี ไม่ต้องลากลงเอง)
SINGLE_RAISE = 60         # ป๊อบอัพบรรทัดเดียว ยกขึ้นให้อยู่กลางโซนไฮไลต์ (เหนือซับ)
# ★ ตัวแปรเดียวคุมแนวตั้งทั้งหมด = "ครึ่งความสูงบรรทัด ต่อ fontSize 1pt"
# ระยะ center-to-center ที่ "แค่แตะกัน" = LINE_HALF×(ขาว+ส้ม) -> +GAP_PAD คงที่ = เกือบชิดติด
# ทุก shot เว้นระยะเท่ากันเสมอ (แพดคงที่) ไม่ห่างตามขนาด | ทับ=เพิ่ม LINE_HALF, ห่าง=ลด
LINE_HALF = 0.58          # คาลิเบรตจากงานจริง (73/71pt ห่าง 103 -> ~0.57-0.58)
GAP_PAD = 6               # แพดคงที่เล็กๆ "เกือบชิด" ไม่ทับ (เพิ่ม=ห่างขึ้นทุก shot เท่ากัน)
# ความกว้าง: char × fontSize ≤ MAX_UNITS -> ขยายเกือบชิดขอบซ้าย-ขวา แต่ไม่ล้น
FILL_WIDTH = 1150         # เป้าความกว้าง (ใหญ่ขึ้น เกือบชิดขอบ)
MAX_UNITS = 1170          # เพดานกันล้นเฟรม (char×size) — ด่านตรวจใช้ค่านี้
SIZE_MAX = 120            # ใหญ่สุด (บรรทัดสั้น)
HARD_MIN = 32             # เล็กสุดที่ยอมได้ เฉพาะบรรทัดยาวมากเพื่อกันล้น
BALANCE_RATIO = 1.9       # ขนาด 2 บรรทัดต่างกันได้ไม่เกินเท่านี้ (ดูใหญ่พอๆ กัน)
LANE_WHITE, LANE_ORANGE = 10, 11
# clip ชนิดที่รองรับ connected clip (แปะ cover ได้)
ANCHORABLE = {'clip', 'asset-clip', 'ref-clip', 'mc-clip', 'sync-clip', 'gap', 'video', 'audio', 'title'}
FILTERS = ('filter-video', 'filter-audio', 'marker', 'chapter-marker',
           'rating', 'keyword', 'analysis-marker', 'metadata')


def T(s):
    if not s:
        return 0.0
    s = s.strip().rstrip('s')
    if '/' in s:
        a, b = s.split('/'); return float(a) / float(b)
    return float(s)


def sub_text(title):
    """ซับธรรมดา = title ที่ไม่ใช่ตัวหนา (bold) ไม่ว่าจะสร้างด้วยเทมเพลตไหนก็ตาม
    (Pop-up Text ฟอนต์ Light, หรือ Custom title ของ FCP เอง) — ไฮไลต์/ป้ายราคา/CTA
    ในเวิร์กโฟลว์นี้เป็น Bold เสมอ จึงใช้ bold เป็นตัวแยกแทนการผูกกับ fontFace/เทมเพลต"""
    ts = title.find('.//text-style-def/text-style')
    if ts is None or ts.get('bold') == '1':
        return None
    name = title.get('name', '')
    if name.endswith(' - COVER'):
        return None   # กันดึงคัฟเวอร์ที่โปรแกรมนี้เคยสร้างเองซ้ำ (เผื่อรันซ้อนไฟล์เดิม)
    txt = ''.join(t.text or '' for t in title.findall('.//text/text-style')).strip()
    if not txt or txt.startswith('**') or 'ผลลัพธ์อาจเปลี่ยนแปลง' in txt:
        return None
    return txt


# คำเด่น (impact/benefit) สำหรับรีวิวสุขภาพ — ดันให้ไปนำบรรทัดส้ม (บรรทัดล่าง) ให้สะดุดตา
KEYWORDS = ('หายขาด', 'หาย', 'ดีขึ้น', 'ไม่ปวด', 'ไม่มี', 'สดชื่น', 'แข็งแรง', 'มะเร็ง',
            'เบาหวาน', 'ริดสีดวง', 'นอนหลับ', 'คล่อง', 'เยี่ยม', 'คุ้ม', 'ปลอดภัย',
            'สำคัญ', 'ต้องการ', 'จำเป็น', 'ที่สุด', 'มากๆ', 'ดีมาก', 'หมดไป')
KW_BONUS = 6   # ยอมให้ไม่บาลานซ์ได้ถึง 6 ตัวอักษร ถ้าแลกกับการดันคำเด่นไปบรรทัดส้ม

# คำกริยาบอกทิศทาง/คำเชื่อมสั้นๆ ที่ "ห้ามอยู่ท้ายบรรทัด" เพราะมันเกาะกับคำถัดไปเป็นวลีเดียว
# เช่น "เข้า"+"บ้าน" = "เข้าบ้าน" — ถ้าตัดขาดจากกันจะอ่านสะดุด เสียอรรถรส
NO_TRAIL_WORDS = {'เข้า', 'ออก', 'ไป', 'มา', 'ขึ้น', 'ลง', 'กลับ', 'ผ่าน', 'ถึง', 'ไว้', 'อยู่',
                  'ได้', 'ต้อง', 'จะ', 'ก็', 'แต่', 'ให้', 'เป็น', 'มี', 'ไม่', 'คือ', 'ว่า',
                  'ที่', 'ซึ่ง', 'และ', 'หรือ', 'จาก', 'ตาม', 'กับ', 'ของ', 'ใน', 'บน', 'ใต้',
                  'ก่อน', 'จน', 'เพื่อ', 'โดย', 'อย่าง', 'พอ', 'ทั้ง', 'ยัง', 'ค่อย', 'เพิ่ง'}
TRAIL_PENALTY = 30   # ปรับคะแนนแรงพอให้เลี่ยงจุดตัดนี้เสมอ (มากกว่า KW_BONUS)

# คำ/อนุภาคท้ายที่ "ห้ามขึ้นต้นบรรทัดล่าง" เพราะมันเกาะท้ายคำก่อนหน้า (กิน+ปุ๊บ, ...ครับ)
NO_LEAD_WORDS = {'ปุ๊บ', 'ปั๊บ', 'ครับ', 'ค่ะ', 'คะ', 'นะ', 'จ้ะ', 'จ้า', 'ล่ะ', 'สิ', 'ฮะ',
                 'เนอะ', 'เลย', 'ด้วย', 'อยู่', 'แล้ว', 'ไป', 'มา', 'ๆ'}
LEAD_PENALTY = 30

# ตัดตรงเว้นวรรค = จุดพักธรรมชาติที่คนพิมพ์ตั้งใจเว้น -> ให้แต้มต่อ (แบ่งตรงนี้ลื่นกว่า)
SPACE_BONUS = 8

# ประโยคสั้น (<= นี้) -> ป๊อบอัพบรรทัดเดียว (ส้ม) ไม่ฝืนแบ่ง 2 บรรทัดให้ดูแปลก
SHORT_MAX_CHARS = 10


def _is_key(orange):
    o = orange.strip()
    return bool(o) and (o[0].isdigit() or any(o.startswith(k) for k in KEYWORDS))


def _token_ends(text, engine):
    """คืน set ของตำแหน่ง(char) ที่เป็น 'ขอบคำ' ตาม engine นั้น"""
    ends, pos = set(), 0
    for t in _th_tok(text, engine=engine, keep_whitespace=True):
        pos += len(t)
        ends.add(pos)
    return ends


def _last_word_before(text, cut):
    """คำสุดท้ายก่อนจุดตัด (ใช้เช็ค NO_TRAIL_WORDS)"""
    pos = 0
    for t in _th_tok(text, engine='newmm', keep_whitespace=True):
        nxt = pos + len(t)
        if nxt == cut:
            return t.strip()
        pos = nxt
    return ''


def split_two(text):
    text = ' '.join(text.split())
    # ประโยคสั้น -> บรรทัดเดียว (ส้ม) ไม่ฝืนแบ่ง 2 บรรทัด
    if not HAS_THAI or len(text) <= SHORT_MAX_CHARS:
        return '', text

    # จุดตัดที่ปลอดภัย = ตำแหน่งที่ทั้ง newmm และ longest เห็นตรงกันว่าเป็นขอบคำ
    # (เลี่ยงจุดที่ engine ไหนแยกคำมั่ว เช่น บอ|กว่า หรือ หมอบ|อก) + เพิ่มตำแหน่งเว้นวรรคเสมอ
    agree = _token_ends(text, 'newmm') & _token_ends(text, 'longest')
    agree |= {i + 1 for i, ch in enumerate(text) if ch == ' '}   # หลังช่องว่าง = ขอบแน่นอน
    cuts = sorted(c for c in agree if 0 < c < len(text))
    if not cuts:
        cuts = sorted(c for c in _token_ends(text, 'newmm') if 0 < c < len(text))
    if not cuts:
        return '', text

    best = None
    for c in cuts:
        a, b = text[:c].strip(), text[c:].strip()
        if not a or not b:
            continue
        score = abs(len(a) - len(b))
        if _is_key(b):
            score -= KW_BONUS
        if text[c - 1] == ' ' or (c < len(text) and text[c] == ' '):
            score -= SPACE_BONUS                       # ตัดตรงเว้นวรรค = ลื่น
        if _last_word_before(text, c) in NO_TRAIL_WORDS:
            score += TRAIL_PENALTY
        if any(b.startswith(x) for x in NO_LEAD_WORDS):
            score += LEAD_PENALTY                      # อนุภาคท้ายห้ามขึ้นต้นบรรทัดล่าง
        if best is None or score < best[0]:
            best = (score, a, b)
    if best is None:
        return '', text
    return best[1], best[2]


def fit(line):
    """ขนาดฟอนต์ให้เต็มเฟรมแต่ไม่ล้น: เริ่มจาก FILL_WIDTH/ความยาว แล้วบีบไม่ให้ char×size เกิน MAX_UNITS
    บรรทัดสั้น -> ใหญ่ (cap SIZE_MAX) | บรรทัดยาวมาก -> ยอมเล็กถึง HARD_MIN เพื่อกันล้น (ห้ามล้นเด็ดขาด)"""
    n = max(len(line), 1)
    s = min(SIZE_MAX, int(FILL_WIDTH / n))
    while s > HARD_MIN and n * s > MAX_UNITS:      # ด่านกันล้น
        s -= 1
    return max(HARD_MIN, s)


def balance(sw, so):
    """ลดฟอนต์บรรทัดที่ใหญ่กว่าลง ถ้าต่างกันเกิน BALANCE_RATIO — ให้ดูใหญ่พอๆ กัน"""
    hi, lo = max(sw, so), min(sw, so)
    if lo and hi / lo > BALANCE_RATIO:
        capped = max(HARD_MIN, int(lo * BALANCE_RATIO))
        if sw > so:
            sw = capped
        else:
            so = capped
    return sw, so


def make_line(text, is_white, ref, offset_str, dur_str, tsid, lane, size, pos):
    """สร้าง Pop-up Text 1 เลเยอร์ (1 บรรทัด สีเดียว) เปิดเข้า-ปิดออก"""
    color = C_WHITE if is_white else C_ORANGE
    t = ET.Element('title', {'ref': ref, 'lane': str(lane), 'offset': offset_str,
                             'name': (text + ' - COVER')[:40], 'start': '3600s', 'duration': dur_str})
    kr = "9999/3296420352/3296420351/3001891230/3296421440"
    def P(nm, k, v): ET.SubElement(t, 'param', {'name': nm, 'key': k, 'value': v})
    P("Build In", "9999/3001891228/2/101", "1")      # เปิดเข้า
    P("Build Out", "9999/3001891228/2/102", "1")     # ปิดออก
    P("Position", kr + "/1/100/101", pos)
    P("Size", kr + "/5/3336715400/3", str(size))
    P("Speed", "9999/3296420352/3296420351/4/3296420944/201", "14")
    P("Speed", "9999/3296420352/3296420351/4/3296420952/200", "15")
    P("Global Scale", "9999/3296421148/3/3296421147/1", "0.05")
    P("Global Angle", "9999/3296421148/3/3296421147/2", "90")
    P("Global Position", "9999/3296421148/3/3296421147/3", GLOBAL_POS)
    txt = ET.SubElement(t, 'text')
    ET.SubElement(txt, 'text-style', {'ref': tsid}).text = text
    d = ET.SubElement(t, 'text-style-def', {'id': tsid})
    attrs = {'font': 'Anakotmai', 'fontSize': str(size), 'fontColor': color, 'bold': '1',
             'shadowColor': '0 0 0 1', 'shadowOffset': '1 315', 'shadowBlurRadius': '9.12',
             'alignment': 'center', 'lineSpacing': '-30'}
    if not is_white:
        attrs['strokeColor'] = '1 1 1 1'; attrs['strokeWidth'] = '-5'
    ET.SubElement(d, 'text-style', attrs)
    return t


def rat(sec, tb):
    return f"{int(round(sec * tb))}/{tb}s"


def _safe_name(s):
    s = ''.join(c for c in (s or '') if c not in '/\\:*?"<>|').strip()
    return s or 'project'


def build(path, overrides=None):
    """อ่าน XML -> สร้าง cover ในทรี. คืน (root, ชื่อโปรเจกต์, pairs)
    pairs = [(idx, white, sw, orange, so), ...] สำหรับพรีวิว | โยน ValueError ถ้ามีปัญหา
    overrides = {idx: (white_text, orange_text)} — ใช้ข้อความที่ผู้ใช้แก้ไขแทนการตัดอัตโนมัติ
    (idx = ลำดับใน subs ก่อนกรอง anchor, ใช้จับคู่กับ pairs ตอน analyze() เพื่อแก้ไขแล้วสร้างใหม่)
    ถ้า override ทั้งขาว+ส้มว่างเปล่า = ผู้ใช้ลบทิ้ง -> ข้ามช่วงนั้นไปเลย ไม่สร้าง cover"""
    if os.path.isdir(path) and path.endswith('.fcpxmld'):
        path = os.path.join(path, 'Info.fcpxml')
    if not os.path.exists(path):
        raise ValueError(f"ไม่พบไฟล์: {path}")

    root = ET.parse(path).getroot()
    popup = next((e for e in root.iter('effect') if e.get('name') == 'Pop-up Text'), None)
    if popup is None:
        raise ValueError("ไม่พบ effect 'Pop-up Text' ในไฟล์ (ซับต้องเป็น Pop-up Text)")
    ref = popup.get('id')
    fmt = root.find('.//format')
    tb = int(fmt.get('frameDuration', '100/2500s').rstrip('s').split('/')[1])
    proj = root.find('.//project')
    proj_name = _safe_name(proj.get('name') if proj is not None else None)

    parent = {c: p for p in root.iter() for c in p}
    subs = [t for t in root.iter('title') if sub_text(t)]
    overrides = overrides or {}
    pairs = []
    for idx, sub in enumerate(subs):
        off = T(sub.get('offset'))
        node = sub; p = parent.get(node)
        while p is not None and p.tag == 'spine':
            off += T(p.get('offset')); node = p; p = parent.get(node)
        if p is None or p.tag not in ANCHORABLE:
            continue
        ov = overrides.get(idx)
        if ov is not None:
            white, orange = (ov[0] or '').strip(), (ov[1] or '').strip()
            if not white and not orange:
                continue    # ผู้ใช้ลบข้อความทั้งคู่ -> ไม่สร้าง cover ให้ช่วงนี้
        else:
            white, orange = split_two(sub_text(sub))
        offset_str = rat(off, tb)
        dur = sub.get('duration', '30000/150000s')
        n = len(pairs)
        at_of = lambda: next((i for i, ch in enumerate(p) if ch.tag in FILTERS), len(list(p)))
        if not white:
            # ประโยคสั้น (หรือผู้ใช้ลบบรรทัดขาว) -> ป๊อบอัพบรรทัดเดียว (ส้ม) ไม่ฝืนแบ่ง 2 บรรทัด
            so = fit(orange)
            opos = f"{X_ORANGE} {BOTTOM_EDGE + LINE_HALF * so + SINGLE_RAISE:.1f}"
            o = make_line(orange, False, ref, offset_str, dur, f'co{n}', LANE_ORANGE, so, opos)
            p.insert(at_of(), o)
            pairs.append((idx, '', 0, orange, so))
            continue
        sw, so = balance(fit(white), fit(orange))
        # ระยะห่าง = ครึ่งความสูงส้ม + ครึ่งความสูงขาว (แค่แตะกัน) + แพดคงที่ -> เกือบชิด สม่ำเสมอทุก shot
        gap = LINE_HALF * (sw + so) + GAP_PAD
        opos_y = BOTTOM_EDGE + LINE_HALF * so        # ขอบล่างส้มยึด BOTTOM_EDGE เสมอ
        wpos_y = opos_y + gap
        wpos = f"{X_WHITE} {wpos_y:.1f}"
        opos = f"{X_ORANGE} {opos_y:.1f}"
        w = make_line(white, True, ref, offset_str, dur, f'cw{n}', LANE_WHITE, sw, wpos)
        o = make_line(orange, False, ref, offset_str, dur, f'co{n}', LANE_ORANGE, so, opos)
        at = at_of()
        p.insert(at, o); p.insert(at, w)
        pairs.append((idx, white, sw, orange, so))
    if not pairs:
        raise ValueError("ไม่พบซับ (Pop-up Text ฟอนต์ Light) ในไฟล์นี้")
    return root, proj_name, pairs


def validate(pairs):
    """ด่านตรวจสอบก่อนออกไฟล์ — คืน list ปัญหา (ว่าง = ผ่าน 100%)
    เช็ค: ไม่ล้นเฟรม (char×size ≤ MAX_UNITS), ขนาดในเกณฑ์, 2 บรรทัดไม่ทับกัน"""
    problems = []
    for i, (idx, w, sw, o, so) in enumerate(pairs, 1):
        if not o:
            problems.append(f"#{i} บรรทัดล่างว่าง"); continue
        if len(o) * so > MAX_UNITS:
            problems.append(f"#{i} ส้ม '{o}' ล้นเฟรม ({len(o)}×{so}={len(o)*so}>{MAX_UNITS})")
        if not (HARD_MIN <= so <= SIZE_MAX):
            problems.append(f"#{i} ขนาดส้ม {so} นอกเกณฑ์ [{HARD_MIN},{SIZE_MAX}]")
        if w:   # คู่ 2 บรรทัด
            if len(w) * sw > MAX_UNITS:
                problems.append(f"#{i} ขาว '{w}' ล้นเฟรม ({len(w)}×{sw}={len(w)*sw}>{MAX_UNITS})")
            if not (HARD_MIN <= sw <= SIZE_MAX):
                problems.append(f"#{i} ขนาดขาว {sw} นอกเกณฑ์ [{HARD_MIN},{SIZE_MAX}]")
            gap = LINE_HALF * (sw + so) + GAP_PAD
            if gap < LINE_HALF * (sw + so):          # ต้องมีแพด >= 0 เสมอ (ไม่ทับ)
                problems.append(f"#{i} 2 บรรทัดชิดเกิน เสี่ยงทับ (gap {gap:.0f})")
    return problems


def analyze(path):
    """พรีวิว: คืน (ชื่อโปรเจกต์, pairs) โดยไม่เขียนไฟล์"""
    _, name, pairs = build(path)
    return name, pairs


def suggest_name(path):
    try:
        name, _ = analyze(path)
        return f"{name}_cover.fcpxml"
    except Exception:
        return "output_cover.fcpxml"


def run(path, overrides=None, out_path=None):
    """สร้าง cover แล้วเขียนไฟล์. out_path=None -> {ชื่อโปรเจกต์}_cover.fcpxml ในโฟลเดอร์แอป
    overrides = {idx: (white_text, orange_text)} จากที่ผู้ใช้แก้ไขในพรีวิว (ดู build())
    คืน (จำนวน cover, จำนวนซับ, path ผลลัพธ์)"""
    root, name, pairs = build(path, overrides=overrides)
    # ★ ด่านตรวจสอบก่อนออกไฟล์ — ถ้าไม่ผ่าน ไม่เขียนไฟล์ (กันงานพลาดหลุดออกไป)
    problems = validate(pairs)
    if problems:
        raise ValueError("ตรวจพบข้อผิดพลาด ไม่สร้างไฟล์:\n- " + "\n- ".join(problems[:10]))
    if out_path is None:
        out_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), f"{name}_cover.fcpxml")
    with open(out_path, 'w', encoding='utf-8') as f:
        f.write('<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE fcpxml>\n')
        f.write(ET.tostring(root, encoding='unicode'))
    return len(pairs), len(pairs), out_path


def main():
    if len(sys.argv) < 2:
        print("ใส่ path ไฟล์ XML ที่ export มา"); sys.exit(1)
    try:
        covers, nsubs, out = run(sys.argv[1])
    except ValueError as e:
        print(f"❌ {e}"); sys.exit(1)
    print(f"✅ สร้าง Cover {covers} อัน -> {out}")
    print("   นำเข้า FCP: File > Import > XML  (เลือก Keep Both) — ต้นฉบับไม่ถูกแตะ")


if __name__ == '__main__':
    main()
```

---

## 4. โค้ดเต็ม — `cover_gui.py` (หน้าตาโปรแกรม, Tkinter)

```python
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
cover_gui.py — SUBTITLE Cover (แอป GUI)
เลือก/ลากไฟล์โปรเจกต์ -> พรีวิวคู่ขาว/ส้ม (แก้ไข/ลบได้ในช่องพิมพ์) -> กดบันทึกสร้างใหม่ตามที่แก้
ไม่ต้องใช้เทอร์มินอล
"""
import os
import sys
import threading
import subprocess
import tkinter as tk
from tkinter import filedialog, messagebox

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import cover_subtitles as core

BG = "#1e1e24"; CARD = "#2a2a33"; ORANGE = "#f88b1a"
WHITE = "#f5f5f7"; GREY = "#9a9aa5"; GREEN = "#4caf72"
ROW_BORDER = "#3a3a44"
ENTRY_FONT = ("Helvetica", 13)


class App:
    def __init__(self, root):
        self.root = root
        self.path = None
        self.proj_name = None
        self.rows = []          # [{'idx':int,'white':tk.StringVar,'orange':tk.StringVar}]
        root.title("SUBTITLE Cover")
        root.configure(bg=BG)
        root.geometry("680x660")
        root.minsize(560, 480)

        tk.Label(root, text="SUBTITLE  Cover", bg=BG, fg=WHITE,
                 font=("Helvetica", 24, "bold")).pack(pady=(20, 0))
        tk.Label(root, text="ดึงซับเดิม → ไฮไลต์ Pop-up 2 บรรทัด ขาว/ส้ม (ซับเดิมไม่แตะ)",
                 bg=BG, fg=GREY, font=("Helvetica", 11)).pack(pady=(0, 12))

        # เลือก/ลากไฟล์
        self.drop = tk.Frame(root, bg=CARD, height=70, highlightbackground=ORANGE, highlightthickness=2)
        self.drop.pack(fill="x", padx=26); self.drop.pack_propagate(False)
        self.drop_lbl = tk.Label(self.drop, text="📁  คลิกเลือกไฟล์ที่ Export XML จาก FCP (.fcpxmld)\nใน FCP: เลือกโปรเจกต์ → File → Export XML…",
                                 bg=CARD, fg=GREY, font=("Helvetica", 12), cursor="hand2")
        self.drop_lbl.pack(expand=True)
        for w in (self.drop, self.drop_lbl):
            w.bind("<Button-1>", lambda e: self.choose())
        try:
            root.tk.call('package', 'require', 'tkdnd')
            self.drop.drop_target_register('DND_Files')
            self.drop.dnd_bind('<<Drop>>', lambda e: self.set_path(e.data.strip().strip('{}')))
        except Exception:
            pass

        # พรีวิว (แก้ไขได้)
        head = tk.Frame(root, bg=BG); head.pack(fill="x", padx=28, pady=(14, 2))
        tk.Label(head, text="พรีวิว — แก้คำผิด/ลบได้ในช่องพิมพ์ (ลบข้อความทั้งคู่ = ไม่เอาป๊อบอัพช่วงนี้)",
                 bg=BG, fg=GREY, font=("Helvetica", 11)).pack(side="left")

        outer = tk.Frame(root, bg=CARD, highlightbackground=ROW_BORDER, highlightthickness=1)
        outer.pack(fill="both", expand=True, padx=26)
        self.canvas = tk.Canvas(outer, bg=CARD, highlightthickness=0)
        vsb = tk.Scrollbar(outer, orient="vertical", command=self.canvas.yview)
        self.canvas.configure(yscrollcommand=vsb.set)
        vsb.pack(side="right", fill="y")
        self.canvas.pack(side="left", fill="both", expand=True)
        self.inner = tk.Frame(self.canvas, bg=CARD)
        self._win = self.canvas.create_window((0, 0), window=self.inner, anchor="nw")
        self.inner.bind("<Configure>", lambda e: self.canvas.configure(scrollregion=self.canvas.bbox("all")))
        self.canvas.bind("<Configure>", lambda e: self.canvas.itemconfig(self._win, width=e.width))
        self.canvas.bind("<MouseWheel>", self._on_wheel)

        self.empty_lbl = tk.Label(self.inner, text="", bg=CARD, fg=GREY, font=("Helvetica", 12))

        # ปุ่ม + สถานะ
        self.btn = tk.Button(root, text="บันทึก & สร้าง Cover", command=self.go, state="disabled",
                             bg=ORANGE, fg="white", activebackground="#ffa02e",
                             font=("Helvetica", 15, "bold"), relief="flat", cursor="hand2",
                             disabledforeground="#7a6a55")
        self.btn.pack(pady=(14, 4), ipadx=26, ipady=6)
        self.status = tk.Label(root, text="", bg=BG, fg=GREY, font=("Helvetica", 11),
                               wraplength=620, justify="center")
        self.status.pack(pady=(0, 12))

    def _on_wheel(self, event):
        self.canvas.yview_scroll(int(-1 * (event.delta)), "units")

    # ---------- ไฟล์ ----------
    def choose(self):
        # ไม่ใส่ filter — .fcpxmld เป็น "แพ็กเกจ" ของ macOS ถ้าใส่ filter จะกลายเป็นสีจางเลือกไม่ได้
        p = filedialog.askopenfilename(title="เลือกไฟล์ที่ Export XML จาก FCP (.fcpxml / .fcpxmld)")
        if p:
            self.set_path(p)

    def set_path(self, p):
        p = p.rstrip('/')
        low = p.lower()
        # เผื่อเลือกไฟล์ Info.fcpxml ข้างใน bundle มา ก็ใช้ได้เลย
        if not (low.endswith('.fcpxml') or low.endswith('.fcpxmld')):
            self.drop_lbl.config(text="⚠️  ไฟล์นี้ไม่ใช่ .fcpxml/.fcpxmld — เลือกไฟล์ที่ Export XML จาก FCP",
                                 fg="#ffb84d")
            self.status.config(text="ใน FCP: เลือกโปรเจกต์ → File → Export XML… แล้วนำไฟล์นั้นมาเลือกที่นี่",
                               fg=GREY)
            return
        self.path = p
        self.drop_lbl.config(text=f"✅  {os.path.basename(p)}", fg=WHITE)
        self.status.config(text="กำลังอ่านซับ...", fg=GREY)
        self.btn.config(state="disabled")
        threading.Thread(target=self._analyze, daemon=True).start()

    def _analyze(self):
        try:
            name, pairs = core.analyze(self.path)
        except Exception as e:
            self.root.after(0, self._show_err, str(e)); return
        self.root.after(0, self._show_preview, name, pairs)

    def _clear_rows(self):
        for ch in list(self.inner.winfo_children()):
            ch.destroy()
        self.rows = []

    def _make_row(self, i, idx, white_text, orange_text, size_hint):
        row = tk.Frame(self.inner, bg=CARD)
        row.pack(fill="x", padx=10, pady=4)
        row.columnconfigure(1, weight=1)
        row.columnconfigure(3, weight=1)

        tk.Label(row, text=f"{i:>3}.", bg=CARD, fg=GREY, font=("Helvetica", 11), width=4, anchor="e").grid(
            row=0, column=0, sticky="w", padx=(0, 6))

        wv = tk.StringVar(value=white_text)
        we = tk.Entry(row, textvariable=wv, bg=BG, fg=WHITE, insertbackground=WHITE,
                      relief="flat", highlightthickness=1, highlightbackground=ROW_BORDER,
                      highlightcolor=ORANGE, font=ENTRY_FONT)
        we.grid(row=0, column=1, sticky="ew", ipady=4)

        tk.Label(row, text="/", bg=CARD, fg=GREY, font=("Helvetica", 12)).grid(row=0, column=2, padx=6)

        ov = tk.StringVar(value=orange_text)
        oe = tk.Entry(row, textvariable=ov, bg=BG, fg=ORANGE, insertbackground=ORANGE,
                      relief="flat", highlightthickness=1, highlightbackground=ROW_BORDER,
                      highlightcolor=ORANGE, font=ENTRY_FONT)
        oe.grid(row=0, column=3, sticky="ew", ipady=4)

        clear_btn = tk.Button(row, text="✕", command=lambda: (wv.set(""), ov.set("")),
                              bg=CARD, fg=GREY, activeforeground="#ff6b6b", relief="flat",
                              font=("Helvetica", 11), bd=0, cursor="hand2", width=2)
        clear_btn.grid(row=0, column=4, padx=(6, 0))

        self.rows.append({'idx': idx, 'white': wv, 'orange': ov})

    def _show_preview(self, name, pairs):
        self.proj_name = name
        self._clear_rows()
        singles = 0
        for i, (idx, w, sw, o, so) in enumerate(pairs, 1):
            if not w:
                singles += 1
            self._make_row(i, idx, w, o, (sw, so))
        self.canvas.after_idle(lambda: self.canvas.configure(scrollregion=self.canvas.bbox("all")))
        self.canvas.yview_moveto(0)
        pair_n = len(pairs) - singles
        extra = f"  (บรรทัดเดียว {singles})" if singles else ""
        self.status.config(text=f"📄 {name}  —  {pair_n} คู่{extra}", fg=GREY)
        self.btn.config(state="normal", text="บันทึก & สร้าง Cover")

    def _show_err(self, msg):
        self._clear_rows()
        self.status.config(text=f"❌ {msg}", fg="#ff6b6b")
        self.btn.config(state="disabled")

    # ---------- สร้าง ----------
    def go(self):
        if not self.path or not self.rows:
            return
        default = f"{self.proj_name}_cover.fcpxml" if self.proj_name else "output_cover.fcpxml"
        out = filedialog.asksaveasfilename(
            title="เซฟไฟล์ Cover", defaultextension=".fcpxml",
            initialfile=default, initialdir=os.path.dirname(self.path.rstrip('/')),
            filetypes=[("FCPXML", "*.fcpxml")])
        if not out:
            return
        # เก็บค่าปัจจุบันจากช่องพิมพ์ทุกแถว (รวมที่แก้ไข/ลบ) ก่อนสลับไป thread เบื้องหลัง
        overrides = {r['idx']: (r['white'].get(), r['orange'].get()) for r in self.rows}
        self.btn.config(state="disabled", text="กำลังสร้าง...")
        self.status.config(text="กำลังประมวลผล...", fg=GREY)
        threading.Thread(target=self._work, args=(out, overrides), daemon=True).start()

    def _work(self, out, overrides):
        try:
            covers, _, path = core.run(self.path, overrides=overrides, out_path=out)
        except Exception as e:
            self.root.after(0, self._done, None, str(e)); return
        self.root.after(0, self._done, (covers, path), None)

    def _done(self, result, err):
        self.btn.config(state="normal", text="บันทึก & สร้าง Cover")
        if err:
            self.status.config(text=f"❌ {err}", fg="#ff6b6b")
            messagebox.showerror("ผิดพลาด", err); return
        covers, path = result
        self.status.config(text=f"✅ สร้าง {covers} คู่ → {os.path.basename(path)}", fg=GREEN)
        try:
            subprocess.run(["open", "-R", path])
        except Exception:
            pass
        messagebox.showinfo("สำเร็จ",
                            f"สร้าง Cover {covers} คู่\n\nไฟล์:\n{path}\n\n"
                            f"นำเข้า FCP: File → Import → XML → เลือกไฟล์นี้\nแล้วเลือก Keep Both")


def _force_redraw(root):
    """แก้บั๊ก Tk บน macOS: หน้าต่างวาดว่างเปล่าจนกว่าจะ resize/focus
    บังคับ redraw ด้วยการ nudge ขนาดหน้าต่าง 1px แล้วคืนค่า + ดึงมาหน้าสุด"""
    root.update_idletasks()
    w = root.winfo_width() or 680
    h = root.winfo_height() or 660
    root.geometry(f"{w + 1}x{h}")
    root.after(80, lambda: root.geometry(f"{w}x{h}"))
    root.lift()
    root.attributes('-topmost', True)
    root.after(400, lambda: root.attributes('-topmost', False))
    try:
        root.focus_force()
    except Exception:
        pass


if __name__ == "__main__":
    root = tk.Tk()
    root.withdraw()               # ซ่อนก่อน สร้าง widget ครบแล้วค่อยโชว์ (กันวาดค้าง)
    App(root)
    root.update_idletasks()
    root.deiconify()
    root.after(150, lambda: _force_redraw(root))
    root.mainloop()
```

---

## 5. macOS app bundle — launcher + Info.plist

**`Contents/MacOS/SUBTITLE Cover`** (ต้อง `chmod +x`):
```bash
#!/bin/bash
# launcher ของแอป SUBTITLE Cover — เปิด GUI จากสคริปต์ในตัว bundle (เลี่ยง TCC ของ Downloads)
# ใช้ Python 3.12 (python.org) เพราะ Tk เรนเดอร์ถูกต้องบน macOS ใหม่ (ตัว /usr/bin จอว่าง)
RES="$(cd "$(dirname "$0")/../Resources" && pwd)"
PY="/Library/Frameworks/Python.framework/Versions/3.12/bin/python3"
[ -x "$PY" ] || PY=/usr/bin/python3
exec "$PY" -B "$RES/cover_gui.py" >"/tmp/subtitle_cover.log" 2>&1
```

**`Contents/Info.plist`**:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>SUBTITLE Cover</string>
    <key>CFBundleDisplayName</key><string>SUBTITLE Cover</string>
    <key>CFBundleIdentifier</key><string>com.dong.subtitlecover</string>
    <key>CFBundleVersion</key><string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleExecutable</key><string>SUBTITLE Cover</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>10.13</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
```

**หลัง copy/แก้ไฟล์ .py ใดๆ ต้องรันคำสั่งนี้ใหม่เสมอ** (ไม่งั้น macOS จะปฏิเสธเปิดแอปหรือใช้โค้ดเก่าจากแคช):
```bash
codesign --force --deep --sign - "SUBTITLE Cover.app"
```

ถ้าดับเบิลคลิกแล้วไม่เปิด (ครั้งแรกหลัง build ใหม่) อาจต้อง register กับ LaunchServices ก่อนหนึ่งครั้ง:
```bash
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "SUBTITLE Cover.app"
```

---

## 6. บทเรียนที่ได้จากการลองผิดลองถูกจริง (สำคัญมาก — ห้ามข้าม)

รายการนี้คือสิ่งที่ **เอกสาร Apple ไม่ได้บอก** ทั้งหมดมาจากการทดสอบจริงกับ FCP + import ไฟล์จริงหลายสิบรอบ:

### 6.1 macOS / packaging
- **`/usr/bin/python3` (Command Line Tools) วาดหน้าต่าง Tkinter ว่างเปล่า** บน macOS เครื่องที่ทดสอบ (บั๊กเรนเดอร์ Tk) —
  ต้องใช้ **Python 3.12 จาก python.org** (`/Library/Frameworks/Python.framework/Versions/3.12/bin/python3`) แทน
- **โค้ด .py ต้องอยู่ข้างใน `.app` bundle** (`Contents/Resources/`) ไม่ใช่ไฟล์ลอยข้างนอกใน `~/Downloads/` —
  เพราะ **TCC (macOS privacy) บล็อกแอปที่เปิดผ่าน Finder ไม่ให้อ่านไฟล์ในโฟลเดอร์ Downloads ที่อยู่นอกตัวเอง** (error "Operation not permitted")
  แอปอ่านไฟล์ **ในตัวมันเอง** ได้เสมอ ไม่ติด TCC
- ต้อง **codesign แบบ ad-hoc** (`--sign -`) ทุกครั้งที่แก้โค้ด ไม่งั้น Gatekeeper จะเตือน/ปฏิเสธตอนดับเบิลคลิก
- ใช้ flag **`-B`** ตอนรัน python (`python3 -B cover_gui.py`) เพื่อกัน `__pycache__` ถูกเขียนกลับเข้าไปใน bundle
  (ซึ่งจะทำให้ codesign เสีย ต้องเซ็นใหม่ทุกครั้งที่รัน)
- Tkinter หน้าต่างมักวาดค้าง/ว่างตอนเปิดครั้งแรกจนกว่าจะ resize — แก้ด้วยการ **`root.withdraw()` ก่อน build widget เสร็จ
  แล้ว `deiconify()` + geometry nudge (`+1px` แล้วคืน) เพื่อบังคับ redraw** (ดูฟังก์ชัน `_force_redraw()`)
- `filedialog.askopenfilename(filetypes=...)` **ห้ามใส่ filter สำหรับ `.fcpxmld`** — มันเป็น **package** (โฟลเดอร์พิเศษ)
  ของ macOS ไม่ใช่ไฟล์ปกติ ถ้าใส่ filter จะกลายเป็นสีจางในไดอะล็อกเลือกไม่ได้ — **ไม่ใส่ filter แล้วมาตรวจนามสกุลเองใน callback แทน**

### 6.2 โครงสร้าง FCPXML (สำคัญที่สุด — ผูกกับตรรกะทั้งหมดของโปรแกรม)

- **`.fcpxmld` = โฟลเดอร์** ข้างในมีไฟล์ `Info.fcpxml` ที่เป็น XML จริง ต้องเปิดไฟล์นั้น ไม่ใช่โฟลเดอร์
- ซับไตเติ้ล/ไฮไลต์ทั้งหมดสร้างจากเทมเพลต **"Pop-up Text"** (Motion template ของผู้ใช้ ไม่ใช่ built-in ของ FCP)
  — ต้องหา `<effect name="Pop-up Text">` ในไฟล์ก่อน แล้วใช้ `id` ของมันเป็น `ref` ตอนสร้าง `<title>` ใหม่
- **แยกซับธรรมดา vs ไฮไลต์/ป้ายราคา/CTA ด้วย `bold` attribute** (`text-style/@bold == "1"`)
  ทั้งโปรเจกต์นี้: **ไฮไลต์/ป้ายราคา/CTA เป็น Bold เสมอ, ซับธรรมดาไม่ Bold** (ไม่ว่าจะสร้างด้วยเทมเพลต Pop-up Text
  หรือ Custom title ของ FCP เอง) — **เดิมทีเคยใช้ `fontFace=="Light"` เป็นตัวคัดกรอง แต่ผิดพลาดกับ Custom title
  ที่ไม่ตั้งค่า fontFace เลย จึงเปลี่ยนมาใช้ bold แทน** (ดูหัวข้อ 8 — จุดนี้ **ยังมีบั๊กค้างอยู่**)
- **connected clip (title ที่แปะซ้อนบนคลิป) ต้องอยู่ใต้ `<clip>`, `<asset-clip>`, `<gap>` ฯลฯ — ห้ามอยู่ใต้ `<spine>` โดยตรง**
  ถ้าแปะผิดที่ FCP จะ import แล้วเตือน "Anchored items were ignored because this item does not support them"
  วิธีแก้: เดินขึ้น (`parent` map) จาก title เดิมผ่าน `<spine>` ที่ซ้อนกัน จนเจอ parent ที่เป็น `ANCHORABLE`
  (`{'clip','asset-clip','ref-clip','mc-clip','sync-clip','gap','video','audio','title'}`) แล้วบวก offset สะสมของ spine
  ทุกชั้นที่เดินผ่าน เพื่อได้ offset จริงเทียบกับ parent นั้น
- **ลำดับ child element ผิด DTD ทำให้ import fail แบบไม่มีคำเตือน แค่ปฏิเสธทั้งไฟล์**:
  ต้องแทรก `<title>` ใหม่ **ก่อน** `filter-video`/`marker`/ฯลฯ ที่มีอยู่แล้วใน parent เดิมเสมอ (ดูตัวแปร `FILTERS`
  และ `at_of()` lambda ที่หาตำแหน่งแทรกที่ถูกต้อง)
- **ไฮไลต์ต้องเป็น 2 `<title>` แยกกันคนละอัน** (ขาว 1 อัน + ส้ม 1 อัน คนละ `lane`) **ไม่ใช่ title เดียวมี 2 สี** —
  ลองทำเป็น title เดียว 2 `text-style` มาก่อนแล้วมันเรนเดอร์เป็นข้อความต่อกันแนวนอนบรรทัดเดียว ไม่ตัดบรรทัดให้อัตโนมัติ
- ถ้าจะทำ 2 บรรทัดใน **title เดียว** (ไม่แนะนำ แต่เผื่อต้องใช้): newline ต้องอยู่ **ในเนื้อหาของ `<text-style>` แรก**
  (`text = "บรรทัดบน\n"`) ไม่ใช่ whitespace ใน `.tail` ของ element — FCP ไม่ตัดบรรทัดจาก tail whitespace
- **`Position` param ของเทมเพลต Pop-up Text ใช้หน่วยที่ไม่ตรงกับ pixel ธรรมดา** — ค่าที่ดึงจากตัวอย่างงานจริงของผู้ใช้
  (สังเกตจาก export XML จริงที่มี title วางมือ): `POS_WHITE≈"6.57 206"`, `POS_ORANGE≈"6.85 103"`, subtitle เดิม `≈"5.8 -7.66"`
  ที่ font size 71-73pt ระยะห่างจริงระหว่างขาว-ส้ม ≈ 103 หน่วย → คำนวณย้อนได้ **`LINE_HALF ≈ 0.58`** (ต่อ fontSize 1pt)
  นี่คือค่าคาลิเบรตเดียวที่มี **ยัง verify กับหลายขนาดในไฟล์จริงแล้วว่าถูกต้อง** (ดูหัวข้อ 8.4)
- ตำแหน่ง X คงที่ `POS_WHITE_X="6.5699"`, `POS_ORANGE_X="6.8484"` (เกือบ 0 เพราะ `alignment=center` ใน text-style
  จัดกึ่งกลางแนวนอนให้เองอยู่แล้ว)
- **`Global Position`, `Global Scale`, `Global Angle`** เป็นพารามิเตอร์ของ **เอฟเฟกต์ Pop-up Text เอง** (คนละตัวกับ
  `Position` ที่เป็นตำแหน่งข้อความ) — ค่าที่ใช้ก็อปมาจากงานจริงตรงๆ (`GLOBAL_POS = "0.497087 0.378268"`, Angle "90",
  Scale "0.05") **อย่าไปแก้ 3 ตัวนี้โดยไม่รู้ที่มา** เพราะเป็นค่าที่ผูกกับแอนิเมชันเด้งเข้า-ออกภายในเทมเพลต
- **`Build In` / `Build Out`** param (`key="9999/3001891228/2/101"` / `/102"`) คือตัวเปิด/ปิดแอนิเมชันป๊อบอัพ
  ต้องตั้งเป็น `"1"` ทั้งคู่เพื่อให้เด้งเข้า**และ**ออก (ถ้า Build Out=0 ตัวอักษรจะค้างอยู่ท้ายคลิปไม่หายไป)
- **`Speed`** 2 param แยกกัน คนละ key (`.../4/3296420944/201` กับ `.../4/3296420952/200`) — ค่า "14" กับ "15" —
  ก็อปมาจากงานจริง คือความเร็ว build-in กับ build-out ตามลำดับ
- ทุก `<title>` ต้องมี `<filter-video ref="...">Drop Shadow</filter-video>` ประกอบด้วย (ในเวอร์ชันแรกๆ เคยใส่
  แต่เวอร์ชันปัจจุบัน **ไม่ได้ใส่แล้ว** เพราะ shadow มาจาก `shadowColor`/`shadowOffset`/`shadowBlurRadius` ใน
  `text-style` โดยตรงแทน ซึ่งง่ายกว่าและไม่ผูก DTD)

### 6.3 การตัดคำภาษาไทย (`pythainlp`)
- **ตัวตัดคำ engine เดียวไม่พอ** — `newmm` (default) กับ `longest` **ตัดคำผิดกันคนละจุด**:
  - `newmm` ตัด "บอกว่า" ผิดเป็น "บอ"+"กว่า" (ทั้งคู่เป็นคำในดิกชันนารีจริง ตรวจ dict ไม่ช่วย)
  - `longest` ตัด "หมอบอกหาย" ผิดเป็น "หมอบ"+"อก", "สารธรรมชาติ" ผิดเป็น "สารธรรม"+"ชาติ"
  - **วิธีแก้ที่ได้ผล**: ใช้เฉพาะจุดตัดที่ **ทั้งสอง engine เห็นตรงกัน** (set intersection ของตำแหน่งขอบคำ)
    เป็นจุดตัดที่ "ปลอดภัย" เท่านั้น — โค้ดในฟังก์ชัน `split_two()`
- ต้องเพิ่ม **ตำแหน่งหลังช่องว่างเสมอเป็นจุดตัดที่ปลอดภัยเพิ่มเติม** (นอกเหนือจาก 2 engine เห็นตรงกัน)
  เพราะเว้นวรรคคือจุดพักที่คนพิมพ์ตั้งใจ ตัดตรงนั้นแล้วลื่นเสมอ
- **คำกริยาทิศทาง/คำเชื่อมสั้น** (เข้า ออก ไป มา ขึ้น ลง ก็ แต่ ให้ ฯลฯ) **ห้ามอยู่ท้ายบรรทัด** เพราะเกาะกับคำถัดไป
  เป็นวลีเดียว (เช่น "เข้า"+"บ้าน"="เข้าบ้าน") — มี list `NO_TRAIL_WORDS` + penalty คะแนน
- **อนุภาคท้ายประโยค** (ปุ๊บ ปั๊บ ครับ ค่ะ นะ ฯลฯ) **ห้ามขึ้นต้นบรรทัดล่าง** เพราะเกาะท้ายคำก่อนหน้า
  (เช่น "กิน"+"ปุ๊บ"="กินปุ๊บ") — มี list `NO_LEAD_WORDS` + penalty คะแนน
- ประโยคสั้น (≤10 ตัวอักษร) **ไม่ควรฝืนแบ่ง 2 บรรทัด** — ทำเป็นบรรทัดเดียว (สีส้ม) ดูเป็นธรรมชาติกว่า
  (เช่น "ชื่อน้อง ?" ไม่ควรแบ่งเป็น "ชื่อ"/"น้อง ?")

### 6.4 การจัดวางขนาด/ตำแหน่ง (Design system)
- **ขนาดฟอนต์ต้อง "เต็มเฟรมแต่ไม่ล้น"**: คำนวณจาก `FILL_WIDTH / จำนวนตัวอักษร` แล้ว **ต้องมีด่านกันล้น**
  (`while size*chars > MAX_UNITS: size -= 1`) เพราะถ้าปล่อยตามสูตรตรงๆ ประโยคสั้นมากจะได้ฟอนต์ใหญ่จนล้นขอบจอ
- **ขนาด 2 บรรทัด (ขาว/ส้ม) ต้อง "บาลานซ์" กัน** ไม่งั้นบรรทัดสั้นจะดูใหญ่โตกว่าอีกบรรทัดผิดสัดส่วน —
  ฟังก์ชัน `balance()` จำกัดอัตราส่วนไม่เกิน `BALANCE_RATIO=1.9` เท่า
- **ระยะห่างแนวตั้งระหว่าง 2 บรรทัดต้อง "คงที่" ไม่ใช่สัดส่วนกับขนาด** — ถ้าคำนวณ gap เป็น `k × ขนาดรวม` ตรงๆ
  จะทำให้ shot ตัวใหญ่ดู "ห่าง" กว่า shot ตัวเล็กอย่างชัดเจน (ไม่สม่ำเสมอ) **วิธีแก้ที่ถูกต้อง**: แยกเป็น
  "ระยะที่แค่แตะกันพอดี" (`LINE_HALF × (ขนาดขาว+ขนาดส้ม)`) **บวก** "แพดคงที่เล็กๆ" (`GAP_PAD=6`) —
  ผลคือช่องว่างที่ตาเห็นจริง (แพด) เท่ากันทุก shot ไม่ว่าฟอนต์จะเล็กหรือใหญ่ **นี่คือ insight สำคัญที่สุดของระบบ**
- **ขอบล่างของบรรทัดส้มต้องยึด `BOTTOM_EDGE` คงที่เสมอ** (ไม่ลอยตามขนาดฟอนต์) แล้วให้บรรทัดขาวขยับขึ้นเพิ่ม
  จากตรงนั้น — ถ้าใช้จุดกึ่งกลางคงที่แทน (ที่เคยลองมาก่อน) ตัวอักษรใหญ่จะดันเข้าใกล้กลางจอ ผู้ใช้ต้องลากลงเองทุกครั้ง

---

## 7. อัลกอริทึมแบบ pseudocode (สำหรับ port ไปภาษา/สแต็กอื่น)

```
FUNCTION generate_cover(source_fcpxml, overrides = {}):
    xml = parse(source_fcpxml)  # ถ้าเป็น .fcpxmld ให้เปิด Info.fcpxml ข้างใน
    popup_effect_id = find effect where name == "Pop-up Text"
    IF not found: ERROR

    all_titles = xml.findAll("title")
    subtitle_titles = FILTER all_titles WHERE:
        - has a text-style child
        - text-style.bold != "1"      # ไม่ใช่ตัวหนา = ไม่ใช่ไฮไลต์เดิม/ป้ายราคา/CTA
        - name does NOT end with " - COVER"   # กันดึงคัฟเวอร์เก่าที่เคยสร้างเองซ้ำ
        - text is non-empty, not a disclaimer

    pairs = []
    FOR idx, sub_title IN enumerate(subtitle_titles):
        # หา parent element ที่รองรับการแปะ connected-clip (เดินขึ้นข้าม <spine> สะสม offset)
        offset = sub_title.offset
        node = sub_title
        WHILE parent(node).tag == "spine":
            offset += parent(node).offset
            node = parent(node)
        anchor_parent = parent(node)
        IF anchor_parent.tag NOT IN {clip, asset-clip, ref-clip, mc-clip, sync-clip, gap, video, audio, title}:
            SKIP this subtitle

        IF idx IN overrides:
            white, orange = overrides[idx]
            IF white == "" AND orange == "": SKIP (ผู้ใช้ลบทิ้ง)
        ELSE:
            white, orange = smart_split(sub_title.text)   # ดูหัวข้อ split algorithm ด้านล่าง

        duration = sub_title.duration   # ใช้เวลาเดียวกับซับเดิมเป๊ะ

        IF white == "":  # ประโยคสั้น -> บรรทัดเดียว
            size_o = fit_size(orange)
            y = BOTTOM_EDGE + LINE_HALF * size_o + SINGLE_RAISE
            create_popup_title(orange, color=ORANGE, size=size_o, x=X_ORANGE, y=y,
                                offset=offset, duration=duration, lane=LANE_ORANGE,
                                insert_before_filters_in=anchor_parent)
        ELSE:
            size_w, size_o = balance(fit_size(white), fit_size(orange))
            gap = LINE_HALF * (size_w + size_o) + GAP_PAD
            y_orange = BOTTOM_EDGE + LINE_HALF * size_o
            y_white  = y_orange + gap
            create_popup_title(white,  color=WHITE,  size=size_w, x=X_WHITE,  y=y_white,
                                offset=offset, duration=duration, lane=LANE_WHITE, ...)
            create_popup_title(orange, color=ORANGE, size=size_o, x=X_ORANGE, y=y_orange,
                                offset=offset, duration=duration, lane=LANE_ORANGE, ...)

        pairs.append((idx, white, size_w, orange, size_o))

    problems = validate(pairs)   # เช็คล้นเฟรม/ขนาดนอกเกณฑ์/ทับกัน
    IF problems: ERROR, don't write file

    write xml to {project_name}_cover.fcpxml
    RETURN pairs


FUNCTION fit_size(text):
    size = min(SIZE_MAX, FILL_WIDTH / length(text))
    WHILE size > HARD_MIN AND length(text) * size > MAX_UNITS:
        size -= 1
    RETURN max(HARD_MIN, size)


FUNCTION smart_split(text):
    IF length(text) <= SHORT_MAX_CHARS: RETURN ("", text)   # บรรทัดเดียว

    # จุดตัดปลอดภัย = ตำแหน่งที่ 2 ตัวตัดคำ (engine ต่างกัน) เห็นตรงกัน + ตำแหน่งหลังช่องว่างเสมอ
    safe_cuts = (word_boundaries(text, engine="A") ∩ word_boundaries(text, engine="B"))
                 ∪ positions_after_spaces(text)

    best = null
    FOR cut IN safe_cuts:
        a, b = text[:cut], text[cut:]
        score = abs(length(a) - length(b))                      # อยากให้บาลานซ์
        IF b starts with keyword: score -= KEYWORD_BONUS         # ดันคำเด่นไปบรรทัดล่าง
        IF cut is right after/before a space: score -= SPACE_BONUS
        IF last_word(a) IN NO_TRAIL_WORDS: score += TRAIL_PENALTY   # ห้ามคำเกาะจบบรรทัดบน
        IF b starts with word IN NO_LEAD_WORDS: score += LEAD_PENALTY  # ห้ามอนุภาคท้ายขึ้นบรรทัดล่าง
        keep lowest-score candidate
    RETURN best (a, b)
```

---

## 8. ⚠️ บั๊กที่ยังแก้ไม่เสร็จ ณ ตอนส่งมอบ — สำคัญมาก อย่าข้าม

### 8.1 อาการ
ผู้ใช้ทดสอบไฟล์ที่ซับทำจาก **Custom title** ของ FCP (ไม่ใช่ Pop-up Text) แล้วได้ error:
```
❌ ไม่พบซับ (Pop-up Text ฟอนต์ Light) ในไฟล์นี้
```
(ข้อความ error นี้เป็นข้อความเก่าที่ยังไม่ได้อัปเดตให้ตรงกับ logic ใหม่ด้วย — ดู 8.3)

### 8.2 สิ่งที่แก้ไปแล้ว (แต่ยังไม่พอ)
เดิมฟังก์ชัน `sub_text()` เช็คแค่ `text-style.fontFace == "Light"` ซึ่งไม่ครอบคลุม Custom title
(ที่มักไม่ตั้งค่า fontFace เลย) — **แก้เป็นเช็ค `bold != "1"` แทน** โดยอ้างอิงจากข้อมูลจริงว่า
"ไฮไลต์/ป้ายราคา/CTA ทุกอันเป็น Bold เสมอ ส่วนซับธรรมดาไม่ Bold" — **ทดสอบผ่านกับไฟล์จำลอง (synthetic XML)**
ที่ผมสร้างเองแล้วใช้ได้ถูกต้อง (ดึงทั้ง Pop-up Text Light และ Custom-ไม่มี-fontFace ได้ ไม่ดึงไฮไลต์ Bold ปน)

**แต่ผู้ใช้ทดสอบกับไฟล์จริง (export จาก Custom title จริง) แล้วยัง error "ไม่พบซับ" อยู่ดี**
แปลว่า **สมมติฐานเรื่อง `bold` attribute อาจไม่ตรงกับความเป็นจริงของ Custom title ในไฟล์ผู้ใช้**

### 8.3 สมมติฐานที่ยังไม่ได้ตรวจสอบ (ต้องทำต่อ)
กำลังจะ inspect ไฟล์ export จริงของผู้ใช้ (`.fcpxmld`) ด้วยคำสั่งนี้ตอนที่ถูกขัดจังหวะ:
```python
import xml.etree.ElementTree as ET
r = ET.parse(path).getroot()
effects = {e.get('id'): e.get('name') for e in r.iter('effect')}
titles = list(r.iter('title'))
for t in titles:
    ts = t.find('.//text-style-def/text-style')
    if ts is None: continue
    eff = effects.get(t.get('ref'), t.get('ref'))
    print(eff, ts.get('fontFace'), ts.get('bold'), ts.get('font'))
```
**ยังไม่ได้รันจนจบ** (ผู้ใช้ยกเลิกคำสั่งกลางคัน) — **นี่คือสิ่งแรกที่ควรทำต่อ**

สมมติฐานที่เป็นไปได้ว่าทำไม bold-based detection ยังพลาด:
1. **Custom title ของ FCP อาจตั้ง `bold="1"` เป็นค่า default เสมอ** แม้ Face จะเป็น "ExtraLight"/"Regular"
   (พบหลักฐานทางอ้อมจาก screenshot จริงของผู้ใช้: Custom title ใช้ฟอนต์ "Prompt" หน้า "ExtraLight" —
   ถ้า Bold checkbox แยกต่างหากจากช่อง Face และผู้ใช้/เทมเพลตติ๊กมันไว้ ก็จะ false-positive ว่าเป็นไฮไลต์)
2. **`text.find('.//text-style-def/text-style')` อาจหา element ไม่เจอเลย** ถ้าโครงสร้าง Custom title
   ซ้อน XML ต่างจาก Pop-up Text (เช่น text-style-def อยู่นอก title โดยตรง อ้างอิงผ่าน resources แทน)
3. **`popup = find effect name=='Pop-up Text'`** อาจหาไม่เจอถ้าไฟล์ที่ export มามีแค่ Custom title
   ล้วนๆ ไม่มี Pop-up Text อยู่เลยแม้แต่อันเดียว (แต่ถ้าเป็นกรณีนี้ error message จะเป็น
   `"ไม่พบ effect 'Pop-up Text' ในไฟล์ (ซับต้องเป็น Pop-up Text)"` **ไม่ใช่** ข้อความที่ผู้ใช้เจอ ("ไม่พบซับ...")
   ดังนั้นข้อนี้น่าจะ **ไม่ใช่สาเหตุ** — แปลว่า popup effect หาเจอ แต่ตัวกรอง `sub_text()` กรองออกหมด)

**แนวทางแก้ที่แนะนำ** (เรียงตามลำดับที่ควรทำ):
1. Inspect XML จริงของผู้ใช้ตามสคริปต์ข้างบนก่อน เพื่อยืนยันว่า attribute จริงเป็นอะไร (อย่าเดาต่อ)
2. ถ้าพบว่า Custom title ตั้ง `bold="1"` จริง แต่ Face ไม่ใช่ "Bold"/"ExtraBold" ให้เปลี่ยนตรรกะเป็น
   **เช็คทั้ง `bold` และ `fontFace`** ร่วมกัน — เช่น ถือว่าเป็นไฮไลต์ก็ต่อเมื่อ `bold=="1"` **และ**
   `fontFace` ไม่ใช่ "Light"/"Regular"/"ExtraLight"/None (กันกรณี Custom title ติ๊ก bold ค้างแต่หน้าตาไม่หนา)
3. หรือถ้า element structure ต่างกันจริง อาจต้องเพิ่ม fallback: ถ้า `.//text-style-def/text-style` หาไม่เจอ
   ให้ลองหาจาก path อื่น (เช่นดูใน resources แทน แล้ว join ผ่าน ref)
4. **ปรับ error message ให้ตรงกับ logic ใหม่ด้วย** (ตอนนี้ยังพิมพ์ "ไม่พบซับ (Pop-up Text ฟอนต์ Light)"
   ทั้งที่ logic เปลี่ยนเป็น bold-based ไปแล้ว — สร้างความสับสน ควรแก้เป็นข้อความที่อธิบายตรงปัญหาจริง)
5. เพิ่ม debug mode/flag ที่ dump รายชื่อ + attribute ของทุก `<title>` ที่เจอในไฟล์ ให้ผู้ใช้ส่งกลับมาได้ง่ายๆ
   โดยไม่ต้องให้ Claude รันคำสั่งเองทุกรอบ (ลด friction ในการ debug ครั้งต่อไป)

**ไฟล์ทดสอบจริงที่ผู้ใช้ใช้ล่าสุด** (ถ้ายังอยู่ในเครื่องเดิม):
- `~/Desktop/เจ้/Claude test.fcpxmld`
- `~/Desktop/เจ้/โปร อั้มคอฟฟี่ รวมสารสกัด มีดีต่อลำไส้.fcpxmld`

(ไฟล์อันที่ 2 นี้ **เคย** วิเคราะห์สำเร็จมาก่อนหน้านี้ในเซสชันเดียวกัน — เห็น GUI แสดงพรีวิว 27 คู่ได้ถูกต้อง
ดังนั้นบั๊กนี้อาจจะ **ไม่ได้เกิดกับทุกไฟล์ที่มี Custom title** แต่เกิดกับบางไฟล์เท่านั้น — เป็นเบาะแสสำคัญว่า
attribute pattern อาจแตกต่างกันระหว่าง Custom title ที่สร้างต่างช่วงเวลา/ต่างการตั้งค่าเริ่มต้น)

---

## 9. Testing methodology ที่ใช้มาตลอด (แนะนำให้ทำต่อแบบเดิม)

ทุกครั้งที่แก้โค้ด ควรทำตามลำดับนี้ (คือสิ่งที่ทำมาตลอดทั้งโปรเจกต์ ป้องกันงานพังหลุดไปถึงผู้ใช้):

1. `python3 -c "import ast; ast.parse(open('FILE.py').read())"` — เช็ค syntax ก่อนเสมอ
2. สร้าง **synthetic FCPXML ขนาดเล็ก** (2-3 titles) ที่จำลองเคสที่กำลังแก้ (ดูตัวอย่างในโค้ดหัวข้อ 3/4
   ที่เคยใช้ทดสอบ overrides/Custom title/word-splitting) — รันผ่าน `analyze()`/`run()` โดยตรงจาก Python
   ไม่ต้องเปิด GUI ก็ตรวจ logic ได้เร็วกว่า
3. เช็คผลลัพธ์ด้วย `xml.dom.minidom.parse()` ว่า XML valid
4. **สำคัญที่สุด**: import ไฟล์ผลลัพธ์เข้า Final Cut Pro จริง (ผ่าน File → Import → XML, เลือก "Keep Both")
   แล้ว **ดูด้วยตาจริงในโปรแกรม** ว่าเรนเดอร์ถูกต้อง (ตำแหน่ง/ขนาด/ไม่ล้น/ไม่ทับ/ไม่มี DTD error) —
   คณิตศาสตร์อย่างเดียวไม่พอ เคยมีเคสที่คำนวณถูกแต่เรนเดอร์จริงผิด (เช่น newline ใน tail vs ในเนื้อหา)
5. หลังแก้ codesign ใหม่เสมอก่อนให้ผู้ใช้ทดสอบ

---

## 10. สรุปสำหรับผู้รับมอบงาน (ทำ 3 ข้อนี้ก่อนอื่นใด)

1. **อ่านหัวข้อ 8 ก่อน** — มีบั๊กค้างอยู่ที่ผู้ใช้เพิ่งรายงานสดๆ ยังไม่ได้แก้เสร็จ
2. Copy ไฟล์ 4 ไฟล์ในหัวข้อ 3-5 ไปวางในโครงสร้างเดียวกัน (`.app/Contents/{MacOS,Resources,Info.plist}`)
   หรือถ้าจะรวมเข้ากับโปรเจกต์อื่นที่มีโครงสร้างต่างออกไป อย่างน้อยต้องคง **`cover_subtitles.py` ไว้เป็นก้อนเดียว
   ไม่แยกไฟล์** เพราะฟังก์ชันผูกกันแน่นมาก (โดยเฉพาะค่าคงที่ทั้งหมดในหัวข้อ 6.2/6.4 ที่คาลิเบรตมาด้วยกัน)
3. ถ้าจะ debug บั๊กหัวข้อ 8 ต่อ ให้เริ่มจากขอไฟล์ `.fcpxmld` ตัวอย่างจากผู้ใช้ แล้ว inspect โครงสร้างจริงก่อนแก้โค้ด
   **อย่าเดา/แก้แบบไม่เห็นข้อมูลจริง** — ทุกค่าคงที่ในไฟล์นี้มาจากการดูข้อมูลจริงทั้งหมด ไม่ใช่การเดา
   (นี่คือแนวทางที่ยึดมาตลอดทั้งโปรเจกต์และได้ผลดี)
