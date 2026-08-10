# -*- coding: utf-8 -*-
"""金币经济模拟（问题 6）：按 R2 击杀分布验证 5 关通关后金币结余 ≤ 2500。

模型（与游戏代码逐条对应，2026-08-10 平衡调整后）：
- 收入 = 普通击杀 × 平均金币 × 掉金概率 + Boss 金币 × 掉金概率 + 保底期望
  * 平均金币：按 levels.json 波次构成 × enemies.json gold 加权（只读数据表）
  * Boss 金币：6 Boss（final_god 按 game_root 的 ×3 计算），全部经击杀掉落概率门控
  * 保底：连续 8 次空刀补发 15 金；空刀概率 q=1-prob，期望 ≈ (k-7)×q^8×15（极小）
- 支出 = 法杖购买 2-3 把（wands.json 中位价，任务禁止改法杖价格）
  + 强化 2 次（game_state.gd WAND_UPGRADE_BASE_COST=250，每级 +100）
  + 刷新若干（wand_shop.gd REFRESH_PRICE=80，已高于任务目标 50，未再调整）
  + 高击杀局额外 1 瓶回复药（HEAL_POTION_PRICE=120）
- 场景：R2 胜局击杀分布 1549 / 2000 / 2608

验收：终局结余 ≤ 2500（旧经济 2858-5968 → 新经济明显下降）→ ALL PASS
"""

import io
import json
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DATA = os.path.join(ROOT, "data")

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

FAILS = []


def load(name):
    with open(os.path.join(DATA, name + ".json"), encoding="utf-8") as f:
        return json.load(f)


def median(xs):
    s = sorted(xs)
    n = len(s)
    return s[n // 2] if n % 2 else (s[n // 2 - 1] + s[n // 2]) / 2.0


def main():
    levels = load("levels")
    enemies = load("enemies")
    drops = load("drops")
    wands = load("wands")

    # ---- 数据契约检查 ----
    gold_prob = next((float(d["prob"]) for d in drops["kill_drops"]
                      if d.get("type") == "gold"), 0.0)
    if abs(gold_prob - 0.65) > 1e-9:
        FAILS.append("kill_drops gold prob != 0.65 (got %s)" % gold_prob)
    for e in enemies["enemies"]:
        if not (1 <= e["gold"] <= 3):
            FAILS.append("enemy %s gold out of 1..3: %s" % (e["id"], e["gold"]))
    for b in enemies["bosses"]:
        if not (30 <= b["gold"] <= 240):
            FAILS.append("boss %s gold out of 30..240: %s" % (b["id"], b["gold"]))

    # ---- 平均普通金币（新表，levels.json 波次加权）----
    gold_by_id = {e["id"]: e["gold"] for e in enemies["enemies"]}
    total_spawns = 0
    total_gold = 0
    for lv in levels["levels"]:
        for w in lv["waves"]:
            for s in w["spawn"]:
                n = int(w.get("count", 1))
                total_spawns += n
                total_gold += n * gold_by_id.get(s, 0)
    avg_gold = total_gold / total_spawns

    # ---- Boss 金币 / 局（final_god ×3，与 boss.gd 一致）----
    boss_total = 0
    for b in enemies["bosses"]:
        mult = 3 if b["id"] == "final_god" else 1
        boss_total += b["gold"] * mult

    # ---- 支出（价格常量与脚本同步；wands 价格只读）----
    wand_price = median([int(w["price"]) for w in wands["wands"]])
    upgrade_base = 250          # game_state.gd WAND_UPGRADE_BASE_COST（200→250）
    upgrade_step = 100          # game_state.gd WAND_UPGRADE_STEP_COST
    refresh_price = 80          # wand_shop.gd REFRESH_PRICE（已高于任务目标 50）
    potion_price = 120          # wand_shop.gd HEAL_POTION_PRICE
    upgrades_cost = upgrade_base + (upgrade_base + upgrade_step)  # 强化 2 次

    scenarios = [
        # (kills, wands, refreshes, potions, 说明)
        (1549, 2, 2, 0, "R2 低击杀胜局"),
        (2000, 3, 3, 1, "R2 中位击杀"),
        (2608, 3, 4, 1, "R2 高击杀胜局"),
    ]

    def income(kills, prob, avg, boss_total_, pity_per_kill=None):
        """收入 = (kills-6 普通杀) × avg × prob + boss_total × prob + 保底期望"""
        norm = max(kills - 6, 0) * avg * prob
        boss = boss_total_ * prob
        if pity_per_kill is not None:
            pity = pity_per_kill * kills          # 旧经济：每 8 杀必发 15 金
        else:
            q = 1.0 - prob
            pity = 15.0 * max(kills - 7, 0) * (q ** 8)   # 8 连空刀保底期望
        return norm + boss + pity

    def spend(wands_n, refreshes_n, potions_n):
        return (wands_n * wand_price + upgrades_cost
                + refreshes_n * refresh_price + potions_n * potion_price)

    # 旧经济对照（调整前：prob 1.0、avg 2.509、Boss 1255、保底 15/8 杀）
    OLD_AVG = 2.509
    OLD_BOSS = 1255

    print("=== 金币经济模拟（R2 击杀分布 × 5 关）===")
    print("平均普通金币(新表) = %.3f   Boss 金币/局 = %d   掉金概率 = %.2f"
          % (avg_gold, boss_total, gold_prob))
    print("支出：法杖 %d 金/把(中位) ×2-3 + 强化 2 次 %d 金 + 刷新 %d 金 ×2-4 + 药水 %d 金 ×0-1"
          % (wand_price, upgrades_cost, refresh_price, potion_price))
    print()
    header = "%-14s %8s %8s %8s %10s %10s %8s" % (
        "场景(kills)", "收入(新)", "支出", "结余(新)", "结余(旧)", "R2实测", "判定")
    print(header)
    print("-" * len(header))
    ok = True
    for kills, wn, rn, pn, note in scenarios:
        inc_new = income(kills, gold_prob, avg_gold, boss_total)
        sp = spend(wn, rn, pn)
        net_new = inc_new - sp
        # 旧经济：同支出模型（旧强化 500、同法杖/刷新价格）
        old_spend = sp - (upgrades_cost - 500)
        net_old = income(kills, 1.0, OLD_AVG, OLD_BOSS, pity_per_kill=15.0 / 8.0) - old_spend
        verdict = "PASS" if net_new <= 2500 else "FAIL"
        if net_new > 2500:
            ok = False
        print("%-14s %8.0f %8.0f %8.0f %10.0f %10s %8s"
              % (note + "(%d)" % kills, inc_new, sp, net_new, net_old, "2858-5968", verdict))

    print()
    if not ok:
        FAILS.append("存在场景终局结余 > 2500（目标：明显下降至 ≤2500）")

    # 旧经济必须显著高于新经济（说明问题确实被修复）
    for kills, wn, rn, pn, note in scenarios:
        old_spend = spend(wn, rn, pn) - (upgrades_cost - 500)
        net_old = income(kills, 1.0, OLD_AVG, OLD_BOSS, pity_per_kill=15.0 / 8.0) - old_spend
        if net_old <= 2500:
            FAILS.append("旧经济结余应 > 2500（模拟失真）：%s -> %.0f" % (note, net_old))

    if FAILS:
        print("FAILED: %d checks" % len(FAILS))
        for m in FAILS:
            print(" -", m)
        return 1
    print("ALL PASS: 新经济 5 关通关终局结余均 ≤ 2500（R2 实测 2858-5968 → 明显下降）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
