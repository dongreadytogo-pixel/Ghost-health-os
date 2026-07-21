# HANDOFF — Ghostly790K AI Final Cut Studio → ส่งต่อให้โปรเจกต์ "Subtitle converter for Final Cut Pro"

> เอกสารนี้สรุป **ทุกอย่าง** ในโปรแกรม Ghostly790K เพื่อให้ Claude Code อีกแชท
> (โปรเจกต์ "โปรดึงไฮไลท์ขึ้น / Subtitle converter for Final Cut Pro") นำไปรวมได้
> อย่างมีประสิทธิภาพ โดยไม่ตกหล่นความรู้ที่สั่งสมมา — โครงสร้างโค้ด, คำสั่ง CLI ทุกตัว,
> ค่าคงที่ที่คาลิเบรตแล้ว, กฎ FCPXML ที่ไม่มีในเอกสารทางการ, และบั๊ก/ข้อจำกัดที่ยังเปิดอยู่
>
> **หมายเหตุความจริง**: ทั้งหมดถูกทดสอบผ่าน CI (คอมไพเลอร์ + unit tests) และบางส่วน
> ทดสอบกับ FCP จริงโดยผู้ใช้ ส่วนที่ยัง **ไม่ได้ยืนยันบนเครื่องผู้ใช้** จะระบุไว้ในหัวข้อ 11

---

## 1. โปรแกรมนี้คืออะไร

**Ghostly790K AI Final Cut Studio** = ผู้ช่วยตัดต่อ AI ภาษาไทยสำหรับนักตัดต่อมืออาชีพหนึ่งคน
(ส่วนตัว ไม่ใช่เชิงพาณิชย์ ตาม Personal Workflow Constitution v5) เน้นสาย **Final Cut Pro** ให้ใช้ได้จริง:

- รับวิดีโอจริง (mov/mp4) → แตกเสียง → (ถอดซับไทยด้วย whisper) → ตัดต่ออัตโนมัติ →
  ออกไฟล์ **FCPXML** ที่เปิดใน Final Cut Pro ได้ทันที ฟุตเทจออนไลน์ ไม่ต้อง relink
- คำสั่งเป็นภาษาไทยธรรมชาติ เช่น "คัตเสียงคลิปนี้โดยเน้นประโยคสำคัญที่น่าสนใจ ความยาวเหลือไม่เกิน 3 นาที"
- แอป macOS แบบ **เมนูปุ่มคำสั่ง** (ลากไฟล์วาง / เลือกจากเมนู วนใช้ซ้ำได้)

**ภาษา/สแตก**: Swift 6 (swift-tools 5.9), Package แบบหลายโมดูล, macOS 14+ (แต่เอนจินหลัก
คอมไพล์/รันบน Linux ได้ด้วย ผ่าน `#if canImport(...)` gating) — CI ทดสอบทั้ง Linux + macOS

**Repo/branch**: `dongreadytogo-pixel/Ghost-health-os` โฟลเดอร์ `studio/`
branch พัฒนา: `claude/ghostly790k-ai-final-cut-4z7syw`

**build**: `cd studio && swift build -c release --product ghostly` (ต้องมี Xcode/Swift toolchain)

---

## 2. แผนที่โมดูล (Swift targets ใน studio/Package.swift)

ชั้นล่าง → บน (dependency ไล่ขึ้น):

