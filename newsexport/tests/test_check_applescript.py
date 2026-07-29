#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ชุดทดสอบของตัวตรวจ AppleScript
รันด้วย:  python3 tests/test_check_applescript.py

ตัวตรวจนี้เกิดขึ้นเพราะโปรแกรมเคยเปิดไม่ขึ้นในมือผู้ใช้
สาเหตุคือบรรทัด  set note to "..."  ซึ่ง note เป็นคำสงวน
ชุดทดสอบนี้จึงต้องพิสูจน์ว่าตัวตรวจจับกรณีนั้นได้จริง
"""

import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "tools"))

import check_applescript as ca  # noqa: E402

APP_SCRIPT = os.path.join(HERE, "..", "app", "แยกงานข่าว.app",
                          "Contents", "Resources", "main.applescript")


def messages(problems):
    return " | ".join(text for _line, text in problems)


class TestReservedWords(unittest.TestCase):
    """คำสงวนคือสาเหตุที่ทำให้โปรแกรมเปิดไม่ขึ้นมาแล้วครั้งหนึ่ง"""

    def test_catches_the_bug_that_broke_the_app(self):
        lines = ['\tset note to "บันทึกแล้ว"']
        self.assertIn("note", messages(ca.check_reserved_names(lines)))

    def test_catches_it_in_a_handler_parameter(self):
        lines = ['on stepBar(doneCount, totalCount, note)']
        self.assertIn("พารามิเตอร์", messages(ca.check_reserved_names(lines)))

    def test_catches_it_in_a_loop_counter(self):
        lines = ['\trepeat with item from 1 to 3']
        self.assertIn("ตัวนับ", messages(ca.check_reserved_names(lines)))

    def test_allows_a_safe_name(self):
        lines = ['\tset savedNote to "บันทึกแล้ว"',
                 'on stepBar(doneCount, totalCount, noteText)']
        self.assertEqual(ca.check_reserved_names(lines), [])

    def test_a_reserved_word_inside_a_name_is_fine(self):
        """noteText มีคำว่า note อยู่ข้างใน แต่ไม่ใช่คำสงวน ห้ามเตือน"""
        lines = ['\tset noteText to "ข้อความ"', '\tset currentValue to 1']
        self.assertEqual(ca.check_reserved_names(lines), [])

    def test_a_reserved_word_in_a_comment_is_ignored(self):
        lines = ['\t-- set note to "ตัวอย่างในคอมเมนต์"']
        self.assertEqual(ca.check_reserved_names(lines), [])


class TestBlocks(unittest.TestCase):
    """เปิดปิดบล็อกไม่ครบ ทำให้คอมไพล์ไม่ผ่านเช่นกัน"""

    def test_missing_end_is_reported(self):
        lines = ['on ทำงาน()', '\tset a to 1']
        self.assertIn("ไม่มี end", messages(ca.check_blocks(lines)))

    def test_extra_end_is_reported(self):
        lines = ['set a to 1', 'end try']
        self.assertIn("end เกินมา", messages(ca.check_blocks(lines)))

    def test_balanced_blocks_pass(self):
        lines = ['on ทำงาน()', '\ttry', '\t\tset a to 1', '\ton error e',
                 '\tend try', 'end ทำงาน']
        self.assertEqual(ca.check_blocks(lines), [])

    def test_one_line_if_needs_no_end(self):
        lines = ['on ทำงาน()', '\tif a is "" then return', 'end ทำงาน']
        self.assertEqual(ca.check_blocks(lines), [])

    def test_one_line_tell_needs_no_end(self):
        lines = ['on ทำงาน()', '\ttell application "Finder" to activate',
                 'end ทำงาน']
        self.assertEqual(ca.check_blocks(lines), [])

    def test_a_handler_whose_name_starts_with_end_is_not_a_closing_line(self):
        """endProgressWindow ขึ้นต้นด้วย end แต่เป็นการเรียกฟังก์ชัน"""
        lines = ['on ทำงาน()', '\tendProgressWindow("จบ")', 'end ทำงาน']
        self.assertEqual(ca.check_blocks(lines), [])


class TestContinuations(unittest.TestCase):
    """เครื่องหมายขึ้นบรรทัดใหม่ที่มีอะไรต่อท้าย ทำให้พังทันที"""

    def test_trailing_space_after_the_mark(self):
        lines = ['\tdisplay dialog "ก" & ¬ ', '\t\t"ข"']
        self.assertIn("ช่องว่าง", messages(ca.check_continuations(lines)))

    def test_text_after_the_mark(self):
        lines = ['\tdisplay dialog "ก" & ¬ เพิ่ม', '\t\t"ข"']
        self.assertIn("ตัวอักษร", messages(ca.check_continuations(lines)))

    def test_comment_on_the_next_line(self):
        lines = ['\tdisplay dialog "ก" & ¬', '\t-- คอมเมนต์']
        self.assertIn("คอมเมนต์", messages(ca.check_continuations(lines)))

    def test_a_proper_continuation_passes(self):
        lines = ['\tdisplay dialog "ก" & ¬', '\t\t"ข"']
        self.assertEqual(ca.check_continuations(lines), [])


class TestCalls(unittest.TestCase):
    """เรียกฟังก์ชันที่ไม่มีอยู่จริง ก็พังตอนใช้งาน"""

    def test_unknown_call_is_reported(self):
        text = 'on doThing()\n\tcallSomethingMissing()\nend doThing'
        self.assertIn("ไม่มีฟังก์ชัน", messages(ca.check_calls(text)))

    def test_duplicate_handler_is_reported(self):
        text = 'on doThing()\nend doThing\non doThing()\nend doThing'
        self.assertIn("ซ้ำกัน", messages(ca.check_calls(text)))

    def test_builtin_calls_are_allowed(self):
        text = 'on doThing()\n\tset a to count(b)\nend doThing'
        self.assertEqual(ca.check_calls(text), [])


class TestTheRealScript(unittest.TestCase):
    """ไฟล์จริงที่จะส่งให้ผู้ใช้ ต้องผ่านทุกข้อ"""

    def test_the_shipped_script_passes(self):
        problems = ca.check_file(APP_SCRIPT)
        self.assertEqual(problems, [], messages(problems))

    def test_the_checker_returns_zero_for_it(self):
        self.assertEqual(ca.main([APP_SCRIPT]), 0)


if __name__ == "__main__":
    result = unittest.main(exit=False, verbosity=1).result
    if result.wasSuccessful():
        print("ผ่านทั้งหมด")
    else:
        sys.exit(1)
