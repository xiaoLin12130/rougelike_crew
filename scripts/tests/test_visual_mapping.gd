extends Node2D
## 技能视觉 P0 修复测试（docs/design/技能视觉全量审计.md）：
## ① water_bolt/thorn_vine 弹道贴图不再是 proj_fireball（STATUS_TEXTURES 补 water/nature，
##    断言 _ready 后 Sprite2D 贴图路径 == verarc 水滴/藤蔓图标）；
## ② flash 盲爆 fx_explosion_scaled 半径 == 最终命中半径（_explode_at 先算最终 radius 再 emit，
##    EventBus.fx_explosion_scaled 捕获断言：90 × aoe_mult）；
## ③ frenzy 施法 fx kind == "buff" + 金色光环挂玩家并 3s 自毁；mana_echo/counterspell kind == "void"（P1）。
## Run: godot --headless --path . res://scripts/tests/test_visual_mapping.tscn

const PROJECTILE_SCENE := preload("res://scenes/game/projectile.tscn")
const SPELL_CASTER_SCRIPT := preload("res://scripts/combat/spell_caster.gd")
const WATER_TEX := "res://assets/icons/verarc/water_spell.png"
const NATURE_TEX := "res://assets/icons/verarc/thorn_vine_spell.png"
const FIREBALL_TEX := "res://assets/sprites/gen/proj_fireball.png"

var _failures: Array[String] = []


func _ready() -> void:
	GameState.run.crit_chance = 0.0  # 固定伤害，避免暴击抖动
	GameState.run.crit_dmg_bonus = 1.5
	GameState.run.wind_speed_area = 0.0  # 移8 踏浪加成归零，半径断言不受干扰
	var player := CharacterBody2D.new()
	player.name = "TestPlayer"
	player.global_position = Vector2(100, 100)
	player.add_to_group("player")
	add_child(player)
	await _test_element_textures()
	await _test_flash_explode_radius()
	await _test_frenzy_cast_kind()
	await _test_echo_counter_kind()
	if _failures.is_empty():
		print("[TEST] VISUAL MAPPING ALL PASS")
		get_tree().quit(0)
	else:
		for f in _failures:
			push_error("[TEST] FAIL: " + f)
		print("VISUAL MAPPING FAILED: %d" % _failures.size())
		get_tree().quit(1)


func _fail(msg: String) -> void:
	_failures.append(msg)
	print("[TEST] FAIL: " + msg)


func _core(core_id: String) -> Dictionary:
	for c in GameState.tables.get("spells", {}).get("cores", []):
		if str(c.get("id", "")) == core_id:
			return c
	return {}


func _sprite_path_of(proj: Node) -> String:
	var spr := proj.get_node_or_null("Sprite2D") as Sprite2D
	if spr == null or spr.texture == null:
		return ""
	return str(spr.texture.resource_path)


# ================= ① STATUS_TEXTURES：water/nature 弹体不再是火球 =================

func _test_element_textures() -> void:
	for entry in [["water", WATER_TEX], ["nature", NATURE_TEX]]:
		var proj = PROJECTILE_SCENE.instantiate()
		proj.setup({
			"position": Vector2(200, 100), "direction": Vector2.RIGHT, "speed": 100.0,
			"range": 10000.0, "damage": 5.0, "element": str(entry[0]), "aoe": 0.0,
			"mods": {}, "status": {}, "chain": 0,
		})
		add_child(proj)  # _ready 同步执行，贴图立即生效
		var path := _sprite_path_of(proj)
		if path != str(entry[1]):
			_fail("%s 弹体贴图应为 %s，实际 '%s'（STATUS_TEXTURES 缺失/回退火球）" % [str(entry[0]), str(entry[1]), path])
		if path == FIREBALL_TEX:
			_fail("%s 弹体仍回退火球贴图 proj_fireball" % str(entry[0]))
		proj.queue_free()
	await get_tree().physics_frame
	# 对照组：fire 弹体保持火球贴图（映射未被误改）
	var fb = PROJECTILE_SCENE.instantiate()
	fb.setup({
		"position": Vector2(200, 140), "direction": Vector2.RIGHT, "speed": 100.0,
		"range": 10000.0, "damage": 5.0, "element": "fire", "aoe": 0.0,
		"mods": {}, "status": {}, "chain": 0,
	})
	add_child(fb)
	var fb_path := _sprite_path_of(fb)
	if fb_path != FIREBALL_TEX:
		_fail("fire 对照组弹体贴图应保持 proj_fireball，实际 '%s'" % fb_path)
	fb.queue_free()
	await get_tree().physics_frame


