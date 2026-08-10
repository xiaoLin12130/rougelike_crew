extends Node2D
## 召唤系统扩展测试：
## 1) 随机召唤不超上限（类型 max_count + 召唤之书总上限）
## 2) 10 种类型均可实例化且精灵加载成功
## 3) 自爆/弹幕/近战/环绕/格挡行为验证（对 dummy 敌人）
## 运行：godot --headless --path . res://scripts/tests/test_summon_ext.tscn

const SUMMON_SCRIPT := preload("res://scripts/combat/summon.gd")
const ENEMY_SCENE := preload("res://scenes/game/enemy.tscn")

var _failures: Array[String] = []
var _player: Node2D
var _dmg_events := 0


func _ready() -> void:
	_player = Node2D.new()
	_player.position = Vector2(640, 360)
	add_child(_player)
	EventBus.damage_dealt.connect(func(_d: int, _p: Vector2, _c: bool) -> void: _dmg_events += 1)
	GameState.run.items["summon_book"] = 6  # 总上限 = 7
	await _test_random_caps()
	await _test_all_types_spawn()
	await _test_self_destruct_damage()
	await _test_ranged_damage()
	await _test_melee_damage()
	await _test_orbit_damage()
	await _test_block()
	_finish()


func _fail(msg: String) -> void:
	_failures.append(msg)
	push_error("[TEST] FAIL: " + msg)


func _spawn_summon(force_id: String = "", at: Vector2 = Vector2.ZERO) -> Node:
	var s: Node = SUMMON_SCRIPT.new()
	s.setup(_player, 10.0, "summon", force_id)
	add_child(s)
	s.global_position = at if at != Vector2.ZERO else _player.position
	return s


func _spawn_dummy(at: Vector2) -> Node:
	var e := ENEMY_SCENE.instantiate()
	e.setup("slime", 1, 1)
	e.global_position = at
	add_child(e)
	return e


## 敌人可能已被击杀销毁：死亡视为“造成伤害”。
func _hp_now(e: Node, hp0: float) -> float:
	return 0.0 if not is_instance_valid(e) else e.hp


func _clear_summons() -> void:
	for s in get_tree().get_nodes_in_group("summons"):
		if is_instance_valid(s):
			s.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _test_random_caps() -> void:
	for i in 40:
		_spawn_summon("", _player.position + Vector2(randf_range(-16, 16), randf_range(-16, 16)))
	await get_tree().process_frame
	await get_tree().process_frame
	var group: Array = get_tree().get_nodes_in_group("summons")
	var cap: int = GameState.total_stacks("summon_book") + 1
	if group.size() > cap:
		_fail("total cap exceeded: %d > %d" % [group.size(), cap])
	var counts := {}
	for s in group:
		var tid: String = str(s.get("_type_id"))
		counts[tid] = int(counts.get(tid, 0)) + 1
	for r in GameState.tables["summons"]["summons"]:
		var tid: String = str(r["id"])
		if int(counts.get(tid, 0)) > int(r["max_count"]):
			_fail("type cap exceeded: %s %d > %d" % [tid, counts.get(tid, 0), r["max_count"]])
	print("[TEST] random caps ok: alive=%d cap=%d counts=%s" % [group.size(), cap, counts])
	await _clear_summons()


func _test_all_types_spawn() -> void:
	for r in GameState.tables["summons"]["summons"]:
		var tid: String = str(r["id"])
		var s := _spawn_summon(tid)
		if str(s.get("_type_id")) != tid:
			_fail("force type %s -> %s" % [tid, s.get("_type_id")])
		var anim := s.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
		if anim == null or anim.sprite_frames.get_frame_count("idle") <= 0:
			_fail("sprite missing for %s" % tid)
		s.queue_free()
	await get_tree().process_frame
	print("[TEST] all %d types instantiate ok" % GameState.tables["summons"]["summons"].size())


