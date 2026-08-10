extends Node2D
## 新法术核心机制 headless 测试：状态触发（burn/slow/root+poison/blind）、
## split 分裂、drain 回血、闪电链跳跃、inferno 瞬发 aoe+burn、spell_caster 参数透传。
## Run: godot --headless --path . res://scripts/tests/test_core_mechanics.tscn

const PROJECTILE_SCRIPT := preload("res://scripts/combat/projectile.gd")
const ENEMY_SCENE := preload("res://scenes/game/enemy.tscn")
const PROJECTILE_SCENE := preload("res://scenes/game/projectile.tscn")

var _failures: Array[String] = []
var _dd_count := 0               ## P2-1a：damage_dealt 计数（反弹断言）
var _split_test_enemy: Node = null  ## P2-1b：物理回调内待击杀的分裂史莱姆


func _ready() -> void:
	GameState.run.crit_chance = 0.0  # 固定伤害，避免暴击抖动
	GameState.run.hp = GameState.run.max_hp
	var player := CharacterBody2D.new()
	player.position = Vector2(100, 100)
	player.add_to_group("player")
	add_child(player)
	await _test_statuses()
	await _test_split()
	await _test_drain()
	await _test_chain()
	await _test_caster_passthrough()
	await _test_thorn_reflect()
	await _test_split_flush_safe()
	await _clear_enemies()
	await _clear_projectiles()
	if _failures.is_empty():
		print("[TEST] CORE MECHANICS OK")
		get_tree().quit(0)
	else:
		for f in _failures:
			push_error("[TEST] FAIL: " + f)
		get_tree().quit(1)


func _fail(msg: String) -> void:
	_failures.append(msg)
	print("[TEST] FAIL: " + msg)


func _spawn_enemy(pos: Vector2) -> Node:
	var e = ENEMY_SCENE.instantiate()
	e.setup("slime", 1, 1)
	e.global_position = pos
	e.speed = 0.0
	add_child(e)
	return e


func _fire(params: Dictionary) -> Node:
	var proj = PROJECTILE_SCENE.instantiate()
	proj.setup(params)
	add_child(proj)
	return proj


func _wait_hit(enemy: Node, timeout := 180) -> bool:
	## 轮询至敌人掉血（命中），超时返回 false
	var full_hp: float = enemy.max_hp
	for i in timeout:
		if enemy.hp < full_hp:
			return true
		await get_tree().physics_frame
	return false


func _projectiles() -> Array:
	var out: Array = []
	for c in get_children():
		if c.get_script() == PROJECTILE_SCRIPT:
			out.append(c)
	return out


func _clear_projectiles() -> void:
	for c in _projectiles():
		c.queue_free()
	await get_tree().physics_frame


func _clear_enemies() -> void:
	for c in get_children():
		if c.has_method("take_damage"):
			c.queue_free()
	await get_tree().physics_frame


