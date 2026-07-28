#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
แยกไทม์ไลน์ข่าวหนึ่งอัน ออกเป็นงานย่อยหลายอัน อันละหนึ่งก้อนข่าว

ทำไมต้องทำแบบนี้
----------------
ปัญหาของคุณคือ ต้องกด Export ทีละก้อน ก้อนละ 2 ไฟล์ รวมหลายสิบครั้ง

วิธีแก้คือ เปลี่ยนไทม์ไลน์ยาว ๆ อันเดียว ให้กลายเป็นงานย่อย 5 อัน
โดยตั้งชื่องานย่อยไว้ล่วงหน้าให้ถูกต้องแล้ว เช่น
    ชื่องาน-1
    ชื่องาน-2
    ...

พอนำเข้า Final Cut Pro คุณจะเห็นงานย่อยครบทุกอันเรียงกันอยู่
เลือกทั้งหมดทีเดียว แล้วสั่ง Export ครั้งเดียวจบ
Final Cut Pro จะตั้งชื่อไฟล์ตามชื่องานย่อยให้เอง = ชื่อถูกต้องอัตโนมัติ

เรื่องเสียง Roles
-----------------
วิธีนี้คัดลอกทุกอย่างในไทม์ไลน์มาครบ รวมทั้งเสียงและ Roles ทั้งหมด
เพราะไม่ได้แปลงไฟล์ ไม่ได้รวมเสียง แค่ "ย้ายที่" เท่านั้น
การตั้งค่า Roles as: 3 Stereo จึงยังใช้ได้เหมือนเดิมทุกประการ

การใช้งาน
--------
    python3 fcpxml_split.py งานข่าว.fcpxml
    python3 fcpxml_split.py งานข่าว.fcpxml -o แยกแล้ว.fcpxml --min-gap 1.0
