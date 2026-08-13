extends Node2D
## 水弹弹体修复测试（docs/design/水弹弹体修复报告.md）：
## 用户反馈"水弹技能直接把技能图标发射出去"——STATUS_TEXTURES["water"] 曾指向
## verarc 16x16 技能图标（assets/icons/verarc/water_spell.png），弹体直接飞图标。
## 修复：water 映射改为程序化 12x12 水滴贴图 assets/sprites/gen/proj_water.png，
##       STATUS_TEXTURE_SCALE["water"] 1.5 → 1.0（12x12 与 fire/ice 同规格，无需放大补偿）。
## 本测试断言：
## ① water 弹体贴图 resource_path == proj_water.png（不再是 verarc 图标、不回退火球）；
## ② 贴图尺寸 12x12；
## ③ Sprite2D scale == 1.0（放大补偿已移除）；
## ④ 对照组：fire 仍为 proj_fireball、ice 仍为 proj_ice（未误伤其他元素）。
## Run: godot --headless --path . res://scripts/tests/test_water_projectile.tscn

const PROJECTILE_SCENE := preload("res://scenes/game/projectile.tscn")
const WATER_TEX := "res://assets/sprites/gen/proj_water.png"
const WATER_ICON_TEX := "res://assets/icons/verarc/water_spell.png"
const FIREBALL_TEX := "res://assets/sprites/gen/proj_fireball.png"
const ICE_TEX := "res://assets/sprites/gen/proj_ice.png"

var _failures: Array[String] = []


func _ready() -> void:
	GameState.run.crit_chance = 0.0
	GameState.run.crit_dmg_bonus = 1.5
	await _test_water_texture()
	await _test_water_scale()
	await _test_element_regression()
	if _failures.is_empty():
		print("[TEST] WATER PROJECTILE ALL PASS")
		get_tree().quit(0)
	else:
		for f in _failures:
			push_error("[TEST] FAIL: " + f)
		print("WATER PROJECTILE FAILED: %d" % _failures.size())
		get_tree().quit(1)


func _fail(msg: String) -> void:
	_failures.append(msg)
	print("[TEST] FAIL: " + msg)


func _make_proj(element: String) -> Node:
	var proj = PROJECTILE_SCENE.instantiate()
	proj.setup({
		"position": Vector2(200, 100), "direction": Vector2.RIGHT, "speed": 100.0,
		"range": 10000.0, "damage": 5.0, "element": element, "aoe": 0.0,
		"mods": {}, "status": {}, "chain": 0,
	})
	add_child(proj)
	return proj


func _sprite_path_of(proj: Node) -> String:
	var spr := proj.get_node_or_null("Sprite2D") as Sprite2D
	if spr == null or spr.texture == null:
		return ""
	return str(spr.texture.resource_path)


## ① water 弹体贴图 == proj_water.png（非 verarc 图标 / 非火球回退）
func _test_water_texture() -> void:
	var proj := _make_proj("water")
	var path := _sprite_path_of(proj)
	if path != WATER_TEX:
		_fail("water 弹体贴图应为 %s，实际 '%s'" % [WATER_TEX, path])
	if path == WATER_ICON_TEX:
		_fail("water 弹体仍直接飞 verarc 技能图标 water_spell.png")
	if path == FIREBALL_TEX:
		_fail("water 弹体仍回退火球贴图 proj_fireball")
	if path == WATER_TEX:
		print("[TEST] water 弹体贴图 = proj_water.png（非图标）→ PASS")
	proj.queue_free()
	await get_tree().physics_frame


## ②③ water 贴图 12x12 + Sprite2D scale == 1.0
func _test_water_scale() -> void:
	var proj := _make_proj("water")
	var spr := proj.get_node_or_null("Sprite2D") as Sprite2D
	if spr == null or spr.texture == null:
		_fail("water 弹体缺少 Sprite2D 贴图")
		return
	var w: int = spr.texture.get_width()
	var h: int = spr.texture.get_height()
	if w != 12 or h != 12:
		_fail("water 弹体贴图应 12x12，实际 %dx%d" % [w, h])
	else:
		print("[TEST] water 弹体贴图 12x12 → PASS")
	if spr.scale != Vector2.ONE:
		_fail("water 弹体 scale 应为 1.0（放大补偿已移除），实际 %s" % str(spr.scale))
	else:
		print("[TEST] water 弹体 scale = 1.0 → PASS")
	proj.queue_free()
	await get_tree().physics_frame


## ④ 对照组：fire/ice 弹体保持原程序化贴图（映射未被误改）
func _test_element_regression() -> void:
	var fb := _make_proj("fire")
	var fb_path := _sprite_path_of(fb)
	if fb_path != FIREBALL_TEX:
		_fail("fire 对照组弹体贴图应保持 proj_fireball，实际 '%s'" % fb_path)
	else:
		print("[TEST] fire 对照组 proj_fireball → PASS")
	fb.queue_free()
	await get_tree().physics_frame
	var ice := _make_proj("ice")
	var ice_path := _sprite_path_of(ice)
	if ice_path != ICE_TEX:
		_fail("ice 对照组弹体贴图应保持 proj_ice，实际 '%s'" % ice_path)
	else:
		print("[TEST] ice 对照组 proj_ice → PASS")
	ice.queue_free()
	await get_tree().physics_frame
