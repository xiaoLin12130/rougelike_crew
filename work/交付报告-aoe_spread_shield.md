# 交付报告：AOE 多弹分散 + 护盾显示（问题 3/5）

日期：2026-08-10 ｜ 任务：范围伤害多弹分散 + 护盾显示（问题 3/5）

## 一、改动清单

### 1. AOE 瞬发核多弹自适应分散（问题 3）— scripts/combat/spell_caster.gd

问题：齐射壳（spread）固定 `spread_angle=24°`，range 200px 时相邻落点间距仅 ~41px，小于毒雾 48 / 火柱 64 / 闪光盲爆 90 的爆炸半径，多团仍重叠。

修复（仅 `_cast` 的瞬发多弹落点逻辑 + 两个辅助函数）：

- `speed<=0 且 shots>1` 时，按核心实际爆炸半径计算扇形总角：
  - 步角 `Δθ = 2*asin(radius/(2*range))`，总角 `(shots-1)*Δθ`，保证相邻落点弦距 ≥ 爆炸半径；
  - 与齐射壳自带 spread_angle 取 max（覆盖固定 24°，壳想更宽仍可更宽）；
  - 非 AOE 瞬发核无半径时保留原 24° 兜底；
  - 总角上限 160° 防极端 aoe_mult 场景反向散射。
- `_instant_burst_radius()`：flash（数据 aoe=0）按盲爆半径 90×aoe_mult 计（与 projectile.gd BLIND_BURST_RADIUS 一致），并计入 wind_speed_area 增幅。
- projectile._instant 分支落点 `spawn + dir*range` 保持不变（dir 已是分散方向）。

实测落点间距：毒雾 50.9px（≥48）、闪电 28.5px（≥26）、闪光 95.4px（≥90）。

### 2. 护盾显示（问题 5）— scripts/ui/game/hud.gd

护盾池确认：`defense_synergy._shield`（synergy 内部状态，非 run 字段），HUD 只读查询、不写不广播。

- 血条灰色层：`_hp_bar` 子节点第二根 ProgressBar（全 rect 锚定、透明背景 + 灰色 fill），绘制于 HP 条之上，`value/max_value = 护盾/最大生命`，宽度即护盾占比；
- 血量文本：有护盾时 `100/120（护盾 30）`，无护盾保持 `100/120`；
- 刷新：`_refresh`（player_stats_changed 链路，扣血/护盾增减后触发）+ 0.5s DPS 定时器兜底（换局重置等无广播路径）；
- 护盾值定位：按脚本路径 `resource_path` 扫描 `defense_synergy` 节点（不 preload 他人进行中的 synergy 脚本，避免编译耦合），未挂载（headless 测试场景）返回 0。

## 二、测试结果（全部 Godot 4.7.1 headless 实跑）

| 测试 | 结果 |
| --- | --- |
| scripts/tests/test_aoe_spread.tscn（新） | AOE SPREAD ALL PASS（毒雾/闪电/闪光 × shots=5，两两间距 ≥ 半径-8，方向互异） |
| scripts/tests/test_hud_shield.gd（新） | ALL PASS（有护盾灰层可见 + value/max 正确 + 文本"100/120（护盾 30）"；无护盾/归零隐藏） |
| scripts/tests/smoke_test.gd | SMOKE OK |
| scripts/tests/test_core_shell.tscn | CORE SHELL OK（既有瞬发多弹断言无需同步：原断言仅要求方向/落点互异，新逻辑天然满足） |
| scripts/tests/test_as_display.gd | ALL PASS |

说明：hud_layout_test 的 "法杖商店商品卡纵向重叠" 失败来自 wand_shop.gd（其他代理进行中改动 +159 行，任务禁止触碰），与本次改动无关；HUD 部分布局断言全部通过。

## 三、文件所有权遵守

- 只写：scripts/combat/spell_caster.gd（仅 _cast 瞬发多弹落点逻辑）、scripts/ui/game/hud.gd、scripts/tests/（新增 3 文件）；
- 未触碰：scripts/fx/fx_manager.gd、scripts/synergies/*、data/*.json、wand_shop.gd、build_panel.gd、projectile.gd；
- 护盾实现（defense_synergy.gd）只读查询，零修改。

## 四、验收命令复现

```
$env:TEMP="H:\rougelike_crew\.tmp"; $env:TMP="H:\rougelike_crew\.tmp"; $env:APPDATA="H:\rougelike_crew\.tmp\appdata"
.\tools\godot\Godot_v4.7.1-stable_win64_console.exe --headless --path . res://scripts/tests/test_aoe_spread.tscn
.\tools\godot\Godot_v4.7.1-stable_win64_console.exe --headless --path . -s res://scripts/tests/test_hud_shield.gd
.\tools\godot\Godot_v4.7.1-stable_win64_console.exe --headless --path . -s res://scripts/tests/smoke_test.gd
.\tools\godot\Godot_v4.7.1-stable_win64_console.exe --headless --path . res://scripts/tests/test_core_shell.tscn
```

无 Godot 进程残留（每轮测试进程自行退出）。
