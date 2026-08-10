extends Node2D
func _ready() -> void:
	# 模拟真实场景：加相机 + 玩家 + level
	var cam := Camera2D.new()
	cam.name = "SimCam"
	cam.add_to_group("camera")
	cam.zoom = Vector2(1.15, 1.15)
	cam.global_position = Vector2(640, 360)
	add_child(cam)
	var level_scene = load("res://scenes/game/level.tscn")
	var level = level_scene.instantiate()
	add_child(level)
	level.call("_build_scene_background", "grass")
	await get_tree().process_frame
	await get_tree().process_frame
	var bg: Sprite2D = level.get_node_or_null("SceneBackground")
	print("BG tex=", bg.texture.get_width(), "x", bg.texture.get_height())
	print("BG scale=", bg.scale, " pos=", bg.position)
	var vis: Rect2 = level.call("_camera_visible_rect")
	print("VIS=", vis)
	var nan: bool = (bg.scale.x != bg.scale.x) or (bg.position.x != bg.position.x) or vis.size.x <= 0.0 or vis.size.y <= 0.0
	print("BG_VALID_", "OK" if not nan else "FAIL")
	get_tree().quit(0 if not nan else 1)
