# -*- coding: utf-8 -*-
"""第 3 轮 autoplay 日志解析：6 局（5 常规 + 1 召唤流定向构筑）。

输入：.tmp/logs/autoplay_r3_run{1..6}.log
输出：.tmp/logs/runs_analysis_r3.json + 控制台摘要
"""

import io
import json
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

RUNS = []
for i in range(1, 7):
    p = os.path.join(ROOT, ".tmp", "logs", "autoplay_r3_run%d.log" % i)
    if os.path.exists(p):
        RUNS.append(i)

HB_RE = re.compile(r"\[HB\] t=([\d.]+)")
STAT_RE = re.compile(r"\[AUTOPLAY\] t=(\d+) hp=(\d+) lv=(\d+) kills=(\d+) enemies=(\d+) dps=(\d+) grid=(\d+) items=(\d+)")
KINDS_RE = re.compile(r"\[KINDS\] (.*)")
CHOICES_RE = re.compile(r"\[AUTOPLAY\] choices: (.*)")
LEVELUP_RE = re.compile(r"\[AUTOPLAY\] levelup -> (.*?) score=(\d+)")
RESULT_RE = re.compile(r"\[AUTOPLAY\] RESULT=(\w+) kills=(\d+) time=(\d+) loop=(\d+) level=(\d+) hp=(\d+) gold=(\d+)")
TIMEOUT_RE = re.compile(r"\[AUTOPLAY\] TIMEOUT kills=(\d+) level=(\d+)")
SHOP_RE = re.compile(r"\[AUTOPLAY\] wand shop handled")
SPAWN_RE = re.compile(r"\[SPAWNER\] setup at run\.time=([\d.]+)")


def decode(path):
    raw = open(path, "rb").read()
    if raw[:2] == b"\xff\xfe":
        return raw.decode("utf-16-le", errors="replace")
    return raw.decode("utf-8", errors="replace")


def parse_run(n):
    lines = [l.strip(" \x00") for l in decode(os.path.join(ROOT, ".tmp", "logs", "autoplay_r3_run%d.log" % n)).split("\n")
             if l.strip(" \x00")]
    run = {"run": n, "hbs": [], "stats": [], "choices": [], "levelups": [], "kinds": [],
           "result": None, "timeout": None, "shops": [], "spawners": []}
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
        if SHOP_RE.search(l):
            run["shops"].append(True)
            continue
        m = SPAWN_RE.search(l)
        if m:
            run["spawners"].append(float(m.group(1)))
    return run


def analyze(run):
    out = {"run": run["run"], "result": run["result"], "timeout": run["timeout"],
           "n_choices": len(run["choices"]), "n_levelups": len(run["levelups"]),
           "n_shops": len(run["shops"]), "level_transitions": len(run["spawners"]) - 1}
    first_at = {}
    for s in run["stats"]:
        lv = int(s["lv"])
        if lv not in first_at:
            first_at[lv] = s["t"]
    out["level_reach_time"] = {str(k): v for k, v in sorted(first_at.items())}
    # Boss 战：kinds 中的 boss hp 采样
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
    out["picks"] = [lu["name"] for lu in run["levelups"]]
    return out


def main():
    all_out = []
    for n in RUNS:
        run = parse_run(n)
        all_out.append(analyze(run))
    with open(os.path.join(ROOT, ".tmp", "logs", "runs_analysis_r3.json"), "w", encoding="utf-8") as f:
        json.dump(all_out, f, ensure_ascii=False, indent=1)
    print("局次 结果      时间   击杀   金币   等级  Boss战(时长s/首末hp/估算dps)            升级数/商店")
    for a in all_out:
        r = a["result"]
        tag = "CRASH" if (r is None and a["timeout"] is None) else ("TIMEOUT" if a["timeout"] else r["result"])
        time_txt = r["time"] if r else "-"
        kills_txt = r["kills"] if r else "-"
        gold_txt = r["gold"] if r else "-"
        lv_txt = r["level"] if r else "-"
        bf = "; ".join("%s:%.0fs hp%d->%d dps%.1f" % (f["boss"], f["dur_est_s"], f["hp_first"], f["hp_last"], f["boss_dps_est"]) for f in a["boss_fights"])
        print("R%-2d %-7s %5s %5s %6s  L%s  %s | lu=%d shop=%d trans=%d" % (
            a["run"], tag, time_txt, kills_txt, gold_txt, lv_txt, bf,
            a["n_levelups"], a["n_shops"], a["level_transitions"]))
    wins = [a for a in all_out if a["result"] and a["result"]["result"] == "VICTORY"]
    deaths = [a for a in all_out if a["result"] and a["result"]["result"] == "DEFEAT"]
    print("\nVICTORY %d/%d（%s）" % (len(wins), len([a for a in all_out if a["result"]]),
          ", ".join("R%d=%ds" % (a["run"], a["result"]["time"]) for a in wins)))
    print("DEFEAT: %s" % {d["run"]: d["result"] for d in deaths})
    return 0


if __name__ == "__main__":
    sys.exit(main())
