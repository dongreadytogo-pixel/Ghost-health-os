#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ทดสอบตัวตามหาไฟล์ไทม์ไลน์

ทำไมต้องมีชุดนี้
-----------------
ปัญหาที่ผู้ใช้เจอซ้ำ ๆ คือ ตามหาไฟล์ไม่เจอ ทั้งที่เปิดโปรเจคไว้แล้ว
ทุกครั้งที่แก้ ต้องพิสูจน์ได้ว่าเคสที่เคยพลาด ตอนนี้ผ่านแล้วจริง
ไม่ใช่เชื่อเพราะโค้ดดูเข้าท่า
"""

import os
import sys
import tempfile
import time
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tools"))

import find_recent


def touch(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as handle:
        handle.write("<fcpxml/>")
    return path


def make_bundle(path):
    """สร้างกล่อง .fcpxmld แบบเดียวกับที่ Final Cut Pro สร้าง"""
    os.makedirs(path, exist_ok=True)
    with open(os.path.join(path, "Info.fcpxml"), "w") as handle:
        handle.write("<fcpxml/>")
    return path


class ScanFolderTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.mkdtemp(prefix="find-recent-")

    def test_เจอไฟล์ที่อยู่ชั้นบนสุด(self):
        touch(os.path.join(self.temp, "งาน.fcpxml"))
        found = find_recent.scan_folder(self.temp, 2)
        self.assertEqual(len(found), 1)

    def test_เจอกล่องfcpxmldและไม่เดินเข้าไปข้างใน(self):
        make_bundle(os.path.join(self.temp, "งาน.fcpxmld"))
        found = find_recent.scan_folder(self.temp, 3)
        self.assertEqual(len(found), 1)
        self.assertTrue(found[0].endswith(".fcpxmld"))

    def test_ความลึกสามชั้นเจอไฟล์ที่ซ้อนสามชั้น(self):
        # นี่คือเคสจริงของผู้ใช้ ปลายทางคือ /Volumes/Media/Dong/4.เช้า พฤ.
        # ถ้าจำกัดแค่สองชั้น ไฟล์ที่ซ้อนลึกกว่านั้นจะถูกมองข้าม
        deep = os.path.join(self.temp, "Media", "Dong", "4.เช้า พฤ.", "งาน.fcpxml")
        touch(deep)
        self.assertEqual(len(find_recent.scan_folder(self.temp, 2)), 0)
        self.assertEqual(len(find_recent.scan_folder(self.temp, 3)), 1)

    def test_ไม่เดินเข้าไปในไลบรารีของfinalcut(self):
        touch(os.path.join(self.temp, "งาน.fcpbundle", "ข้างใน.fcpxml"))
        self.assertEqual(find_recent.scan_folder(self.temp, 4), [])

    def test_โฟลเดอร์ที่ไม่มีอยู่จริงไม่ทำให้พัง(self):
        self.assertEqual(find_recent.scan_folder("/ไม่มีที่นี่", 3), [])


class ModifiedAtTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.mkdtemp(prefix="find-recent-time-")

    def test_กล่องใช้เวลาของไฟล์ข้างในถ้าใหม่กว่า(self):
        # เวลาของตัวกล่องบางทีไม่ขยับตามไฟล์ข้างใน
        # ถ้าดูแค่ตัวกล่อง จะตัดสินว่าไฟล์เก่าแล้วทิ้งไป ทั้งที่เพิ่งเซฟมา
        bundle = make_bundle(os.path.join(self.temp, "งาน.fcpxmld"))
        old = time.time() - 9999
        os.utime(bundle, (old, old))
        self.assertGreater(find_recent.modified_at(bundle), old)

    def test_ไฟล์ที่ไม่มีอยู่คืนค่าว่าง(self):
        self.assertIsNone(find_recent.modified_at(os.path.join(self.temp, "ไม่มี")))


class SearchRoundsTests(unittest.TestCase):
    def test_โฟลเดอร์ที่ระบุมาต้องถูกค้นก่อนเสมอ(self):
        rounds = list(find_recent.search_rounds("/บ้าน", ["/ที่เก็บของเรา"]))
        self.assertEqual(rounds[0][0][0], "/ที่เก็บของเรา")

    def test_โฟลเดอร์ที่ระบุมาค้นลึกสามชั้น(self):
        rounds = list(find_recent.search_rounds("/บ้าน", ["/ที่เก็บของเรา"]))
        self.assertEqual(rounds[0][0][1], 3)

    def test_มีรอบที่ถามจากค่าที่finalcutจำไว้(self):
        รอบทั้งหมด = list(find_recent.search_rounds("/บ้าน", []))
        self.assertGreaterEqual(len(รอบทั้งหมด), 4)

    def test_ไดรฟ์ถูกค้นลึกสามชั้น(self):
        # ปลายทางของห้องข่าวซ้อนหลายชั้นในไดรฟ์เครือข่าย
        # สองชั้นเคยตื้นเกินไปจนหาไม่เจอ
        รอบทั้งหมด = list(find_recent.search_rounds("/บ้าน", []))
        ความลึกของไดรฟ์ = [ความลึก for จุด, ความลึก in รอบทั้งหมด[-1]]
        for ความลึก in ความลึกของไดรฟ์:
            self.assertEqual(ความลึก, 3)


class FcpLastFoldersTests(unittest.TestCase):
    def test_คืนเฉพาะโฟลเดอร์ที่มีอยู่จริง(self):
        # บนเครื่องทดสอบไม่มี Final Cut Pro จึงต้องได้รายการว่าง
        # ข้อสำคัญคือห้ามพังหรือคืนที่อยู่ที่ไม่มีอยู่จริง
        for folder in find_recent.fcp_last_folders():
            self.assertTrue(os.path.isdir(folder))


class MainTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.mkdtemp(prefix="find-recent-main-")
        self.marker = os.path.join(self.temp, "เครื่องหมาย")
        touch(self.marker)
        self.target = os.path.join(self.temp, "ที่เก็บ")
        os.makedirs(self.target, exist_ok=True)

    def test_เจอไฟล์ที่ใหม่กว่าเครื่องหมาย(self):
        time.sleep(0.01)
        touch(os.path.join(self.target, "งาน.fcpxml"))
        self.assertEqual(find_recent.main([self.marker, self.target]), 0)

    def test_ไฟล์เก่ากว่าเครื่องหมายไม่ถูกหยิบ(self):
        ไฟล์เก่า = touch(os.path.join(self.target, "งานเก่า.fcpxml"))
        เมื่อวาน = time.time() - 86400
        os.utime(ไฟล์เก่า, (เมื่อวาน, เมื่อวาน))
        self.assertEqual(find_recent.main([self.marker, self.target]), 1)

    def test_เลือกเฉพาะชื่อที่ระบุ(self):
        time.sleep(0.01)
        touch(os.path.join(self.target, "งานอื่น.fcpxml"))
        self.assertEqual(
            find_recent.main([self.marker, self.target, "--name", "ของเรา"]), 1)

    def test_ไม่มีเครื่องหมายเวลาแจ้งผิดพลาด(self):
        self.assertEqual(find_recent.main([os.path.join(self.temp, "ไม่มี"), self.target]), 2)


if __name__ == "__main__":
    unittest.main()
