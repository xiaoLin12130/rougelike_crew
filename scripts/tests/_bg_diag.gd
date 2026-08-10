extends SceneTree

func _init() -> void:
	var gs: Node = load("res://scripts/core/game_state.gd").new()
	root.add_child(gs)
	var level: Node = load("res://scenes/game/level.tscn").instantiate()
	level.init_level("level_1")
	root.add_child(level)
	for c in level.get_children():
		print("[BG] child: ", c.name, " type=", c.get_class())
		if c is Sprite2D:
			var s := c as Sprite2D
			print("   texture=", s.texture.resource_path if s.texture != null else "NULL",
				" scale=", s.scale, " modulate=", s.modulate, " z=", s.z_index)
		elif c.name == "Floor":
			print("   floor tilemap present")
	quit(0)
