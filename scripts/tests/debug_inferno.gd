extends Node2D
## 临时诊断：复现 test_core_mechanics 的 inferno 伤害检查
const PROJECTILE_SCENE := preload("res://scenes/game/projectile.tscn")

func _ready() -> void:
	GameState.run.crit_chance = 0.0
	var player := CharacterBody2D.new()
	player.position = Vector2(100, 100)
	player.add_to_group("player")
	add_child(player)
	var e = load("res://scenes/game/enemy.tscn").instantiate()
	e.setup("slime", 1, 1)
	e.global_position = Vector2(620, 160)
	e.speed = 0.0
	add_child(e)
	var e2 = load("res://scenes/game/enemy.tscn").instantiate()
	e2.setup("slime", 1, 1)
	e2.global_position = Vector2(670, 160)
	e2.speed = 0.0
	add_child(e2)
	print("DEBUG max_hp=", e.max_hp, " armor=", e.armor, " hp=", e.hp)
	var proj = PROJECTILE_SCENE.instantiate()
	proj.setup({
		"position": Vector2(400, 160), "direction": Vector2.RIGHT, "speed": 0.0,
		"range": 220.0, "damage": 22.0, "element": "fire", "aoe": 64.0,
		"mods": {}, "status": {"burn": 2.0}, "chain": 0,
	})
	add_child(proj)
	var full: float = e.max_hp
	var frames := 0
	while e.hp >= full and frames < 60:
		await get_tree().physics_frame
		frames += 1
	print("DEBUG hit after frames=", frames)
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("DEBUG e1.hp=", e.hp, " expect=", e.max_hp - 22.0, " burn_dps=", e._burn_dps, " burn_left=", e._burn_left)
	print("DEBUG e2.hp=", e2.hp, " expect=", e2.max_hp - 22.0)
	get_tree().quit(0)
