# -*- coding: utf-8 -*-
"""雷系连锁视觉任务交付：更新 work/status.json 并生成中文交付报告（docs/design/lightning_fx_visual.md）。
规则要求中文文档用 Python 脚本文件生成，本脚本即载体；以 UTF-8 读写，避免控制台编码问题。"""
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

REPORT = """# 雷系连锁视觉交付报告（lightning_fx_visual）

## 背景
用户反馈「雷系连锁完全看不出效果」。本任务为雷系链跳（projectile._try_chain 的 chain 逻辑 + thunder_synergy
的雷云/落雷/电弧）补齐清晰视觉：链跳闪电连线、麻痹蓝白闪烁 + 定身图标、落雷闪电柱 + 地面电弧溅射，并确认
屏幕微震接线有效。所有视觉均为程序化绘制（折线/粒子/Tween），不引入静态贴图冒充动态效果，视觉节点不参与碰撞；
机制数值（伤害/链跳距离/麻痹时长等）零改动。

## 一、链跳闪电连线（LightningBolt）
- 渲染：fx_manager.gd 内嵌 LightningBolt（Node2D + 程序化 _draw）。起点→终点之间 3~5 段随机抖动折线，
  抖动幅度按距离自适应（clamp(距离×7%, 5~16px)）。
- 配色/辉光：主色淡蓝白 Color(0.6, 0.8, 1.0)，双层绘制——5px 半透明粗 glow 层 + 2px 白色细亮芯层，
  两端绘制电光圆点；前段约 70Hz 高频闪烁模拟电流，尾段 0.08s 渐隐。
- 生命周期：0.22s 后 queue_free（验收要求 0.15~0.3s 渐隐、0.5s 内自毁）。
- 性能：fx_manager 统一限量，同时最多 12 条（CHAIN_BOLT_MAX），满额降频跳过；池内失效引用自动清理。
- 挂接点：projectile._try_chain 每跳调用 _emit_chain_bolt(from, to)（仅触发视觉信号/节点，伤害逻辑不动）；
  thunder_synergy._chain_burst（雷M3 静电满充能 / 雷M5 导雷 / 雷M10 高压电网死亡连锁）每跳同样绘制连线。

## 二、麻痹反馈（蓝白闪烁 + 定身图标）
- 机制不动：thunder_synergy._apply_paralysis 仍只写 enemy._root_left（定身判定原逻辑）。
- 视觉标记：_apply_paralysis 额外写 enemy._paralyze_left（纯视觉字段，enemy 侧只加不动逻辑，随 _tick 递减）。
- 蓝白闪烁：enemy._apply_status_visual 新增 paralyze 分支——0.5s 周期亮白 ↔ 淡蓝脉动
  （modulate 蓝分量 1.30~1.35 恒高于红分量 0.62~1.17）。
- 定身图标：复用 _status_attach_root 体系，_build_status_attach 新增 "paralyze" 分支，
  头顶生成程序化定身图标（3 颗四角星折线三角排布 + 竖标，Line2D 无贴图），带摆动/呼吸动画；
  蓝白电花粒子（fx_manager STATUS_ATTACH_RECIPES 新增 "paralyze" 配方）。
- 附着优先级：冻结 > 麻痹 > 燃烧 > 中毒 > 雷电 > 水 > 减速（新增麻痹分支，不动既有分支）。

## 三、落雷 / 雷云视觉强化（闪电柱 + 地面电弧溅射）
- thunder_synergy._strike（雷M2 雷暴 / 雷M8 超载线圈 / 雷M9 雷云风暴 / 雷M10 高压电网 / N2 雷云）统一经
  _fx_lightning 触发；在原有雷云闪电（云团蓄能 + 分叉折线 + 冲击粒子）之上，新增 spawn_strike_arcs：
  - 竖直闪电柱：86px 双层柱（11px 半透明粗 glow + 3.4px 白色亮芯），轻微抖动保持柱状；
  - 底部地面电弧溅射：4~6 条短折线沿地面辐射（20~42px），同 _bolt_fade 闪烁淡出；
  - 落地闪光（light_03 贴图粒子，加法混合）。
- 雷云风暴/雷云（雷M9/N2）落点额外生成短时电弧闪烁雷区（spawn_ground_fx，程序化折线多边形，0.55s 自毁）。

## 四、屏幕微震（确认接线有效）
- 既有链路已生效：fx_manager._play_explosion 对 lightning 爆炸触发 SHAKE_SMALL + 1.2×闪电流派持有件数；
  thunder_synergy._tick_storm 雷M9 落雷前 emit screen_shake(3.0)；fx_manager._on_screen_shake 转发
  camera.shake(power)。本任务未改动，测试场景无 camera 时静默跳过。

## 测试结果（headless，均通过）
| 测试 | 命令 | 结果 |
| --- | --- | --- |
| 雷系视觉 | godot --headless --path . res://scripts/tests/test_lightning_fx.tscn | [TEST] LIGHTNING FX ALL PASS |
| 冒烟 | godot --headless --path . -s res://scripts/tests/smoke_test.gd | SMOKE OK |
| 核心机制回归 | godot --headless --path . res://scripts/tests/test_core_mechanics.tscn | [TEST] CORE MECHANICS OK |

test_lightning_fx.gd 断言：① chain=3 弹道链跳产生 3 条 LightningBolt，0.5s 内全部自毁且连线池清空；
② thunder_synergy._chain_burst 3 跳产生 3 条连线并自毁；③ 麻痹敌人 _root_left/_paralyze_left 写入、
附着切换为 paralyze、定身图标存在、sprite 蓝白闪烁且随时间变化（蓝分量高于红分量）；
④ _strike 落雷产生 ≥5 个闪电柱/溅射视觉节点且 ~2.3s 内全部自毁。

## 文件清单（本轮涉及）
- scripts/fx/fx_manager.gd：LightningBolt 内嵌类 + spawn_chain_bolt/lightning_bolt_count +
  spawn_strike_arcs + STATUS_ATTACH_RECIPES["paralyze"]
- scripts/combat/projectile.gd：_try_chain 链跳处触发 _emit_chain_bolt（仅视觉）
- scripts/synergies/thunder_synergy.gd：_chain_burst 每跳连线、_fx_lightning 落雷强化、
  _apply_paralysis 视觉标记（含既有雷区地面视觉 spawn_ground_fx 挂接）
- scripts/enemies/enemy.gd：_paralyze_left 视觉字段 + paralyze 附着/定身图标/0.5s 蓝白闪烁（只加不动）
- scripts/tests/test_lightning_fx.gd / .tscn：新增雷系视觉测试

## 已知限制
- 闪电连线为程序化随机折线，方向/抖动每帧不同属设计内表现（电流感）；
- 并发上限 12 条时高频链跳会降频跳过连线（性能保护），机制不受影响。
"""


