"""data/wands.json 校验（用途差异化重设计版）+ 商店加权抽取模拟（无需 Godot 即可运行）。

用法：
    python tools/tests/test_wands.py
退出码 0 = 全绿。

覆盖：
  1. 数据契约：55 把 / 每流派 5 把 / id 唯一 / rarity 合法 / icon 存在 /
     price 按稀有度分层 / shape 白名单 / 字段齐全
  2. 用途差异化：aoe_mult 出现 <=10 把（<20%，原 21 把=38%）；
     每流派 (shape, shape_mods 键组合) 指纹互异 >= 3；11 把传说两两互异
  3. 键白名单：shape_mods 仅允许 spell_caster.gd 消费的 11 键
     （shots/spread_angle/aoe_mult/speed_mult/pierce/bounce/split/delay/drain/
     orbit/damage_mult；slow_power/homing/explode 等一律禁止）
  4. 元素归属：element_bonus 与 school 对应（fire 法杖只给 fire 加成等）
  5. desc 一致性铁律：description 必须覆盖每个 shape_mods / cd_mult /
     damage_mult / element_bonus 的实际效果（关键词断言）
  6. 稀有度重分类（2026-08-12）：连发类（shape=rapid 或 shots>=3）必须 legendary；
     每流派至少 1 把 legendary；price 与 rarity 区间严格正相关不重叠；
     同流派内传说用途指纹两两互异
  7. 抽取模拟：1000 次 3 连抽（镜像 wand_shop.gd 公式）——
     lucky=0 时 普通>稀有>传说 递减；lucky=10 时传说占比明显高于 lucky=0
"""

import json
import os
import random
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FAILS = []

