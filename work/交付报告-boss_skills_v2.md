# 交付报告：Boss 技能扩展 v2

> 日期：2026-08-10 · 状态：done · 方案文档：docs/design/Boss技能扩展方案.md

## 一、每 Boss 新技能清单（含参考来源）

| Boss | 原有技能 | 新增技能 | 类型 | 参考来源 |
| --- | --- | --- | --- | --- |
| 史莱姆王 | 4 | 分裂本体（split_self）| split 分裂 | 以撒的结合（Mulliboom 分裂怪） |
| 树精守卫 | 5 | 根须地刺（root_spikes）| spike_trail 地刺轨迹 | 元气骑士冰洞 Boss 地面突刺、以撒 Delirium 地板刺 |
| 骷髅王 | 4 | 骨刃扫射（bone_sweep）| sweep 扇形激光扫 | 雨中冒险 2 Stone Titan 激光扫射、元气骑士激光 Boss |
| 熔岩魔王 | 5 | 烈焰螺旋（flame_spiral）| spiral 旋转弹幕环 | 以撒 Hush 连续错相弹幕环、元气骑士火山 Boss 火圈 |
| 熔岩魔王 | 5 | 火墙（fire_wall）| wall 弹幕墙 | 吸血鬼幸存者 Boss 弹幕墙推进 |
| 远古守卫 | 4 | 圣光追踪弹（seeker_light）| homing_shot 追踪弹 | 吸血鬼幸存者 seeker、枪火重生追踪词缀 |
| 远古守卫 | 4 | 圣光闪现（guardian_blink）| blink 闪现+落点爆炸 | 以撒 Delirium 闪现、雨中冒险 2 Mithrix 相位 |
| 古神 | 5 | 虚空螺旋（void_spiral）| spiral 旋转弹幕环 | 以撒 Hush 弹幕环 |
| 古神 | 5 | 虚空追踪（void_seeker）| homing_shot 追踪弹 | 枪火重生追踪词缀 |
| 古神 | 5 | 远古狂暴（ancient_enrage）| enrage 狂暴 | 雨中冒险 2 阶段强化、吸血鬼幸存者精英狂暴 |

技能数达标：前 3 个 Boss ≥3（5/6/5），后 3 个 ≥5（7/6/8）。旧技能参数零改动。

## 二、实现说明

- 全部 8 种新类型复用状态机（WINDUP→CAST→RECOVER）+ telegraph 系统，共新增 8 个实现函数、2 个判定函数，未动旧技能逻辑。
- **预告一致性铁律**：每种新类型的预告几何与伤害区逐一断言（circle 半径=爆炸半径、line 宽=判定宽/两边界线夹角=sweep_angle、dot 大半径=地刺伤害半径）；dot 预告新增"大半径=伤害点"红色语义（半径>12 画红圈），小圈仍为弹幕发射点标记。
- homing_shot：enemy_bullet.gd 只增 `_homing/_turn_rate/_lifetime` 与转向逻辑（默认参数向后兼容，非 homing 弹行为不变）。
- sweep 伤害语义：玩家方向角落在"已扫过扇形"内即命中（与起止边界线预告一致），避免窄带判定漏伤。
- enrage：`_check_phase` 阶段 3 自动触发（幂等），`_start_skill` 冷却乘区 ×0.7，`_update_approach` 移速乘区 ×1.3；不占 AI 施法池。
- CD 8-12s 控制弹幕密度；伤害全部走 skill dict 参数（damage_mult 默认值保持旧技能行为）。

## 三、测试结果

- `test_boss_skills.tscn`：**BOSS SKILL TESTS OK**（退出码 0）。覆盖：23 个通用用例（原 14 + 新 9：spiral/homing_shot/sweep/spike_trail/blink/wall/enrage/split 全绿：debug_cast→telegraph 生成→cast 完成→状态恢复 APPROACH）+ homing 转向标志专项 + enrage 冷却 ×0.7 断言 + 6 Boss 技能数断言 + 真实 enemies.json 配置预告几何审计。
- `smoke_test.gd`：**SMOKE OK**（退出码 0）。
- 无 Godot 进程残留。

## 四、并行代理注意事项

1. `scripts/tests/_probe_engine.gd`（Godel 性能优化代理 22:23 创建）存在 parse error（`Engine.get_error_messages` 不存在），smoke_test 扫描时会报错但不影响 SMOKE OK/退出码；属其中间态文件，未改动。
2. `data/enemies.json` 22:58 由本任务重写（追加 Boss 技能），Descartes 的小怪 bullet_speed 改动已完整保留；若 Descartes 之后继续改 enemies.json，请基于当前版本（含 10 个新 Boss 技能）继续。
3. `scripts/enemies/boss.gd` 中 Godel 的 `GameState.get_enemies()` 改动（_on_phase_up）已保留。

## 五、文件清单

- docs/design/Boss技能扩展方案.md（新）
- scripts/enemies/boss.gd（+8 新类型）
- scripts/enemies/enemy_bullet.gd（+homing 转向，只增不改）
- data/enemies.json（+10 技能，旧参数零改动）
- scripts/tests/test_boss_skills.gd（+9 用例 + 3 专项）
- work/write_boss_skills_doc.py / work/append_boss_skills.py / work/write_boss_skills_status.py（生成脚本）
