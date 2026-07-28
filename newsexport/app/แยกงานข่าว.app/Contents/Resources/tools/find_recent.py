#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
หาไฟล์ไทม์ไลน์ที่ Final Cut Pro เพิ่งสร้างขึ้นมา

ทำไมต้องมีตัวนี้
----------------
เวลาสั่งให้ Final Cut Pro ส่งไทม์ไลน์ออกมา มันจะเปิดหน้าต่างถามที่เก็บไฟล์
ที่เก็บนั้นเปลี่ยนไปเรื่อย ๆ ตามที่ผู้ใช้เคยเลือกไว้ครั้งก่อน

แทนที่จะไปบังคับหน้าต่างนั้น ซึ่งพังง่าย
เราปล่อยให้มันเซฟตรงไหนก็ได้ แล้วค่อยตามหาไฟล์เอา

บทเรียนจากงานจริง
------------------
ห้องข่าวทำงานบนไดรฟ์เครือข่าย เช่น /Volumes/Media
ถ้าหาแค่ในโฟลเดอร์ส่วนตัวของผู้ใช้ จะหาไม่เจอเลย
และไดรฟ์เครือข่ายมักไม่ถูกจัดทำดัชนีค้นหา จึงพึ่งระบบค้นหาของ Mac ไม่ได้

ลำดับการหาจึงเป็นแบบนี้ เร็วก่อน ช้าทีหลัง
  1. โฟลเดอร์ที่ระบุมาให้โดยตรง เร็วที่สุด
  2. โฟลเดอร์ที่คนชอบเซฟกัน
  3. ไดรฟ์ทุกตัวที่ต่ออยู่ รวมไดรฟ์เครือข่าย
  4. ระบบค้นหาของ Mac เป็นตัวสำรองสุดท้าย
"""

import argparse
import os
import subprocess
import sys

SUFFIXES = (".fcpxmld", ".fcpxml")

# โฟลเดอร์ในบ้านของผู้ใช้ ที่คนมักเซฟลงไป
HOME_FOLDERS = ("Desktop", "Documents", "Movies", "Downloads")


def looks_like_timeline(name):
    return name.endswith(SUFFIXES)


def scan_folder(folder, max_depth):
    """ไล่ดูในโฟลเดอร์หนึ่ง ลึกไม่เกินที่กำหนด เพื่อไม่ให้ช้าเกินไป"""
    found = []
    if not os.path.isdir(folder):
        return found
    base_depth = folder.rstrip("/").count("/")
    try:
        walker = os.walk(folder, onerror=lambda e: None)
        for current, dirnames, filenames in walker:
            # ข้ามโฟลเดอร์ที่ไม่มีทางมีไฟล์ไทม์ไลน์ และใหญ่มาก
            dirnames[:] = [d for d in dirnames
                           if not d.startswith(".")
                           and not d.endswith((".fcpbundle", ".photoslibrary", ".app"))]
            # ถึงชั้นลึกสุดแล้ว ให้หยุดเดินลงต่อ
            # แต่ยังต้องดูไฟล์ในชั้นนี้ให้ครบก่อน ไม่งั้นไฟล์ชั้นล่างสุดจะถูกมองข้าม
            if current.count("/") - base_depth >= max_depth:
                dirnames[:] = []
            for name in list(dirnames):
                if name.endswith(".fcpxmld"):
                    found.append(os.path.join(current, name))
                    dirnames.remove(name)
            for name in filenames:
                if name.endswith(".fcpxml"):
                    found.append(os.path.join(current, name))
    except OSError:
        pass
    return found


def mounted_volumes():
    """ไดรฟ์ทุกตัวที่ต่ออยู่ รวมไดรฟ์เครือข่ายของห้องข่าว"""
    try:
        return [os.path.join("/Volumes", name) for name in os.listdir("/Volumes")]
    except OSError:
        return []


def spotlight_candidates():
    """ถามระบบค้นหาของ Mac ใช้เป็นตัวสำรอง เพราะไดรฟ์เครือข่ายมักไม่มีดัชนี"""
    query = " || ".join('kMDItemFSName == "*%s"' % s for s in SUFFIXES)
    try:
        output = subprocess.run(["mdfind", query], capture_output=True,
                                text=True, timeout=8)
    except (OSError, subprocess.SubprocessError):
        return []
    return [line for line in output.stdout.splitlines() if line.strip()]


def modified_at(path):
    """
    เวลาที่แก้ไขล่าสุด
    ถ้าเป็นกล่อง .fcpxmld ต้องดูไฟล์ข้างในด้วย
    เพราะเวลาของตัวกล่องบางทีไม่อัปเดตตาม
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


def search_rounds(home, extra_folders):
    """คืนกลุ่มที่ต้องค้น เรียงจากเร็วไปช้า"""
    yield [(folder, 2) for folder in extra_folders]
    yield [(os.path.join(home, name), 3) for name in HOME_FOLDERS]
    yield [(volume, 4) for volume in mounted_volumes()]


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="หาไฟล์ไทม์ไลน์ที่เพิ่งถูกสร้างขึ้นใหม่")
    parser.add_argument("marker", help="ไฟล์เครื่องหมายเวลา เอาไว้เทียบว่าอะไรใหม่กว่า")
    parser.add_argument("folders", nargs="*", help="โฟลเดอร์ที่ให้หาก่อนเป็นอันดับแรก")
    parser.add_argument("--explain", action="store_true",
                        help="บอกด้วยว่าไปหามาจากที่ไหนบ้าง สำหรับดูเวลามีปัญหา")
    args = parser.parse_args(argv)

    try:
        since = os.path.getmtime(args.marker)
    except OSError:
        print("ไม่พบไฟล์เครื่องหมายเวลา: %s" % args.marker, file=sys.stderr)
        return 2

    home = os.path.expanduser("~")

    def newest_among(paths):
        best_path, best_time = None, since
        for path in paths:
            when = modified_at(path)
            if when is None or when <= best_time:
                continue
            best_path, best_time = path, when
        return best_path

    # ค้นทีละรอบ เจอตั้งแต่รอบแรกก็จบเลย จะได้ไม่ต้องไปกวาดไดรฟ์ใหญ่ ๆ
    for round_number, targets in enumerate(search_rounds(home, args.folders), start=1):
        candidates = []
        for folder, depth in targets:
            candidates += scan_folder(folder, depth)
        winner = newest_among(candidates)
        if args.explain:
            print("รอบที่ %d ค้น %d ที่ พบผู้สมัคร %d ไฟล์"
                  % (round_number, len(targets), len(candidates)), file=sys.stderr)
        if winner:
            print(winner)
            return 0

    winner = newest_among(spotlight_candidates())
    if winner:
        print(winner)
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
