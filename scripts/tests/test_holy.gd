extends Node2D
## 机制补全批次回归测试（mech_fill_batch，基于 docs/design/流派机制缺口审计.md 第 6 节）：
## ① 圣光流：光M4 治疗光环（player_move）/ 光M1 圣盾护佑（player_hit）
##    持有对应 holy_mN 道具后钩子触发，无道具不触发；
## ② 毒系门控（G4）：仅 poison_essence（数值）无 poison_m1 时传染不触发，
##    持有 poison_m1 后传染触发（放大器强度乘区保留）；
## ③ melee 四叶草（0 层泄漏）：无 lucky_clover 时重掷路径不进入（守卫存在），
##    持有后重掷曲线生效。
## 运行：godot --headless --path . res://scripts/tests/test_holy.tscn

const ENEMY_SCENE := preload("res://scenes/game/enemy.tscn")
const MELEE_SCRIPT := preload("res://scripts/combat/melee_attack.gd")

var _failures: Array[String] = []
var _player: Node2D


func _ready() -> void:
	SynergyRegistry.load_synergy_scripts()
	await get_tree().process_frame
	GameState.new_run()
	GameState.run.crit_chance = 0.0
	GameState.run.crit_dmg_bonus = 1.5
	GameState.run.hp = GameState.run.max_hp
	randomize()
	_player = Node2D.new()
	_player.name = "TestPlayer"
	_player.global_position = Vector2(300, 300)
	_player.add_to_group("player")
	add_child(_player)
	await _test_holy_m4_aura()
	await _test_holy_m1_shield()
	await _test_poison_gate()
	await _test_melee_clover()
	if _failures.is_empty():
		print("HOLY TEST ALL PASS")
		get_tree().quit(0)
	else:
		for f in _failures:
			push_error("[TEST] FAIL: " + f)
		print("HOLY TEST FAILED: %d" % _failures.size())
		get_tree().quit(1)


func _fail(msg: String) -> void:
	_failures.append(msg)
	print("[TEST] FAIL: " + msg)


func _items(d: Dictionary) -> void:
	GameState.run.items = d.duplicate()


func _spawn_enemy(pos: Vector2) -> Node:
	var e = ENEMY_SCENE.instantiate()
	e.setup("slime", 1, 1)
	e.global_position = pos
	e.speed = 0.0
	e.attack = 0
	add_child(e)
	return e


func _trigger(kind: String, ctx: Dictionary) -> void:
	SynergyRegistry.trigger(kind, ctx)


func _synergy(script_path: String) -> Node:
	for c in SynergyRegistry.get_children():
		if c.get_script() != null and str(c.get_script().resource_path) == script_path:
			return c
	return null


func _clear_entities() -> void:
	for c in get_children():
		if c == _player:
			continue
		if c.has_method("take_damage") or c.get_script() != null:
			c.queue_free()
	await get_tree().process_frame


# ================= ① 圣光流：光M4 治疗光环（player_move） =================

func _test_holy_m4_aura() -> void:
	var holy := _synergy("res://scripts/synergies/holy_synergy.gd")
	if holy == null:
		_fail("holy_synergy not loaded")
		return
	# 基线：无道具 → 移动不回复
	_items({})
	GameState.run.hp = GameState.run.max_hp - 20
	var hp0: int = GameState.run.hp
	_trigger("player_move", {"player": _player, "velocity": Vector2(100, 0), "delta": 0.5})
	_trigger("player_move", {"player": _player, "velocity": Vector2(100, 0), "delta": 0.5})
	if GameState.run.hp != hp0:
		_fail("aura heals without holy_m4 (leak: %d -> %d)" % [hp0, GameState.run.hp])
	# 持有 holy_m4 → 光环触发回复
	_items({"holy_m4": 1})
	GameState.run.hp = GameState.run.max_hp - 20
	hp0 = GameState.run.hp
	_trigger("player_move", {"player": _player, "velocity": Vector2(100, 0), "delta": 0.5})
	_trigger("player_move", {"player": _player, "velocity": Vector2(100, 0), "delta": 0.5})
	if GameState.run.hp <= hp0:
		_fail("aura did not heal with holy_m4 (hp %d -> %d)" % [hp0, GameState.run.hp])
	_items({})


