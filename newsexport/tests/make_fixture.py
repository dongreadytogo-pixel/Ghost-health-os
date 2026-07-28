#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
สร้างไฟล์ FCPXML ตัวอย่างสำหรับทดสอบ
เลียนแบบโครงสร้างไทม์ไลน์งานข่าวจริง: ข่าว 5 ก้อน คั่นด้วยช่องว่าง
ใช้สำหรับทดสอบเท่านั้น ไม่เกี่ยวกับงานจริงของผู้ใช้
"""

import os
from fractions import Fraction

FPS = 25
PROJECT = "OA690728_4 (ลบ) หนุ่มขับรถตู้ชนท้ายรถ 3 คันเสียหาย(ชลบุรี)"

# (ความยาวคลิปในก้อน..., ช่องว่างหลังก้อน) หน่วยเป็นวินาที
GROUPS = [
    ([8, 6, 5, 7, 9], 7),      # ก้อน 1 ยาว 35 วินาที
    ([10, 6, 7], 17),          # ก้อน 2 ยาว 23 วินาที
    ([12, 9, 9], 5),           # ก้อน 3 ยาว 30 วินาที
    ([11, 8, 6], 13),          # ก้อน 4 ยาว 25 วินาที
    ([9, 8, 9], 0),            # ก้อน 5 ยาว 26 วินาที
]


def fcp_time(seconds):
    """เขียนเวลาแบบเศษส่วนอย่างที่ Final Cut Pro เขียนจริง"""
    fraction = Fraction(seconds).limit_denominator(FPS * 1000)
    numerator = fraction.numerator * FPS
    return "%d/%ds" % (numerator, FPS * fraction.denominator)


def build():
    parts = []
    cursor = Fraction(0)
    clip_number = 0

    for group_index, (clip_lengths, gap_length) in enumerate(GROUPS, start=1):
        for length in clip_lengths:
            clip_number += 1
            parts.append(
                '        <asset-clip ref="r2" offset="%s" name="ชลบุรี(วิเชียร)ชนแหลก %d" '
                'start="0s" duration="%s" format="r1" tcFormat="NDF"/>'
                % (fcp_time(cursor), clip_number, fcp_time(length))
            )
            cursor += length
        if gap_length:
            parts.append(
                '        <gap name="Gap" offset="%s" start="0s" duration="%s"/>'
                % (fcp_time(cursor), fcp_time(gap_length))
            )
            cursor += gap_length

    return """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE fcpxml>
<fcpxml version="1.11">
  <resources>
    <format id="r1" name="FFVideoFormat1080p25" frameDuration="100/2500s"
            width="1920" height="1080" colorSpace="1-1-1 (Rec. 709)"/>
    <asset id="r2" name="A001" start="0s" duration="3600s" hasVideo="1" hasAudio="1"
           format="r1" audioSources="1" audioChannels="2">
      <media-rep kind="original-media" src="file:///Volumes/News/A001.mov"/>
    </asset>
  </resources>
  <library location="file:///Volumes/News/News.fcpbundle/">
    <event name="28-07-2569">
      <project name="%s">
        <sequence format="r1" duration="%s" tcStart="0s" tcFormat="NDF"
                  audioLayout="stereo" audioRate="48k">
          <spine>
%s
          </spine>
        </sequence>
      </project>
    </event>
  </library>
</fcpxml>
""" % (PROJECT, fcp_time(cursor), "\n".join(parts))


if __name__ == "__main__":
    target = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sample-news.fcpxml")
    with open(target, "w", encoding="utf-8") as handle:
        handle.write(build())
    print("สร้างไฟล์ตัวอย่างแล้ว: %s" % target)
