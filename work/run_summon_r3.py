# -*- coding: utf-8 -*-
"""第 3 轮召唤流定向构筑局：用 .tmp/summon_force.tscn 启动 headless Godot。

强制 GameState.run = summon_bat 核心 x2 + summon_m1/summon_1/summon_book 道具，
验证 P0 召唤光环 freed-instance 崩溃修复在真实长战（全流程自动通关）中不再复现。
日志：.tmp/logs/autoplay_r3_run6.log + .tools/autoplay_full_summon.log
"""

import io
import os
import subprocess
import sys
import time

ROOT = r"H:\rougelike_crew"
GODOT = os.path.join(ROOT, ".tools", "godot", "Godot_v4.7.1-stable_win64_console.exe")
SCENE = os.path.join(ROOT, ".tmp", "summon_force.tscn")
OUT = os.path.join(ROOT, ".tmp", "logs", "autoplay_r3_run6.log")
OUT2 = os.path.join(ROOT, ".tools", "autoplay_full_summon.log")

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")


def main() -> int:
    max_min = float(sys.argv[1]) if len(sys.argv) > 1 else 30.0
    max_sec = max_min * 60.0
    env = dict(os.environ)
    env["TEMP"] = os.path.join(ROOT, ".tmp")
    env["TMP"] = os.path.join(ROOT, ".tmp")
    env["APPDATA"] = os.path.join(ROOT, ".tmp", "appdata")
    p = subprocess.Popen(
        [GODOT, "--headless", "--fixed-fps", "60",
         "--path", ROOT, SCENE, "--", "--auto-play"],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1,
        encoding="utf-8", errors="replace", env=env,
    )
    deadline = time.time() + max_min * 60
    lines = []
    while p.poll() is None and time.time() < deadline:
        line = p.stdout.readline()
        if line:
            line = line.rstrip()
            lines.append(line)
            if any(k in line for k in ("[SUMMON]", "[AUTOPLAY]", "RESULT",
                                       "ERROR", "SCRIPT ERROR", "TIMEOUT")):
                sys.stdout.write(line + "\n")
                sys.stdout.flush()
    if p.poll() is None:
        # console exe 是包装器，只杀它会留下 GUI 子进程并持有管道；
        # 必须按进程树整树终止（taskkill /T）。
        subprocess.run(["taskkill", "/PID", str(p.pid), "/T", "/F"],
                       capture_output=True)
        try:
            for line in p.stdout:
                lines.append(line.rstrip())
        except Exception:
            pass
        sys.stdout.write("SUMMON RUN KILLED by wall-clock cap\n")
        sys.stdout.flush()
    else:
        for line in p.stdout:
            line = line.rstrip()
            lines.append(line)
    print("exit code:", p.returncode, flush=True)
    with open(OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    with open(OUT2, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main())
