# 交付报告：P0 召唤光环崩溃 + P2 火系地面数组越界修复

日期：2026-08-10 ｜ 依据：docs/reports/全流程体验报告-第2轮.md（BUG P0-1 / P2-4）
状态：两 BUG 修复完成，全部回归测试绿，无 Godot 残留进程。

## 1. P0-1 召唤光环 freed-instance 崩溃（fx_manager.gd）

### 根因
`_refresh_summon_auras()` 把 `_summon_auras`（召唤物 instance_id → 光环节点）的字典值
直接赋给 **Node2D 类型化变量**（原第 1094/1112 行）：

```gdscript
var aura: Node2D = _summon_auras[sid]   # 值可能是已释放实例
```

召唤物死亡（连带其光环子节点销毁）后字典残留该条目。下一轮刷新把 freed-instance 赋给
类型化变量 → GDScript 立即报 `Trying to assign invalid previously freed instance` 并
**中止整个函数**，`erase` 不执行 → 残留条目每帧重复报错（R1 实测 327 次）直至进程退出
（t=477.5s 古神战，必胜局丢失）。

### 修复（scripts/fx/fx_manager.gd，仅 `_refresh_summon_auras` 及两个新私有函数）
1. **判活后使用**：字典取值一律先落无类型 Variant，`is_instance_valid()` 判活通过后才
   赋给类型化变量/调用；无效值先 `erase` 再重建（覆盖"召唤物存活但光环被外部释放"的
   同型路径，原 1094 行）。
2. **生命周期钩子**：光环创建时连接 `tree_exiting`（`_connect_aura_cleanup` +
   `_on_aura_tree_exiting`），召唤物销毁帧即同步擦除条目，杜绝残留窗口期。
3. 清理循环同样改为无类型取值 + 判活后 `queue_free`。

## 2. P2-4 火系地面区数组越界（fire_synergy.gd）

### 根因
`_tick_zones` / `_ignite_zones` 用倒序下标遍历 `_zones`，但循环体内存在**重入**：
`_zone_hit` → 敌人受击死亡 → 火M1 灰烬爆炸 → 重入 `_ignite_zones` 删除 zone（甚至
嵌套重入，以及火M10 上限 `pop_front` 前移索引）。外层循环继续按调用时的旧下标访问
`_zones[i]` / `_zones.remove_at(i)` → 越界（R2 实测 `_ignite_zones:408/415` +
`_tick_zones:364` 各 1 次；回归测试稳定复现 `remove_at index 6 OOB` +
`get index '5' OOB`）。函数中止还导致 zone 的 tick 不再推进。

### 修复（scripts/synergies/fire_synergy.gd，仅地面数组相关）
1. 每个 zone 增加唯一 `id`（`_zone_seq` 计数）。
2. 两个循环改为 `_zones.duplicate()` 快照迭代 + `_zone_exists()` 按 id 确认存活 +
   `_remove_zone()` 按 id 定位删除——重入删除/前移后不会访问失效下标，也不会对
   同一 zone 二次引爆/二次释放。
3. `_ignite_zones` 改为"先摘除再结算伤害"，重入方天然跳过已摘除 zone。

## 3. 回归测试

| 测试 | 命令 | 结果 |
|---|---|---|
| 召唤光环崩溃 | `res://scripts/tests/test_summon_fx_crash.tscn` | **SUMMON_FX ALL PASS**（600 帧，无 freed-instance ERROR，残留条目清零；覆盖 30 召唤物批量生成→击杀消失→持续刷新，及"光环被外部释放"边界） |
| 火地重入越界 | `res://scripts/tests/test_fire_zones_reentrant.tscn` | **FIRE_ZONES REENTRANT ALL PASS**（旧代码下 FAIL：`left_sum=6.00 未递减` + 两条越界报错；修复后 zones 正常过期清空） |
| 地面视觉 | `res://scripts/tests/test_ground_fx.tscn` | **GROUND_FX ALL PASS**（fire/water/poison/ice/thunder 5/5 + 泄漏检查） |
| 雷系视觉 | `res://scripts/tests/test_lightning_fx.tscn` | **LIGHTNING FX ALL PASS**（无视觉回归） |
| 冒烟 | `-s res://scripts/tests/smoke_test.gd` | **SMOKE OK** |

运行方式：`Godot_v4.7.1-stable_win64_console.exe --headless --path . <场景>`，
TEMP/TMP/APPDATA 均指向项目 `.tmp`；测试结束无 Godot 进程残留（已核查）。

## 4. 附注
- test_ground_fx 毒雾用例按第2轮报告建议③对齐：毒M3 毒雾弥漫门控（a94b85d 起）要求
  持有 `poison_m3`，用例原只持 `poison_m1`（既有 P3-5 漂移，与本轮修复无关）。
- 本任务未改 data/*.json、scripts/combat/*、scripts/ui/*、scripts/enemies/*、
  scripts/player/*、scenes/、tools/。