| โมดูล | หน้าที่ |
|---|---|
| **GhostlyCore** | ชนิดเวลา (RationalTime, TimeRange, FrameRate), StudioError, JSONValue |
| **GhostlyDomain** | โมเดลโดเมน: Asset, Timeline, Clip, Caption, Marker, MotionTitle, VideoFormat, Project, Library |
| **GhostlyFCPXML** | เขียน/อ่าน/validate FCPXML — **หัวใจของการส่งออก FCP** (ดูหัวข้อ 6) |
| **GhostlySubtitles** | SRT/WebVTT parse+serialize, CaptionStyle (TikTok/YouTube/IG/Broadcast), ThaiSegmentation (ตัดพยางค์ไทย), sentence grouping |
| **GhostlyDetection** | WAV codec (ไม่มี dependency), AudioFixture, SilenceDetector, BeatDetector, SpeakerDiarizer, **AudioAligner** (multicam), AVAudioSampleProvider (macOS), VisionDetectionProvider (macOS) |
| **GhostlyAudio** | Loudness (RMS/LUFS K-weighting), AudioCleanup (high-pass/de-hum/gate), MusicDucking |
| **GhostlyColor** | CUBE LUT parse/generate/apply, auto white balance |
| **GhostlyExport** | RenderPreset, FFmpegCommandBuilder (+Trim), MediaExtraction (ffmpeg recipes), ToolchainCheck |
| **GhostlyDirector** | **เอนจินตัดต่อ**: EditIntentParser, Director, PacingProfile, AutoEditPlanner, EditPipeline, Workflow, HighlightPlanner, ChapterExport, ThaiImportance, MotionGraphics |
| **GhostlyCover** | **SUBTITLE Cover ที่พอร์ตมา** (ดูหัวข้อ 8) |
| **GhostlyLearning** | PreferenceStore (AI memory จำค่าที่เคยใช้) |
| **GhostlyAssets** | auto-tag, NL search (ไทย/อังกฤษ) |
| **GhostlyMCP** | MCP server tools (16 tools) |
| **GhostlyViewModels / GhostlyApp** | SwiftUI (platform-gated) |
| **GhostlyCLI** → `ghostly` | executable รวมทุกคำสั่ง |
| **GhostlyMCPServer** → `ghostly-mcp-server` | MCP stdio server |

ทดสอบ: ~17 test targets, ~470 tests. CI = คอมไพเลอร์ (ไม่มี local toolchain ตอนพัฒนา)

---

## 3. คำสั่ง CLI ทั้งหมด (`ghostly <cmd>`)

- **auto** `<video>` [--command "..."] [--model ggml.bin] [--whisper path] [--preset] [--remember] [--diarize] [--clean] [--out] — **คลิกเดียวจบ**: วิดีโอ→แตกเสียง(native/ffmpeg)→ซับ(whisper)→ตัดต่อ→FCPXML อ้างอิงไฟล์จริง
- **sync** `<cam1> <cam2> ...` [--name] [--vertical] [--out] — **ซิงก์มุมกล้อง** ด้วยเสียง → FCP multicam clip
- **cover** `<exported.fcpxml|.fcpxmld>` [--out] [--list-titles] — **SUBTITLE Cover**: ไฮไลต์ป๊อบอัพ 2 บรรทัด ขาว/ส้ม ทับซับเดิม
- **edit** `<subs.srt> --duration N --command "..."` | `--wav <clip.wav>` [--media video.mp4] — ตัดต่อจากซับ/เสียง
- **workflow** — สายเต็ม analyze→edit→captions→FCPXML→export command
- **intent** "..." — ดูว่าคำสั่งไทยถูกแปลเป็น intent อะไร
- **chapters** / **highlights** / **shorts** — (YouTube extras — deprioritized ตามผู้ใช้)
- **captions** <srt> --style — restyle ซับ
- **transcribe** <audio> --model — whisper.cpp → SRT (--sentences จัดกลุ่มประโยค)
- **extract-audio** <video> [--run] — ffmpeg → WAV (--run รันจริง)
- **analyze-audio** / **normalize-audio** / **clean-audio** / **demo-audio** [--lead-silence N]
- **lut** / **lut-info** — CUBE LUT
- **validate** / **analyze** <fcpxml> — lint/report
- **doctor** — ตรวจ ffmpeg/whisper + วิธีติดตั้ง (ไทย)
- **styles** / **presets** / **demo-thai** / **version**

---

## 4. คำสั่งอัจฉริยะภาษาไทย (GhostlyDirector/EditIntent.swift)

`EditIntentParser.parse()` แปลคำสั่งไทย/อังกฤษเป็น `[EditIntent]` แบบ deterministic (ไม่ใช้ LLM):

