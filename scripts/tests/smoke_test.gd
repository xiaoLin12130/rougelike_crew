extends SceneTree
## Godot headless smoke test: validates autoloads, data tables and core scenes.
## Run: godot --headless --path . -s res://scripts/tests/smoke_test.gd

var failures: Array[String] = []
var _frame := 0

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	_validate_autoloads()
	_validate_tables()
	_validate_scenes()
	if failures.is_empty():
		print("SMOKE OK")
	else:
		for f in failures:
			push_error("SMOKE FAIL: " + f)
	quit(0 if failures.is_empty() else 1)
	return true

func fail(msg: String) -> void:
	failures.append(msg)

func _gs() -> Node:
	return root.get_node_or_null("GameState")

func _validate_autoloads() -> void:
	for name in ["GameState", "EventBus", "InputRouter", "SfxBus", "SaveStore"]:
		if root.get_node_or_null(name) == null:
			fail("autoload missing: " + name)

func _validate_tables() -> void:
	var gs := _gs()
	if gs == null:
		return
	for t in ["balance", "items", "spells", "enemies", "levels", "drops"]:
		var tables: Dictionary = gs.tables
		if not tables.has(t) or tables[t].is_empty():
			fail("table missing: " + t)
	var run: Dictionary = gs.run
	if not run.has("loop"):
		fail("run state incomplete")
	var items: Array = gs.tables.get("items", {}).get("items", [])
	if items.size() < 20:
		fail("items table too small: " + str(items.size()))

func _validate_scenes() -> void:
	for p in [
		"res://scenes/main_menu.tscn",
		"res://scenes/game/game_root.tscn",
		"res://scenes/game/player.tscn",
		"res://scenes/game/enemy.tscn",
		"res://scenes/game/boss.tscn",
		"res://scenes/game/enemy_bullet.tscn",
		"res://scenes/game/projectile.tscn",
		"res://scenes/game/level.tscn",
		"res://scenes/game/camera.tscn",
		"res://scenes/ui/hud.tscn",
		"res://scenes/ui/build_panel.tscn",
		"res://scenes/ui/levelup_overlay.tscn",
		"res://scenes/ui/loop_choice.tscn",
		"res://scenes/ui/game_over.tscn",
		"res://scenes/ui/pause_menu.tscn",
	]:
		if not ResourceLoader.exists(p):
			fail("scene missing: " + p)
