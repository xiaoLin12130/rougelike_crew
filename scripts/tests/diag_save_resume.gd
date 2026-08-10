extends Node2D
## 存档问题深入研究：不切场景，直接实例化节点模拟完整链路
## 运行：godot --headless --path . res://scripts/tests/diag_save_resume.tscn

var gs: Node
var store: Node

func _ready() -> void:
	await get_tree().physics_frame
	gs = get_tree().root.get_node("GameState")
	store = get_tree().root.get_node("SaveStore")
	store.clear_save()
	gs.new_run()
	gs.run.level = 3
	gs.run.grid = [{"core": "fireball", "shell": "rapid"}, {"core": "ice_shard", "shell": "pierce"}]
	gs.run.items = {"fire_ember_ring": 2}
	gs.run.gold = 500
	gs.run.hp = 70
	gs.run.max_hp = 120
	gs.run.level_elapsed = 42.5
	# 步骤1：启动游戏场景
	var gr: Node = load("res://scenes/game/game_root.tscn").instantiate()
	add_child(gr)
	await _frames(60)
	print("[SR] 游戏运行: level=%d LevelNode=%s hp=%d elapsed=%.1f" % [
		gs.run.level, gr.has_node("Level"), gs.run.hp, gs.run.level_elapsed])
	# 步骤2：模拟返回主菜单（pause_menu._back 等效）
	gs.run.level_elapsed = 42.5  # 模拟已打了一段时间（波次进度）
	store.save_run(gs.run)
	gr.queue_free()
	await _frames(10)
	var menu: Node = load("res://scenes/main_menu.tscn").instantiate()
	add_child(menu)
	await _frames(20)
	print("[SR] 主菜单: has_save=%s ContinueButton.disabled=%s" % [
		store.has_save(), menu.get_node_or_null("ContinueButton").disabled])
	# 步骤3：模拟继续（main_menu._on_continue 等效）
	var data: Dictionary = store.load_run()
	if data.is_empty():
		print("[SR] FAIL: 读档为空")
		get_tree().quit(1)
		return
	gs.run = data
	gs.run["resumed"] = true
	menu.queue_free()
	await _frames(10)
	var gr2: Node = load("res://scenes/game/game_root.tscn").instantiate()
	add_child(gr2)
	await _frames(60)
	var ok := true
	if not gr2.has_node("Level"):
		ok = false
		print("[SR] FAIL: 继续后关卡未初始化")
	var player := gr2.get_node_or_null("Player")
	if player == null and gr2.get_node_or_null("PlayerCharacter") == null:
		ok = false
		print("[SR] FAIL: 继续后玩家缺失")
	print("[SR] 继续后: level=%d grid=%d gold=%d hp=%d elapsed=%.1f" % [
		gs.run.level, gs.run.grid.size(), gs.run.gold, gs.run.hp, gs.run.level_elapsed])
	if gs.run.level != 3: ok = false; print("[SR] FAIL: level=%d" % gs.run.level)
	if gs.run.grid.size() != 2: ok = false; print("[SR] FAIL: grid=%d" % gs.run.grid.size())
	if gs.run.gold != 500: ok = false; print("[SR] FAIL: gold=%d" % gs.run.gold)
	if gs.run.level_elapsed < 42.0: ok = false; print("[SR] FAIL: 波次进度未保留 elapsed=%.1f (期望>=42)" % gs.run.level_elapsed)
	print("[SR] %s" % ("FULL FLOW OK" if ok else "FULL FLOW FAIL"))
	get_tree().quit(0 if ok else 1)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
