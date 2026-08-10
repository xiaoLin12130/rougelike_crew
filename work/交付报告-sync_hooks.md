# 交付报告：流派机制接线（P0+P1）

**任务**：按 docs/design/流派机制缺口审计.md 的 P0/P1 清单接线，激活死代码机制、攻速对法术流派生效。
**完成时间**：2026-08-10 · 全部 headless 测试通过，无残留 Godot 进程。

## 一、接线代码（改动清单）

| 文件 | 改动 |
|---|---|
| data/items.json | 新增 6 个暴击机制道具（G3）：crit_crit_bounce、crit_weak_mark（稀有）；crit_execute、crit_headhunter、crit_lethal_blow、crit_crit_storm（传说）。id 与 crit_synergy.gd 门控常量一致，tags = ["crit", "mechanic:crit_*"] |
| scripts/combat/spell_caster.gd | ① 施法冷却接入攻速聚合（G1，与近战同公式 cd ÷(1+总攻速)）；② 弹数 += run.wind_m4_shots（移M4）；③ 冷却 × run.wind_cd_mult（移9 迅捷） |
| scripts/combat/melee_attack.gd | 攻击间隔改用同一套攻速聚合（基础 + 六路流派读取点之和） |
| scripts/synergies/fire_synergy.gd | 火M2 只写 run.fire_m2_atk_speed，不再写 run.attack_speed_bonus（G2 收敛） |
| scripts/synergies/melee_synergy.gd | 近M3/M9 只写 run.melee_m3_as_bonus / melee_m9_as_bonus（G2 收敛） |
| scripts/synergies/wind_synergy.gd | ① 攻速只写 run.wind_as_bonus / wind_m2_atk_speed / wind_m10_as_bonus（G2 收敛）；② 修复移5 疾风术架 0 层泄漏（+8% 假攻速）与移10 风行者 0 层泄漏（+0.2 假移速上限）；③ 移速口径封顶 1.0+wind_speed_cap_bonus 与 player 一致 |
| scripts/combat/projectile.gd | ① 命中伤害 ×(1+wind_m7_dmg+wind_m6_move_dmg)（移M7/移6 风刃）；② 暴击率 +wind_speed_crit（移7 顺风）；③ 爆炸半径 ×(1+wind_speed_area)（移8 踏浪） |
| scripts/player/player.gd | 移速聚合：+wind_kill_speed_bonus（移4 追风）+wind_m6_speed_bonus（移6 破风），上限 1.0+wind_speed_cap_bonus（移10 风行者），× water_m7_speed（水M7 洋流） |
| scenes/game/game_root.gd | 受击结算 × run.wind_m10_taken_mult（移M10 暴走 +20%，仅此一处） |
| scripts/combat/summon.gd | 召唤总上限 = total_stacks("summon_1") + total_stacks("summon_book") + 1（召1 接线，旧 id 兼容） |
| scripts/synergies/mech_items.gd | trinket_ember 余烬坠饰：火系命中 +25%/件 |
| scripts/tests/test_sync_hooks.gd + .tscn | 新增回归测试（6 项验收 + 附测） |

## 二、测试全绿输出

```
Godot_v4.7.1-stable_win64_console.exe --headless --path . -s res://scripts/tests/smoke_test.gd
  → SMOKE OK
Godot_v4.7.1-stable_win64_console.exe --headless --path . res://scripts/tests/test_sync_hooks.tscn
  → SYNC HOOKS OK
Godot_v4.7.1-stable_win64_console.exe --headless --path . res://scripts/tests/test_build_mech.tscn
  → BUILD MECH OK
Godot_v4.7.1-stable_win64_console.exe --headless --path . res://scripts/tests/test_summon_ext.tscn
  → [TEST] SUMMON_EXT OK（召1 上限改动未破坏既有召唤测试）
Godot_v4.7.1-stable_win64_console.exe --headless --path . res://scripts/tests/test_core_mechanics.tscn
  → [TEST] CORE MECHANICS OK
Godot_v4.7.1-stable_win64_console.exe --headless --path . res://scripts/tests/test_wand_fix.tscn
  → WAND FIX OK
```

环境按规则：$env:TEMP/$env:TMP → 项目 .tmp，$env:APPDATA → .tmp\appdata，纯 headless（无 GUI 弹窗），
测试结束后已清理全部 Godot 进程。

## 三、接线明细（对应验收 6 项）

1. **① 暴击 6 道具**：6 个 id 均存在于 items.json；模拟持有后 crit_synergy 门控可触发：
   crit_crit_bounce→弹射弹幕生成、crit_weak_mark→标记后 +15% 伤害、crit_execute→低血强制暴击补足差额、
   crit_headhunter→击杀后 crit_hunt_bonus=0.15、crit_lethal_blow→首击必暴补足差额、crit_crit_storm→slow_mo 事件。
2. **② 攻速聚合**：attack_speed_potion×1 → spell_caster 冷却 ÷1.15（与近战 interval 同公式）；
   火M2/近M3/移速流读取点求和生效；移9 迅捷冷却 ×wind_cd_mult。
3. **③ 移M4**：wind_hunter + 移速 ≥100% → run.wind_m4_shots=1 → 施法 2 发（基线 1 发）。
4. **④ 移M7**：wind_tail_shot 方向一致 → 弹幕伤害 ×1.2；移6 风刃追加 ×0.04/层。
5. **⑤ 冰1**：ice_1×1 → 冰系 _spell_damage 10→11（tag "ice" 聚合已生效，验证无双重计数）。
6. **⑥ 召1**：summon_1×1 → 上限 2（5 连召后存活 ≤2）；与 summon_book 叠加 → 上限 3。

## 四、设计取舍说明

- **移速上限语义**（移10 风行者）：默认移速加成上限 100%，风行者按曲线提升
  （player 与 wind 脚本内部口径一致，追风猎手/顺风/暴走阈值系统共用该口径）。
  移M10 暴走（250%）成为需要风行者抬上限的终局收益，与设计文档"移10 联动"一致。
- **G3 稀有度**：按任务要求"传说 4 + 稀有 2"（crit_crit_bounce / crit_weak_mark 稀有，
  其余 4 件传说），与 .tools/build_defs/crit.json 的原始稀有度略有出入，以任务指令为准。
- **冰1**：审计标注"无消费点"，实际 items.json 中 ice_1 已带 tag "ice"，经
  _spell_damage 的 aggregate_bonus("ice") 生效；本次以回归测试确认而非重复叠加。
- **G2 收敛方式**：game_state.gd 禁改，故采用"唯一写入者 + 消费端求和"：
  run.attack_speed_bonus 只由 apply_item_effects_to_stats 写入，三个 synergy 只写各自
  run.xxx_bonus，spell_caster / melee_attack 统一读和（同步维护同一常量表）。

## 五、禁改文件核对

未改动：data/balance.json、data/enemies.json、data/levels.json、data/wands.json、
scripts/ui/game/*、scripts/core/game_state.gd、scripts/fx/*、scripts/tests/auto_play.gd。