Intents: `applyStyle`, `createDeliverable(tiktok/youtube/shorts/reel/instagram)`, `adjustPacing(faster/slower)`,
`generateCaptions`, `removeSilence`, `cutToBeat`, `replaceMusic`, `addTransitions`, `cleanAudio`,
**`limitDuration(seconds:)`**, **`emphasizeHighlights`**, **`titleSubtitles`**

คำสำคัญไทยที่จับได้ (ตัวอย่าง):
- "คัตเสียง/คัทเสียง/ตัดเสียง/ตัดช่วงเงียบ" → removeSilence (ระวัง "ตัดเสียงรบกวน" = cleanAudio ไม่ใช่)
- "เน้นประโยคสำคัญ/ช่วงที่น่าสนใจ/ไฮไลต์" → emphasizeHighlights
- "ไม่เกิน/เหลือ/ภายใน N นาที/วินาที/ชั่วโมง" (+เลขไทย หนึ่ง-สิบ, ทศนิยม) → limitDuration
- "ซับแบบ Title/ไตเติ้ล" → titleSubtitles
- "ลดเสียงรบกวน/แก้เสียงฮัม" → cleanAudio
- "ทำเป็นติ๊กต๊อก/ยูทูบ/ไอจี" → createDeliverable

`Director.interpret()` → `Plan{ profile, wantsCaptions, wantsAudioCleanup, ... }`
`PacingProfile` มี: minShotLength/maxShotLength, silenceRemoval, captionStyleName,
**maxTotalDuration**, **emphasizeHighlights**, **titleSubtitles** (ทั้งหมด tolerant-decode เผื่อไฟล์เก่า)

---

## 5. การเลือกช็อตตามเนื้อหา (สำคัญ — เพิ่งแก้บั๊ก "คัตมั่ว")

**บทเรียน**: การคัตสัมภาษณ์ให้เหลือแต่ประเด็นสำคัญ **ต้องมีซับ (transcript)** เพราะโปรแกรม
ต้องอ่านสิ่งที่พูดจริง ไม่มีซับ = เลือกได้จากพลังงานเสียงอย่างเดียว (หยาบ ดูเหมือน "คัตมั่ว")

`AutoEditPlanner` (GhostlyDirector):
- เมื่อ `emphasizeHighlights` + มี transcript → **`sentenceKeeps()`**: รวม cue ที่ห่างกัน ≤ 0.6s
  เป็นประโยค แล้วเก็บทั้งประโยค (ไม่หั่นกลางประโยค)
- `shotScore()` ให้คะแนนแต่ละช็อตจาก **`ThaiImportance.score()`** (คำสรุป/ผลลัพธ์/ตัวเลข/เครื่องหมายเน้น)
  ถ่วงน้ำหนัก 0.9 เมื่อสั่งเน้นประเด็น + beat/scene
- `applyDurationBudget()`: เก็บช็อตคะแนนสูงสุดที่พอดีงบเวลา (maxTotalDuration) เรียงตามเวลาเดิม
- **fallback สำคัญ**: ถ้า per-shot filter ตัดทิ้งหมด → ใช้ merged speech / ทั้งคลิป
  (กัน error "no usable segments found in footage" — เคยเป็นบั๊กจริงกับ profile podcast ช็อตยาว)

**ThaiImportance.swift**: keyword heuristics ล้วน (strongWords 0.35, weakWords 0.12, ตัวเลข 0.2, !/? 0.15)

---

## 6. FCPXML — กฎที่ไม่มีในเอกสารทางการ (GhostlyFCPXML/FCPXMLWriter.swift)

**หัวใจ**: `<asset><media-rep kind="original-media" src="...">` — `src` = `asset.url.absoluteString`
- ✅ **ต้องเป็น URL ไฟล์จริง** (percent-encoded) ไม่งั้น FCP ขึ้น offline/missing media
  โปรแกรมรับ `--media <path>` / `mediaURL` ส่งเข้ามาเป็น asset URL (มี placeholder เฉพาะโหมด CI ไม่มีสื่อ)
- เวลา: `offset` = เวลาใน parent timeline, `start` = source in-point ของ clip,
  child (marker/caption/title) วางในเวลา source ของ clip แม่ → map: `T - O + S`

