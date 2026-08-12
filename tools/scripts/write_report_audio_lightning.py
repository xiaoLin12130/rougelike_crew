# -*- coding: utf-8 -*-
"""生成 docs/design/落雷与音效二次修复报告.md（UTF-8，中文经 Python 写出）。

草稿源：.tmp/report_src.md（UTF-8，apply_patch 维护）
用法：python tools/scripts/write_report_audio_lightning.py
"""
import shutil
import os
import sys

SRC = r"H:\rougelike_crew\.tmp\report_src.md"
DST = r"H:\rougelike_crew\docs\design\落雷与音效二次修复报告.md"


def main():
    with open(SRC, "r", encoding="utf-8") as f:
        content = f.read()
    with open(DST, "w", encoding="utf-8", newline="\n") as f:
        f.write(content)
    print("WROTE: %s (%d bytes)" % (DST, os.path.getsize(DST)))


if __name__ == "__main__":
    main()
