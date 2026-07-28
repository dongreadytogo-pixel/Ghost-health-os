#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ชุดทดสอบของตัวตรวจจับก้อนข่าว
รันด้วย:  python3 tests/test_segments.py
ถ้าขึ้น "ผ่านทั้งหมด" แปลว่าโปรแกรมยังทำงานถูกต้อง
"""

import os
import sys
import time
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


class TestNamingAgainstRealProject(unittest.TestCase):
    """
    ชื่องานจริงของผู้ใช้ลงท้ายด้วยขีดอยู่แล้ว
    ผลลัพธ์ที่ต้องได้คือ '…(ชลบุรี)-1.mov' ไม่ใช่ '…(ชลบุรี)--1.mov'
    """

    REAL = "OA690728_4 (ลบ) หนุ่มขับรถตู้ชนท้ายรถ 3 คันเสียหาย(ชลบุรี)-"
    WANT = "OA690728_4 (ลบ) หนุ่มขับรถตู้ชนท้ายรถ 3 คันเสียหาย(ชลบุรี)-1"

    def test_trailing_hyphen_is_not_doubled(self):
        self.assertEqual(ns.segment_basename(self.REAL, 1), self.WANT)

    def test_name_without_hyphen_gets_one(self):
        self.assertEqual(ns.segment_basename("ข่าวเช้า", 2), "ข่าวเช้า-2")

    def test_trailing_hyphen_and_space(self):
        self.assertEqual(ns.segment_basename("ข่าวเช้า - ", 3), "ข่าวเช้า-3")

    def test_filenames_match_the_delivery_list(self):
        names = ns.build_filenames(self.REAL, 1, ["mov", "mxf"])
        self.assertEqual(names, [self.WANT + ".mov", self.WANT + ".mxf"])


class TestBundleInput(unittest.TestCase):
    """Final Cut Pro รุ่นใหม่ส่งออกเป็นกล่อง .fcpxmld ต้องรับได้ด้วย"""

    def setUp(self):
        import tempfile
        self.temp = tempfile.mkdtemp()

    def tearDown(self):
        import shutil
        shutil.rmtree(self.temp, ignore_errors=True)

    def test_bundle_folder_resolves_to_inner_file(self):
        bundle = os.path.join(self.temp, "งาน.fcpxmld")
        os.makedirs(bundle)
        inner = os.path.join(bundle, "Info.fcpxml")
        with open(inner, "w", encoding="utf-8") as handle:
            handle.write("<fcpxml/>")
        self.assertEqual(ns.resolve_input(bundle), inner)

    def test_plain_file_passes_through(self):
        plain = os.path.join(self.temp, "งาน.fcpxml")
        with open(plain, "w", encoding="utf-8") as handle:
            handle.write("<fcpxml/>")
        self.assertEqual(ns.resolve_input(plain), plain)

    def test_bundle_without_inner_file_explains_itself(self):
        bundle = os.path.join(self.temp, "ว่าง.fcpxmld")
        os.makedirs(bundle)
        with self.assertRaises(ns.TimelineError) as caught:
            ns.resolve_input(bundle)
        self.assertIn("Export XML", str(caught.exception))

    def test_missing_path_is_reported(self):
        with self.assertRaises(ns.TimelineError):
            ns.resolve_input(os.path.join(self.temp, "ไม่มีจริง.fcpxml"))


class TestRealTimelineShape(unittest.TestCase):
    """
    ทดสอบด้วยโครงสร้างแบบเดียวกับไทม์ไลน์จริงของผู้ใช้
    ช่องว่าง 4 จุด ยาว 6.36 / 11.20 / 7.52 / 10.28 วินาที รวมเป็น 5 ก้อน
    """

    GAPS = [6.36, 11.20, 7.52, 10.28]

    def build_items(self):
        pattern = []
        for index in range(5):
            pattern.append(("clip", 20))
            if index < 4:
                pattern.append(("gap", self.GAPS[index]))
        return spine_items(pattern)

    def test_default_threshold_finds_five_blocks(self):
        segments = ns.group_into_segments(self.build_items(), ns.DEFAULT_MIN_GAP)
        self.assertEqual(len(segments), 5)

    def test_every_real_gap_is_a_separator(self):
        gaps = ns.list_gaps(self.build_items())
        self.assertEqual(len(gaps), 4)
        for _, duration in gaps:
            self.assertGreaterEqual(float(duration), ns.DEFAULT_MIN_GAP)

    def test_accidental_two_frame_gap_does_not_split(self):
        # ช่องว่าง 2 เฟรมที่ 25 fps = 0.08 วินาที ต่ำกว่าค่าเริ่มต้น 0.2
        pattern = [("clip", 20), ("gap", 0.08), ("clip", 20)]
        segments = ns.group_into_segments(spine_items(pattern), ns.DEFAULT_MIN_GAP)
        self.assertEqual(len(segments), 1)


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


class TestSplit(unittest.TestCase):
    """ทดสอบการแยกไทม์ไลน์ออกเป็นงานย่อย"""

    @classmethod
    def setUpClass(cls):
        import xml.etree.ElementTree as ET
        import fcpxml_split
        cls.split_module = fcpxml_split
        fixture = os.path.join(HERE, "sample-news.fcpxml")
        if not os.path.exists(fixture):
            import make_fixture  # noqa
        cls.tree, cls.details, cls.fps, cls.warnings = fcpxml_split.split(
            ET.parse(fixture), 1.0)
        cls.root = cls.tree.getroot()
        cls.ET = ET

    def test_makes_one_project_per_block(self):
        self.assertEqual(len(list(self.root.iter("project"))), 5)
        self.assertEqual(len(self.details), 5)

    def test_project_names_end_with_the_block_number(self):
        names = [p.get("name") for p in self.root.iter("project")]
        for index, name in enumerate(names, start=1):
            self.assertTrue(name.endswith("-%d" % index), name)

    def test_each_block_starts_at_zero(self):
        # งานย่อยทุกอันต้องเริ่มที่ 0 ไม่ใช่ตำแหน่งเดิมบนไทม์ไลน์ยาว
        for project in self.root.iter("project"):
            first = list(project.find("sequence").find("spine"))[0]
            self.assertEqual(ns.parse_time(first.get("offset")), Fraction(0))

    def test_block_duration_matches_the_detected_length(self):
        for project, detail in zip(self.root.iter("project"), self.details):
            duration = ns.parse_time(project.find("sequence").get("duration"))
            self.assertEqual(duration, detail["end"] - detail["start"])

    def test_no_clip_is_lost_or_duplicated(self):
        total = sum(len(list(p.find("sequence").find("spine")))
                    for p in self.root.iter("project"))
        self.assertEqual(total, 17)  # 5+3+3+3+3 คลิปในไฟล์ตัวอย่าง

    def test_resources_are_carried_over(self):
        # ถ้าไม่ยก resources มาด้วย Final Cut Pro จะหาไฟล์วิดีโอไม่เจอ
        resources = self.root.find("resources")
        self.assertIsNotNone(resources)
        self.assertIsNotNone(resources.find("asset"))
        self.assertIsNotNone(resources.find("format"))

    def test_sequence_settings_are_preserved(self):
        # การวางเสียงและอัตราเสียงต้องเหมือนเดิม ไม่งั้น Roles จะเพี้ยน
        for project in self.root.iter("project"):
            sequence = project.find("sequence")
            self.assertEqual(sequence.get("audioLayout"), "stereo")
            self.assertEqual(sequence.get("audioRate"), "48k")
            self.assertEqual(sequence.get("format"), "r1")

    def test_output_is_valid_xml(self):
        text = self.ET.tostring(self.root, encoding="unicode")
        self.assertIsNotNone(self.ET.fromstring(text))

    def test_ntsc_timescale_is_not_rounded(self):
        # 29.97 fps ต้องใช้ตัวส่วน 30000 ไม่ใช่ 30
        self.assertEqual(self.split_module.timescale_for(Fraction(30000, 1001)), 30000)
        self.assertEqual(self.split_module.timescale_for(Fraction(25)), 25)

    def test_clean_timeline_reports_no_warning(self):
        self.assertEqual(self.warnings, [])

    def test_title_hanging_under_a_separator_gap_is_reported(self):
        # ตัวอักษรที่ห้อยใต้ช่องว่างคั่นข่าว ต้องถูกเตือน ไม่ใช่หายเงียบ ๆ
        spine = self.ET.fromstring(
            '<spine>'
            '  <asset-clip offset="0s" duration="250/25s" name="คลิป"/>'
            '  <gap offset="250/25s" duration="175/25s" name="Gap">'
            '    <title offset="250/25s" duration="50/25s" name="ชื่อเรื่องข่าว"/>'
            '  </gap>'
            '  <asset-clip offset="425/25s" duration="250/25s" name="คลิป"/>'
            '</spine>')
        warnings = self.split_module.find_orphaned_content(spine, [], 1.0)
        self.assertEqual(len(warnings), 1)
        self.assertEqual(warnings[0]["name"], "ชื่อเรื่องข่าว")

    def test_content_under_a_short_gap_is_not_reported(self):
        # ช่องว่างสั้นยังอยู่ในก้อนเดิม ของที่ห้อยอยู่จึงไม่ตกหล่น
        spine = self.ET.fromstring(
            '<spine>'
            '  <gap offset="0s" duration="10/25s" name="Gap">'
            '    <title offset="0s" duration="10/25s" name="ชื่อเรื่องข่าว"/>'
            '  </gap>'
            '</spine>')
        self.assertEqual(self.split_module.find_orphaned_content(spine, [], 1.0), [])

    def test_write_time_lands_on_whole_frames(self):
        write_time = self.split_module.write_time
        self.assertEqual(write_time(Fraction(0), 25), "0s")
        self.assertEqual(write_time(Fraction(35), 25), "875/25s")


class TestProgressCounting(unittest.TestCase):
    """ตัวนับเปอร์เซ็นต์ต้องไม่นับไฟล์ที่ยังเขียนไม่เสร็จว่าเสร็จแล้ว"""

    def setUp(self):
        import tempfile
        import watch_outputs
        self.watch = watch_outputs
        self.temp = tempfile.mkdtemp()
        self.names = ["ก้อน-1.mov", "ก้อน-1.mxf", "ก้อน-2.mov", "ก้อน-2.mxf"]
        self.namesFile = os.path.join(self.temp, "names.txt")
        with open(self.namesFile, "w", encoding="utf-8") as handle:
            handle.write("\n".join(self.names) + "\n")

    def tearDown(self):
        import shutil
        shutil.rmtree(self.temp, ignore_errors=True)

    def write(self, name, size):
        with open(os.path.join(self.temp, name), "wb") as handle:
            handle.write(b"x" * size)

    def run_watch(self):
        import io
        import contextlib
        buffer = io.StringIO()
        with contextlib.redirect_stdout(buffer):
            self.watch.main([self.temp, self.namesFile, "--settle", "0.2"])
        lines = buffer.getvalue().split("\n")
        return int(lines[0]), int(lines[1]), int(lines[2]), lines[3]

    def test_empty_folder_reports_zero(self):
        done, working, total, last = self.run_watch()
        self.assertEqual((done, working, total), (0, 0, 4))
        self.assertEqual(last, "")

    def test_settled_files_count_as_done(self):
        self.write("ก้อน-1.mov", 100)
        self.write("ก้อน-1.mxf", 100)
        done, working, total, last = self.run_watch()
        self.assertEqual((done, working, total), (2, 0, 4))
        self.assertEqual(last, "ก้อน-1.mxf")

    def test_growing_file_counts_as_working_not_done(self):
        import threading
        self.write("ก้อน-1.mov", 100)
        path = os.path.join(self.temp, "ก้อน-2.mov")
        with open(path, "wb") as handle:
            handle.write(b"x" * 10)
        stop = threading.Event()

        def grow():
            while not stop.is_set():
                with open(path, "ab") as handle:
                    handle.write(b"y" * 64)
                time.sleep(0.01)

        worker = threading.Thread(target=grow)
        worker.start()
        try:
            done, working, total, _ = self.run_watch()
        finally:
            stop.set()
            worker.join()
        self.assertEqual(done, 1)
        self.assertEqual(working, 1)
        self.assertEqual(total, 4)

    def test_zero_byte_file_is_not_done(self):
        # ไฟล์ขนาดศูนย์คือเพิ่งเปิดไว้ ยังไม่ได้เขียนอะไรลงไป
        self.write("ก้อน-1.mov", 0)
        done, working, total, _ = self.run_watch()
        self.assertEqual((done, working), (0, 1))

    def test_all_present_reports_complete(self):
        for name in self.names:
            self.write(name, 50)
        done, working, total, _ = self.run_watch()
        self.assertEqual((done, working, total), (4, 0, 4))


class TestFindRecentTimeline(unittest.TestCase):
    """
    โปรแกรมต้องไปหาไฟล์ไทม์ไลน์เอง ผู้ใช้ไม่ต้องเลือกไฟล์
    จึงต้องหยิบเฉพาะไฟล์ที่เพิ่งเกิดใหม่ ห้ามหยิบไฟล์เก่าของเมื่อวาน
    """

    def setUp(self):
        import tempfile
        import find_recent
        self.finder = find_recent
        self.temp = tempfile.mkdtemp()
        self.marker = os.path.join(self.temp, "marker")
        open(self.marker, "w").close()

    def tearDown(self):
        import shutil
        shutil.rmtree(self.temp, ignore_errors=True)

    def find(self):
        import io
        import contextlib
        buffer = io.StringIO()
        with contextlib.redirect_stdout(buffer):
            code = self.finder.main([self.marker, self.temp])
        return code, buffer.getvalue().strip()

    def make_old(self, name):
        path = os.path.join(self.temp, name)
        open(path, "w").close()
        os.utime(path, (0, 0))
        return path

    def make_new(self, name):
        path = os.path.join(self.temp, name)
        open(path, "w").close()
        later = os.path.getmtime(self.marker) + 10
        os.utime(path, (later, later))
        return path

    def make_new_bundle(self, name):
        bundle = os.path.join(self.temp, name)
        os.makedirs(bundle)
        inner = os.path.join(bundle, "Info.fcpxml")
        open(inner, "w").close()
        later = os.path.getmtime(self.marker) + 10
        os.utime(inner, (later, later))
        os.utime(bundle, (0, 0))   # เวลาของตัวกล่องไม่อัปเดต ต้องดูไฟล์ข้างใน
        return bundle

    def test_nothing_new_reports_not_found(self):
        self.make_old("เมื่อวาน.fcpxml")
        code, output = self.find()
        self.assertEqual(code, 1)
        self.assertEqual(output, "")

    def test_finds_a_new_plain_file(self):
        wanted = self.make_new("วันนี้.fcpxml")
        code, output = self.find()
        self.assertEqual(code, 0)
        self.assertEqual(output, wanted)

    def test_finds_a_new_bundle_by_its_inner_file(self):
        wanted = self.make_new_bundle("วันนี้.fcpxmld")
        code, output = self.find()
        self.assertEqual(code, 0)
        self.assertEqual(output, wanted)

    def test_old_file_is_never_chosen_over_new_one(self):
        self.make_old("เมื่อวาน.fcpxml")
        wanted = self.make_new("วันนี้.fcpxml")
        code, output = self.find()
        self.assertEqual((code, output), (0, wanted))

    def test_newest_wins_between_two_new_files(self):
        first = self.make_new("หนึ่ง.fcpxml")
        second = self.make_new("สอง.fcpxml")
        later = os.path.getmtime(first) + 5
        os.utime(second, (later, later))
        code, output = self.find()
        self.assertEqual((code, output), (0, second))

    def test_finds_file_saved_deep_in_a_given_folder(self):
        # ห้องข่าวเซฟลงไดรฟ์เครือข่าย ซึ่งอยู่นอกโฟลเดอร์ส่วนตัว
        # จึงต้องค้นโฟลเดอร์ที่ส่งเข้ามาให้ ไม่ใช่แค่ในบ้านของผู้ใช้
        deep = os.path.join(self.temp, "งานข่าว", "วันนี้")
        os.makedirs(deep)
        wanted = os.path.join(deep, "ไทม์ไลน์.fcpxml")
        open(wanted, "w").close()
        later = os.path.getmtime(self.marker) + 10
        os.utime(wanted, (later, later))
        code, output = self.find()
        self.assertEqual((code, output), (0, wanted))

    def test_does_not_look_inside_a_library_bundle(self):
        # ในคลังของ Final Cut Pro มีไฟล์เยอะมาก และไม่ใช่ไฟล์ที่เราต้องการ
        # ถ้าเดินเข้าไปจะช้าและอาจหยิบไฟล์ผิด
        inside = os.path.join(self.temp, "คลัง.fcpbundle", "ข้างใน")
        os.makedirs(inside)
        wrong = os.path.join(inside, "ไม่ควรเจอ.fcpxml")
        open(wrong, "w").close()
        later = os.path.getmtime(self.marker) + 10
        os.utime(wrong, (later, later))
        code, output = self.find()
        self.assertEqual(code, 1)

    def test_unrelated_files_are_ignored(self):
        self.make_new("ไม่เกี่ยว.mov")
        self.make_new("ไม่เกี่ยว.txt")
        code, output = self.find()
        self.assertEqual(code, 1)


class TestManyBlocks(unittest.TestCase):
    """
    งานข่าวจริงอาจมี 30 ก้อนขึ้นไป ต้องได้ครบทุกก้อน เร็ว และไม่เพี้ยน
    ข้อสอบชุดนี้จึงสร้างไทม์ไลน์ 30 ก้อนขึ้นมาทดสอบจริง
    """

    BLOCKS = 30
    CLIPS_PER_BLOCK = 3
    PROJECT = "OA690729_1 (ลบ) ข่าวเช้าทั้งหมด(กรุงเทพ)-"

    @classmethod
    def setUpClass(cls):
        import xml.etree.ElementTree as ET
        import fcpxml_split
        cls.ET = ET
        cls.split_module = fcpxml_split

        def fcp_time(seconds):
            fraction = Fraction(seconds).limit_denominator(25000)
            return "%d/%ds" % (fraction.numerator * 25, 25 * fraction.denominator)

        parts, cursor, number = [], Fraction(0), 0
        for block in range(cls.BLOCKS):
            for length in (7, 5, 9):
                number += 1
                parts.append(
                    '<asset-clip ref="r2" offset="%s" name="ข่าว %d" start="0s" '
                    'duration="%s" format="r1" audioRole="dialogue"/>'
                    % (fcp_time(cursor), number, fcp_time(length)))
                cursor += length
            if block < cls.BLOCKS - 1:
                parts.append('<gap name="Gap" offset="%s" start="0s" duration="%s"/>'
                             % (fcp_time(cursor), fcp_time(6)))
                cursor += 6

        document = (
            '<?xml version="1.0" encoding="UTF-8"?><fcpxml version="1.14"><resources>'
            '<format id="r1" name="FFVideoFormat1080i50" frameDuration="200/5000s"'
            ' width="1920" height="1080"/>'
            '<asset id="r2" name="A" start="0s" duration="9999s" hasVideo="1"'
            ' hasAudio="1" format="r1"><media-rep kind="original-media"'
            ' src="file:///x.mov"/></asset>'
            '</resources><library><event name="test">'
            '<project name="%s"><sequence format="r1" duration="%s" tcStart="0s"'
            ' tcFormat="NDF" audioLayout="stereo" audioRate="48k"><spine>%s</spine>'
            '</sequence></project></event></library></fcpxml>'
            % (cls.PROJECT, fcp_time(cursor), "".join(parts)))

        started = time.time()
        tree = ET.ElementTree(ET.fromstring(document))
        cls.tree, cls.details, cls.fps, cls.warnings = fcpxml_split.split(
            tree, ns.DEFAULT_MIN_GAP, "แยกงาน ทดสอบ")
        cls.elapsed = time.time() - started
        cls.root = cls.tree.getroot()

    def test_all_thirty_blocks_are_found(self):
        self.assertEqual(len(self.details), self.BLOCKS)
        self.assertEqual(len(list(self.root.iter("project"))), self.BLOCKS)

    def test_numbering_runs_one_to_thirty_in_order(self):
        names = [p.get("name") for p in self.root.iter("project")]
        for index, name in enumerate(names, start=1):
            self.assertEqual(name, self.PROJECT.rstrip("- ") + "-%d" % index)

    def test_no_clip_is_lost_across_thirty_blocks(self):
        total = sum(len(list(p.find("sequence").find("spine")))
                    for p in self.root.iter("project"))
        self.assertEqual(total, self.BLOCKS * self.CLIPS_PER_BLOCK)

    def test_audio_roles_survive_on_every_clip(self):
        # ถ้า Roles หายแม้คลิปเดียว ไฟล์ mxf แบบ 3 Stereo จะเสีย
        with_roles = sum(
            1 for p in self.root.iter("project")
            for clip in p.find("sequence").find("spine")
            if clip.get("audioRole"))
        self.assertEqual(with_roles, self.BLOCKS * self.CLIPS_PER_BLOCK)

    def test_every_block_starts_at_zero(self):
        for project in self.root.iter("project"):
            first = list(project.find("sequence").find("spine"))[0]
            self.assertEqual(ns.parse_time(first.get("offset")), Fraction(0))

    def test_sixty_output_filenames_are_produced(self):
        names = []
        for index in range(1, self.BLOCKS + 1):
            names += ns.build_filenames(self.PROJECT, index, ["mov", "mxf"])
        self.assertEqual(len(names), self.BLOCKS * 2)
        self.assertEqual(names[-1], self.PROJECT.rstrip("- ") + "-30.mxf")
        self.assertEqual(len(set(names)), len(names))  # ห้ามมีชื่อซ้ำ

    def test_thirty_blocks_split_quickly(self):
        # ต้องเร็วพอที่จะไม่รู้สึกว่าค้าง แม้งานใหญ่
        self.assertLess(self.elapsed, 2.0)

    def test_event_name_is_the_one_we_asked_for(self):
        # ชื่อ Event ต้องไม่ซ้ำของเดิม ไม่งั้นงานเก่าจะปนกับงานใหม่
        event = self.root.find(".//event")
        self.assertEqual(event.get("name"), "แยกงาน ทดสอบ")


class TestCollectOutputs(unittest.TestCase):
    """
    Final Cut Pro บังคับที่เซฟไม่ได้จริง ไฟล์จึงไปตกที่อื่น
    เคยไปโผล่ทั้งในโฟลเดอร์ F และในโฟลเดอร์ Applications
    ตัวเก็บไฟล์จึงต้องตามไปเก็บมาให้ถูกที่ และห้ามแตะไฟล์อื่นของผู้ใช้
    """

    def setUp(self):
        import tempfile
        import collect_outputs
        self.collector = collect_outputs
        self.temp = tempfile.mkdtemp()
        self.target = os.path.join(self.temp, "ปลายทาง")
        self.stray = os.path.join(self.temp, "ที่ผิด")
        os.makedirs(self.target)
        os.makedirs(self.stray)
        self.names = ["ข่าว-1.mov", "ข่าว-1.mxf", "ข่าว-2.mov", "ข่าว-2.mxf"]
        self.namesFile = os.path.join(self.temp, "names.txt")
        with open(self.namesFile, "w", encoding="utf-8") as handle:
            handle.write("\n".join(self.names) + "\n")

    def tearDown(self):
        import shutil
        shutil.rmtree(self.temp, ignore_errors=True)

    def put(self, folder, name, size=400):
        path = os.path.join(folder, name)
        with open(path, "wb") as handle:
            handle.write(b"x" * size)
        return path

    def collect(self):
        import io
        import contextlib
        buffer = io.StringIO()
        with contextlib.redirect_stdout(buffer):
            self.collector.main([self.target, self.namesFile,
                                 "--also-look-in", self.stray, "--settle", "0.2"])
        lines = buffer.getvalue().split("\n")
        return int(lines[0]), int(lines[1]), int(lines[2])

    def test_files_saved_elsewhere_are_brought_back(self):
        for name in self.names:
            self.put(self.stray, name)
        moved, waiting, missing = self.collect()
        self.assertEqual((moved, waiting, missing), (4, 0, 0))
        self.assertEqual(sorted(os.listdir(self.target)), sorted(self.names))
        self.assertEqual(os.listdir(self.stray), [])

    def test_other_files_are_never_touched(self):
        self.put(self.stray, "ข่าว-1.mov")
        keep = self.put(self.stray, "งานสำคัญของผู้ใช้.mov")
        self.collect()
        self.assertTrue(os.path.exists(keep))

    def test_files_already_in_place_are_left_alone(self):
        wanted = self.put(self.target, "ข่าว-1.mov")
        moved, waiting, missing = self.collect()
        self.assertTrue(os.path.exists(wanted))
        self.assertEqual(missing, 3)

    def test_existing_file_is_not_overwritten(self):
        self.put(self.target, "ข่าว-1.mov", size=111)
        self.put(self.stray, "ข่าว-1.mov", size=999)
        self.collect()
        # ของเดิมต้องยังอยู่เท่าเดิม ของใหม่ได้ชื่อใหม่
        self.assertEqual(os.path.getsize(os.path.join(self.target, "ข่าว-1.mov")), 111)
        self.assertTrue(any(n.startswith("ข่าว-1 (2)") for n in os.listdir(self.target)))

    def test_a_file_still_being_written_is_left_for_next_round(self):
        import threading
        path = self.put(self.stray, "ข่าว-1.mov", size=10)
        stop = threading.Event()

        def grow():
            while not stop.is_set():
                with open(path, "ab") as handle:
                    handle.write(b"y" * 64)
                time.sleep(0.01)

        worker = threading.Thread(target=grow)
        worker.start()
        try:
            moved, waiting, missing = self.collect()
        finally:
            stop.set()
            worker.join()
        self.assertEqual(moved, 0)
        self.assertEqual(waiting, 1)
        self.assertTrue(os.path.exists(path))

    def test_missing_files_are_reported_not_invented(self):
        self.put(self.stray, "ข่าว-1.mov")
        moved, waiting, missing = self.collect()
        self.assertEqual(moved, 1)
        self.assertEqual(missing, 3)


class TestNameListOutput(unittest.TestCase):
    """รายชื่อไฟล์ที่ส่งให้ตัวนับเปอร์เซ็นต์ ต้องเรียงและครบถ้วน"""

    def test_two_extensions_per_segment_in_order(self):
        names = []
        for index in range(1, 4):
            names += ns.build_filenames("ข่าวเช้า-", index, ["mov", "mxf"])
        self.assertEqual(names, [
            "ข่าวเช้า-1.mov", "ข่าวเช้า-1.mxf",
            "ข่าวเช้า-2.mov", "ข่าวเช้า-2.mxf",
            "ข่าวเช้า-3.mov", "ข่าวเช้า-3.mxf",
        ])


if __name__ == "__main__":
    result = unittest.main(exit=False, verbosity=1).result
    print("")
    if result.wasSuccessful():
        print("✅ ผ่านทั้งหมด %d ข้อ — โปรแกรมทำงานถูกต้อง" % result.testsRun)
    else:
        print("❌ มีข้อที่ไม่ผ่าน กรุณาส่งข้อความข้างบนนี้กลับมา")
    sys.exit(0 if result.wasSuccessful() else 1)
