#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
อ่าน และ จำ ค่าตั้งของ Final Cut Pro ที่เกี่ยวกับ Roles

ทำไมต้องมีตัวนี้
----------------
ช่อง Roles as ในหน้าต่าง MXF-50 เป็นปุ่มบนหน้าจอของ Final Cut Pro
เราพยายามสั่งให้เครื่องกดปุ่มนั้นแทนคนมาหลายวิธีแล้วยังไม่สำเร็จ
เพราะ Final Cut Pro ไม่ได้เปิดทางให้โปรแกรมอื่นเข้าถึงปุ่มนั้นตรง ๆ

แต่ค่าที่ตั้งไว้ไม่ได้อยู่แค่บนหน้าจอ มันถูกบันทึกเป็นไฟล์จริงในเครื่อง
สังเกตได้จากในเมนูของช่องนั้นมีคำสั่ง Reveal User Presets in Finder
ซึ่งแปลว่ากดแล้วมันเปิด Finder ไปที่ไฟล์ preset ได้

ตัวนี้จึงทำสามอย่าง
1. สำรวจ  บอกว่าในเครื่องมีไฟล์ตั้งค่าอะไรบ้าง อยู่ที่ไหน ข้างในเขียนว่าอะไร
2. จำ     ถ่ายสำเนาไฟล์ตั้งค่าทั้งชุดเก็บไว้ ตอนที่ค่ายังถูกต้องอยู่
3. คืนค่า เอาสำเนาที่จำไว้ใส่กลับ เมื่อค่าถูกเปลี่ยนไป

ข้อดีของวิธี จำ แล้ว คืนค่า
--------------------------
เราไม่ต้องรู้เลยว่าข้างในไฟล์เขียนอะไรไว้ตรงไหน
ขอแค่ผู้ใช้ตั้ง 3 Stereo ด้วยมือให้ถูกหนึ่งครั้ง แล้วสั่งให้โปรแกรมจำ
หลังจากนั้นโปรแกรมคืนค่าชุดเดิมกลับได้เสมอ ไม่ว่าจะผ่านไปกี่เดือน
เป็นการคัดลอกไฟล์ธรรมดา จึงแม่นยำ 100 เปอร์เซ็นต์

