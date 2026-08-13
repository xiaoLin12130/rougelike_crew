extends Node2D
## 怪物技能差异化 v2 测试（P0/P1/P2，docs/design/怪物技能差异化实施报告.md）
## ① 31 怪均有 skills 数组（2 技能），技能1.form != 技能2.form，技能1.type == behavior
## ② 调度器能触发技能2（force：_skill2_cd=0 → 等待 → skill2_cast_count 增加）
## ③ enemy_bullet bounce/status 参数生效（撞墙反弹、命中施加状态）
## ④ 逐怪 debug_cast 技能2 不报错（覆盖全部 type）
## 运行：godot --headless --path . res://scripts/tests/test_enemy_skills_v2.tscn

const ENEMY_SCENE := preload("res://scenes/game/enemy.tscn")
const BULLET_SCENE := preload("res://scenes/game/enemy_bullet.tscn")

var _failures: Array[String] = []
var _container: Node2D
var _dummy: CharacterBody2D

class SlowTarget:
	extends CharacterBody2D
	var slowed := false
	func apply_slow(_f: float, _d: float) -> void:
		slowed = true

func _ready() -> void:
	GameState.run.level = 1
	GameState.run.loop = 1
	_container = Node2D.new()
	_container.name = "SkillTestContainer"
	add_child(_container)
	_spawn_dummy()
	await _test_data()
	await _test_scheduler_trigger()
	await _test_bullet_params()
	await _test_cast_sweep()
	_report()
	_dummy.queue_free()
	_container.queue_free()
	get_tree().quit(0 if _failures.is_empty() else 1)

func _fail(msg: String) -> void:
	_failures.append(msg)
	push_error("[TEST] FAIL: " + msg)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _spawn_dummy() -> void:
	_dummy = CharacterBody2D.new()
	_dummy.name = "TestDummy"
	_dummy.add_to_group("player")
	var shape := CircleShape2D.new()
	shape.radius = 10.0
	var col := CollisionShape2D.new()
	col.shape = shape
	_dummy.add_child(col)
	add_child(_dummy)
	_dummy.global_position = Vector2(480, 320)

func _enemy_table() -> Array:
	return GameState.tables.get("enemies", {}).get("enemies", [])

func _test_data() -> void:
	## ① 31 怪双技能数据完整、形态差异化
	var enemies := _enemy_table()
	if enemies.size() != 31:
		_fail("enemies 数量 != 31 (%d)" % enemies.size())
	var forms: Dictionary = {}
	for e in enemies:
		var eid := str(e.get("id", ""))
		var sk: Array = e.get("skills", [])
		if sk.size() != 2:
			_fail("%s: skills 数量 != 2 (%d)" % [eid, sk.size()])
			continue
		var s1: Dictionary = sk[0]
		var s2: Dictionary = sk[1]
		if str(s1.get("form", "")) == "" or str(s2.get("form", "")) == "":
			_fail("%s: 技能缺少 form" % eid)
		if str(s1.get("form", "")) == str(s2.get("form", "")):
			_fail("%s: 技能1/技能2 形态相同 (%s)" % [eid, s1.get("form")])
		if str(e.get("behavior", "")) != str(s1.get("type", "")):
			_fail("%s: 技能1 type != behavior" % eid)
		if not s2.has("cooldown") or float(s2.get("cooldown", 0.0)) <= 0.0:
			_fail("%s: 技能2 缺少有效 cooldown" % eid)
		forms[str(s1.get("form", ""))] = true
		forms[str(s2.get("form", ""))] = true
	# 双技能合计形态覆盖 >= 10 类（方案 §4.1 为 19 类）
	if forms.size() < 10:
		_fail("形态覆盖过少 (%d < 10)" % forms.size())

