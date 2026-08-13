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
        check(i["rarity"] in ("common", "uncommon", "rare", "epic", "legendary"),
              f"item {i['id']} rarity")
        check(i["type"] in ("item", "trinket", "memory"), f"item {i['id']} type")

    # --- 流派构筑补全（school_fill_ice_summon）---
    # 门控 id 与 scripts/synergies/ice_synergy.gd / summon_synergy.gd 的
    # _stacks("ice_mN") / _stacks("summon_mN") 消费点一一对应（只读契约）
    ICE_GATES = {f"ice_m{i}" for i in range(1, 11)}
    SUMMON_GATES = {f"summon_m{i}" for i in range(1, 11)}
    # 机制补全批次（mech_fill_batch）：圣光流 10+10 门控与 holy_synergy.gd 一致
    HOLY_GATES = {f"holy_m{i}" for i in range(1, 11)}
    def school_items(school):
        return [i for i in items
                if str(i["id"]).startswith(school + "_") or school in i.get("tags", [])]

    for school, gates in (("ice", ICE_GATES), ("summon", SUMMON_GATES), ("holy", HOLY_GATES)):
        school_it = school_items(school)
        check(len(school_it) >= 20,
              f"{school} 流派道具数 >= 20（现 {len(school_it)}）")
        rarities = Counter(i["rarity"] for i in school_it)
        # 五档（2026-08-13）：白+绿 >= 8、蓝+金 >= 8、红 >= 4
        check(rarities.get("common", 0) + rarities.get("uncommon", 0) >= 8,
              f"{school} 白+绿 >= 8（现 {rarities.get('common', 0)}/{rarities.get('uncommon', 0)}）")
        check(rarities.get("rare", 0) + rarities.get("epic", 0) >= 8,
              f"{school} 蓝+金 >= 8（现 {rarities.get('rare', 0)}/{rarities.get('epic', 0)}）")
        check(rarities.get("legendary", 0) >= 4,
              f"{school} 红 >= 4（现 {rarities.get('legendary', 0)}）")
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

    # --- 机制补全批次（mech_fill_batch）：G7 全流派传说 >= 4 ---
    # wind / melee（blade）原各 3 传说，本轮补 melee_giant_cleaver / wind_typhoon_eye
    for school in ("wind", "melee"):
        rarities = Counter(i["rarity"] for i in school_items(school))
        check(rarities.get("legendary", 0) >= 4,
              f"{school} 传说 >= 4（现 {rarities.get('legendary', 0)}）")

    # --- 机制补全批次：G4 毒系门控道具齐备（poison_m1..m10 带 mechanic tag）---
    POISON_GATES = {f"poison_m{i}" for i in range(1, 11)}
    for gate in sorted(POISON_GATES):
        it = next((x for x in items if x["id"] == gate), None)
        check(it is not None, f"poison 门控道具 {gate} 存在")
        if it is not None:
            check(f"mechanic:{gate}" in it.get("tags", []), f"{gate} mechanic tag")

    # --- 机制补全批次：G5 重复道具去重（defense_amulet 曲线与 defense_iron_wall 区分）---
    amulet_def = next(x for x in items if x["id"] == "defense_amulet")
    iron_wall_def = next(x for x in items if x["id"] == "defense_iron_wall")
    check(amulet_def["curve"] != iron_wall_def["curve"],
          "defense_amulet 曲线已与 defense_iron_wall 去重（不再数值相同）")

    # --- 机制补全批次：防9 石肤 / 咒7 恐惧咒 语义对齐（实现为玩家减伤）---
    stone_skin = next(x for x in items if x["id"] == "defense_stone_skin")
    fear_word = next(x for x in items if x["id"] == "curse_fear_word")
    check("受到伤害" in stone_skin["description"], "defense_stone_skin 描述对齐减伤实现")
    check("受到" in fear_word["description"], "curse_fear_word 描述对齐玩家减伤实现")

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

    # --- drops（2026-08-10：kill_drops prob 改为独立命中概率，不再权重归一求和为 1）---
    for d in drops["kill_drops"]:
        check(0 <= d["prob"] <= 1, f"drop prob in [0,1]: {d}")
    gold_prob = next((float(d["prob"]) for d in drops["kill_drops"] if d.get("type") == "gold"), 0.0)
    check(abs(gold_prob - 0.65) < 1e-9, f"kill_drops gold prob = 0.65 (got {gold_prob})")
    check(drops["pity_threshold"] > 0, "pity threshold positive")
    for d in drops["kill_drops"]:
        check(0 <= d["prob"] <= 1, f"drop prob in [0,1]: {d}")
        check(d["type"] != "heal", "普通小怪不再掉落回血（回血只来自精英/Boss 血包）")
    check(abs(drops["elite_drops"]["heal_pct"] - 0.10) < 1e-9, "elite heal pack = 10%")
    check(abs(drops["boss_drops"]["heal_pct"] - 0.30) < 1e-9, "boss heal pack = 30%")
    check("gold_mult" not in drops["boss_drops"], "boss_drops.gold_mult 已移除（Boss 金币按 enemies.json gold 发放）")
    # 全局吸血上限 3%（balance.json lifesteal.cap，GameState 钳制）；吸血牙单件封顶 3%
    check(abs(balance.get("lifesteal", {}).get("cap", 0.0) - 0.03) < 1e-9, "全局吸血上限 = 3%")
    check(vamp["curve"].get("cap", 0) <= 0.03, "vampire_fang cap <= 全局吸血上限 3%")
    rw = drops["item_rarity_weights"]
    check(abs(sum(rw.values()) - 1.0) < 1e-9, "rarity weights sum to 1")

    # --- 金币数值（2026-08-13 对齐 enemies.json 实际区间）：普通 1-4、Boss 30-240 ---
    for e in enemies["enemies"]:
        check(1 <= e["gold"] <= 4, f"enemy {e['id']} gold in 1..4 (got {e['gold']})")
    for b2 in enemies["bosses"]:
        check(30 <= b2["gold"] <= 240, f"boss {b2['id']} gold in 30..240 (got {b2['gold']})")

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

    # --- 防御流道具（F7，批次A去重：旧 id → defense_ 新 id，2026-08-13） ---
    stone = next(i for i in items if i["id"] == "defense_bedrock")
    amulet_def = next(i for i in items if i["id"] == "defense_amulet")
    thorn_r = next(i for i in items if i["id"] == "defense_thorn_refit")
    blood = next(i for i in items if i["id"] == "defense_blood_thorn")
    check(abs(stone["curve"]["cap"] - 0.35) < 1e-9, "defense_bedrock cap 35%")
    check(abs(amulet_def["curve"]["cap"] - 0.15) < 1e-9, "defense_amulet cap 15%")
    check(stone["curve"]["cap"] + amulet_def["curve"]["cap"] <= 0.50,
          "防御减伤合计上限 <= 50%（game_root 封顶，2026-08-10）")
    check(abs(thorn_r["curve"]["base"] - 0.30) < 1e-9, "defense_thorn_refit base 30%")
    check(abs(blood["curve"]["base"] - 0.02) < 1e-9, "defense_blood_thorn 2%")
    for old_id in ("stone_armor", "thorn_reflect", "blood_thorn", "summon_book"):
        check(all(i["id"] != old_id for i in items), f"批次A去重：旧 id {old_id} 已从 items.json 移除")

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

    # --- 玩家初始 HP 80（balance.json player.hp，2026-08-13 对齐）---
    check(balance["player"]["hp"] == 80, f"player hp = 80 (got {balance['player']['hp']})")

    # --- enemy scaling hand checks（2026-08-13：level_hp 1.22 / level_atk 0.12，取自 balance.json）---
    b = balance["enemy_scaling"]
    slime = next(e for e in enemies["enemies"] if e["id"] == "slime")
    hp_l1_l1 = slime["hp"] * math.pow(b["level_hp"], 0) * math.pow(b["loop_hp"], 0)
    hp_l5_l2 = slime["hp"] * math.pow(b["level_hp"], 4) * math.pow(b["loop_hp"], 1)
    check(abs(hp_l1_l1 - 45) < 1e-9, "slime hp l1 loop1 = 45")
    check(abs(hp_l5_l2 - 45 * (1.22 ** 4) * b["loop_hp"]) < 1e-6, "slime hp l5 loop2")
    atk_l1 = slime["attack"] * (1 + 0.12 * 0)
    atk_l5 = slime["attack"] * (1 + 0.12 * 4)
    check(abs(atk_l5 / atk_l1 - (1 + 0.48)) < 1e-9, "atk scaling level factor (1+4*0.12)")
    check(abs(b["level_hp"] - 1.22) < 1e-9, "balance level_hp = 1.22 (GameState.level_factor)")
    check(abs(b["level_atk"] - 0.12) < 1e-9, "balance level_atk = 0.12 (GameState.enemy_atk 从 balance 读取)")
    # --- loop 系数与 GameState 硬编码一致（2026-08-10 表值对齐 1.34/1.24）---
    check(abs(b["loop_hp"] - 1.34) < 1e-9, "balance loop_hp = 1.34 (GameState.loop_factor_hp)")
    check(abs(b["loop_dmg"] - 1.24) < 1e-9, "balance loop_dmg = 1.24 (GameState.loop_factor_dmg)")


    # --- ?????2026-08-10?minion_boost????/??/?????????? ---
    # ??????touch???? atk_cd????????enemy.gd _ai_melee ????
    # ???projectile???? fire_interval / bullet_speed?enemy.gd _ai_ranged ????
    for e in enemies["enemies"]:
        if e.get("touch", False):
            check("atk_cd" in e, f"enemy {e['id']} melee has atk_cd")
            check(0.5 < e.get("atk_cd", 0) <= 1.1, f"enemy {e['id']} atk_cd in (0.5, 1.1]")
        if e.get("projectile", False):
            check(2.5 < e.get("fire_interval", 0) <= 5.0, f"enemy {e['id']} fire_interval in (2.5, 5.0]")
            check(120 <= e.get("bullet_speed", 0) <= 400, f"enemy {e['id']} bullet_speed in [120, 400]")
    # ????????? -> ???
    def ec(eid):
        return next(x for x in enemies["enemies"] if x["id"] == eid)
    check(ec("slime")["attack"] == 9 and abs(ec("slime")["atk_cd"] - 0.85) < 1e-9, "slime 7/1.0 -> 9/0.85")
    check(ec("bat")["attack"] == 6 and abs(ec("bat")["atk_cd"] - 0.8) < 1e-9, "bat 5/1.0 -> 6/0.8")
    check(ec("goblin")["attack"] == 13 and abs(ec("goblin")["atk_cd"] - 0.85) < 1e-9, "goblin 10/1.0 -> 13/0.85")
    check(ec("wizard")["attack"] == 18 and abs(ec("wizard")["bullet_speed"] - 165) < 1e-9, "wizard 14/130 -> 18/165")
    check(ec("goblin_archer")["bullet_speed"] == 170 and ec("goblin_archer")["sniper_speed"] == 340,
          "archer bullet 150 -> 170 / sniper 300 -> 340")
    check(ec("charger")["charge_cd"] == 2.6, "charger charge_cd 3.2 -> 2.6 (????+)")
    check(ec("bat")["dive_cd"] == 2.4, "bat dive_cd 3.0 -> 2.4 (????+)")
    # ???? DPS ?? 30~60%????????????=atk/atk_cd???=atk/fire_interval?
    OLD_STATS = {
        "slime": (7, 1.0), "bat": (5, 1.0), "ghost": (8, 1.0), "goblin": (10, 1.0),
        "goblin_archer": (7, 4.5), "skeleton": (12, 1.0), "imp": (8, 4.5), "wizard": (14, 3.6),
        "bomber": (10, 1.0), "charger": (14, 1.0), "healer": (6, 1.0),
        "crystal_sentry": (9, 4.0), "spider": (7, 1.0), "mimic_block": (13, 1.0), "specter": (10, 4.2),
    }
    for e in enemies["enemies"]:
        eid = e["id"]
        if eid not in OLD_STATS:
            continue
        o_atk, o_iv = OLD_STATS[eid]
        o_dps = o_atk / o_iv
        n_dps = e["attack"] / (e.get("atk_cd", e.get("fire_interval", 1.0)))
        ratio = n_dps / o_dps
        check(1.30 <= ratio <= 1.60,
              f"enemy {eid} ?? DPS ?? {ratio:.2f}x ?? [1.30, 1.60]")

    # --- ???? +20% ???2026-08-10 minion_boost?---
    lv1 = next(x for x in levels["levels"] if x["id"] == "level_1")
    wave_totals = [sum(w["spawn"].values()) for w in lv1["waves"]]
    check(wave_totals == [4, 6, 12], f"level_1 ???? 3/5/10 -> 4/6/12 (got {wave_totals})")
    for lv in levels["levels"]:
        old_total = {"level_1": 18, "level_2": 29, "level_3": 33, "level_4": 31, "level_5": 46}[lv["id"]]
        new_total = sum(sum(w["spawn"].values()) for w in lv["waves"])
        check(new_total >= old_total * 1.12,
              f"level {lv['id']} ???? >= ??x1.12 ({old_total} -> {new_total})")
    # level_num ????? spawner??? +26%??? x1.5?
    check(abs(b["level_num"] - 0.24) < 1e-9, "balance level_num = 0.24 (spawner 数量系数)")

    # --- xp curve (GameState.xp_to_next 公式一致性) ---
    xp = balance["xp"]
    # 2026-08-13: 统一公式 38 + 30(L-1) + 5(L-1)^2
    # （balance.xp base=38 / per_level=30 / quad=5；已移除 L1-3 硬编码加速 30/60/100）
    check(xp["base"] + xp["per_level"] * 0 + xp["quad"] * 0 == 38, "xp L1 = 38")
    check(xp["base"] + xp["per_level"] * 1 + xp["quad"] * 1 == 73, "xp L2 = 73")
    check(xp["base"] + xp["per_level"] * 2 + xp["quad"] * 4 == 118, "xp L3 = 118")
    check(xp["base"] + xp["per_level"] * 3 + xp["quad"] * 9 == 173, "xp L4 = 173")
    check(xp["base"] + xp["per_level"] * 4 + xp["quad"] * 16 == 238, "xp L5 = 238")
    check(xp["base"] + xp["per_level"] * 5 + xp["quad"] * 25 == 313, "xp L6 = 313")
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
