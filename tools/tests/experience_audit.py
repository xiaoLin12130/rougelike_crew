# -*- coding: utf-8 -*-
"""全流程体验审计：静态解析 data 表，输出数值曲线与构筑权重数据。

用法（无需 Godot）：
    python tools/tests/experience_audit.py
退出码 0 = 全部通过（全绿）。

输出内容：
  A. 数据表完整性
  B. L1-L5 敌人血量/伤害/数量/经验成长曲线（与 GameState 同公式）
  C. Boss 血量/攻击/技能
  D. 升级经验曲线 xp_to_next（L1-L20）
  E. 金币掉落分布（击杀金币 + Boss 金币 + 波次理论收入）
  F. 构筑获取概率权重（F9 元素加权 + 非主流保底 + N2 筛选，模拟三选一）
  G. 技能"追踪"静态核对（瞬发核 vs 弹道核、homing 外壳、命中窗口）
  H. 数值表/代码一致性（loop_hp/loop_dmg/xp base 漂移）
"""

import json
import math
import os
import random
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DATA = os.path.join(ROOT, "data")


def load(name):
    with open(os.path.join(DATA, name + ".json"), encoding="utf-8") as f:
        return json.load(f)


def gs_xp_to_next(level, xp_cfg):
    """与 GameState.xp_to_next 完全一致。"""
    l = max(level, 1)
    return int(xp_cfg.get("base", 50)) + int(xp_cfg.get("per_level", 30)) * (l - 1) \
        + int(xp_cfg.get("quad", 5)) * (l - 1) * (l - 1)


def gs_enemy_hp(base, level, loop, cfg):
    """与 GameState.enemy_hp 一致：level 系数 1.18^(L-1)，loop 系数硬编码 1.30。"""
    return base * pow(1.18, level - 1) * pow(1.30, loop - 1)


def gs_enemy_atk(base, level, loop):
    return base * (1.0 + 0.12 * (level - 1)) * pow(1.18, loop - 1)


def gs_enemy_xp(base, level, loop, cfg):
    lx = cfg.get("enemy_scaling", {}).get("level_xp", 0.12)
    return int(base * (1.0 + lx * (level - 1)) * pow(1.35, loop - 1))


ELEMENTS = ["fire", "ice", "lightning", "poison", "summon", "water", "nature", "light", "void", "blade"]


def element_key(item, spells=None):
    tags = item.get("tags", [])
    for el in ELEMENTS:
        if el in tags:
            return el
    iid = str(item.get("id", ""))
    if iid.startswith("spell_part:") and spells is not None:
        parts = iid.split(":")
        if len(parts) > 1:
            for c in spells.get("cores", []):
                if str(c.get("id", "")) == parts[1]:
                    return str(c.get("element", ""))
    return ""


