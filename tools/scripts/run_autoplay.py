"""Run the auto-play test with live streaming output.

Usage (escalated): python tools/scripts/run_autoplay.py [max_minutes]
"""

import subprocess
import sys
import time

GODOT = r"H:\rougelike_crew\.tools\godot\Godot_v4.7.1-stable_win64_console.exe"
PATH = r"H:\rougelike_crew"


def main():
    max_min = float(sys.argv[1]) if len(sys.argv) > 1 else 20.0
    p = subprocess.Popen(
        [GODOT, "--headless", "--fixed-fps", "60",
         "--path", PATH, "res://scenes/game/game_root.tscn", "--", "--auto-play"],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1,
        encoding="utf-8", errors="replace",
    )
    deadline = time.time() + max_min * 60
    lines = []
    while p.poll() is None and time.time() < deadline:
        line = p.stdout.readline()
        if line:
            line = line.rstrip()
            lines.append(line)
            if line.strip():
                print(line, flush=True)
    if p.poll() is None:
        p.kill()
        print("AUTOPLAY KILLED by wall-clock cap", flush=True)
    else:
        for line in p.stdout:
            line = line.rstrip()
            lines.append(line)
            if line.strip():
                print(line, flush=True)
    print("exit code:", p.returncode, flush=True)
    with open(r"H:\rougelike_crew\.tools\autoplay_full.log", "w", encoding="utf-8") as f:
        f.write("\n".join(lines))


if __name__ == "__main__":
    main()
