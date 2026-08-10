extends Node2D
## P2-4 火系地面区数组越界回归测试（全流程体验报告-第2轮）
## 复现重入路径：fire_synergy._tick_zones → _zone_hit → 燃烧敌人死亡
## （模拟火M1 灰烬爆炸）→ 重入 _ignite_zones 删除多个 zone → 旧代码继续按
## 调用时记录的下标访问 _zones → get index / remove_at 越界，且函数中止导致
## 本 pass 内后续 zone 不再被 tick（left 不递减）。
## 断言：双 dummy 均死亡（重入真实发生，防空跑）；重入 pass 后剩余 zone 的
## left 仍随 tick 递减（旧代码中止路径下 left_sum 不递减 → FAIL）；
## 8 个 pass 后 _zones 全部过期清空；全程无 SCRIPT ERROR（配合日志 grep）。
## 运行：godot --headless --path . res://scripts/tests/test_fire_zones_reentrant.tscn

const FIRE_SCRIPT := preload("res://scripts/synergies/fire_synergy.gd")

var _failures: Array[String] = []
var _fire: Node
var _deaths := 0


class DummyEnemy:
	extends Node2D

	var hp := 1.0
	var _dead := false
	var _burn_left := 5.0
	var on_death: Callable

	func _init() -> void:
		add_to_group("enemy")

	func take_damage(dmg: int, _el: String, _c: bool) -> void:
		hp -= dmg
		if hp <= 0.0 and not _dead:
			_dead = true
			on_death.call()
			queue_free()


func _ready() -> void:
	GameState.run.items["fire_dragon_breath"] = 1  ## 火M10 龙息：产生火地
	GameState.run.items["fire_ash_blast"] = 1      ## 火M1 灰烬爆炸：引爆火地（重入方）
	_fire = FIRE_SCRIPT.new()
	_fire.name = "FireSynergy"
	add_child(_fire)  ## 挂树后 _zone_hit 的 get_tree() 可用
	_fire.set_process(false)  ## 手动驱动 _tick_zones，精确控制重入时机
	## 8 个 zone 沿 x 排列（x=100*i）。_tick_zones 从尾部倒序：处理到 zone[6] 时
	## dummy 死亡 → 重入引爆删除 zone[4..7] → 旧代码下一轮 _zones[5] 越界。
	for i in 8:
		_fire._on_m10({"element": "fire", "pos": Vector2(100.0 * float(i), 0.0)})
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var z6 := Vector2(600.0, 0.0)
	var d1 := DummyEnemy.new()
	d1.global_position = z6
	## lambda 按值捕获局部变量（z6 / 250.0）
	d1.on_death = func() -> void: _on_ash_blast(z6, 250.0)
	add_child(d1)
	var d2 := DummyEnemy.new()
	d2.global_position = z6 + Vector2(30.0, 0.0)
	## 第二只 dummy 会在首次引爆的 _damage_aoe 中死亡 → 嵌套重入 _ignite_zones
	d2.on_death = func() -> void: _on_ash_blast(z6 + Vector2(30.0, 0.0), 250.0)
	add_child(d2)
	await get_tree().process_frame
	## pass 1：所有 zone tick 归零 → zone_hit → dummy 死亡 → 重入引爆（越界点）
	_fire._tick_zones(0.25)
	_check_pass1()
	## pass 2..8：剩余 zone 的 left 递减至过期（1.5 / 0.25 = 6 个 pass）
	for p in 7:
		_fire._tick_zones(0.25)
	_check_expired()
	_finish()


func _on_ash_blast(center: Vector2, radius: float) -> void:
	## 模拟火M1 灰烬爆炸：重入引爆范围内的火地
	_deaths += 1
	_fire._ignite_zones(center, radius)


func _check_pass1() -> void:
	## 重入引爆删除了距离内的 zone（剩余 3~4 个）；旧代码越界中止会跳过
	## 未处理 zone 的 tick，left 保持 1.5（left_sum=6.0）→ 判定为中止复现
	var zones: Array = _fire.get("_zones")
	if zones.size() < 2 or zones.size() > 5:
		_fail("pass1: 剩余 zone 数量异常（%d，期望 2~5）" % zones.size())
	var left_sum := 0.0
	for z in zones:
		left_sum += float(z["left"])
	if left_sum >= 6.0:
		_fail("pass1: 剩余 zone 未随 tick 递减（left_sum=%.2f）→ 越界中止复现"
				% left_sum)
	else:
		print("[TEST] pass1: 剩余 zone=", zones.size(), " left_sum=", left_sum,
				"（重入后继续正常 tick）")


func _check_expired() -> void:
	var zones: Array = _fire.get("_zones")
	if not zones.is_empty():
		_fail("8 个 pass 后 _zones 未清空（size=%d）：zone 生命周期被中断"
				% zones.size())


func _finish() -> void:
	var zones: Array = _fire.get("_zones")
	if _deaths < 2:
		_fail("重入路径未触发（deaths=%d，期望 ≥2）：用例空跑" % _deaths)
	_check_expired()
	if _failures.is_empty():
		print("[TEST] FIRE_ZONES REENTRANT ALL PASS (zones=%d, deaths=%d)"
				% [zones.size(), _deaths])
		get_tree().quit(0)
	else:
		for f in _failures:
			push_error("[TEST] FAIL: " + f)
		get_tree().quit(1)


func _fail(msg: String) -> void:
	_failures.append(msg)
	print("[TEST] FAIL: " + msg)
