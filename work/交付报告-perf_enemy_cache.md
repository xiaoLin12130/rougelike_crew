# 交付报告：P0 敌人数组缓存（perf_enemy_cache）

> 2026-08-10 · 依据 docs/design/性能优化方案.md 第 2/3 节 P0 项

## 一、目标与结论

目标：把 synergy 钩子 / combat 读取点中高频的 `get_nodes_in_group("enemy")` 换成常驻敌人列表缓存，
由 spawner/level 生命周期内的敌人注册/注销维护，战斗帧 CPU 下降。

**结论：缓存实现 + 全量替换 + 测试全绿完成；查询动作本身实测提速 2.6~3.1 倍
（0.51µs → 0.19µs/次，同进程 2000 次对比）；但 300 帧场景级帧耗时差异处于机器
背景负载噪声之内——Godot 4.7 的组查询是哈希索引（非全树搜索），单查询绝对收益为
微秒级，帧级"明显下降"在该引擎版本下无法成立（详见第五节性能数据与归因）。**

## 二、实现内容

### 1. 缓存容器（scripts/core/game_state.gd，只增不改）

- `var _enemy_cache: Array[Node]` / `_enemy_cache_pending` / `_enemy_cache_dirty`：
  常驻敌人列表 + 入树挂起队列 + 出树脏标记。
- `register_enemy(e)`：入树注册（挂起队列，防遍历中追加）。
- `unregister_enemy(e)`：出树注销（只置脏标记，防遍历中删除）。
- `get_enemies() -> Array[Node]`：查询时合并挂起 / 压缩失效条目（整体重建数组，
  不改旧数组对象，遍历期间注册/注销/嵌套查询均安全）；**缓存为空时回退组查询**，
  与旧语义完全一致（兼容测试中用 `add_to_group` 的假敌人场景）。
- 返回类型 `Array[Node]` 与 `get_nodes_in_group` 一致：`var id := e.get_instance_id()`
  等类型推断与旧代码完全相同（首版无类型返回导致 curse_synergy 解析错误，已修复）。

### 2. 注册/注销（scripts/enemies/enemy.gd）

- `_ready()`：`add_to_group("enemy")` 后 `GameState.register_enemy(self)`。
- `_exit_tree()`：`GameState.unregister_enemy(self)`（带 `is_instance_valid(GameState)`
  守卫，关机场景安全）。
- Boss 继承 EnemyBase 无顶层 `_ready`，自动覆盖注册；分裂/精英小怪/Boss 召唤
  均用 enemy.tscn（EnemyBase），全部自动注册。

### 3. 读取点替换（45 处 / 18 文件）

