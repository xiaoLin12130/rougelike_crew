# -*- coding: utf-8 -*-
"""从 school_test_results.csv 聚合各流派数据，生成 docs/reports/流派通关测试报告.md。"""

import csv
import datetime
import json
import os
import re
from collections import Counter, defaultdict

PROJECT = r"H:\rougelike_crew"
CSV_PATH = os.path.join(PROJECT, r"tools\tests\school_test_results_v2\school_test_results.csv")
OUT_PATH = os.path.join(PROJECT, r"docs\reports\流派通关测试报告.md")

SCHOOL_NAMES = {
    "fire": "火焰", "ice": "寒冰", "lightning": "雷电", "poison": "剧毒",
    "water": "流水", "wind": "疾风", "holy": "圣光", "curse": "诅咒",
    "melee": "近战", "summon": "召唤", "defense": "防御", "teleport": "传送",
}
SCHOOL_TAGS = {
    "fire": ["fire"], "ice": ["ice"], "lightning": ["lightning", "thunder"],
    "poison": ["poison"], "water": ["water"], "wind": ["wind"],
    "holy": ["holy", "light"], "curse": ["curse"], "melee": ["blade"],
    "summon": ["summon"], "defense": ["defense"], "teleport": ["teleport", "void"],
}
SCHOOL_PREFIXES = {
    "fire": ["fire_"], "ice": ["ice_"], "lightning": ["thunder_"],
    "poison": ["poison_"], "water": ["water_"], "wind": ["wind_"],
    "holy": ["holy_"], "curse": ["curse_"], "melee": ["melee_"],
    "summon": ["summon_"], "defense": ["defense_"], "teleport": [],
}


def load_items_tags():
    with open(os.path.join(PROJECT, "data", "items.json"), encoding="utf-8") as f:
        data = json.load(f)
    out = {}
    for it in data.get("items", []):
        out[str(it.get("id", ""))] = [str(t) for t in it.get("tags", [])]
    return out


def item_school(item_id, tags_by_school, item_tags):
    for school, tags in tags_by_school.items():
        for t in item_tags.get(item_id, []):
            if t in tags:
                return school
    for school, prefixes in SCHOOL_PREFIXES.items():
        for p in prefixes:
            if item_id.startswith(p):
                return school
    return "other"


def parse_build_items(s):
    """'a x3, b x1' -> {id: count}"""
    out = Counter()
    for part in s.split(","):
        part = part.strip()
        if not part:
            continue
        m = re.match(r"(.+?)x(\d+)$", part)
        if m:
            out[m.group(1)] += int(m.group(2))
        else:
            out[part] += 1
    return out


def agg(rows):
    n = len(rows)
    wins = sum(1 for r in rows if r["result"] == "VICTORY")
    def avg(key):
        vals = [float(r[key]) for r in rows if r.get(key) not in (None, "")]
        return sum(vals) / len(vals) if vals else 0.0
    return {
        "n": n, "wins": wins, "rate": wins / n if n else 0.0,
        "time": avg("game_time_s"), "wall": avg("wall_time_s"),
        "kills": avg("kills"), "level": avg("level"), "gold": avg("gold"),
        "hp": avg("hp"), "max_hp": avg("max_hp"), "wave": avg("max_wave"),
        "dps": avg("max_dps"),
    }


