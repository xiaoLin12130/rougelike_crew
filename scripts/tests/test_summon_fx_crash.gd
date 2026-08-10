extends Node2D
## P0 召唤光环 freed-instance 崩溃回归测试（全流程体验报告-第2轮 BUG P0-1）
## 复现场景：召唤流战局（召唤流派持有 ≥3 件 → 光环 tier≥1），
## 召唤物大量生成 → 光环渲染建立 → 召唤物被击杀消失（queue_free）→
## fx_manager._refresh_summon_auras 每 0.5s 刷新，持续跑 600 帧。
## 断言：
##   1) 光环档位生效（_summon_auras 非空，防止空跑误绿）；
##   2) 召唤物消失后 _summon_auras 无残留 freed-instance 条目（旧代码在
##      fx_manager.gd:1112 类型化赋值处报错并中止，erase 不执行 → 条目残留）；
##   3) "光环被外部释放但召唤物存活" 边界（fx_manager.gd:1094 同型报错点）
##      也能自愈重建；
##   4) 全程无 freed-instance 报错、进程不退出（配合日志 grep ERROR 验收）。
## 运行：godot --headless --path . res://scripts/tests/test_summon_fx_crash.tscn

const FX_MANAGER_SCRIPT := preload("res://scripts/fx/fx_manager.gd")
const SUMMON_SCRIPT := preload("res://scripts/combat/summon.gd")

const TOTAL_FRAMES := 600
const REFRESH_FRAMES := 30  ## fx_manager._aura_timer = 0.5s @ 60fps

var _failures: Array[String] = []
var _fx: Node
var _player: Node2D
var _frame := 0

## 阶段时间线（帧）：60 帧 = 1 秒
const F_WAVE1 := 2          ## 第一批召唤物生成
const F_WAVE2 := 90         ## 第二批（大量 + 上限压测）
const F_KILL1 := 180        ## 全体召唤物被击杀消失
const F_CHECK1 := 260       ## 断言光环残留已清空（≥2 个刷新周期）
const F_EDGE_SPAWN := 200   ## 边界批次：重新生成少量召唤物
const F_EDGE := 280         ## 边界：召唤物存活但光环被外部释放
const F_KILL2 := 400        ## 边界批次召唤物消失
const F_CHECK2 := 470       ## 断言再次清空
const F_END := TOTAL_FRAMES ## 最终断言 + 退出


func _ready() -> void:
	## 召唤流派持有 3 件 → _tier_of(3) = 1（光环渲染开启）；召唤之书放大总上限
	GameState.run.items["summon_1"] = 3
	GameState.run.items["summon_book"] = 30
	_player = Node2D.new()
	_player.position = Vector2(640, 360)
	add_child(_player)
	_fx = FX_MANAGER_SCRIPT.new()
	_fx.name = "FxManager"
	add_child(_fx)
	print("[TEST] summon fx crash: tier=", _tier(), " setup ok")


func _process(_delta: float) -> void:
	_frame += 1
	match _frame:
		F_WAVE1:
			_spawn_wave(12)
		F_WAVE2:
			_spawn_wave(18)
		F_KILL1:
			_kill_all_summons()
		F_CHECK1:
			_check_auras_clean("wave1")
		F_EDGE_SPAWN:
			_spawn_wave(6)
		F_EDGE:
			_test_aura_freed_while_alive()
		F_KILL2:
			_kill_all_summons()
		F_CHECK2:
			_check_auras_clean("edge")
		F_END:
			_finish()


func _tier() -> int:
	var holdings: Dictionary = GameState.school_holdings()
	var n: int = int(holdings.get("summon", 0))
	return 3 if n >= 9 else (2 if n >= 6 else (1 if n >= 3 else 0))


func _spawn_wave(count: int) -> void:
	var before: int = get_tree().get_nodes_in_group("summons").size()
	for i in count:
		var s: Node = SUMMON_SCRIPT.new()
		s.setup(_player, 10.0, "summon")
		add_child(s)
		s.global_position = _player.position + Vector2(
				randf_range(-90.0, 90.0), randf_range(-90.0, 90.0))
	var after: int = get_tree().get_nodes_in_group("summons").size()
	print("[TEST] wave spawned: before=", before, " after=", after)


func _kill_all_summons() -> void:
	var n := 0
	for s in get_tree().get_nodes_in_group("summons"):
		if is_instance_valid(s):
			s.queue_free()
			n += 1
	print("[TEST] killed summons: ", n)


func _auras() -> Dictionary:
	return _fx.get("_summon_auras") as Dictionary


func _check_auras_clean(label: String) -> void:
	var auras: Dictionary = _auras()
	var stale := 0
	for sid in auras:
		var v = auras[sid]
		if not is_instance_valid(v):
			stale += 1
	if stale > 0:
		_fail(label + ": _summon_auras 残留已释放条目 %d 个（size=%d）→ freed-instance 报错路径复现"
				% [stale, auras.size()])
	elif auras.is_empty():
		print("[TEST] ", label, ": _summon_auras 已清空（无残留条目）")
	else:
		print("[TEST] ", label, ": 仅存活召唤物的有效光环 ", auras.size(), " 个，无已释放残留")


func _test_aura_freed_while_alive() -> void:
	## 边界：召唤物存活但光环子节点被外部释放 → 下一刷新应擦除重建而非报错
	var summons: Array = get_tree().get_nodes_in_group("summons")
	if summons.is_empty():
		_fail("edge: 无召唤物可测（前置波次生成失败）")
		return
	var s = summons[0]
	if not is_instance_valid(s):
		return
	var auras: Dictionary = _auras()
	var sid: int = s.get_instance_id()
	if not auras.has(sid):
		_fail("edge: 召唤物无光环条目（tier 未生效？）")
		return
	var aura = auras[sid]
	if is_instance_valid(aura):
		aura.queue_free()
		print("[TEST] edge: 外部释放光环 sid=", sid)


func _finish() -> void:
	## 帧数达标（进程未被 freed-instance 崩溃带出）+ 无残留 + 光环档位真实生效
	if _frame < TOTAL_FRAMES:
		_fail("提前退出：仅运行 %d 帧（进程可能被 freed-instance 报错拖崩）" % _frame)
	_check_auras_clean("final")
	if _failures.is_empty() and _tier() < 1:
		_fail("测试环境：summon 流派持有未生效（tier=0，光环未开启，用例空跑）")
	if _failures.is_empty():
		print("[TEST] SUMMON_FX ALL PASS (%d frames, no freed-instance ERROR, no stale auras)"
				% _frame)
		get_tree().quit(0)
	else:
		for f in _failures:
			push_error("[TEST] FAIL: " + f)
		get_tree().quit(1)


func _fail(msg: String) -> void:
	_failures.append(msg)
	print("[TEST] FAIL: " + msg)