# ================= ① 圣光流：光M1 圣盾护佑（player_hit） =================

func _test_holy_m1_shield() -> void:
	var holy := _synergy("res://scripts/synergies/holy_synergy.gd")
	# 基线：无道具 → 不授予护盾
	_items({})
	holy._shield = 0.0
	_trigger("player_hit", {"dmg": 10, "pos": _player.global_position, "taken": 10.0, "attacker": null})
	if float(holy._shield) > 0.0:
		_fail("shield granted without holy_m1 (leak)")
	# 持有 holy_m1 → 受击授予护盾
	_items({"holy_m1": 1})
	GameState.run.hp = GameState.run.max_hp - 10
	holy._shield = 0.0
	_trigger("player_hit", {"dmg": 10, "pos": _player.global_position, "taken": 10.0, "attacker": null})
	if float(holy._shield) <= 0.0:
		_fail("shield not granted with holy_m1")
	_items({})


# ================= ② 毒系门控：传染需 poison_m1 =================

func _test_poison_gate() -> void:
	var poison := _synergy("res://scripts/synergies/poison_synergy.gd")
	if poison == null:
		_fail("poison_synergy not loaded")
		return
	# 仅数值道具 poison_essence（无 poison_m1）：传染永不触发
	_items({"poison_essence": 1})
	var spread := 0
	for i in range(60):
		await _clear_entities()
		var e1 := _spawn_enemy(Vector2(400, 300))
		var e2 := _spawn_enemy(Vector2(440, 300))
		EventBus.apply_status.emit(e1, "poison", 1)
		_trigger("enemy_died", {"enemy": e1, "pos": e1.global_position})
		if float(e2.get("_poison_left")) > 0.0:
			spread += 1
	if spread != 0:
		_fail("poison spread fired without poison_m1 (%d/60)" % spread)
	# 持有 poison_m1：传染按概率触发（15% 起，60 次尝试几乎必中）
	_items({"poison_essence": 1, "poison_m1": 1})
	spread = 0
	for i in range(60):
		await _clear_entities()
		var e1 := _spawn_enemy(Vector2(400, 300))
		var e2 := _spawn_enemy(Vector2(440, 300))
		EventBus.apply_status.emit(e1, "poison", 1)
		_trigger("enemy_died", {"enemy": e1, "pos": e1.global_position})
		if float(e2.get("_poison_left")) > 0.0:
			spread += 1
	if spread == 0:
		_fail("poison spread never fired with poison_m1 (60 tries)")
	_items({})
	await _clear_entities()


# ================= ③ melee 四叶草：0 层重掷泄漏守卫 =================

func _test_melee_clover() -> void:
	# 静态守卫检查：melee_attack.gd 必须先判 0 层再进入重掷分支
	var f := FileAccess.open("res://scripts/combat/melee_attack.gd", FileAccess.READ)
	if f == null:
		_fail("cannot read melee_attack.gd for guard check")
	else:
		var src: String = f.get_as_text()
		f.close()
		if not src.contains("clover_stacks > 0"):
			_fail("melee_attack.gd 缺 lucky_clover 0 层守卫（重掷泄漏）")
	var melee := MELEE_SCRIPT.new()
	add_child(melee)
	# 行为基线：无四叶草、暴击率 0 → 300 次重掷路径不可产出暴击（泄漏守卫生效）
	_items({})
	GameState.run.crit_chance = 0.0
	var crits := 0
	for i in range(300):
		if melee._roll_crit():
			crits += 1
	if crits != 0:
		_fail("melee crit without lucky_clover at 0% chance (%d/300)" % crits)
	# 持有四叶草：重掷曲线生效（暴击率 20% + 20 层重掷 ≈ 11.5%+ → 显著高于基线）
	_items({"lucky_clover": 20})
	GameState.run.crit_chance = 0.2
	crits = 0
	for i in range(400):
		if melee._roll_crit():
			crits += 1
	if crits < 90:
		_fail("lucky_clover reroll not working (crits %d/400 < 90)" % crits)
	melee.queue_free()
	_items({})
