# 批次A测试对齐报告

- 日期：2026-08-13
- 文件：`tools/tests/test_curves.py`（仅测试断言，未改任何游戏代码 / data / 其他脚本）
- 结果：`python tools/tests/test_curves.py` 全绿，0 失败（293 items / 15 cores / 10 shells / 31 enemies / 6 bosses / 5 levels）
- 真源：`data/balance.json`、`data/enemies.json`（以当前表值为准）

## 修改清单

| # | 位置 | 旧断言 | 新断言 | 依据 |
|---|------|--------|--------|------|
| 1 | 玩家初始 HP | `player.hp == 85` | `player.hp == 80` | balance.json `player.hp = 80` |
| 2 | enemy scaling 注释与派生计算 | `level_atk 0.16`；`atk_l1/atk_l5` 用 `0.16`，系数 `(1+0.64)` | `level_atk 0.12`；派生用 `0.12`，系数 `(1+0.48)` | balance.json `enemy_scaling.level_atk = 0.12`（game_state.enemy_atk 默认参数 0.16 只是 fallback，实际从 balance 读 0.12） |
| 3 | balance level_atk 一致性 | `b["level_atk"] - 0.16` | `b["level_atk"] - 0.12` | 同上 |
| 4 | level_num | `b["level_num"] - 0.26` | `b["level_num"] - 0.24` | balance.json `enemy_scaling.level_num = 0.24` |
| 5 | xp L1 | 硬编码 `30`（旧加速段） | `38` | 统一公式 `38 + 30(L-1) + 5(L-1)^2`（base=38 / per_level=30 / quad=5），L1-3 硬编码加速已移除 |
| 6 | xp L2 | 硬编码 `60`（旧加速段） | `73` | 同上 |
| 7 | xp L3 | 硬编码 `100`（旧加速段） | `118` | 同上 |
| 8 | xp L4 | `== 175`（重复断言 2 次，去重 1 次） | `== 173` | `38 + 30*3 + 5*9 = 173` |
| 9 | xp L5 | `== 240` | `== 238` | `38 + 30*4 + 5*16 = 238` |
| 10 | xp L6（新增） | 无 | `== 313` | `38 + 30*5 + 5*25 = 313` |
| 11 | goblin_archer 子弹速度 | `bullet_speed == 190` | `bullet_speed == 170` | enemies.json `goblin_archer.bullet_speed = 170`（sniper_speed = 340 不变） |
| 12 | 普通怪金币区间 | `1 <= gold <= 3` | `1 <= gold <= 4` | enemies.json 实际区间：obsidian_golem / temple_guardian gold = 4 |

## 核对未改动项（已验证与真源一致）

- `level_hp = 1.22`、`loop_hp = 1.34`、`loop_dmg = 1.24`：与 balance.json 一致，未改。
- wizard：`attack = 18`、`bullet_speed = 165`：与 enemies.json 一致，未改。
- goblin_archer `sniper_speed = 340`：与 enemies.json 一致，未改。
- Boss 金币区间 `30 <= gold <= 240`：enemies.json 实际 30/44/56/68/84/240，均在区间内，未改。
- player.speed = 200：test_curves.py 中无 speed 断言（test_sync_hooks.py 不在本次范围），未改。
- xp 单调性断言（L1..L14 逐级递增）保留，新曲线下依然成立。
