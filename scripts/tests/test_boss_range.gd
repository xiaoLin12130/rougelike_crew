extends Node2D
## Boss 技能范围一致性测试（2026-08-13）：
## 断言每个 Boss 技能的 telegraph（视觉红圈/红线）半径 == 实际伤害判定半径。
## 两层验证：
##  ① 几何层：遍历 enemies.json 全部 Boss 技能，cast 后断言 telegraph 半径/宽度 == 伤害半径/宽度；
##  ② 运行时边界层：把"玩家"放在视觉边缘 ±0.5px，验证实际伤害在圈内命中、圈外不命中
##     （覆盖 leap / root_zone / lava_eruption / meteor / blink / wall / spike_trail /
##       charge / beam / whirl_laser / sweep 全部范围类技能）。
## Run: godot --headless --path . res://scripts/tests/test_boss_range.tscn

## -s 脚本编译早于 autoload 注册：禁止 preload 依赖 autoload 的场景，运行时 load
const BOSS_SCENE_PATH := "res://scenes/game/boss.tscn"

var failures: Array[String] = []
var _frame := 0
var _hits := 0
var _boss: CharacterBody2D
var _dummy: CharacterBody2D

func _ready() -> void:
	await _run()
	if failures.is_empty():
		print("BOSS RANGE TESTS OK")
	else:
		for f in failures:
			push_error("BOSS RANGE FAIL: " + f)
	get_tree().quit(0 if failures.is_empty() else 1)

func _fail(msg: String) -> void:
	failures.append(msg)
	print("[FAIL] " + msg)

func _gs() -> Node:
	return get_tree().root.get_node_or_null("GameState")

func _bus() -> Node:
	return get_tree().root.get_node_or_null("EventBus")

func _run() -> void:
	var gs := _gs()
	if gs == null:
		_fail("GameState autoload missing")
		return
	gs.run.level = 1
	gs.run.loop = 1
	_spawn_dummy()
	await _frames(2)
	await _test_geometry_all_bosses()
	await _test_boundary_types()
	_free_boss()
	_dummy.queue_free()
	await _frames(2)

# ================= 辅助 =================

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _spawn_dummy() -> void:
	_dummy = CharacterBody2D.new()
	_dummy.name = "RangeDummy"
	_dummy.add_to_group("player")
	var shape := CircleShape2D.new()
	shape.radius = 6.0
	var col := CollisionShape2D.new()
	col.shape = shape
	_dummy.add_child(col)
	add_child(_dummy)
	_dummy.global_position = Vector2(1000, 620)
	_bus().player_hit.connect(func(_dmg: int, _pos: Vector2) -> void: _hits += 1)

func _spawn_boss(boss_id: String) -> void:
	if is_instance_valid(_boss):
		_boss.queue_free()
	_boss = load(BOSS_SCENE_PATH).instantiate()
	_boss.setup_boss(boss_id, 1, 1)
	_boss.global_position = Vector2(300, 360)
	add_child(_boss)
	_boss.auto_casts = false
	await _frames(2)

func _free_boss() -> void:
	if is_instance_valid(_boss):
		_boss.queue_free()
		_boss = null
	await _frames(2)

func _dummy_at(pos: Vector2) -> void:
	_dummy.global_position = pos
	await get_tree().physics_frame

func _cast(skill: Dictionary) -> void:
	_hits = 0
	_boss.debug_cast(skill)
	await _frames(3)

func _count_hits() -> int:
	return _hits

# ================= ① 几何层：全部真实 Boss 技能 =================

func _test_geometry_all_bosses() -> void:
	var bosses: Array = _gs().tables.get("enemies", {}).get("bosses", [])
	for b in bosses:
		var boss_id: String = str(b.get("id", ""))
		if boss_id == "":
			continue
		await _spawn_boss(boss_id)
		for sk in b.get("skills", []):
			var skill: Dictionary = sk
			if str(skill.get("telegraph", "")) == "":
				continue
			await _dummy_at(Vector2(700, 360))
			await _cast(skill)
			_check_geometry(boss_id + "/" + str(skill.get("id", "?")), skill)
			await _frames(8)