func _test_scheduler_trigger() -> void:
	## ② 每怪强制触发调度器，断言技能2 被施放
	for e in _enemy_table():
		var eid := str(e.get("id", ""))
		var sk: Array = e.get("skills", [])
		if sk.size() < 2:
			continue
		var s2: Dictionary = sk[1]
		var enemy := ENEMY_SCENE.instantiate()
		enemy.setup(eid, 1, 1)
		enemy.global_position = _dummy.global_position + Vector2(-150, 0)
		_container.add_child(enemy)
		await _frames(2)
		var type := str(s2.get("type", ""))
		if type == "rage" or type == "self_destruct":
			enemy.hp = enemy.max_hp * 0.3  # 血线条件
		enemy._skill2_cd = 0.0
		var before: int = enemy.skill2_cast_count
		await _frames(60)  # 1 秒（调度器每物理帧检查）
		var after: int = enemy.skill2_cast_count
		if after <= before:
			_fail("%s: 调度器未触发技能2 (%s)" % [eid, s2.get("id")])
		elif str(enemy.last_skill2_id) != str(s2.get("id", "")):
			_fail("%s: 技能2 id 不符 (%s != %s)" % [eid, enemy.last_skill2_id, s2.get("id")])
		# 清理该怪及技能产物（召唤/图腾/弹幕等随容器释放）
		enemy.queue_free()
		await _frames(1)

func _test_bullet_params() -> void:
	## ③ enemy_bullet bounce/status 参数生效
	# 3a. 默认向后兼容：status/bounce 缺省为空/0
	var b0 := BULLET_SCENE.instantiate()
	b0.setup(Vector2.ZERO, Vector2.RIGHT, 100.0, 5, 400.0)
	_container.add_child(b0)
	await _frames(2)
	if b0._status != "" or b0._bounce_left != 0:
		_fail("bullet: 默认 status/bounce 应为空/0")
	b0.queue_free()
	# 3b. bounce：撞墙反弹一次，方向翻转、次数消耗
	var b1 := BULLET_SCENE.instantiate()
	b1.setup(Vector2(100, 100), Vector2(-1, 0), 100.0, 5, 500.0, false, 3.0, 4.0,
		"", "", 0.0, 1)
	_container.add_child(b1)
	await _frames(2)
	b1.global_position = Vector2(20, 100)  # 推到竞技场左边界外
	b1._physics_process(0.016)
	if b1._bounce_left != 0:
		_fail("bounce: 反弹后未消耗 bounce 次数")
	if b1._dir.x < 0.0:
		_fail("bounce: 反弹后方向未翻转 (x=%f)" % b1._dir.x)
	b1.queue_free()
	# 3c. status：命中带 apply_slow 的目标会施加 slow
	var b2 := BULLET_SCENE.instantiate()
	b2.setup(Vector2(200, 200), Vector2(1, 0), 100.0, 5, 500.0, false, 3.0, 4.0,
		"", "slow", 1.5, 0)
	_container.add_child(b2)
	await _frames(2)
	if b2._status != "slow" or absf(b2._status_duration - 1.5) > 0.01:
		_fail("bullet: status 参数未写入")
	var target := SlowTarget.new()
	target.name = "StatusTarget"
	target.add_to_group("player")
	target.global_position = Vector2(220, 200)
	_container.add_child(target)
	b2._on_body(target)
	if not target.slowed:
		_fail("status: slow 未施加到目标")
	b2.queue_free()
	target.queue_free()

func _test_cast_sweep() -> void:
	## ④ 逐怪 debug_cast 技能2，确保全部 type 可施放不报错
	for e in _enemy_table():
		var eid := str(e.get("id", ""))
		var sk: Array = e.get("skills", [])
		if sk.size() < 2:
			continue
		var enemy := ENEMY_SCENE.instantiate()
		enemy.setup(eid, 1, 1)
		enemy.global_position = _dummy.global_position + Vector2(-160, 0)
		_container.add_child(enemy)
		await _frames(2)
		enemy.debug_cast_skill2(1)
		await _frames(45)  # 0.75s 观察（蓄力/施法/特效）
		enemy.queue_free()
		await _frames(1)

func _report() -> void:
	if _failures.is_empty():
		print("ENEMY_SKILLS_V2 ALL PASS")
	else:
		for f in _failures:
			push_error("[TEST] FAIL: " + f)
