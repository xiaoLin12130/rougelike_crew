# -*- coding: utf-8 -*-
"""各流派通关测试统计脚本。

对每个流派跑 N 局 auto-play，记录通关/失败、用时、击杀、等级、金币、HP、
最大波次、DPS 峰值与终局构筑，输出 CSV 汇总；--report 生成 Markdown 报告。

用法:
  python tools/tests/run_school_tests.py --school fire,ice --runs 3
  python tools/tests/run_school_tests.py --school all --runs 3
  python tools/tests/run_school_tests.py --report

运行前必须设置 TEMP/TMP/APPDATA 到项目 .tmp（铁律②）。
"""

import argparse
import csv
import json
import os
import re
import subprocess
import sys
import time

PROJECT = r"H:\rougelike_crew"
GODOT = os.path.join(PROJECT, r".tools\godot\Godot_v4.7.1-stable_win64_console.exe")
CSV_PATH = os.path.join(PROJECT, r"tools\tests\school_test_results.csv")
LOG_DIR = os.path.join(PROJECT, r"tools\tests\logs")

# 铁律：只允许 console 版 Godot + --headless，绝不允许 GUI 版
if "console" not in os.path.basename(GODOT) or not os.path.exists(GODOT):
    raise SystemExit("GODOT 必须是 console 版且存在: %s" % GODOT)

GUI_GODOT_IMAGE = "Godot_v4.7.1-stable_win64.exe"  # GUI 版进程名（无 console 字样）

SCHOOLS = [
    "fire", "ice", "lightning", "poison", "water", "wind",
    "holy", "curse", "melee", "summon", "defense", "teleport",
]

CSV_FIELDS = [
    "school", "run", "result", "exit_code", "game_time_s", "wall_time_s",
    "kills", "level", "hp", "max_hp", "gold", "max_wave", "max_dps",
    "grid", "item_count", "build_items", "wands", "tainted", "log",
]


def parse_line(line):
    """从一行日志提取字段，返回 dict 或 None。"""
    m = re.search(r"RESULT=(\w+) kills=(\d+) time=(\d+) loop=(\d+) level=(\d+) plv=(\d+) hp=(\d+) maxhp=(\d+) gold=(\d+) wave=(\d+)", line)
    if m:
        return {
            "kind": "result",
            "result": m.group(1),
            "kills": int(m.group(2)),
            "time": int(m.group(3)),
            "loop": int(m.group(4)),
            "level": int(m.group(5)),
            "plv": int(m.group(6)),
            "hp": int(m.group(7)),
            "maxhp": int(m.group(8)),
            "gold": int(m.group(9)),
            "wave": int(m.group(10)),
        }
    m = re.search(r"\[AUTOPLAY\] TIMEOUT kills=(\d+) level=(\d+) hp=(\d+)", line)
    if m:
        return {
            "kind": "result",
            "result": "TIMEOUT",
            "kills": int(m.group(1)),
            "time": 1500,
            "loop": 1,
            "level": 0,
            "plv": 0,
            "hp": int(m.group(3)),
            "maxhp": 0,
            "gold": 0,
            "wave": 0,
        }
    m = re.search(r"\[BUILD\] school=(\S*) grid=\[(.*?)\] items=\[(.*?)\] wands=(.*)", line)
    if m:
        return {
            "kind": "build",
            "school": m.group(1),
            "grid": m.group(2),
            "items": m.group(3),
            "wands": m.group(4),
        }
    m = re.search(r"\[AUTOPLAY\] t=\d+ hp=\d+ lv=\d+ kills=\d+ enemies=\d+ dps=(\d+) grid=\d+ items=\d+ wave=(\d+)", line)
    if m:
        return {"kind": "report", "dps": int(m.group(1)), "wave": int(m.group(2))}
    return None


