# -*- coding: utf-8 -*-
"""生成第二轮报告的分章 A（火焰/寒冰/雷电/剧毒），由并行代理 A 产出。"""
import csv
import os

BASE = r"H:\rougelike_crew"
CSV = os.path.join(BASE, r"tools\tests\school_test_results_v2\school_test_results.csv")
SEC = os.path.join(BASE, r"docs\reports\第二轮-章节-火焰寒冰雷电剧毒.md")
MAIN = os.path.join(BASE, r"docs\reports\流派通关测试报告-第二轮.md")

MY_SCHOOLS = ["fire", "ice", "lightning", "poison"]
NAMES = {"fire": "火焰", "ice": "寒冰", "lightning": "雷电", "poison": "剧毒"}
# 第一轮数据（来自 docs/reports/流派通关测试报告.md）
V1 = {
    "fire":      {"n": 3, "wins": 2, "rate": 67, "time": 468, "kills": 2666, "level": 26.0, "gold": 723, "hp": 220, "wave": 3.0, "dps": 451},
    "ice":       {"n": 3, "wins": 1, "rate": 33, "time": 689, "kills": 1845, "level": 18.5, "gold": 106, "hp": 142, "wave": 3.0, "dps": 190},
    "lightning": {"n": 3, "wins": 2, "rate": 67, "time": 402, "kills": 1840, "level": 21.3, "gold": 694, "hp": 227, "wave": 3.0, "dps": 267},
    "poison":    {"n": 3, "wins": 2, "rate": 67, "time": 908, "kills": 2387, "level": 25.0, "gold": 506, "hp": 259, "wave": 3.0, "dps": 293},
}

rows = {}
with open(CSV, encoding="utf-8-sig") as f:
    for r in csv.DictReader(f):
        if r["school"] in MY_SCHOOLS and r["result"] in ("VICTORY", "DEFEAT", "TIMEOUT"):
            rows.setdefault(r["school"], []).append(r)


def avg(key, rs):
    vals = [float(r[key]) for r in rs if r.get(key) not in (None, "")]
    return sum(vals) / len(vals) if vals else 0.0


