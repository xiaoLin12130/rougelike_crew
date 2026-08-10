extends Node2D
## 雷系连锁视觉 headless 测试：
## 1) 弹道链跳（projectile._try_chain，chain=3）每次跳跃产生一条 LightningBolt，
##    且 0.5s 内全部自毁（不泄漏、不残留）；
## 2) thunder_synergy._chain_burst（电弧链）每跳也产生闪电连线；
## 3) 麻痹目标（_apply_paralysis）出现蓝白闪烁视觉 + 定身图标（_paralyze_left 驱动）；
## 4) 落雷（_strike）产生闪电柱 + 地面电弧溅射等视觉节点，且自动回收。
## Run: godot --headless --path . res://scripts/tests/test_lightning_fx.tscn

const PROJECTILE_SCRIPT := preload("res://scripts/combat/projectile.gd")
const ENEMY_SCENE := preload("res://scenes/game/enemy.tscn")
const PROJECTILE_SCENE := preload("res://scenes/game/projectile.tscn")
const FX_MANAGER_SCRIPT := preload("res://scripts/fx/fx_manager.gd")
const THUNDER_SCRIPT := preload("res://scripts/synergies/thunder_synergy.gd")

var _failures: Array[String] = []
var _fx: Node
var _thunder: Node


func _ready() -> void:
	GameState.run.crit_chance = 0.0  # 固定伤害，避免暴击抖动
	_fx = FX_MANAGER_SCRIPT.new()
	_fx.name = "FxManager"
	add_child(_fx)
	_thunder = THUNDER_SCRIPT.new()
	_thunder.name = "ThunderSynergy"
	add_child(_thunder)
	var player := CharacterBody2D.new()
	player.position = Vector2(100, 100)
	player.add_to_group("player")
	add_child(player)
	await _test_chain_bolts()
	await _test_synergy_chain_bolts()
	await _test_paralyze_visual()
	await _test_strike_visual()
	if _failures.is_empty():
		print("[TEST] LIGHTNING FX ALL PASS")
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
	var full_hp: float = enemy.max_hp
	for i in timeout:
		if enemy.hp < full_hp:
			return true
		await get_tree().physics_frame
	return false


