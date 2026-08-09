"""Numeric consistency tests for data tables (run without Godot).

Usage:
    python tools/tests/test_curves.py
Exit code 0 = all pass.
"""

import json
import math
import os
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


def curve_value(c, n):
    t = c["type"]
    base = c.get("base", 0.0)
    if t == "linear":
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

    # --- basic schema integrity ---
    item_ids = [i["id"] for i in items]
    check(len(item_ids) == len(set(item_ids)), "item ids unique")
    for i in items:
        check(i["curve"]["type"] in ("linear", "exp_proc", "threshold", "multiplicative"),
              f"item {i['id']} curve type")
        for f in ("base",):
            check(f in i["curve"], f"item {i['id']} curve has {f}")
        if i["curve"]["type"] == "linear":
            check("k" in i["curve"], f"item {i['id']} linear needs k")
        if i["curve"]["type"] == "exp_proc":
            p = i["curve"].get("p", 0)
            check(0 < p <= 1, f"item {i['id']} exp_proc p in (0,1]")
        if i["curve"]["type"] == "threshold":
            check(i["curve"].get("threshold", 0) >= 1, f"item {i['id']} threshold >= 1")
        if i["curve"]["type"] == "multiplicative":
            check(0 < i["curve"]["base"] < 1, f"item {i['id']} multiplicative base in (0,1)")
        check(0 <= i["curve"].get("base", 0), f"item {i['id']} base >= 0")
        check(i["rarity"] in ("common", "rare", "legendary"), f"item {i['id']} rarity")
        check(i["type"] in ("item", "trinket", "memory"), f"item {i['id']} type")

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

    # --- drops ---
    total = sum(d["prob"] for d in drops["kill_drops"])
    check(abs(total - 1.0) < 1e-9, f"kill_drops sum to 1 (got {total})")
    check(drops["pity_threshold"] > 0, "pity threshold positive")
    for d in drops["kill_drops"]:
        check(0 <= d["prob"] <= 1, f"drop prob in [0,1]: {d}")
    rw = drops["item_rarity_weights"]
    check(abs(sum(rw.values()) - 1.0) < 1e-9, "rarity weights sum to 1")

    # --- enemy scaling hand checks ---
    b = balance["enemy_scaling"]
    slime = next(e for e in enemies["enemies"] if e["id"] == "slime")
    hp_l1_l1 = slime["hp"] * math.pow(b["level_hp"], 0) * math.pow(b["loop_hp"], 0)
    hp_l5_l2 = slime["hp"] * math.pow(b["level_hp"], 4) * math.pow(b["loop_hp"], 1)
    check(abs(hp_l1_l1 - 45) < 1e-9, "slime hp l1 loop1 = 45")
    check(abs(hp_l5_l2 - 45 * (1.18 ** 4) * 1.30) < 1e-6, "slime hp l5 loop2")
    atk_l1 = slime["attack"] * (1 + 0.12 * 0)
    atk_l5 = slime["attack"] * (1 + 0.12 * 4)
    check(abs(atk_l5 / atk_l1 - (1 + 0.48)) < 1e-9, "atk scaling level factor")

    # --- xp curve (GameState.xp_to_next 公式一致性) ---
    xp = balance["xp"]
    check(xp["base"] + xp["per_level"] * 0 == 50, "xp L1 = 50")
    check(xp["base"] + xp["per_level"] * 3 + xp["quad"] * 9 == 185, "xp L4 = 185")
    check(xp["base"] + xp["per_level"] * 4 + xp["quad"] * 16 == 250, "xp L5 = 250")
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
            if obj < 0:
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
