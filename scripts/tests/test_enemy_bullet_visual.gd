extends SceneTree
## Enemy bullet visual separation test (2026-08-12):
## 1) enemy_bullet default texture != player fireball (enemy/player separation)
## 2) all 8 eb_* bullet textures exist with correct size
## 3) set_by_enemy(enemy_id) applies per-enemy bullet_visual config from enemies.json
## 4) sharp bullets rotate toward flight dir; round bullets do not rotate
## Run: godot --headless --path . -s res://scripts/tests/test_enemy_bullet_visual.gd

var failures: Array[String] = []
var _frame := 0

const EXPECTED := {
	"eb_diamond_purple": Vector2i(16, 16),
	"eb_shard_red": Vector2i(16, 16),
	"eb_cross_bone": Vector2i(16, 16),
	"eb_skull_dark": Vector2i(16, 16),
	"eb_bolt_bone": Vector2i(20, 12),
	"eb_spore_green": Vector2i(16, 16),
	"eb_orb_stone": Vector2i(16, 16),
	"eb_blade_shadow": Vector2i(20, 12),
}

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	_run_all()
	if failures.is_empty():
		print("ENEMY_BULLET_VISUAL ALL PASS")
	else:
		for f in failures:
			push_error("TEST FAIL: " + f)
	quit(0 if failures.is_empty() else 1)
	return true

func fail(msg: String) -> void:
	failures.append(msg)

func _gs() -> Node:
	return root.get_node_or_null("GameState")

func _make_bullet() -> Node:
	var b: Node = load("res://scenes/game/enemy_bullet.tscn").instantiate()
	root.add_child(b)
	return b

func _run_all() -> void:
	if _gs() == null:
		fail("GameState autoload missing")
	_default_texture_not_fireball()
	_textures_exist_and_sized()
	_set_by_enemy_applies()
	_rotation_logic()
	_unknown_enemy_falls_back()

func _default_texture_not_fireball() -> void:
	var b := _make_bullet()
	var sprite: Sprite2D = b.get_node("Sprite2D")
	var p := sprite.texture.resource_path
	if "proj_fireball" in p:
		fail("default texture is still player fireball: " + p)
	if "eb_diamond_purple" not in p:
		fail("default texture is not eb_diamond_purple: " + p)
	b.queue_free()

func _textures_exist_and_sized() -> void:
	for shape in EXPECTED:
		var path := "res://assets/sprites/enemy/%s.png" % shape
		if not ResourceLoader.exists(path):
			fail("texture missing: " + path)
			continue
		var tex: Texture2D = load(path)
		var want: Vector2i = EXPECTED[shape]
		if tex.get_width() != want.x or tex.get_height() != want.y:
			fail("%s size %dx%d != %dx%d" % [shape, tex.get_width(), tex.get_height(), want.x, want.y])

func _set_by_enemy_applies() -> void:
	var cases := {
		"imp": "eb_shard_red",
		"wizard": "eb_diamond_purple",
		"ghost": "eb_skull_dark",
		"goblin": "eb_orb_stone",
		"specter": "eb_blade_shadow",
		"bone_arbalest": "eb_bolt_bone",
		"mushroom": "eb_spore_green",
		"bat": "eb_shard_red",
		"obsidian_golem": "eb_orb_stone",
	}
	for eid in cases:
		var b := _make_bullet()
		b.set_by_enemy(eid)
		var sprite: Sprite2D = b.get_node("Sprite2D")
		var want: String = cases[eid]
		if want not in sprite.texture.resource_path:
			fail("enemy %s -> %s (want %s)" % [eid, sprite.texture.resource_path, want])
		b.queue_free()

func _rotation_logic() -> void:
	var dir := Vector2(1, 1).normalized()
	# sharp bullet (shard) rotates toward flight dir
	var b := _make_bullet()
	b.setup(Vector2.ZERO, dir, 100.0, 5, 400)
	b.set_by_enemy("imp")
	b._physics_process(0.016)
	var sprite: Sprite2D = b.get_node("Sprite2D")
	if absf(sprite.rotation - dir.angle()) > 0.01:
		fail("shard rotation %.3f != dir angle %.3f" % [sprite.rotation, dir.angle()])
	b.queue_free()
	# round bullet (orb) does not rotate
	var b2 := _make_bullet()
	b2.setup(Vector2.ZERO, dir, 100.0, 5, 400)
	b2.set_by_enemy("goblin")
	b2._physics_process(0.016)
	var sprite2: Sprite2D = b2.get_node("Sprite2D")
	if absf(sprite2.rotation) > 0.01:
		fail("orb should not rotate: %.3f" % sprite2.rotation)
	b2.queue_free()

func _unknown_enemy_falls_back() -> void:
	var b := _make_bullet()
	b.set_by_enemy("no_such_enemy")
	var sprite: Sprite2D = b.get_node("Sprite2D")
	if "eb_diamond_purple" not in sprite.texture.resource_path:
		fail("unknown enemy should fall back to eb_diamond_purple")
	b.queue_free()