# 与 wand_shop.gd 保持一致的加权公式常量
# （2026-08-12：稀有度重分类后传说池 21 把，common 60→70 / legendary 15→13
#  保持 lucky=0/lucky=10 下 common > rare > legendary 分层递减语义）
RARITY_WEIGHT = {"common": 70.0, "rare": 25.0, "legendary": 13.0}
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
# spell_caster.gd / projectile.gd 实际消费的 shape_mods 键（白名单，禁止发明新键）
VALID_MODS = {
    "shots", "spread_angle", "aoe_mult", "speed_mult", "pierce",
    "bounce", "split", "delay", "drain", "orbit", "damage_mult",
}
# school -> 允许的 element_bonus 元素（fire 法杖只给 fire 加成）
SCHOOL_ELEMENTS = {
    "fire": {"fire"},
    "ice": {"ice"},
    "lightning": {"lightning"},
    "poison": {"poison"},
    "summon": {"summon"},
    "water": {"water"},
    "wind": set(),
    "defense": {"light"},
    "curse": {"void"},
    "crit": set(),
    "melee": {"blade"},
}
# 元素 -> 描述必须包含的中文词
ELEMENT_WORDS = {
    "fire": "火", "ice": "冰", "lightning": "雷", "poison": "毒",
    "summon": "召唤", "water": "水", "void": "虚空", "light": "光",
    "blade": "斩击", "nature": "自然", "buff": "增益",
}
# shape_mods 键 -> 描述必须包含的关键词之一（desc 一致性铁律）
MOD_KEYWORDS = {
    "aoe_mult": ["范围"],
    "delay": ["延迟"],
    "drain": ["吸血"],
    "bounce": ["反弹"],
    "pierce": ["贯穿"],
    "split": ["分裂", "溅射", "迸裂", "疫弹"],
    "orbit": ["环绕"],
    "shots": ["连发", "连射", "扇形", "召唤", "刃"],
    "spread_angle": ["扇形"],
    "speed_mult": ["弹速"],
    "damage_mult": ["伤害"],
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


def fingerprint(w):
    """用途指纹 = (shape, shape_mods 键组合)，同指纹=同用途。"""
    return (w.get("shape"), tuple(sorted(w.get("shape_mods", {}).keys())))


def main():
    with open(os.path.join(ROOT, "data", "wands.json"), encoding="utf-8") as f:
        data = json.load(f)
    wands = data.get("wands", [])

    # 1. 总数与保留项
    check(len(wands) == 55, "总数应为 55，实际 %d" % len(wands))
    basic = [w for w in wands if w["id"] == "basic_wand"]
    check(len(basic) == 1 and basic[0]["name"] == "学徒法杖",
          "必须保留 basic_wand 学徒法杖")

    # 2. 每流派恰好 5 把，流派数量 = 11
    schools = {}
    for w in wands:
        schools.setdefault(w.get("school", "?"), 0)
        schools[w["school"]] += 1
    check(len(schools) == 11, "应有 11 个流派，实际 %d：%s" % (len(schools), sorted(schools)))
    for s, n in sorted(schools.items()):
        check(n == 5, "流派 %s 有 %d 把（需 5 把）" % (s, n))

    # 3. id 唯一
    ids = [w["id"] for w in wands]
    check(len(ids) == len(set(ids)), "存在重复 id")

    # 4. 用途差异化：aoe_mult 去堆叠（<20%）
    aoe_wands = [w for w in wands if "aoe_mult" in w.get("shape_mods", {})]
    check(len(aoe_wands) <= 10,
          "aoe_mult 出现 %d 把（需 <=10 把，即 <20%%；重设计前 21 把=38%%）"
          % len(aoe_wands))
    check(len(aoe_wands) / max(len(wands), 1) < 0.20,
          "aoe_mult 占比 %.1f%% 未低于 20%%" % (100.0 * len(aoe_wands) / len(wands)))

    # 5. 用途差异化：每流派指纹互异 >= 3
    for s in sorted(schools):
        fps = {fingerprint(w) for w in wands if w.get("school") == s}
        check(len(fps) >= 3,
              "流派 %s 用途指纹仅 %d 种（需 >=3）：%s"
              % (s, len(fps), sorted(fps)))

    # 6. 稀有度重分类（2026-08-12）
    leg = [w for w in wands if w.get("rarity") == "legendary"]
    check(len(leg) == 21, "传说应 21 把，实际 %d" % len(leg))

    # 6a. 连发类强制 legendary：shape=rapid 或任意 shape 下 shots>=3
    for w in wands:
        wid = w["id"]
        mods = w.get("shape_mods", {})
        is_burst_fire = (w.get("shape") == "rapid") or (int(mods.get("shots", 1)) >= 3)
        if is_burst_fire:
            check(w.get("rarity") == "legendary",
                  "[%s] 连发类（shape=rapid 或 shots>=3）必须是 legendary，实际 %s"
                  % (wid, w.get("rarity")))

    # 6b. 每流派至少 1 把 legendary
    for s in sorted(schools):
        n_leg = sum(1 for w in wands if w.get("school") == s and w.get("rarity") == "legendary")
        check(n_leg >= 1, "流派 %s 没有 legendary 法杖" % s)

    # 6c. price 与 rarity 正相关：三档价格区间严格不重叠
    price_by_rarity = {}
    for w in wands:
        price_by_rarity.setdefault(w["rarity"], []).append(w["price"])
    p_c = price_by_rarity.get("common", [])
    p_r = price_by_rarity.get("rare", [])
    p_l = price_by_rarity.get("legendary", [])
    check(max(p_c) < min(p_r), "common 最高价 %d 应低于 rare 最低价 %d（正相关）"
          % (max(p_c), min(p_r)))
    check(max(p_r) < min(p_l), "rare 最高价 %d 应低于 legendary 最低价 %d（正相关）"
          % (max(p_r), min(p_l)))

    # 6d. 同流派内传说法杖用途两两互异（跨流派 rapid 连发共享指纹属预期）
    leg_fps = {}
    for w in leg:
        fp = fingerprint(w)
        key = (w.get("school"), fp)
        if key in leg_fps:
            check(False, "同流派传说用途重复：%s 与 %s 同为 %s"
                  % (leg_fps[key], w["id"], fp))
        leg_fps[key] = w["id"]

    # 7. 逐条字段校验 + 白名单 + 元素归属 + desc 一致性
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

        desc = str(w.get("description", ""))
        check(len(desc) >= 5, "[%s] description 过短" % wid)

        # 元素归属：school 对应
        school = w.get("school", "?")
        allowed = SCHOOL_ELEMENTS.get(school, set())
        for elem in w.get("element_bonus", {}):
            check(elem in VALID_ELEMENTS, "[%s] element_bonus 元素非法：%s" % (wid, elem))
            check(elem in allowed,
                  "[%s] school=%s 但 element_bonus 含 %s（元素与流派不对应）"
                  % (wid, school, elem))
            word = ELEMENT_WORDS.get(elem, elem)
            check(word in desc,
                  "[%s] 描述未提元素 %s（应有'%s'字样）" % (wid, elem, word))

        # 键白名单
        mods = w.get("shape_mods", {})
        for k in mods:
            check(k in VALID_MODS,
                  "[%s] shape_mods 含白名单外键 %s（spell_caster 不消费）" % (wid, k))

        # desc 一致性：每个 mod 必须被描述覆盖
        for k, kws in MOD_KEYWORDS.items():
            if k not in mods:
                continue
            check(any(kw in desc for kw in kws),
                  "[%s] 描述未覆盖 shape_mods.%s（需含：%s）"
                  % (wid, k, "/".join(kws)))
        if "speed_mult" in mods:
            v = mods["speed_mult"]
            if v > 1.0:
                check("弹速 +" in desc, "[%s] speed_mult>1 但描述无'弹速 +'" % wid)
            elif v < 1.0:
                check("弹速 -" in desc, "[%s] speed_mult<1 但描述无'弹速 -'" % wid)
        if "damage_mult" in mods:
            v = mods["damage_mult"]
            if v > 1.0:
                check(re.search(r"伤害 [+-]?\d+%", desc) is not None,
                      "[%s] damage_mult>1 但描述无'伤害 +X%%'" % wid)
            elif v < 1.0:
                check(("单发" in desc and re.search(r"\d+% 伤害", desc)) or "伤害 -" in desc,
                      "[%s] damage_mult<1 但描述无'单发 X%% 伤害'或'伤害 -X%%'" % wid)
        if w.get("damage_mult", 1.0) != 1.0:
            check("伤害" in desc,
                  "[%s] 顶层 damage_mult=%s 但描述未提伤害"
                  % (wid, w.get("damage_mult")))
        if w.get("cd_mult", 1.0) != 1.0:
            check("冷却" in desc,
                  "[%s] cd_mult=%s 但描述未提冷却" % (wid, w.get("cd_mult")))

    # 7. 抽取模拟（镜像商店公式，1000 次 × 3 把）
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

    # 8. 汇总输出
    per_school = {s: len({fingerprint(w) for w in wands if w.get("school") == s})
                  for s in sorted(schools)}
    print("wands: %d | schools: %d | aoe_mult: %d (%.1f%%) | rarity: %s" % (
        len(wands), len(schools), len(aoe_wands),
        100.0 * len(aoe_wands) / len(wands),
        {r: sum(1 for w in wands if w["rarity"] == r)
         for r in ("common", "rare", "legendary")}))
    print("distinct uses per school: %s" % per_school)
    print("aoe wands: %s" % ", ".join(w["id"] for w in aoe_wands))
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