func _test_statuses() -> void:
	## 状态施加：inferno(burn) / water_bolt(slow) / thorn_vine(root+poison) / flash(blind)
	# --- inferno：瞬发爆炸，中心与 aoe 边缘敌人均受伤并灼烧 ---
	var e1 := _spawn_enemy(Vector2(620, 160))
	var e1b := _spawn_enemy(Vector2(670, 160))
	_fire({
		"position": Vector2(400, 160), "direction": Vector2.RIGHT, "speed": 0.0,
		"range": 220.0, "damage": 22.0, "element": "fire", "aoe": 64.0,
		"mods": {}, "status": {"burn": 2.0}, "chain": 0,
	})
	if not await _wait_hit(e1):
		_fail("inferno did not hit")
	else:
		if e1._burn_left <= 0.0:
			_fail("inferno burn not applied")
		await get_tree().physics_frame
		await get_tree().physics_frame
		if not is_equal_approx(e1.hp, e1.max_hp - 22.0):
			_fail("inferno center dmg != 22 (got %s)" % str(e1.hp))
		if not is_equal_approx(e1b.hp, e1b.max_hp - 22.0):
			_fail("inferno aoe missed +50px enemy (got %s)" % str(e1b.hp))
		if e1b._burn_left <= 0.0:
			_fail("inferno aoe burn not applied")
	# --- water_bolt：飞行弹命中施加 slow ---
	var e2 := _spawn_enemy(Vector2(620, 240))
	_fire({
		"position": Vector2(500, 240), "direction": Vector2.RIGHT, "speed": 400.0,
		"range": 200.0, "damage": 9.0, "element": "water", "aoe": 0.0,
		"mods": {}, "status": {"slow": 1.2}, "chain": 0,
	})
	if not await _wait_hit(e2):
		_fail("water_bolt did not hit")
	elif e2._slow_left <= 0.0:
		_fail("water_bolt slow not applied")
	# --- thorn_vine：root + poison 同时施加 ---
	var e3 := _spawn_enemy(Vector2(620, 320))
	_fire({
		"position": Vector2(500, 320), "direction": Vector2.RIGHT, "speed": 300.0,
		"range": 200.0, "damage": 8.0, "element": "nature", "aoe": 0.0,
		"mods": {}, "status": {"root": 1.5, "poison": 2.0}, "chain": 0,
	})
	if not await _wait_hit(e3):
		_fail("thorn_vine did not hit")
	else:
		if e3._root_left <= 0.0:
			_fail("thorn_vine root not applied")
		if e3._poison_left <= 0.0:
			_fail("thorn_vine poison not applied")
	# --- flash：瞬发 aoe=0，靠爆发半径命中并失明 ---
	var e4 := _spawn_enemy(Vector2(660, 400))
	_fire({
		"position": Vector2(400, 400), "direction": Vector2.RIGHT, "speed": 0.0,
		"range": 200.0, "damage": 6.0, "element": "light", "aoe": 0.0,
		"mods": {}, "status": {"blind": 2.0}, "chain": 0,
	})
	if not await _wait_hit(e4):
		_fail("flash burst did not reach +60px enemy")
	elif e4._blind_left <= 0.0:
		_fail("flash blind not applied")
	await _clear_projectiles()


func _test_split() -> void:
	## split 外壳：命中分裂 2 个小弹（伤害×0.6），小弹不重复命中来源敌人
	await _clear_projectiles()
	var e := _spawn_enemy(Vector2(620, 480))
	var start_hp: float = e.hp
	_fire({
		"position": Vector2(560, 480), "direction": Vector2.RIGHT, "speed": 400.0,
		"range": 200.0, "damage": 10.0, "element": "fire", "aoe": 0.0,
		"mods": {"split": 2}, "status": {}, "chain": 0,
	})
	if not await _wait_hit(e):
		_fail("split: no hit")
		return
	await get_tree().physics_frame
	await get_tree().physics_frame
	var minis := _projectiles()
	if minis.size() != 2:
		_fail("split: expected 2 minis, got %d" % minis.size())
	for m in minis:
		if not is_equal_approx(float(m._damage), 6.0):
			_fail("split: mini dmg should be 10x0.6=6, got %s" % str(m._damage))
	if not is_equal_approx(e.hp, start_hp - 10.0):
		_fail("split: source enemy must take parent dmg only (10), got %s" % str(e.hp))
	await _clear_projectiles()


func _test_drain() -> void:
	## drain 外壳：命中回复伤害 10% 生命
	await _clear_projectiles()
	GameState.run.hp = 50
	GameState.run.max_hp = 100
	var e := _spawn_enemy(Vector2(620, 560))
	e.hp = 1000.0
	e.max_hp = 1000.0
	_fire({
		"position": Vector2(560, 560), "direction": Vector2.RIGHT, "speed": 400.0,
		"range": 200.0, "damage": 100.0, "element": "fire", "aoe": 0.0,
		"mods": {"drain": 0.1}, "status": {}, "chain": 0,
	})
	if not await _wait_hit(e):
		_fail("drain: no hit")
	else:
		if GameState.run.hp != 60:
			_fail("drain: heal 10%% of 100 dmg -> hp 60, got %d" % GameState.run.hp)
	await _clear_projectiles()


