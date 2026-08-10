# 交付报告：第 3 轮遗留 BUG 修复（荆棘甲 0 层反弹 + 分裂史莱姆物理冲刷报错）

日期：2026-08-10 ｜ 依据：docs/reports/全流程体验报告-第3轮.md（P2-1）
状态：两 BUG 修复完成，回归测试全绿（CORE MECHANICS OK / SMOKE OK），无 flushing 错误，无 Godot 残留进程。

## 0. 重要附注：任务文件映射与代码现实不符（已按任务自身兜底条款落地）

任务描述将"荆棘甲反弹实现"定位在 `scripts/synergies/mech_items.gd`，但实际代码不在那里：
mech_items.gd（125 行）只有饰品增伤/熔岩护符/石肤恐惧咒退款/冻结延长，**没有任何 thorn 相关函数**。
荆棘甲反弹的真实实现（与第 3 轮报告证据链一致）：

- `scenes/game/game_root.gd` `_on_player_hit`（旧 id `thorn_reflect`，报告点名的 game_root.gd:407 消费点）；
- `scripts/synergies/defense_synergy.gd` `_reflect_pct_old()` / `_reflect_pct_new()` / `_reflect_total()` / `_supply_reflect()`（旧 id 估算 + 新 id 防2 荆棘甲改造补发）。

任务条款写明"mech_items.gd（或相关反弹实现）"，故守卫落在真实消费点（两处均加）。
mech_items.gd 保持未改。数据表/UI/fx/场景结构均未动；未动任何机制数值。

## 1. P2-1a 荆棘甲 0 层反弹（item_value linear 边界缺陷）

### 根因
`GameState.item_value` 的 linear 曲线在 n=0 时返回 base（`base*(1+k*max(n-1,0))`，n=0 → base）。
`thorn_reflect` 未持有层数时，game_root 仍按硬编码曲线（base 0.40）反弹 40% 所受伤害给最近敌人；
defense_synergy 同款公式估算也按 40% 参与吸血/传染/复仇等联动，`defense_thorn_refit`（新 id）同样
按 base 30% 泄漏。防御流成型奖励叠加逻辑保持原样（≥1 层时曲线 + 成型奖励与修复前一致）。

### 修复（全部为消费点加 `total_stacks > 0` 守卫，与既有"四叶草 0 层泄漏"模式同款）
1. `scenes/game/game_root.gd`：反弹消费 if 增加 `GameState.total_stacks("thorn_reflect") > 0`；
   同块内血棘甲回血增加 `total_stacks("blood_thorn") > 0`（同款 0 层泄漏，防 2%→0 层白嫖）。
2. `scripts/synergies/defense_synergy.gd`：`_reflect_pct_old()` 增加 thorn_reflect 守卫、
   `_reflect_pct_new()` 增加 defense_thorn_refit 守卫（0 层直接返回 0，下游吸血/传染/复仇/吸收自动归零）。

## 2. P2-1b 分裂生成在物理冲刷期 add_child（flushing queries 报错）

### 根因
分裂史莱姆 `_die()` 直接 `get_parent().add_child(e)`；弹幕 `_spawn_split_minis` 直接
`current_scene.add_child(mini)`。当死亡发生在物理冲刷期回调链内（第 3 轮证据链：
enemy_bullet._on_body → game_root 反弹 → enemy.take_damage → _die → add_child），
新碰撞体在 flush 期间入树 → 16 次 `Can't change this state while flushing queries`（非致命刷屏）。

### 修复（两处分裂生成均改 deferred，延迟一帧加树）
1. `scripts/enemies/enemy.gd` `_die()`：`get_parent().add_child(e)` → `get_parent().call_deferred("add_child", e)`；
   分裂产物 20s 自毁 lambda 保持按值捕获 instance_id（GDScript lambda 语义无改动）。
2. `scripts/combat/projectile.gd` `_spawn_split_minis()`：`current_scene.add_child(mini)` →
   `current_scene.call_deferred("add_child", mini)`（先创建/设参后加树的顺序不变）。

