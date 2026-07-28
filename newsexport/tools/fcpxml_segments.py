#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
อ่านไฟล์ FCPXML จาก Final Cut Pro แล้วหาว่าในไทม์ไลน์มีข่าวกี่ก้อน
ก้อนไหนเริ่มตรงไหน จบตรงไหน และควรตั้งชื่อไฟล์ว่าอะไร

หลักการ
-------
ในไทม์ไลน์ของงานข่าว ข่าวแต่ละเรื่องจะถูกคั่นด้วย "ช่องว่าง" (gap)
โปรแกรมนี้จึงเดินดูไทม์ไลน์จากซ้ายไปขวา
เจอคลิปติดกันเป็นพืด = ข่าวหนึ่งก้อน
เจอช่องว่างยาวพอ      = จบก้อน ขึ้นก้อนใหม่

ทุกการคำนวณเวลาใช้ "เศษส่วน" ไม่ใช่ทศนิยม
เพราะงานออกอากาศผิดแม้เฟรมเดียวก็เห็นบนจอ

การใช้งาน
--------
    python3 fcpxml_segments.py งานข่าว.fcpxml
    python3 fcpxml_segments.py งานข่าว.fcpxml --min-gap 1.0
    python3 fcpxml_segments.py งานข่าว.fcpxml --json
