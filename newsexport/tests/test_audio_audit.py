#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ชุดทดสอบของตัวตรวจเสียง
รันด้วย:  python3 tests/test_audio_audit.py

เรื่องที่ต้องมั่นใจ
- นับช่องเสียงของแต่ละก้อนได้ถูก
- จับได้เมื่อก้อนใดก้อนหนึ่งเสียงไม่ครบ
- ก้อนที่เสียงครบต้องไม่ถูกเตือนผิด ๆ
"""

import os
import sys
import unittest
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "tools"))

import audio_audit as aa  # noqa: E402

# หกช่องเสียงแบบที่ห้องข่าวใช้จริง แยกกันช่องละ Role
SIX_MONO = ["dialogue.Dialogue-%d" % n for n in range(1, 7)]


def clip(offset, duration, roles, name="คลิป"):
    """
    สร้างคลิปหนึ่งชิ้นที่ถือ Role ของเสียงตามที่กำหนด
    เขียนเหมือนของจริง คือ audioRole อยู่บนคลิป
    และช่องเสียงย่อยอยู่ใน audio-channel-source
    """
    parts = []
    parts.append('<asset-clip ref="r2" offset="%d/25s" name="%s" start="0s" '
                 'duration="%d/25s" format="r1" audioRole="%s">'
                 % (offset, name, duration, roles[0]))
    for number, role in enumerate(roles, start=1):
        parts.append('<audio-channel-source srcCh="%d" role="%s"/>' % (number, role))
    parts.append('</asset-clip>')
    return "".join(parts)


def gap(offset, duration):
    return '<gap name="Gap" offset="%d/25s" start="0s" duration="%d/25s"/>' % (offset, duration)


def timeline(spine_xml, total):
    """ห่อ spine ให้เป็นไฟล์ FCPXML ที่สมบูรณ์"""
    return ET.ElementTree(ET.fromstring(
        '<fcpxml version="1.11">'
        '<resources>'
        '<format id="r1" name="FFVideoFormat1080p25" frameDuration="100/2500s"'
        ' width="1920" height="1080"/>'
        '<asset id="r2" name="A001" start="0s" duration="3600s" hasVideo="1"'
        ' hasAudio="1" format="r1" audioSources="1" audioChannels="6"/>'
        '</resources>'
        '<library>'
        '<event name="ทดสอบ">'
        '<project name="ข่าวเช้า-">'
        '<sequence format="r1" duration="%d/25s" tcStart="0s" tcFormat="NDF"'
        ' audioLayout="stereo" audioRate="48k">'
        '<spine>%s</spine>'
        '</sequence>'
        '</project>'
        '</event>'
        '</library>'
        '</fcpxml>' % (total, spine_xml)))


class TestCounting(unittest.TestCase):
    """การนับช่องเสียงต้องตรงกับที่เขียนไว้ในไฟล์"""

    def test_reads_every_subrole_of_a_clip(self):
        element = ET.fromstring(clip(0, 100, SIX_MONO))
        self.assertEqual(aa.collect_roles(element), set(SIX_MONO))

    def test_one_field_may_hold_several_roles(self):
        self.assertEqual(aa.split_role_list("dialogue.D-1, dialogue.D-2"),
                         ["dialogue.D-1", "dialogue.D-2"])

    def test_video_roles_are_not_counted_as_audio(self):
        element = ET.fromstring('<asset-clip ref="r2" videoRole="titles"/>')
        self.assertEqual(aa.collect_roles(element), set())

    def test_role_on_a_plain_audio_layer_counts(self):
        element = ET.fromstring('<clip><audio role="music.music-1" ref="r2"/></clip>')
        self.assertEqual(aa.collect_roles(element), {"music.music-1"})


class TestAudit(unittest.TestCase):
    """ตรวจทั้งไทม์ไลน์แล้วต้องชี้ได้ว่าก้อนไหนมีปัญหา"""

    def full_timeline(self):
        spine = (clip(0, 200, SIX_MONO, "ก้อน1")
                 + gap(200, 50)
                 + clip(250, 200, SIX_MONO, "ก้อน2")
                 + gap(450, 50)
                 + clip(500, 200, SIX_MONO, "ก้อน3"))
        return timeline(spine, 700)

    def broken_timeline(self):
        """ก้อนกลางมีเสียงแค่สองช่อง"""
        spine = (clip(0, 200, SIX_MONO, "ก้อน1")
                 + gap(200, 50)
                 + clip(250, 200, SIX_MONO[:2], "ก้อน2")
                 + gap(450, 50)
                 + clip(500, 200, SIX_MONO, "ก้อน3"))
        return timeline(spine, 700)

    def test_all_blocks_have_six_channels(self):
        results, expected, _fps = aa.audit(self.full_timeline(), 0.2)
        self.assertEqual(len(results), 3)
        self.assertEqual(len(expected), 6)
        for row in results:
            self.assertTrue(row["enough"], row)
            self.assertEqual(len(row["roles"]), 6)

    def test_requiring_six_passes_when_there_are_six(self):
        results, _expected, _fps = aa.audit(self.full_timeline(), 0.2, require=6)
        self.assertTrue(all(row["enough"] for row in results))

    def test_a_requirement_nobody_can_meet_is_ignored(self):
        """
        เกณฑ์ที่สูงกว่าจำนวน Role ทั้งไทม์ไลน์ ทำให้ทุกก้อนตกหมด
        แบบนั้นแปลว่าเกณฑ์ผิด ไม่ใช่งานผิด จึงต้องมองข้ามเกณฑ์นั้นไป

        เคยเกิดขึ้นจริง ตอนที่ค่าเริ่มต้นถูกตั้งไว้ที่หก Role ต่อก้อน
        ทั้งที่งานจริงใช้อยู่หกตัวไม่ถึง ผู้ใช้จึงโดนเตือนทุกก้อนทุกวัน
        """
        results, _expected, _fps = aa.audit(self.full_timeline(), 0.2, require=7)
        self.assertTrue(all(row["enough"] for row in results))

    def test_a_requirement_that_fits_still_applies(self):
        spine = (clip(0, 200, SIX_MONO, "ก้อน1")
                 + gap(200, 50)
                 + clip(250, 200, SIX_MONO, "ก้อน2"))
        results, _expected, _fps = aa.audit(timeline(spine, 450), 0.2, require=6)
        self.assertTrue(all(row["enough"] for row in results))

    def test_effective_require_drops_an_impossible_bar(self):
        self.assertIsNone(aa.effective_require(["a", "b"], 6))

    def test_effective_require_keeps_a_reachable_bar(self):
        self.assertEqual(aa.effective_require(["a", "b", "c"], 3), 3)

    def test_effective_require_without_any_role_is_off(self):
        self.assertIsNone(aa.effective_require([], 6))

    def test_command_line_does_not_fail_on_an_impossible_bar(self):
        """
        นี่คือกรณีที่ผู้ใช้เจอจริง ทุกก้อนถูกเตือนพร้อมกันหมด
        รหัสจบต้องเป็นศูนย์ แอปจะได้ไม่ขึ้นหน้าต่างเตือนโดยไม่จำเป็น
        """
        path = os.path.join(HERE, "ทดสอบเกณฑ์ชั่วคราว.fcpxml")
        spine = (clip(0, 200, SIX_MONO[:2]) + gap(200, 50)
                 + clip(250, 200, SIX_MONO[:2]))
        timeline(spine, 450).write(path, encoding="utf-8", xml_declaration=True)
        try:
            self.assertEqual(aa.main([path, "--require", "6", "--brief"]), 0)
        finally:
            os.remove(path)

    def test_finds_the_block_that_is_short(self):
        results, expected, _fps = aa.audit(self.broken_timeline(), 0.2)
        self.assertEqual(len(expected), 6)
        self.assertTrue(results[0]["enough"])
        self.assertFalse(results[1]["enough"])
        self.assertTrue(results[2]["enough"])
        self.assertEqual(results[1]["missing"], sorted(SIX_MONO[2:]))

    def test_block_numbers_follow_the_timeline_order(self):
        results, _expected, _fps = aa.audit(self.broken_timeline(), 0.2)
        self.assertEqual([row["index"] for row in results], [1, 2, 3])
        self.assertTrue(results[1]["name"].endswith("-2"))

    def test_timeline_without_any_audio_role_never_passes(self):
        spine = ('<asset-clip ref="r2" offset="0/25s" name="เงียบ" start="0s"'
                 ' duration="200/25s" format="r1"/>')
        results, expected, _fps = aa.audit(timeline(spine, 200), 0.2)
        self.assertEqual(expected, [])
        self.assertFalse(results[0]["enough"])


class TestReport(unittest.TestCase):
    """ข้อความที่ผู้ใช้เห็นต้องบอกความจริงตรง ๆ"""

    def build(self, tree, require=None):
        results, expected, _fps = aa.audit(tree, 0.2, require)
        return results, expected

    def test_brief_says_all_good(self):
        spine = clip(0, 200, SIX_MONO) + gap(200, 50) + clip(250, 200, SIX_MONO)
        results, expected = self.build(timeline(spine, 450))
        self.assertIn("ครบทุกก้อน", aa.brief(results, expected))

    def test_brief_without_a_bar_says_it_differs_from_the_others(self):
        """
        ไม่ได้ตั้งเกณฑ์จำนวนไว้ ข้อความต้องไม่พูดว่า ต้องได้ก้อนละเท่าไร
        เพราะไม่มีเกณฑ์ตายตัวอยู่จริง มาตรฐานมาจากก้อนอื่นในงานเดียวกัน
        """
        spine = (clip(0, 200, SIX_MONO) + gap(200, 50)
                 + clip(250, 200, SIX_MONO[:2]))
        results, expected = self.build(timeline(spine, 450))
        summary = aa.brief(results, expected)
        self.assertIn("ไม่เหมือนก้อนอื่น", summary)
        self.assertIn("ก้อนอื่นมี 6 Role", summary)
        self.assertNotIn("ต้องได้ก้อนละ", summary)

    def test_brief_names_the_bad_blocks(self):
        spine = (clip(0, 200, SIX_MONO) + gap(200, 50)
                 + clip(250, 200, SIX_MONO[:2]))
        results, expected = self.build(timeline(spine, 450))
        summary = aa.brief(results, expected, 6)
        self.assertIn("ก้อนที่ 2", summary)
        self.assertIn("6 Role", summary)

    def test_report_states_the_three_stereo_layout(self):
        """ผู้ใช้ต้องเห็นชัดว่าไฟล์ได้สามแทร็กเสมอ ไม่ว่าก้อนนั้นเสียงครบไหม"""
        spine = (clip(0, 200, SIX_MONO) + gap(200, 50)
                 + clip(250, 200, SIX_MONO[:2]))
        results, expected = self.build(timeline(spine, 450))
        text = "\n".join(aa.format_report(results, expected))
        self.assertIn("3 Stereo", text)
        self.assertIn("สามแทร็ก", text)
        self.assertIn("เงียบ", text)
        self.assertNotIn("ช่องเสียงน้อยกว่าก้อนอื่น", text)

    def test_report_lists_the_missing_roles(self):
        spine = (clip(0, 200, SIX_MONO) + gap(200, 50)
                 + clip(250, 200, SIX_MONO[:2]))
        results, expected = self.build(timeline(spine, 450))
        text = "\n".join(aa.format_report(results, expected))
        self.assertIn("ขาด", text)
        self.assertIn("dialogue.Dialogue-6", text)

    def test_report_of_a_silent_timeline_does_not_claim_success(self):
        spine = ('<asset-clip ref="r2" offset="0/25s" name="เงียบ" start="0s"'
                 ' duration="200/25s" format="r1"/>')
        results, expected = self.build(timeline(spine, 200))
        text = "\n".join(aa.format_report(results, expected))
        self.assertNotIn("ทุกก้อนเสียงครบเท่ากันหมด", text)
        self.assertIn("ไม่พบช่องเสียง", text)


class TestExitCode(unittest.TestCase):
    """แอปอ่านผลจากรหัสจบของโปรแกรม จึงต้องถูกต้องเสมอ"""

    def setUp(self):
        self.path = os.path.join(HERE, "ทดสอบเสียงชั่วคราว.fcpxml")

    def tearDown(self):
        if os.path.exists(self.path):
            os.remove(self.path)

    def write(self, spine, total):
        timeline(spine, total).write(self.path, encoding="utf-8", xml_declaration=True)

    def test_zero_when_every_block_is_complete(self):
        self.write(clip(0, 200, SIX_MONO) + gap(200, 50) + clip(250, 200, SIX_MONO), 450)
        self.assertEqual(aa.main([self.path, "--require", "6", "--brief"]), 0)

    def test_one_when_a_block_is_short(self):
        self.write(clip(0, 200, SIX_MONO) + gap(200, 50) + clip(250, 200, SIX_MONO[:2]), 450)
        self.assertEqual(aa.main([self.path, "--require", "6", "--brief"]), 1)

    def test_two_when_the_file_cannot_be_read(self):
        self.assertEqual(aa.main([os.path.join(HERE, "ไม่มีไฟล์นี้.fcpxml")]), 2)


if __name__ == "__main__":
    result = unittest.main(exit=False, verbosity=1).result
    if result.wasSuccessful():
        print("ผ่านทั้งหมด")
    else:
        sys.exit(1)