func _check_geometry(tag: String, skill: Dictionary) -> void:
	var type: String = str(skill.get("type", ""))
	var radius := float(skill.get("radius", 40.0))
	match type:
		"leap", "root_zone", "lava_eruption", "meteor", "blink", "wall", "spike_trail":
			for t in _boss._telegraphs:
				if str(t.get("kind", "")) == "circle":
					if absf(float(t.get("radius", 0.0)) - radius) > 0.01:
						_fail("%s 几何: 预告圈半径 %.1f != 伤害半径 %.1f" % [tag, float(t.get("radius", 0.0)), radius])
				elif str(t.get("kind", "")) == "dot":
					if absf(float(t.get("radius", 0.0)) - radius) > 0.01:
						_fail("%s 几何: 预告点半径 %.1f != 伤害半径 %.1f" % [tag, float(t.get("radius", 0.0)), radius])
		"charge":
			for t in _boss._telegraphs:
				if str(t.get("kind", "")) == "line":
					if absf(float(t.get("width", 0.0)) - _boss.CHARGE_HIT_DIST * 2.0) > 0.01:
						_fail("%s 几何: 预告线宽 %.1f != 冲撞判定直径 %.1f" % [tag, float(t.get("width", 0.0)), _boss.CHARGE_HIT_DIST * 2.0])
		"beam", "whirl_laser", "sweep":
			for t in _boss._telegraphs:
				if str(t.get("kind", "")) == "line":
					if absf(float(t.get("width", 0.0)) - _boss.BEAM_HALF_WIDTH * 2.0) > 0.01:
						_fail("%s 几何: 预告线宽 %.1f != 光束判定宽度 %.1f" % [tag, float(t.get("width", 0.0)), _boss.BEAM_HALF_WIDTH * 2.0])
		"ring_barrage", "spiral", "homing_shot":
			for t in _boss._telegraphs:
				if str(t.get("kind", "")) != "dot" or float(t.get("radius", 0.0)) > 10.0:
					_fail("%s 几何: 发射点应是小圈（radius<=10），got kind=%s r=%.1f" % [tag, str(t.get("kind", "")), float(t.get("radius", 0.0))])
		_:
			_fail("%s 几何: 未覆盖类型 %s" % [tag, type])

# ================= ② 运行时边界层：视觉边缘 ±0.5px =================

func _test_boundary_types() -> void:
	await _spawn_boss("slime_king")
	await _circle_boundary(_skill_of("slime_king", "leap"), 120.0, "leap")
	await _spawn_boss("tree_golem")
	await _circle_boundary(_skill_of("tree_golem", "root_vine"), 90.0, "root_zone")
	await _spawn_boss("imp_king")
	var erupt := _skill_of("imp_king", "lava_eruption").duplicate()
	erupt["count"] = 1
	await _circle_boundary(erupt, 58.0, "lava_eruption")
	await _spawn_boss("final_god")
	var meteor := _skill_of("final_god", "meteor_storm").duplicate()
	meteor["count"] = 1
	await _circle_boundary(meteor, 70.0, "meteor")
	await _spawn_boss("ancient_guardian")
	await _circle_boundary(_skill_of("ancient_guardian", "guardian_blink"), 110.0, "blink")
	await _spawn_boss("imp_king")
	await _wall_boundary(_skill_of("imp_king", "fire_wall"))
	await _spawn_boss("tree_golem")
	await _spike_boundary(_skill_of("tree_golem", "root_spikes"))
	await _spawn_boss("imp_king")
	await _charge_boundary(_skill_of("imp_king", "lava_charge"))
	await _spawn_boss("ancient_guardian")
	await _beam_boundary(_skill_of("ancient_guardian", "light_beam"))
	await _spawn_boss("final_god")
	await _whirl_boundary(_skill_of("final_god", "whirl_laser"))
	await _spawn_boss("skeleton_king")
	await _sweep_boundary(_skill_of("skeleton_king", "bone_sweep"))

func _skill_of(boss_id: String, skill_id: String) -> Dictionary:
	for b in _gs().tables.get("enemies", {}).get("bosses", []):
		if str(b.get("id", "")) != boss_id:
			continue
		for s in b.get("skills", []):
			if str(s.get("id", "")) == skill_id:
				return s
	return {}

func _first_damage_center() -> Vector2:
	## 伤害中心：逐点/落点类取 eruption_queue[0]（spike/wall/eruption/meteor），
	## 追踪落点类取 _locked_target（leap/root_zone/blink）
	if not _boss._eruption_queue.is_empty():
		return Vector2(_boss._eruption_queue[0])
	var lt := Vector2(_boss._locked_target)
	if not lt.is_zero_approx():
		return Vector2(_boss._locked_target)
	for t in _boss._telegraphs:
		if str(t.get("kind", "")) in ["circle", "dot"]:
			return Vector2(t.get("pos", Vector2.ZERO))
	return Vector2.ZERO

