# -*- coding: utf-8 -*-
"""地面效果视觉 smoke 检查（Windows / PowerShell 环境）。

依次执行两项验收命令并核对输出标记：
  1) test_ground_fx.tscn            -> 期待 "GROUND_FX ALL PASS"
  2) smoke_test.gd（-s 模式）        -> 期待 "SMOKE OK"

运行前置要求（与项目铁律一致）：
  - 只用 .tools/godot/Godot_v4.7.1-stable_win64_console.exe + --headless；
  - TEMP/TMP 重定向到项目 .tmp，APPDATA 重定向到 .tmp\\appdata；
  - 结束后清理残留 Godot 进程。
"""

import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GODOT = ROOT / ".tools" / "godot" / "Godot_v4.7.1-stable_win64_console.exe"
TMP = ROOT / ".tmp"
APPDATA = TMP / "appdata"


def run_godot(args, tag):
    env = os.environ.copy()
    env["TEMP"] = str(TMP)
    env["TMP"] = str(TMP)
    env["APPDATA"] = str(APPDATA)
    TMP.mkdir(parents=True, exist_ok=True)
    APPDATA.mkdir(parents=True, exist_ok=True)
    cmd = [str(GODOT), "--headless", "--path", str(ROOT)] + args
    proc = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8",
                          errors="replace", cwd=str(ROOT), env=env, timeout=240)
    out = (proc.stdout or "") + (proc.stderr or "")
    print("[%s] exit=%d" % (tag, proc.returncode))
    return proc.returncode, out


def kill_godot():
    """清理残留 Godot 进程（控制台包装 + 引擎子进程）。"""
    ps = ("powershell -NoProfile -Command "
          "\"Get-Process | Where-Object { $_.ProcessName -like '*Godot*' } "
          "| Stop-Process -Force -ErrorAction SilentlyContinue\"")
    subprocess.run(ps, shell=True, capture_output=True, timeout=60)


def main():
    results = []
    rc1, out1 = run_godot(["res://scripts/tests/test_ground_fx.tscn"], "ground_fx")
    results.append(("GROUND_FX ALL PASS" in out1, rc1 == 0, "test_ground_fx"))
    kill_godot()
    rc2, out2 = run_godot(["-s", "res://scripts/tests/smoke_test.gd"], "smoke")
    results.append(("SMOKE OK" in out2, rc2 == 0, "smoke_test"))
    kill_godot()

    ok = True
    for passed, rc_ok, name in results:
        status = "PASS" if passed and rc_ok else "FAIL"
        if status == "FAIL":
            ok = False
        print("  [%s] %s" % (status, name))
    print("GROUND FX CHECK: %s" % ("ALL PASS" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
