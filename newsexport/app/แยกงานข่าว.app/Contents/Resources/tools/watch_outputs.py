#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
เฝ้าดูโฟลเดอร์ปลายทาง แล้วบอกว่าสร้างไฟล์เสร็จไปแล้วกี่ไฟล์

ใช้สำหรับแสดงเปอร์เซ็นต์ความคืบหน้าระหว่างที่ Final Cut Pro กำลังเอ็กพอร์ต

หลักการนับว่า "เสร็จ"
--------------------
ระหว่างที่ Final Cut Pro เขียนไฟล์อยู่ ไฟล์นั้นจะมีอยู่แล้วแต่ขนาดยังโตขึ้นเรื่อย ๆ
ถ้านับแค่ว่ามีไฟล์อยู่ จะได้เปอร์เซ็นต์ที่หลอกตา

โปรแกรมนี้จึงวัดขนาดสองครั้ง ห่างกันไม่กี่วินาที
ไฟล์ไหนขนาดหยุดนิ่งแล้ว ถึงจะนับว่าเสร็จจริง

ผลลัพธ์ที่พิมพ์ออกมา มี 4 บรรทัด
    จำนวนที่เสร็จแล้ว
    จำนวนที่กำลังเขียนอยู่
    จำนวนทั้งหมดที่ต้องได้
    ชื่อไฟล์ล่าสุดที่เสร็จ
"""

import argparse
import os
import sys
import time


def sizes_of(folder, names):
    """อ่านขนาดไฟล์ทุกไฟล์ที่รออยู่ ไฟล์ที่ยังไม่มีให้เป็น None"""
    result = {}
    for name in names:
        path = os.path.join(folder, name)
        try:
            result[name] = os.path.getsize(path)
        except OSError:
            result[name] = None
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description="เฝ้าดูความคืบหน้าการสร้างไฟล์")
    parser.add_argument("folder", help="โฟลเดอร์ปลายทางที่ไฟล์จะถูกสร้าง")
    parser.add_argument("namesfile", help="ไฟล์รายชื่อ บรรทัดละหนึ่งชื่อ")
    parser.add_argument("--settle", type=float, default=2.0,
                        help="รอกี่วินาทีก่อนวัดขนาดครั้งที่สอง (ค่าเริ่มต้น 2)")
    parser.add_argument("--missing", action="store_true",
                        help="พิมพ์รายชื่อไฟล์ที่ยังไม่เสร็จ บรรทัดละหนึ่งชื่อ")
    args = parser.parse_args(argv)

    try:
        with open(args.namesfile, encoding="utf-8") as handle:
            names = [line.strip() for line in handle if line.strip()]
    except OSError as error:
        print("อ่านรายชื่อไฟล์ไม่ได้: %s" % error, file=sys.stderr)
        return 2

    if not names:
        if args.missing:
            return 0
        print("0\n0\n0\n")
        return 0

    first = sizes_of(args.folder, names)
    time.sleep(max(0.2, args.settle))
    second = sizes_of(args.folder, names)

    finished = []
    working = 0
    for name in names:
        before, after = first[name], second[name]
        if after is None:
            continue          # ยังไม่เริ่มเขียนไฟล์นี้
        if before == after and after > 0:
            finished.append(name)   # ขนาดหยุดนิ่งแล้ว = เขียนเสร็จ
        else:
            working += 1            # ขนาดยังโตอยู่ = กำลังเขียน

    # โหมดบอกรายชื่อที่ยังขาด
    # ใช้ตอนจบงาน เพื่อบอกผู้ใช้ตรง ๆ ว่าก้อนไหนยังไม่ได้ไฟล์
    # จะได้ไม่ต้องนั่งไล่เทียบรายชื่อเองทีละบรรทัด
    if args.missing:
        done = set(finished)
        for name in names:
            if name not in done:
                print(name)
        return 0

    print(len(finished))
    print(working)
    print(len(names))
    print(finished[-1] if finished else "")
    return 0


if __name__ == "__main__":
    sys.exit(main())