func _circle_boundary(skill: Dictionary, radius: float, tag: String) -> void:
	## 圆圈类：cast 锁定落点/伤害点后，再把"玩家"移到视觉边缘 ±0.5px
	## （落点类技能目标在 windup 起锁定，移动玩家不影响本次落点）。
	var window := int(_cast_window(skill) * 60.0) + 12
	# 命中：圈内 r-0.5
	await _dummy_at(Vector2(700, 360))
	await _cast(skill)
	var center: Vector2 = _first_damage_center()
	await _dummy_at(center + Vector2(radius - 0.5, 0))
	await _frames(window)
	if _count_hits() <= 0:
		_fail("%s 边界: 圈内(r-0.5)未命中" % tag)
	# 未命中：圈外 r+0.5（重新 cast，按本次落点计算）
	await _dummy_at(Vector2(700, 360))
	await _cast(skill)
	var center2: Vector2 = _first_damage_center()
	# 圈外方向避开其它伤害点（spike 间距 64 时 +X 可能落进相邻点），两者都危险则跳过
	var miss_dir := Vector2.RIGHT
	var other_pts: Array = _boss._eruption_queue.duplicate()
	other_pts.erase(center2)
	var safe := true
	for op in other_pts:
		if Vector2(op).distance_to(center2 + miss_dir * (radius + 0.5)) < radius + 0.5:
			safe = false
	if not safe:
		miss_dir = Vector2.LEFT
		safe = true
		for op in other_pts:
			if Vector2(op).distance_to(center2 + miss_dir * (radius + 0.5)) < radius + 0.5:
				safe = false
	if safe:
		await _dummy_at(center2 + miss_dir * (radius + 0.5))
		await _frames(window)
		if _count_hits() > 0:
			_fail("%s 边界: 圈外(r+0.5)误命中" % tag)
	else:
		print("[SKIP] %s 边界: 无安全圈外方向，跳过 miss 断言" % tag)
	await _dummy_at(Vector2(1000, 620))
	print("[OK] %s 边界 radius=%.1f 圈内命中/圈外不命中" % [tag, radius])

func _wall_boundary(skill: Dictionary) -> void:
	## 弹幕墙：相邻落点间距 >= 165px > 2×46.5，任一点边界互不干扰
	await _circle_boundary(skill, 46.0, "wall")

func _spike_boundary(skill: Dictionary) -> void:
	## 地刺：相邻刺点间距 64 > 2×34.5，边界互不干扰
	await _circle_boundary(skill, 34.0, "spike_trail")

func _charge_boundary(skill: Dictionary) -> void:
	## 冲撞：cast 锁定方向后（windup 内）再把玩家放到路径上/路径旁
	var dash_dist: float = _boss.speed * float(skill.get("speed_mult", 4.0)) * _boss.CHARGE_CAST_TIME
	var window := int(_cast_window(skill) * 60.0) + 12
	# 命中：路径上
	await _dummy_at(Vector2(700, 360))
	await _cast(skill)
	var dir: Vector2 = Vector2(_boss._locked_dir)
	var on_path: Vector2 = _boss.global_position + dir * minf(dash_dist * 0.5, 200.0)
	await _dummy_at(on_path)
	await _frames(window)
	if _count_hits() <= 0:
		_fail("charge 边界: 路径上未命中")
	# 未命中：路径旁 34.5px（> 判定半径 34）
	await _dummy_at(Vector2(700, 360))
	await _cast(skill)
	var dir2: Vector2 = Vector2(_boss._locked_dir)
	var off2: Vector2 = dir2.orthogonal() * (_boss.CHARGE_HIT_DIST + 0.5)
	await _dummy_at(_boss.global_position + dir2 * minf(dash_dist * 0.5, 200.0) + off2)
	await _frames(window)
	if _count_hits() > 0:
		_fail("charge 边界: 路径旁(>34)误命中")
	await _dummy_at(Vector2(1000, 620))
	print("[OK] charge 边界 hit=%.1fpx 路径内命中/路径外不命中" % _boss.CHARGE_HIT_DIST)