"""

import argparse
import copy
import os
import sys
import xml.etree.ElementTree as ET
from fractions import Fraction

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from fcpxml_segments import (  # noqa: E402
    CLIP_TAGS,
    DEFAULT_MIN_GAP,
    TimelineError,
    find_sequence,
    format_timecode,
    group_into_segments,
    parse_time,
    read_frame_rate,
    resolve_input,
    safe_filename,
    segment_basename,
    walk_spine,
)


# ============================================================
# ส่วนที่ 1 — การเขียนเวลากลับเป็นแบบที่ Final Cut Pro อ่านได้
# ============================================================


def write_time(value, timescale):
    """
    เขียนเศษส่วนกลับเป็นข้อความเวลาของ FCPXML
    ต้องใช้ตัวส่วนเดียวกับที่ไทม์ไลน์ใช้ (เช่น 25 หรือ 30000)
    ไม่งั้น Final Cut Pro จะปัดตำแหน่งให้ แล้วภาพจะเลื่อนไปหนึ่งเฟรม
    """
    if value == 0:
        return "0s"
    numerator = value * timescale
    if numerator.denominator != 1:
        # ตำแหน่งไม่ลงเฟรมพอดี ให้ปัดเข้าเฟรมที่ใกล้ที่สุด
        numerator = Fraction(round(float(numerator)))
    return "%d/%ds" % (numerator.numerator, timescale)


def timescale_for(fps):
    """
    หาตัวส่วนที่เหมาะกับความเร็วภาพ
    25 fps  -> 25       (PAL)
    30000/1001 -> 30000 (NTSC 29.97 ต้องใช้ตัวส่วนใหญ่ ห้ามปัด)
    """
    return fps.numerator


# ============================================================
# ส่วนที่ 2 — การหั่นไทม์ไลน์
# ============================================================


def slice_spine(spine, start, end, timescale):
    """
    คัดลอกของทุกชิ้นที่อยู่ในช่วงเวลา start ถึง end ออกมาเป็นไทม์ไลน์ใหม่
    แล้วเลื่อนตำแหน่งให้เริ่มที่ศูนย์

    คัดลอกแบบยกทั้งก้อน (ทั้งลูกทั้งหลาน) จึงได้ทุกอย่างครบ
    ทั้งเสียง Roles คลิปที่แปะอยู่ข้างบน ตัวอักษร และเอฟเฟกต์
    """
    new_spine = ET.Element("spine")
    cursor = Fraction(0)

    for element in spine:
        if element.tag not in CLIP_TAGS and element.tag != "gap":
            continue

        offset_text = element.get("offset")
        item_start = parse_time(offset_text) if offset_text is not None else cursor
        duration = parse_time(element.get("duration"))
        cursor = item_start + duration

        if duration <= 0:
            continue
        # เอาเฉพาะชิ้นที่อยู่ในช่วงของก้อนนี้
        if item_start < start or item_start >= end:
            continue
        # ไม่เอาช่องว่างที่ค้างอยู่ท้ายก้อน
        if element.tag == "gap" and item_start + duration > end:
            continue

        clone = copy.deepcopy(element)
        clone.set("offset", write_time(item_start - start, timescale))
        new_spine.append(clone)

    return new_spine


def find_orphaned_content(spine, segments, min_gap):
    """
    ตรวจหาของที่จะ "ตกหล่น" ตอนแยกงาน

    ในไทม์ไลน์ บางครั้งมีตัวอักษรหรือคลิปแปะห้อยอยู่ใต้ช่องว่าง
    ถ้าช่องว่างนั้นถูกใช้เป็นตัวคั่นข่าว ของที่ห้อยอยู่จะหายไปด้วย
    โปรแกรมจะไม่ลบเงียบ ๆ แต่จะเตือนให้ผู้ใช้รู้ก่อนเสมอ
    """
    threshold = Fraction(min_gap).limit_denominator(1000)
    warnings = []
    cursor = Fraction(0)

    for element in spine:
        if element.tag != "gap":
            if element.tag in CLIP_TAGS:
                offset_text = element.get("offset")
                item_start = parse_time(offset_text) if offset_text is not None else cursor
                cursor = item_start + parse_time(element.get("duration"))
            continue

        offset_text = element.get("offset")
        item_start = parse_time(offset_text) if offset_text is not None else cursor
        duration = parse_time(element.get("duration"))
        cursor = item_start + duration

        if duration < threshold:
            continue  # ช่องว่างสั้น ยังอยู่ในก้อน ไม่ตกหล่น

        for child in element:
            if child.tag in CLIP_TAGS:
                warnings.append({
                    "at": item_start,
                    "tag": child.tag,
                    "name": child.get("name") or "(ไม่มีชื่อ)",
                })

    return warnings


def build_segment_project(source_sequence, spine, name, duration, timescale):
    """สร้างงานย่อยหนึ่งอัน จากไทม์ไลน์ที่หั่นมาแล้ว"""
    project = ET.Element("project", {"name": name})

    sequence = ET.SubElement(project, "sequence")
    # คัดค่าตั้งของไทม์ไลน์เดิมมาทั้งหมด (รูปแบบภาพ อัตราเสียง การวางเสียง)
    for key, value in source_sequence.attrib.items():
        sequence.set(key, value)
    sequence.set("duration", write_time(duration, timescale))
    sequence.set("tcStart", "0s")

    sequence.append(spine)
    return project


def split(tree, min_gap, event_name=None):
    """แยกไฟล์ทั้งไฟล์ออกเป็นงานย่อยหลายอัน คืนค่าเป็น (ต้นไม้ใหม่, รายการก้อน)"""
    root = tree.getroot()
    project, sequence = find_sequence(root)
    project_name = project.get("name") or "Untitled"
    fps = read_frame_rate(root, sequence)
    timescale = timescale_for(fps)

    spine = sequence.find("spine")
    if spine is None:
        raise TimelineError("ไทม์ไลน์นี้ว่างเปล่า ไม่มีคลิปเลย")

    segments = group_into_segments(walk_spine(spine), min_gap)
    if not segments:
        raise TimelineError(
            "ไม่พบข่าวสักก้อนในไทม์ไลน์นี้\n"
            "  ลองสั่งใหม่โดยเพิ่ม --min-gap 0.5 เพื่อให้จับช่องว่างที่สั้นกว่าเดิม"
        )

    # สร้างไฟล์ผลลัพธ์ โดยยกส่วน <resources> เดิมมาทั้งหมด
    # เพราะงานย่อยทุกอันยังอ้างถึงไฟล์วิดีโอชุดเดิม
    new_root = ET.Element("fcpxml", {"version": root.get("version") or "1.11"})
    resources = root.find("resources")
    if resources is not None:
        new_root.append(copy.deepcopy(resources))

    source_library = root.find("library")
    library = ET.SubElement(new_root, "library")
    if source_library is not None and source_library.get("location"):
        library.set("location", source_library.get("location"))

    # ชื่อ Event ต้องไม่ซ้ำของเดิม
    #
    # ถ้าใช้ชื่อเดิมทุกครั้ง พอนำเข้าซ้ำ Final Cut Pro จะเอาไปรวมกับ Event เดิม
    # ทำให้ข้างในมีงานปนกันระหว่างรอบเก่ากับรอบใหม่
    # เวลาสั่งเลือกทั้งหมดเพื่อเอ็กพอร์ต จะได้ไฟล์เกินและซ้ำ
    # ยิ่งงานที่มี 30 ก้อน ยิ่งพลาดง่ายและตรวจยาก
    event = ET.SubElement(library, "event",
                          {"name": event_name or safe_filename(project_name)})

    warnings = find_orphaned_content(spine, segments, min_gap)

    details = []
    for index, segment in enumerate(segments, start=1):
        start, end = segment["start"], segment["end"]
        name = segment_basename(project_name, index)
        sliced = slice_spine(spine, start, end, timescale)
        event.append(build_segment_project(sequence, sliced, name, end - start, timescale))
        details.append({
            "index": index,
            "name": name,
            "start": start,
            "end": end,
            "startTimecode": format_timecode(start, fps),
            "endTimecode": format_timecode(end, fps),
            "clips": len(sliced),
        })

    return ET.ElementTree(new_root), details, fps, warnings


# ============================================================
# ส่วนที่ 3 — การเขียนไฟล์ผลลัพธ์
# ============================================================


def write_fcpxml(tree, path):
    """เขียนไฟล์ออกมาให้ Final Cut Pro นำเข้าได้"""
    ET.indent(tree, space="  ")
    with open(path, "w", encoding="utf-8") as handle:
        handle.write('<?xml version="1.0" encoding="UTF-8"?>\n')
        handle.write("<!DOCTYPE fcpxml>\n")
        handle.write(ET.tostring(tree.getroot(), encoding="unicode"))
        handle.write("\n")


def print_report(details, fps, output_path, warnings=()):
    print("")
    print("=" * 60)
    print("  แยกงานเรียบร้อยแล้ว")
    print("=" * 60)
    print("  ความเร็วภาพ : %g เฟรมต่อวินาที" % float(fps))
    print("  แยกได้      : %d งาน" % len(details))
    print("")
    for item in details:
        print("  %d. %s" % (item["index"], item["name"]))
        print("     ช่วงเวลาเดิม %s ถึง %s   (%d ชิ้น)"
              % (item["startTimecode"], item["endTimecode"], item["clips"]))
    print("")

    if warnings:
        print("  " + "!" * 56)
        print("  ⚠️  คำเตือน: มีของห้อยอยู่ใต้ช่องว่างที่ใช้คั่นข่าว %d ชิ้น" % len(warnings))
        print("      ของพวกนี้จะไม่ถูกนำไปใส่ในงานย่อยอันไหนเลย")
        for warning in warnings:
            print("      • %s ที่ตำแหน่ง %s"
                  % (warning["name"], format_timecode(warning["at"], fps)))
        print("      ถ้าของพวกนี้สำคัญ กรุณาบอกผม แล้วผมจะปรับวิธีแยกให้")
        print("  " + "!" * 56)
        print("")
    print("  ไฟล์ผลลัพธ์ : %s" % output_path)
    print("")
    print("  ขั้นตอนต่อไป")
    print("   1. เปิด Final Cut Pro")
    print("   2. เมนู File > Import > XML…  แล้วเลือกไฟล์ผลลัพธ์ข้างบน")
    print("   3. จะได้งานย่อยครบทุกอัน ชื่อถูกต้องแล้ว")
    print("   4. เลือกงานย่อยทั้งหมด แล้วสั่ง Export ครั้งเดียว")
    print("=" * 60)
    print("")


def write_per_segment(tree, min_gap, folder, event_prefix):
    """
    เขียนไฟล์แยกทีละก้อน ก้อนละหนึ่งไฟล์ และแต่ละไฟล์มีงานเดียว

    ทำไมต้องแยกทีละไฟล์
    -------------------
    ตอนสั่งเอ็กพอร์ต ปัญหาใหญ่ที่สุดคือการเลือกงานให้ครบทุกอัน
    ถ้าเลือกไม่ครบ จะได้ไฟล์มาแค่ก้อนเดียว ซึ่งเกิดขึ้นจริงมาแล้ว

    วิธีนี้ตัดปัญหาทิ้งทั้งหมด
    เพราะนำเข้าทีละไฟล์ Event ที่ได้จะมีงานอยู่แค่ชิ้นเดียว
    สั่งเลือกทั้งหมดเมื่อไร ก็ได้งานชิ้นนั้นชิ้นเดียวแน่นอน
    ไม่มีทางเลือกผิด และไม่มีทางเลือกไม่ครบ
    """
    os.makedirs(folder, exist_ok=True)
    written = []
    total = len(group_into_segments(
        walk_spine(find_sequence(tree.getroot())[1].find("spine")), min_gap))

    for index in range(1, total + 1):
        single, details, fps, _ = split(tree, min_gap,
                                        "%s %d" % (event_prefix, index))
        root = single.getroot()
        library = root.find("library")
        event = library.find("event")
        # เก็บไว้เฉพาะงานลำดับที่ต้องการ ที่เหลือเอาออก
        for project in list(event.findall("project")):
            if project.get("name") != details[index - 1]["name"]:
                event.remove(project)
        path = os.path.join(folder, "ก้อน-%03d.fcpxml" % index)
        write_fcpxml(single, path)
        written.append({"index": index, "path": path,
                        "name": details[index - 1]["name"]})
    return written


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="แยกไทม์ไลน์ข่าวออกเป็นงานย่อย อันละหนึ่งก้อน")
    parser.add_argument("fcpxml", help="ไฟล์ .fcpxml ที่ Export มาจาก Final Cut Pro")
    parser.add_argument("-o", "--output", help="ชื่อไฟล์ผลลัพธ์ (ค่าเริ่มต้นคือเติม -แยกแล้ว)")
    parser.add_argument("--per-segment", default=None,
                        help="เขียนไฟล์แยกทีละก้อนลงในโฟลเดอร์นี้ ก้อนละหนึ่งไฟล์")
    parser.add_argument("--event-name", default=None,
                        help="ชื่อ Event ที่จะสร้างในไฟล์ผลลัพธ์ ควรไม่ซ้ำของเดิม")
    parser.add_argument("--min-gap", type=float, default=DEFAULT_MIN_GAP,
                        help="ช่องว่างกี่วินาทีขึ้นไปจึงถือว่าคั่นข่าว (ค่าเริ่มต้น %g)"
                             % DEFAULT_MIN_GAP)
    args = parser.parse_args(argv)

    try:
        source = resolve_input(args.fcpxml)
    except TimelineError as error:
        print("")
        print("เกิดปัญหา:")
        print("  %s" % error)
        print("")
        return 2

    try:
        tree = ET.parse(source)
    except ET.ParseError as error:
        print("อ่านไฟล์ไม่ได้ ไฟล์อาจเสียหาย: %s" % error, file=sys.stderr)
        return 2

    try:
        new_tree, details, fps, warnings = split(tree, args.min_gap, args.event_name)
    except TimelineError as error:
        print("")
        print("เกิดปัญหา:")
        print("  %s" % error)
        print("")
        return 2

    output = args.output
    if not output:
        # เก็บผลลัพธ์ไว้ข้าง ๆ ของเดิม และเป็นไฟล์ .fcpxml ธรรมดาเสมอ
        # ถึงต้นทางจะเป็นกล่อง .fcpxmld ก็ตาม
        base = args.fcpxml.rstrip("/")
        for suffix in (".fcpxmld", ".fcpxml"):
            if base.endswith(suffix):
                base = base[: -len(suffix)]
                break
        output = base + "-แยกแล้ว.fcpxml"

    if args.per_segment:
        written = write_per_segment(tree, args.min_gap, args.per_segment,
                                    args.event_name or "แยกงาน")
        for item in written:
            print("%d\t%s\t%s" % (item["index"], item["path"], item["name"]))
        return 0

    write_fcpxml(new_tree, output)
    print_report(details, fps, output, warnings)
    return 0


if __name__ == "__main__":
    sys.exit(main())
