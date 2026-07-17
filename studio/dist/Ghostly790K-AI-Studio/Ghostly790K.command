#!/bin/bash
# Ghostly790K AI Final Cut Studio — โปรแกรมตัดต่อคลิกเดียวจบ
# ดับเบิลคลิกไฟล์นี้ → เลือกวิดีโอ → พิมพ์คำสั่ง (ภาษาไทยได้) → ได้ .fcpxml
# ที่เปิดใน Final Cut Pro ได้ทันที ฟุตเทจออนไลน์ ไม่ต้อง relink
# ไม่ต้องติดตั้งอะไรเพิ่ม: โปรแกรมแตกเสียงจากวิดีโอด้วยเอนจิน macOS เอง
set -u
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
cd "$(dirname "$0")"

# ปลดล็อกไฟล์ที่ดาวน์โหลดมา (ทำเองอัตโนมัติ ไม่ต้องรันตัวติดตั้งก่อน)
xattr -dr com.apple.quarantine . 2>/dev/null || true
chmod +x bin/ghostly ./*.command 2>/dev/null || true

BIN="./bin/ghostly"
if [ ! -x "$BIN" ] || ! "$BIN" version >/dev/null 2>&1; then
    osascript -e 'display dialog "ตัวโปรแกรมยังใช้กับเครื่องนี้ไม่ได้ — ดับเบิลคลิก \"ติดตั้งครั้งแรก.command\" หนึ่งครั้ง เดี๋ยวมันจัดการให้เองครับ" buttons {"ตกลง"} default button "ตกลง" with title "Ghostly790K"' >/dev/null 2>&1
    exit 1
fi

# 1) เลือกไฟล์วิดีโอ
VIDEO=$(osascript -e 'POSIX path of (choose file with prompt "เลือกไฟล์วิดีโอที่จะตัดต่อ")' 2>/dev/null) || exit 0
[ -z "$VIDEO" ] && exit 0

# 2) คำสั่งตัดต่อ (แก้ได้ในกล่องข้อความ)
DEFAULT_CMD="ตัดช่วงเงียบออก ใส่คำบรรยาย"
EDIT_CMD=$(osascript -e "text returned of (display dialog \"คำสั่งตัดต่อ (พิมพ์ภาษาไทยได้เลย เช่น ทำเป็นติ๊กต๊อก / ลดเสียงรบกวน)\" default answer \"$DEFAULT_CMD\" with title \"Ghostly790K\")" 2>/dev/null) || exit 0
[ -z "$EDIT_CMD" ] && EDIT_CMD="$DEFAULT_CMD"

# 3) ซับไทยอัตโนมัติ เมื่อมีโมเดล whisper วางไว้ในโฟลเดอร์ models/
MODEL_ARGS=()
MODEL=$(ls models/*.bin 2>/dev/null | head -1 || true)
if [ -n "$MODEL" ] && command -v whisper-cli >/dev/null 2>&1; then
    MODEL_ARGS=(--model "$MODEL")
fi

OUT="${VIDEO%.*}.fcpxml"
echo "== Ghostly790K: กำลังตัดต่อ =="
echo "วิดีโอ:  $VIDEO"
echo "คำสั่ง:  $EDIT_CMD"
if "$BIN" auto "$VIDEO" --command "$EDIT_CMD" --remember --out "$OUT" ${MODEL_ARGS[@]+"${MODEL_ARGS[@]}"}; then
    open -R "$OUT" 2>/dev/null || true
    RESP=$(osascript -e "button returned of (display dialog \"เสร็จแล้ว ✅  ได้ไฟล์:\n$OUT\n\nเปิดใน Final Cut Pro เลยไหม\" buttons {\"ไว้ก่อน\",\"เปิดเลย\"} default button \"เปิดเลย\" with title \"Ghostly790K\")" 2>/dev/null || true)
    if [ "${RESP:-}" = "เปิดเลย" ]; then open "$OUT"; fi
else
    osascript -e 'display dialog "มีข้อผิดพลาด — อ่านรายละเอียดในหน้าต่าง Terminal นี้ได้เลย" buttons {"ตกลง"} default button "ตกลง" with title "Ghostly790K"' >/dev/null 2>&1
    exit 1
fi