**Multicam** (`multicamDocument`): `<media><multicam>` มี `<mc-angle angleID="A1">` แต่ละมุม
วาง asset-clip ด้วย delay ที่ซิงก์ได้ + project spine มี `<mc-clip ref>` ตัวเดียวครอบทั้งช่วง

**ResourceTable**: allocate r1,r2,… dedupe format/asset/effect; text style ts1,ts2,…

**Captions**: role `iTT?captionFormat=ITT.<lang>` (ไทย = ITT.th) — เป็น closed caption ของ FCP
เปิด/ปิด/ส่งออกได้ **แต่แต่งหนัก ๆ ไม่ได้** (เงา/อนิเมชัน/ฟอนต์อิสระทำไม่ได้)

**Title subtitles (ซับแบบ Title)**: ทางเลือก — วาง MotionTitle เลน 2 (Basic Title) เพิ่มอีกชั้น
พร้อมกับเลน caption ปกติ → แต่งใน FCP ได้เต็มที่ เลือกใช้/ลบอันไหนก็ได้

**Validator** เช็ค: ref ชี้ resource จริง, ลำดับ child ถูก DTD — **ผิดลำดับ import fail เงียบ ๆ**

---

## 7. Multicam sync ด้วยเสียง (GhostlyDetection/AudioAligner.swift)

- Cross-correlation แบบ coarse-to-fine (10Hz หาช่วง → 100Hz ละเอียด) บน RMS envelope
  ที่ลบค่าเฉลี่ยแล้ว → **ระดับเสียง/โคเดกต่างกันไม่มีผล**
- `offsetSeconds(reference, other)` คืนว่ากล้อง other เริ่มช้ากว่ากี่วินาที (ลบ = เริ่มก่อน)
- CLI `sync`: ดึงความยาว **จากตัววิดีโอจริง** (`AVAudioSampleProvider.mediaDuration` ผ่าน
  `AVURLAsset.duration`) ไม่ใช่จากจำนวนตัวอย่างเสียง (บั๊กเดิม: ไฟล์เสียงเบา→คลิปว่าง)
- **ไฟล์ไม่มีเสียง (โดรน)**: ซิงก์ด้วยเสียงไม่ได้ → ใส่มุมนั้นที่ offset 0 พร้อมเตือน
  ให้ผู้ใช้เลื่อนตรงเองใน FCP (ไม่ทิ้ง/ไม่ error) — reference audio = มุมแรกที่มีเสียงจริง

---

## 8. SUBTITLE Cover (GhostlyCover/) — โปรเจกต์ที่รวมเข้ามาแล้ว

พอร์ต 1:1 จาก Python เดิม (เอกสารเต็มที่ `docs/knowledge/SUBTITLE-COVER.md`):
- อ่านไฟล์ที่ Export XML จาก FCP → หา title ที่ **ไม่ใช่ตัวหนา** (= ซับธรรมดา) →
  ตัด 2 บรรทัด (ขาวบน/ส้มล่าง, ดันคำเด่นไปบรรทัดล่าง) → วางไฮไลต์ Pop-up 2 title แยกเลน (10/11)
  ตรงเวลาเป๊ะ → เขียน `{project}_cover.fcpxml` **ซับเดิมไม่ถูกแตะ**
- ค่าคาลิเบรตทุกตัวคงไว้ (LINE_HALF=0.58, GAP_PAD=6, BOTTOM_EDGE=55, FILL_WIDTH=1150,
  MAX_UNITS=1170, SIZE_MAX=120, HARD_MIN=32, Pop-up param keys, GLOBAL_POS...)
- **แก้บั๊กค้าง §8**: ไฮไลต์ = bold **และ** หน้าหนัก (Custom title ที่ bold=1 + ExtraLight
  นับเป็นซับ), fallback หา text-style ผ่าน ref, error message ตรงปัญหา, `--list-titles` debug
- ตัดคำไทย: NLTokenizer (macOS) ∩ ThaiSegmentation + หลังช่องว่าง + keyword/no-trail/no-lead scoring
- validate ก่อนเขียนไฟล์เสมอ (ล้นเฟรม/ขนาดนอกเกณฑ์)