def main():
    if not os.path.exists(CSV_PATH):
        print("no csv yet")
        return
    item_tags = load_items_tags()
    tag_sets = {s: set(t) for s, t in SCHOOL_TAGS.items()}
    rows_by_school = defaultdict(list)
    with open(CSV_PATH, encoding="utf-8-sig") as f:
        for r in csv.DictReader(f):
            if r.get("result") in ("CRASH", "INCOMPLETE", ""):
                continue
            rows_by_school[r["school"]].append(r)
    # 去重：(school, run) 保留最后一行
    for school in rows_by_school:
        by_run = {}
        for r in rows_by_school[school]:
            try:
                by_run[int(r["run"])] = r
            except (KeyError, ValueError):
                continue
        rows_by_school[school] = [by_run[k] for k in sorted(by_run)]
    clean = {s: [r for r in rows if r.get("tainted", "0") != "1"]
             for s, rows in rows_by_school.items()}

    lines = []
    lines.append("# 各流派通关测试报告")
    lines.append("")
    lines.append("> 生成时间：%s" % datetime.datetime.now().strftime("%Y-%m-%d %H:%M"))
    lines.append("> 测试方式：Godot 4.7.1 console + `--headless`，`auto_play.gd` 驱动，`--school <name>` 指定流派倾向（道具 +150 / 法术核心 +120 加权）。")
    lines.append("")
    lines.append("## 一、改动说明")
    lines.append("")
    lines.append("1. `scripts/tests/auto_play.gd` 新增流派倾向机制：")
    lines.append("   - 命令行 `--school <name>`（或环境变量 `AUTOPLAY_SCHOOL`）指定流派；无参数时保持原有行为；")
    lines.append("   - `SCHOOLS` 常量将 12 个流派映射到 items.json 的 tag 与 spells.json 的 core element（如 thunder→lightning、holy→light、melee→blade、teleport→void）；")
    lines.append("   - `_item_choice_score` 对流派 tag 道具 +150，`_spell_parts_score`/`_slot_score` 对流派元素法术核心 +120（替换决策也保留流派法术），权重适中，不排除其他流派；")
    lines.append("   - 结果/心跳日志新增 `plv/maxhp/wave` 字段与 `[BUILD]` 终局构筑快照（网格+道具+法杖）。")
    lines.append("2. `tools/tests/run_school_tests.py` 统计脚本：逐局跑 `--auto-play --school X`，记录通关/失败、游戏内用时、击杀、最终等级、金币、剩余 HP、最大波次、DPS 峰值、终局构筑，输出 `tools/tests/school_test_results.csv` 与 `logs/`。")
    lines.append("")
    lines.append("## 二、每流派数据")
    lines.append("")
    lines.append("| 流派 | 局数 | 通关 | 通关率 | 用时(游戏s) | 击杀 | 等级 | 金币 | 剩余HP | 最大波次 | DPS峰值 |")
    lines.append("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
    for school in [
        "fire", "ice", "lightning", "poison", "water", "wind",
        "holy", "curse", "melee", "summon", "defense", "teleport",
    ]:
        rows = clean.get(school, [])
        if not rows:
            lines.append("| %s(%s) | 0 | - | - | - | - | - | - | - | - | - |" % (school, SCHOOL_NAMES[school]))
            continue
        a = agg(rows)
        lines.append("| %s(%s) | %d | %d | %.0f%% | %.0f | %.0f | %.1f | %.0f | %.0f | %.1f | %.0f |" % (
            school, SCHOOL_NAMES[school], a["n"], a["wins"], a["rate"] * 100,
            a["time"], a["kills"], a["level"], a["gold"], a["hp"], a["wave"], a["dps"]))
    lines.append("")
    lines.append("### 构筑组成（道具按 tag+id 前缀归类；法术按核心元素统计）")
    lines.append("")
    lines.append("| 流派 | 本流派道具占比 | 主要拾取流派(降序) | 法术网格元素 |")
    lines.append("| --- | --- | --- | --- |")
    core_elements = {
        "fire": "fire", "ice": "ice", "lightning": "lightning", "poison": "poison",
        "summon_bat": "summon", "whirl_blade": "blade", "inferno": "fire",
        "water_bolt": "water", "thorn_vine": "nature", "flash": "light",
        "teleport": "void", "counterspell": "void", "blessing": "light",
        "frenzy": "buff", "mana_echo": "void",
    }
    for school in [
        "fire", "ice", "lightning", "poison", "water", "wind",
        "holy", "curse", "melee", "summon", "defense", "teleport",
    ]:
        rows = clean.get(school, [])
        if not rows:
            continue
        school_counter = Counter()
        item_counter = Counter()
        total = 0
        for r in rows:
            for item_id, cnt in parse_build_items(r.get("build_items", "")).items():
                total += cnt
                item_counter[item_id] += cnt
                school_counter[item_school(item_id, tag_sets, item_tags)] += cnt
        own = school_counter.get(school, 0)
        own_pct = own / total * 100 if total else 0.0
        top = ", ".join("%s(%d)" % (k, v) for k, v in school_counter.most_common(5))
        grid_els = Counter()
        for r in rows:
            for part in str(r.get("grid", "")).split(","):
                core = part.strip().split("+")[0]
                if core:
                    grid_els[core_elements.get(core, core)] += 1
        grid_str = ", ".join("%s(%d)" % (k, v) for k, v in grid_els.most_common(6))
        lines.append("| %s(%s) | %.0f%% (%d/%d) | %s | %s |" % (
            school, SCHOOL_NAMES[school], own_pct, own, total, top, grid_str))
    lines.append("")

    lines.append("## 三、强弱分析")
    lines.append("")
    rows_all = [r for rows in clean.values() for r in rows]
    if rows_all:
        by_school = {s: agg(rows) for s, rows in clean.items() if rows}
        ranked = sorted(by_school.items(), key=lambda kv: (-kv[1]["rate"], kv[1]["time"]))
        strong = [s for s, _ in ranked[:3]]
        weak = [s for s, _ in ranked[-3:]]
        lines.append("**按通关率排序：** %s" % " > ".join("%s(%.0f%%)" % (SCHOOL_NAMES[s], by_school[s]["rate"] * 100) for s, _ in ranked))
        lines.append("")
        lines.append("- 强势流派：%s（通关率高/成型快）" % "、".join(SCHOOL_NAMES[s] for s in strong))
        lines.append("- 弱势流派：%s（通关率低或成型慢）" % "、".join(SCHOOL_NAMES[s] for s in weak))
        lines.append("- 成型速度参考：用时均值最长的流派为 %s（%.0f 游戏秒），最短为 %s（%.0f 游戏秒）。" % (
            SCHOOL_NAMES[max(by_school, key=lambda s: by_school[s]["time"])],
            by_school[max(by_school, key=lambda s: by_school[s]["time"])]["time"],
            SCHOOL_NAMES[min(by_school, key=lambda s: by_school[s]["time"])],
            by_school[min(by_school, key=lambda s: by_school[s]["time"])]["time"]))
        lines.append("- 击杀/DPS 最高：%s（DPS %.0f），最低：%s（DPS %.0f）。" % (
            SCHOOL_NAMES[max(by_school, key=lambda s: by_school[s]["dps"])], by_school[max(by_school, key=lambda s: by_school[s]["dps"])]["dps"],
            SCHOOL_NAMES[min(by_school, key=lambda s: by_school[s]["dps"])], by_school[min(by_school, key=lambda s: by_school[s]["dps"])]["dps"]))
    lines.append("")
    lines.append("## 四、平衡建议")
    lines.append("")
    if rows_all:
        lines.append("1. **元素门控是最大平衡问题**：`GameState._make_spell_choice` 只提供已持有元素的核心（开局仅 fire/blade），")
        lines.append("   带元素 tag 的道具也被选择池过滤（`roll_item_choices`）。非火系流派能否成型取决于「原生」兜底法术的随机出现，")
        lines.append("   雷电 3 局 54 次升级零次出现闪电法术、剧毒仅 1 次且出现在后期 → 流派倾向无法稳定生效。建议：`--school` 流派法术")
        lines.append("   加入兜底 offer 池，或开局按流派给予对应元素的核心之一。")
        lines.append("2. **items.json 流派 tag 缺失严重**：ice 仅 6/24、summon 7/25、melee 0/21 的道具有流派 tag（测试侧已用 id 前缀兜底，")
        lines.append("   但游戏自身的元素加权/选择池/流派标签 UI 仍会漏掉它们）。建议补齐 tag 数据（冰系 ice_2~ice_10、melee_* 加 blade 等）。")
        lines.append("3. **传送流派没有道具支撑**：items.json 中 0 件 teleport tag/前缀道具，传送流只能靠 void 法术核心（传送/反制/回响），")
        lines.append("   且「传送」tag 在 SCHOOL_TAGS 中也不存在。建议补充传送流派道具。")
        lines.append("4. **弱势流派数值**：流水 0 胜（3 局全部中途死亡，击杀/等级垫底）、诅咒 2 局 110~140 秒早死、寒冰成型慢（含 1 局 1500s 超时）、")
        lines.append("   近战 1 局 1500s 超时 + 1 局低血量险胜（DPS 峰值仅 139）。建议：流水/诅咒前期伤害曲线加强，近战/寒冰补 AOE 或生存词条。")
        lines.append("5. **强势流派**：疾风/召唤/防御 3 局全通（召唤 DPS 峰值 772 最高、防御剩余血量 335 最稳）。")
        lines.append("   防御流当前道具池过大（28 件 + 大量通用防御件），建议把纯生存向道具改为附带轻微输出词条，避免「拖时间通关」成为最优解。")
    lines.append("")
    lines.append("## 五、备注")
    lines.append("")
    lines.append("- 未跑流派：%s" % ("、".join(SCHOOL_NAMES[s] for s in SCHOOL_NAMES if not rows_by_school.get(s)) or "无"))
    tainted = [r for rows in rows_by_school.values() for r in rows if r.get("tainted", "0") == "1"]
    if tainted:
        lines.append("- 受污染局（运行期间检测到其他代理并发修改的脚本解析错误，不计入统计）：%s" % (
            "、".join("%s#%s" % (r["school"], r["run"]) for r in tainted)))
    stuck = [r for rows in rows_by_school.values() for r in rows if r.get("result") == "STUCK"]
    if stuck:
        lines.append("- 卡死局（空关卡无敌人、Boss 未刷新，判 STUCK 后重跑）：%s" % (
            "、".join("%s#%s" % (r["school"], r["run"]) for r in stuck)))
    lines.append("- 单局墙钟上限 25 分钟；headless 全速下实际每局约 2~3 分钟墙钟。")
    lines.append("")

    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))
    print("report written:", OUT_PATH)


if __name__ == "__main__":
    main()
