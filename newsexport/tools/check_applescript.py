#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ตรวจไฟล์ AppleScript ก่อนส่งให้ผู้ใช้

ทำไมต้องมีตัวนี้
----------------
ผู้พัฒนาไม่มีเครื่อง Mac จึงคอมไพล์ AppleScript ล่วงหน้าไม่ได้
ที่ผ่านมาจึงมีความผิดพลาดหลุดไปถึงมือผู้ใช้ และโปรแกรมเปิดไม่ขึ้นเลย

ครั้งล่าสุดสาเหตุคือบรรทัดนี้
    set note to "บันทึกแล้ว ..."
คำว่า note เป็นคำที่ AppleScript จองไว้ใช้เอง เอามาตั้งเป็นชื่อตัวแปรไม่ได้
ข้อความที่เครื่องผู้ใช้ขึ้นคือ Can't set note to ... Access not allowed

ความผิดพลาดแบบนี้ตรวจได้ด้วยการอ่านโค้ดล้วน ๆ ไม่ต้องมีเครื่อง Mac
ตัวนี้จึงตรวจให้ทุกครั้งก่อนส่ง

สิ่งที่ตรวจ
-----------
1. ชื่อตัวแปรหรือชื่อพารามิเตอร์ ที่ไปชนกับคำสงวนของ AppleScript
2. การเปิดปิดบล็อกครบคู่ไหม เช่น on กับ end  if กับ end if
3. เรียกฟังก์ชันที่ไม่มีอยู่จริงไหม
4. เครื่องหมายขึ้นบรรทัดใหม่ ¬ มีอะไรต่อท้ายไหม ซึ่งทำให้พังทันที
"""

import argparse
import collections
import os
import re
import sys

# คำที่ AppleScript กับ Standard Additions จองไว้ใช้เอง
# เอามาตั้งเป็นชื่อตัวแปรไม่ได้ จะขึ้นว่า Access not allowed
#
# รายการนี้ไม่ได้ครบทุกคำในภาษา แต่เก็บคำที่คนมักเผลอใช้เป็นชื่อตัวแปร
RESERVED_WORDS = {
    "note", "result", "text", "string", "count", "length", "name", "id",
    "class", "item", "items", "list", "record", "date", "time", "day",
    "month", "year", "weekday", "seconds", "minutes", "hours",
    "file", "path", "folder", "alias", "application", "window", "document",
    "character", "characters", "word", "words", "paragraph", "paragraphs",
    "version", "size", "bounds", "contents", "value", "index", "state",
    "color", "data", "space", "tab", "return", "quote", "linefeed",
    "front", "back", "beginning", "end", "middle", "some", "every",
    "current", "container", "properties", "selection", "point",
    "reference", "script", "error", "message", "number", "info",
    "position", "title", "button", "buttons", "icon", "type",
}

# รูปแบบที่ถือว่าเป็นการตั้งชื่อตัวแปร
ASSIGNMENT = re.compile(r'^\s*set\s+([A-Za-z_][A-Za-z0-9_]*)\s+to\b')
HANDLER = re.compile(r'^on\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)')
REPEAT_WITH = re.compile(r'^\s*repeat\s+with\s+([A-Za-z_][A-Za-z0-9_]*)\b')

# คำที่ขึ้นต้นบล็อก ต้องมี end คู่กันเสมอ
BLOCK_STARTS = (
    # ชื่อฟังก์ชันเป็นภาษาอะไรก็ได้ AppleScript ไม่ได้จำกัดไว้แค่อังกฤษ
    (re.compile(r'^on\s+\S'), "on"),
    (re.compile(r'^if\b'), "if"),
    (re.compile(r'^repeat\b'), "repeat"),
    (re.compile(r'^try\b'), "try"),
    (re.compile(r'^tell\b'), "tell"),
    (re.compile(r'^with timeout\b'), "with timeout"),
)

# ชื่อที่เรียกได้โดยไม่ต้องนิยามเอง เพราะเป็นของภาษาหรือของระบบ
BUILTIN_CALLS = {
    "my", "display", "count", "item", "offset", "paragraphs", "text",
    "do", "round", "set", "quoted", "open", "close", "write", "read",
}


def strip_comment(line):
    """ตัดคอมเมนต์ท้ายบรรทัดออก โดยไม่ตัดที่อยู่ในเครื่องหมายคำพูด"""
    inside = False
    for index, character in enumerate(line):
        if character == '"' and (index == 0 or line[index - 1] != "\\"):
            inside = not inside
        if not inside and line[index:index + 2] == "--":
            return line[:index]
    return line


def check_reserved_names(lines):
    """หาชื่อตัวแปรหรือพารามิเตอร์ที่ชนกับคำสงวน"""
    problems = []
    for number, line in enumerate(lines, start=1):
        code = strip_comment(line)

        match = ASSIGNMENT.match(code)
        if match and match.group(1).lower() in RESERVED_WORDS:
            problems.append((number, "ตั้งชื่อตัวแปรว่า %s ไม่ได้ เป็นคำสงวน"
                             % match.group(1)))

        match = REPEAT_WITH.match(code)
        if match and match.group(1).lower() in RESERVED_WORDS:
            problems.append((number, "ตั้งชื่อตัวนับว่า %s ไม่ได้ เป็นคำสงวน"
                             % match.group(1)))

        match = HANDLER.match(code)
        if match:
            for parameter in match.group(2).split(","):
                parameter = parameter.strip()
                if parameter and parameter.lower() in RESERVED_WORDS:
                    problems.append((number, "ตั้งชื่อพารามิเตอร์ว่า %s ไม่ได้ เป็นคำสงวน"
                                     % parameter))
    return problems


def check_blocks(lines):
    """ตรวจว่าเปิดปิดบล็อกครบคู่"""
    problems = []
    stack = []
    for number, line in enumerate(lines, start=1):
        code = strip_comment(line).strip()
        if not code:
            continue

        # ต้องเป็นคำว่า end เต็มคำ ไม่ใช่ชื่อฟังก์ชันที่ขึ้นต้นด้วย end
        # เช่น endProgressWindow ไม่ใช่การปิดบล็อก
        if re.match(r"^end\b", code):
            if not stack:
                problems.append((number, "มี end เกินมา"))
            else:
                stack.pop()
            continue

        if code.startswith("on error"):
            continue

        for pattern, kind in BLOCK_STARTS:
            if not pattern.match(code):
                continue
            # if ที่จบในบรรทัดเดียว ไม่ต้องมี end if
            if kind == "if" and re.search(r'\bthen\s+\S', code):
                break
            # tell ที่สั่งงานในบรรทัดเดียว ไม่ต้องมี end tell
            if kind == "tell" and re.search(r'\bto\s+\S', code):
                break
            stack.append((kind, number))
            break

    for kind, number in stack:
        problems.append((number, "บล็อก %s ไม่มี end ปิด" % kind))
    return problems


def check_continuations(lines):
    """ตรวจว่าหลังเครื่องหมาย ¬ ไม่มีอะไรต่อท้าย"""
    problems = []
    for number, line in enumerate(lines, start=1):
        if "¬" not in line:
            continue
        after = line.split("¬", 1)[1]
        if after.strip():
            problems.append((number, "มีตัวอักษรต่อท้าย ¬"))
        elif after:
            problems.append((number, "มีช่องว่างต่อท้าย ¬"))
        if number < len(lines):
            following = lines[number].strip()
            if not following or following.startswith("--"):
                problems.append((number, "บรรทัดหลัง ¬ ว่างหรือเป็นคอมเมนต์"))
    return problems


def check_calls(text):
    """
    ตรวจว่าเรียกฟังก์ชันที่มีอยู่จริง และไม่มีฟังก์ชันชื่อซ้ำ

    ดูเฉพาะชื่อที่เป็นตัวอักษรอังกฤษ เพราะโปรแกรมนี้ตั้งชื่อฟังก์ชันแบบนั้นทั้งหมด
    ชื่อภาษาอื่นจะถูกข้ามไป ไม่ใช่ถือว่าผิด
    """
    problems = []
    defined = re.findall(r'^on\s+([A-Za-z_][A-Za-z0-9_]*)', text, re.M)
    called = collections.Counter(re.findall(r'\b([a-z][A-Za-z0-9_]*)\(', text))

    for name in sorted(set(called) - set(defined) - BUILTIN_CALLS):
        problems.append((0, "เรียก %s แต่ไม่มีฟังก์ชันชื่อนี้" % name))

    duplicates = [name for name, times in collections.Counter(defined).items()
                  if times > 1]
    for name in sorted(duplicates):
        problems.append((0, "มีฟังก์ชันชื่อ %s ซ้ำกัน" % name))
    return problems


def check_file(path):
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    lines = text.split("\n")

    problems = []
    problems.extend(check_reserved_names(lines))
    problems.extend(check_blocks(lines))
    problems.extend(check_continuations(lines))
    problems.extend(check_calls(text))
    problems.sort(key=lambda row: row[0])
    return problems


def main(argv=None):
    parser = argparse.ArgumentParser(description="ตรวจไฟล์ AppleScript ก่อนส่ง")
    parser.add_argument("files", nargs="+", help="ไฟล์ที่จะตรวจ")
    args = parser.parse_args(argv)

    total = 0
    for path in args.files:
        if not os.path.isfile(path):
            print("ไม่พบไฟล์ %s" % path, file=sys.stderr)
            return 2
        problems = check_file(path)
        total += len(problems)
        if not problems:
            print("ผ่าน  %s" % os.path.basename(path))
            continue
        print("พบปัญหาใน %s" % path)
        for number, message in problems:
            where = "บรรทัด %d" % number if number else "ทั้งไฟล์"
            print("  %s  %s" % (where, message))

    return 0 if total == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