func _test_chain() -> void:
	## 闪电链：chain=2 → 初始命中 A，跳 B（×0.7）、C（×0.49），D 超出跳数不受击
	await _clear_enemies()
	await _clear_projectiles()
	var a := _spawn_enemy(Vector2(620, 200))
	var b := _spawn_enemy(Vector2(700, 200))
	var c := _spawn_enemy(Vector2(780, 200))
	var d := _spawn_enemy(Vector2(880, 200))
	var ha: float = a.hp
	var hb: float = b.hp
	var hc: float = c.hp
	var hd: float = d.hp
	_fire({
		"position": Vector2(400, 200), "direction": Vector2.RIGHT, "speed": 0.0,
		"range": 220.0, "damage": 10.0, "element": "lightning", "aoe": 26.0,
		"mods": {}, "status": {}, "chain": 2,
	})
	if not await _wait_hit(a):
		_fail("chain: initial hit failed")
		return
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_equal_approx(a.hp, ha - 10.0):
		_fail("chain: A dmg != 10 (got %s)" % str(a.hp))
	if not is_equal_approx(b.hp, hb - 7.0):
		_fail("chain: B dmg != 7 (got %s)" % str(b.hp))
	if not is_equal_approx(c.hp, hc - 5.0):
		_fail("chain: C dmg != 5 (got %s)" % str(c.hp))
	if not is_equal_approx(d.hp, hd):
		_fail("chain: D must not be hit (got %s)" % str(d.hp))
	await _clear_projectiles()


func _test_caster_passthrough() -> void:
	## spell_caster._spawn_projectile：status/chain/split/drain 参数透传
	await _clear_enemies()
	await _clear_projectiles()
	var saved_grid: Array = GameState.run.grid
	GameState.run.grid = []  # 防空转施法
	var caster = load("res://scripts/combat/spell_caster.gd").new()
	add_child(caster)
	var player := CharacterBody2D.new()
	player.global_position = Vector2(400, 360)
	add_child(player)
	var core := {"element": "fire", "range": 220.0, "burn": 2.0, "slow": 1.2, "chain": 3}
	caster._spawn_projectile(player, Vector2.RIGHT, core, {"split": 2, "drain": 0.1}, 10.0, 0.0, 300.0)
	var projs := _projectiles()
	if projs.size() != 1:
		_fail("caster passthrough: expected 1 projectile, got %d" % projs.size())
	else:
		var p = projs[0]
		if float(p._status.get("burn", 0.0)) != 2.0:
			_fail("caster passthrough: burn not passed")
		if float(p._status.get("slow", 0.0)) != 1.2:
			_fail("caster passthrough: slow not passed")
		if int(p._chain_left) != 3:
			_fail("caster passthrough: chain not passed (got %s)" % str(p._chain_left))
		if int(p._split) != 2:
			_fail("caster passthrough: split not passed")
		if not is_equal_approx(float(p._drain), 0.1):
			_fail("caster passthrough: drain not passed")
	caster.queue_free()
	GameState.run.grid = saved_grid
	await _clear_projectiles()


func _on_dd(_dmg: int, _pos: Vector2, _crit: bool) -> void:
	_dd_count += 1