def run_one(school, run_idx, max_minutes):
    """跑一局，返回统计 dict。"""
    # 铁律⑥：跑测试前清理残留 GUI 版 Godot（防止“内存不能为read”弹窗）
    subprocess.run(
        ["taskkill", "/IM", GUI_GODOT_IMAGE, "/F"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    os.makedirs(LOG_DIR, exist_ok=True)
    log_path = os.path.join(LOG_DIR, "%s_%02d.log" % (school, run_idx))
    env = dict(os.environ)
    env["TEMP"] = os.path.join(PROJECT, ".tmp")
    env["TMP"] = os.path.join(PROJECT, ".tmp")
    env["APPDATA"] = os.path.join(PROJECT, ".tmp", "appdata")
    cmd = [
        GODOT, "--headless", "--fixed-fps", "60", "--path", PROJECT,
        "res://scenes/game/game_root.tscn", "--", "--auto-play",
        "--school", school,
    ]
    wall_start = time.time()
    p = subprocess.Popen(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, encoding="utf-8", errors="replace", env=env,
        bufsize=1,
    )
    stat = {
        "school": school, "run": run_idx, "result": "UNKNOWN", "exit_code": None,
        "game_time_s": None, "wall_time_s": None, "kills": None, "level": None,
        "hp": None, "max_hp": None, "gold": None, "max_wave": 0, "max_dps": 0,
        "grid": "", "item_count": 0, "build_items": "", "wands": "",
        "tainted": "0", "log": log_path,
    }
    last_t = 0.0
    last_kills = -1
    last_enemies = -1
    with open(log_path, "w", encoding="utf-8") as f:
        deadline = wall_start + max_minutes * 60
        while True:
            if p.poll() is not None:
                break
            if time.time() > deadline:
                p.kill()
                stat["result"] = "TIMEOUT"
                break
            try:
                line = p.stdout.readline()
            except Exception:
                break
            if not line:
                if p.poll() is not None:
                    break
                time.sleep(0.05)
                continue
            line = line.rstrip()
            f.write(line + "\n")
            f.flush()
            if "Parse Error" in line or "Failed to load script" in line:
                stat["tainted"] = "1"
            info = parse_line(line)
            if info:
                if info["kind"] == "result":
                    stat["result"] = info["result"]
                    stat["game_time_s"] = info["time"]
                    stat["kills"] = info["kills"]
                    stat["level"] = info["plv"]
                    stat["hp"] = info["hp"]
                    stat["max_hp"] = info["maxhp"]
                    stat["gold"] = info["gold"]
                    stat["max_wave"] = max(stat["max_wave"], info["wave"])
                elif info["kind"] == "build":
                    stat["grid"] = info["grid"]
                    stat["build_items"] = info["items"]
                    stat["wands"] = info["wands"]
                    stat["item_count"] = len([x for x in info["items"].split(",") if x.strip()])
                else:
                    stat["max_dps"] = max(stat["max_dps"], info["dps"])
                    stat["max_wave"] = max(stat["max_wave"], info["wave"])
                    m = re.search(r"\[AUTOPLAY\] t=(\d+) hp=\d+ lv=\d+ kills=(\d+) enemies=(\d+)", line)
                    if m:
                        cur_t = float(m.group(1))
                        cur_kills = int(m.group(2))
                        cur_enemies = int(m.group(3))
                        # 卡死检测：无敌人且击杀长时间不增长 → 游戏卡在空关卡
                        if last_kills >= 0 and cur_enemies == 0 and last_enemies == 0 \
                                and cur_kills == last_kills and cur_t - last_t >= 60.0:
                            p.kill()
                            stat["result"] = "STUCK"
                            f.write("[RUNNER] killed: stuck with 0 enemies, kills frozen\n")
                            break
                        last_t = cur_t
                        last_kills = cur_kills
                        last_enemies = cur_enemies
        for line in p.stdout:
            line = line.rstrip()
            f.write(line + "\n")
            if "Parse Error" in line or "Failed to load script" in line:
                stat["tainted"] = "1"
            info = parse_line(line)
            if info:
                if info["kind"] == "result":
                    stat["result"] = info["result"]
                    stat["game_time_s"] = info["time"]
                    stat["kills"] = info["kills"]
                    stat["level"] = info["plv"]
                    stat["hp"] = info["hp"]
                    stat["max_hp"] = info["maxhp"]
                    stat["gold"] = info["gold"]
                    stat["max_wave"] = max(stat["max_wave"], info["wave"])
                elif info["kind"] == "build":
                    stat["grid"] = info["grid"]
                    stat["build_items"] = info["items"]
                    stat["wands"] = info["wands"]
                    stat["item_count"] = len([x for x in info["items"].split(",") if x.strip()])
                else:
                    stat["max_dps"] = max(stat["max_dps"], info["dps"])
                    stat["max_wave"] = max(stat["max_wave"], info["wave"])
        p.wait(timeout=5)
    stat["wall_time_s"] = int(time.time() - wall_start)
    stat["exit_code"] = p.returncode
    if stat["result"] in ("STUCK", "TIMEOUT"):
        pass
    elif stat["result"] == "UNKNOWN":
        stat["result"] = "CRASH" if p.returncode not in (0, 1, 2) else ("VICTORY" if p.returncode == 0 else ("DEFEAT" if p.returncode == 1 else "TIMEOUT"))
    return stat


def load_items_tags():
    """items.json: id -> tags 列表，用于构筑组成统计。"""
    with open(os.path.join(PROJECT, "data", "items.json"), encoding="utf-8") as f:
        data = json.load(f)
    out = {}
    for it in data.get("items", []):
        out[str(it.get("id", ""))] = [str(t) for t in it.get("tags", [])]
    return out


def existing_max_run():
    """CSV 中每流派已有的最大 run 号，用于断点续跑。"""
    out = {}
    if not os.path.exists(CSV_PATH):
        return out
    with open(CSV_PATH, encoding="utf-8-sig") as f:
        for r in csv.DictReader(f):
            if r.get("result") not in ("VICTORY", "DEFEAT", "TIMEOUT"):
                continue
            try:
                n = int(r.get("run", 0))
            except (TypeError, ValueError):
                continue
            out[r["school"]] = max(out.get(r["school"], 0), n)
    return out


def main():
    ap = argparse.ArgumentParser(description="各流派自动通关测试统计")
    ap.add_argument("--school", default="", help="流派列表，逗号分隔，或 all")
    ap.add_argument("--runs", type=int, default=1, help="每流派局数")
    ap.add_argument("--max-minutes", type=float, default=25.0, help="单局墙钟上限(分钟)")
    ap.add_argument("--csv", default="", help="CSV 输出路径（默认 tools/tests/school_test_results.csv），多实例并行时用 --csv 隔离")
    ap.add_argument("--report", action="store_true", help="只生成 Markdown 报告")
    args = ap.parse_args()

    global CSV_PATH
    if args.csv:
        CSV_PATH = os.path.abspath(args.csv)
        d = os.path.dirname(CSV_PATH)
        if d:
            os.makedirs(d, exist_ok=True)

    if args.report:
        from gen_school_report import main as gen
        gen()
        return

    if args.school == "all":
        schools = SCHOOLS
    elif args.school:
        schools = [s.strip().lower() for s in args.school.split(",") if s.strip()]
    else:
        schools = SCHOOLS

    header_exists = os.path.exists(CSV_PATH) and os.path.getsize(CSV_PATH) > 0
    max_run = existing_max_run()
    rows = []
    with open(CSV_PATH, "a", newline="", encoding="utf-8-sig") as f:
        writer = csv.DictWriter(f, fieldnames=CSV_FIELDS)
        if not header_exists:
            writer.writeheader()
        for school in schools:
            start = max_run.get(school, 0) + 1
            if start > args.runs:
                print("== %s already has %d runs, skip" % (school, args.runs), flush=True)
                continue
            for i in range(start, args.runs + 1):
                print("== run %s #%d start" % (school, i), flush=True)
                stat = run_one(school, i, args.max_minutes)
                writer.writerow({k: stat.get(k, "") for k in CSV_FIELDS})
                f.flush()
                rows.append(stat)
                print("== %s #%d -> %s game=%ss wall=%ss kills=%s lv=%s hp=%s gold=%s wave=%s dps=%s items=%d" % (
                    school, i, stat["result"], stat["game_time_s"], stat["wall_time_s"],
                    stat["kills"], stat["level"], stat["hp"], stat["gold"],
                    stat["max_wave"], stat["max_dps"], stat["item_count"]), flush=True)

    wins = sum(1 for r in rows if r["result"] == "VICTORY")
    print("batch done: %d runs, %d victories" % (len(rows), wins), flush=True)


if __name__ == "__main__":
    main()
