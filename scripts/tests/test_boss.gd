extends Node2D
## 最小 Boss 测试：实例化 → 打一拳 → 验证掉血与死亡

func _ready() -> void:
	var scene := preload("res://scenes/game/boss.tscn")
	var boss := scene.instantiate()
	boss.setup_boss("slime_king", 1, 1)  # setup 必须先于 add_child（_ready 会读 conf 建精灵）
	add_child(boss)
	print("[TEST] boss max_hp=", boss.max_hp)
	boss.take_damage(100, "fire", false)
	await get_tree().create_timer(0.2).timeout
	print("[TEST] after 100 dmg hp=", boss.hp)
	boss.take_damage(int(boss.hp) + 10, "fire", false)
	await get_tree().create_timer(0.2).timeout
	print("[TEST] after lethal freed=", not is_instance_valid(boss))
	print("[TEST] DONE")
	get_tree().quit(0)
