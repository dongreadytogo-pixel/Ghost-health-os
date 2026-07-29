#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ตรวจเสียงของแต่ละก้อน ก่อนสั่งเอ็กพอร์ต

ทำไมต้องมีตัวนี้
----------------
ไฟล์ MXF-50 ต้องมีเสียงครบทุกช่อง เช่น หกช่องแยกกัน
จำนวนช่องเสียงในไฟล์ที่ได้ ไม่ได้มาจากการตั้งค่าอย่างเดียว
แต่มาจากว่า ในก้อนนั้นมีเสียงของ Role ไหนอยู่บ้าง

Final Cut Pro สร้างช่องเสียงให้เฉพาะ Role ที่มีของอยู่จริงในงานนั้น
ถ้าก้อนที่สามไม่มีคลิปที่ใช้ Dialogue-5 เลย
ไฟล์ของก้อนที่สามก็จะขาดช่องนั้นไป ทั้งที่ตั้งค่าไว้ถูกต้องแล้ว

ตัวนี้จึงตรวจให้เห็นก่อนเอ็กพอร์ต ว่าก้อนไหนเสียงไม่ครบ
จะได้รู้ตั้งแต่ต้น ไม่ต้องรอไฟล์เสร็จแล้วมานั่งไล่เปิดทีละไฟล์

หลักการวัดว่า ครบ คืออะไร
--------------------------
ไม่เดาชื่อ Role เอง แต่ดูจากไทม์ไลน์จริงว่ามี Role อะไรบ้างทั้งเส้น
รายการนั้นคือมาตรฐานของงานชิ้นนี้
ก้อนไหนมีไม่ครบตามรายการนั้น ถือว่าเสียงไม่ครบ

