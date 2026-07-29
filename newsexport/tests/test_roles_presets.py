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


def three_stereo_preset():
    """
    preset จริงที่ผู้ใช้ส่งมา สามแทร็กเสียง แทร็กละสองช่อง
    รหัส 6619138 คือสเตอริโอ เอา 65536 หารแล้วเหลือเศษ 2 คือสองช่อง
    """
    audio_track = {
        "audioChannelLayout": 6619138,
        "mediaType": 0,
        "roles": [{"identifier": "a.music", "mediaType": 0, "name": "All Music"},
                  {"identifier": "a.dialogue", "mediaType": 0, "name": "All Dialogue"},
                  {"identifier": "a.effects", "mediaType": 0, "name": "All Effects"}],
    }
    return {
        "name": "3 Stereo",
        "type": 0,
        "outputs": [
            {"audioChannelLayout": 6619138, "mediaType": 1,
             "roles": [{"identifier": "v.video", "mediaType": 1, "name": "All Video"},
                       {"identifier": "v.titles", "mediaType": 1, "name": "All Titles"}]},
            dict(audio_track), dict(audio_track), dict(audio_track),
        ],
    }


class TestRolePresetFile(Sandbox):
    """ไฟล์ preset จริงต้องอ่านออกและตรวจได้ถูกต้อง"""

    def write_preset(self, data, name="3 Stereo.rolepreset"):
        path = os.path.join(self.settings, name)
        write_plist(path, data)
        return path

    def test_channel_count_comes_from_the_layout_code(self):
        self.assertEqual(rp.channels_of(6619138), 2)

    def test_bad_layout_code_does_not_crash(self):
        self.assertEqual(rp.channels_of(None), 0)
        self.assertEqual(rp.channels_of("ไม่ใช่ตัวเลข"), 0)

    def test_reads_the_real_shape(self):
        summary = rp.read_role_preset(self.write_preset(three_stereo_preset()))
        self.assertEqual(summary["name"], "3 Stereo")
        self.assertEqual(len(summary["tracks"]), 4)
        self.assertEqual(len(summary["audioTracks"]), 3)
        self.assertEqual(summary["totalChannels"], 6)

    def test_a_file_that_is_not_a_preset_is_ignored(self):
        path = os.path.join(self.settings, "อื่น.rolepreset")
        write_plist(path, {"name": "ไม่ใช่ preset"})
        self.assertIsNone(rp.read_role_preset(path))

    def test_finds_preset_files_by_extension(self):
        self.write_preset(three_stereo_preset())
        found = rp.find_role_presets(self.roots())
        self.assertEqual(len(found), 1)
        self.assertTrue(found[0].endswith(".rolepreset"))

    def test_correct_preset_reports_no_problem(self):
        summary = rp.read_role_preset(self.write_preset(three_stereo_preset()))
        self.assertEqual(rp.check_role_preset(summary), [])

    def test_missing_audio_track_is_reported(self):
        data = three_stereo_preset()
        data["outputs"] = data["outputs"][:3]
        summary = rp.read_role_preset(self.write_preset(data))
        problems = rp.check_role_preset(summary)
        self.assertTrue(any("2 แทร็ก" in problem for problem in problems))

    def test_mono_track_is_reported(self):
        data = three_stereo_preset()
        data["outputs"][2]["audioChannelLayout"] = (100 << 16) | 1
        summary = rp.read_role_preset(self.write_preset(data))
        problems = rp.check_role_preset(summary)
        self.assertTrue(any("แทร็กที่ 2" in problem and "1 ช่อง" in problem
                            for problem in problems))

    def test_dropped_role_is_reported(self):
        data = three_stereo_preset()
        data["outputs"][3]["roles"] = [{"name": "All Dialogue"}]
        summary = rp.read_role_preset(self.write_preset(data))
        problems = rp.check_role_preset(summary)
        self.assertTrue(any("ขาด" in problem for problem in problems))

    def test_description_does_not_claim_the_video_track_has_channels(self):
        summary = rp.read_role_preset(self.write_preset(three_stereo_preset()))
        first = rp.describe_role_preset(summary)[2]
        self.assertIn("ภาพ", first)
        self.assertNotIn("ช่อง", first)

    def test_description_states_six_channels(self):
        summary = rp.read_role_preset(self.write_preset(three_stereo_preset()))
        text = "\n".join(rp.describe_role_preset(summary, []))
        self.assertIn("3 แทร็ก เป็นเสียง 6 ช่อง", text)
        self.assertIn("ตรงกับที่ห้องข่าวต้องการ", text)

    def test_install_puts_the_file_beside_the_others(self):
        self.write_preset(three_stereo_preset())
        spare = os.path.join(self.home, "สำรอง.rolepreset")
        write_plist(spare, three_stereo_preset())
        destination, message = rp.install_role_preset(spare, self.roots())
        self.assertIsNotNone(destination, message)
        self.assertEqual(os.path.dirname(destination), self.settings)

    def test_install_keeps_the_previous_file(self):
        original = self.write_preset(three_stereo_preset())
        write_plist(os.path.join(self.home, "3 Stereo.rolepreset"), three_stereo_preset())
        rp.install_role_preset(os.path.join(self.home, "3 Stereo.rolepreset"), self.roots())
        leftovers = [n for n in os.listdir(os.path.dirname(original)) if "เดิม" in n]
        self.assertEqual(len(leftovers), 1)

    def test_install_without_any_preset_folder_explains_itself(self):
        spare = os.path.join(self.home, "สำรอง.rolepreset")
        write_plist(spare, three_stereo_preset())
        destination, message = rp.install_role_preset(spare, self.roots())
        self.assertIsNone(destination)
        self.assertIn("ไม่รู้ว่าต้องวางไว้ที่ไหน", message)

    def test_check_from_the_command_line(self):
        self.write_preset(three_stereo_preset())
        self.assertEqual(rp.main(["check", "3 Stereo",
                                  "--also-look-in", self.roots()[0]]), 0)

    def test_check_fails_for_a_broken_preset(self):
        data = three_stereo_preset()
        data["outputs"] = data["outputs"][:2]
        self.write_preset(data)
        self.assertEqual(rp.main(["check", "3 Stereo",
                                  "--also-look-in", self.roots()[0]]), 1)

    def test_check_of_an_unknown_name_fails(self):
        self.write_preset(three_stereo_preset())
        self.assertEqual(rp.main(["check", "ไม่มีชื่อนี้",
                                  "--also-look-in", self.roots()[0]]), 1)


