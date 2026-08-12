# -*- coding: utf-8 -*-
"""items.json 码点守护扫描（2026-08-12 二次修复配套）。

检查 data/items.json 全部 name/description：
  - 禁止"字体子集外"特殊符号（U+00D7 x / U+2265 >= / U+2264 <= /
    U+00F7 / / U+2192 -> / U+2014 -- / U+2026 ... / U+00B7 . 等）
  - 禁止历史乱码 '?' 残留
允许：CJK 汉字、CJK 标点（U+3000-303F）、全角标点（U+FF00-FFEF）。

退出码：0 = 通过；1 = 发现风险字符。
用法：python tools/scripts/scan_items_chars.py
"""
import json
import io
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

SRC = r"H:\rougelike_crew\data\items.json"

# 明确禁用的特殊符号（字体子集风险字符）
BANNED = {
    "\u00d7": "x (U+00D7)",
    "\u2265": ">= (U+2265)",
    "\u2264": "<= (U+2264)",
    "\u00f7": "/ (U+00F7)",
    "\u2192": "-> (U+2192)",
    "\u2014": "- (U+2014)",
    "\u2026": "... (U+2026)",
    "\u00b7": "- (U+00B7)",
}


def is_ok_char(c):
    o = ord(c)
    if o < 128:
        return True
    if 0x4E00 <= o <= 0x9FFF or 0x3400 <= o <= 0x4DBF:
        return True
    if 0x3000 <= o <= 0x303F or 0xFF00 <= o <= 0xFFEF:
        return True
    return False


def main():
    with open(SRC, encoding="utf-8") as f:
        data = json.load(f)
    problems = []
    for it in data["items"]:
        iid = str(it.get("id", ""))
        for field in ("name", "description"):
            v = str(it.get(field, ""))
            if "?" in v:
                problems.append((iid, field, "HAS '?'", v))
            for c in v:
                if c in BANNED:
                    problems.append((iid, field, BANNED[c], v))
                elif not is_ok_char(c):
                    problems.append((iid, field, "OTHER U+%04X" % ord(c), v))
    if problems:
        for iid, field, why, v in problems:
            print("[FAIL] %s %s: %s -> %r" % (iid, field, why, v))
        print("ITEMS CHARS SCAN FAIL: %d problems" % len(problems))
        sys.exit(1)
    print("ITEMS CHARS SCAN OK (all name/description ASCII-safe or CJK)")
    sys.exit(0)


if __name__ == "__main__":
    main()