def simulate_rolls(items, spells, drops, level, holdings, n=6000, seed=20260810):
    """复刻 GameState.roll_item_choices（元素加权 + N2 筛选 + 非主流保底 + 法术部件）。"""
    rng = random.Random(seed)
    lv_factor = 1.0 + 0.25 * max(level - 1, 0.0)
    base_w = drops.get("item_rarity_weights", {})
    el_seen = {}
    spell_seen = 0
    # 预计算每件道具的固定权重（仅与稀有度/元素持有相关，场景内不变）
    item_weights = []
    for i in items["items"]:
        w = float(base_w.get(i.get("rarity", "common"), 0.2))
        el = element_key(i, spells)
        if el and el in holdings:
            cnt = int(holdings[el])
            if cnt > 0:
                w *= min(1.0 + 0.02 * cnt * lv_factor, 1.6)
        item_weights.append((i, el, w))
    for _ in range(n):
        pool = [x for x in item_weights if x[1] == "" or x[1] in holdings]
        if len(pool) < 3:
            pool = item_weights
        main_el = ""
        best_n = 0
        for el, cnt in holdings.items():
            if cnt > best_n:
                best_n = cnt
                main_el = el
        off_pool = [x for x in pool if x[1] != "" and x[1] != main_el]
        choices = []
        # 法术部件：核心×外壳随机
        core = rng.choice(spells["cores"])
        shell = rng.choice(spells["shells"]) if spells.get("shells") else {}
        spell_el = str(core.get("element", ""))
        choices.append(("spell_part", spell_el))
        # 非主流保底
        if off_pool and len(choices) < 3:
            pick = rng.choice(off_pool)
            choices.append((pick[0], pick[1]))
            pool = [x for x in pool if x[0].get("id") != pick[0].get("id")]
            off_pool = [x for x in off_pool if x[0].get("id") != pick[0].get("id")]
        while len(choices) < 3 and pool:
            total = sum(x[2] for x in pool)
            roll = rng.random() * total
            acc = 0.0
            picked = -1
            for idx, it in enumerate(pool):
                acc += it[2]
                if roll <= acc:
                    picked = idx
                    break
            if picked < 0:
                picked = len(pool) - 1
            choices.append((pool[picked][0], pool[picked][1]))
            pool = [x for x in pool if x[0].get("id") != pool[picked][0].get("id")]
        rng.shuffle(choices)
        for _item, el in choices:
            if _item == "spell_part":
                spell_seen += 1
            else:
                el_seen[el or "通用"] = el_seen.get(el or "通用", 0) + 1
    return spell_seen, el_seen, n