class TestCollecting(Sandbox):
    """ปุ่มเก็บไฟล์ตั้งค่าต้องได้ของครบ และบอกที่มาไว้ด้วย"""

    def setUp(self):
        super().setUp()
        write_plist(os.path.join(self.settings, "3 Stereo.rolepreset"),
                    three_stereo_preset())
        write_plist(os.path.join(self.settings, "MXF-50.fcpdest"),
                    {"name": "MXF-50"})
        self.target = os.path.join(self.home, "รวมไฟล์")

    def test_finds_both_kinds_of_file(self):
        found = rp.find_by_extension(extra=[self.roots()[0]])
        names = sorted(os.path.basename(path) for path in found)
        self.assertIn("3 Stereo.rolepreset", names)
        self.assertIn("MXF-50.fcpdest", names)

    def test_plain_files_are_left_behind(self):
        found = rp.find_by_extension(extra=[self.roots()[0]])
        self.assertFalse(any(path.endswith("readme.txt") for path in found))

    def test_copies_them_into_one_folder(self):
        copied, paths = rp.collect_setting_files(self.target, [self.roots()[0]])
        self.assertGreaterEqual(copied, 2)
        self.assertEqual(len(paths), copied)
        gathered = os.listdir(self.target)
        self.assertIn("3 Stereo.rolepreset", gathered)
        self.assertIn("MXF-50.fcpdest", gathered)

    def test_writes_where_each_file_came_from(self):
        rp.collect_setting_files(self.target, [self.roots()[0]])
        index = os.path.join(self.target, "ไฟล์เหล่านี้มาจากไหน.txt")
        with open(index, encoding="utf-8") as handle:
            self.assertIn(self.settings, handle.read())

    def test_same_name_in_two_folders_keeps_both(self):
        other = os.path.join(self.roots()[0], "อีกที่")
        write_plist(os.path.join(other, "MXF-50.fcpdest"), {"name": "MXF-50 อีกอัน"})
        rp.collect_setting_files(self.target, [self.roots()[0]])
        gathered = [n for n in os.listdir(self.target) if n.startswith("MXF-50")]
        self.assertEqual(len(gathered), 2)

    def test_the_original_files_are_not_moved(self):
        rp.collect_setting_files(self.target, [self.roots()[0]])
        self.assertTrue(os.path.exists(os.path.join(self.settings, "MXF-50.fcpdest")))

    def test_command_line_collect(self):
        self.assertEqual(rp.main(["collect", self.target,
                                  "--also-look-in", self.roots()[0]]), 0)
        self.assertTrue(os.path.isdir(self.target))


