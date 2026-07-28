#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ชุดทดสอบของตัวตรวจจับก้อนข่าว
รันด้วย:  python3 tests/test_segments.py
ถ้าขึ้น "ผ่านทั้งหมด" แปลว่าโปรแกรมยังทำงานถูกต้อง
"""

import os
import sys
import unittest
from fractions import Fraction

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "tools"))

import fcpxml_segments as ns  # noqa: E402


def spine_items(pattern):
    """
    สร้างรายการของบนไทม์ไลน์จากรูปแบบสั้น ๆ เพื่อให้เขียนเทสต์ได้ง่าย
    pattern เป็นรายการของ ("clip"|"gap", ความยาววินาที)
    """
    items = []
    cursor = Fraction(0)
    for kind, length in pattern:
        items.append((kind, cursor, Fraction(length), "ทดสอบ", "asset-clip"))
        cursor += Fraction(length)
    return items


class TestParseTime(unittest.TestCase):
    """การอ่านเวลาต้องเป็นเศษส่วนเป๊ะ ห้ามปัดเศษ"""

    def test_fraction_form(self):
        self.assertEqual(ns.parse_time("52052/25s"), Fraction(52052, 25))

    def test_whole_seconds(self):
        self.assertEqual(ns.parse_time("3s"), Fraction(3))

    def test_zero_and_missing(self):
        self.assertEqual(ns.parse_time("0s"), Fraction(0))
        self.assertEqual(ns.parse_time(None), Fraction(0))

    def test_ntsc_rate_stays_exact(self):
        # 29.97 fps คือ 30000/1001 — ถ้าใช้ทศนิยมจะเพี้ยน
        frame = ns.parse_time("1001/30000s")
        self.assertEqual(1 / frame, Fraction(30000, 1001))


class TestTimecode(unittest.TestCase):
    def test_start_of_timeline(self):
        self.assertEqual(ns.format_timecode(Fraction(0), Fraction(25)), "00:00:00:00")

    def test_minutes_and_frames(self):
        # 1 นาที 5 วินาที 12 เฟรม ที่ 25 fps
        seconds = Fraction(65) + Fraction(12, 25)
        self.assertEqual(ns.format_timecode(seconds, Fraction(25)), "00:01:05:12")

    def test_hour_boundary(self):
        self.assertEqual(ns.format_timecode(Fraction(3600), Fraction(25)), "01:00:00:00")


class TestGrouping(unittest.TestCase):
    def test_five_blocks_split_by_gaps(self):
        pattern = []
        for index in range(5):
            pattern.append(("clip", 10))
            if index < 4:
                pattern.append(("gap", 5))
        segments = ns.group_into_segments(spine_items(pattern), 1.0)
        self.assertEqual(len(segments), 5)

    def test_short_gap_stays_inside_one_block(self):
        # ช่องว่างสั้นกว่าเกณฑ์ ต้องไม่ทำให้ข่าวขาดเป็นสองก้อน
        pattern = [("clip", 10), ("gap", 0.5), ("clip", 10)]
        segments = ns.group_into_segments(spine_items(pattern), 1.0)
        self.assertEqual(len(segments), 1)
        self.assertEqual(segments[0]["end"], Fraction(41, 2))

    def test_leading_gap_is_ignored(self):
        # ถ้าไทม์ไลน์เริ่มด้วยช่องว่าง ก้อนแรกต้องเริ่มที่คลิปแรกจริง ๆ
        pattern = [("gap", 8), ("clip", 10)]
        segments = ns.group_into_segments(spine_items(pattern), 1.0)
        self.assertEqual(len(segments), 1)
        self.assertEqual(segments[0]["start"], Fraction(8))

    def test_trailing_gap_does_not_create_empty_block(self):
        pattern = [("clip", 10), ("gap", 8)]
        segments = ns.group_into_segments(spine_items(pattern), 1.0)
        self.assertEqual(len(segments), 1)
        self.assertEqual(segments[0]["end"], Fraction(10))

    def test_empty_timeline(self):
        self.assertEqual(ns.group_into_segments([], 1.0), [])

    def test_threshold_changes_the_answer(self):
        # ช่องว่าง 2 วินาที: เกณฑ์ 1 วิ แยกเป็น 2 ก้อน / เกณฑ์ 5 วิ รวมเป็นก้อนเดียว
        pattern = [("clip", 10), ("gap", 2), ("clip", 10)]
        self.assertEqual(len(ns.group_into_segments(spine_items(pattern), 1.0)), 2)
        self.assertEqual(len(ns.group_into_segments(spine_items(pattern), 5.0)), 1)


class TestFilenames(unittest.TestCase):
    PROJECT = "OA690728_4 (ลบ) หนุ่มขับรถตู้ชนท้ายรถ 3 คันเสียหาย(ชลบุรี)"

    def test_numbering_matches_the_spec(self):
        names = ns.build_filenames(self.PROJECT, 1, ["mov", "mxf"])
        self.assertEqual(names[0], self.PROJECT + "-1.mov")
        self.assertEqual(names[1], self.PROJECT + "-1.mxf")

    def test_thai_characters_are_preserved(self):
        names = ns.build_filenames("ข่าวเช้า", 3, ["mov"])
        self.assertEqual(names[0], "ข่าวเช้า-3.mov")

    def test_slash_and_colon_are_replaced(self):
        # macOS ห้ามใช้ / และ : ในชื่อไฟล์
        self.assertEqual(ns.safe_filename("ข่าว/ด่วน:ชลบุรี"), "ข่าว-ด่วน-ชลบุรี")

    def test_trailing_dot_removed(self):
        self.assertEqual(ns.safe_filename("ข่าวเช้า. "), "ข่าวเช้า")


class TestRealFixture(unittest.TestCase):
    """ทดสอบกับไฟล์ FCPXML ตัวอย่างที่เลียนแบบงานข่าวจริง"""

    @classmethod
    def setUpClass(cls):
        fixture = os.path.join(HERE, "sample-news.fcpxml")
        if not os.path.exists(fixture):
            import make_fixture  # noqa
        cls.fixture = fixture

    def test_detects_five_blocks_end_to_end(self):
        import xml.etree.ElementTree as ET
        root = ET.parse(self.fixture).getroot()
        project, sequence = ns.find_sequence(root)
        fps = ns.read_frame_rate(root, sequence)
        items = ns.walk_spine(sequence.find("spine"))
        segments = ns.group_into_segments(items, 1.0)

        self.assertEqual(fps, Fraction(25))
        self.assertEqual(len(segments), 5)
        self.assertEqual(ns.format_timecode(segments[0]["start"], fps), "00:00:00:00")
        self.assertEqual(ns.format_timecode(segments[0]["end"], fps), "00:00:35:00")
        self.assertEqual(ns.format_timecode(segments[4]["end"], fps), "00:03:01:00")

    def test_missing_project_gives_a_readable_message(self):
        import xml.etree.ElementTree as ET
        root = ET.fromstring('<fcpxml version="1.11"><resources/></fcpxml>')
        with self.assertRaises(ns.TimelineError) as caught:
            ns.find_sequence(root)
        self.assertIn("Export XML", str(caught.exception))


if __name__ == "__main__":
    result = unittest.main(exit=False, verbosity=1).result
    print("")
    if result.wasSuccessful():
        print("✅ ผ่านทั้งหมด %d ข้อ — โปรแกรมทำงานถูกต้อง" % result.testsRun)
    else:
        print("❌ มีข้อที่ไม่ผ่าน กรุณาส่งข้อความข้างบนนี้กลับมา")
    sys.exit(0 if result.wasSuccessful() else 1)
