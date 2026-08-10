# -*- coding: utf-8 -*-
"""生成中文交付报告 work/交付报告-balance_gold_fix.md（前后对比）。
用法：python tools/scripts/write_report_balance_gold.py
"""

import io
import json
import os
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def load(name):
    with open(os.path.join(ROOT, "data", name + ".json"), encoding="utf-8") as f:
        return json.load(f)


def main():
    enemies = load("enemies")
    levels = load("levels")
    drops = load("drops")

    gold_by_id = {e["id"]: e["gold"] for e in enemies["enemies"]}
    tot_s, tot_g = 0, 0
    for l in levels["levels"]:
        for w in l["waves"]:
            for s in w["spawn"]:
                n = int(w.get("count", 1))
                tot_s += n
                tot_g += n * gold_by_id.get(s, 0)
    avg = tot_g / tot_s
    boss = sum((3 if b["id"] == "final_god" else 1) * b["gold"] for b in enemies["bosses"])

    rows = []
    rows.append("# 交付报告：平衡与金币经济调整（问题 4/6）")
    rows.append("")
    rows.append("> 日期：2026-08-10｜任务：难度增长（问题4）+ 金币经济（问题6）"
                "｜验收：test_curves OK / gold_sim ALL PASS / smoke SMOKE OK")
    rows.append("")
    rows.append("## 1. 难度增长调整（问题 4：非反甲流后期死不掉）")
    rows.append("")
    rows.append("| 参数 | 调整前 | 调整后 | 生效位置 |")
    rows.append("|---|---|---|---|")
    rows.append("| 敌人生命成长 level_hp | 1.18 | **1.22** | balance.json + game_state.gd level_factor |")
    rows.append("| 敌人攻击成长 level_atk | 0.12 | **0.16** | balance.json + game_state.gd enemy_atk |")
    rows.append("| loop 血量系数 loop_hp | 1.30 | **1.34** | balance.json + game_state.gd loop_factor_hp |")
    rows.append("| loop 伤害系数 loop_dmg | 1.18 | **1.24** | balance.json + game_state.gd loop_factor_dmg |")
    rows.append("| 玩家初始 HP | 100 | **85** | balance.json player.hp（GameState 运行时读取） |")
    rows.append("| 吸血全局上限 | 4% | **3%** | balance.json lifesteal.cap + game_state.gd 钳制 |")
    rows.append("| 防御减伤合计上限 | 无（stone 35% + amulet 15% = 50%） | **封顶 50%** "
                "| game_root._on_player_hit 增加 minf 上限 |")
    rows.append("")
    rows.append("说明：")
    rows.append("- GameState 的敌人缩放因子此前为硬编码（1.18/0.12/1.30/1.18），"
                "本次同步为表值（与 balance.json 对齐，沿用 num_drift_fix 的表值对齐约定）。")
    rows.append("- 防御减伤检查结论：实际减伤 = stone_armor 曲线（上限 35%）+ defense_amulet 曲线（上限 15%）"
                "= 50%，未超过 50%；已在扣血处显式封顶 50%，防止未来曲线上调后叠加超限。")
    rows.append("- 回血体系未动（击杀 2%/精英 10%/Boss 30% 契约不变）。")
    rows.append("")
    rows.append("## 2. 金币经济调整（问题 6：获取过多无法消耗）")
    rows.append("")
    rows.append("| 项目 | 调整前 | 调整后 | 生效位置 |")
    rows.append("|---|---|---|---|")
    rows.append("| 击杀掉金概率 | 1.0 | **0.65** | drops.json kill_drops + game_root 独立命中判定 |")
    rows.append("| 普通敌人金币 | 1-4（wizard/healer/mimic 为 4） | **1-3**（4→3） | enemies.json |")
    rows.append("| Boss 金币 | 40/55/70/85/105/300 | **30/44/56/68/84/240** "
                "| enemies.json（final_god 击杀×3 不变） |")
    rows.append("| 强化价格 | 200 起，每级 +100 | **250 起**，每级 +100 "
                "| game_state.gd WAND_UPGRADE_BASE_COST |")
    rows.append("| 刷新价格 | 30（任务预期）→ 实际已 80 | **保持 80** | wand_shop.gd（见 §4 说明） |")
    rows.append("| 法杖价格 | 不变 | **不变** | wands.json 未动（另一代理在用，禁止改） |")
    rows.append("")
    rows.append("### 2.1 掉落语义修正（关键）")
    rows.append("原实现中 kill_drops 的 prob 只是表内权重归一（单条目永远命中），"
                "且 type=gold 不发放金币、只累加保底计数，导致：")
    rows.append("- 保底金币实际变成**每 8 杀必发 15 金**（约 1.875 金/杀），占 R2 收入近一半"
                "——这是金币泛滥的主要来源之一；")
    rows.append("- prob 改成 0.65 后原代码不会产生任何效果。")
    rows.append("本次改为**独立命中判定**：每次击杀以 prob 判定金币掉落"
                "（掉落=发放敌人金币并重置保底），未命中才累计空刀，连续 8 空刀才触发 15 金保底"
                "（期望约 0，真正成为兜底）。")
    rows.append("")
    rows.append("### 2.2 金币模拟（tools/tests/gold_sim.py，按 R2 击杀分布）")
    rows.append("")
    rows.append("| 场景 | 击杀 | 收入(新) | 支出 | **结余(新)** | 结余(旧,同支出模型) | R2 实测 |")
    rows.append("|---|---:|---:|---:|---:|---:|---:|")
    for kills, note, inc, sp, net_new, net_old in [
        (1549, "R2 低击杀胜局", 3064, 1660, 1404, 6471),
        (2000, "R2 中位击杀", 3769, 2310, 1459, 7798),
        (2608, "R2 高击杀胜局", 4719, 2390, 2329, 10383),
    ]:
        rows.append("| %s | %d | %d | %d | **%d** | %d | 2858-5968 |"
                    % (note, kills, inc, sp, net_new, net_old))
    rows.append("")
    rows.append("模拟口径：平均普通金币 %.3f（levels.json 波次加权）、Boss 金币/局 %d（final×3）、"
                "掉金概率 %.2f；支出 = 法杖 2-3 把（wands.json 中位价 450）+ 强化 2 次（250+350）"
                "+ 刷新 80×2-4 + 药水 120×0-1；保底期望按 8 连空刀模型计入。"
                % (avg, boss, drops["kill_drops"][0]["prob"]))
    rows.append("")
    rows.append("**结论：新经济 5 关通关结余 1404-2329，全部 ≤ 2500"
                "（R2 实测 2858-5968 → 明显下降，高击杀局仍有余钱但不再溢出）。**")
    rows.append("")
    rows.append("## 3. 测试结果")
    rows.append("")
    rows.append("| 测试 | 命令 | 结果 |")
    rows.append("|---|---|---|")
    rows.append("| 数据一致性 | python tools/tests/test_curves.py | **OK**"
                "（含新断言：level_hp 1.22 / level_atk 0.16 / player hp 85 / 吸血 cap 3%"
                " / 金币区间 / 掉金概率 0.65 / 防御合计≤50%） |")
    rows.append("| 金币模拟 | python tools/tests/gold_sim.py | **ALL PASS**（3 场景结余 ≤2500） |")
    rows.append("| Godot 冒烟 | Godot headless -s smoke_test.gd | **SMOKE OK**"
                "（exit 0，无解析错误，无残留进程） |")
    rows.append("| 运行时断言 | 临时脚本（跑完已删） | CHECK BALANCE ALL PASS"
                "（缩放因子/吸血 3%/强化 250/max_hp 135=85+50） |")
    rows.append("")
    rows.append("## 4. 边界与说明")
    rows.append("")
    rows.append("- **wand_shop.gd 未修改**：任务预期刷新价 30→50，但该常量当前已是 80"
                "（此前 gold_economy 任务已上调），高于目标 50，再改反而降价，故保持 80 并在模拟中按 80 计"
                "；避免与商店重构代理（Noether）冲突。")
    rows.append("- **game_state.gd 改动范围说明**：除吸血 cap（任务授权）外，敌人缩放硬编码与强化基价"
                "（200→250）也在该文件，属任务目标必需改动，已同步 balance.json 表值。")
    rows.append("- **game_root.gd 改动范围说明**：掉金概率门控、保底语义修正、防御减伤封顶三处"
                "均在该文件（不在禁止清单内），为任务目标必需。")
    rows.append("- **观察（未改动）**：apply_item_effects_to_stats 会把 life_crystal/defense_crystal"
                " 的基础值无条件计入 max_hp（+50，存量行为）；本次玩家 HP 85 的实际开局 max_hp 为 135"
                "（原 150），仍符合 -15% 的调整意图。")
    rows.append("- 掉血上限/回血/护盾机制未触碰；wands.json、scripts/combat/*、hud.gd、build_panel.gd 未修改。")
    rows.append("")
    rows.append("## 5. 涉及文件")
    rows.append("")
    rows.append("- data/balance.json（player.hp / enemy_scaling / 新增 lifesteal.cap）")
    rows.append("- data/enemies.json（仅 gold 字段降档）")
    rows.append("- data/drops.json（kill_drops gold prob 1.0→0.65）")
    rows.append("- scripts/core/game_state.gd（缩放因子硬编码同步 / 吸血 cap 读取 balance"
                " / WAND_UPGRADE_BASE_COST 250）")
    rows.append("- scenes/game/game_root.gd（掉金门控 + 保底语义 + 防御 50% 封顶）")
    rows.append("- tools/tests/test_curves.py（断言同步）")
    rows.append("- tools/tests/gold_sim.py（新增金币模拟）")
    rows.append("")

    out = os.path.join(ROOT, "work", "交付报告-balance_gold_fix.md")
    with open(out, "w", encoding="utf-8") as f:
        f.write("\n".join(rows))
    print("report written: %s (%d lines)" % (out, len(rows)))


if __name__ == "__main__":
    main()
