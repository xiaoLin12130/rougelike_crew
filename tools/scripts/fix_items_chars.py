# -*- coding: utf-8 -*-
"""items.json 码点清理（2026-08-12 二次修复）。

替换原则：description/name 中所有"非 ASCII 特殊符号"改为 ASCII 等价，
避免字体子集缺字形渲染成 '?'。映射：
    U+00D7 (x)   -> 'x'
    U+2265 (>=)  -> '>='
    U+2264 (<=)  -> '<='
    U+00F7 (/)   -> '/'
    U+2192 (->)  -> '-'
    U+2014 (--)  -> '-'
    U+2026 (...) -> '...'
    U+00B7 (.)   -> '-'
同时修复 wand_expander 的 name/description 历史乱码（"??????"）。
输出 UTF-8 JSON（ensure_ascii=False），与源文件编码一致。

用法：python tools/scripts/fix_items_chars.py
"""
import json
import io
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

SRC = r"H:\rougelike_crew\data\items.json"

# 字符映射（\uXXXX 转义，ASCII 源码）
CHARMAP = {
    "\u00d7": "x",    # x
    "\u2265": ">=",   # >=
    "\u2264": "<=",   # <=
    "\u00f7": "/",    # /
    "\u2192": "->",   # ->
    "\u2014": "-",    # --
    "\u2026": "...",  # ...
    "\u00b7": "-",    # .
}

# wand_expander（法杖扩容）：功能见 game_state.gd max_wand_slots()
#   法杖槽上限 = 3 + 法杖扩容卷轴（传说饰品，最多 1 件生效）
WAND_NAME = "\u6cd5\u6756\u6269\u5bb9"  # 法杖扩容
WAND_DESC = (
    "\u6cd5\u6756\u69fd\u4f4d +1"
    "\uff08\u6700\u591a 4 \u628a\uff0c"
    "\u91cd\u590d\u643a\u5e26\u4ec5 1 \u4ef6\u751f\u6548\uff09"
)  # 法杖槽位 +1（最多 4 把，重复携带仅 1 件生效）


def fix_text(v):
    out = []
    for ch in str(v):
        out.append(CHARMAP.get(ch, ch))
    return "".join(out)


def main():
    with open(SRC, encoding="utf-8") as f:
        data = json.load(f)
    items = data["items"]
    changes = []
    for it in items:
        iid = str(it.get("id", ""))
        for field in ("name", "description"):
            old = str(it.get(field, ""))
            new = fix_text(old)
            if new != old:
                it[field] = new
                changes.append((iid, field, old, new))
        if iid == "wand_expander":
            old_n = str(it.get("name", ""))
            old_d = str(it.get("description", ""))
            if old_n != WAND_NAME:
                it["name"] = WAND_NAME
                changes.append((iid, "name", old_n, WAND_NAME))
            if old_d != WAND_DESC:
                it["description"] = WAND_DESC
                changes.append((iid, "description", old_d, WAND_DESC))
        if iid == "defense_unbreakable":
            # 用户指定措辞：>=30% 改为"达到30%"
            old = str(it.get("description", ""))
            new = old.replace(" \u8fbe\u523030%", "\u8fbe\u523030%")
            if new != old:
                it["description"] = new
                changes.append((iid, "description", old, new))
    with open(SRC, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
        f.write("\n")
    print("TOTAL CHANGES: %d" % len(changes))
    for iid, field, old, new in changes:
        print("[%s] %s:" % (iid, field))
        print("   OLD: %r" % old)
        print("   NEW: %r" % new)


if __name__ == "__main__":
    main()
