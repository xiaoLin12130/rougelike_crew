extends Node2D
## 验证：四选一（roll_item_choices(4)）+ 主流派保底（≥3 件时至少 1 选项来自主流派）
## 运行：godot --headless --path . res://scripts/tests/diag_choices4.tscn

func _ready() -> void:
	await get_tree().physics_frame
	var gs: Node = get_tree().root.get_node("GameState")
	# 场景 1：空构筑 → 4 个选项
	gs.run.items = {}
	gs.run.grid = []
	var c1: Array = gs.roll_item_choices(4)
	print("[C4] 空构筑: %d 个选项 (期望 4)" % c1.size())
	# 场景 2：持有 3 件 fire 道具 → 至少 1 个 fire 选项
	gs.run.items = {"fire_ember_ring": 3}
	gs.run.grid = [{"core": "fireball", "shell": "rapid"}]
	var fire_hits := 0
	var main_hits := 0
	for i in 200:
		var c2: Array = gs.roll_item_choices(4)
		if c2.size() != 4:
			print("[C4] FAIL: 选项数 %d" % c2.size())
			get_tree().quit(1)
			return
		for ch in c2:
			if str(ch.get("id", "")).begins_with("spell_part:fire"):
				fire_hits += 1
				break
			if gs._element_key(ch) == "fire":
				fire_hits += 1
				break
	for i in 200:
		var c3: Array = gs.roll_item_choices(4)
		var has_main := false
		for ch in c3:
			if gs._element_key(ch) == "fire":
				has_main = true
				break
		if has_main:
			main_hits += 1
	print("[C4] 持有3火: 200局中fire出现局数=%d (期望≥150, +10%/件保底)" % main_hits)
	print("[C4] %s" % ("ALL OK" if c1.size() == 4 and main_hits >= 150 else "FAIL"))
	get_tree().quit(0 if c1.size() == 4 and main_hits >= 150 else 1)
