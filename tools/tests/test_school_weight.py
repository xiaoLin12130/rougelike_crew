"""同流派升级权重平衡测试（2026-08-12）。

镜像 game_state.gd roll_item_choices / _element_weight 的抽卡逻辑，
对「持有 5 件 fire 流派道具」场景分别用旧公式（+10%/件/关，上限 +150%）与
新公式（+3.33%/件/关，上限 +50%）模拟 1000 次三选一。
统计两类指标：
  a) 加权槽位 fire 占比（权重加成的直接度量，不含强制法术槽/保底槽）
     —— 断言新公式相比旧公式降幅 >= 15%；
  b) 整体三选一 fire 占比（含保底）—— 断言新 < 旧，且保底保留
     （新公式整体占比仍明显高于无加权基线）。

用法：python tools/tests/test_school_weight.py
"""

import json
import os
import random
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

SCHOOL_TAGS = ["fire", "ice", "lightning", "poison", "summon", "water",
               "wind", "blade", "defense", "curse", "crit", "speed"]


def load():
    with open(os.path.join(ROOT, "data", "items.json"), encoding="utf-8") as f:
        items = json.load(f)["items"]
    with open(os.path.join(ROOT, "data", "drops.json"), encoding="utf-8") as f:
        drops = json.load(f)
    with open(os.path.join(ROOT, "data", "spells.json"), encoding="utf-8") as f:
        spells = json.load(f)
    return items, drops["item_rarity_weights"], spells


def element_key(defn, spells):
    tags = defn.get("tags", [])
    for el in SCHOOL_TAGS:
        if el in tags:
            return el
    if str(defn.get("id", "")).startswith("spell_part:"):
        parts = str(defn["id"]).split(":")
        if len(parts) > 1:
            for c in spells["cores"]:
                if c.get("id") == parts[1]:
                    return c.get("element", "")
    return ""


def element_weight(defn, base_weights, holdings, lv_factor, formula):
    w = float(base_weights.get(defn.get("rarity", "common"), 0.2))
    el = element_key(defn, None)
    if el and el in holdings:
        n = holdings[el]
        if n > 0:
            per, cap = formula
            w *= min(1.0 + per * n * lv_factor, 1.0 + cap)
    return w


def simulate(items, base_weights, spells, holdings, formula, count=3, trials=1000):
    """镜像 roll_item_choices：混合法术部件 + 道具，元素加权 + 主流派保底。"""
    counts = {"total": 0, "fire": 0, "weighted_total": 0, "weighted_fire": 0}
    lv_factor = 1.0  # level=1
    for _ in range(trials):
        pool = list(items)
        choices = []
        # 网格未满必含 1 个法术部件（简化：固定一个 rare 法术选项，不计 fire 统计）
        # 强制法术槽（不计入加权槽位统计；元素门控下持有 fire 时高概率出 fire 法术）
        choices.append({"id": "spell_part:ice_shard:rapid", "tags": ["spell_part"],
                        "rarity": "rare", "_spell": True})
        main_el = "fire"
        main_n = holdings.get("fire", 0)
        main_pool = [it for it in pool if element_key(it, spells) == main_el]
        if main_n >= 3 and main_pool and len(choices) < count:
            pick = random.choice(main_pool)
            choices.append(pick)
            pool.remove(pick)
            main_pool.remove(pick)
        while len(choices) < count and pool:
            total = sum(element_weight(it, base_weights, holdings, lv_factor, formula)
                        for it in pool)
            roll = random.random() * total
            acc = 0.0
            picked = len(pool) - 1
            for i, it in enumerate(pool):
                acc += element_weight(it, base_weights, holdings, lv_factor, formula)
                if roll <= acc:
                    picked = i
                    break
            picked_def = pool[picked]
            choices.append(picked_def)
            pool.remove(pool[picked])
            counts["weighted_total"] += 1
            if element_key(picked_def, spells) == "fire":
                counts["weighted_fire"] += 1
        for c in choices:
            counts["total"] += 1
            if element_key(c, spells) == "fire":
                counts["fire"] += 1
    return counts


def main():
    random.seed(20260812)
    items, base_weights, spells = load()
    items = [it for it in items if it.get("type") == "item"]
    holdings = {"fire": 5}  # 同流派 5 件（用户指定场景）
    old_formula = (0.10, 1.5)   # 旧：+10%/件/关，上限 +150%
    new_formula = (0.0333, 0.5) # 新：+3.33%/件/关，上限 +50%
    old_c = simulate(items, base_weights, spells, holdings, old_formula)
    new_c = simulate(items, base_weights, spells, holdings, new_formula)
    old_share = old_c["fire"] / old_c["total"]
    new_share = new_c["fire"] / new_c["total"]
    drop = (old_share - new_share) / old_share
    old_w = old_c["weighted_fire"] / old_c["weighted_total"]
    new_w = new_c["weighted_fire"] / new_c["weighted_total"]
    w_drop = (old_w - new_w) / old_w
    print("weighted slot fire share: old %.2f%% -> new %.2f%% (drop %.1f%%)"
          % (old_w * 100, new_w * 100, w_drop * 100))
    print("overall fire share (with pity): old %.2f%% -> new %.2f%% (drop %.1f%%)"
          % (old_share * 100, new_share * 100, drop * 100))
    fails = []
    if not (w_drop >= 0.15):
        fails.append("加权槽位 fire 占比降幅 %.1f%% < 15%%" % (w_drop * 100))
    if not (new_w < old_w):
        fails.append("新公式加权槽位占比 %.3f 未低于旧公式 %.3f" % (new_w, old_w))
    if not (new_share < old_share):
        fails.append("新公式整体占比 %.3f 未低于旧公式 %.3f" % (new_share, old_share))
    # 保底仍保留：5 件同流派时 fire 占比应明显高于均匀分布（无加权时的期望）
    baseline = sum(1 for it in items if element_key(it, spells) == "fire") / len(items)
    if not (new_share > baseline * 1.2):
        fails.append("保底/加成失效：新公式 fire 占比 %.3f 未明显高于基线 %.3f"
                     % (new_share, baseline))
    if fails:
        print("FAILED:")
        for f in fails:
            print("  -", f)
        sys.exit(1)
    print("ALL PASS")


if __name__ == "__main__":
    main()
