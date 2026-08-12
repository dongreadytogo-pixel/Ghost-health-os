#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ตามเก็บไฟล์ที่ Final Cut Pro สร้างไว้ แล้วย้ายมาไว้ในโฟลเดอร์ที่ผู้ใช้เลือก

ทำไมต้องมีตัวนี้
----------------
หน้าต่างเซฟของ Final Cut Pro บังคับให้ไปโฟลเดอร์ที่ต้องการไม่ได้จริง
ลองมาหลายวิธีแล้วไม่สำเร็จ ไฟล์จึงไปตกอยู่ที่เดิมที่โปรแกรมจำไว้
ซึ่งเคยไปโผล่ทั้งในโฟลเดอร์ F และในโฟลเดอร์ Applications

แทนที่จะฝืนบังคับหน้าต่างนั้นต่อไป
เราปล่อยให้มันเซฟตรงไหนก็ได้ แล้วค่อยตามไปเก็บมาไว้ที่ถูกต้อง
วิธีนี้ควบคุมได้ 100 เปอร์เซ็นต์ เพราะเป็นการย้ายไฟล์ธรรมดา
ไม่ต้องพึ่งการกดปุ่มใด ๆ อีกเลย

ความปลอดภัย
-----------
ย้ายเฉพาะไฟล์ที่ชื่อตรงกับรายชื่อที่โปรแกรมคำนวณไว้เท่านั้น
ไฟล์อื่นของผู้ใช้จะไม่ถูกแตะ
และถ้าปลายทางมีไฟล์ชื่อเดียวกันอยู่แล้ว จะไม่เขียนทับ
"""

import argparse
import os
import shutil
import subprocess
import sys
import time

# ที่ที่ Final Cut Pro ชอบเซฟไฟล์ไปไว้ เรียงตามที่เคยเจอจริง
LIKELY_FOLDERS = ("/Applications", "~/Desktop", "~/Documents", "~/Movies", "~/Downloads")


def candidate_folders(extra):
    folders = [os.path.expanduser(f) for f in LIKELY_FOLDERS]
    folders += list(extra)
    try:
        folders += [os.path.join("/Volumes", name) for name in os.listdir("/Volumes")]
    except OSError:
        pass
    return folders


def find_named_files(wanted, folders, max_depth=3):
    """
    หาไฟล์ตามรายชื่อที่ต้องการ ในโฟลเดอร์ที่น่าจะอยู่
    คืนค่าเป็น แผนที่ ชื่อไฟล์ ไปยัง ที่อยู่จริง
    """
    remaining = set(wanted)
    found = {}
    for folder in folders:
        if not remaining:
            break
        if not os.path.isdir(folder):
            continue
        base_depth = folder.rstrip("/").count("/")
        try:
            for current, dirnames, filenames in os.walk(folder, onerror=lambda e: None):
                dirnames[:] = [d for d in dirnames
                               if not d.startswith(".")
                               and not d.endswith((".fcpbundle", ".photoslibrary",
                                                   ".app", ".framework"))]
                if current.count("/") - base_depth >= max_depth:
                    dirnames[:] = []
                for name in filenames:
                    if name in remaining:
                        found[name] = os.path.join(current, name)
                        remaining.discard(name)
                if not remaining:
                    break
        except OSError:
            continue
    return found


def is_settled(path, settle_seconds=2.0):
    """ไฟล์เขียนเสร็จแล้วหรือยัง ดูจากขนาดที่หยุดโตแล้ว"""
    try:
        first = os.path.getsize(path)
    except OSError:
        return False
    time.sleep(settle_seconds)
    try:
        return first == os.path.getsize(path) and first > 0
    except OSError:
        return False


def move_into(source, target_folder):
    """
    ย้ายไฟล์เข้าโฟลเดอร์ปลายทาง
    ถ้าอยู่ที่นั่นอยู่แล้วก็ไม่ต้องทำอะไร
    ถ้ามีไฟล์ชื่อซ้ำอยู่แล้ว จะไม่เขียนทับ แต่เติมเลขต่อท้ายแทน
    """
    name = os.path.basename(source)
    destination = os.path.join(target_folder, name)
    if os.path.abspath(source) == os.path.abspath(destination):
        return destination, "อยู่ที่ถูกต้องแล้ว"

    if os.path.exists(destination):
        stem, extension = os.path.splitext(name)
        counter = 2
        while os.path.exists(os.path.join(target_folder,
                                          "%s (%d)%s" % (stem, counter, extension))):
            counter += 1
        destination = os.path.join(target_folder,
                                   "%s (%d)%s" % (stem, counter, extension))

    try:
        shutil.move(source, destination)
        return destination, "ย้ายแล้ว"
    except OSError as error:
        return None, "ย้ายไม่สำเร็จ %s" % error


# นามสกุลของไฟล์ที่ Final Cut Pro สร้างออกมา
OUTPUT_EXTENSIONS = (".mov", ".mxf", ".mp4", ".m4v")


def survey_recent(folders, minutes=60, max_depth=3, limit=40):
    """
    สำรวจว่ามีไฟล์วิดีโอไหนถูกสร้างขึ้นใหม่บ้างในช่วงที่ผ่านมา

    ทำไมต้องมีตัวนี้
    ----------------
    เวลาผลออกมาเป็นศูนย์ไฟล์ คำถามแรกคือ
    Final Cut Pro ไม่ยอมเอ็กพอร์ตเลย หรือเอ็กพอร์ตแล้วแต่เราหาไม่เจอ
    สองอย่างนี้แก้คนละแบบกันสิ้นเชิง แต่เดาจากข้างนอกไม่ได้

    ตัวนี้ตอบคำถามนั้นตรง ๆ โดยไม่สนใจว่าชื่อไฟล์จะตรงกับที่เราคำนวณไว้ไหม
    ถ้าเจอไฟล์ใหม่ แปลว่าเครื่องทำงาน แต่ชื่อหรือที่อยู่ไม่ตรงกับที่เราคาด
    ถ้าไม่เจอเลย แปลว่าคำสั่งเอ็กพอร์ตไม่ได้ถูกส่งไปจริง

    คืนค่าเป็นรายการของ (ที่อยู่ไฟล์, ขนาด, อายุเป็นนาที) เรียงใหม่สุดก่อน
    """
    cutoff = time.time() - minutes * 60
    found = []
    seen = set()
    for folder in folders:
        if not os.path.isdir(folder):
            continue
        base_depth = folder.rstrip("/").count("/")
        try:
            for current, dirnames, filenames in os.walk(folder, onerror=lambda e: None):
                dirnames[:] = [d for d in dirnames
                               if not d.startswith(".")
                               and not d.endswith((".fcpbundle", ".photoslibrary",
                                                   ".app", ".framework"))]
                if current.count("/") - base_depth >= max_depth:
                    dirnames[:] = []
                for name in filenames:
                    if not name.lower().endswith(OUTPUT_EXTENSIONS):
                        continue
                    path = os.path.join(current, name)
                    real = os.path.realpath(path)
                    if real in seen:
                        continue
                    try:
                        info = os.stat(path)
                    except OSError:
                        continue
                    if info.st_mtime < cutoff:
                        continue
                    seen.add(real)
                    found.append((path, info.st_size,
                                  int((time.time() - info.st_mtime) / 60)))
        except OSError:
            continue
    found.sort(key=lambda row: row[2])
    return found[:limit]


def format_survey(rows):
    """เขียนผลสำรวจเป็นข้อความไทยอ่านง่าย"""
    if not rows:
        return ["ไม่พบไฟล์วิดีโอที่สร้างใหม่เลยในช่วงที่ผ่านมา",
                "แปลว่า Final Cut Pro ยังไม่ได้สร้างไฟล์ไหนออกมาจริง ๆ",
                "ปัญหาจึงอยู่ที่ขั้นสั่งเอ็กพอร์ต ไม่ใช่ขั้นตามเก็บไฟล์"]
    lines = ["พบไฟล์วิดีโอที่สร้างใหม่ %d ไฟล์" % len(rows),
             "แปลว่า Final Cut Pro ทำงานจริง แต่ชื่อหรือที่อยู่ไม่ตรงกับที่เราคาดไว้"]
    for path, size, age in rows:
        lines.append("  %s   %.1f MB   สร้างเมื่อ %d นาทีที่แล้ว"
                     % (path, size / 1024.0 / 1024.0, age))
    return lines


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="ตามเก็บไฟล์ที่เอ็กพอร์ตแล้ว มาไว้ในโฟลเดอร์ที่ต้องการ")
    parser.add_argument("target", help="โฟลเดอร์ปลายทางที่ผู้ใช้เลือกไว้")
    parser.add_argument("namesfile", help="ไฟล์รายชื่อ บรรทัดละหนึ่งชื่อ")
    parser.add_argument("--also-look-in", action="append", default=[],
                        help="โฟลเดอร์เพิ่มเติมที่ให้ไปหาด้วย")
    parser.add_argument("--settle", type=float, default=2.0,
                        help="รอกี่วินาทีเพื่อดูว่าไฟล์เขียนเสร็จแล้ว")
    parser.add_argument("--survey", type=int, default=None, metavar="นาที",
                        help="สำรวจว่ามีไฟล์วิดีโอใหม่ถูกสร้างในกี่นาทีที่ผ่านมา")
    args = parser.parse_args(argv)

    try:
        with open(args.namesfile, encoding="utf-8") as handle:
            wanted = [line.strip() for line in handle if line.strip()]
    except OSError as error:
        print("อ่านรายชื่อไฟล์ไม่ได้: %s" % error, file=sys.stderr)
        return 2

    if not os.path.isdir(args.target):
        print("ไม่พบโฟลเดอร์ปลายทาง: %s" % args.target, file=sys.stderr)
        return 2

    folders = candidate_folders(args.also_look_in + [args.target])

    # โหมดสำรวจ ใช้ตอนผลออกมาเป็นศูนย์ไฟล์ เพื่อแยกว่าปัญหาอยู่ตรงไหน
    if args.survey is not None:
        print("\n".join(format_survey(survey_recent(folders, args.survey))))
        return 0

    found = find_named_files(wanted, folders)

    moved = 0
    waiting = 0
    for name in wanted:
        path = found.get(name)
        if path is None:
            continue
        if not is_settled(path, args.settle):
            waiting += 1
            continue
        destination, note = move_into(path, args.target)
        if destination is not None:
            moved += 1

    print(moved)                    # ย้ายมาแล้วกี่ไฟล์
    print(waiting)                  # ยังเขียนไม่เสร็จกี่ไฟล์
    print(len(wanted) - len(found))  # ยังไม่เจอเลยกี่ไฟล์
    return 0


if __name__ == "__main__":
    sys.exit(main())