"""

import argparse
import json
import os
import sys
import xml.etree.ElementTree as ET
from fractions import Fraction

# ============================================================
# ส่วนที่ 1 — การอ่านเวลาแบบเศษส่วนของ Final Cut Pro
# ============================================================

# Final Cut Pro เขียนเวลาเป็นเศษส่วน เช่น "52052/25s" หรือ "3s" หรือ "0s"
# เราต้องเก็บเป็นเศษส่วนจริง ๆ ห้ามแปลงเป็นทศนิยมระหว่างทาง
# เพราะทศนิยมจะปัดเศษ แล้วตำแหน่งตัดจะเพี้ยนไปจากเดิม


def parse_time(text):
    """แปลงข้อความเวลาของ FCPXML เป็นเศษส่วน (หน่วยวินาที)"""
    if text is None:
        return Fraction(0)
    text = text.strip()
    if text.endswith("s"):
        text = text[:-1]
    if not text:
        return Fraction(0)
    if "/" in text:
        numerator, denominator = text.split("/", 1)
        return Fraction(int(numerator), int(denominator))
    return Fraction(int(float(text) * 1000), 1000) if "." in text else Fraction(int(text))


def format_timecode(seconds, fps):
    """แปลงเวลาเป็นไทม์โค้ด ชั่วโมง:นาที:วินาที:เฟรม"""
    total_frames = int(round(float(seconds) * float(fps)))
    frames_per_hour = int(round(float(fps) * 3600))
    frames_per_minute = int(round(float(fps) * 60))
    hours = total_frames // frames_per_hour
    remainder = total_frames % frames_per_hour
    minutes = remainder // frames_per_minute
    remainder = remainder % frames_per_minute
    seconds_part = remainder // int(round(float(fps)))
    frames = remainder % int(round(float(fps)))
    return "%02d:%02d:%02d:%02d" % (hours, minutes, seconds_part, frames)


def format_duration(seconds):
    """แปลงเวลาเป็นข้อความอ่านง่าย เช่น 1 นาที 23.5 วินาที"""
    total = float(seconds)
    minutes = int(total // 60)
    rest = total - minutes * 60
    if minutes:
        return "%d นาที %.1f วินาที" % (minutes, rest)
    return "%.1f วินาที" % rest


# ============================================================
# ส่วนที่ 2 — การอ่านโครงสร้างไทม์ไลน์
# ============================================================

# ชนิดของสิ่งที่วางอยู่บนไทม์ไลน์หลัก ที่ถือว่าเป็น "เนื้อข่าว"
CLIP_TAGS = {
    "asset-clip",   # คลิปวิดีโอ/เสียงธรรมดา
    "clip",         # คลิปทั่วไป
    "ref-clip",     # Compound Clip
    "sync-clip",    # Synchronized Clip
    "mc-clip",      # Multicam Clip
    "video",        # ภาพนิ่ง / เจเนอเรเตอร์
    "audio",        # เสียงล้วน
    "title",        # ตัวอักษร
    "transition",   # ทรานซิชัน (ถือเป็นเนื้อ ไม่ใช่ช่องว่าง)
}


class TimelineError(Exception):
    """ข้อผิดพลาดที่อธิบายเป็นภาษาคนได้ ไม่ใช่ข้อความของเครื่อง"""


def resolve_input(path):
    """
    รับได้ทั้งสองแบบที่ Final Cut Pro ส่งออกมา

    แบบเก่า  ไฟล์เดียว           งาน.fcpxml
    แบบใหม่  กล่องที่มีไฟล์ข้างใน  งาน.fcpxmld  (ข้างในมี Info.fcpxml)

    Final Cut Pro รุ่นใหม่ส่งออกเป็นแบบกล่อง ซึ่งบน Mac จะเห็นเป็นไฟล์เดียว
    แต่จริง ๆ เป็นโฟลเดอร์ โปรแกรมจึงต้องเข้าไปหยิบไฟล์ข้างในให้เอง
    """
    if os.path.isdir(path):
        inner = os.path.join(path, "Info.fcpxml")
        if os.path.isfile(inner):
            return inner
        raise TimelineError(
            "ในกล่องนี้ไม่มีไฟล์ Info.fcpxml\n"
            "  กรุณาส่งออกใหม่จาก Final Cut Pro ด้วยเมนู File > Export XML"
        )
    if os.path.isfile(path):
        return path
    raise TimelineError("ไม่พบไฟล์หรือโฟลเดอร์นี้: %s" % path)


def find_sequence(root):
    """หา <project> และ <sequence> ในไฟล์ ไม่ว่าจะซ้อนอยู่ลึกแค่ไหน"""
    project = None
    for candidate in root.iter("project"):
        project = candidate
        break
    if project is None:
        raise TimelineError(
            "ไม่พบงาน (project) ในไฟล์นี้\n"
            "  สาเหตุที่พบบ่อย: ตอน Export XML เลือกที่ Event หรือ Library แทนที่จะเลือกที่ตัวงาน\n"
            "  วิธีแก้: ใน Final Cut Pro ให้คลิกที่ชื่องานก่อน แล้วค่อยไปเมนู File > Export XML"
        )
    sequence = project.find("sequence")
    if sequence is None:
        raise TimelineError("งานนี้ไม่มีไทม์ไลน์อยู่ข้างใน (ไม่พบ sequence)")
    return project, sequence


def read_frame_rate(root, sequence):
    """อ่านจำนวนเฟรมต่อวินาทีของงาน จากรูปแบบภาพที่ไทม์ไลน์ใช้"""
    format_id = sequence.get("format")
    for element in root.iter("format"):
        if element.get("id") == format_id:
            frame_duration = parse_time(element.get("frameDuration"))
            if frame_duration > 0:
                return 1 / frame_duration
    return Fraction(25)  # ค่าสำรอง ถ้าอ่านไม่ได้จริง ๆ


def walk_spine(spine):
    """
    เดินดูของทุกชิ้นบนไทม์ไลน์หลัก จากซ้ายไปขวา
    คืนค่าเป็นรายการของ (ชนิด, ตำแหน่งเริ่ม, ความยาว, ชื่อ)
    ชนิดมีสองแบบเท่านั้น: "clip" (เนื้อข่าว) กับ "gap" (ช่องว่าง)
    """
    items = []
    cursor = Fraction(0)  # ตำแหน่งปัจจุบันบนไทม์ไลน์

    for element in spine:
        tag = element.tag
        if tag not in CLIP_TAGS and tag != "gap":
            continue  # ข้ามพวก marker/metadata ที่ไม่กินเวลา

        # ถ้ามีการระบุตำแหน่งไว้ ให้เชื่อตำแหน่งนั้น
        # ถ้าไม่ระบุ แปลว่าวางต่อจากชิ้นก่อนหน้าพอดี
        offset_text = element.get("offset")
        start = parse_time(offset_text) if offset_text is not None else cursor

        duration = parse_time(element.get("duration"))
        if duration <= 0:
            continue

        kind = "gap" if tag == "gap" else "clip"
        name = element.get("name") or ""
        items.append((kind, start, duration, name, tag))
        cursor = start + duration

    return items


def group_into_segments(items, min_gap_seconds):
    """
    รวมคลิปที่ติดกันเป็น "ก้อน" เดียว
    ช่องว่างที่ยาวตั้งแต่ min_gap_seconds ขึ้นไป ถือเป็นตัวคั่นระหว่างข่าว
    ช่องว่างสั้นกว่านั้น ถือว่าเป็นจังหวะภายในข่าวเรื่องเดียวกัน
    """
    threshold = Fraction(min_gap_seconds).limit_denominator(1000)
    segments = []
    current = None

    for kind, start, duration, name, tag in items:
        if kind == "gap" and duration >= threshold:
            # ช่องว่างยาวพอ = ปิดก้อนปัจจุบัน
            if current is not None:
                segments.append(current)
                current = None
            continue

        # เป็นเนื้อข่าว (หรือช่องว่างสั้นที่นับรวมเข้าไปในก้อน)
        if current is None:
            if kind == "gap":
                continue  # ช่องว่างสั้นที่อยู่หน้าก้อน ไม่ต้องนับ
            current = {"start": start, "end": start + duration, "clips": 0, "names": []}
        current["end"] = max(current["end"], start + duration)
        if kind == "clip":
            current["clips"] += 1
            if name:
                current["names"].append(name)

    if current is not None:
        segments.append(current)
    return segments


def list_gaps(items):
    """คืนรายการช่องว่างทั้งหมดที่พบ พร้อมตำแหน่งและความยาว"""
    return [(start, duration) for kind, start, duration, _, _ in items if kind == "gap"]


# ค่าเริ่มต้นของตัวคั่น หน่วยวินาที
#
# ผู้ใช้ยืนยันว่า "จะมีช่องว่างเสมอ พอเห็นคลิปใหม่ถัดจากช่องว่าง นั่นคือไฟล์ถัดไป"
# แปลว่าช่องว่างทุกอันคือตัวคั่นข่าว ไม่ได้ขึ้นกับว่ายาวเท่าไร
#
# แต่ตั้งไว้ที่ 0.2 วินาที (5 เฟรม) ไม่ใช่ 0 เพราะเวลาตัดงานจริง
# บางครั้งเผลอเว้นช่องว่างไว้ 1-2 เฟรมโดยไม่ตั้งใจ ซึ่งมองด้วยตาไม่เห็น
# ถ้าตั้งเป็น 0 ช่องว่างที่เผลอนั้นจะทำให้ข่าวขาดเป็นสองก้อนโดยไม่รู้ตัว
DEFAULT_MIN_GAP = 0.2


# ============================================================
# ส่วนที่ 3 — การตั้งชื่อไฟล์
# ============================================================

# ตัวอักษรที่ห้ามใช้ในชื่อไฟล์บน macOS
ILLEGAL_IN_FILENAME = {"/": "-", ":": "-"}


def safe_filename(name):
    """ทำให้ชื่องานใช้เป็นชื่อไฟล์ได้ โดยเปลี่ยนแปลงให้น้อยที่สุด"""
    cleaned = name.strip()
    for bad, good in ILLEGAL_IN_FILENAME.items():
        cleaned = cleaned.replace(bad, good)
    # ตัดจุดและช่องว่างท้ายชื่อออก เพราะ macOS ไม่ชอบ
    cleaned = cleaned.rstrip(". ")
    return cleaned or "Untitled"


def segment_basename(project_name, index):
    """
    สร้างชื่อฐานของก้อนที่ index เช่น 'ชื่องาน-1'

    ผู้ใช้บางคนตั้งชื่องานลงท้ายด้วยขีดไว้อยู่แล้ว เช่น '…(ชลบุรี)-'
    ถ้าเติมขีดซ้ำจะกลายเป็น '…(ชลบุรี)--1' ซึ่งผิดจากที่ต้องการ
    จึงตัดขีดและช่องว่างท้ายชื่อออกก่อนเสมอ แล้วค่อยเติม '-เลขก้อน'
    ผลลัพธ์จึงเป็น '…(ชลบุรี)-1' ไม่ว่าผู้ใช้จะตั้งชื่อมาแบบไหน
    """
    base = safe_filename(project_name).rstrip("- ")
    return "%s-%d" % (base or "Untitled", index)


def build_filenames(project_name, index, extensions):
    """สร้างชื่อไฟล์ของก้อนที่ index เช่น 'ชื่องาน-1.mov' และ 'ชื่องาน-1.mxf'"""
    base = segment_basename(project_name, index)
    return [base + "." + extension for extension in extensions]


# ============================================================
# ส่วนที่ 4 — การแสดงผล
# ============================================================


def print_report(project_name, fps, segments, extensions, min_gap, gaps=()):
    total = len(segments)
    print("")
    print("=" * 60)
    print("  รายการข่าวที่พบในไทม์ไลน์")
    print("=" * 60)
    print("  ชื่องาน      : %s" % project_name)
    print("  ความเร็วภาพ  : %g เฟรมต่อวินาที" % float(fps))
    print("  ถือว่าช่องว่างตั้งแต่ %g วินาทีขึ้นไป คือตัวคั่นข่าว" % min_gap)
    print("  พบทั้งหมด    : %d ก้อน" % total)
    print("")

    if gaps:
        separators = [g for g in gaps if float(g[1]) >= min_gap]
        too_short = [g for g in gaps if float(g[1]) < min_gap]
        print("  ช่องว่างที่ใช้คั่นข่าว %d จุด" % len(separators))
        for start, duration in separators:
            print("     ที่ %s  ยาว %.1f วินาที"
                  % (format_timecode(start, fps), float(duration)))
        print("")
        if too_short:
            print("  หมายเหตุ: พบช่องว่างสั้นมากอีก %d จุด ซึ่งไม่ถูกใช้คั่นข่าว"
                  % len(too_short))
            for start, duration in too_short:
                frames = int(round(float(duration) * float(fps)))
                print("     ที่ %s  ยาวแค่ %d เฟรม"
                      % (format_timecode(start, fps), frames))
            print("     ถ้าจุดพวกนี้ควรเป็นตัวคั่นข่าวด้วย ให้ลดตัวเลขวินาทีลง")
            print("")

    if total == 0:
        print("  ⚠️  ไม่พบข่าวสักก้อน")
        print("     ลองลดค่าตัวคั่นลง เช่น --min-gap 0.5")
        print("")
        return

    for index, segment in enumerate(segments, start=1):
        start = segment["start"]
        end = segment["end"]
        length = end - start
        print("  ── ก้อนที่ %d ──────────────────────────────────" % index)
        print("     เริ่มที่ : %s" % format_timecode(start, fps))
        print("     จบที่   : %s" % format_timecode(end, fps))
        print("     ความยาว : %s   (%d คลิป)" % (format_duration(length), segment["clips"]))
        if segment["names"]:
            preview = segment["names"][0]
            if len(preview) > 40:
                preview = preview[:40] + "…"
            print("     คลิปแรก : %s" % preview)
        for filename in build_filenames(project_name, index, extensions):
            print("     ไฟล์    : %s" % filename)
        print("")

    print("=" * 60)
    print("  รวมต้องสร้างไฟล์ทั้งหมด %d ไฟล์" % (total * len(extensions)))
    print("=" * 60)
    print("")


def brief_report(project_name, fps, segments, extensions):
    """
    สรุปแบบสั้น สำหรับแสดงในหน้าต่างของโปรแกรม
    หน้าต่างของ macOS แสดงข้อความยาว ๆ ได้ไม่ดี จึงต้องกระชับ
    """
    lines = []
    short_name = project_name if len(project_name) <= 34 else project_name[:33] + "…"
    lines.append("งาน  " + short_name)
    lines.append("พบข่าว " + str(len(segments)) + " ก้อน  ที่ %g เฟรมต่อวินาที" % float(fps))
    lines.append("")
    for index, segment in enumerate(segments, start=1):
        length = segment["end"] - segment["start"]
        lines.append("ก้อน %d   %s ถึง %s   ยาว %s"
                     % (index,
                        format_timecode(segment["start"], fps),
                        format_timecode(segment["end"], fps),
                        format_duration(length)))
    lines.append("")
    lines.append("จะได้ไฟล์ทั้งหมด %d ไฟล์" % (len(segments) * len(extensions)))
    lines.append("ชื่อลงท้าย -1 ถึง -%d ทั้งนามสกุล %s"
                 % (len(segments), " และ ".join(extensions)))
    return "\n".join(lines)


def build_json(project_name, fps, segments, extensions):
    """ผลลัพธ์แบบที่โปรแกรมอื่นเอาไปใช้ต่อได้ (สำหรับขั้นตอน Export)"""
    return {
        "projectName": project_name,
        "frameRate": [fps.numerator, fps.denominator],
        "segmentCount": len(segments),
        "segments": [
            {
                "index": index,
                "startSeconds": [segment["start"].numerator, segment["start"].denominator],
                "endSeconds": [segment["end"].numerator, segment["end"].denominator],
                "startTimecode": format_timecode(segment["start"], fps),
                "endTimecode": format_timecode(segment["end"], fps),
                "clipCount": segment["clips"],
                "outputs": build_filenames(project_name, index, extensions),
            }
            for index, segment in enumerate(segments, start=1)
        ],
    }


# ============================================================
# ส่วนที่ 5 — จุดเริ่มโปรแกรม
# ============================================================


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="หาว่าไทม์ไลน์ Final Cut Pro มีข่าวกี่ก้อน และควรตั้งชื่อไฟล์ว่าอะไร"
    )
    parser.add_argument("fcpxml", help="ไฟล์ .fcpxml ที่ Export มาจาก Final Cut Pro")
    parser.add_argument(
        "--min-gap", type=float, default=DEFAULT_MIN_GAP,
        help="ช่องว่างกี่วินาทีขึ้นไปจึงถือว่าคั่นข่าว (ค่าเริ่มต้น %g)" % DEFAULT_MIN_GAP)
    parser.add_argument(
        "--ext", default="mov,mxf",
        help="นามสกุลไฟล์ที่ต้องสร้าง คั่นด้วยจุลภาค (ค่าเริ่มต้น mov,mxf)")
    parser.add_argument("--json", action="store_true", help="แสดงผลเป็นข้อมูลสำหรับโปรแกรม")
    parser.add_argument("--brief", action="store_true",
                        help="แสดงผลแบบสั้น สำหรับใส่ในหน้าต่างของโปรแกรม")
    parser.add_argument("--names", action="store_true",
                        help="แสดงเฉพาะรายชื่อไฟล์ที่จะได้ บรรทัดละหนึ่งชื่อ")
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

    root = tree.getroot()

    try:
        project, sequence = find_sequence(root)
    except TimelineError as error:
        print("")
        print("เกิดปัญหา:")
        print("  %s" % error)
        print("")
        return 2

    project_name = project.get("name") or "Untitled"
    fps = read_frame_rate(root, sequence)

    spine = sequence.find("spine")
    if spine is None:
        print("ไทม์ไลน์นี้ว่างเปล่า ไม่มีคลิปเลย", file=sys.stderr)
        return 2

    items = walk_spine(spine)
    segments = group_into_segments(items, args.min_gap)
    extensions = [e.strip().lstrip(".") for e in args.ext.split(",") if e.strip()]

    if args.json:
        print(json.dumps(build_json(project_name, fps, segments, extensions),
                         ensure_ascii=False, indent=2))
    elif args.names:
        for index in range(1, len(segments) + 1):
            for filename in build_filenames(project_name, index, extensions):
                print(filename)
    elif args.brief:
        print(brief_report(project_name, fps, segments, extensions))
    else:
        print_report(project_name, fps, segments, extensions, args.min_gap,
                     list_gaps(items))
    return 0


if __name__ == "__main__":
    sys.exit(main())
