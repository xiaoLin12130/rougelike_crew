"""Run the standing-pressure probe headless with a wall-clock cap.

Usage:
    python tools/tests/run_standing_probe.py noattack|turret
"""

import os
import subprocess
import sys
import time

GODOT = r"H:\rougelike_crew\.tools\godot\Godot_v4.7.1-stable_win64_console.exe"
PATH = r"H:\rougelike_crew"


def main() -> int:
    mode = sys.argv[1] if len(sys.argv) > 1 else "noattack"
    env = dict(os.environ)
    env["TEMP"] = r"H:\rougelike_crew\.tmp"
    env["TMP"] = r"H:\rougelike_crew\.tmp"
    env["APPDATA"] = r"H:\rougelike_crew\.tmp\appdata"
    log_path = r"H:\rougelike_crew\.tmp\logs\standing_probe_%s.log" % mode
    with open(log_path, "w", encoding="utf-8", errors="replace") as log:
        p = subprocess.Popen(
            [GODOT, "--headless", "--fixed-fps", "60",
             "--path", PATH, "res://tools/tests/standing_pressure_probe.tscn", "--", "--mode=" + mode],
            stdout=log, stderr=subprocess.STDOUT, env=env,
        )
        deadline = time.time() + 120.0
        while p.poll() is None and time.time() < deadline:
            time.sleep(0.5)
    if p.poll() is None:
        subprocess.run(["taskkill", "/PID", str(p.pid), "/T", "/F"],
                       capture_output=True, check=False)
        print("PROBE KILLED by wall-clock cap", flush=True)
    print("exit code:", p.returncode, flush=True)
    with open(log_path, encoding="utf-8", errors="replace") as f:
        text = f.read()
    print(text, flush=True)
    return p.returncode


if __name__ == "__main__":
    sys.exit(main())