func _test_self_destruct_damage() -> void:
	_dmg_events = 0
	var e := _spawn_dummy(Vector2(560, 360))
	var hp0: float = e.hp
	var s := _spawn_summon("fire_spirit", Vector2(610, 360))
	await get_tree().create_timer(2.0).timeout
	if _hp_now(e, hp0) >= hp0:
		_fail("self_destruct no damage (%.1f -> %.1f)" % [hp0, _hp_now(e, hp0)])
	else:
		print("[TEST] self_destruct ok: %.1f -> %.1f" % [hp0, _hp_now(e, hp0)])
	if _dmg_events <= 0:
		_fail("self_destruct no damage_dealt event")
	e.queue_free()
	await _clear_summons()


func _test_ranged_damage() -> void:
	# 三连弹幕（法师）
	_dmg_events = 0
	var e := _spawn_dummy(Vector2(560, 360))
	var hp0: float = e.hp
	var s := _spawn_summon("mage", Vector2(660, 360))
	await get_tree().create_timer(3.0).timeout
	if _hp_now(e, hp0) >= hp0:
		_fail("mage triple_shot no damage (%.1f -> %.1f)" % [hp0, _hp_now(e, hp0)])
	else:
		print("[TEST] triple_shot ok: %.1f -> %.1f" % [hp0, _hp_now(e, hp0)])
	if _dmg_events <= 0:
		_fail("mage no damage_dealt event")
	e.queue_free()
	await _clear_summons()
	# 追踪弹幕（元素精灵）
	_dmg_events = 0
	var e2 := _spawn_dummy(Vector2(560, 360))
	var hp2: float = e2.hp
	var s2 := _spawn_summon("spirit", Vector2(660, 360))
	await get_tree().create_timer(3.0).timeout
	if _hp_now(e2, hp2) >= hp2:
		_fail("spirit follow_shot no damage (%.1f -> %.1f)" % [hp2, _hp_now(e2, hp2)])
	else:
		print("[TEST] follow_shot ok: %.1f -> %.1f" % [hp2, _hp_now(e2, hp2)])
	e2.queue_free()
	await _clear_summons()


func _test_melee_damage() -> void:
	_dmg_events = 0
	var e := _spawn_dummy(Vector2(560, 360))
	var hp0: float = e.hp
	var s := _spawn_summon("bat", Vector2(640, 360))
	await get_tree().create_timer(3.0).timeout
	if _hp_now(e, hp0) >= hp0:
		_fail("bat bite no damage (%.1f -> %.1f)" % [hp0, _hp_now(e, hp0)])
	else:
		print("[TEST] bite ok: %.1f -> %.1f" % [hp0, _hp_now(e, hp0)])
	e.queue_free()
	await _clear_summons()


func _test_orbit_damage() -> void:
	_dmg_events = 0
	var e := _spawn_dummy(Vector2(602, 360))
	var hp0: float = e.hp
	var s := _spawn_summon("orb", Vector2(640, 360))
	await get_tree().create_timer(3.0).timeout
	if _hp_now(e, hp0) >= hp0:
		_fail("orb orbit no damage (%.1f -> %.1f)" % [hp0, _hp_now(e, hp0)])
	else:
		print("[TEST] orbit ok: %.1f -> %.1f" % [hp0, _hp_now(e, hp0)])
	if _dmg_events <= 0:
		_fail("orb no damage_dealt event")
	e.queue_free()
	await _clear_summons()


func _test_block() -> void:
	GameState.run.hp = 50
	var s := _spawn_summon("shieldbearer")
	EventBus.player_hit.emit(10, Vector2(640, 360))
	await get_tree().process_frame
	if GameState.run.hp < 55:
		_fail("block did not restore hp (hp=%d)" % GameState.run.hp)
	if float(s.get("_block_left")) <= 0.0:
		_fail("block cooldown not set")
	else:
		print("[TEST] block ok: hp=%d block_left=%.2f" % [GameState.run.hp, float(s.get("_block_left"))])
	await _clear_summons()


func _finish() -> void:
	if _failures.is_empty():
		print("[TEST] SUMMON_EXT OK")
		get_tree().quit(0)
	else:
		for f in _failures:
			push_error("[TEST] FAIL: " + f)
		print("[TEST] SUMMON_EXT FAILED: %d" % _failures.size())
		get_tree().quit(1)
