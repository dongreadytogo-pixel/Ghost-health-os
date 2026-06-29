# Project Titan — Free Asset Sourcing & License Guide

แหล่งทรัพยากร **ฟรีและถูกลิขสิทธิ์** สำหรับเกม: โมเดล/ตัวละคร, UI, ไอคอน,
ซาวด์เอฟเฟกต์, ฟอนต์ — คัดมาเฉพาะแหล่งที่ใบอนุญาต **อนุญาตให้ใช้ในเกมเชิงพาณิชย์**

> 🎵 **เพลงแบ็กกราวนด์ (BGM):** ผู้ใช้มีของตนเองที่ถูกลิขสิทธิ์อยู่แล้ว — จะแนบภายหลัง.
> เก็บหลักฐานสิทธิ์ (ใบเสร็จ/ใบอนุญาต) ไว้ใน `assets/audio/music/LICENSE-PROOF/`
> และบันทึกใน `ATTRIBUTIONS.md` ด้วย แม้จะเป็นของเราเองก็ตาม.

---

## 0) กฎเหล็ก (อ่านก่อนนำเข้า asset ทุกครั้ง)

1. **ตรวจ License ก่อนดาวน์โหลดทุกไฟล์** — แหล่งฟรีหลายแห่ง (OpenGameArt, itch.io,
   Freesound) มีใบอนุญาต *ต่อชิ้น* ที่ต่างกัน อย่าเหมารวมว่า "ทั้งเว็บคือ CC0".
2. ใช้เฉพาะใบอนุญาตในรายการ **อนุญาต** ด้านล่าง. ถ้าเจอ `NC` (Non-Commercial),
   `ND` (No-Derivatives) หรือ "personal use only" → **ห้ามใช้**.
3. ทุกชิ้นที่นำเข้าต้องบันทึกใน [`ATTRIBUTIONS.md`](./ATTRIBUTIONS.md) (ดูฟอร์แมตในนั้น).
4. เก็บไฟล์ asset ใน `assets/` แยกตามชนิด; โค้ดเกมไม่ผูกกับ asset ใดเฉพาะเจาะจง
   (ดูหลักการ data-driven ใน README) → เปลี่ยน asset ได้โดยไม่แตะ logic.

### ใบอนุญาตที่ "อนุญาต" ✅ และข้อผูกมัด

| License | ใช้เชิงพาณิชย์ | ต้องเครดิต | หมายเหตุ |
|---|---|---|---|
| **CC0 / Public Domain** | ✅ | ไม่บังคับ (แต่ควรให้) | ดีที่สุด — ไม่มีข้อผูกมัด |
| **CC-BY 4.0/3.0** | ✅ | **บังคับ** | ต้องลงเครดิตผู้สร้าง |
| **OGA-BY** | ✅ | **บังคับ** | เหมือน CC-BY เฉพาะ OpenGameArt |
| **MIT / Apache-2.0** | ✅ | บังคับ (ข้อความ license) | มักใช้กับฟอนต์/โค้ด |
| **SIL OFL** (ฟอนต์) | ✅ | ตามเงื่อนไข | ฝังฟอนต์ในเกมได้ |

### ใบอนุญาตที่ต้อง "ระวัง" ⚠️ / "ห้าม" ❌

- ⚠️ **CC-BY-SA / GPL** — "ติดเชื้อ" (share-alike/copyleft). งานดัดแปลงต้องเปิดสิทธิ์
  แบบเดียวกัน. ใช้ได้แต่เลี่ยงถ้าไม่อยากผูกมัด (เช่น sprite ชุด LPC).
- ❌ **CC-BY-NC** (Non-Commercial), **CC-BY-ND**, "free for personal use",
  Mixamo redistribute ข้าม Adobe ฯลฯ → **ไม่ใช้กับเกมที่จะหารายได้**.

---

## 1) 🎨 ทิศทางศิลป์ที่แนะนำ (Mobile-First)

มีสองแนวที่คุ้ม. เลือกแนวเดียวเพื่อความกลมกลืน:

**แนะนำ A — Low-Poly 3D (CC0 เป็นหลัก, กลมกลืน, เบาบนมือถือ)**
ตัวละคร/มอนสเตอร์/ฉากจาก Quaternius + KayKit, อนิเมชันจาก Mixamo, ไอคอนสกิลจาก
game-icons, UI/เสียงจาก Kenney. แทบทั้งหมดเป็น **CC0** → ผูกมัดน้อยที่สุด.