class TestCollectingEverything(Sandbox):
    """
    เก็บทั้งโฟลเดอร์ ไม่เลือกเฉพาะนามสกุล

    รอบแรกเราเก็บเฉพาะนามสกุลที่คาดไว้ แล้วได้มาไฟล์เดียว
    ไฟล์ของปลายทางไม่เจอเลย แปลว่าการเดานามสกุลผิด
    เมื่อเดาไม่ถูก ก็ไม่ต้องเดา เก็บมาทั้งโฟลเดอร์เลย
    """

    def setUp(self):
        super().setUp()
        self.presets = os.path.join(self.home, "ProApps", "Export Presets")
        write_plist(os.path.join(self.presets, "3 Stereo.rolepreset"),
                    three_stereo_preset())
        self.prefs = os.path.join(self.home, "Preferences")
        os.makedirs(self.prefs, exist_ok=True)
        for name in ("com.apple.FinalCut.plist", "com.example.other.plist"):
            with open(os.path.join(self.prefs, name), "w", encoding="utf-8") as handle:
                handle.write("x")
        self.target = os.path.join(self.home, "เก็บทั้งหมด")

    def collect(self):
        return rp.collect_everything(self.target, [self.roots()[0], self.prefs])

    def gathered(self):
        names = []
        for current, _dirs, files in os.walk(self.target):
            for name in files:
                names.append(os.path.relpath(os.path.join(current, name), self.target))
        return names

    def test_takes_files_of_every_extension(self):
        self.collect()
        names = self.gathered()
        self.assertTrue(any(n.endswith("3 Stereo.rolepreset") for n in names))
        self.assertTrue(any(n.endswith("readme.txt") for n in names))

    def test_keeps_the_folder_shape(self):
        self.collect()
        self.assertTrue(any(os.path.join("Export Presets", "3 Stereo.rolepreset") in n
                            for n in self.gathered()))

    def test_takes_only_final_cut_preferences(self):
        self.collect()
        names = self.gathered()
        self.assertTrue(any("com.apple.FinalCut.plist" in n for n in names))
        self.assertFalse(any("com.example.other.plist" in n for n in names))

    def test_skips_files_that_are_too_big(self):
        big = os.path.join(self.presets, "ใหญ่เกิน.plist")
        with open(big, "wb") as handle:
            handle.write(b"x" * (rp.MAX_COLLECT_BYTES + 1))
        self.collect()
        self.assertFalse(any("ใหญ่เกิน" in n for n in self.gathered()))

    def test_writes_where_each_folder_came_from(self):
        self.collect()
        with open(os.path.join(self.target, "ไฟล์เหล่านี้มาจากไหน.txt"),
                  encoding="utf-8") as handle:
            self.assertIn(self.roots()[0], handle.read())

    def test_originals_are_untouched(self):
        self.collect()
        self.assertTrue(os.path.exists(os.path.join(self.presets, "3 Stereo.rolepreset")))

    def test_command_line_collectall(self):
        self.assertEqual(rp.main(["collectall", self.target,
                                  "--also-look-in", self.roots()[0]]), 0)


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
