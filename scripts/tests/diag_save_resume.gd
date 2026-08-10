extends Node2D
## 复现：开始游戏 → 游玩 → 返回主菜单（保存）→ 继续（读档恢复，完整场景切换）
## 运行：godot --headless --path . res://scripts/tests/diag_save_resume.tscn

func _ready() -> void:
	await get_tree().physics_frame
	var gs: Node = get_tree().root.get_node("GameState")
	var store: Node = get_tree().root.get_node("SaveStore")
	store.clear_save()
	# 1) 准备游玩状态
	gs.new_run()
	gs.run.level = 3
	gs.run.grid = [{"core": "fireball", "shell": "rapid"}, {"core": "ice_shard", "shell": "pierce"}]
	gs.run.items = {"fire_ember_ring": 2, "poison_essence": 1}
	gs.run.gold = 500
	gs.run.hp = 70
	gs.run.max_hp = 120
	gs.run.level_elapsed = 42.5
	gs.run.time = 300.0
	# 2) 进入游戏（完整场景）
	store.save_run(gs.run)
	get_tree().change_scene_to_file("res://scenes/game/game_root.tscn")
	await _frames(60)
	var gr: Node = get_tree().current_scene
	if gr == null or not gr.has_node("LevelNode"):
		print("[SAVE] FAIL: 游戏场景未正常初始化")
		get_tree().quit(1)
		return
	print("[SAVE] 游戏运行中: level=%d hp=%d elapsed=%.1f" % [gs.run.level, gs.run.hp, gs.run.level_elapsed])
	# 3) 模拟返回主菜单（pause_menu._back 等效）
	store.save_run(gs.run)
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	await _frames(60)
	var menu: Node = get_tree().current_scene
	if menu == null:
		print("[SAVE] FAIL: 主菜单未加载")
		get_tree().quit(1)
		return
	print("[SAVE] 返回主菜单: has_save=%s" % store.has_save())
	# 4) 模拟继续（main_menu._on_continue 等效）
	var data: Dictionary = store.load_run()
	if data.is_empty():
		print("[SAVE] FAIL: 读档为空")
		get_tree().quit(1)
		return
	gs.run = data
	get_tree().change_scene_to_file("res://scenes/game/game_root.tscn")
	await _frames(60)
	var gr2: Node = get_tree().current_scene
	var ok := true
	if gr2 == null:
		ok = false
		print("[SAVE] FAIL: 继续后游戏场景为空")
	elif not gr2.has_node("LevelNode"):
		ok = false
		print("[SAVE] FAIL: 继续后关卡未初始化")
	print("[SAVE] 继续后: level=%d grid=%d items=%d gold=%d hp=%d elapsed=%.1f scene=%s" % [
		gs.run.level, gs.run.grid.size(), gs.run.items.size(), gs.run.gold,
		gs.run.hp, gs.run.level_elapsed, gr2.name if gr2 else "NULL"])
	if gs.run.level != 3: ok = false; print("[SAVE] FAIL: level=%d" % gs.run.level)
	if gs.run.grid.size() != 2: ok = false; print("[SAVE] FAIL: grid=%d" % gs.run.grid.size())
	if gs.run.gold != 500: ok = false; print("[SAVE] FAIL: gold=%d" % gs.run.gold)
	print("[SAVE] %s" % ("FULL FLOW OK" if ok else "FULL FLOW FAIL"))
	get_tree().quit(0 if ok else 1)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