**ทางเลือก B — 2D Sprite / Pixel**
Kenney 2D + LPC characters (ระวัง CC-BY-SA) + game-icons + Kenney UI/audio.

---

## 2) 🧍 โมเดล & ตัวละคร (3D)

| แหล่ง | License | เหมาะกับ |
|---|---|---|
| **Quaternius** (quaternius.com) | **CC0** | ตัวละคร, มอนสเตอร์, อาวุธ, ฉาก low-poly — ชุดใหญ่มาก |
| **KayKit / Kay Lousberg** (kaylousberg.com) | **CC0** | ชุด adventurers, skeletons, dungeon — สไตล์เดียวกันทั้งชุด |
| **Poly Pizza** (poly.pizza) | CC0 / CC-BY (ดูต่อชิ้น) | คลังโมเดล low-poly ค้นหาง่าย |
| **Kenney 3D** (kenney.nl) | **CC0** | props, modular dungeon, characters |
| **OpenGameArt** (3D filter) | กรอง CC0/CC-BY | เสริมเฉพาะชิ้น |

**อนิเมชัน:** **Mixamo** (mixamo.com, ฟรี, ต้องมีบัญชี Adobe) — rig + animation
อัตโนมัติ ใช้ในโปรเจกต์เชิงพาณิชย์ได้ แต่ **ห้าม** redistribute ไฟล์ดิบเป็นคลังแยก.

## 3) 🖼️ UI (ปุ่ม, กรอบ, แผงหน้าจอ)

| แหล่ง | License | หมายเหตุ |
|---|---|---|
| **Kenney UI Pack / UI Pack RPG Expansion** | **CC0** | ครบชุดที่สุดสำหรับ RPG/idle |
| **Kenney Game Icons** | **CC0** | ไอคอนระบบ (gear, heart, coin) |
| **OpenGameArt UI** | กรอง CC0/CC-BY | เสริมธีม |

## 4) ⚔️ ไอคอนสกิล / ไอเทม (RPG)

| แหล่ง | License | หมายเหตุ |
|---|---|---|
| **game-icons.net** | **CC-BY 3.0** | ~4,000+ ไอคอน skill/item/affix — มาตรฐานวงการ RPG. **ต้องเครดิต** |
| **Kenney Board/Item icons** | **CC0** | ไอคอนของสะสม, ทรัพยากร |

> ไอคอนพวกนี้แมปกับ `ItemDefinition` / `SkillDefId` แบบ data-driven ได้เลย —
> เก็บชื่อไฟล์ไอคอนเป็น field ใน definition.

## 5) 🔊 ซาวด์เอฟเฟกต์ (SFX)

| แหล่ง | License | หมายเหตุ |
|---|---|---|
| **Kenney Audio** (ui/impact/rpg) | **CC0** | ชุด SFX เกมพร้อมใช้ |
| **Freesound.org** | กรอง **CC0** เท่านั้น | คลังใหญ่ — ตั้งฟิลเตอร์ license = CC0 |
| **Sonniss GDC Game Audio bundle** | Royalty-free เชิงพาณิชย์ | คุณภาพสูง ปล่อยฟรีทุกปี |
| **jsfxr / Bfxr / ChipTone** | งานที่สร้างเอง = ของเรา | สร้าง SFX 8-bit เองได้ทันที |

## 6) 🔡 ฟอนต์

| แหล่ง | License | หมายเหตุ |
|---|---|---|
| **Google Fonts** | **SIL OFL / Apache** | ฝังในเกมได้, รองรับไทย (เช่น Noto Sans Thai, Sarabun, IBM Plex) |
| **Font Library** (fontlibrary.org) | กรอง OFL | ฟอนต์ตกแต่ง/หัวเรื่อง |

---

## 7) โครงสร้างโฟลเดอร์ asset ที่แนะนำ

```
assets/
  models/        # .glb/.gltf  (Quaternius, KayKit …)
  sprites/       # 2D ถ้าใช้แนว B
  ui/            # Kenney UI
  icons/         # game-icons (skill/item), Kenney icons
  audio/
    sfx/         # Kenney/Freesound CC0
    music/       # 🎵 BGM ของผู้ใช้ (+ LICENSE-PROOF/)
  fonts/         # OFL fonts
```

ดู [`ATTRIBUTIONS.md`](./ATTRIBUTIONS.md) สำหรับวิธีบันทึกเครดิตทุกชิ้นที่นำเข้า.