func _test_thorn_reflect() -> void:
	## P2-1a：荆棘甲（thorn_reflect）0 层受击不反弹；1 层按曲线反弹 40%
	await _clear_enemies()
	await _clear_projectiles()
	var ds_script: Script = load("res://scripts/synergies/defense_synergy.gd")
	if ds_script == null:
		_fail("thorn: defense_synergy.gd 编译失败")
		return
	var ds: Node = ds_script.new()
	# 免疫掷骰（thorn_armor/guard_shield 在 0 层 exp_proc 仍有 10%/30% 概率）用固定种子压掉
	var safe_seed := 0
	for s in range(1, 600):
		seed(s)
		if randf() >= 0.35:
			safe_seed = s
			break
	if safe_seed == 0:
		_fail("thorn: 找不到免疫掷骰通过种子")
		return
	var saved_items: Dictionary = GameState.run.get("items", {}).duplicate()
	var saved_bonus = GameState.run.get("synergy_bonus", {})
	GameState.run.items.clear()
	GameState.run["synergy_bonus"] = {}
	# 树上裸节点后置 set_script：跑真实 game_root._on_player_hit 但不触发 _ready（不拉整局）
	var gr := Node2D.new()
	add_child(gr)
	gr.set_script(load("res://scenes/game/game_root.gd"))
	EventBus.damage_dealt.connect(_on_dd)
	var attacker := _spawn_enemy(Vector2(600, 40))
	attacker.hp = 10000.0
	attacker.max_hp = 10000.0
	var pos: Vector2 = attacker.global_position
	# --- 0 层：不反弹 ---
	_dd_count = 0
	gr._hit_protect = 0.0
	seed(safe_seed)
	gr._on_player_hit(10, pos)
	await get_tree().physics_frame
	if not is_equal_approx(attacker.hp, attacker.max_hp):
		_fail("thorn 0层: attacker 不应掉血（hp=%s）" % str(attacker.hp))
	if _dd_count != 0:
		_fail("thorn 0层: 不应产生 damage_dealt（%d 次）" % _dd_count)
	if ds._reflect_pct_old() != 0.0 or ds._reflect_pct_new() != 0.0:
		_fail("thorn 0层: defense_synergy 反弹估算应为 0")
	# --- 1 层：按曲线反弹（game_root 硬编码 0.40/0.35/0.95，第 1 层 = base 40%）---
	GameState.run.items["thorn_reflect"] = 1
	var stone := float(GameState.item_value(
		GameState.item_def("stone_armor").get("curve", {"type": "linear", "base": 0.06, "k": 0.06, "cap": 0.35}), 0))
	var amulet := float(GameState.item_value(
		GameState.item_def("defense_amulet").get("curve", {"type": "linear", "base": 0.03, "k": 0.03, "cap": 0.20}), 0))
	var taken_int := int(10.0 * (1.0 - minf(stone + amulet, 0.50)))
	var reflected := int(float(taken_int) * 0.40)
	if not is_equal_approx(float(ds._reflect_pct_old()), 0.40):
		_fail("thorn 1层: defense_synergy 旧 id 估算应 0.40")
	_dd_count = 0
	gr._hit_protect = 0.0
	seed(safe_seed)
	gr._on_player_hit(10, pos)
	await get_tree().physics_frame
	var expect_hp: float = attacker.max_hp - float(reflected) * (1.0 - float(attacker.armor))
	if not is_equal_approx(attacker.hp, expect_hp):
		_fail("thorn 1层: 反弹 %d 伤，attacker hp=%s（期望 %s）" % [reflected, attacker.hp, expect_hp])
	if _dd_count != 1:
		_fail("thorn 1层: 应恰好 1 次 damage_dealt（got %d）" % _dd_count)
	# 还原
	EventBus.damage_dealt.disconnect(_on_dd)
	GameState.run.items.clear()
	for k in saved_items:
		GameState.run.items[k] = saved_items[k]
	GameState.run["synergy_bonus"] = saved_bonus
	attacker.queue_free()
	gr.queue_free()
	ds.free()
	await get_tree().physics_frame


func _on_killer_body(body: Node) -> void:
	## 物理冲刷期回调内击杀分裂史莱姆：_die 内 add_child 若未 deferred 会报 flushing queries
	if body == _split_test_enemy and is_instance_valid(_split_test_enemy):
		_split_test_enemy.take_damage(99999, "blade", false)


func _test_split_flush_safe() -> void:
	## P2-1b：分裂史莱姆在物理回调内死亡 → 分裂体 deferred 生成，不报 flushing queries
	await _clear_enemies()
	await _clear_projectiles()
	var e := _spawn_enemy(Vector2(300, 300))
	e.hp = 10.0
	e.max_hp = 10.0
	e.behavior = "split"  # 史莱姆 conf 默认即 split，显式声明防配置漂移
	_split_test_enemy = e
	var killer := Area2D.new()
	killer.collision_mask = 2  # 敌人 collision_layer=2
	var cs := CollisionShape2D.new()
	cs.shape = CircleShape2D.new()
	(cs.shape as CircleShape2D).radius = 10.0
	killer.add_child(cs)
	killer.global_position = e.global_position
	killer.body_entered.connect(_on_killer_body)
	add_child(killer)
	for i in 5:
		await get_tree().physics_frame
	var minis := 0
	for c in get_children():
		if c.get("_is_split") == true:
			minis += 1
	if minis != 1:
		_fail("split flush: 应生成 1 只分裂史莱姆（got %d）" % minis)
	if is_instance_valid(e):
		_fail("split flush: 原史莱姆应已死亡")
	killer.queue_free()
	_split_test_enemy = null
	await get_tree().physics_frame
