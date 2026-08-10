# -*- coding: utf-8 -*-
"""第 2 轮 autoplay 日志解析：5 个有效局 + 2 个异常局。

输入：.tmp/logs/autoplay_r2_run{1..7}.log
输出：.tmp/logs/runs_analysis_r2.json + 控制台摘要
"""

import io
import json
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

RUNS = []
for i in range(1, 8):
    p = os.path.join(ROOT, ".tmp", "logs", "autoplay_r2_run%d.log" % i)
    if os.path.exists(p):
        RUNS.append(i)

HB_RE = re.compile(r"\[HB\] t=([\d.]+)")
STAT_RE = re.compile(r"\[AUTOPLAY\] t=(\d+) hp=(\d+) lv=(\d+) kills=(\d+) enemies=(\d+) dps=(\d+) grid=(\d+) items=(\d+)")
KINDS_RE = re.compile(r"\[KINDS\] (.*)")
CHOICES_RE = re.compile(r"\[AUTOPLAY\] choices: (.*)")
LEVELUP_RE = re.compile(r"\[AUTOPLAY\] levelup -> (.*?) score=(\d+)")
RESULT_RE = re.compile(r"\[AUTOPLAY\] RESULT=(\w+) kills=(\d+) time=(\d+) loop=(\d+) level=(\d+) hp=(\d+) gold=(\d+)")
TIMEOUT_RE = re.compile(r"\[AUTOPLAY\] TIMEOUT kills=(\d+) level=(\d+)")
WAND_RE = re.compile(r"\[AUTOPLAY\] wand shop handled")
ERR_RE = re.compile(r"SCRIPT ERROR: (.*)")
FRMT_RE = re.compile(r"String formatting error")


def decode(path):
    raw = open(path, "rb").read()
    if raw[:2] == b"\xff\xfe":
        return raw.decode("utf-16-le", errors="replace")
    return raw.decode("utf-8", errors="replace")


def parse_run(n):
    lines = [l.strip(" \x00") for l in decode(os.path.join(ROOT, ".tmp", "logs", "autoplay_r2_run%d.log" % n)).split("\n")
             if l.strip(" \x00")]
    run = {"run": n, "hbs": [], "stats": [], "choices": [], "levelups": [], "kinds": [],
           "result": None, "timeout": None, "wand_shops": [], "script_errors": [], "fmt_errors": 0}
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
        m = TIMEOUT_RE.search(l)
        if m:
            run["timeout"] = {"kills": int(m.group(1)), "level": int(m.group(2))}
            continue
        if WAND_RE.search(l):
            run["wand_shops"].append(True)
            continue
        m = ERR_RE.search(l)
        if m:
            run["script_errors"].append(m.group(1).strip())
            continue
        if FRMT_RE.search(l):
            run["fmt_errors"] += 1
    return run


def analyze(run):
    out = {"run": run["run"], "result": run["result"], "timeout": run["timeout"]}
    out["n_choices"] = len(run["choices"])
    out["n_levelups"] = len(run["levelups"])
    lv_timeline = [(s["t"], s["lv"]) for s in run["stats"]]
    out["lv_timeline"] = lv_timeline
    first_at = {}
    for t, lv in lv_timeline:
        if lv not in first_at:
            first_at[lv] = t
    out["level_reach_time"] = {str(k): v for k, v in sorted(first_at.items())}
    out["kill_timeline"] = [(s["t"], s["kills"], s["hp"], s["dps"]) for s in run["stats"]]
    # Boss 战：kinds 中的 boss hp 采样（每 5s 一行）→ 时长/有效 DPS 估算
    bosses = {}
    for k in run["kinds"]:
        for kid, v in k.items():
            if kid.endswith("_hp"):
                bosses.setdefault(kid[:-3], []).append(v)
    out["boss_hp_samples"] = bosses
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
        n_samples = len(hp_nums)
        dur_est = max(n_samples - 1, 1) * 5.0
        fights.append({
            "boss": bname, "samples": n_samples, "dur_est_s": round(dur_est, 1),
            "hp_first": hp_nums[0][0], "hp_last": hp_nums[-1][0], "hp_max": hp_nums[0][1],
            "boss_dps_est": round((hp_nums[0][0] - hp_nums[-1][0]) / dur_est, 1) if dur_est > 0 else 0.0,
        })
    out["boss_fights"] = fights
    picks = [lu["name"] for lu in run["levelups"]]
    out["picks"] = picks
    # 错误统计
    err_counts = {}
    for e in run["script_errors"]:
        key = e.split(".")[0][:80]
        err_counts[key] = err_counts.get(key, 0) + 1
    out["script_error_top"] = sorted(err_counts.items(), key=lambda x: -x[1])[:5]
    out["fmt_errors"] = run["fmt_errors"]
    return out


def main():
    all_out = []
    for n in RUNS:
        run = parse_run(n)
        all_out.append(analyze(run))
    with open(os.path.join(ROOT, ".tmp", "logs", "runs_analysis_r2.json"), "w", encoding="utf-8") as f:
        json.dump(all_out, f, ensure_ascii=False, indent=1)
    print("局次 结果      时间   击杀   金币  等级  Boss战(时长s/首末hp/估算dps)         首达等级时间")
    for a in all_out:
        r = a["result"]
        tag = "CRASH" if (r is None and a["timeout"] is None) else ("TIMEOUT" if a["timeout"] else r["result"])
        time_txt = r["time"] if r is not None else "-"
        kills_txt = r["kills"] if r is not None else "-"
        gold_txt = r["gold"] if r is not None else "-"
        lv_txt = r["level"] if r is not None else "-"
        bf = "; ".join("%s:%.0fs hp%d->%d dps%.1f" % (f["boss"], f["dur_est_s"], f["hp_first"], f["hp_last"], f["boss_dps_est"]) for f in a["boss_fights"])
        reach = {k: v for k, v in list(a["level_reach_time"].items())[:6]}
        errs = "; ".join("%s x%d" % (k, v) for k, v in a["script_error_top"])
        print("R%-2d %-7s %5s %5s %6s  L%s  %s | %s | %s" % (a["run"], tag, time_txt, kills_txt, gold_txt, lv_txt, bf, reach, errs))
    wins = [a for a in all_out if a["result"] and a["result"]["result"] == "VICTORY"]
    deaths = [a for a in all_out if a["result"] and a["result"]["result"] == "DEFEAT"]
    print("\nVICTORY %d/%d（%s）" % (len(wins), len([a for a in all_out if a["result"]]),
          ", ".join("R%d=%ds" % (a["run"], a["result"]["time"]) for a in wins)))
    print("DEFEAT: %s" % {d["run"]: d["result"] for d in deaths})
    return 0


if __name__ == "__main__":
    sys.exit(main())