> ⚠️ ถ้าอีกโปรเจกต์คือ "Subtitle converter" ที่ทำงานคล้ายกัน — **GhostlyCover คือแกนเดียวกัน**
> ควรรวมโดยยึด GhostlyCover เป็น source of truth (มันแก้บั๊ก §8 ไปแล้ว) หรือ merge ค่าคงที่ให้ตรงกัน

---

## 9. แอป macOS + การแพ็ก (dist/Ghostly790K-AI-Studio/)

- **Ghostly790K.app** = AppleScript droplet (`dist/Ghostly790K-droplet.applescript`) คอมไพล์ด้วย
  `osacompile` ใน CI + ลงทะเบียน document types (public.movie) ให้ลากไฟล์วางได้
- **เมนูวนใช้ซ้ำ**: เปิดแอป → เมนู 8 ปุ่ม (คัตอัจฉริยะ/TikTok/YouTube/ลดเสียงรบกวน/ซับ Title/
  ซิงก์มุมกล้อง/SUBTITLE Cover/พิมพ์เอง) → ทำงาน → กลับมาเมนู จนกดปิด
- **whisper + โมเดลไทยแพ็กมาในแอป** (`bin/whisper-cli` + `models/ggml-large-v3-turbo-q5_0.bin`)
  → ซับทำงานทันทีบน Apple Silicon ไม่ต้องติดตั้ง (Intel: build จากซอร์สผ่านปุ่มติดตั้งในแอป)
- ทนไฟล์ใหญ่: `caffeinate` กันหลับ, ไม่มี AppleScript timeout (เพดาน 24h), log ที่ `logs/ghostly.log`
- **สำคัญ**: ห้ามรัน `do shell script` ก่อนเมนูขึ้น (TCC prompt ซ่อนหลังหน้าต่าง = ดูเหมือนค้าง) —
  packageDir เป็น AppleScript ล้วน, ปลดล็อก quarantine ตอนสั่งงานครั้งแรก
- launcher.command + ติดตั้งครั้งแรก.command เป็น fallback

**gotchas macOS** (จาก SUBTITLE-COVER.md ด้วย): codesign ad-hoc ทุกครั้งที่แก้, ใช้ python.org
ไม่ใช่ /usr/bin/python3 (ถ้าทำ Tkinter), .fcpxmld = โฟลเดอร์ (เปิด Info.fcpxml ข้างใน),
ห้ามใส่ filetypes filter กับ .fcpxmld ในไดอะล็อก

---

## 10. CI (.github/workflows/studio-ci.yml)

- **linux-test** (swift:6.0): build+test, smoke ทุกคำสั่ง CLI, MCP handshake
- **macos-build** (macos-15): build+test, **build whisper-cli + โหลดโมเดล (cached)**,
  แพ็ก Ghostly790K.app + ไบนารี + โมเดล → artifact **Ghostly790K-AI-Studio**,
  verify whisper ถอดเสียงได้จริง
- ทุก commit: fix-forward, CI เป็น oracle. ผลรัน list เกิน token → เซฟไฟล์ → parse ด้วย python

---

## 11. บั๊ก/ข้อจำกัดที่ยังเปิดอยู่ (อย่าข้าม)

1. **แอปหมุนค้างตอนเปิด (ยังไม่ยืนยันแก้)**: ผู้ใช้รายงานว่ายังค้าง เดาว่า **Gatekeeper สแกน
   ไฟล์โมเดล 550MB** ตอนเปิดครั้งแรก (เกิดก่อนโค้ดแอปทำงาน) — วิธีทดสอบ:
   `xattr -dr com.apple.quarantine ~/Downloads/Ghostly790K-AI-Studio` แล้วเปิดใหม่
   **ยังไม่ได้คำตอบจากผู้ใช้ว่าหายไหม** — ถ้ายังค้าง อาจต้องแยกโมเดลออกจาก zip (โหลดตอนติดตั้ง)
   หรือ notarize แอป. (พัฒนาบน Linux ทดสอบ macOS GUI จริงไม่ได้ — ต้องพึ่งผู้ใช้ยืนยัน)
