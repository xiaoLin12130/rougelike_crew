"""从《流派构筑大全.md》解析全部构筑定义 → .tools/build_defs/build_items_draft.json
用法：python tools/scripts/parse_build_defs.py
"""

import io
import json
import os
import re

SRC = os.path.join(os.path.dirname(__file__), "..", "..", "docs", "design", "流派构筑大全.md")
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "..", ".tools", "build_defs")

prefix_map = {
    "火系": "fire_", "冰系": "ice_", "雷系": "thunder_", "毒系": "poison_",
    "召唤": "summon_", "近战": "melee_", "水控": "water_", "防御": "defense_",
    "诅咒": "curse_", "暴击": "crit_", "移速": "wind_",
}


def main():
    lines = io.open(SRC, encoding="utf-8").read().splitlines()
    out = []
    cur_school = None
    cur_section = None
    for ln in lines:
        m = re.match(r"^## (\d+)\. (.+?)[（(]", ln)
        if m:
            cur_school = m.group(2)
            cur_section = None
            continue
        if cur_school is None:
            continue
        if "数值构筑" in ln:
            cur_section = "numeric"
            continue
        if "机制构筑" in ln:
            cur_section = "mechanic"
            continue
        if not ln.startswith("|") or cur_section is None:
            continue
        cells = [c.strip() for c in ln.strip().strip("|").split("|")]
        if len(cells) < 3 or not re.match(r"^(火|冰|雷|毒|召|近|水|防|咒|暴|移)\d+", cells[0]):
            continue
        prefix = None
        for k, v in prefix_map.items():
            if k in cur_school:
                prefix = v
                break
        if prefix is None:
            continue
        name = cells[1]
        effect = cells[2] if len(cells) > 2 else ""
        if cur_section == "mechanic":
            linkage = cells[3] if len(cells) > 3 else ""
            hook = cells[4] if len(cells) > 4 else ""
            out.append({"school": cur_school, "type": "mechanic", "name": name,
                        "effect": effect, "linkage": linkage, "hook": hook})
        else:
            curve_raw = cells[3] if len(cells) > 3 else ""
            out.append({"school": cur_school, "type": "numeric", "name": name,
                        "effect": effect, "curve": curve_raw})

    os.makedirs(OUT_DIR, exist_ok=True)
    dst = os.path.join(OUT_DIR, "build_items_draft.json")
    io.open(dst, "w", encoding="utf-8").write(json.dumps(out, ensure_ascii=False, indent=1))
    schools = {}
    for i in out:
        schools[i["school"]] = schools.get(i["school"], 0) + 1
    print("parsed:", len(out))
    for k, v in schools.items():
        print(" ", k, v)
    print("saved:", dst)


if __name__ == "__main__":
    main()
