"""Batch-A data-layer dedup test (run without Godot).

Usage:
    python tools/tests/test_data_dedup.py
Exit code 0 = all pass.
"""

import json
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DATA = os.path.join(ROOT, "data")

FAILS = []


def check(cond, msg):
    if not cond:
        FAILS.append(msg)


def load(name):
    with open(os.path.join(DATA, name + ".json"), encoding="utf-8") as f:
        return json.load(f)


OLD_IDS = ("stone_armor", "thorn_reflect", "blood_thorn", "summon_book")
NEW_IDS = ("defense_bedrock", "defense_thorn_refit", "defense_blood_thorn", "summon_1")
TRINKET_IDS = ("trinket_ember", "trinket_frost", "trinket_storm", "wand_expander")


def main():
    items = load("items")["items"]
    by_id = {it["id"]: it for it in items}

    # 1) 旧 id 已移除、新 id 存在
    for old in OLD_IDS:
        check(old not in by_id, f"旧 id {old} 应从 items.json 移除")
    for new in NEW_IDS:
        check(new in by_id, f"新 id {new} 应存在")

    # 2) 新 id 曲线与去重设计一致
    check(abs(by_id["defense_bedrock"]["curve"]["cap"] - 0.35) < 1e-9, "defense_bedrock cap 35%")
    check(abs(by_id["defense_bedrock"]["curve"]["base"] - 0.06) < 1e-9, "defense_bedrock base 6%")
    check(abs(by_id["defense_thorn_refit"]["curve"]["base"] - 0.30) < 1e-9, "defense_thorn_refit base 30%")
    check(abs(by_id["defense_thorn_refit"]["curve"]["cap"] - 0.65) < 1e-9, "defense_thorn_refit cap 65%")
    check(abs(by_id["defense_blood_thorn"]["curve"]["base"] - 0.02) < 1e-9, "defense_blood_thorn base 2%")
    check(abs(by_id["defense_blood_thorn"]["curve"]["cap"] - 0.04) < 1e-9, "defense_blood_thorn cap 4%")
    check(by_id["summon_1"]["curve"]["type"] == "threshold", "summon_1 threshold curve")

    # 3) 代码 0 残留：旧 id 不得以真实消费调用点形式出现（注释/迁移说明允许）
    call_pat = re.compile(
        r"(?:total_stacks|item_def|_stacks|_curve_value)\s*\(\s*\"(?:%s)\"\s*\)"
        % "|".join(OLD_IDS)
    )
    dict_pat = re.compile(r"run\.items\[\s*\"(?:%s)\"\s*\]" % "|".join(OLD_IDS))
    const_pat = re.compile(
        r"const\s+[A-Za-z_][A-Za-z0-9_]*\s*(?::=|=)\s*\"(?:%s)\"" % "|".join(OLD_IDS)
    )
    hits = []
    for base in ("scripts", "scenes"):
        for dirpath, _dirnames, filenames in os.walk(os.path.join(ROOT, base)):
            for fn in filenames:
                if not fn.endswith(".gd"):
                    continue
                with open(os.path.join(dirpath, fn), encoding="utf-8") as f:
                    txt = f.read()
                for pat in (call_pat, dict_pat, const_pat):
                    for m in pat.finditer(txt):
                        hits.append(f"{os.path.relpath(os.path.join(dirpath, fn), ROOT)}: {m.group(0)}")
    check(not hits, f"旧 id 代码残留 {len(hits)} 处: {hits[:5]}")

    # 4) trinket 道具保留（独立掉落/商店渠道），且 roll_item_choices 有排除逻辑
    for tid in TRINKET_IDS:
        check(tid in by_id, f"trinket 道具 {tid} 应保留（走独立掉落渠道）")
        check(by_id[tid].get("type") == "trinket", f"{tid} type 应为 trinket")
    gs_src = open(os.path.join(ROOT, "scripts", "core", "game_state.gd"), encoding="utf-8").read()
    check('"trinket"' in gs_src, "game_state.gd 应包含 trinket 池排除逻辑")
    check('"disabled"' in gs_src, "game_state.gd 应包含 disabled 池过滤逻辑")


if __name__ == "__main__":
    main()
    if FAILS:
        for f in FAILS:
            print("FAIL:", f)
        sys.exit(1)
    print("DATA DEDUP TEST OK")
    sys.exit(0)
