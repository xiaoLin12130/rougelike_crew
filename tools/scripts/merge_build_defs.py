"""流派构筑合库：把子代理产出的 .tools/build_defs/<流派>.json 合并进 data/items.json。

用法：python tools/scripts/merge_build_defs.py
- 数值型构筑：转 items.json 条目（curve 展示用，实际效果由流派脚本按 total_stacks 生效）
- 机制型构筑：转 items.json 条目（curve 用 threshold 占位，tags 含 "mechanic:<id>" 供脚本读取）
"""

import io
import json
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DEFS_DIR = os.path.join(ROOT, ".tools", "build_defs")
ITEMS_PATH = os.path.join(ROOT, "data", "items.json")
DEFAULT_ICON = "res://assets/icons/verarc/glow.png"


def main() -> int:
    items = json.load(io.open(ITEMS_PATH, encoding="utf-8"))
    existing = {i["id"] for i in items["items"]}
    added = 0
    for fn in sorted(os.listdir(DEFS_DIR)):
        if not fn.endswith(".json") or fn == "build_items_draft.json" or fn.endswith("_mech.json"):
            continue
        data = json.load(io.open(os.path.join(DEFS_DIR, fn), encoding="utf-8"))
        school = data.get("school", fn[:-5])
        for it in data.get("items", []):
            iid = it.get("id", "")
            if not iid or iid in existing:
                continue
            curve = it.get("curve", {"type": "linear", "base": 0.1, "k": 0.1})
            tags = list(it.get("tags", []))
            if it.get("type") == "mechanic":
                curve = {"type": "threshold", "base": 0, "step": 1, "threshold": 1}
                tags.append("mechanic:" + iid)
            items["items"].append({
                "id": iid,
                "name": it.get("name", iid),
                "rarity": it.get("rarity", "common"),
                "type": "item",
                "slot": None,
                "curve": curve,
                "description": it.get("effect", ""),
                "icon": it.get("icon") or DEFAULT_ICON,
                "tags": tags,
            })
            existing.add(iid)
            added += 1
        # 机制表也落一份引用（供测试校验）
        mech = data.get("mechanisms", [])
        if mech:
            meta_path = os.path.join(DEFS_DIR, fn[:-5] + "_mech.json")
            io.open(meta_path, "w", encoding="utf-8").write(
                json.dumps({"school": school, "mechanisms": mech}, ensure_ascii=False, indent=1))
    io.open(ITEMS_PATH, "w", encoding="utf-8", newline="\n").write(
        json.dumps(items, ensure_ascii=False, indent=1))
    print("merged:", added, "total items:", len(items["items"]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