def main() -> None:
    # 1) 更新 work/status.json
    status_path = os.path.join(ROOT, "work", "status.json")
    with open(status_path, "r", encoding="utf-8") as f:
        status = json.load(f)
    status["tasks"]["lightning_fx_visual"] = {
        "status": "done",
        "note": ("雷系连锁视觉落地：LightningBolt 链跳连线(3~5段抖动折线+双层辉光+0.22s渐隐+上限12条降频)；"
                 "麻痹蓝白0.5s周期闪烁+程序化定身图标(_paralyze_left视觉标记只加不动)；"
                 "落雷闪电柱(86px双层)+地面电弧溅射4~6条+落地闪光；屏幕微震接线确认有效；"
                 "test_lightning_fx ALL PASS + smoke OK + test_core_mechanics OK"),
    }
    status["updated"] = "2026-08-10-lightning_fx_visual"
    with open(status_path, "w", encoding="utf-8") as f:
        json.dump(status, f, ensure_ascii=False, indent=1)
        f.write("\n")
    print("[report] status.json updated: lightning_fx_visual=done")

    # 2) 生成交付报告
    doc_dir = os.path.join(ROOT, "docs", "design")
    os.makedirs(doc_dir, exist_ok=True)
    report_path = os.path.join(doc_dir, "lightning_fx_visual.md")
    with open(report_path, "w", encoding="utf-8") as f:
        f.write(REPORT)
    print("[report] wrote", report_path)


if __name__ == "__main__":
    main()
