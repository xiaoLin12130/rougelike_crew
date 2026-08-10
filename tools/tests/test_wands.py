"""data/wands.json 校验 + 商店加权抽取模拟（无需 Godot 即可运行）。

用法：
    python tools/tests/test_wands.py
退出码 0 = 全绿。

覆盖：
  1. 数据契约：55 把 / 每流派 ≥5 / id 唯一 / rarity 合法 / icon 存在 /
     price 按稀有度分层 / shape 白名单 / 字段齐全 / shape_mods 仅用生效键
  2. 抽取模拟：1000 次 3 连抽（镜像 wand_shop.gd 公式）——
     lucky=0 时 普通>稀有>传说 递减；lucky=10 时传说占比明显高于 lucky=0
"""

import json
import os
import random
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FAILS = []

# 与 wand_shop.gd 保持一致的加权公式常量
RARITY_WEIGHT = {"common": 60.0, "rare": 25.0, "legendary": 15.0}
LUCKY_RARITY_BOOST = {"common": 1.0, "rare": 2.0, "legendary": 4.0}
LUCKY_PER_STACK = 0.06

PRICE_BANDS = {
    "common": (120, 260),
    "rare": (300, 600),
    "legendary": (700, 1200),
}
VALID_SHAPES = {
    "none", "burst", "rapid", "orbit", "scatter", "frost", "pierce",
    "poison", "light", "chain", "split", "bounce", "summon",
}
REQUIRED_KEYS = {
    "id", "name", "rarity", "price", "shape", "damage_mult", "cd_mult",
    "element_bonus", "shape_mods", "description", "icon", "school",
}
VALID_ELEMENTS = {
    "fire", "ice", "water", "lightning", "poison", "void", "light",
    "nature", "summon", "blade", "buff",
}
# spell_caster.gd / projectile.gd 实际消费的 shape_mods 键（其余键无效，禁止写）
VALID_MODS = {
    "damage_mult", "aoe_mult", "speed_mult", "shots", "spread_angle",
    "pierce", "bounce", "split", "delay", "drain", "orbit", "slow_power",
}


def check(cond, msg):
    if not cond:
        FAILS.append(msg)


def rarity_weight(rarity, lucky):
    base = RARITY_WEIGHT.get(rarity, 10.0)
    boost = LUCKY_RARITY_BOOST.get(rarity, 1.0)
    return base * (1.0 + max(lucky, 0) * LUCKY_PER_STACK * boost)


def weighted_pick(pool, lucky, count):
    pool = list(pool)
    out = []
    while len(out) < count and pool:
        total = sum(rarity_weight(w["rarity"], lucky) for w in pool)
        r = random.random() * total
        idx = 0
        for i, w in enumerate(pool):
            r -= rarity_weight(w["rarity"], lucky)
            if r <= 0.0:
                idx = i
                break
        out.append(pool.pop(idx))
    return out


def main():
    with open(os.path.join(ROOT, "data", "wands.json"), encoding="utf-8") as f:
        data = json.load(f)
    wands = data.get("wands", [])

    # 1. 总数与保留项
    check(len(wands) == 55, "总数应为 55，实际 %d" % len(wands))
    basic = [w for w in wands if w["id"] == "basic_wand"]
    check(len(basic) == 1 and basic[0]["name"] == "学徒法杖",
          "必须保留 basic_wand 学徒法杖")

    # 2. 每流派 ≥5 把，流派数量 = 11
    schools = {}
    for w in wands:
        schools.setdefault(w.get("school", "?"), 0)
        schools[w["school"]] += 1
    check(len(schools) == 11, "应有 11 个流派，实际 %d：%s" % (len(schools), sorted(schools)))
    for s, n in sorted(schools.items()):
        check(n >= 5, "流派 %s 只有 %d 把（需 ≥5）" % (s, n))

    # 3. id 唯一
    ids = [w["id"] for w in wands]
    check(len(ids) == len(set(ids)), "存在重复 id")

    # 4. 逐条字段校验
    for w in wands:
        wid = w.get("id", "?")
        for k in REQUIRED_KEYS:
            check(k in w, "[%s] 缺少字段 %s" % (wid, k))
        check(w.get("rarity") in ("common", "rare", "legendary"),
              "[%s] rarity 非法：%s" % (wid, w.get("rarity")))
        icon = str(w.get("icon", ""))
        check(icon.startswith("res://"), "[%s] icon 应使用 res:// 路径" % wid)
        rel = icon[len("res://"):].replace("/", os.sep)
        check(os.path.isfile(os.path.join(ROOT, rel)),
              "[%s] icon 文件不存在：%s" % (wid, icon))
        lo, hi = PRICE_BANDS.get(w.get("rarity"), (0, 0))
        p = w.get("price", 0)
        check(lo <= p <= hi,
              "[%s] price %d 超出 %s 档位 %d-%d" % (wid, p, w.get("rarity"), lo, hi))
        check(w.get("shape") in VALID_SHAPES,
              "[%s] shape 非法：%s（spell_caster 不支持会白板）" % (wid, w.get("shape")))
        for elem in w.get("element_bonus", {}):
            check(elem in VALID_ELEMENTS, "[%s] element_bonus 元素非法：%s" % (wid, elem))
        for k in w.get("shape_mods", {}):
            check(k in VALID_MODS, "[%s] shape_mods 含无效键 %s（spell_caster 不消费）" % (wid, k))

    # 5. 抽取模拟（镜像商店公式，1000 次 × 3 把）
    random.seed(20260810)
    trials = 1000

    def simulate(lucky):
        counts = {"common": 0, "rare": 0, "legendary": 0}
        for _ in range(trials):
            for w in weighted_pick(wands, lucky, 3):
                counts[w["rarity"]] += 1
        total = sum(counts.values())
        return {k: v / total for k, v in counts.items()}

    s0 = simulate(0)
    s10 = simulate(10)
    check(s0["common"] > s0["rare"] > s0["legendary"],
          "lucky=0 应 普通>稀有>传说，实际 %.3f/%.3f/%.3f"
          % (s0["common"], s0["rare"], s0["legendary"]))
    check(s10["common"] > s10["rare"] > s10["legendary"],
          "lucky=10 应仍 普通>稀有>传说，实际 %.3f/%.3f/%.3f"
          % (s10["common"], s10["rare"], s10["legendary"]))
    check(s10["legendary"] > s0["legendary"] + 0.05,
          "lucky=10 传说占比 %.3f 应明显高于 lucky=0 的 %.3f（+5pp 以上）"
          % (s10["legendary"], s0["legendary"]))

    print("wands: %d | schools: %d | rarity: %s" % (
        len(wands), len(schools),
        {r: sum(1 for w in wands if w["rarity"] == r)
         for r in ("common", "rare", "legendary")}))
    print("sim lucky=0 : common %.1f%% rare %.1f%% legendary %.1f%%"
          % (s0["common"] * 100, s0["rare"] * 100, s0["legendary"] * 100))
    print("sim lucky=10: common %.1f%% rare %.1f%% legendary %.1f%%"
          % (s10["common"] * 100, s10["rare"] * 100, s10["legendary"] * 100))

    if FAILS:
        print("FAILED (%d):" % len(FAILS))
        for m in FAILS:
            print("  -", m)
        sys.exit(1)
    print("ALL PASS")


if __name__ == "__main__":
    main()
