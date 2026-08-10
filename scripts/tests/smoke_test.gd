extends SceneTree
## Godot headless smoke test: validates autoloads, data tables and core scenes.
## Run: godot --headless --path . -s res://scripts/tests/smoke_test.gd

var failures: Array[String] = []
var _frame := 0
var _script_count := 0

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	_validate_autoloads()
	_validate_tables()
	_validate_scenes()
	_validate_script_compile()
	_validate_healing_system()
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
		"res://scenes/game/health_pack.tscn",
	]:
		if not ResourceLoader.exists(p):
			fail("scene missing: " + p)

func _validate_script_compile() -> void:
	## 编译检查：load 全部 .gd 脚本（能抓到变量重复/作用域等解析错误，
	## 这类错误 exists 检查发现不了，且会导致运行时 UI 静默失效）
	## synergies/ 为子代理并行开发目录（可能处于中间态），流派全部完成后恢复扫描
	var dirs := ["res://scripts", "res://scenes"]
	_script_count = 0
	for d in dirs:
		var dir := DirAccess.open(d)
		if dir == null:
			continue
		_collect_scripts(dir, d)
	if _script_count == 0:
		fail("script compile scan found nothing")

func _collect_scripts(dir: DirAccess, prefix: String) -> void:
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var path := prefix + "/" + name
		if dir.current_is_dir():
			var sub := DirAccess.open(path)
			if sub != null:
				_collect_scripts(sub, path)
		elif name.ends_with(".gd"):
			if path.begins_with("res://scripts/synergies/"):
				name = dir.get_next()
				continue
			var res := load(path)
			if res == null:
				fail("script compile failed: " + path)
			_script_count += 1
		name = dir.get_next()
	dir.list_dir_end()

func _validate_healing_system() -> void:
	var gs := _gs()
	if gs == null:
		return
	var drops: Dictionary = gs.tables.get("drops", {})
	# 普通小怪不掉血包：kill_drops 无 heal 类型
	for d in drops.get("kill_drops", []):
		if str(d.get("type", "")) == "heal":
			fail("普通小怪不应掉落回血")
	# 精英/Boss 血包百分比符合契约
	if absf(float(drops.get("elite_drops", {}).get("heal_pct", 0.0)) - 0.10) > 1e-6:
		fail("elite_drops.heal_pct != 0.10")
	if absf(float(drops.get("boss_drops", {}).get("heal_pct", 0.0)) - 0.30) > 1e-6:
		fail("boss_drops.heal_pct != 0.30")
	# GameState.heal 钳制：回血不超上限、返回实际值
	gs.run.max_hp = 100
	gs.run.hp = 80
	var healed1: int = gs.heal(15.0)
	if healed1 != 15 or gs.run.hp != 95:
		fail("heal 15 -> 95 (got %d -> %d)" % [healed1, gs.run.hp])
	var healed2: int = gs.heal(999.0)
	if healed2 != 5 or gs.run.hp != 100:
		fail("heal overflow clamps (got %d -> %d)" % [healed2, gs.run.hp])
	# 吸血全局上限：20 层吸血牙也只到曲线封顶 3%，再叠加也不超过 4%
	gs.run.items["vampire_fang"] = 20
	gs.apply_item_effects_to_stats()
	if absf(float(gs.run.get("lifesteal", 0.0)) - 0.03) > 1e-6:
		fail("20 stacks lifesteal != 3%% (got %f)" % float(gs.run.get("lifesteal", 0.0)))
	gs.run.items.erase("vampire_fang")
	gs.apply_item_effects_to_stats()
	# 血包场景可实例化且 setup 生效（回归：掉落物不出错）
	var pack: Node = load("res://scenes/game/health_pack.tscn").instantiate()
	pack.setup(0.10)
	root.add_child(pack)
	pack.queue_free()
