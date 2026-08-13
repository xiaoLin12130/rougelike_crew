extends Node2D
## 藤蔓弹体视觉修复测试（docs/design/藤蔓护盾音效修复报告.md）：
## ① nature（thorn_vine）弹体不飞静态图标：Sprite2D 隐藏 + 程序化 VineSeed 种子节点；
## ② 弹体命中敌人后，命中点生成 GroundVine 地面藤蔓节点（"投出种子，命中缠绕"）；
## ③ 对照组：water 弹体仍为水滴图标、fire 仍为火球（未误伤其他元素）。
## Run: godot --headless --path . res://scripts/tests/test_thorn_vine_visual.tscn

const PROJECTILE_SCENE := preload("res://scenes/game/projectile.tscn")
const WATER_TEX := "res://assets/sprites/gen/proj_water.png"
const FIREBALL_TEX := "res://assets/sprites/gen/proj_fireball.png"

var _failures: Array[String] = []


class DummyEnemy:
	extends Node2D

	var hp := 100.0
	var is_boss := false
	var is_elite := false

	func _init() -> void:
		add_to_group("enemy")

	func take_damage(dmg: int, _el: String, _c: bool) -> void:
		hp -= dmg


func _ready() -> void:
	GameState.run.crit_chance = 0.0
	GameState.run.crit_dmg_bonus = 1.5
	await get_tree().process_frame
	await _test_flying_visual()
	await _test_hit_spawns_vine()
	await _test_element_regression()
	if _failures.is_empty():
		print("[TEST] THORN VINE VISUAL ALL PASS")
		get_tree().quit(0)
	else:
		for f in _failures:
			push_error("[TEST] FAIL: " + f)
		print("THORN VINE VISUAL FAILED: %d" % _failures.size())
		get_tree().quit(1)


func _fail(msg: String) -> void:
	_failures.append(msg)
	print("[TEST] FAIL: " + msg)


func _sprite_of(proj: Node) -> Sprite2D:
	return proj.get_node_or_null("Sprite2D") as Sprite2D


func _find_ground(name: String) -> Node:
	return find_child(name, true, false)


func _wait_appear(name: String, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if _find_ground(name) != null:
			return true
		await get_tree().create_timer(0.05).timeout
		t += 0.05
	return false


func _make_proj(pos: Vector2, dir: Vector2, element: String) -> Node:
	var proj = PROJECTILE_SCENE.instantiate()
	proj.setup({
		"position": pos, "direction": dir, "speed": 240.0,
		"range": 10000.0, "damage": 5.0, "element": element, "aoe": 0.0,
		"mods": {}, "status": {"root": 1.0}, "chain": 0,
	})
	add_child(proj)
	return proj


## ① 飞行阶段视觉：nature 弹体 = 程序化种子，不飞图标
func _test_flying_visual() -> void:
	var proj := _make_proj(Vector2(200, 100), Vector2.RIGHT, "nature")
	var spr := _sprite_of(proj)
	if spr == null:
		_fail("nature 弹体缺少 Sprite2D 子节点")
	elif spr.visible:
		_fail("nature 弹体 Sprite2D 应隐藏（藤蔓图标不应再飞出去）")
	if spr != null and spr.texture != null and str(spr.texture.resource_path) == "res://assets/icons/verarc/thorn_vine_spell.png":
		_fail("nature 弹体仍在飞 thorn_vine 图标")
	if proj.get_node_or_null("VineSeed") == null:
		_fail("nature 弹体应挂程序化 VineSeed 种子视觉节点")
	else:
		print("[TEST] nature 飞行视觉 = VineSeed 程序化种子（Sprite2D 隐藏）→ PASS")
	proj.queue_free()
	await get_tree().physics_frame


## ② 命中生成 GroundVine：弹体命中敌人后场景出现地面藤蔓节点
func _test_hit_spawns_vine() -> void:
	var e := DummyEnemy.new()
	e.global_position = Vector2(420, 260)
	add_child(e)
	var proj := _make_proj(Vector2(300, 260), Vector2.RIGHT, "nature")
	if not await _wait_appear("GroundVine", 2.0):
		_fail("nature 弹体命中敌人后应生成 GroundVine 地面藤蔓（未出现）")
	else:
		print("[TEST] 命中点生成 GroundVine → PASS")
	var vine := _find_ground("GroundVine")
	if vine != null:
		if vine.global_position.distance_to(e.global_position) > 8.0:
			_fail("GroundVine 应生成在命中点附近，实际偏移 %.1f" % vine.global_position.distance_to(e.global_position))
	# 藤蔓 1.5s 后自毁（不泄漏）
	await _wait_gone("GroundVine", 3.0)
	e.queue_free()
	proj.queue_free()
	await get_tree().process_frame


func _wait_gone(name: String, timeout: float) -> void:
	var t := 0.0
	while t < timeout:
		if _find_ground(name) == null:
			return
		await get_tree().create_timer(0.1).timeout
		t += 0.1
	_fail(name + " 藤蔓节点超时未消失（泄漏）")


## ③ 回归：water 程序化水滴贴图 / fire 火球贴图不受影响
func _test_element_regression() -> void:
	var w := _make_proj(Vector2(200, 140), Vector2.RIGHT, "water")
	var wspr := _sprite_of(w)
	if wspr == null or not wspr.visible or str(wspr.texture.resource_path) != WATER_TEX:
		_fail("water 弹体应保持程序化水滴贴图可见（回归破坏）")
	else:
		print("[TEST] water 弹体 proj_water 贴图回归 → PASS")
	w.queue_free()
	await get_tree().physics_frame
	var f := _make_proj(Vector2(200, 180), Vector2.RIGHT, "fire")
	var fspr := _sprite_of(f)
	if fspr == null or not fspr.visible or str(fspr.texture.resource_path) != FIREBALL_TEX:
		_fail("fire 弹体应保持火球贴图可见（回归破坏）")
	else:
		print("[TEST] fire 弹体火球贴图回归 → PASS")
	f.queue_free()
	await get_tree().physics_frame
