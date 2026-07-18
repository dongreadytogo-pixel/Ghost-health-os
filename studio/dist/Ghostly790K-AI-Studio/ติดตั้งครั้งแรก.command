#!/bin/bash
# ติดตั้ง Ghostly790K AI Final Cut Studio (ปกติ *ไม่ต้องรัน* —
# Ghostly790K.command จัดการตัวเองได้ ไฟล์นี้มีไว้กรณีตัวโปรแกรม
# สำเร็จรูปใช้กับเครื่องไม่ได้ เช่น Mac ชิป Intel จะ build ให้ใหม่)
# - ปลดล็อกไฟล์ที่ดาวน์โหลดมา (quarantine)
# - ถ้าไม่มีตัวโปรแกรมสำเร็จรูป จะ build จากซอร์สโค้ดให้อัตโนมัติ
# - ติดตั้ง ffmpeg เพิ่ม "ถ้ามี Homebrew อยู่แล้ว" (ทางเลือก — ไม่จำเป็น
#   เพราะโปรแกรมแตกเสียงด้วยเอนจิน macOS เองได้)
set -u
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
cd "$(dirname "$0")"

echo "== Ghostly790K: ติดตั้งครั้งแรก =="

# 1) ปลดล็อก quarantine ให้ทุกไฟล์ในโฟลเดอร์นี้ (macOS ล็อกไฟล์ที่ดาวน์โหลดมา)
xattr -dr com.apple.quarantine . 2>/dev/null || true
chmod +x ./*.command bin/ghostly 2>/dev/null || true

# 2) ffmpeg — ทางเลือกเสริมเท่านั้น (เอนจิน macOS แตกเสียงได้เองอยู่แล้ว)
if ! command -v ffmpeg >/dev/null 2>&1 && command -v brew >/dev/null 2>&1; then
    echo "กำลังติดตั้ง ffmpeg เสริมผ่าน Homebrew (ใช้เป็นตัวสำรอง)..."
    brew install ffmpeg || echo "ข้าม ffmpeg — โปรแกรมทำงานได้โดยไม่ต้องมี"
fi

# 2.5) ซับไทยอัตโนมัติ: whisper + โมเดลถอดเสียง (แนะนำมาก — ถ้าข้ามขั้นนี้
# โปรแกรมจะตัดต่อได้แต่ไม่มีซับ)
if ! command -v whisper-cli >/dev/null 2>&1; then
    if command -v brew >/dev/null 2>&1; then
        echo "กำลังติดตั้งตัวถอดเสียง whisper..."
        brew install whisper-cpp || echo "ติดตั้ง whisper ไม่สำเร็จ — ซับอัตโนมัติจะไม่ทำงาน"
    else
        echo "ไม่มี Homebrew — ข้ามการติดตั้ง whisper (ซับอัตโนมัติจะไม่ทำงาน)"
        echo "ติดตั้ง Homebrew จาก https://brew.sh แล้วรันไฟล์นี้อีกครั้งเพื่อเปิดใช้ซับ"
    fi
fi
mkdir -p models
if command -v whisper-cli >/dev/null 2>&1 && ! ls models/*.bin >/dev/null 2>&1; then
    echo "กำลังดาวน์โหลดโมเดลถอดเสียงไทย (~550MB — ใช้เวลาสักพัก ครั้งเดียวจบ)..."
    curl -L --fail --progress-bar -o "models/ggml-large-v3-turbo-q5_0.bin" \
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin" \
        || { rm -f "models/ggml-large-v3-turbo-q5_0.bin"; echo "ดาวน์โหลดโมเดลไม่สำเร็จ — ลองรันไฟล์นี้อีกครั้งเมื่อเน็ตพร้อม"; }
fi

# 3) ตัวโปรแกรม ghostly — ใช้ตัวสำเร็จรูปใน bin/ ถ้ามี ไม่มีก็ build จากซอร์ส
if [ ! -x "bin/ghostly" ] || ! ./bin/ghostly version >/dev/null 2>&1; then
    echo "ตัวโปรแกรมสำเร็จรูปใช้ไม่ได้กับเครื่องนี้ — กำลัง build จากซอร์สโค้ด"
    if ! xcode-select -p >/dev/null 2>&1; then
        xcode-select --install 2>/dev/null || true
        echo "กด Install ในหน้าต่างที่เด้งขึ้นมา เสร็จแล้วดับเบิลคลิกไฟล์นี้อีกครั้ง"
        osascript -e 'display dialog "ต้องติดตั้ง Xcode Command Line Tools ก่อน (กด Install ในหน้าต่างที่เด้งขึ้นมา)\nเสร็จแล้วดับเบิลคลิกไฟล์นี้อีกครั้งนะครับ" buttons {"ตกลง"} default button "ตกลง" with title "Ghostly790K"' >/dev/null 2>&1
        exit 1
    fi
    SRC="../studio"
    if [ ! -d "$SRC" ]; then
        SRC="$HOME/Ghostly790K-src/studio"
        if [ ! -d "$SRC" ]; then
            echo "กำลังดาวน์โหลดซอร์สโค้ด..."
            git clone --branch claude/ghostly790k-ai-final-cut-4z7syw \
                https://github.com/dongreadytogo-pixel/Ghost-health-os.git "$HOME/Ghostly790K-src"
        fi
    fi
    echo "กำลัง build (ครั้งแรกใช้เวลา 2-5 นาที)..."
    (cd "$SRC" && swift build -c release --product ghostly)
    mkdir -p bin
    cp "$(cd "$SRC" && swift build -c release --show-bin-path)/ghostly" bin/
fi

echo
./bin/ghostly doctor || true
echo
echo "✅ ติดตั้งเสร็จแล้ว — ดับเบิลคลิก Ghostly790K.command เพื่อเริ่มตัดต่อ"
echo "   (อยากได้ซับไทยอัตโนมัติ: brew install whisper-cpp แล้ววางไฟล์โมเดล ggml*.bin ไว้ในโฟลเดอร์ models/)"
osascript -e 'display dialog "ติดตั้งเสร็จแล้ว ✅\nดับเบิลคลิก Ghostly790K.command เพื่อเริ่มตัดต่อได้เลยครับ" buttons {"ตกลง"} default button "ตกลง" with title "Ghostly790K"' >/dev/null 2>&1 || true