func _beam_boundary(skill: Dictionary) -> void:
	await _dummy_at(_boss.global_position + Vector2(200, 0))
	await _cast(skill)
	await _frames(int(_cast_window(skill) * 60.0) + 12)
	if _count_hits() <= 0:
		_fail("beam 边界: 射程内未命中")
	await _dummy_at(_boss.global_position + Vector2(350, 0))
	await _cast(skill)
	await _frames(int(_cast_window(skill) * 60.0) + 12)
	if _count_hits() > 0:
		_fail("beam 边界: 射程外误命中")
	await _dummy_at(Vector2(1000, 620))
	print("[OK] beam 边界 range=%.0f 射程内命中/射程外不命中" % _boss.BEAM_RANGE)

func _whirl_boundary(skill: Dictionary) -> void:
	await _dummy_at(_boss.global_position + Vector2(200, 0))
	await _cast(skill)
	await _frames(int(_cast_window(skill) * 60.0) + 12)
	if _count_hits() <= 0:
		_fail("whirl 边界: 射程内未命中")
	await _dummy_at(_boss.global_position + Vector2(350, 0))
	await _cast(skill)
	await _frames(int(_cast_window(skill) * 60.0) + 12)
	if _count_hits() > 0:
		_fail("whirl 边界: 射程外误命中")
	await _dummy_at(Vector2(1000, 620))
	print("[OK] whirl 边界 range=%.0f 射程内命中/射程外不命中" % _boss.BEAM_RANGE)

func _sweep_boundary(skill: Dictionary) -> void:
	## 扇形扫：cast 锁定扇形后（windup 内）再放玩家，测起扫方向/终角外/超射程
	var sweep_angle := float(skill.get("sweep_angle", 120.0))
	var window := int(_cast_window(skill) * 60.0) + 12
	# 命中：起扫方向
	await _dummy_at(Vector2(700, 360))
	await _cast(skill)
	await _dummy_at(_boss.global_position + Vector2.from_angle(_boss._sweep_start_angle) * 200.0)
	await _frames(window)
	if _count_hits() <= 0:
		_fail("sweep 边界: 扇形内未命中")
	# 未命中：超出终角 5°
	await _dummy_at(Vector2(700, 360))
	await _cast(skill)
	await _dummy_at(_boss.global_position + Vector2.from_angle(_boss._sweep_end_angle + deg_to_rad(5.0)) * 200.0)
	await _frames(window)
	if _count_hits() > 0:
		_fail("sweep 边界: 扇形外误命中")
	# 未命中：超射程
	await _dummy_at(Vector2(700, 360))
	await _cast(skill)
	await _dummy_at(_boss.global_position + Vector2.from_angle(_boss._sweep_start_angle + deg_to_rad(sweep_angle * 0.5)) * 350.0)
	await _frames(window)
	if _count_hits() > 0:
		_fail("sweep 边界: 超射程误命中")
	await _dummy_at(Vector2(1000, 620))
	print("[OK] sweep 边界 angle=%.0f 扇形内命中/外与超程不命中" % sweep_angle)

func _cast_window(skill: Dictionary) -> float:
	match str(skill.get("type", "")):
		"leap":
			return float(skill.get("windup", 0.6)) + 0.6
		"root_zone":
			return float(skill.get("windup", 0.8)) + 0.8
		"lava_eruption", "meteor":
			return float(skill.get("windup", 0.9)) + float(skill.get("count", 3)) * 0.3 + 0.2
		"charge":
			return float(skill.get("windup", 0.8)) + 0.9
		"beam":
			return float(skill.get("windup", 1.0)) + float(skill.get("duration", 1.2))
		"whirl_laser":
			return float(skill.get("windup", 1.0)) + float(skill.get("duration", 2.0))
		"sweep":
			return float(skill.get("windup", 1.0)) + float(skill.get("duration", 1.6))
		"blink":
			return float(skill.get("windup", 0.9)) + 0.3
		"wall":
			return float(skill.get("windup", 0.9)) + float(skill.get("delay", 0.6)) + float(skill.get("interval", 0.3)) * float(skill.get("count", 8)) + 0.3
		"spike_trail":
			return float(skill.get("windup", 0.8)) + float(skill.get("delay", 0.6)) + float(skill.get("interval", 0.3)) * float(skill.get("count", 6)) + 0.3
		_:
			return 1.5