ข้อควรระวังที่ต้องบอกตรง ๆ
--------------------------
Final Cut Pro อ่านไฟล์เหล่านี้ตอนเปิดโปรแกรม และเขียนทับตอนปิดโปรแกรม
การคืนค่าจึงต้องทำตอน Final Cut Pro ปิดอยู่ ไม่อย่างนั้นจะถูกเขียนทับ
โปรแกรมนี้จะไม่ยอมคืนค่าให้ ถ้า Final Cut Pro ยังเปิดอยู่
"""

import argparse
import os
import plistlib
import shutil
import subprocess
import sys
import time

# โฟลเดอร์ที่ Final Cut Pro เก็บค่าตั้งของ Share และ Roles
# ใส่ไว้หลายที่เพราะแต่ละรุ่นของ macOS เก็บไม่เหมือนกัน
# ตัวไหนไม่มีอยู่จริงก็จะถูกข้ามไปเอง
SETTING_ROOTS = (
    "~/Library/Application Support/ProApps",
    "~/Library/Containers/com.apple.FinalCut/Data/Library/Application Support/ProApps",
    "~/Library/Containers/com.apple.FinalCut/Data/Library/Preferences",
)

# คำที่บอกว่าไฟล์นี้น่าจะเกี่ยวกับ Roles
INTERESTING_WORDS = ("role", "stereo", "dialogue", "destination", "preset", "share")

# ที่เก็บสำเนาที่โปรแกรมจำไว้
SNAPSHOT_HOME = "~/Library/Application Support/GhostNewsExport/roles-snapshots"

# ขนาดไฟล์ที่ยอมอ่านเนื้อใน ไฟล์ตั้งค่าจริงเล็กมาก
# กันไว้ไม่ให้เผลอไปอ่านไฟล์วิดีโอที่ใหญ่เป็นกิกะไบต์
MAX_READ_BYTES = 2 * 1024 * 1024


def expand(path):
    return os.path.abspath(os.path.expanduser(path))


def existing_roots(extra=()):
    """คืนเฉพาะโฟลเดอร์ตั้งค่าที่มีอยู่จริงในเครื่องนี้"""
    roots = []
    for candidate in list(SETTING_ROOTS) + list(extra):
        full = expand(candidate)
        if os.path.isdir(full) and full not in roots:
            roots.append(full)
    return roots


def list_setting_files(roots, max_depth=6):
    """
    ไล่ดูไฟล์ทั้งหมดในโฟลเดอร์ตั้งค่า
    คืนค่าเป็นรายการของ (ที่อยู่เต็ม, ขนาด, เวลาที่แก้ล่าสุด)
    """
    results = []
    for root in roots:
        base_depth = root.rstrip("/").count("/")
        for current, dirnames, filenames in os.walk(root, onerror=lambda e: None):
            if current.count("/") - base_depth >= max_depth:
                dirnames[:] = []
            for name in sorted(filenames):
                if name.startswith("."):
                    continue
                path = os.path.join(current, name)
                try:
                    info = os.stat(path)
                except OSError:
                    continue
                results.append((path, info.st_size, info.st_mtime))
    results.sort(key=lambda row: row[0])
    return results


def looks_interesting(path):
    """
    ชื่อไฟล์หรือชื่อโฟลเดอร์ที่มันอยู่ บอกไหมว่าน่าจะเกี่ยวกับ Roles

    ดูแค่ชื่อไฟล์กับชื่อโฟลเดอร์ที่มันอยู่เท่านั้น ไม่ดูที่อยู่ทั้งเส้น
    เพราะถ้าบังเอิญมีโฟลเดอร์ชั้นบนชื่อมีคำว่า role อยู่ด้วย
    ไฟล์ทุกไฟล์ข้างในจะถูกนับว่าสำคัญไปหมด ซึ่งไม่จริง
    """
    name = os.path.basename(path).lower()
    parent = os.path.basename(os.path.dirname(path)).lower()
    return any(word in name or word in parent for word in INTERESTING_WORDS)


def read_plist(path):
    """
    อ่านไฟล์ตั้งค่าแบบ plist ซึ่งเป็นรูปแบบมาตรฐานของ macOS
    รองรับทั้งแบบข้อความและแบบไบนารี
    อ่านไม่ได้ก็คืน None ไม่ทำให้โปรแกรมพัง
    """
    try:
        if os.path.getsize(path) > MAX_READ_BYTES:
            return None
        with open(path, "rb") as handle:
            return plistlib.load(handle)
    except Exception:
        return None


def flatten(value, prefix=""):
    """
    แบนค่าที่ซ้อนกันหลายชั้นให้เหลือบรรทัดเดียวต่อหนึ่งค่า
    เช่น  destination / audio / rolesMode = 3 Stereo
    จะได้อ่านง่าย และค้นคำได้
    """
    lines = []
    if isinstance(value, dict):
        for key in value:
            lines.extend(flatten(value[key], prefix + "/" + str(key)))
    elif isinstance(value, (list, tuple)):
        for index, item in enumerate(value):
            lines.extend(flatten(item, prefix + "/" + str(index)))
    elif isinstance(value, bytes):
        lines.append((prefix, "ข้อมูลดิบ %d ไบต์" % len(value)))
    else:
        lines.append((prefix, str(value)))
    return lines


def describe_file(path, find=None):
    """
    อธิบายไฟล์ตั้งค่าหนึ่งไฟล์เป็นข้อความอ่านง่าย
    ถ้าใส่ find มาด้วย จะแสดงเฉพาะบรรทัดที่มีคำนั้น
    """
    lines = ["ไฟล์ %s" % path]
    data = read_plist(path)
    if data is None:
        lines.append("  อ่านเนื้อในไม่ได้ อาจไม่ใช่ไฟล์ตั้งค่าแบบ plist")
        return lines
    flat = flatten(data)
    if find:
        needle = find.lower()
        flat = [row for row in flat if needle in row[0].lower() or needle in row[1].lower()]
        if not flat:
            lines.append("  ไม่มีคำว่า %s ในไฟล์นี้" % find)
            return lines
    for key, value in flat:
        if len(value) > 200:
            value = value[:200] + " ..."
        lines.append("  %s = %s" % (key, value))
    return lines


def final_cut_is_running():
    """Final Cut Pro เปิดอยู่หรือเปล่า"""
    try:
        subprocess.check_output(["/usr/bin/pgrep", "-x", "Final Cut Pro"],
                                stderr=subprocess.DEVNULL)
        return True
    except Exception:
        return False


def snapshot_folder(name):
    return os.path.join(expand(SNAPSHOT_HOME), name)


def do_snapshot(name, roots):
    """
    ถ่ายสำเนาโฟลเดอร์ตั้งค่าทั้งชุดเก็บไว้ใต้ชื่อที่ตั้ง
    เก็บโครงสร้างเดิมไว้ จะได้คืนกลับที่เดิมได้ถูกต้อง
    """
    target = snapshot_folder(name)
    if os.path.exists(target):
        stamp = time.strftime("%Y%m%d-%H%M%S")
        shutil.move(target, target + "-เก่า-" + stamp)
    os.makedirs(target, exist_ok=True)

    copied = 0
    index_lines = []
    for number, root in enumerate(roots, start=1):
        slot = os.path.join(target, "root-%d" % number)
        try:
            shutil.copytree(root, slot, symlinks=True)
        except Exception as error:
            index_lines.append("ข้าม\t%s\t%s" % (root, error))
            continue
        index_lines.append("root-%d\t%s" % (number, root))
        for _, _, filenames in os.walk(slot):
            copied += len(filenames)

    with open(os.path.join(target, "ที่มาของไฟล์.txt"), "w", encoding="utf-8") as handle:
        handle.write("จำไว้เมื่อ %s\n" % time.strftime("%Y-%m-%d %H:%M:%S"))
        handle.write("\n".join(index_lines) + "\n")
    return copied


def read_snapshot_index(name):
    """อ่านว่าสำเนาชุดนี้มาจากโฟลเดอร์ไหนบ้าง"""
    target = snapshot_folder(name)
    index = os.path.join(target, "ที่มาของไฟล์.txt")
    pairs = []
    try:
        with open(index, encoding="utf-8") as handle:
            for line in handle:
                parts = line.rstrip("\n").split("\t")
                if len(parts) >= 2 and parts[0].startswith("root-"):
                    pairs.append((os.path.join(target, parts[0]), parts[1]))
    except OSError:
        return []
    return pairs


def do_restore(name, force=False):
    """
    เอาสำเนาที่จำไว้ใส่กลับที่เดิม
    ของเดิมไม่ได้ถูกลบทิ้ง แต่ถูกเปลี่ยนชื่อเก็บไว้ก่อน เผื่อต้องย้อนกลับ
    """
    if final_cut_is_running() and not force:
        return None, "Final Cut Pro ยังเปิดอยู่ ต้องปิดก่อนจึงจะคืนค่าได้"

    pairs = read_snapshot_index(name)
    if not pairs:
        return None, "ไม่พบสำเนาชื่อ %s" % name

    restored = 0
    stamp = time.strftime("%Y%m%d-%H%M%S")
    for slot, original in pairs:
        if not os.path.isdir(slot):
            continue
        try:
            if os.path.exists(original):
                shutil.move(original, original + "-ก่อนคืนค่า-" + stamp)
            os.makedirs(os.path.dirname(original), exist_ok=True)
            shutil.copytree(slot, original, symlinks=True)
            restored += 1
        except Exception as error:
            return None, "คืนค่าไม่สำเร็จที่ %s %s" % (original, error)
    return restored, "คืนค่าแล้ว %d โฟลเดอร์" % restored


def list_snapshots():
    home = expand(SNAPSHOT_HOME)
    if not os.path.isdir(home):
        return []
    names = []
    for name in sorted(os.listdir(home)):
        if name.startswith("."):
            continue
        if os.path.isdir(os.path.join(home, name)):
            names.append(name)
    return names


def build_report(roots, find=None):
    """สร้างรายงานสำรวจทั้งเครื่อง เป็นข้อความภาษาไทยอ่านง่าย"""
    lines = []
    lines.append("รายงานค่าตั้งของ Final Cut Pro ที่เกี่ยวกับ Roles")
    lines.append("ทำเมื่อ %s" % time.strftime("%Y-%m-%d %H:%M:%S"))
    lines.append("")

    if not roots:
        lines.append("ไม่พบโฟลเดอร์ตั้งค่าเลย แปลว่าเครื่องนี้อาจยังไม่เคยบันทึก preset")
        return lines

    lines.append("โฟลเดอร์ตั้งค่าที่พบ")
    for root in roots:
        lines.append("  " + root)
    lines.append("")

    files = list_setting_files(roots)
    lines.append("ไฟล์ทั้งหมด %d ไฟล์" % len(files))
    for path, size, mtime in files:
        mark = "  * " if looks_interesting(path) else "    "
        lines.append("%s%s   %d ไบต์   แก้ล่าสุด %s"
                     % (mark, path, size, time.strftime("%Y-%m-%d %H:%M", time.localtime(mtime))))
    lines.append("")
    lines.append("เครื่องหมาย * คือไฟล์ที่ชื่อบอกว่าน่าจะเกี่ยวกับ Roles")
    lines.append("")

    for path, _, _ in files:
        if not looks_interesting(path):
            continue
        lines.extend(describe_file(path, find))
        lines.append("")
    return lines


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="อ่าน จำ และคืนค่าตั้ง Roles ของ Final Cut Pro")
    parser.add_argument("command",
                        choices=["report", "snapshot", "restore", "snapshots", "roots"],
                        help="report สำรวจ  snapshot จำ  restore คืนค่า  snapshots ดูรายชื่อที่จำไว้")
    parser.add_argument("name", nargs="?", default="ค่ามาตรฐาน",
                        help="ชื่อของชุดที่จำไว้")
    parser.add_argument("--find", default=None, help="แสดงเฉพาะบรรทัดที่มีคำนี้")
    parser.add_argument("--also-look-in", action="append", default=[],
                        help="โฟลเดอร์ตั้งค่าเพิ่มเติม")
    parser.add_argument("--force", action="store_true",
                        help="คืนค่าแม้ Final Cut Pro จะเปิดอยู่ ไม่แนะนำ")
    parser.add_argument("--out", default=None, help="เขียนรายงานลงไฟล์นี้แทนการพิมพ์")
    args = parser.parse_args(argv)

    roots = existing_roots(args.also_look_in)

    if args.command == "roots":
        for root in roots:
            print(root)
        return 0

    if args.command == "report":
        lines = build_report(roots, args.find)
        text = "\n".join(lines) + "\n"
        if args.out:
            with open(args.out, "w", encoding="utf-8") as handle:
                handle.write(text)
            print(args.out)
        else:
            sys.stdout.write(text)
        return 0

    if args.command == "snapshots":
        for name in list_snapshots():
            print(name)
        return 0

    if args.command == "snapshot":
        if not roots:
            print("ไม่พบโฟลเดอร์ตั้งค่า จึงยังจำอะไรไม่ได้", file=sys.stderr)
            return 1
        copied = do_snapshot(args.name, roots)
        print(copied)
        return 0

    if args.command == "restore":
        count, message = do_restore(args.name, args.force)
        # ถ้าไม่สำเร็จต้องพิมพ์ลงช่องข้อผิดพลาด
        # เพราะฝั่งแอปอ่านข้อความจากช่องนั้นไปแสดงให้ผู้ใช้เห็น
        if count is None:
            print(message, file=sys.stderr)
            return 1
        print(message)
        return 0

    return 2


if __name__ == "__main__":
    sys.exit(main())
