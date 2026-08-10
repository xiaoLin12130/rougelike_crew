"""Numeric consistency tests for data tables (run without Godot).

Usage:
    python tools/tests/test_curves.py
Exit code 0 = all pass.
"""

import json
import math
import os
import sys
from collections import Counter

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DATA = os.path.join(ROOT, "data")

FAILS = []


def check(cond, msg):
    if not cond:
        FAILS.append(msg)


def load(name):
    with open(os.path.join(DATA, name + ".json"), encoding="utf-8") as f:
        return json.load(f)


def curve_value(c, n):
    t = c["type"]
    base = c.get("base", 0.0)
    if t in ("linear", "tradeoff"):
        v = base * (1.0 + c.get("k", 0.0) * n)
    elif t == "exp_proc":
        v = 1.0 - math.pow(1.0 - c.get("p", 0.1), n + 1)
    elif t == "threshold":
        T = max(c.get("threshold", 1), 1)
        v = base + c.get("step", 0.0) * (n // T)
    elif t == "multiplicative":
        v = math.pow(base, n)
    else:
        raise ValueError(t)
    if "cap" in c:
        if t == "multiplicative" and base < 1.0:
            v = max(v, c["cap"])  # 乘性衰减类：cap 为下限
        else:
            v = min(v, c["cap"])
    return v


def main():
    balance = load("balance")
    items = load("items")["items"]
    spells = load("spells")
    enemies = load("enemies")
    levels = load("levels")
    drops = load("drops")
    wands = load("wands")

    # --- basic schema integrity ---
    item_ids = [i["id"] for i in items]
    check(len(item_ids) == len(set(item_ids)), "item ids unique")
    for i in items:
        check(i["curve"]["type"] in ("linear", "exp_proc", "threshold", "multiplicative", "tradeoff"),
              f"item {i['id']} curve type")
        for f in ("base",):
            check(f in i["curve"], f"item {i['id']} curve has {f}")
        if i["curve"]["type"] in ("linear", "tradeoff"):
            check("k" in i["curve"], f"item {i['id']} linear needs k")
        if i["curve"]["type"] == "exp_proc":
            p = i["curve"].get("p", 0)
            check(0 < p <= 1, f"item {i['id']} exp_proc p in (0,1]")
        if i["curve"]["type"] == "threshold":
            check(i["curve"].get("threshold", 0) >= 1, f"item {i['id']} threshold >= 1")
        if i["curve"]["type"] == "multiplicative":
            check(i["curve"]["base"] > 0 and abs(i["curve"]["base"] - 1.0) > 1e-9,
                  f"item {i['id']} multiplicative base >0 and !=1")
        check(0 <= i["curve"].get("base", 0), f"item {i['id']} base >= 0")
        check(i["rarity"] in ("common", "rare", "legendary"), f"item {i['id']} rarity")
        check(i["type"] in ("item", "trinket", "memory"), f"item {i['id']} type")

    # --- 流派构筑补全（school_fill_ice_summon）---
    # 门控 id 与 scripts/synergies/ice_synergy.gd / summon_synergy.gd 的
    # _stacks("ice_mN") / _stacks("summon_mN") 消费点一一对应（只读契约）
    ICE_GATES = {f"ice_m{i}" for i in range(1, 11)}
    SUMMON_GATES = {f"summon_m{i}" for i in range(1, 11)}
    def school_items(school):
        return [i for i in items
                if str(i["id"]).startswith(school + "_") or school in i.get("tags", [])]

    for school, gates in (("ice", ICE_GATES), ("summon", SUMMON_GATES)):
        school_it = school_items(school)
        check(len(school_it) >= 20,
              f"{school} 流派道具数 >= 20（现 {len(school_it)}）")
        rarities = Counter(i["rarity"] for i in school_it)
        check(rarities.get("common", 0) >= 8, f"{school} 普通 >= 8（现 {rarities.get('common', 0)}）")
        check(rarities.get("rare", 0) >= 8, f"{school} 稀有 >= 8（现 {rarities.get('rare', 0)}）")
        check(rarities.get("legendary", 0) >= 4, f"{school} 传说 >= 4（现 {rarities.get('legendary', 0)}）")
        # 图标必须存在（assets/icons 下）；流派内不得新增共用图标。
        # 存量共用对（school_fill_ice_summon 之前已存在，契约禁止修改现有条目）：
        #   ice_spell.png: ice_1 + trinket_frost；frozen.png: ice_2 + ice_6；slowed.png: ice_10 + ice_m7
        LEGACY_ICON_SHARES = {
            "res://assets/icons/verarc/ice_spell.png": {"ice_1", "trinket_frost"},
            "res://assets/icons/verarc/frozen.png": {"ice_2", "ice_6"},
            "res://assets/icons/verarc/slowed.png": {"ice_10", "ice_m7"},
        }
        icon_users = {}
        for it in school_it:
            icon = it.get("icon", "")
            check(icon.startswith("res://"), f"{school} item {it['id']} icon path prefix")
            fs_path = os.path.join(ROOT, icon.replace("res://", "").replace("/", os.sep))
            check(os.path.isfile(fs_path), f"{school} item {it['id']} icon file exists: {icon}")
            icon_users.setdefault(icon, []).append(it["id"])
        for icon, users in icon_users.items():
            if len(users) <= 1:
                continue
            if icon in LEGACY_ICON_SHARES and set(users) == LEGACY_ICON_SHARES[icon]:
                continue  # 存量共用对，白名单放行
            check(False, f"{school} icon 共用（新增重复）: {icon} <- {users}")
        # 机制型 tags：mechanic: 前缀且与脚本门控对应
        for it in school_it:
            for tag in it.get("tags", []):
                if not str(tag).startswith("mechanic:"):
                    continue
                gate = str(tag).split(":", 1)[1]
                check(gate in gates,
                      f"{school} item {it['id']} 机制 tag {tag} 不在脚本门控 {school}_m1..m10")

    # --- monotonicity: increasing curves non-decrease; multiplicative(base<1) non-increase ---
    for i in items:
        t = i["curve"]["type"]
        increasing = not (t == "multiplicative" and i["curve"]["base"] < 1.0)
        prev = -1e9 if increasing else 1e9
        for n in range(0, 21):
            v = curve_value(i["curve"], n)
            if increasing:
                check(v + 1e-9 >= prev, f"item {i['id']} monotonic at stack {n}")
            else:
                check(v - 1e-9 <= prev, f"item {i['id']} monotonic(dec) at stack {n}")
            prev = v

    # --- hand-checked curve cases (from docs/design/数值设计.md) ---
    def val(iid, n):
        it = next(x for x in items if x["id"] == iid)
        return curve_value(it["curve"], n)

    check(abs(val("attack_speed_potion", 1) - 0.15 * 1.15) < 1e-9, "attack_speed n=1")
    check(abs(val("attack_speed_potion", 3) - 0.15 * 1.45) < 1e-9, "attack_speed n=3")
    check(abs(val("thorn_armor", 1) - (1 - 0.9 ** 2)) < 1e-9, "thorn n=1: 19%")
    check(abs(val("thorn_armor", 4) - (1 - 0.9 ** 5)) < 1e-9, "thorn n=4")
    check(abs(val("lucky_clover", 2) - (1 - 0.96 ** 3)) < 1e-9, "clover n=2")
    check(val("bounce_mirror", 2) == 0 and val("bounce_mirror", 3) == 1, "bounce threshold")
    check(abs(val("wand_charge", 3) - 0.9 ** 3) < 1e-9, "wand_charge multiplicative")
    check(abs(val("wand_charge", 7) - 0.5) < 1e-9, "wand_charge cap floor 0.5")
    check(abs(val("wand_charge", 10) - 0.5) < 1e-9, "wand_charge stays at floor")
    # --- 吸血牙（调低后：1% + 0.25%/层，曲线封顶 3%） ---
    check(abs(val("vampire_fang", 1) - 0.0125) < 1e-9, "vampire_fang n=1 = 1.25%")
    check(abs(val("vampire_fang", 8) - 0.03) < 1e-9, "vampire_fang n=8 cap 3%")
    check(abs(val("vampire_fang", 20) - 0.03) < 1e-9, "vampire_fang n=20 stays at 3%")
    vamp = next(i for i in items if i["id"] == "vampire_fang")
    check(vamp["curve"].get("cap", 0) <= 0.03, "vampire_fang curve cap <= 3%")

    # --- drops ---
    total = sum(d["prob"] for d in drops["kill_drops"])
    check(abs(total - 1.0) < 1e-9, f"kill_drops sum to 1 (got {total})")
    check(drops["pity_threshold"] > 0, "pity threshold positive")
    for d in drops["kill_drops"]:
        check(0 <= d["prob"] <= 1, f"drop prob in [0,1]: {d}")
        check(d["type"] != "heal", "普通小怪不再掉落回血（回血只来自精英/Boss 血包）")
    check(abs(drops["elite_drops"]["heal_pct"] - 0.10) < 1e-9, "elite heal pack = 10%")
    check(abs(drops["boss_drops"]["heal_pct"] - 0.30) < 1e-9, "boss heal pack = 30%")
    # 全局吸血上限 4%（GameState 钳制）；吸血牙单件封顶 3% 必须低于全局上限
    check(vamp["curve"].get("cap", 0) < 0.04, "vampire_fang cap < 全局吸血上限 4%")
    rw = drops["item_rarity_weights"]
    check(abs(sum(rw.values()) - 1.0) < 1e-9, "rarity weights sum to 1")

    # --- wands（法杖商店） ---
    wand_ids = [w["id"] for w in wands["wands"]]
    check(len(wand_ids) == len(set(wand_ids)), "wand ids unique")
    valid_shapes = ("none", "burst", "rapid", "orbit", "scatter", "frost", "homing", "summon",
                    "pierce", "poison", "light", "chain", "split", "bounce")
    for w in wands["wands"]:
        check(w["price"] > 0, f"wand {w['id']} price > 0")
        check(w["shape"] in valid_shapes, f"wand {w['id']} shape valid")
        check(w["icon"].startswith("res://"), f"wand {w['id']} icon path")
        check(w.get("damage_mult", 0) > 0 and w.get("cd_mult", 0) > 0, f"wand {w['id']} mults > 0")

    # --- 防御流道具（F7） ---
    stone = next(i for i in items if i["id"] == "stone_armor")
    thorn_r = next(i for i in items if i["id"] == "thorn_reflect")
    blood = next(i for i in items if i["id"] == "blood_thorn")
    check(abs(stone["curve"]["cap"] - 0.35) < 1e-9, "stone_armor cap 35%")
    check(abs(thorn_r["curve"]["base"] - 0.30) < 1e-9, "thorn_reflect base 30%")
    check(abs(blood["curve"]["base"] - 0.02) < 1e-9, "blood_thorn 2%")

    # --- 新法术核心（15）与外壳（10） ---
    all_cores = [c["id"] for c in spells["cores"]]
    all_shells = [s["id"] for s in spells["shells"]]
    check(len(all_cores) == 15, f"15 cores (got {len(all_cores)})")
    check(len(all_shells) == 10, f"10 shells (got {len(all_shells)})")
    for c in spells["cores"]:
        check(c["icon"].startswith("res://"), f"core {c['id']} icon path")
        check(c["element"] in ("fire", "ice", "lightning", "poison", "summon", "blade",
                               "water", "nature", "light", "void", "buff"), f"core {c['id']} element")

    # --- Boss 技能参数（F5） ---
    for b in enemies["bosses"]:
        sk = b.get("skills", [])
        check(len(sk) >= 2, f"boss {b['id']} has >=2 skills")
        for s in sk:
            check(s.get("id", "") and s.get("type", ""), f"boss {b['id']} skill fields")
            check(s.get("cooldown", 0) > 0, f"boss {b['id']} skill cooldown > 0")

    # --- enemy scaling hand checks ---
    b = balance["enemy_scaling"]
    slime = next(e for e in enemies["enemies"] if e["id"] == "slime")
    hp_l1_l1 = slime["hp"] * math.pow(b["level_hp"], 0) * math.pow(b["loop_hp"], 0)
    hp_l5_l2 = slime["hp"] * math.pow(b["level_hp"], 4) * math.pow(b["loop_hp"], 1)
    check(abs(hp_l1_l1 - 45) < 1e-9, "slime hp l1 loop1 = 45")
    check(abs(hp_l5_l2 - 45 * (1.18 ** 4) * b["loop_hp"]) < 1e-6, "slime hp l5 loop2")
    atk_l1 = slime["attack"] * (1 + 0.12 * 0)
    atk_l5 = slime["attack"] * (1 + 0.12 * 4)
    check(abs(atk_l5 / atk_l1 - (1 + 0.48)) < 1e-9, "atk scaling level factor")

    # --- xp curve (GameState.xp_to_next 公式一致性) ---
    xp = balance["xp"]
    check(xp["base"] + xp["per_level"] * 0 == 40, "xp L1 = 40")
    check(xp["base"] + xp["per_level"] * 3 + xp["quad"] * 9 == 175, "xp L4 = 175")
    check(xp["base"] + xp["per_level"] * 4 + xp["quad"] * 16 == 240, "xp L5 = 240")
    # 增幅逐级增加 → 曲线平滑且单调
    prev_gain = 0
    for l in range(1, 15):
        need = xp["base"] + xp["per_level"] * (l - 1) + xp["quad"] * (l - 1) ** 2
        check(need > prev_gain, f"xp need monotonic at L{l}")
        prev_gain = need

    # --- crit ---
    crit = balance["crit"]
    check(abs(crit["base_chance"] + crit["per_stack"] * 10 - 0.23) < 1e-9, "crit 10 stacks = 23%")
    check(crit["cap"] <= 1.0, "crit cap <= 1")

    # --- cross references ---
    core_ids = [c["id"] for c in spells["cores"]]
    shell_ids = [s["id"] for s in spells["shells"]]
    check(len(core_ids) == len(set(core_ids)) and len(shell_ids) == len(set(shell_ids)), "spell ids unique")
    enemy_ids = [e["id"] for e in enemies["enemies"]]
    boss_ids = [b2["id"] for b2 in enemies["bosses"]]
    all_e = set(enemy_ids) | set(boss_ids)
    for lv in levels["levels"]:
        check(lv["boss"] in boss_ids, f"level {lv['id']} boss exists")
        for w in lv["waves"]:
            for eid in w["spawn"]:
                check(eid in enemy_ids, f"level {lv['id']} wave spawn {eid} exists")
    check(levels["final_boss"] in boss_ids, "final boss exists")
    for a in enemies["affixes"].values():
        check(a["hp_mult"] > 1 and a["atk_mult"] > 1, f"affix {a['name']} multipliers")

    # --- no negative values anywhere in tables ---
    def scan(obj, path=""):
        if isinstance(obj, dict):
            for k, v in obj.items():
                scan(v, path + "." + k)
        elif isinstance(obj, list):
            for i, v in enumerate(obj):
                scan(v, f"{path}[{i}]")
        elif isinstance(obj, (int, float)):
            # tradeoff 曲线的负惩罚字段（如 crit_penalty）是设计内合法的
            if obj < 0 and not path.endswith(".curve.crit_penalty"):
                check(False, f"negative value at {path}: {obj}")

    scan(balance)
    scan(items)
    scan(spells)
    scan(enemies)
    scan(levels)
    scan(drops)

    if FAILS:
        print(f"FAILED: {len(FAILS)} checks")
        for m in FAILS[:30]:
            print(" -", m)
        return 1
    print(f"OK: all tests passed ({len(items)} items, {len(core_ids)} cores, {len(shell_ids)} shells, "
          f"{len(enemy_ids)} enemies, {len(boss_ids)} bosses, {len(levels['levels'])} levels)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