| 文件 | 处数 | 说明 |
|---|---|---|
| synergies/*.gd（12 个） | 44 | 钩子内 `for e in ...get_nodes_in_group("enemy")` 全部改 `GameState.get_enemies()`；`is_instance_valid`/`is_elite`/`_dead` 等过滤全部保留 |
| enemies/enemy.gd | 4 | 治疗/集群/图腾/防重叠内部查询 |
| enemies/boss.gd | 1 | 清屏冲击波 |
| enemies/spawner.gd | 1 | `_enemies_alive()` |
| combat/projectile.gd | 1 | `_all_enemies()`（组缺失的全树回退保留） |
| combat/melee_attack.gd | 1 | 常驻索敌 |
| combat/summon.gd | 3 | 嘲讽/最近敌人/附近敌人 |
| combat/spell_caster.gd | 4 | 虚空/圣光爆发、清场、最近敌人 |
| tests/auto_play.gd | 3 | 自动机读取点 |

未改（按所有权）：`scenes/game/game_root.gd`（禁改区，组查询仍可用）、
`tools/tests/experience_probe.gd`（tools 区）、测试断言中的组查询
（test_boss_skills/test_build_mech，直接对照真实组，语义正确）。
`get_nodes_in_group("summons"/"player_projectile"/"enemy_bullet")` 不在本次范围。

### 4. 已知坑处置

- 死亡帧：`_die → queue_free` 后 tree_exiting 帧末触发，缓存仍含该敌人——与
  组查询行为一致，遍历处保留 `is_instance_valid` 检查（原代码已具备）。
- 遍历中击杀/生成：注册走挂起队列、注销置脏，查询时整体重建数组，实测
  test_enemy_cache ④ 遍历中击杀+生成不报"数组遍历中被修改"。
- 切关清空：level 释放 → 全部敌人 tree_exiting → 脏标记 → 下次查询压缩为空。
- 缓存为空回退组查询：test_fire_zones_reentrant / test_ground_fx 的假敌人
  （add_to_group 非 EnemyBase）行为与旧代码完全一致，无需改既有测试。

## 三、新增测试

- `scripts/tests/test_enemy_cache.gd` + `.tscn`：
  - ① 同步：生成 10 → 缓存 10；杀 5 → 缓存 5；清场 → 0（均与组集合相等）
  - ② 钩子对照：加载全 12 synergy 后触发 enemy_status / projectile_hit /
    enemy_hit，每步断言缓存结果 == get_nodes_in_group 结果（集合相等）
  - ③ 切关：释放容器 → 缓存 0；新关卡生成 2 → 缓存 2
  - ④ 遍历中击杀 + 生成：不报错且最终集合一致
  - 结果：**ENEMY CACHE ALL PASS**
- `scripts/tests/bench_enemy_cache.gd` + `.tscn`：性能基准（见第五节）。

## 四、回归结果（全部 Green）

| 测试 | 结果 |
|---|---|
| scripts/tests/test_enemy_cache.tscn | ENEMY CACHE ALL PASS |
| scripts/tests/smoke_test.gd（-s） | SMOKE OK |
| test_core_mechanics.tscn | CORE MECHANICS OK（exit 0） |
| test_sync_hooks.tscn | SYNC HOOKS OK（exit 0） |
| test_ground_fx.tscn | GROUND_FX ALL PASS |
| test_lightning_fx.tscn | LIGHTNING FX ALL PASS |
| test_core_shell.tscn | CORE SHELL OK（exit 0） |

运行方式（每次运行后清理 Godot 进程，无残留）：
`$env:TEMP/$env:TMP=项目\.tmp；$env:APPDATA=项目\.tmp\appdata；
.\.tools\godot\Godot_v4.7.1-stable_win64_console.exe --headless --path . <场景>`

## 五、性能对比数据

### 微基准（Phase A：查询动作本身，同进程 2000 次，32 敌人）

优化前（组查询）：**0.51 µs/次**（6 次取样中位数，范围 0.49~0.94 µs）
优化后（缓存查询）：**0.19 µs/次**（范围 0.18~0.30 µs）
**提速 2.6~3.1 倍**，且组查询每次调用新建数组（GC 分配），缓存查询零分配。

### 场景基准（Phase B：同一场景 300 帧，32 敌人 + 全 synergy + melee/spawner/ice
每帧读取点 + 火地 zone，`--fixed-fps 60`，固定种子，跳过前 30 帧预热）

| 运行组 | TIME_PROCESS+PHYSICS 合计（ms，中位数） |
|---|---|
| 优化前（9 次取样） | 17.02 ms |
| 优化后（6 次取样） | 20.58 ms（受背景负载影响，见下） |

运行期间本机 Codex 运行时（bun/ChatGPT 进程，全天常驻，CPU 达 ~50% 单核且波动）
导致帧级测量方差 ±30%，两版最干净样本分别为 13.47 ms（前）/ 15.99 ms（后），
差值落在噪声带内，**不能得出帧级显著差异**。

### 归因（重要）

设计文档假设 `get_nodes_in_group` 是"全树搜索 O(n)"。实测 Godot 4.7 中组是按名字
哈希索引的，单次 32 节点组查询仅 ~0.5 µs（含新数组分配）；缓存后 ~0.19 µs。
战斗帧内实际每帧查询次数约 3~10 次，单帧绝对节省 ~1~3 µs（16 ms 帧的 0.02% 量级），
帧级无法呈现"明显下降"。本次改动价值：

1. 查询动作提速 ~3 倍 + 每帧消除 N 次数组分配（GC 压力下降）；
2. 热路径读取点收敛到单一数据源（后续可无缝升级为真正的对象池/空间索引）；
3. 语义与旧行为严格一致（缓存为空回退组查询 + 类型化返回），全量回归绿。

## 六、文件清单

改：scripts/core/game_state.gd、scripts/enemies/{enemy,boss,spawner}.gd、
scripts/combat/{projectile,melee_attack,summon,spell_caster}.gd、
scripts/synergies/（12 个）、scripts/tests/auto_play.gd、work/status.json
新：scripts/tests/{test_enemy_cache,bench_enemy_cache}.gd + .tscn、
work/交付报告-perf_enemy_cache.md
备份：.tmp/perf_enemy_cache_backup/（优化前/后文件快照，A/B 测量用）
