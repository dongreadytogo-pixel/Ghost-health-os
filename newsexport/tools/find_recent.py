#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
หาไฟล์ไทม์ไลน์ที่ Final Cut Pro เพิ่งสร้างขึ้นมา

ทำไมต้องมีตัวนี้
----------------
เวลาสั่งให้ Final Cut Pro ส่งไทม์ไลน์ออกมา มันจะเปิดหน้าต่างถามที่เก็บไฟล์
ซึ่งที่เก็บนั้นเปลี่ยนไปเรื่อย ๆ ตามที่ผู้ใช้เคยเลือกไว้ครั้งก่อน

แทนที่จะไปบังคับหน้าต่างนั้น ซึ่งพังง่าย
เราปล่อยให้มันเซฟตรงไหนก็ได้ แล้วค่อยมาตามหาไฟล์เอา
วิธีนี้ทนทานกว่ามาก เพราะไม่ต้องพึ่งการกดปุ่มแทนผู้ใช้

วิธีหา
------
1. ถามระบบค้นหาของ Mac ก่อน เพราะเร็วที่สุด
2. ถ้าไม่ได้ผล ค่อยไล่ดูโฟลเดอร์ที่คนชอบเซฟกัน

แล้วเอาเฉพาะไฟล์ที่ใหม่กว่าเวลาที่เริ่มสั่งงาน
จะได้ไม่ไปหยิบไฟล์เก่าของเมื่อวานมาใช้
"""

import argparse
import os
import subprocess
import sys

# นามสกุลของไฟล์ไทม์ไลน์ที่ Final Cut Pro ส่งออกมา
# .fcpxmld คือแบบใหม่ ซึ่งจริง ๆ เป็นโฟลเดอร์
SUFFIXES = (".fcpxmld", ".fcpxml")

# โฟลเดอร์ที่คนมักเซฟไฟล์ลงไป เรียงตามความน่าจะเป็น
COMMON_FOLDERS = ("Desktop", "Documents", "Movies", "Downloads")


def spotlight_candidates(home):
    """ถามระบบค้นหาของ Mac ว่ามีไฟล์ไทม์ไลน์อยู่ที่ไหนบ้าง"""
    query = " || ".join('kMDItemFSName == "*%s"' % s for s in SUFFIXES)
    try:
        output = subprocess.run(
            ["mdfind", "-onlyin", home, query],
            capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return []
    return [line for line in output.stdout.splitlines() if line.strip()]


def walk_candidates(home, extra_folders, max_depth=3):
    """ไล่ดูโฟลเดอร์ยอดนิยมเอง เผื่อระบบค้นหาใช้ไม่ได้"""
    found = []
    roots = [os.path.join(home, name) for name in COMMON_FOLDERS]
    roots += list(extra_folders)
    for root in roots:
        if not os.path.isdir(root):
            continue
        base_depth = root.rstrip("/").count("/")
        for current, dirnames, filenames in os.walk(root):
            if current.count("/") - base_depth >= max_depth:
                dirnames[:] = []
                continue
            for name in list(dirnames):
                if name.endswith(".fcpxmld"):
                    found.append(os.path.join(current, name))
                    dirnames.remove(name)   # ไม่ต้องเดินเข้าไปข้างใน
            for name in filenames:
                if name.endswith(".fcpxml"):
                    found.append(os.path.join(current, name))
    return found


def modified_at(path):
    """
    เวลาที่แก้ไขล่าสุด
    ถ้าเป็นกล่อง .fcpxmld ให้ดูไฟล์ข้างในด้วย
    เพราะเวลาของตัวโฟลเดอร์บางทีไม่อัปเดตตาม
    """
    try:
        newest = os.path.getmtime(path)
    except OSError:
        return None
    inner = os.path.join(path, "Info.fcpxml")
    if os.path.isfile(inner):
        try:
            newest = max(newest, os.path.getmtime(inner))
        except OSError:
            pass
    return newest


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="หาไฟล์ไทม์ไลน์ที่เพิ่งถูกสร้างขึ้นใหม่")
    parser.add_argument("marker", help="ไฟล์เครื่องหมายเวลา เอาไว้เทียบว่าอะไรใหม่กว่า")
    parser.add_argument("folders", nargs="*", help="โฟลเดอร์เพิ่มเติมที่อยากให้หาด้วย")
    args = parser.parse_args(argv)

    try:
        since = os.path.getmtime(args.marker)
    except OSError:
        print("ไม่พบไฟล์เครื่องหมายเวลา: %s" % args.marker, file=sys.stderr)
        return 2

    home = os.path.expanduser("~")
    candidates = list(args.folders)
    seen = set()
    newest_path, newest_time = None, since

    for path in spotlight_candidates(home) + walk_candidates(home, args.folders):
        if path in seen:
            continue
        seen.add(path)
        when = modified_at(path)
        if when is None or when <= newest_time:
            continue
        newest_path, newest_time = path, when

    if newest_path is None:
        return 1
    print(newest_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