ถ้าอยากกำหนดจำนวนขั้นต่ำเองก็ได้ ด้วย --require
เช่น --require 6 แปลว่าทุกก้อนต้องมีอย่างน้อยหกช่องเสียง
"""

import argparse
import os
import sys
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from fcpxml_segments import resolve_input, segment_basename  # noqa: E402
import fcpxml_split as splitter  # noqa: E402

# ที่ที่ Role ของเสียงไปแอบอยู่ได้ในไฟล์ FCPXML
# audioRole อยู่บนตัวคลิป
# role อยู่บนช่องเสียงย่อยและบนเลเยอร์เสียงที่แยกออกมา
ROLE_ATTRIBUTES = ("audioRole", "role")

# แท็กที่ถือว่าเป็นของฝั่งเสียง
# ใช้กรองไม่ให้ Role ของภาพหลุดเข้ามาปน
AUDIO_TAGS = ("audio", "audio-channel-source", "audio-role-source")


def collect_roles(element):
    """
    เก็บชื่อ Role ของเสียงทั้งหมดที่อยู่ใต้ก้อนนี้
    คืนค่าเป็นชุดของชื่อ ไม่ซ้ำกัน
    """
    roles = set()
    for node in element.iter():
        for attribute in ROLE_ATTRIBUTES:
            value = node.get(attribute)
            if not value:
                continue
            if attribute == "audioRole" or node.tag in AUDIO_TAGS:
                roles.update(split_role_list(value))
    return roles


def split_role_list(value):
    """
    หนึ่งช่องอาจเขียนหลาย Role คั่นด้วยจุลภาค เช่น  dialogue.D-1, dialogue.D-2
    แยกออกมาเป็นชื่อละตัว และตัดช่องว่างหัวท้ายทิ้ง
    """
    return [part.strip() for part in value.split(",") if part.strip()]


def audit(tree, min_gap, require=None):
    """
    ตรวจทุกก้อน คืนค่าเป็น (รายการผลตรวจ, รายชื่อ Role มาตรฐาน)

    ผลตรวจแต่ละก้อนเป็น dict
      index    ลำดับก้อน
      name     ชื่อไฟล์ของก้อนนั้น
      roles    รายชื่อ Role ที่มีในก้อนนั้น
      missing  รายชื่อ Role ที่ขาดไปเทียบกับมาตรฐาน
      enough   ผ่านเกณฑ์ไหม
    """
    split_tree, details, fps, _warnings = splitter.split(tree, min_gap)
    root = split_tree.getroot()

    projects = root.findall(".//event/project")

    # มาตรฐานคือทุก Role ที่มีอยู่จริงในไทม์ไลน์ทั้งเส้น
    expected = set()
    for project in projects:
        expected |= collect_roles(project)

    results = []
    for index, project in enumerate(projects, start=1):
        roles = collect_roles(project)
        missing = sorted(expected - roles)
        # ไม่มี Role ของเสียงเลยทั้งไทม์ไลน์ ถือว่าไม่ผ่านทุกก้อน
        # เพราะงานข่าวที่ไม่มีเสียงเลย ย่อมไม่ใช่สิ่งที่ตั้งใจ
        enough = bool(expected) and not missing
        if require is not None:
            enough = enough and len(roles) >= require
        results.append({
            "index": index,
            "name": project.get("name") or segment_basename("งาน", index),
            "roles": sorted(roles),
            "missing": missing,
            "enough": enough,
        })
    return results, sorted(expected), fps


def format_report(results, expected, require=None):
    """เขียนผลตรวจเป็นข้อความไทยอ่านง่าย"""
    lines = []
    lines.append("ตรวจเสียงของแต่ละก้อน")
    lines.append("")
    if expected:
        lines.append("ช่องเสียงมาตรฐานของงานนี้ มี %d ช่อง" % len(expected))
        for name in expected:
            lines.append("  " + name)
    else:
        lines.append("ไม่พบ Role ของเสียงเลยในไทม์ไลน์นี้")
    if require is not None:
        lines.append("เกณฑ์ที่ตั้งไว้ ทุกก้อนต้องมีอย่างน้อย %d ช่อง" % require)
    lines.append("")

    short = [row for row in results if not row["enough"]]
    for row in results:
        mark = "ครบ" if row["enough"] else "ไม่ครบ"
        lines.append("ก้อนที่ %d  %s  %d ช่อง  %s"
                     % (row["index"], mark, len(row["roles"]), row["name"]))
        if row["missing"]:
            lines.append("        ขาด " + ", ".join(row["missing"]))
    lines.append("")

    if not expected:
        lines.append("ไม่พบช่องเสียงเลยแม้แต่ก้อนเดียว")
        lines.append("ไฟล์ MXF ที่ได้จะไม่มีเสียง ควรตรวจไทม์ไลน์ก่อนเอ็กพอร์ต")
    elif not short:
        lines.append("ทุกก้อนเสียงครบเท่ากันหมด")
    else:
        lines.append("มีก้อนที่เสียงไม่ครบ %d ก้อน" % len(short))
        lines.append("ก้อนเหล่านี้จะได้ไฟล์ MXF ที่ช่องเสียงน้อยกว่าก้อนอื่น")
        lines.append("เพราะ Final Cut Pro สร้างช่องเสียงให้เฉพาะ Role ที่มีของอยู่จริง")
        lines.append("วิธีแก้คือกลับไปใส่เสียงของ Role ที่ขาด ให้ครบในก้อนนั้นก่อน")
    return lines


def brief(results, expected, require=None):
    """สรุปสั้นบรรทัดเดียว สำหรับเอาไปแสดงในหน้าต่างของแอป"""
    short = [row for row in results if not row["enough"]]
    if not expected:
        return "ไม่พบช่องเสียงเลยในไทม์ไลน์นี้"

    # เกณฑ์ที่ใช้ตัดสิน คือค่าที่ตั้งไว้ ถ้าไม่ได้ตั้งก็ใช้จำนวนช่องของทั้งเส้น
    standard = require if require is not None else len(expected)
    if not short:
        return "เสียงครบทุกก้อน ก้อนละ %d ช่อง" % len(expected)
    names = ", ".join(str(row["index"]) for row in short[:8])
    if len(short) > 8:
        names += " และอื่น ๆ"
    return ("เสียงไม่ครบ %d ก้อน คือก้อนที่ %s  ต้องได้ก้อนละ %d ช่อง"
            % (len(short), names, standard))


def main(argv=None):
    parser = argparse.ArgumentParser(description="ตรวจว่าแต่ละก้อนมีช่องเสียงครบไหม")
    parser.add_argument("input", help="ไฟล์ fcpxml หรือ fcpxmld ของไทม์ไลน์ทั้งเส้น")
    parser.add_argument("--min-gap", type=float, default=0.2,
                        help="ช่องว่างกี่วินาทีจึงนับเป็นก้อนใหม่")
    parser.add_argument("--require", type=int, default=None,
                        help="ทุกก้อนต้องมีอย่างน้อยกี่ช่องเสียง")
    parser.add_argument("--brief", action="store_true", help="สรุปสั้นบรรทัดเดียว")
    args = parser.parse_args(argv)

    try:
        tree = ET.parse(resolve_input(args.input))
    except Exception as error:
        print("อ่านไฟล์ไม่ได้: %s" % error, file=sys.stderr)
        return 2

    try:
        results, expected, _fps = audit(tree, args.min_gap, args.require)
    except Exception as error:
        print("ตรวจไม่สำเร็จ: %s" % error, file=sys.stderr)
        return 2

    if args.brief:
        print(brief(results, expected, args.require))
    else:
        print("\n".join(format_report(results, expected, args.require)))

    # คืนค่า 1 เมื่อมีก้อนที่เสียงไม่ครบ เพื่อให้ฝั่งแอปรู้ว่าต้องเตือน
    return 0 if all(row["enough"] for row in results) else 1


if __name__ == "__main__":
    sys.exit(main())
