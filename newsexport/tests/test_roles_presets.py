#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ชุดทดสอบของตัวอ่าน จำ และคืนค่าตั้ง Roles
รันด้วย:  python3 tests/test_roles_presets.py
"""

import os
import plistlib
import shutil
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "tools"))

import roles_presets as rp  # noqa: E402


def write_plist(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as handle:
        plistlib.dump(data, handle)


class Sandbox(unittest.TestCase):
    """สร้างเครื่องจำลองขึ้นมาหนึ่งเครื่อง จะได้ทดสอบได้โดยไม่แตะของจริง"""

    def setUp(self):
        self.home = tempfile.mkdtemp(prefix="roles-test-")
        self.settings = os.path.join(self.home, "ProApps", "Share Destinations")
        write_plist(os.path.join(self.settings, "MXF-50.fcpdest"), {
            "name": "MXF-50",
            "audio": {"rolesAs": "3 Stereo", "channels": 6},
            "video": {"codec": "AVC-Intra Class 50"},
        })
        write_plist(os.path.join(self.settings, "Export File.fcpdest"), {
            "name": "Export File",
            "audio": {"rolesAs": "Single Track"},
        })
        # ไฟล์ที่ไม่เกี่ยวข้อง ต้องไม่ถูกจับมาแสดงเป็นไฟล์สำคัญ
        os.makedirs(os.path.join(self.home, "ProApps", "อื่น ๆ"), exist_ok=True)
        with open(os.path.join(self.home, "ProApps", "อื่น ๆ", "readme.txt"),
                  "w", encoding="utf-8") as handle:
            handle.write("ไม่เกี่ยวข้อง")

        self.snapshots = os.path.join(self.home, "snapshots")
        self.original_home = rp.SNAPSHOT_HOME
        rp.SNAPSHOT_HOME = self.snapshots

    def tearDown(self):
        rp.SNAPSHOT_HOME = self.original_home
        shutil.rmtree(self.home, ignore_errors=True)

    def roots(self):
        return [os.path.join(self.home, "ProApps")]


class TestReading(Sandbox):
    """การสำรวจต้องเห็นไฟล์ครบ และอ่านค่าข้างในออกมาได้"""

    def test_lists_every_file(self):
        files = rp.list_setting_files(self.roots())
        names = [os.path.basename(row[0]) for row in files]
        self.assertIn("MXF-50.fcpdest", names)
        self.assertIn("Export File.fcpdest", names)
        self.assertIn("readme.txt", names)

    def test_marks_only_the_relevant_files(self):
        self.assertTrue(rp.looks_interesting(os.path.join(self.settings, "MXF-50.fcpdest")))
        self.assertFalse(rp.looks_interesting(os.path.join(self.home, "ProApps",
                                                           "อื่น ๆ", "readme.txt")))

    def test_reads_a_plist(self):
        data = rp.read_plist(os.path.join(self.settings, "MXF-50.fcpdest"))
        self.assertEqual(data["audio"]["rolesAs"], "3 Stereo")

    def test_unreadable_file_does_not_crash(self):
        path = os.path.join(self.home, "ProApps", "อื่น ๆ", "readme.txt")
        self.assertIsNone(rp.read_plist(path))

    def test_flatten_makes_one_line_per_value(self):
        flat = dict(rp.flatten({"audio": {"rolesAs": "3 Stereo"}}))
        self.assertEqual(flat["/audio/rolesAs"], "3 Stereo")

    def test_flatten_handles_lists(self):
        flat = dict(rp.flatten({"tracks": ["A", "B"]}))
        self.assertEqual(flat["/tracks/0"], "A")
        self.assertEqual(flat["/tracks/1"], "B")

    def test_describe_can_search_for_a_word(self):
        lines = rp.describe_file(os.path.join(self.settings, "MXF-50.fcpdest"),
                                 find="3 Stereo")
        joined = "\n".join(lines)
        self.assertIn("rolesAs = 3 Stereo", joined)
        self.assertNotIn("AVC-Intra", joined)

    def test_report_mentions_the_stereo_setting(self):
        report = "\n".join(rp.build_report(self.roots()))
        self.assertIn("3 Stereo", report)
        self.assertIn("MXF-50.fcpdest", report)

    def test_report_without_settings_says_so_plainly(self):
        report = "\n".join(rp.build_report([]))
        self.assertIn("ไม่พบโฟลเดอร์ตั้งค่า", report)


class TestRemembering(Sandbox):
    """จำค่าไว้แล้วต้องคืนกลับได้เป๊ะ แม้ค่าจะถูกแก้ไปแล้ว"""

    def test_snapshot_copies_every_file(self):
        copied = rp.do_snapshot("ค่ามาตรฐาน", self.roots())
        self.assertGreaterEqual(copied, 3)
        self.assertIn("ค่ามาตรฐาน", rp.list_snapshots())

    def test_restore_brings_back_the_old_value(self):
        rp.do_snapshot("ค่ามาตรฐาน", self.roots())

        # จำลองว่ามีคนเผลอเปลี่ยนค่าเป็นอย่างอื่น
        write_plist(os.path.join(self.settings, "MXF-50.fcpdest"),
                    {"name": "MXF-50", "audio": {"rolesAs": "Single Track"}})
        self.assertEqual(
            rp.read_plist(os.path.join(self.settings, "MXF-50.fcpdest"))["audio"]["rolesAs"],
            "Single Track")

        count, message = rp.do_restore("ค่ามาตรฐาน", force=True)
        self.assertIsNotNone(count, message)
        self.assertEqual(
            rp.read_plist(os.path.join(self.settings, "MXF-50.fcpdest"))["audio"]["rolesAs"],
            "3 Stereo")

    def test_restore_keeps_the_previous_files_as_a_backup(self):
        rp.do_snapshot("ค่ามาตรฐาน", self.roots())
        rp.do_restore("ค่ามาตรฐาน", force=True)
        parent = os.path.dirname(self.roots()[0])
        leftovers = [n for n in os.listdir(parent) if "ก่อนคืนค่า" in n]
        self.assertEqual(len(leftovers), 1)

    def test_restore_without_a_snapshot_fails_politely(self):
        count, message = rp.do_restore("ยังไม่เคยจำ", force=True)
        self.assertIsNone(count)
        self.assertIn("ไม่พบสำเนา", message)

    def test_snapshotting_twice_keeps_the_older_copy(self):
        rp.do_snapshot("ค่ามาตรฐาน", self.roots())
        rp.do_snapshot("ค่ามาตรฐาน", self.roots())
        older = [n for n in rp.list_snapshots() if n.startswith("ค่ามาตรฐาน-เก่า-")]
        self.assertEqual(len(older), 1)

    def test_index_records_where_each_folder_came_from(self):
        rp.do_snapshot("ค่ามาตรฐาน", self.roots())
        pairs = rp.read_snapshot_index("ค่ามาตรฐาน")
        self.assertEqual(len(pairs), 1)
        self.assertEqual(pairs[0][1], self.roots()[0])

    def test_thai_names_survive_the_round_trip(self):
        thai = os.path.join(self.roots()[0], "ชุดเสียง", "สามสเตอริโอ.fcpdest")
        write_plist(thai, {"audio": {"rolesAs": "3 Stereo"}})
        rp.do_snapshot("ค่ามาตรฐาน", self.roots())
        os.remove(thai)
        rp.do_restore("ค่ามาตรฐาน", force=True)
        self.assertTrue(os.path.exists(thai))


class TestCommandLine(Sandbox):
    """สั่งจากบรรทัดคำสั่งต้องได้ผลเหมือนกัน เพราะแอปเรียกผ่านทางนี้"""

    def test_report_writes_to_a_file(self):
        out = os.path.join(self.home, "รายงาน.txt")
        code = rp.main(["report", "--also-look-in", self.roots()[0], "--out", out])
        self.assertEqual(code, 0)
        with open(out, encoding="utf-8") as handle:
            self.assertIn("3 Stereo", handle.read())

    def test_snapshot_then_restore_from_the_command_line(self):
        self.assertEqual(rp.main(["snapshot", "ชุดข่าว",
                                  "--also-look-in", self.roots()[0]]), 0)
        write_plist(os.path.join(self.settings, "MXF-50.fcpdest"),
                    {"audio": {"rolesAs": "ผิด"}})
        self.assertEqual(rp.main(["restore", "ชุดข่าว", "--force"]), 0)
        self.assertEqual(
            rp.read_plist(os.path.join(self.settings, "MXF-50.fcpdest"))["audio"]["rolesAs"],
            "3 Stereo")

    def test_restore_of_a_missing_snapshot_returns_an_error_code(self):
        self.assertEqual(rp.main(["restore", "ไม่มีอยู่จริง", "--force"]), 1)


if __name__ == "__main__":
    result = unittest.main(exit=False, verbosity=1).result
    if result.wasSuccessful():
        print("ผ่านทั้งหมด")
    else:
        sys.exit(1)
