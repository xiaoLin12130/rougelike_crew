# -*- coding: utf-8 -*-
"""A2 流派成型反馈实现记录：追加设计文档实现记录 + 更新 work/status.json。"""
import glob
import json
import io

ROOT = r"H:\rougelike_crew"

RECORD = """
## A2. 实现落地：2026-08-10 子代理（流派成型反馈）执行，已完成

### A2.1 成型档位反馈（3/6/9）

- `GameState.school_holdings()`：按 items.json 的 tags 统计 12 流派持有层数
  （fire/ice/lightning/poison/summon/water/wind/blade/defense/curse/crit/speed），
  道具堆叠层数 + 法术网格核心元素各计 1；阈值 3/6/9 由消费方判定（HUD/FX），
  GameState 只提供计数，不改 game_root。
- `GameState.schools_of_item()`：道具归属流派（tags 命中流派表；spell_part 按核心元素解析）。
- `hud.gd` 成型横幅：顶部居中小横幅（y=48），弹出 + 停留 2s 渐隐；
  每档位（school+tier）只触发一次，`_formed_tiers` 记录，重复刷新不重触发。

### A2.2 联动标签

- `levelup_overlay.show_choices`：卡片流派已持有>=1 件（本件为第 2+ 件）时显示
  "联动已激活：火/毒…" 小字（绿色）。
- `build_panel` 道具格：第 2+ 件同流派（持有>=2）显示金色"联动"角标，
  详情弹窗与 tooltip 附流派说明。

### A2.3 机制视觉强化

- 毒爆（fx_explosion kind=poison）：主环后延迟第二圈扩散环 + 外圈毒沫粒子，
  档位（3/6/9 件）越高环越大、毒沫越多。
- 碎冰（kind=ice）：短时多粒子冰屑向四周迸射（高初速+重力下落），
  >=6 件追加一簇冰晶。
- 电弧（kind=lightning）：屏幕微震强度随雷流派持有件数提升（3.0 + 1.2/件 起）。
- 召唤物光环：fx_manager 按召唤流派持有件数渲染召唤物脚下光环
  （3/6/9 = 1/2/3 圈，半径/亮度递增、反向旋转），召唤物消失即释放；
  召唤物分组名为 `summons`（summon.gd 注册），不改 summon.gd。

### A2.4 校验

- `scripts/tests/test_form_tiers.gd`：1 件无横幅 / 3/6/9 各档触发一次不重复 /
  卡片联动标签（含 spell_part 解析）/ 构建面板角标 → ALL PASS
- `smoke_test.gd` → SMOKE OK（全部脚本编译通过）
- `hud_layout_test.gd` → 与基线一致（仅"资源条压缩"一项为基线既有失败，
  与本次改动无关；本次改动未引入新布局断言失败）
"""


def main() -> None:
    # 1. 设计文档追加实现记录
    doc_paths = glob.glob(ROOT + r"\docs\design\流派联动强化与法杖扩充方案.md")
    if not doc_paths:
        raise SystemExit("design doc not found")
    doc = doc_paths[0]
    with io.open(doc, "r", encoding="utf-8", newline="") as f:
        text = f.read()
    if "A2. 实现落地" not in text:
        text = text.rstrip("\r\n") + "\n" + RECORD
        with io.open(doc, "w", encoding="utf-8", newline="") as f:
            f.write(text)
        print("doc updated:", doc)
    else:
        print("doc already has A2 record, skip")

    # 2. status.json 更新
    status_path = ROOT + r"\work\status.json"
    with io.open(status_path, "r", encoding="utf-8") as f:
        status = json.load(f)
    status["updated"] = "2026-08-10-form-tiers"
    status["tasks"]["form_tiers"] = {
        "status": "done",
        "note": (
            "A2流派成型反馈三件套完成：①GameState.school_holdings()/schools_of_item()"
            "流派计数(12流派tag+法术核心)；②hud成型横幅3/6/9每档一次(顶部居中2s渐隐)；"
            "③levelup_overlay/build_panel联动标签(第2+件,含spell_part解析)；"
            "④fx_manager毒爆扩散波/碎冰冰屑/电弧震屏(强度随件数)/召唤物光环3/6/9；"
            "⑤test_form_tiers.gd ALL PASS + smoke OK；hud_layout仅基线既有资源条断言失败"
        ),
    }
    with io.open(status_path, "w", encoding="utf-8", newline="") as f:
        json.dump(status, f, ensure_ascii=False, indent=1)
        f.write("\n")
    print("status updated:", status_path)


if __name__ == "__main__":
    main()
