# -*- coding: utf-8 -*-
"""在 work/status.json 的 tasks 中字节级插入 round2_test 条目（保留文件其余字节不变）。"""

import io
import os
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

p = os.path.join(os.path.dirname(os.path.abspath(__file__)), "status.json")
raw = open(p, "rb").read()

marker = b'"tasks": {'
assert marker in raw, "marker not found"

entry = (
    '\n  "round2_test": {\n'
    '   "status": "done",\n'
    '   "note": "2026-08-10 第2轮导出版复测：通关率 4/5=80%（第1轮27%）；P0直击修复验证通过；'
    'R1召唤光环freed-instance崩溃(必胜局丢失,P0待修)；R6并行编辑干扰超时；'
    '回归:smoke/lightning/core_shell全绿,ground_fx导出树全绿(当前树毒雾用例漂移)；'
    '报告 docs/reports/全流程体验报告-第2轮.md"\n'
    '  },\n'
).encode("utf-8")

raw = raw.replace(marker, marker + entry, 1)
with open(p, "wb") as f:
    f.write(raw)
print("status.json updated:", os.path.getsize(p), "bytes")