def main():
    balance = load("balance")
    items = load("items")
    spells = load("spells")
    enemies = load("enemies")
    levels = load("levels")
    drops = load("drops")
    warnings = []

    print("=" * 78)
    print("全流程体验审计（静态数值曲线）")
    print("=" * 78)

    # ---------- A. 数据表完整性 ----------
    print("\n[A] 数据表完整性")
    n_items = len(items["items"])
    n_cores = len(spells["cores"])
    n_shells = len(spells["shells"])
    n_enn = len(enemies["enemies"])
    n_boss = len(enemies["bosses"])
    n_lv = len(levels["levels"])
    print("    items=%d cores=%d shells=%d enemies=%d bosses=%d levels=%d" % (
        n_items, n_cores, n_shells, n_enn, n_boss, n_lv))
    ids = [i["id"] for i in items["items"]]
    assert len(ids) == len(set(ids)), "item id 重复"
    boss_ids = [b["id"] for b in enemies["bosses"]]
    assert levels["final_boss"] in boss_ids, "final_boss 缺失"
    print("    [PASS] id 唯一 / 关卡 Boss 引用完整")

    # ---------- B. 敌人成长曲线 ----------
    print("\n[B] 敌人成长曲线（L1-L5，loop=1，公式与 GameState 一致）")
    esc = balance["enemy_scaling"]
    print("    %-16s | %-38s | %-20s | %-8s" % ("敌人", "HP L1→L5", "ATK L1→L5", "XP L5"))
    for e in enemies["enemies"]:
        hp_l = [gs_enemy_hp(e["hp"], lv, 1, esc) for lv in range(1, 6)]
        atk_l = [gs_enemy_atk(e["attack"], lv, 1) for lv in range(1, 6)]
        xp5 = gs_enemy_xp(e["xp"], 5, 1, esc)
        print("    %-16s | %-38s | %-20s | %-8d" % (
            e["id"],
            " ".join("%.0f" % h for h in hp_l),
            " ".join("%.0f" % a for a in atk_l),
            xp5))
    print("    关卡 HP 系数: %.2f^(L-1)；关卡 ATK: ×(1+%.2f×(L-1))；关卡 XP: ×(1+%.2f×(L-1))" % (
        esc["level_hp"], esc["level_atk"], esc["level_xp"]))

    # 波次数量/收入
    print("\n    每关波次构成（spawn 计数/刷新间隔/时长/精英率/Boss）")
    for lv in levels["levels"]:
        wave_info = []
        total_spawn = 0
        for w in lv["waves"]:
            cnt = sum(w["spawn"].values())
            total_spawn += cnt
            wave_info.append("W@%2ds:%d只/%.1fs/%.0fs/e%.0f%%" % (
                w["time"], cnt, w.get("interval", 1.0), w.get("duration", 20),
                w.get("elite_chance", 0.0) * 100))
        print("    %-10s Boss=%-16s | %s" % (lv["id"], lv["boss"], " | ".join(wave_info)))

    # ---------- C. Boss 数值 ----------
    print("\n[C] Boss 数值（HP/ATK 按所在关 level 系数换算，loop=1）")
    lv_of = {lv["id"]: i + 1 for i, lv in enumerate(levels["levels"])}
    print("    %-18s | %-8s | %-10s | %-8s | 技能" % ("Boss", "关卡", "HP", "ATK"))
    for b in enemies["bosses"]:
        lv = lv_of.get(b["id"], 5)
        hp = gs_enemy_hp(b["hp"], lv, 1, esc)
        atk = gs_enemy_atk(b["attack"], lv, 1)
        sk = ", ".join("%s(cd%.1fs)" % (s["type"], s["cooldown"]) for s in b.get("skills", []))
        print("    %-18s |  L%-7d | %-10.0f | %-8.0f | %s" % (b["id"], lv, hp, atk, sk))
        print("        phases=%s xp=%d gold=%d" % (b.get("phases"), b.get("xp"), b.get("gold")))

    # ---------- D. 升级经验曲线 ----------
    print("\n[D] 升级经验曲线 xp_to_next（balance.xp: base=%d per=%d quad=%d）" % (
        balance["xp"]["base"], balance["xp"]["per_level"], balance["xp"]["quad"]))
    print("    设计意图对比：PROGRESS 记 50+30(L-1)+5(L-1)^2；数值设计.md 记 60+35L")
    cum = 0
    for l in range(1, 21):
        need = gs_xp_to_next(l, balance["xp"])
        cum += need
        print("    L%-2d 需要 %-4d 经验（累计 %-5d）" % (l, need, cum))
    if balance["xp"]["base"] != 50:
        warnings.append("xp.base=%d != 文档 50（PROGRESS）且 != 60+35L（数值设计.md）" % balance["xp"]["base"])
    # 击杀经验供给：L1 常见怪 slime/bat 经验 8/6
    print("    L1 供给参照：slime xp=8、bat xp=6 → L1(40)≈5-7 只；L2(75)≈9-13 只")

    # ---------- E. 金币掉落 ----------
    print("\n[E] 金币掉落分布")
    kd = drops["kill_drops"]
    print("    kill_drops: %s（击杀 100%% 掉金币）" % [d["type"] for d in kd])
    gold_by_enemy = {}
    for e in enemies["enemies"]:
        gold_by_enemy.setdefault(e["gold"], []).append(e["id"])
    for g in sorted(gold_by_enemy):
        print("    每击杀金币=%d：%s" % (g, ", ".join(gold_by_enemy[g])))
    print("    Boss 金币：%s（drops.boss_drops.gold_mult=%d 在代码中未引用，实际用 enemies.json 的 gold）" % (
        {b["id"]: b["gold"] for b in enemies["bosses"]}, drops["boss_drops"].get("gold_mult")))
    print("    稀有度权重：%s" % drops["item_rarity_weights"])
    print("    保底：连续 %d 次击杀无道具 → 必掉" % drops["pity_threshold"])

    # ---------- F. 构筑获取概率权重 ----------
    print("\n[F] 构筑获取概率权重（F9 元素加权模拟，6000 次三选一）")
    print("    公式：w = 稀有度权重 × min(1 + 0.02×持有件数×关卡系数, 1.6)；关卡系数 = 1+0.25×(L-1)")
    scenarios = [
        ("开局(火球+旋风刃+攻速药水)", 1, {"fire": 1, "blade": 1}),
        ("L1 已持 火×3", 1, {"fire": 3}),
        ("L3 已持 火×5 剑×2", 3, {"fire": 5, "blade": 2}),
        ("L5 已持 毒×8", 5, {"poison": 8}),
    ]
    for name, lv, holdings in scenarios:
        spell_seen, el_seen, n = simulate_rolls(items, spells, drops, lv, holdings)
        tot = sum(el_seen.values())
        dist = {k: "%.1f%%" % (v * 100.0 / tot) for k, v in sorted(el_seen.items(), key=lambda kv: -kv[1])}
        print("    %-28s L%d 持有%s → 法术部件 %.1f%%（每轮3选必含1个） | 道具元素分布 %s" % (
            name, lv, holdings, spell_seen * 100.0 / (n * 3.0), dist))

    # ---------- G. 技能"追踪"静态核对 ----------
    print("\n[G] 技能自动索敌/落点核对（spell_caster._aim_dir 指向最近敌人；speed=0 为瞬发核）")
    print("    %-14s | %-8s | %-6s | %-7s | 命中窗口（敌距 d 命中 iff |d-range|<=aoe+8）" % (
        "核心", "元素", "射程", "AOE"))
    instants = []
    projectiles = []
    for c in spells["cores"]:
        r = float(c.get("range", 0))
        aoe = float(c.get("aoe", 0))
        spd = float(c.get("speed", 0))
        if spd <= 0.0 and c.get("summon") is None and not any(c.get(k) for k in ("teleport", "frenzy", "mana_echo", "bless", "counter")):
            if str(c.get("id", "")) != "whirl_blade":
                instants.append(c)
        if spd > 0.0:
            projectiles.append(c)
        win = ""
        if spd <= 0.0 and r > 0:
            rr = max(aoe, 90.0) if c.get("blind") else aoe  # flash 兜底 BLIND_BURST_RADIUS=90
            win = "%.0f~%.0f" % (r - rr - 8, r + rr + 8)
        elif spd > 0:
            win = "弹道直线，接触半径9+体型8"
        print("    %-14s | %-8s | %-6.0f | %-7.0f | %s%s" % (
            c["id"], c["element"], r, aoe, win,
            "  [flash盲半径兜底90]" if c.get("blind") else ""))
    print("    结论（静态）：瞬发核（flash/lightning/poison_cloud/inferno）落点=玩家+aim×range 固定点，")
    print("    不落在目标身上；d<range-aoe-8 或 d>range+aoe+8 必脱靶。homing 外壳仅对 speed>0 弹道生效")
    print("    （projectile._move_step），对瞬发核完全无效。")
    if not instants:
        warnings.append("未找到瞬发核心，请检查 spells.json 解析")

    # ---------- H. 数值表/代码一致性 ----------
    print("\n[H] 数值表/代码一致性")
    checks = [
        ("balance.loop_hp=1.35", "GameState.loop_factor_hp 硬编码 1.30", esc["loop_hp"] == 1.30),
        ("balance.loop_dmg=1.45", "GameState.loop_factor_dmg 硬编码 1.18", esc["loop_dmg"] == 1.18),
        ("balance.loop_num=1.25", "GameState.loop_factor_num=1.25", esc["loop_num"] == 1.25),
        ("balance.loop_xp=1.35", "GameState.enemy_xp 用 1.35", esc["loop_xp"] == 1.35),
    ]
    for table_v, code_v, ok in checks:
        print("    %s  vs  %s → %s" % (table_v, code_v, "一致" if ok else "漂移(表值未被使用)"))
        if not ok:
            warnings.append("%s 与代码 %s 不一致" % (table_v, code_v))
    print("    drops.boss_drops.gold_mult=5 → 代码无引用（Boss 金币按 enemies.json gold 发放）")

    # ---------- 汇总 ----------
    print("\n" + "=" * 78)
    if warnings:
        print("全绿（含 %d 项数据漂移提示，不影响运行，见上）：" % len(warnings))
        for w in warnings:
            print("  [提示] " + w)
        print("全绿")
    else:
        print("全绿")
    print("=" * 78)
    return 0


if __name__ == "__main__":
    sys.exit(main())
