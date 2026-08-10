extends Node2D
func _ready() -> void:
	# 模拟完整场景：game_root 结构（玩家 + level + 怪物 + 相机）
	GameState.new_run()
	GameState.run.level = 1
	var cam := Camera2D.new()
	cam.script = load("res://scripts/fx/camera_shake.gd")
	cam.add_to_group("camera")
	add_child(cam)
	var player_scene = load("res://scenes/game/player.tscn")
	var player = player_scene.instantiate()
	player.add_to_group("player")
	player.global_position = Vector2(640, 360)
	add_child(player)
	var level_scene = load("res://scenes/game/level.tscn")
	var level = level_scene.instantiate()
	add_child(level)
	level.call("init_level", "level_1")
	await get_tree().process_frame
	await get_tree().process_frame
	# 直接生成一只怪物在固定位置
	var enemy_scene = load("res://scenes/game/enemy.tscn")
	var e = enemy_scene.instantiate()
	e.setup("slime", 1, 1)
	e.global_position = Vector2(500, 500)
	e.speed = 0.0
	e.attack = 0
	level.add_child(e)
	await get_tree().process_frame
	var e_before: Vector2 = e.global_position
	var p_before: Vector2 = player.global_position
	# 模拟玩家向右移动 100px
	player.global_position += Vector2(100, 0)
	await get_tree().process_frame
	await get_tree().process_frame
	var e_after: Vector2 = e.global_position
	var p_after: Vector2 = player.global_position
	print("P_BEFORE=", p_before, " P_AFTER=", p_after)
	print("E_BEFORE=", e_before, " E_AFTER=", e_after)
	var ok: bool = e_after == e_before and p_after != p_before
	print("ENEMY_STATIC_", "OK" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
