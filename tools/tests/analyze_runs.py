# -*- coding: utf-8 -*-
"""解析 autoplay 运行日志 → 升级节奏/Boss 战/金币/构筑分布 JSON。

用法：python tools/tests/analyze_runs.py
输入：.tools/autoplay_run{1..11}_final.log（本次 11 局）
输出：.tmp/logs/runs_analysis.json + 控制台摘要
"""

import io
import json
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

RUNS = []
for i in range(1, 12):
    p = os.path.join(ROOT, ".tools", "autoplay_run%d_final.log" % i)
    if os.path.exists(p):
        RUNS.append(i)

HB_RE = re.compile(r"\[HB\] t=([\d.]+)")
STAT_RE = re.compile(r"\[AUTOPLAY\] t=(\d+) hp=(\d+) lv=(\d+) kills=(\d+) enemies=(\d+) dps=(\d+) grid=(\d+) items=(\d+)")
KINDS_RE = re.compile(r"\[KINDS\] (.*)")
CHOICES_RE = re.compile(r"\[AUTOPLAY\] choices: (.*)")
LEVELUP_RE = re.compile(r"\[AUTOPLAY\] levelup -> (.*?) score=(\d+)")
RESULT_RE = re.compile(r"\[AUTOPLAY\] RESULT=(\w+) kills=(\d+) time=(\d+) loop=(\d+) level=(\d+) hp=(\d+) gold=(\d+)")
WAND_RE = re.compile(r"\[AUTOPLAY\] wand shop handled")


def decode(path):
    raw = open(path, "rb").read()
    if raw[:2] == b"\xff\xfe":
        return raw.decode("utf-16-le", errors="replace")
    return raw.decode("utf-8", errors="replace")


def parse_run(n):
    lines = [l.strip(" \x00") for l in decode(os.path.join(ROOT, ".tools", "autoplay_run%d_final.log" % n)).split("\n")
             if l.strip(" \x00")]
    run = {"run": n, "hbs": [], "stats": [], "choices": [], "levelups": [], "kinds": [], "result": None, "wand_shops": []}
    for l in lines:
        m = HB_RE.search(l)
        if m:
            run["hbs"].append(float(m.group(1)))
            continue
        m = STAT_RE.search(l)
        if m:
            run["stats"].append({
                "t": int(m.group(1)), "hp": int(m.group(2)), "lv": int(m.group(3)),
                "kills": int(m.group(4)), "enemies": int(m.group(5)), "dps": int(m.group(6)),
                "grid": int(m.group(7)), "items": int(m.group(8))})
            continue
        m = KINDS_RE.search(l)
        if m:
            try:
                run["kinds"].append(json.loads(m.group(1)))
            except Exception:
                pass
            continue
        m = CHOICES_RE.search(l)
        if m:
            run["choices"].append(m.group(1))
            continue
        m = LEVELUP_RE.search(l)
        if m:
            run["levelups"].append({"name": m.group(1), "score": int(m.group(2))})
            continue
        m = RESULT_RE.search(l)
        if m:
            run["result"] = {"result": m.group(1), "kills": int(m.group(2)), "time": int(m.group(3)),
                             "loop": int(m.group(4)), "level": int(m.group(5)), "hp": int(m.group(6)),
                             "gold": int(m.group(7))}
            continue
        if WAND_RE.search(l):
            run["wand_shops"].append(True)
    return run


def t_at(run, t):
    """最近一个 <= t 的 [AUTOPLAY] 统计点。"""
    best = None
    for s in run["stats"]:
        if s["t"] <= t:
            best = s
        else:
            break
    return best