## 3. 回归测试（scripts/tests/test_core_mechanics.gd 扩展，不新增数据/场景）

① `_test_thorn_reflect`：裸节点后置 `set_script(game_root.gd)`（不触发 _ready，跑真实 `_on_player_hit` 消费链）；
免疫掷骰（thorn_armor/guard_shield 0 层 exp_proc 10%/30%）用固定种子压掉。
- 0 层：受击 10 → attacker 不掉血、damage_dealt 0 次、defense_synergy 旧/新估算均为 0；
- 1 层：反弹 = int(taken_int × 0.40)（第 1 层 = base），attacker 精确掉血、damage_dealt 恰好 1 次。

② `_test_split_flush_safe`：Area2D(collision_mask=2) 与分裂史莱姆重叠 → body_entered（物理冲刷期回调）
内 take_damage 击杀 → `_die` 分裂体 deferred 生成：5 帧后场上恰好 1 只 `_is_split` 分裂体、原怪已死；
运行日志无任何 `flushing queries` / SCRIPT ERROR。

## 4. 验收结果

| 命令 | 结果 |
| --- | --- |
| `test_core_mechanics.tscn`（含新增 2 项回归） | `[TEST] CORE MECHANICS OK`，exit 0，日志 3 行无 ERROR |
| `-s res://scripts/tests/smoke_test.gd` | `SMOKE OK`，exit 0 |
| 全量日志扫描 | 无 `flushing queries`、无 `SCRIPT ERROR`、无 `TEST] FAIL` |
| Godot 进程残留 | 0（本任务全部 console + headless + TEMP/APPDATA 隔离到 .tmp） |

## 5. 协同与边界说明

- **解阻塞**：并行代理（P0 敌人常驻缓存）工作区遗留 `game_state.gd` `unregister_enemy` 的
  `Array.erase()` 误用（parse error，GameState autoload 无法加载，阻塞一切运行）。按"先 has 再 erase"
  语义不变修复，其后续改动（类型化数组/合并重建）已在同一文件上叠加共存，未冲突。
- **并发回滚与重打**：验收期间并行代理整体回滚其敌人缓存分支（enemy.gd / projectile.gd /
  defense_synergy.gd / game_state.gd 一度回到 HEAD，本任务的 3 处修复被连带冲掉，测试文件与
  game_root.gd 守卫幸存）。发现后已重新应用 3 处修复并**再次全量验收**（22:38 重跑：
  CORE MECHANICS OK / SMOKE OK / 无 flushing），最终工作树修复在位（见第 4 节最终结果）。
- **未触碰**：mech_items.gd（无 thorn 代码，无需改）、data/*.json、scripts/ui/*、fx_manager.gd、tools/。
- **既有噪音**（非本任务引入，未改）：`scripts/tests/_probe_engine.gd`（HEAD 已提交的探测脚本，
  `Engine.get_error_messages()` 在 4.7.1 不存在）与并行代理新建 `bench_enemy_cache.gd`（_process 签名错误）
  在 smoke 编译扫描中打印解析错误行，但 smoke 仍 `SMOKE OK` exit 0（Godot 4.7 load() 对坏脚本返回非 null）。
- 数值未动：反弹曲线（game_root 硬编码 0.40/0.35/0.95、OLD_REFLECT、C2）与 items.json 均未改；
  仅 0 层消费被守卫禁用。

## 6. 最终验证快照（重打补丁后，22:38）

- `test_core_mechanics.tscn` → `[TEST] CORE MECHANICS OK`（exit 0，日志 3 行，含新增
  `_test_thorn_reflect` / `_test_split_flush_safe` 全部断言）
- `-s res://scripts/tests/smoke_test.gd` → `SMOKE OK`（exit 0）
- 扫描两日志：无 `flushing queries`、无 `SCRIPT ERROR`、无 `TEST] FAIL`
- Godot 进程残留：0
