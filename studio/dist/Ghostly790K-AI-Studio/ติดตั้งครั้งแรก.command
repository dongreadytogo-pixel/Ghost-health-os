#!/bin/bash
# ติดตั้ง Ghostly790K AI Final Cut Studio ครั้งแรก (รันครั้งเดียว)
# - ปลดล็อกไฟล์ที่ดาวน์โหลดมา (quarantine)
# - ติดตั้ง ffmpeg (ผ่าน Homebrew)
# - ถ้าไม่มีตัวโปรแกรมสำเร็จรูป จะ build จากซอร์สโค้ดให้อัตโนมัติ
set -u
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
cd "$(dirname "$0")"

echo "== Ghostly790K: ติดตั้งครั้งแรก =="

# 1) ปลดล็อก quarantine ให้ทุกไฟล์ในโฟลเดอร์นี้ (macOS ล็อกไฟล์ที่ดาวน์โหลดมา)
xattr -dr com.apple.quarantine . 2>/dev/null || true
chmod +x ./*.command bin/ghostly 2>/dev/null || true

# 2) ffmpeg — ตัวแตกเสียงจากวิดีโอ (จำเป็น)
if ! command -v ffmpeg >/dev/null 2>&1; then
    if command -v brew >/dev/null 2>&1; then
        echo "กำลังติดตั้ง ffmpeg ผ่าน Homebrew (รอสักครู่)..."
        brew install ffmpeg
    else
        echo "ยังไม่มี Homebrew — เปิดเว็บ https://brew.sh ให้แล้ว"
        echo "ติดตั้ง Homebrew ตามคำสั่งบรรทัดแรกในเว็บ เสร็จแล้วดับเบิลคลิกไฟล์นี้อีกครั้ง"
        open "https://brew.sh" 2>/dev/null || true
        osascript -e 'display dialog "ต้องติดตั้ง Homebrew ก่อน (เปิดเว็บ brew.sh ให้แล้ว)\nติดตั้งเสร็จแล้วดับเบิลคลิกไฟล์นี้อีกครั้งนะครับ" buttons {"ตกลง"} default button "ตกลง" with title "Ghostly790K"' >/dev/null 2>&1
        exit 1
    fi
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