def analyze(run):
    out = {"run": run["run"], "result": run["result"]}
    # 升级时间戳：choices 行出现时刻 = 升级时刻（取该行之前最近的 HB t）
    lu_times = []
    for c in run["choices"]:
        # 用 stats 5s 粒度也行；这里用 hb 精确到秒
        best = None
        for h in run["hbs"]:
            if h <= c_t(run, c):
                best = h
            else:
                break
        lu_times.append(best)
    # 简化：choices 与 levelup 数量
    out["n_choices"] = len(run["choices"])
    out["n_levelups"] = len(run["levelups"])
    # 玩家等级时间线（stats 5s 采样）
    lv_timeline = [(s["t"], s["lv"]) for s in run["stats"]]
    out["lv_timeline"] = lv_timeline
    # 升级间隔：从 lv_timeline 提取每级首次到达时间
    first_at = {}
    for t, lv in lv_timeline:
        if lv not in first_at:
            first_at[lv] = t
    out["level_reach_time"] = {str(k): v for k, v in sorted(first_at.items())}
    # 击杀/金币节奏：每 60s 采样
    out["kill_timeline"] = [(s["t"], s["kills"], s["hp"], s["dps"]) for s in run["stats"]]
    # Boss 战：kinds 中出现的 boss id 与 hp
    bosses = {}
    for k in run["kinds"]:
        for kid, v in k.items():
            if kid.endswith("_hp") and "final_god" in kid:
                bname = kid[:-3]
                bosses.setdefault(bname, []).append(v)
            elif kid.endswith("_hp"):
                bname = kid[:-3]
                bosses.setdefault(bname, []).append(v)
    out["boss_hp_samples"] = bosses
    # Boss 战时长与有效 DPS：kinds 带 5s 采样，用 boss hp 序列推算
    fights = []
    for bname, samples in bosses.items():
        hp_nums = []
        for s in samples:
            try:
                cur, mx = s.split("/")
                hp_nums.append((int(cur), int(mx)))
            except Exception:
                pass
        if not hp_nums:
            continue
        # 用 stats 对齐时间：假定 kinds 均匀分布在 run 内不可行，改用 hp 首末样本 + run 时长近似
        start_hp = hp_nums[0][0]
        end_hp = hp_nums[-1][0]
        # 时长：用 kinds 在日志中的位置估算（每 5s 一行）
        n_samples = len(hp_nums)
        dur_est = max(n_samples - 1, 1) * 5.0
        fights.append({
            "boss": bname, "samples": n_samples, "dur_est_s": round(dur_est, 1),
            "hp_first": start_hp, "hp_last": end_hp, "hp_max": hp_nums[0][1],
            "boss_dps_est": round((start_hp - end_hp) / dur_est, 1) if dur_est > 0 else 0.0,
        })
    out["boss_fights"] = fights
    # 升级选择（流派分布）
    picks = []
    for lu in run["levelups"]:
        picks.append(lu["name"])
    out["picks"] = picks
    return out


def c_t(run, c):
    """choices 行的近似时刻：用该行在文件中的序号映射到 hb 时间。未实现精确，直接取 0。"""
    return 0.0


def main():
    all_out = []
    for n in RUNS:
        run = parse_run(n)
        all_out.append(analyze(run))
    with open(os.path.join(ROOT, ".tmp", "logs", "runs_analysis.json"), "w", encoding="utf-8") as f:
        json.dump(all_out, f, ensure_ascii=False, indent=1)
    # 摘要
    print("局次 结果    时间   击杀   金币  最终等级  Boss战(时长s/剩余血)  首达等级时间(s)")
    for a in all_out:
        r = a["result"]
        if r is None:
            continue
        boss_txt = "; ".join("%s=%d样本" % (b, len(v)) for b, v in a["boss_hp_samples"].items())
        reach = {k: v for k, v in list(a["level_reach_time"].items())[:8]}
        bf = "; ".join("%s:%.0fs/%.1fdps" % (f["boss"], f["dur_est_s"], f["boss_dps_est"]) for f in a["boss_fights"])
        print("R%-2d %-6s %5d %5d %6d  L%d  %s | %s | %s" % (
            a["run"], r["result"], r["time"], r["kills"], r["gold"], r["level"], boss_txt, reach, bf))
    wins = [a for a in all_out if a["result"] and a["result"]["result"] == "VICTORY"]
    deaths = [a for a in all_out if a["result"] and a["result"]["result"] == "DEFEAT"]
    print("\nVICTORY %d/%d（%s）" % (len(wins), len(all_out), ", ".join("R%d=%ds" % (a["run"], a["result"]["time"]) for a in wins)))
    print("DEFEAT 死亡关卡分布：%s" % {d["result"]["level"]: sum(1 for x in deaths if x["result"]["level"] == d["result"]["level"]) for d in deaths})
    return 0


if __name__ == "__main__":
    sys.exit(main())
