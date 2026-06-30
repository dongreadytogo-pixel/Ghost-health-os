# Asset Attributions / เครดิตทรัพยากร

บันทึก **ทุกชิ้น** ที่นำเข้าโปรเจกต์ ก่อน import ลง `assets/`. แม้แต่ของ CC0
(ไม่บังคับเครดิต) และของที่เป็นของเราเอง ก็ควรบันทึกไว้เพื่อตรวจสอบสิทธิ์ภายหลัง.

> วิธีใช้: คัดลอกแถวในตารางต่อท้าย, กรอกข้อมูล, แล้ว commit พร้อมไฟล์ asset.
> ถ้าใบอนุญาตต้องการไฟล์ข้อความ (เช่น CC-BY, OFL) ให้วาง license ต้นฉบับไว้ข้าง ๆ
> ไฟล์ asset หรือใน `assets/<หมวด>/LICENSES/`.

## รูปแบบที่ต้องกรอก

| ไฟล์ asset | ชื่อผลงาน | ผู้สร้าง | แหล่งที่มา (URL) | License | ต้องเครดิต? | หลักฐาน |
|---|---|---|---|---|---|---|
| _(ตัวอย่าง)_ `models/hero_base.glb` | Adventurers Pack | Quaternius | https://quaternius.com | CC0 | ไม่ | — |
| _(ตัวอย่าง)_ `icons/skill_fireball.png` | Game-icons | Lorc | https://game-icons.net | CC-BY 3.0 | **ใช่** | license ใน `icons/LICENSES/` |
| _(ตัวอย่าง)_ `audio/music/theme_01.ogg` | (BGM ของผู้ใช้) | เจ้าของโปรเจกต์ | (สิทธิ์ของตนเอง) | Owned/Licensed | — | `audio/music/LICENSE-PROOF/` |

<!-- เพิ่มแถวจริงด้านล่างนี้ เมื่อมีการ import asset -->

## Asset ที่ใช้งานจริงแล้ว (In use)

| ไฟล์ | ผลงาน | ผู้สร้าง | แหล่งที่มา | License | เครดิต |
|---|---|---|---|---|---|
| `apps/titan-web/assets/0x72_dungeon.png` | DungeonTileset II | **0x72** | https://0x72.itch.io/dungeontileset-ii | **CC0 1.0** (Public Domain) | ไม่บังคับ (ให้เครดิตแล้ว) |

> สไปรท์ตัวละคร/มอนสเตอร์/เพื่อนในเกมเว็บใช้จากชุดนี้ทั้งหมด — เป็น **CC0**
> ใช้เชิงพาณิชย์ได้เต็มที่ ไม่ต้องขออนุญาต. เปลี่ยนสไตล์ได้โดยสลับไฟล์ PNG +
> ตาราง `FRAMES` ใน `apps/titan-web/src/sprites.ts`.

## หมายเหตุการให้เครดิต (สำหรับหน้าจอ Credits ในเกม)

รวบรวมเครดิตของ asset ที่ใบอนุญาต **บังคับ** (CC-BY, OGA-BY, MIT, OFL) ไว้แสดง
ในเกม เช่น:

```
ART / ICONS
  Game-icons.net — Lorc, Delapouite และคณะ (CC-BY 3.0)

3D MODELS
  Quaternius (CC0), Kay Lousberg / KayKit (CC0)

UI & SFX
  Kenney.nl (CC0)

FONTS
  Noto Sans Thai — Google (SIL OFL 1.1)
```
