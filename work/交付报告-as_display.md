# 交付报告：攻速效果展示（F 批）

日期：2026-08-10
状态：done（三处展示全部实现 + 测试全绿）

## 1. 问题与目标

玩家反馈"无法理解攻击速度的作用"。攻速此前已全局接线（spell_caster 施法冷却 ÷(1+总攻速)、melee_attack 攻击间隔同公式），但界面上只有干巴巴的"攻速 +X%"数值，玩家看不到它对冷却的实际影响。

目标：把"攻速 → 冷却缩短"的换算用直白文案展示到三处 UI，全部基于运行时同一公式 `cd_mult = 1/(1+as)`，显示值与实际施法/攻击间隔完全一致。

## 2. 改动清单（仅任务授权文件）

| 文件 | 改动 |
| --- | --- |
| scripts/core/game_state.gd | 新增 4 个只读查询函数 + 常量（无任何写入/状态变更） |
| scripts/ui/game/build_panel.gd | `_refresh_stats` 统计区追加换算行 |
| scripts/ui/game/hud.gd | DPS 行旁新增攻速小字（_as_label） |
| scripts/ui/game/levelup_overlay.gd | 攻速类道具卡片描述自动追加换算 |
| scripts/tests/test_as_display.gd | 新增攻速展示测试 |

未改动：data/*.json、scripts/combat/*、scripts/synergies/*、scenes/。

## 3. 展示实现细节

### 3.1 game_state.gd 只读查询（与运行时同口径）

- `total_attack_speed_bonus()`：基础聚合 `run.attack_speed_bonus`（apply_item_effects_to_stats 写入）+ 6 个流派贡献读取点（fire_m2_atk_speed / melee_m3_as_bonus / melee_m9_as_bonus / wind_as_bonus / wind_m2_atk_speed / wind_m10_as_bonus），与 spell_caster._total_attack_speed / melee_attack._interval 求和方式一致；未聚合时（新局/测试）回退 `aggregate_bonus("attack_speed")`，保证任何时刻显示值与运行时一致。
- `attack_speed_pct()`：攻速百分比（round 后整数）。
- `attack_speed_cd_reduction_pct(as_bonus=-1)`：换算 `round((1 - 1/(1+as)) * 100)`；不传参用当前总攻速，传参可预览。
- `attack_speed_summary()`：直白文案 `攻速 +50%：施法更快，冷却缩短 33%`。

### 3.2 三处展示

1. **构筑面板统计区**（build_panel._refresh_stats）：原有三行统计下方追加第 4 行换算文案；第一行"攻速 +X%"同步改用 attack_speed_pct()（此前用 aggregate_bonus 漏掉了流派贡献键）。
2. **升级三选一卡片**（levelup_overlay.show_choices）：道具 tags 含 `attack_speed` 时，描述末尾自动追加 `（当前攻速 X%，冷却 -Y%）`，X/Y 为当前（拾取前）实时值；非攻速道具不追加。
3. **HUD**（hud._refresh）：DPS 行旁新增小字 `攻速+Z%`（与 DPS 同字号同色系），攻速为 0 时留空不占视觉噪音；随 player_stats_changed 事件实时刷新。

### 3.3 换算一致性验证

- 公式与施法侧一致：spell_caster._cooldown_of 中 `cd_mult *= 1.0 / (1.0 + _total_attack_speed())`；近战 melee_attack._interval 为 `0.8 / (1.0 + as)`。展示的"冷却 -Y%"即 `1 - 1/(1+as)`。
- 数值抽查：0% → 冷却 -0%；50% → -33%；100% → -50%；15%（1 瓶攻速药水）→ -13%。

## 4. 测试结果（Godot 4.7.1 headless 控制台版）

```
test_as_display.gd  → ALL PASS   (0→0% / 50→33% / 100→50% + 三处 UI 文本断言 + 流派键计入 + 未聚合回退)
smoke_test.gd       → SMOKE OK
hud_layout_test.gd  → PORTRAIT UI OK / EXPAND UI OK（资源条宽 274 ≤ 360，高 70 ≤ 80，布局未破坏）
```

测试后已清理全部 Godot 进程，TEMP/TMP/APPDATA 指向项目 .tmp 目录（headless 运行强制规则）。

## 5. 已知边界

- HUD 小字仅显示攻速加成百分比（保持低信息密度设计），完整换算文案在构筑面板与升级卡片中。
- 升级卡片描述区为固定 46px 高 + 自动换行，追加行在攻速卡片上会使卡片略增高（3 卡总高仍 < 640，不超屏）。
- 攻速为 0 时 HUD 小字留空、换算行显示"攻速 +0%：施法更快，冷却缩短 0%"，不误导。
