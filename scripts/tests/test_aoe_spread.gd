extends Node2D
## AOE 瞬发核多弹分散测试（问题3）：
## 毒雾/闪电/闪光 × shots=5（齐射壳 spread_angle=24°）：落点两两间距 >= 爆炸半径
##  - 毒雾 48px / 闪电 26px / 闪光盲爆 90px（数据 speed=0 的瞬发核）
##  - 断言 5 个弹幕落点两两间距 >= 爆炸半径 - 8（例：毒雾 48 -> 间距 >= 40）
##  - 弹幕方向全部互不相同（多弹确实分散）
## Run: godot --headless --path . res://scripts/tests/test_aoe_spread.tscn

const SPELL_CASTER_SCRIPT := preload("res://scripts/combat/spell_caster.gd")
const PROJECTILE_SCRIPT := preload("res://scripts/combat/projectile.gd")
const PROJECTILE_SCENE := preload("res://scenes/game/projectile.tscn")

var _failures: Array[String] = []


func _ready() -> void:
	GameState.run.crit_chance = 0.0  # 固定伤害，避免暴击扰动
	GameState.run.crit_dmg_bonus = 1.5
	GameState.run.hp = GameState.run.max_hp
	GameState.run.wands = ["basic_wand"]
	var player := CharacterBody2D.new()
	player.name = "TestPlayer"
	player.global_position = Vector2(100, 100)
	player.add_to_group("player")
	add_child(player)
	await _test_aoe_spread()
	if _failures.is_empty():
		print("[TEST] AOE SPREAD ALL PASS")
		get_tree().quit(0)
	else:
		for f in _failures:
			push_error("[TEST] FAIL: " + f)
		print("AOE SPREAD FAILED: %d" % _failures.size())
		get_tree().quit(1)


func _fail(msg: String) -> void:
	_failures.append(msg)
	print("[TEST] FAIL: " + msg)


func _core(core_id: String) -> Dictionary:
	for c in GameState.tables.get("spells", {}).get("cores", []):
		if str(c.get("id", "")) == core_id:
			return c
	return {}


func _projectiles() -> Array:
	var out: Array = []
	for c in get_children():
		if c.get_script() == PROJECTILE_SCRIPT:
			out.append(c)
	return out


func _clear_projectiles() -> void:
	for c in _projectiles():
		c.queue_free()
	await get_tree().physics_frame


## 齐射壳（spread，即任务所称 scatter 外壳）：shots=5 + spread_angle=24
func _test_aoe_spread() -> void:
	for cid in ["poison_cloud", "lightning", "flash"]:
		await _clear_projectiles()
		var core := _core(cid)
		var mods := {"shots": 5, "spread_angle": 24.0, "damage_mult": 0.7, "cooldown_mult": 1.5}
		var caster := SPELL_CASTER_SCRIPT.new()
		add_child(caster)
		var player: Node = get_tree().get_first_node_in_group("player")
		caster._cast(player, core, mods)
		var projs := _projectiles()
		if projs.size() != 5:
			_fail("%s x spread shell: expect 5 projectiles, got %d" % [cid, projs.size()])
			caster.queue_free()
			continue
		# 期望爆炸半径：aoe 字段；flash 数据 aoe=0，用盲爆半径 90（aoe_mult=1）
		var radius: float = float(core.get("aoe", 0.0))
		if radius <= 0.0:
			radius = 90.0
		var lands: Array = []
		var dirs := {}
		for p in projs:
			var d: Vector2 = p._dir
			dirs["%.4f,%.4f" % [d.x, d.y]] = true
			lands.append(p._spawn_pos + d * float(p._range))
		if dirs.size() != 5:
			_fail("%s: 5 projectiles must have distinct directions (got %d)" % [cid, dirs.size()])
		var min_dist := INF
		for i in lands.size():
			for j in range(i + 1, lands.size()):
				min_dist = minf(min_dist, lands[i].distance_to(lands[j]))
		var threshold: float = radius - 8.0
		if min_dist < threshold:
			_fail("%s: landing min spacing %.1fpx < %.1fpx (radius %.1f)" % [cid, min_dist, threshold, radius])
		else:
			print("[TEST] %s x5 spread: min landing spacing %.1fpx >= %.1fpx PASS" % [cid, min_dist, threshold])
		caster.queue_free()
		await _clear_projectiles()
