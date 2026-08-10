# -*- coding: utf-8 -*-
"""图标去重实施校验（全绿输出）

① 四文件全部 icon 路径存在（文件系统核实：PNG 本体 + .import）
② glow.png 引用数 = 0
③ 任一素材被引用 ≤ 3（跨 items/spells/wands/summons 合计）
④ 与 docs/design/图标去重分配方案.md 映射表一致（抽查 20 条）
"""
import json
import os
import re
import sys
from collections import Counter

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", ".tmp"))
from icon_map_lib import resolve  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.chdir(ROOT)

DATA_FILES = ["data/items.json", "data/spells.json", "data/wands.json", "data/summons.json"]
DOC = "docs/design/图标去重分配方案.md"

failures = []
info = []


def collect_icons():
    """返回 {icon_path: [ids]}"""
    out = {}
    for fname in DATA_FILES:
        with open(fname, encoding="utf-8") as f:
            data = json.load(f)

        def walk(obj, file_):
            if isinstance(obj, dict):
                if "icon" in obj and isinstance(obj["icon"], str):
                    out.setdefault(obj["icon"], []).append(f"{file_}:{obj.get('id', '?')}")
                for v in obj.values():
                    walk(v, file_)
            elif isinstance(obj, list):
                for v in obj:
                    walk(v, file_)

        walk(data, fname)
    return out


def check_paths(icons):
    missing, no_import = [], []
    for p in icons:
        fs = p.replace("res://", "")
        if not os.path.exists(fs):
            missing.append(p)
        if not os.path.exists(fs + ".import"):
            no_import.append(p)
    if missing:
        failures.append(f"[①] 路径不存在: {missing}")
    if no_import:
        failures.append(f"[①] 缺 .import: {no_import}")
    info.append(f"[①] icon 引用总数={sum(len(v) for v in icons.values())}，"
                f"唯一素材={len(icons)}，缺文件={len(missing)}，缺 .import={len(no_import)}")


def check_glow(icons):
    n = sum(1 for p in icons if p.endswith("/verarc/glow.png"))
    if n != 0:
        failures.append(f"[②] glow.png 引用数 = {n}（应为 0）")
    info.append(f"[②] glow.png 引用数 = {n}（应为 0）")


def check_max_refs(icons):
    over = {p: len(v) for p, v in icons.items() if len(v) > 3}
    if over:
        failures.append(f"[③] 超 3 次引用素材: {over}")
    info.append(f"[③] 超 3 次引用素材数 = {len(over)}（应 0）")


def parse_doc_tables():
    with open(DOC, encoding="utf-8") as f:
        doc = f.read()
    tables, cur = [], []
    for ln in doc.split("\n"):
        if ln.strip().startswith("|"):
            cells = [x.strip() for x in ln.strip().strip("|").split("|")]
            if cells and all(re.fullmatch(r":?-{3,}:?", x or "-") for x in cells):
                continue
            cur.append(cells)
        else:
            if cur:
                tables.append(cur)
                cur = []
    if cur:
        tables.append(cur)
    mapping = {}
    for t in tables:
        if not t or t[0][:2] != ["id", "名称"]:
            continue
        for row in t[1:]:
            if len(row) >= 5 and row[0]:
                mapping[row[0]] = row[3]
    return mapping


def spot_check(mapping, icons):
    """抽查 20 条：文档新图标（保留除外）→ 解析路径 → 与 JSON 一致"""
    change_ids = [rid for rid, new in mapping.items() if new != "保留"]
    step = max(1, len(change_ids) // 20)
    sample = change_ids[::step][:20]
    # 构建 id → icon 映射
    id_icon = {}
    for fname in DATA_FILES:
        with open(fname, encoding="utf-8") as f:
            data = json.load(f)

        def walk(obj):
            if isinstance(obj, dict):
                if "icon" in obj and isinstance(obj["icon"], str) and obj.get("id"):
                    id_icon[obj["id"]] = obj["icon"]
                for v in obj.values():
                    walk(v)
            elif isinstance(obj, list):
                for v in obj:
                    walk(v)

        walk(data)
    bad = []
    for rid in sample:
        short = mapping[rid]
        expect = resolve(short)
        actual = id_icon.get(rid)
        if expect is None:
            bad.append(f"{rid}: 文档新图标 {short!r} 无法解析")
        elif actual != expect:
            bad.append(f"{rid}: JSON={actual} != 文档解析={expect}")
    if bad:
        failures.append(f"[④] 抽查 20 条不一致: {bad}")
    info.append(f"[④] 与文档映射抽查 {len(sample)} 条（步长 {step}）：全部一致" if not bad else "")
    return sample


def main():
    icons = collect_icons()
    check_paths(icons)
    check_glow(icons)
    check_max_refs(icons)
    mapping = parse_doc_tables()
    sample = spot_check(mapping, icons)
    print("=== icon_check.py ===")
    for line in info:
        if line:
            print(" ", line)
    print("  抽查 ids:", " ".join(sample))
    if failures:
        print("ICON CHECK FAIL")
        for f_ in failures:
            print("  FAIL:", f_)
        sys.exit(1)
    print("ICON CHECK OK (ALL GREEN)")


if __name__ == "__main__":
    main()