# ================= ② flash 盲爆：fx 半径 == 最终命中半径 =================

func _test_flash_explode_radius() -> void:
	var captured: Array = []
	var cb := func(_pos: Vector2, _kind: String, radius: float) -> void:
		captured.append(radius)
	EventBus.fx_explosion_scaled.connect(cb)
	for tc in [{"aoe_mult": 1.0, "expect": 90.0}, {"aoe_mult": 2.0, "expect": 180.0}]:
		captured.clear()
		var proj = PROJECTILE_SCENE.instantiate()
		proj.setup({
			"position": Vector2(400, 100), "direction": Vector2.RIGHT, "speed": 0.0,
			"range": 200.0, "damage": 6.0, "element": "light", "aoe": 0.0,
			"mods": {"explode": true, "aoe_mult": float(tc["aoe_mult"])},
			"status": {"blind": 2.0}, "chain": 0,
		})
		add_child(proj)
		# 瞬发核：首个物理帧 _instant_landing + _explode_at
		await get_tree().physics_frame
		await get_tree().physics_frame
		if captured.is_empty():
			_fail("flash aoe_mult=%s: 未捕获 fx_explosion_scaled" % str(tc["aoe_mult"]))
			continue
		var got: float = captured[0]
		if not is_equal_approx(got, float(tc["expect"])):
			_fail("flash aoe_mult=%s: fx 半径 %s != 最终命中半径 %s（_explode_at 时序未修复）" \
				% [str(tc["aoe_mult"]), str(got), str(tc["expect"])])
		else:
			print("[TEST] flash fx radius=%.0f (aoe_mult=%s) → PASS" % [got, str(tc["aoe_mult"])])
	EventBus.fx_explosion_scaled.disconnect(cb)


# ================= ③ frenzy：kind=buff + 金色光环挂玩家 =================

func _test_frenzy_cast_kind() -> void:
	var captured: Array = []
	var cb := func(_pos: Vector2, kind: String) -> void:
		captured.append(kind)
	EventBus.fx_explosion.connect(cb)
	var caster := SPELL_CASTER_SCRIPT.new()
	add_child(caster)
	var player: Node = get_tree().get_first_node_in_group("player")
	caster._cast(player, _core("frenzy"), {})
	if captured.is_empty() or str(captured[0]) != "buff":
		_fail("frenzy 施法 fx kind 应为 buff（金色 buff 配方），实际 %s" % str(captured))
	else:
		print("[TEST] frenzy kind=buff → PASS")
	if not is_equal_approx(caster._frenzy_left, 3.0):
		_fail("frenzy 后 _frenzy_left 应为 3.0，实际 %s" % str(caster._frenzy_left))
	var aura: Node = player.get_node_or_null("FrenzyAura")
	if aura == null:
		_fail("frenzy 后玩家应挂 FrenzyAura 金色光环（P0-3 持续反馈缺失）")
	else:
		print("[TEST] frenzy aura attached → PASS")
		# 光环随狂暴结束自毁（3s）
		aura._process(3.1)
		await get_tree().process_frame
		if is_instance_valid(aura):
			_fail("FrenzyAura 3s 后应自毁")
	caster.queue_free()
	EventBus.fx_explosion.disconnect(cb)
	await get_tree().process_frame


# ================= P1：mana_echo / counterspell kind 归位 void =================

func _test_echo_counter_kind() -> void:
	var expl: Array = []
	var cb := func(_pos: Vector2, kind: String) -> void:
		expl.append(kind)
	EventBus.fx_explosion.connect(cb)
	var scaled: Array = []
	var cb2 := func(_pos: Vector2, kind: String, _radius: float) -> void:
		scaled.append(kind)
	EventBus.fx_explosion_scaled.connect(cb2)
	var caster := SPELL_CASTER_SCRIPT.new()
	add_child(caster)
	var player: Node = get_tree().get_first_node_in_group("player")
	caster._cast(player, _core("mana_echo"), {})
	if expl.is_empty() or str(expl[0]) != "void":
		_fail("mana_echo 施法 fx kind 应为 void（虚空余波），实际 %s" % str(expl))
	else:
		print("[TEST] mana_echo kind=void → PASS")
	caster._cast(player, _core("counterspell"), {})
	if scaled.is_empty() or str(scaled[0]) != "void":
		_fail("counterspell 施法 fx kind 应为 void（吞没弹幕），实际 %s" % str(scaled))
	else:
		print("[TEST] counterspell kind=void → PASS")
	caster.queue_free()
	EventBus.fx_explosion.disconnect(cb)
	EventBus.fx_explosion_scaled.disconnect(cb2)
	await get_tree().process_frame
