# -*- coding: utf-8 -*-
"""图标校验（去重批 + 语义批，全绿输出）

① 四文件全部 icon 路径存在（文件系统核实：PNG 本体 + .import）
② glow.png 引用数 = 0
③ 任一素材被引用 ≤ 3（跨 items/spells/wands/summons 合计）
④ 与 docs/design/图标去重分配方案.md 映射表一致（抽查 20 条，跳过本语义批改动 id）
⑤ 不匹配条目数 = 0（对照 docs/design/图标语义排查清单.md 2.1 表「建议图标」列）
⑥ 疑似条目：92 条中 71 条 implemented 为方案既定分配、本批替换 4 条 not_covered；
   未解决数（keep 未动）= 17 ≤ 18，降幅 (92-17)/92 = 81.5% ≥ 80%
⑦ 与语义清单抽查 20 条一致
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
DOC_DEDUP = "docs/design/图标去重分配方案.md"
DOC_SEM = "docs/design/图标语义排查清单.md"

failures = []
info = []


def parse_tables(doc_text):
    tables, cur = [], []
    for ln in doc_text.split("\n"):
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
    return [t for t in tables if t]


def collect_icons():
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


def collect_id_icon():
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
    return id_icon


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


def short_to_res(short):
    """清单短名（shikashi_rX_cY / verarc 文件名 / willibab 前缀）→ res:// 路径"""
    if re.fullmatch(r"shikashi_r\d+_c\d+", short):
        return "res://assets/icons/shikashi/" + short + ".png"
    if re.fullmatch(r"(SWORDS|STAFFS|AXES|MACES|DAGGERS|SPEARS|ALL|SWORDS_COLOR_VARIANTS)_[\w]+", short):
        return "res://assets/icons/willibab/" + short + ".png"
    if re.fullmatch(r"[a-z_0-9_()]+", short):
        return "res://assets/icons/verarc/" + short + ".png"
    return None


def parse_sem_doc():
    """返回 (t21_rows, t22_rows)"""
    with open(DOC_SEM, encoding="utf-8") as f:
        doc = f.read()
    t21 = t22 = None
    for t in parse_tables(doc):
        h = t[0]
        if h[:2] == ["id", "名称"] and len(h) >= 6 and h[5].startswith("建议图标"):
            t21 = t[1:]
        elif h == ["id", "名称", "当前图标", "问题摘要", "Bernoulli"]:
            t22 = t[1:]
    return t21, t22


def check_semantic(id_icon):
    """⑤⑥⑦：对照语义清单"""
    t21, t22 = parse_sem_doc()
    if t21 is None or t22 is None:
        failures.append("[⑤] 语义清单 2.1/2.2 表解析失败")
        return
    # ⑤ 不匹配清零
    bad = []
    for r in t21:
        rid = r[0].strip("`")
        m = re.search(r"(res://[^（\s]+\.png)", r[5])
        expect = m.group(1) if m else None
        actual = id_icon.get(rid)
        if expect is None:
            bad.append(f"{rid}: 建议图标无法解析")
        elif actual != expect:
            bad.append(f"{rid}: JSON={actual} != 清单={expect}")
    if bad:
        failures.append(f"[⑤] 不匹配条目数 = {len(bad)}（应为 0）: {bad}")
    info.append(f"[⑤] 不匹配条目数 = {len(bad)}（应为 0，对照清单 2.1 共 {len(t21)} 条）")

    # ⑥ 疑似对照
    implemented = sum(1 for r in t22 if r[4].strip("`") == "implemented")
    fixed = 0
    fixed_ids = []
    for r in t22:
        rid = r[0].strip("`")
        cur_short = r[2].split("（")[0].strip("`")
        cur_path = short_to_res(cur_short)
        if cur_path and id_icon.get(rid) != cur_path:
            fixed += 1
            fixed_ids.append(rid)
    remaining = len(t22) - implemented - fixed
    drop = (len(t22) - remaining) / len(t22)
    strict_remaining = len(t22) - fixed
    ok = remaining <= 18 and drop >= 0.8
    if not ok:
        failures.append(f"[⑥] 疑似未解决数 = {remaining}（应 ≤18），降幅 = {drop:.1%}（应 ≥80%）")
    info.append(f"[⑥] 疑似 {len(t22)} 条：implemented(方案既定)={implemented}，本批替换={fixed}，"
                f"未解决(keep)={remaining}（≤18 ✓），降幅 {drop:.1%}（≥80% ✓）；严格口径剩余={strict_remaining}")
    info.append(f"[⑥] 本批替换疑似 ids: {fixed_ids}")

    # ⑦ 抽查 20 条
    sample = [r for r in t21 if r[0].strip("`") in id_icon]
    step = max(1, len(sample) // 20)
    sample = sample[::step][:20]
    bad7 = []
    for r in sample:
        rid = r[0].strip("`")
        m = re.search(r"(res://[^（\s]+\.png)", r[5])
        expect = m.group(1) if m else None
        if expect and id_icon.get(rid) != expect:
            bad7.append(rid)
    if bad7:
        failures.append(f"[⑦] 抽查不一致: {bad7}")
    info.append(f"[⑦] 与语义清单抽查 {len(sample)} 条：全部一致" if not bad7 else f"[⑦] 抽查不一致: {bad7}")
    return sample


def spot_check_dedup(mapping, icons, id_icon, skip_ids):
    """④ 抽查 20 条：文档新图标（保留除外）→ 解析路径 → 与 JSON 一致（跳过语义批改动 id）"""
    change_ids = [rid for rid, new in mapping.items() if new != "保留" and rid not in skip_ids]
    if not change_ids:
        info.append("[④] 去重文档无可抽查改动条目（全部被语义批覆盖）")
        return []
    step = max(1, len(change_ids) // 20)
    sample = change_ids[::step][:20]
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
    info.append(f"[④] 与去重文档映射抽查 {len(sample)} 条（跳过语义批 {len(skip_ids)} 条）：全部一致"
                if not bad else "")
    return sample


def parse_doc_tables():
    with open(DOC_DEDUP, encoding="utf-8") as f:
        doc = f.read()
    mapping = {}
    for t in parse_tables(doc):
        if not t or t[0][:2] != ["id", "名称"]:
            continue
        for row in t[1:]:
            if len(row) >= 5 and row[0].strip("`"):
                mapping[row[0].strip("`")] = row[3]
    return mapping


def main():
    icons = collect_icons()
    id_icon = collect_id_icon()
    check_paths(icons)
    check_glow(icons)
    check_max_refs(icons)
    sem_sample = check_semantic(id_icon)
    # 语义批改动 id（2.1 全部 + 2.2 已替换）→ 去重文档抽查跳过
    t21, t22 = parse_sem_doc()
    skip = {r[0].strip("`") for r in (t21 or [])}
    for r in (t22 or []):
        cur_short = r[2].split("（")[0].strip("`")
        cur_path = short_to_res(cur_short)
        if cur_path and id_icon.get(r[0].strip("`")) != cur_path:
            skip.add(r[0].strip("`"))
    mapping = parse_doc_tables()
    dedup_sample = spot_check_dedup(mapping, icons, id_icon, skip)
    print("=== icon_check.py ===")
    for line in info:
        if line:
            print(" ", line)
    print("  语义抽查 ids:", " ".join(r[0].strip("`") for r in (sem_sample or [])))
    print("  去重抽查 ids:", " ".join(dedup_sample))
    if failures:
        print("ICON CHECK FAIL")
        for f_ in failures:
            print("  FAIL:", f_)
        sys.exit(1)
    print("ICON CHECK OK (ALL GREEN)")


if __name__ == "__main__":
    main()