L = []
L.append("")
L.append("## 分章 A：火焰 / 寒冰 / 雷电 / 剧毒（本轮 8 局，全部 DEFEAT）")
L.append("")
L.append("> 本分章由并行代理 A 产出，数据源 `tools/tests/school_test_results_v2/school_test_results.csv`（run 1-2）。")
L.append("")
L.append("### A.1 每流派数据（第二轮）")
L.append("")
L.append("| 流派 | 局数 | 通关 | 通关率 | 用时(游戏s) | 击杀 | 等级 | 金币 | 剩余HP | 最大波次 | DPS峰值 |")
L.append("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
for s in MY_SCHOOLS:
    rs = rows.get(s, [])
    wins = sum(1 for r in rs if r["result"] == "VICTORY")
    L.append("| %s(%s) | %d | %d | %.0f%% | %.0f | %.0f | %.1f | %.0f | %.0f | %.1f | %.0f |" % (
        s, NAMES[s], len(rs), wins, wins / len(rs) * 100 if rs else 0,
        avg("game_time_s", rs), avg("kills", rs), avg("level", rs),
        avg("gold", rs), avg("hp", rs), avg("max_wave", rs), avg("max_dps", rs)))
L.append("")
L.append("单局明细：")
L.append("")
L.append("| 流派 | 局 | 结果 | 游戏秒 | 击杀 | 等级 | HP/最大HP | 金币 | 波次 | DPS | 道具数 |")
L.append("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
for s in MY_SCHOOLS:
    for r in sorted(rows.get(s, []), key=lambda x: int(x["run"])):
        L.append("| %s | %s | %s | %s | %s | %s | %s/%s | %s | %s | %s | %s |" % (
            NAMES[s], r["run"], r["result"], r["game_time_s"], r["kills"], r["level"],
            r["hp"], r["max_hp"], r["gold"], r["max_wave"], r["max_dps"], r["item_count"]))
L.append("")
L.append("### A.2 与第一轮对比（同一流派 3 局 → 本轮 2 局）")
L.append("")
L.append("| 流派 | 通关率 一→二 | 用时 一→二 | 击杀 一→二 | 等级 一→二 | 剩余HP 一→二 | DPS 一→二 |")
L.append("| --- | --- | --- | --- | --- | --- | --- |")
for s in MY_SCHOOLS:
    rs = rows.get(s, [])
    v1 = V1[s]
    wins = sum(1 for r in rs if r["result"] == "VICTORY")
    rate2 = wins / len(rs) * 100 if rs else 0
    L.append("| %s(%s) | %d%% → %.0f%% | %.0f → %.0f | %.0f → %.0f | %.1f → %.1f | %.0f → %.0f | %.0f → %.0f |" % (
        s, NAMES[s], v1["rate"], rate2,
        v1["time"], avg("game_time_s", rs), v1["kills"], avg("kills", rs),
        v1["level"], avg("level", rs), v1["hp"], avg("hp", rs),
        v1["dps"], avg("max_dps", rs)))
L.append("")
L.append("### A.3 对比结论")
L.append("")
L.append("1. **通关率全面崩盘（0/8）**：火焰 67%→0%、雷电 67%→0%、剧毒 67%→0%、寒冰 33%→0%。8 局全部 DEFEAT 且全部死于 wave 3（最终 Boss 阶段），HP 全部归零。第一轮 12 局中 7 局存活到结算，本轮 8 局无一生还。")
L.append("2. **死亡时间提前、击杀与等级大幅下滑**：火焰用时 468→156s、雷电 402→137s、剧毒 908→303s、寒冰 689→305s；击杀数几乎腰斩（火焰 2666→793、雷电 1840→510）；最终等级也普遍低 8-13 级。升级曲线平滑化（移除 L1-3 硬编码加速）后等级增长放缓，叠加早死，等级明显偏低。")
L.append("3. **初始双技能随机化反而破坏流派成型**：本轮最常见的构筑是「指定流派却打出其他流派核心」——火焰局终局网格是 whirl_blade+ice_shard（近战+冰系）、寒冰长局是 fireball+inferno、雷电局带出 teleport/counterspell、剧毒局带出 water_bolt/thorn_vine。原因：开局随机 2 技能决定元素门控，`--school` 倾向权重（道具+150/核心+120）敌不过元素选择池过滤，流派倾向参数形同虚设。")
L.append("4. **精英血包 10% 后生存压力剧增**：日志中 HP 频繁大起大落（火焰局 60↔202↔29↔188 反复横跳），冰/毒深局后期也保不住血线，最终都在 wave 3 弹幕阶段被磨死。配合「怪物 30 种+弹幕 8 类」的强度提升，回复与血量词条跟不上新难度。")
L.append("5. **DPS 增长断层明显**：火焰局 DPS 卡在 68-78 长达 125 秒（t=25~150 不涨），说明升级曲线放缓后格子/道具跟不上，前期伤害不足被怪群围殴；寒冰深局 DPS 45→115→214→440 稳步爬升但 468 秒仍未够打死 Boss。")
L.append("")
L.append("### A.4 平衡建议")
L.append("")
L.append("1. **元素门控修复优先（第一轮建议仍未落地且被初始双技能放大）**：`--school`/流派开局应直接解锁对应元素核心进选择池，否则随机初始技能把流派带偏后，任何倾向权重都无法纠正。建议开局 2 技能至少 1 个来自所选流派。")
L.append("2. **难度曲线回调**：当前 0/8 通关说明 v48-v51 的敌人强化（30 种+弹幕）+ 精英血包 10% + 升级放缓三者叠加过猛。建议先回调一项（如精英血包回到必掉或 50%），再观察 2 轮。")
L.append("3. **前期输出断层**：升级曲线平滑后 0-150 秒阶段 DPS 长期不涨（火焰局 125 秒无提升），建议给第 3/5 次升级固定提供一次构筑提升（如额外法术格子），避免「等级在涨、伤害不涨」。")
L.append("4. **Boss 战强度**：8 局全部死在 wave 3，说明最终阶段弹幕密度对 autoplay（以及大部分玩家）过载。建议降低 wave 3 弹幕密度或给玩家一层减伤/护盾容错。")
L.append("")
L.append("### A.5 体验建议（非数值）")
L.append("")
L.append("- **升级节奏体感**：前期（0-60s）升级飞快、体感正反馈强，但 60s 后等级爬升明显变慢且「升级不给构筑」的真空期很长（火焰局连续 100+s DPS 无变化），体感像「空转」。建议每次升级至少滚动 1 个法术/道具选项并保证可替换。")
L.append("- **构筑成型体感**：初始双技能带来更强的开局（前 30 秒就有 2 个核心），但随即被元素门控锁死——玩家/autoplay 捡到与开局元素无关的流派道具时完全无法利用，体感「流派标签骗人」。寒冰深局成型后（DPS 440）清场爽快，但成型窗口太窄（t=160 才起飞），前期被 goblin/弹幕怪围殴的挫败感重。")
L.append("- **受击与回复体感**：精英血包 10% 后，中后期血线长期在 30%-60% 徘徊，配合弹幕怪无法走位输出，操作压力集中在「躲弹幕」而非「构筑」，建议观察正式玩家是否出现「无回复期」挫败。")
L.append("- **最终 Boss 体感**：wave 3 从「可以一战」变成「必死墙」——本分章 8 局全灭于此。若保留当前难度，建议给 autoplay 之外的正式玩家至少一个 Boss 前保命道具/技能提示。")
L.append("")

sec_text = "\n".join(L) + "\n"
os.makedirs(os.path.dirname(SEC), exist_ok=True)
with open(SEC, "w", encoding="utf-8", newline="\n") as f:
    f.write(sec_text)
print("section written:", SEC, len(sec_text))

# 合并到主报告（追加模式，避免覆盖其他并行代理已写入的章节）
if os.path.exists(MAIN):
    with open(MAIN, encoding="utf-8") as f:
        existing = f.read()
    if "分章 A" in existing:
        print("main already has section A, skip append")
    else:
        with open(MAIN, "a", encoding="utf-8", newline="\n") as f:
            f.write(sec_text)
        print("appended section A to main")
else:
    head = """# 各流派通关测试报告（第二轮）

> 生成方式：并行代理分批跑 12 流派 × 2 局（v48-v51 版本），数据源 `tools/tests/school_test_results_v2/school_test_results.csv`。
> 测试方式：Godot 4.7.1 console + `--headless`，`auto_play.gd` 驱动，`--school <name>` 指定流派倾向。
> 分章结构：各代理分别产出自己的章节，最后合并。

"""
    with open(MAIN, "w", encoding="utf-8", newline="\n") as f:
        f.write(head)
        f.write(sec_text)
    print("created main with section A")