2. **โดรนซิงก์อัตโนมัติไม่ได้**: ไฟล์ไม่มีเสียงพูด → วางที่ offset 0 ให้เลื่อนเองใน FCP (by design)
3. **artifact เป็น arm64**: Intel Mac ต้อง build whisper เองผ่านปุ่มติดตั้งในแอป
4. **YouTube extras (chapters/highlights/shorts/export_chapters)**: ผู้ใช้สั่งพักไว้ — โค้ดมีครบแต่ deprioritized

---

## 12. วิธีรวมเข้ากับอีกโปรเจกต์อย่างมีประสิทธิภาพ (แนะนำ)

**ถ้าอีกโปรเจกต์เล็ก/เป็น subtitle converter เฉพาะทาง** → ดึงเฉพาะที่ต้องใช้:
- แกน cover: `GhostlyCover/` (SubtitleCover.swift + CoverBuilder.swift) พึ่งแค่ GhostlyCore+GhostlySubtitles
- ตัดคำไทย: `GhostlySubtitles/ThaiSegmentation.swift`
- FCPXML: `GhostlyFCPXML/` ถ้าต้องเขียน/อ่าน XML

**ถ้าจะรวมเป็นโปรแกรมเดียว** → นำ Ghostly790K เป็นฐาน (ครบกว่า) แล้วเพิ่มสิ่งที่อีกโปรเจกต์มีเกิน:
- ก็อป target ใหม่เข้า `studio/Package.swift` (library + testTarget + เพิ่ม dependency ใน GhostlyCLI)
- เพิ่ม `case "..."` ใน `GhostlyCLI/main.swift` + เมนูปุ่มใน `dist/Ghostly790K-droplet.applescript`
- เพิ่ม smoke test ใน `.github/workflows/studio-ci.yml`
- ทุกฟีเจอร์ต้องมีเทสต์ (synthetic FCPXML/WAV) + อัปเดต CHANGELOG.md

**หลักการที่ยึดมาตลอด** (ให้ทำต่อ):
1. ทดสอบด้วย synthetic FCPXML/WAV ขนาดเล็กก่อนเสมอ (เร็วกว่าเปิด GUI)
2. import เข้า FCP จริงดูด้วยตา — คณิตศาสตร์ถูกไม่พอ
3. CI เป็น oracle, fix-forward, commit เล็ก ๆ พร้อมเทสต์
4. อย่าเดา FCPXML — ดู export จริงของผู้ใช้ก่อนแก้ (ทุกค่าคงที่มาจากข้อมูลจริง)
5. รายงานผลตามจริง — ถ้าทดสอบบนเครื่องผู้ใช้ไม่ได้ ให้บอกตรง ๆ

---

## 13. ไฟล์สำคัญที่ควรอ่านก่อน (เรียงลำดับ)

1. `studio/docs/knowledge/SUBTITLE-COVER.md` — เอกสารเดิมของ cover (ค่าคงที่ + gotcha ครบ)
2. `studio/Sources/GhostlyCover/{SubtitleCover,CoverBuilder}.swift` — cover ที่พอร์ตแล้ว
3. `studio/Sources/GhostlyDirector/{EditIntent,AutoEditPlanner,ThaiImportance}.swift` — เอนจินตัดต่อ
4. `studio/Sources/GhostlyFCPXML/FCPXMLWriter.swift` — เขียน FCPXML (multicam, caption, title)
5. `studio/Sources/GhostlyDetection/{AudioAligner,MediaAnalysis}.swift` — sync + decode
6. `studio/Sources/GhostlyCLI/main.swift` — คำสั่งทั้งหมด
7. `studio/dist/Ghostly790K-droplet.applescript` — แอปเมนู
8. `.github/workflows/studio-ci.yml` — build/แพ็ก/smoke
9. `studio/CHANGELOG.md` — ประวัติการเปลี่ยนแปลงทั้งหมด (อ่านย้อนได้ว่าแต่ละอย่างทำไม)
