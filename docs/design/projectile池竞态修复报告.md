# projectile 对象池竞态修复报告

- 日期：2026-08-13
- 引擎：Godot 4.7.1（`Godot_v4.7.1-stable_win64_console.exe --headless`）
- 涉及生产文件：`scripts/combat/projectile.gd`（唯一修改的源文件）
- 复现路径：`test_core_shell.gd` 的 whirl split 用例（唯一复现路径）；生产路径为换法术
  `clear_player_projectiles` 后的下一次施法（whirl split 场景必现）

## 一、根因确认

### 1. 复现证据（修复前，test_core_shell）

```text
SCRIPT ERROR: Trying to assign invalid previously freed instance.
   at: obtain (res://scripts/combat/projectile.gd:125)
   GDScript backtrace:
       [0] obtain (projectile.gd:125)
       [1] _spawn_split_minis (projectile.gd:559)
       [2] _test_whirl_split_speed (test_core_shell.gd:281)
SCRIPT ERROR: Invalid access to property or key '_hit_enemies' on a base object of type 'Nil'.
[TEST] FAIL: whirl split: expect 2 minis, got 0
```

### 2. 竞态时序

Godot 的 `queue_free()` 只把节点登记到删除队列，帧末（`flush_delete_queue`）才真正释放。
在这段窗口内，节点仍会照常跑物理帧。因此：

1. 测试/生产清场（`clear_player_projectiles` 或测试 `_clear_projectiles`）对场上弹体逐个
   `queue_free()`，其中瞬发弹（speed=0）尚未爆炸；
2. 下一物理帧：待销毁的瞬发弹仍执行 `_physics_process` → 瞬发分支爆炸 →
   `_explode_at()` → `_retire()` → `recycle(self)` 把**即将销毁**的弹体回收入池
   （此时引用仍有效，入池成功）；
3. 帧末 `flush_delete_queue` 按 pending 的 queue_free 释放该弹体 → 池内残留**死引用**；
4. 下一次施法 `obtain()` 弹到死引用：`var cand: Node = _proj_pool.pop_back()`
   的类型化赋值在 Variant→Node 转换时对已释放实例报硬错误，**中断整个 obtain() 返回 null**；
5. split 小弹生成处 `_spawn_split_minis` 拿到 null → `mini._hit_enemies[...]` 对 Nil
   取值报错 → 0 枚小弹生成（施法静默失效）。

对象池回归时复现计数：测试在 `_test_poison_rapid_fan` 末尾清 3 团瞬发毒雾，恰好产生
3 个死引用，后续 whirl split 的 `obtain()` 必然弹到死引用。

## 二、修复方案（两点，均落在 projectile.gd）

### 修复点 1：`_retire()` 加 `is_queued_for_deletion()` 守卫

```gdscript
func _retire() -> void:
	if is_queued_for_deletion():
		return  # 已被 queue_free 排队销毁：不再入池，交由 pending 销毁
	recycle(self)
```

弹体已被 queue_free 排队销毁时直接跳过回收，杜绝死引用入池（`recycle` 是池的唯一入口，
仅由 `_retire` 调用，守卫一处即封死整条入池链路）。

### 修复点 2：`obtain()` 非类型化取值 + `is_instance_valid()` 判活

```gdscript
while not _proj_pool.is_empty():
	var cand = _proj_pool.pop_back()          # 非类型化取值：死引用不再触发赋值硬错误
	if cand is Node and is_instance_valid(cand):
		proj = cand
		_proj_reused += 1
		break
```

弹到死引用时直接丢弃继续取下一个；全部失效则照常实例化新弹（既有 fallback 分支），
`obtain()` 永不因死引用中断返回 null。这是对修复点 1 的第二道防线（兜底池内任何历史/残余
脏引用）。

## 三、测试结果

全部使用 `Godot_v4.7.1-stable_win64_console.exe --headless`，`TEMP/TMP/APPDATA`
指向 `.tmp`，进程真实退出码（`$LASTEXITCODE`）判定：

| 测试 | 结果 | 退出码 |
| --- | --- | --- |
| `test_core_shell.gd`（whirl split 用例，唯一复现路径） | CORE SHELL OK | 0 |
| `test_core_shell.gd`（二跑，稳定性复核） | CORE SHELL OK | 0 |
| `test_projectile_pool.gd`（对象池复用回归） | PROJECTILE POOL ALL PASS | 0 |
| `smoke_test.gd` | SMOKE OK | 0 |
| `test_projectile_clear_recast.gd`（专项断言，新建） | PROJECTILE CLEAR-RECAST OK | 0 |

专项断言稳定性：连续 12 次运行全部 PASS（排除抖动后 12/12）。

> 说明：测试输出中 "Failed to read the root certificate store" 是 headless 窗口环境
> 的既有启动噪音，与本次修复无关；退出时 "RID allocations leaked" 是测试场景不清理
> 静态池的既有退出噪音（修复前同样存在），不影响判定。

## 四、专项断言（test_projectile_clear_recast.gd）

新增场景测试，忠实复刻生产路径"施法 → 换法术清场 → 再施法"：

1. 施放 3 团瞬发毒雾（`poison_cloud`，shots=3）；
2. 调用生产同款 `clear_player_projectiles(get_tree())` 清场，等 2 个物理帧
   （第 1 帧是待销毁弹体的竞态窗口，第 2 帧等帧末 `flush_delete_queue` 落定）；
3. 断言池内无死引用（遍历 `_proj_pool` 全部 `is_instance_valid`）；
4. 再施法 `fireball` × split=2 外壳，命中敌人后断言：父弹正常生成（`obtain` 未中断）、
   2 枚 split 小弹正常生成、速度 ≥ 240、伤害 = 父弹 × 0.6、挂树存活。

测试对旧代码的判真性已复核：临时还原 buggy 代码后运行，精确失败于
"池内残留 3 个死引用" + "Trying to assign invalid previously freed instance" +
"父弹（split=2）未生成"，退出码 1；恢复修复后全绿。

测试隔离说明：`GameState.run.grid` / `run.wands` 在用例开头清空——caster 的
`_physics_process` 会按默认开局网格自动施法、法杖 shape mods 会改变弹体数值，
不清空会射入未知弹体干扰断言（曾观测到"幽灵弹先命中敌人"导致的抖动，隔离后 12/12 稳定）。

## 五、改动清单

- 修改：`scripts/combat/projectile.gd`
  - `obtain()`：池弹出改非类型化取值 + `cand is Node and is_instance_valid(cand)` 判活；
  - `_retire()`：`is_queued_for_deletion()` 守卫，排队销毁的弹体不再回收入池。
- 新增：`scripts/tests/test_projectile_clear_recast.gd` + `.tscn`（专项断言，见上节）；
- 新增：`docs/design/projectile池竞态修复报告.md`（本文档）。

未改动任何其他生产脚本、测试脚本与数据文件；`.git` 未触碰。
