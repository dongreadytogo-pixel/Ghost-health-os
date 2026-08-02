#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ตรวจเสียงของแต่ละก้อน ก่อนสั่งเอ็กพอร์ต

รูปแบบเสียงที่ห้องข่าวนี้ส่งออกอากาศ
------------------------------------
ไฟล์ MXF-50 ใช้ preset ชื่อ 3 Stereo
ได้เสียงสามแทร็ก แทร็กละสองช่อง รวมหกช่อง
และทั้งสามแทร็กถูกตั้งให้รับ All Dialogue กับ All Effects กับ All Music เหมือนกัน

ข้อนี้สำคัญมาก เพราะมันแปลว่า
จำนวนแทร็กในไฟล์มาจาก preset ไม่ได้มาจากเนื้อในของก้อน
ต่อให้ก้อนไหนไม่มีเสียงของ Role บางตัว ไฟล์ก็ยังมีสามแทร็กครบ
แต่คู่สเตอริโอที่ไม่มีของ จะออกมาเป็นความเงียบ

ตัวนี้จึงไม่ได้ตรวจว่าไฟล์จะมีกี่ช่อง เพราะเรื่องนั้น preset จัดการให้แล้ว
สิ่งที่ตรวจคือ ก้อนไหนเสียงไม่เหมือนก้อนอื่น
ซึ่งมักแปลว่าตอนตัดต่อลืมใส่เสียงบางส่วนของก้อนนั้น
และความเงียบที่ออกอากาศ แก้ทีหลังไม่ได้

หลักการวัดว่า ครบ คืออะไร
--------------------------
ไม่เดาชื่อ Role เอง แต่ดูจากไทม์ไลน์จริงว่ามี Role อะไรบ้างทั้งเส้น
รายการนั้นคือมาตรฐานของงานชิ้นนี้
ก้อนไหนมีไม่ครบตามรายการนั้น ถือว่าน่าสงสัย ต้องบอกให้รู้

ถ้าอยากกำหนดจำนวนขั้นต่ำเองก็ได้ ด้วย --require
เช่น --require 6 แปลว่าทุกก้อนต้องมีเสียงอย่างน้อยหก Role
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


def effective_require(expected, require):
    """
    ตัดสินว่าเกณฑ์จำนวน Role ที่ตั้งไว้ ใช้ได้จริงกับงานชิ้นนี้ไหม

    ถ้าเกณฑ์สูงกว่าจำนวน Role ที่มีอยู่ทั้งไทม์ไลน์
    ไม่มีก้อนไหนผ่านได้เลยแม้แต่ก้อนเดียว แปลว่าเกณฑ์ผิด ไม่ใช่งานผิด

    เรื่องนี้เกิดขึ้นจริงมาแล้ว ผมเคยตั้งค่าเริ่มต้นไว้ที่หก Role ต่อก้อน
    ซึ่งมาจากที่ผมเข้าใจผิดว่าไฟล์ต้องมีหกแทร็กแยกกัน
    ความจริงคือสามแทร็กสเตอริโอ ที่แต่ละแทร็กรับ
    All Dialogue กับ All Effects กับ All Music
    ไทม์ไลน์จริงจึงมี Role ไม่ถึงหกตัว และทุกก้อนถูกเตือนหมดทุกวัน

    การเตือนที่ขึ้นทุกก้อนทุกครั้ง ไม่มีประโยชน์ มีแต่ทำให้เสียเวลา
    จึงต้องมองข้ามเกณฑ์จำนวนไปเมื่อเจอกรณีนี้
    """
    if require is None or not expected:
        return None
    if len(expected) < require:
        return None
    return require


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

    require = effective_require(expected, require)

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
    lines.append("รูปแบบไฟล์ MXF-50 ของห้องข่าวนี้")
    lines.append("  preset ชื่อ 3 Stereo คือสามแทร็ก แทร็กละสองช่อง รวมหกช่อง")
    lines.append("  จำนวนแทร็กมาจาก preset ไม่ได้มาจากเนื้อในของก้อน")
    lines.append("  ก้อนที่เสียงไม่ครบจึงยังได้สามแทร็กเหมือนเดิม แต่จะมีส่วนที่เงียบ")
    lines.append("")
    if expected:
        lines.append("Role ของเสียงที่งานนี้ใช้ มี %d ตัว" % len(expected))
        for name in expected:
            lines.append("  " + name)
    else:
        lines.append("ไม่พบ Role ของเสียงเลยในไทม์ไลน์นี้")
    if require is not None:
        lines.append("เกณฑ์ที่ตั้งไว้ ทุกก้อนต้องมีอย่างน้อย %d Role" % require)
    lines.append("")

    short = [row for row in results if not row["enough"]]
    for row in results:
        mark = "ครบ" if row["enough"] else "ไม่ครบ"
        lines.append("ก้อนที่ %d  %s  %d Role  %s"
                     % (row["index"], mark, len(row["roles"]), row["name"]))
        if row["missing"]:
            lines.append("        ขาด " + ", ".join(row["missing"]))
    lines.append("")

    if not expected:
        lines.append("ไม่พบช่องเสียงเลยแม้แต่ก้อนเดียว")
        lines.append("ไฟล์ MXF ที่ได้จะมีสามแทร็กตาม preset แต่เงียบทั้งหมด")
        lines.append("ควรตรวจไทม์ไลน์ก่อนเอ็กพอร์ต")
    elif not short:
        lines.append("ทุกก้อนเสียงครบเท่ากันหมด")
    else:
        lines.append("มีก้อนที่เสียงไม่ครบ %d ก้อน" % len(short))
        lines.append("ก้อนเหล่านี้ยังได้สามแทร็กครบตาม preset")
        lines.append("แต่ส่วนที่ไม่มีของ จะออกอากาศเป็นความเงียบ")
        lines.append("วิธีแก้คือกลับไปใส่เสียงของ Role ที่ขาด ให้ครบในก้อนนั้นก่อน")
    return lines


