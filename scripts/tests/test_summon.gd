extends Node2D
## 召唤物测试：3 秒内应主动接近并攻击敌人（敌人 hp 下降）

func _ready() -> void:
	var enemy_scene := preload("res://scenes/game/enemy.tscn")
	var e := enemy_scene.instantiate()
	e.setup("slime", 1, 1)
	e.global_position = Vector2(500, 360)
	add_child(e)
	var player := CharacterBody2D.new()
	player.position = Vector2(640, 360)
	add_child(player)
	var summon: Node = load("res://scripts/combat/summon.gd").new()
	summon.setup(player, 10.0, "summon")
	add_child(summon)
	summon.global_position = player.position
	print("[TEST] enemy hp before:", e.hp)
	await get_tree().create_timer(3.5).timeout
	print("[TEST] enemy hp after:", e.hp)
	print("[TEST] DONE")
	get_tree().quit(0)
