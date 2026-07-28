#!/bin/bash
# ============================================================
# ตัวตรวจสอบเครื่อง Mac สำหรับโปรเจกต์ FCPX News Export
# ------------------------------------------------------------
# สคริปต์นี้ "อ่านอย่างเดียว" เท่านั้น
# ไม่แก้ไฟล์ ไม่ลบไฟล์ ไม่ติดตั้งอะไร ไม่ต่อเน็ต
# หน้าที่เดียวคือดูว่าในเครื่องมีเครื่องมืออะไรอยู่แล้วบ้าง
# ============================================================

echo "============================================"
echo "  รายงานเครื่องของคุณ"
echo "============================================"
echo

# ---------- ข้อมูลเครื่อง ----------
echo "[ 1 ] เครื่องและระบบ"
echo "  macOS: $(sw_vers -productVersion 2>/dev/null)"
echo "  ชนิดชิป: $(uname -m 2>/dev/null)"
echo

# ---------- โปรแกรมตระกูล Apple Pro ----------
echo "[ 2 ] โปรแกรมตัดต่อที่ติดตั้งอยู่"

# อ่านเลขเวอร์ชันจากตัวโปรแกรม
app_version() {
    /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
        "$1/Contents/Info.plist" 2>/dev/null
}

for app_name in "Final Cut Pro" "Compressor" "Motion"; do
    app_path="/Applications/$app_name.app"
    if [ -d "$app_path" ]; then
        version="$(app_version "$app_path")"
        echo "  ✅ มี  $app_name  (เวอร์ชัน ${version:-ไม่ทราบ})"
    else
        echo "  ❌ ไม่มี  $app_name"
    fi
done
echo

# ---------- ค่าตั้ง Export ที่ผู้ใช้มีอยู่แล้ว ----------
echo "[ 3 ] ค่าตั้ง Export ที่มีอยู่ในเครื่อง"

# 3.1 ปลายทาง Export ที่ตั้งไว้ใน Final Cut Pro
dest_dir="$HOME/Library/Application Support/ProApps/Share Destinations"
echo
echo "  --- ปลายทาง Export ใน Final Cut Pro (เมนู Share) ---"
if [ -d "$dest_dir" ]; then
    found=0
    while IFS= read -r file; do
        echo "     • $(basename "$file")"
        found=1
    done < <(find "$dest_dir" -maxdepth 1 -type f ! -name ".*" 2>/dev/null | sort)
    [ "$found" -eq 0 ] && echo "     (ไม่พบ)"
else
    echo "     (ไม่พบโฟลเดอร์นี้)"
fi

# 3.2 ค่าตั้งของ Compressor
setting_dir="$HOME/Library/Application Support/Compressor/Settings"
echo
echo "  --- ค่าตั้งของ Compressor ---"
if [ -d "$setting_dir" ]; then
    found=0
    while IFS= read -r file; do
        echo "     • $(basename "$file")"
        found=1
    done < <(find "$setting_dir" -maxdepth 1 -name "*.cmprstng" 2>/dev/null | sort)
    [ "$found" -eq 0 ] && echo "     (ไม่พบ)"
else
    echo "     (ไม่พบโฟลเดอร์นี้)"
fi
echo

# ---------- เครื่องมือแปลงไฟล์ที่มีในเครื่อง ----------
echo "[ 4 ] เครื่องมือแปลงไฟล์"

check_tool() {
    # $1 = ชื่อคำสั่ง, $2 = คำอธิบายภาษาไทย
    path="$(command -v "$1" 2>/dev/null)"
    if [ -n "$path" ]; then
        echo "  ✅ มี  $1  ($2)"
        echo "        ที่อยู่: $path"
    else
        echo "  ❌ ไม่มี  $1  ($2)"
    fi
}

check_tool avconvert "ตัวแปลงไฟล์ที่ติดมากับ macOS"
check_tool ffmpeg    "ตัวแปลงไฟล์ฟรี ต้องติดตั้งเอง"
check_tool ffprobe   "ตัวอ่านข้อมูลไฟล์วิดีโอ"

# คำสั่งของ Compressor สำหรับสั่งงานอัตโนมัติ
compressor_cli="/Applications/Compressor.app/Contents/MacOS/Compressor"
if [ -x "$compressor_cli" ]; then
    echo "  ✅ มี  ตัวสั่งงาน Compressor อัตโนมัติ"
else
    echo "  ❌ ไม่มี  ตัวสั่งงาน Compressor อัตโนมัติ"
fi
echo

# ---------- พื้นที่ว่าง ----------
echo "[ 5 ] พื้นที่ว่างในดิสก์"
df -h / 2>/dev/null | awk 'NR==2 {print "  ดิสก์หลัก: ว่าง " $4 " จากทั้งหมด " $2}'
echo

echo "============================================"
echo "  ตรวจเสร็จแล้ว"
echo "  กรุณาคัดลอกข้อความทั้งหมดนี้ส่งกลับมา"
echo "============================================"
