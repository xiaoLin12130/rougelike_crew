extends Node2D
## ????????P1 ?????docs/design/??????.md ?? 3?
## ???? ?? spawn 100 ???????????????
##       ? ??/??????????????????
##       ? ??????????????????????
## Run: godot --headless --path . res://scripts/tests/test_projectile_pool.tscn

const PROJECTILE_SCRIPT := preload("res://scripts/combat/projectile.gd")
const ENEMY_SCENE := preload("res://scenes/game/enemy.tscn")
const PROJ_POOL_MAX := 48

var _failures: Array[String] = []
var _container: Node2D


func _ready() -> void:
	GameState.run.crit_chance = 0.0  # ???????????
	_container = Node2D.new()
	_container.name = "ProjContainer"
	add_child(_container)
	await _test_obtain_recycle()
	await _test_reuse_bounds()
	await _test_state_reset()
	await _test_hit_recycle()
	PROJECTILE_SCRIPT.clear_pool()
	await get_tree().process_frame
	if _failures.is_empty():
		print("[TEST] PROJECTILE POOL ALL PASS")
		get_tree().quit(0)
	else:
		for f in _failures:
			push_error("[TEST] FAIL: " + f)
		get_tree().quit(1)


func _fail(msg: String) -> void:
	_failures.append(msg)
	print("[TEST] FAIL: " + msg)


func _live_proj() -> int:
	## ????????
	var n := 0
	for c in _container.get_children():
		if c.get_script() == PROJECTILE_SCRIPT:
			n += 1
	return n


func _stats() -> Dictionary:
	return PROJECTILE_SCRIPT.projectile_pool_stats()


func _spawn_batch(n: int, speed: float = 300.0, range: float = 150.0) -> void:
	## ???? spawn????????????????
	for i in n:
		var dir := Vector2.from_angle(TAU * float(i) / float(maxi(n, 1)))
		PROJECTILE_SCRIPT.obtain({
			"position": Vector2(600, 360),
			"direction": dir,
			"speed": speed,
			"range": range,
			"damage": 0.0,
			"element": "fire",
			"aoe": 0.0,
			"mods": {},
		}, _container)


func _test_obtain_recycle() -> void:
	## ? 100 ??????? ? ?????????
	var before: Dictionary = _stats()
	_spawn_batch(100)
	await get_tree().process_frame
	var live := _live_proj()
	if live != 100:
		_fail("spawn 100 ????? 100??? %d" % live)
	# ?? 150 / ?? 300 = 0.5s ???? 1.2s ??
	await get_tree().create_timer(1.2).timeout
	live = _live_proj()
	if live != 0:
		_fail("??????????????? %d" % live)
	var after: Dictionary = _stats()
	if after.created - before.created <= 0:
		_fail("created ???")
	print("[TEST] projectile pool obtain/recycle ? OK (created=%d)" % (after.created - before.created))


func _test_reuse_bounds() -> void:
	## ? ??? 100 ???????created ??????????????
	var before: Dictionary = _stats()
	_spawn_batch(100)
	await get_tree().create_timer(1.2).timeout
	var after: Dictionary = _stats()
	var gain: int = after.created - before.created
	if gain >= 100:
		_fail("?????? %d ???????" % gain)
	if after.reused - before.reused <= 0:
		_fail("????? > 0")
	if after.idle > PROJ_POOL_MAX:
		_fail("??? %d ??? %d" % [after.idle, PROJ_POOL_MAX])
	if _live_proj() != 0:
		_fail("???????? %d" % _live_proj())
	# ???????created??????? 100 + ???????????????
	var third: Dictionary = _stats()
	_spawn_batch(100)
	await get_tree().create_timer(1.2).timeout
	var third_after: Dictionary = _stats()
	if third_after.created - third.created >= 100:
		_fail("?????? %d ???????" % (third_after.created - third.created))
	print("[TEST] projectile pool reuse/bounds ? OK (round2 gain=%d, idle=%d)" % [gain, after.idle])


func _test_state_reset() -> void:
	## ? ????????????????????/??????
	await get_tree().process_frame
	var proj = PROJECTILE_SCRIPT.obtain({
		"position": Vector2(300, 300),
		"direction": Vector2.UP,
		"speed": 500.0,
		"range": 60.0,
		"damage": 7.0,
		"element": "ice",
		"aoe": 0.0,
		"mods": {"pierce": 2, "bounce": 1},
		"status": {"burn": 1.0},
	}, _container)
	# ???????????????????????
	if proj._element != "ice":
		_fail("?????%s??? ice?" % str(proj._element))
	if proj._damage != 7.0:
		_fail("?????%f??? 7.0?" % proj._damage)
	if proj._pierce_left != 2:
		_fail("?????%d??? 2?" % proj._pierce_left)
	if proj._travelled != 0.0 or proj._impacted != false or not proj._hit_enemies.is_empty():
		_fail("??/???????")
	if proj._is_whirl != false or proj._orbit_mode != false:
		_fail("??/???????")
	if proj._dir != Vector2.UP:
		_fail("?????%s??? UP?" % str(proj._dir))
	if not proj.is_in_group("player_projectile"):
		_fail("???????? player_projectile")
	await get_tree().create_timer(0.6).timeout
	if _live_proj() != 0:
		_fail("??????????????? %d?" % _live_proj())
	print("[TEST] projectile pool state reset ? OK")


func _test_hit_recycle() -> void:
	## ? ??????? + ???????????????????
	var e := ENEMY_SCENE.instantiate()
	e.setup("slime", 1, 1)
	e.behavior = ""
	e.speed = 0.0
	e.global_position = Vector2(640, 360)
	e.max_hp = 50.0  # slime ???????????????
	e.hp = e.max_hp
	_container.add_child(e)
	await get_tree().process_frame
	var hp0: float = e.hp
	var before: Dictionary = _stats()
	PROJECTILE_SCRIPT.obtain({
		"position": Vector2(300, 360),
		"direction": Vector2.RIGHT,
		"speed": 400.0,
		"range": 800.0,
		"damage": 1.0,
		"element": "fire",
		"aoe": 0.0,
		"mods": {"pierce": 0},
	}, _container)
	await get_tree().create_timer(1.4).timeout
	if e.hp >= hp0:
		_fail("????????hp %f -> %f?" % [hp0, e.hp])
	if _live_proj() != 0:
		_fail("??????????? %d?" % _live_proj())
	# ?????????????????
	var after: Dictionary = _stats()
	if after.reused - before.reused < 0:
		_fail("??????")
	var hp_after: float = e.hp
	e.queue_free()
	await get_tree().process_frame
	print("[TEST] projectile pool hit recycle ? OK (hp %f -> %f)" % [hp0, hp_after])