func _wait_sec(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _lightning_bolts() -> Array:
	## FxManager 下存活的 LightningBolt 节点（名字前缀识别，双保险 meta）
	var out: Array = []
	for c in _fx.get_children():
		if str(c.name).begins_with("LightningBolt"):
			out.append(c)
		elif bool(c.get_meta("is_lightning_bolt", false)):
			out.append(c)
	return out


func _clear_enemies() -> void:
	for c in get_children():
		if c.has_method("take_damage"):
			c.queue_free()
	await get_tree().physics_frame


func _clear_projectiles() -> void:
	for c in get_children():
		if c.get_script() == PROJECTILE_SCRIPT:
			c.queue_free()
	await get_tree().physics_frame


func _test_chain_bolts() -> void:
	## 弹道链跳 chain=3：初击 A 后跳 B/C/D，每次跳转产生 1 条 LightningBolt，共 3 条；
	## 0.5s 内全部自毁（不泄漏）。
	await _clear_enemies()
	await _clear_projectiles()
	var a := _spawn_enemy(Vector2(620, 200))
	var b := _spawn_enemy(Vector2(700, 200))
	var c := _spawn_enemy(Vector2(780, 200))
	var d := _spawn_enemy(Vector2(860, 200))
	_fire({
		"position": Vector2(400, 200), "direction": Vector2.RIGHT, "speed": 0.0,
		"range": 220.0, "damage": 5.0, "element": "lightning", "aoe": 26.0,
		"mods": {}, "status": {}, "chain": 3,
	})
	if not await _wait_hit(a):
		_fail("chain visual: 初击未命中")
		return
	await get_tree().physics_frame
	await get_tree().physics_frame
	if a.hp >= a.max_hp or b.hp >= b.max_hp or c.hp >= c.max_hp or d.hp >= d.max_hp:
		_fail("chain visual: 链跳伤害结算缺失")
	var bolts := _lightning_bolts()
	if bolts.size() != 3:
		_fail("chain=3 应产生 3 条 LightningBolt，实际 %d" % bolts.size())
	else:
		for bolt in bolts:
			if not (bolt is Node2D) or bolt.get("is_lightning_bolt", false) != true:
				_fail("LightningBolt 节点属性异常")
		if int(_fx.call("lightning_bolt_count")) != 3:
			_fail("lightning_bolt_count() 与节点数不一致")
	# 0.5s 内自动消失（生命周期 0.22s + 余量）
	await _wait_sec(0.55)
	if _lightning_bolts().size() != 0:
		_fail("0.5s 后 LightningBolt 未全部自毁（残留 %d）" % _lightning_bolts().size())
	if int(_fx.call("lightning_bolt_count")) != 0:
		_fail("闪电连线池未清空（泄漏）")
	await _clear_projectiles()


func _test_synergy_chain_bolts() -> void:
	## thunder_synergy._chain_burst（M3 静电/M5 导雷/M10 电网共用）每跳绘制连线
	await _clear_enemies()
	await _clear_projectiles()
	var a := _spawn_enemy(Vector2(300, 380))
	var b := _spawn_enemy(Vector2(380, 380))
	var c := _spawn_enemy(Vector2(460, 380))
	_thunder._chain_burst(Vector2(220, 380), 200.0, 3, 8.0, false, {})
	await get_tree().physics_frame
	await get_tree().physics_frame
	var n := _lightning_bolts().size()
	if n != 3:
		_fail("synergy 电弧 3 跳应产生 3 条连线，实际 %d" % n)
	if a.hp >= a.max_hp or b.hp >= b.max_hp or c.hp >= c.max_hp:
		_fail("synergy 电弧未造成伤害（机制回归）")
	await _wait_sec(0.45)
	if _lightning_bolts().size() != 0:
		_fail("synergy 连线未在 0.5s 内自毁")
	await _clear_enemies()


func _test_paralyze_visual() -> void:
	## 麻痹：_apply_paralysis 写入 _root_left（机制）与 _paralyze_left（视觉标记）→
	## 附着切换为 paralyze，出现定身图标 ParalyzeIcon，sprite 蓝白闪烁且随时间变化。
	await _clear_enemies()
	var e := _spawn_enemy(Vector2(400, 300))
	_thunder._apply_paralysis(e, 1.2)
	await get_tree().physics_frame
	await get_tree().physics_frame
	if e._root_left <= 0.0:
		_fail("麻痹未写入 _root_left（机制回归）")
	if e._paralyze_left <= 0.0:
		_fail("麻痹视觉标记 _paralyze_left 未写入")
	if e._status_attach_kind != "paralyze":
		_fail("麻痹附着应为 paralyze，实际 %s" % str(e._status_attach_kind))
	if e.get_node_or_null("StatusAttach/ParalyzeIcon") == null:
		_fail("缺少定身图标 ParalyzeIcon")
	var spr := e.get_node_or_null("AnimatedSprite2D") as Sprite2D
	if spr == null:
		_fail("敌人缺少 AnimatedSprite2D")
		return
	var m1: Color = spr.modulate
	await _wait_sec(0.28)
	var m2: Color = spr.modulate
	if m1.is_equal_approx(m2):
		_fail("麻痹闪烁未随时间变化（modulate 静止）")
	if m2.b <= m2.r:
		_fail("麻痹色调应偏蓝白（蓝分量应高于红分量）")
	await _clear_enemies()


func _test_strike_visual() -> void:
	## 落雷：_strike → fx_explosion(雷云闪电) + spawn_strike_arcs(闪电柱+地面电弧溅射)，
	## FxManager 产生一批视觉节点并在 ~1.5s 内全部自毁。
	await _clear_enemies()
	var e := _spawn_enemy(Vector2(400, 500))
	await _wait_sec(0.2)  # 等上一段测试节点回收
	var before := _fx.get_child_count()
	_thunder._strike(e.global_position, 60.0, 5)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var gained := _fx.get_child_count() - before
	if gained < 5:
		_fail("落雷应产生闪电柱+溅射等视觉节点，实际新增 %d" % gained)
	await _wait_sec(1.5)
	if _fx.get_child_count() != before:
		_fail("落雷视觉未全部自毁（残留 %d）" % (_fx.get_child_count() - before))
	await _clear_enemies()