def brief(results, expected, require=None):
    """สรุปสั้นบรรทัดเดียว สำหรับเอาไปแสดงในหน้าต่างของแอป"""
    short = [row for row in results if not row["enough"]]
    if not expected:
        return "ไม่พบช่องเสียงเลยในไทม์ไลน์นี้"

    # เกณฑ์ที่ใช้ตัดสิน คือค่าที่ตั้งไว้ ถ้าไม่ได้ตั้งก็ใช้จำนวน Role ของทั้งเส้น
    standard = require if require is not None else len(expected)
    if not short:
        return "เสียงครบทุกก้อน ก้อนละ %d Role" % len(expected)
    names = ", ".join(str(row["index"]) for row in short[:8])
    if len(short) > 8:
        names += " และอื่น ๆ"
    if require is None:
        # ไม่ได้ตั้งเกณฑ์จำนวนไว้ มาตรฐานจึงมาจากก้อนอื่นในไทม์ไลน์เดียวกัน
        # เขียนให้ตรงตามนั้น จะได้ไม่เข้าใจผิดว่ามีเกณฑ์ตายตัวอยู่
        return ("ก้อนที่ %s เสียงไม่เหมือนก้อนอื่น  ก้อนอื่นมี %d Role"
                % (names, len(expected)))
    return ("เสียงไม่ครบ %d ก้อน คือก้อนที่ %s  ต้องได้ก้อนละ %d Role"
            % (len(short), names, standard))


def main(argv=None):
    parser = argparse.ArgumentParser(description="ตรวจว่าแต่ละก้อนมีช่องเสียงครบไหม")
    parser.add_argument("input", help="ไฟล์ fcpxml หรือ fcpxmld ของไทม์ไลน์ทั้งเส้น")
    parser.add_argument("--min-gap", type=float, default=0.2,
                        help="ช่องว่างกี่วินาทีจึงนับเป็นก้อนใหม่")
    parser.add_argument("--require", type=int, default=None,
                        help="ทุกก้อนต้องมีเสียงอย่างน้อยกี่ Role")
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

    # แสดงผลด้วยเกณฑ์ที่ใช้ได้จริง ไม่ใช่ตัวเลขดิบที่ผู้ใช้ตั้งไว้
    # ไม่อย่างนั้นข้อความจะอ้างเกณฑ์ที่โปรแกรมมองข้ามไปแล้ว
    used = effective_require(expected, args.require)
    if args.brief:
        print(brief(results, expected, used))
    else:
        print("\n".join(format_report(results, expected, used)))

    # คืนค่า 1 เมื่อมีก้อนที่เสียงไม่ครบ เพื่อให้ฝั่งแอปรู้ว่าต้องเตือน
    return 0 if all(row["enough"] for row in results) else 1


if __name__ == "__main__":
    sys.exit(main())
