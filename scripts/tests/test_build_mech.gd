extends Node2D
## N2 验收测试：三流派机制构筑触发 / 无效道具修复 / 构筑筛选
## Run: godot --headless --path . res://scripts/tests/test_build_mech.tscn

const ENEMY_SCENE := preload("res://scenes/game/enemy.tscn")
const PROJECTILE_SCENE := preload("res://scenes/game/projectile.tscn")
const PICKUP_SCENE := preload("res://scenes/game/item_pickup.tscn")

var _failures: Array[String] = []


func _ready() -> void:
	SynergyRegistry.load_synergy_scripts()
	await get_tree().process_frame
	GameState.new_run()
	GameState.run.crit_chance = 0.0
	GameState.run.crit_dmg_bonus = 1.5
	GameState.run.hp = GameState.run.max_hp
	randomize()
	await _test_poison()
	await _test_thunder()
	await _test_crit()
	await _test_invalid_items()
	await _test_filter()
	if _failures.is_empty():
		print("BUILD MECH OK")
		get_tree().quit(0)
	else:
		for f in _failures:
			push_error("[TEST] FAIL: " + f)
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


func _player_with_caster(cds: Array) -> Node:
	## 返回 SpellCaster 节点（调用处用 caster._cds 读冷却、caster.get_parent() 取玩家）
	## 同步清理旧玩家：queue_free 是延迟的，残留玩家会让 _find_spell_caster 命中已释放的 caster
	for p in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(p):
			p.free()
	var player := CharacterBody2D.new()
	player.name = "Player"
	player.global_position = Vector2(300, 300)
	player.add_to_group("player")
	var script := GDScript.new()
	script.source_code = "extends Node\nvar _cds: Array = []"
	script.reload()
	var caster := Node.new()
	caster.name = "SpellCaster"
	caster.set_script(script)
	caster._cds = cds
	player.add_child(caster)
	add_child(player)
	return caster


func _synergy(script_path: String) -> Node:
	for c in SynergyRegistry.get_children():
		if c.get_script() != null and str(c.get_script().resource_path) == script_path:
			return c
	return null


func _trigger(kind: String, ctx: Dictionary) -> void:
	SynergyRegistry.trigger(kind, ctx)


func _clear_entities() -> void:
	for c in get_children():
		if c.has_method("take_damage") or c.get_script() != null:
			c.queue_free()
	await get_tree().process_frame


# ================= 毒系机制（poison_m1..m10 代码路径） =================

func _test_poison() -> void:
	var poison := _synergy("res://scripts/synergies/poison_synergy.gd")
	if poison == null:
		_fail("poison_synergy not loaded")
		return
	# 毒M1 传染：中毒敌人死亡概率扩散毒（m1=10 → 24%）
	_items({"poison_m1": 10})
	var e1 := _spawn_enemy(Vector2(600, 100))
	var e2 := _spawn_enemy(Vector2(630, 100))
	var spread := false
	for i in 200:
		if not is_instance_valid(e1) or not is_instance_valid(e2):
			break
		EventBus.apply_status.emit(e1, "poison", 1)
		_trigger("enemy_died", {"enemy": e1, "pos": e1.global_position})
		if float(e2.get("_poison_left")) > 0.0:
			spread = true
			break
	if not spread:
		_fail("poison_m1 spread not triggered")
	await _clear_entities()
	# 毒M2 毒爆：毒层叠满爆炸（cap=5），范围毒伤
	_items({"poison_m2": 1})
	e1 = _spawn_enemy(Vector2(600, 160))
	e2 = _spawn_enemy(Vector2(630, 160))
	for i in 5:
		EventBus.apply_status.emit(e1, "poison", 1)
	var hp_before: float = e2.hp
	_trigger("enemy_status", {"enemy": e1, "kind": "poison", "delta": 0.1})
	if e2.hp >= hp_before:
		_fail("poison_m2 burst not triggered")
	await _clear_entities()
	# 毒M8 解毒反哺：毒伤按比例回血（5%）
	_items({"poison_m8": 1})
	e1 = _spawn_enemy(Vector2(600, 220))
	e1._poison_left = 3.0
	e1._poison_dps = 1000.0
	GameState.run.hp = 50
	_trigger("enemy_status", {"enemy": e1, "kind": "poison", "delta": 0.5})
	if GameState.run.hp < 70:
		_fail("poison_m8 feed-heal not triggered (hp=%d)" % GameState.run.hp)
	await _clear_entities()
	# 毒M9 疫病之源：中毒敌人死亡孵化毒爆虫（8%，200 次必出）
	_items({"poison_m9": 1})
	e1 = _spawn_enemy(Vector2(600, 280))
	var bug := false
	for i in 200:
		if not is_instance_valid(e1):
			break
		EventBus.apply_status.emit(e1, "poison", 1)
		var before := get_tree().get_nodes_in_group("enemy").size()
		_trigger("enemy_died", {"enemy": e1, "pos": e1.global_position})
		if get_tree().get_nodes_in_group("enemy").size() > before:
			bug = true
			break
	if not bug:
		_fail("poison_m9 bug spawn not triggered")
	await _clear_entities()


# ================= 雷系机制（thunder_m1..m10 代码路径） =================

func _test_thunder() -> void:
	var thunder := _synergy("res://scripts/synergies/thunder_synergy.gd")
	if thunder == null:
		_fail("thunder_synergy not loaded")
		return
	var caster := _player_with_caster([10.0])
	# 雷M6 雷暴回响：链跳命中回 1% 冷却
	_items({"thunder_m6": 1})
	var e := _spawn_enemy(Vector2(360, 300))
	_trigger("projectile_hit", {"enemy": e, "dmg": 10, "element": "lightning", "crit": false, "pos": e.global_position})
	if float(caster._cds[0]) >= 10.0:
		_fail("thunder_m6 cd refund not triggered")
	# 雷M1 麻痹：15% 概率（200 次必出）
	_items({"thunder_m1": 10})
	var para := false
	for i in 200:
		if not is_instance_valid(e):
			break
		_trigger("projectile_hit", {"enemy": e, "dmg": 10, "element": "lightning", "crit": false, "pos": e.global_position})
		if float(e.get("_root_left")) > 0.0:
			para = true
			break
	if not para:
		_fail("thunder_m1 paralyze not triggered")
	# 雷M8 超载线圈：同目标 3 次命中爆炸
	_items({"thunder_m8": 1})
	var e2 := _spawn_enemy(Vector2(420, 300))
	for i in 3:
		if not is_instance_valid(e):
			break
		_trigger("projectile_hit", {"enemy": e, "dmg": 10, "element": "lightning", "crit": false, "pos": e.global_position})
	if is_instance_valid(e2) and e2.hp >= e2.max_hp:
		_fail("thunder_m8 overload explosion not triggered")
	# 雷M2 雷暴：击杀 12% 降雷（200 次必出）
	_items({"thunder_m2": 10})
	e = _spawn_enemy(Vector2(360, 300))
	e2 = _spawn_enemy(Vector2(400, 300))
	var storm := false
	for i in 200:
		if not is_instance_valid(e):
			e = _spawn_enemy(Vector2(360, 300))
		if not is_instance_valid(e2):
			break
		_trigger("enemy_died", {"enemy": e, "pos": e.global_position})
		if float(e2.hp) < float(e2.max_hp):
			storm = true
			break
	if not storm:
		_fail("thunder_m2 kill-strike not triggered")
	# 雷M4 过载：麻痹目标受击必暴（补足暴击差额）
	_items({"thunder_m4": 1})
	e = _spawn_enemy(Vector2(360, 300))
	e._root_left = 1.0
	var hp_before: float = e.hp
	_trigger("enemy_hit", {"enemy": e, "dmg": 50, "element": "lightning", "crit": false})
	if float(e.hp) >= float(hp_before) - 24.0:
		_fail("thunder_m4 overload crit not triggered")
	# 雷M3 静电积累：移动充能释放电弧
	_items({"thunder_m3": 1})
	e = _spawn_enemy(Vector2(360, 300))
	for i in 4:
		_trigger("player_move", {"player": caster.get_parent(), "velocity": Vector2(100, 0), "delta": 1.0})
	if is_instance_valid(e) and float(e.hp) >= float(e.max_hp):
		_fail("thunder_m3 static arc not triggered")
	# 雷M5 导雷：每 3s 微型闪电
	_items({"thunder_m5": 1})
	e = _spawn_enemy(Vector2(360, 300))
	thunder.call("_tick_conduit", 3.0)
	if is_instance_valid(e) and float(e.hp) >= float(e.max_hp):
		_fail("thunder_m5 conduit not triggered")
	# 雷M9 雷云风暴 / 雷云（storm_cloud）：周期落雷
	_items({"thunder_m9": 1})
	e = _spawn_enemy(Vector2(360, 300))
	thunder.call("_tick_storm", 5.0)
	if is_instance_valid(e) and float(e.hp) >= float(e.max_hp):
		_fail("thunder_m9 storm not triggered")
	await _clear_entities()
	_items({"storm_cloud": 2})
	e = _spawn_enemy(Vector2(360, 300))
	thunder.call("_tick_storm_cloud", 3.0)
	if is_instance_valid(e) and float(e.hp) >= float(e.max_hp):
		_fail("storm_cloud strikes not triggered")
	# 雷M10 高压电网：麻痹死亡电爆
	_items({"thunder_m10": 1})
	e = _spawn_enemy(Vector2(360, 300))
	e._root_left = 1.0
	e2 = _spawn_enemy(Vector2(400, 300))
	_trigger("enemy_died", {"enemy": e, "pos": e.global_position})
	if is_instance_valid(e2) and float(e2.hp) >= float(e2.max_hp):
		_fail("thunder_m10 grid chain not triggered")
	# 雷核（trinket_storm）：落雷数量翻倍
	GameState.run.trinkets = ["trinket_storm"]
	if absf(float(thunder.call("_trinket_storm_mult")) - 2.0) > 1e-6:
		_fail("trinket_storm mult != 2")
	GameState.run.trinkets = []
	await _clear_entities()


# ================= 暴击机制（crit_m1..m9 + 致命节奏） =================

func _test_crit() -> void:
	var crit := _synergy("res://scripts/synergies/crit_synergy.gd")
	if crit == null:
		_fail("crit_synergy not loaded")
		return
	# 暴M1 暴击溢出：run.crit_overflow 转真伤
	_items({"crit_m1": 1})
	GameState.run.crit_overflow = 0.5
	var e := _spawn_enemy(Vector2(500, 400))
	var hp_before: float = e.hp
	_trigger("projectile_hit", {"enemy": e, "dmg": 100, "element": "fire", "crit": false, "pos": e.global_position})
	if float(e.hp) >= float(hp_before) - 49.0:
		_fail("crit_m1 overflow true damage not triggered")
	await _clear_entities()
	# 暴M2 暴击吸血
	_items({"crit_m2": 1})
	GameState.run.hp = 50
	GameState.run.max_hp = 100
	e = _spawn_enemy(Vector2(500, 400))
	_trigger("projectile_hit", {"enemy": e, "dmg": 100, "element": "fire", "crit": true, "pos": e.global_position})
	if GameState.run.hp != 52:
		_fail("crit_m2 leech not triggered (hp=%d)" % GameState.run.hp)
	await _clear_entities()
	# 暴M3 暴击连击：连击层数叠伤害，未暴击重置
	_items({"crit_m3": 1})
	e = _spawn_enemy(Vector2(500, 400))
	_trigger("projectile_hit", {"enemy": e, "dmg": 100, "element": "fire", "crit": true, "pos": e.global_position})
	hp_before = float(e.hp)
	_trigger("projectile_hit", {"enemy": e, "dmg": 100, "element": "fire", "crit": true, "pos": e.global_position})
	if float(e.hp) >= float(hp_before) - 14.0:
		_fail("crit_m3 combo bonus not triggered")
	hp_before = float(e.hp)
	_trigger("projectile_hit", {"enemy": e, "dmg": 100, "element": "fire", "crit": false, "pos": e.global_position})
	if float(e.hp) != float(hp_before):
		_fail("crit_m3 combo not reset on non-crit")
	await _clear_entities()
	# 暴M4 暴击减速
	_items({"crit_m4": 1})
	e = _spawn_enemy(Vector2(500, 400))
	_trigger("projectile_hit", {"enemy": e, "dmg": 50, "element": "fire", "crit": true, "pos": e.global_position})
	if float(e.get("_slow_left")) < 0.79:
		_fail("crit_m4 slow not triggered")
	await _clear_entities()
	# 暴M5 暴击爆炸（m5=10 → 80%，30 次必出）
	_items({"crit_m5": 10})
	e = _spawn_enemy(Vector2(500, 400))
	var e2 := _spawn_enemy(Vector2(530, 400))
	var boom := false
	for i in 30:
		_trigger("projectile_hit", {"enemy": e, "dmg": 100, "element": "fire", "crit": true, "pos": e.global_position})
		if is_instance_valid(e2) and float(e2.hp) < float(e2.max_hp):
			boom = true
			break
	if not boom:
		_fail("crit_m5 explosion not triggered")
	await _clear_entities()
	# 暴M6 暴击穿透：补足护甲减免（真伤）
	_items({"crit_m6": 1})
	e = _spawn_enemy(Vector2(500, 400))
	e.armor = 0.5
	hp_before = float(e.hp)
	_trigger("projectile_hit", {"enemy": e, "dmg": 100, "element": "fire", "crit": true, "pos": e.global_position})
	if float(e.hp) >= float(hp_before) - 49.0:
		_fail("crit_m6 pierce not triggered")
	await _clear_entities()
	# 暴M7 暴击回能
	var caster := _player_with_caster([10.0])
	_items({"crit_m7": 1})
	e = _spawn_enemy(Vector2(360, 300))
	_trigger("projectile_hit", {"enemy": e, "dmg": 50, "element": "fire", "crit": true, "pos": e.global_position})
	if float(caster._cds[0]) >= 10.0:
		_fail("crit_m7 cd refund not triggered")
	# 暴M8 完美暴击：暴伤 ≥2.0 且暴击率 100% → 非暴击必强制暴击
	_items({"crit_m8": 1})
	GameState.run.crit_dmg_bonus = 3.0
	GameState.run.crit_chance = 1.0
	e = _spawn_enemy(Vector2(360, 300))
	hp_before = float(e.hp)
	_trigger("projectile_hit", {"enemy": e, "dmg": 50, "element": "fire", "crit": false, "pos": e.global_position})
	if float(e.hp) >= float(hp_before) - 99.0:
		_fail("crit_m8 perfect crit not triggered")
	# 暴M9 暴击攻速 + 致命节奏（触发式）
	_items({"crit_m9": 1})
	GameState.run.crit_dmg_bonus = 1.5
	e = _spawn_enemy(Vector2(360, 300))
	_trigger("projectile_hit", {"enemy": e, "dmg": 50, "element": "fire", "crit": true, "pos": e.global_position})
	if absf(float(GameState.run.get("crit_haste_bonus", 0.0)) - 0.04) > 1e-6:
		_fail("crit_m9 haste not armed")
	crit.call("_tick_n2_haste", 1.0)
	if float(caster._cds[0]) >= 9.97:
		_fail("crit_m9 haste tick not applied")
	crit.call("_tick_n2_haste", 2.0)
	if float(GameState.run.get("crit_haste_bonus", 1.0)) != 0.0:
		_fail("crit_m9 haste not expired")
	_items({"crit_deadly_rhythm": 1})
	GameState.run.crit_haste_bonus = 0.0
	_trigger("projectile_hit", {"enemy": e, "dmg": 50, "element": "fire", "crit": true, "pos": e.global_position})
	if absf(float(GameState.run.get("crit_haste_bonus", 0.0)) - 0.04) > 1e-6:
		_fail("crit_deadly_rhythm not triggered as haste")
	await _clear_entities()


# ================= 无效道具修复 =================

func _test_invalid_items() -> void:
	# 磁铁：拾取半径 +30%/层
	_items({"magnet": 3})
	var pickup = PICKUP_SCENE.instantiate()
	add_child(pickup)
	var r: float = pickup.call("_magnet_radius")
	if absf(r - 148.0) > 1e-6:
		_fail("magnet radius != 148 (got %f)" % r)
	pickup.queue_free()
	# 弹射镜：每 3 层 +1 弹射
	_items({"bounce_mirror": 6})
	var proj = PROJECTILE_SCENE.instantiate()
	proj.setup({"position": Vector2.ZERO, "direction": Vector2.RIGHT, "speed": 100.0,
		"range": 300.0, "damage": 5.0, "element": "fire", "aoe": 0.0, "mods": {}, "status": {}, "chain": 0})
	add_child(proj)
	if proj._bounce_left != 2:
		_fail("bounce_mirror +2 bounce not applied (got %d)" % proj._bounce_left)
	proj.queue_free()
	# 金币袋 / 经验书 tag 乘区（game_root._on_enemy_died 读取）
	_items({"gold_pouch": 1, "xp_book": 1})
	if absf(GameState.aggregate_bonus("gold") - 0.1) > 1e-6:
		_fail("gold_pouch aggregate != 0.1")
	if absf(GameState.aggregate_bonus("xp") - 0.15) > 1e-6:
		_fail("xp_book aggregate != 0.15")
	# 寒冰护符：非冰系命中概率冻结（10 层 ≈68.6%/次，20 次必出）
	_items({"frost_charm": 10})
	GameState.run.crit_chance = 0.0
	var e := _spawn_enemy(Vector2(600, 500))
	var frozen := false
	for i in 20:
		if not is_instance_valid(e):
			break
		var p = PROJECTILE_SCENE.instantiate()
		p.setup({"position": Vector2(500, 500), "direction": Vector2.RIGHT, "speed": 400.0,
			"range": 200.0, "damage": 5.0, "element": "fire", "aoe": 0.0, "mods": {}, "status": {}, "chain": 0})
		add_child(p)
		for j in 60:
			await get_tree().physics_frame
			if not is_instance_valid(p):
				break
		if float(e.get("_freeze_left")) > 0.0:
			frozen = true
			break
	if not frozen:
		_fail("frost_charm freeze not triggered")
	await _clear_entities()
	# 毒液瓶：命中附加毒层
	_items({"venom_flask": 2})
	e = _spawn_enemy(Vector2(600, 560))
	var p = PROJECTILE_SCENE.instantiate()
	p.setup({"position": Vector2(500, 560), "direction": Vector2.RIGHT, "speed": 400.0,
		"range": 200.0, "damage": 5.0, "element": "nature", "aoe": 0.0, "mods": {}, "status": {}, "chain": 0})
	add_child(p)
	var poisoned := false
	for j in 60:
		await get_tree().physics_frame
		if not is_instance_valid(p):
			break
	if float(e.get("_poison_left")) > 0.0:
		poisoned = true
	if not poisoned:
		_fail("venom_flask poison not triggered")
	await _clear_entities()
	# 余烬指环：燃烧时长 +0.6s/层
	_items({"fire_ember_ring": 1})
	e = _spawn_enemy(Vector2(600, 100))
	EventBus.apply_status.emit(e, "burn", 1)
	if float(e.get("_burn_left")) < 2.59:
		_fail("fire_ember_ring burn duration not extended (got %f)" % float(e.get("_burn_left")))
	await _clear_entities()
	# 防御结晶（原 defense_life_crystal 改名）：生命上限聚合生效
	_items({})
	GameState.apply_item_effects_to_stats()
	var base_hp: int = GameState.run.max_hp
	_items({"defense_crystal": 2})
	GameState.apply_item_effects_to_stats()
	if GameState.run.max_hp < base_hp + 49:
		_fail("defense_crystal max_hp not applied (base=%d now=%d)" % [base_hp, GameState.run.max_hp])
	# 石肤：受到伤害 -10%（player_hit 补结）
	_items({"defense_stone_skin": 1})
	GameState.run.hp = 90
	_trigger("player_hit", {"dmg": 50, "taken": 50.0, "pos": Vector2.ZERO, "attacker": null})
	if GameState.run.hp != 95:
		_fail("defense_stone_skin refund not triggered (hp=%d)" % GameState.run.hp)
	# 恐惧咒：受到伤害 -8%
	_items({"curse_fear_word": 1})
	GameState.run.hp = 90
	_trigger("player_hit", {"dmg": 50, "taken": 50.0, "pos": Vector2.ZERO, "attacker": null})
	if GameState.run.hp != 94:
		_fail("curse_fear_word refund not triggered (hp=%d)" % GameState.run.hp)
	# 霜之心：冰霜伤害 +25% / 冻结 +0.3s
	GameState.run.items = {}
	GameState.run.trinkets = ["trinket_frost"]
	e = _spawn_enemy(Vector2(600, 160))
	var hp_before: float = e.hp
	_trigger("projectile_hit", {"enemy": e, "dmg": 100, "element": "ice", "crit": false, "pos": e.global_position})
	if float(e.hp) >= float(hp_before) - 24.0:
		_fail("trinket_frost ice bonus not triggered")
	EventBus.apply_status.emit(e, "freeze", 1)
	await get_tree().process_frame
	if float(e.get("_freeze_left")) < 1.27:
		_fail("trinket_frost freeze extend not triggered (got %f)" % float(e.get("_freeze_left")))
	await _clear_entities()
	# 雷核：雷电伤害 +25%
	GameState.run.trinkets = ["trinket_storm"]
	e = _spawn_enemy(Vector2(600, 220))
	hp_before = float(e.hp)
	_trigger("projectile_hit", {"enemy": e, "dmg": 100, "element": "lightning", "crit": false, "pos": e.global_position})
	if float(e.hp) >= float(hp_before) - 24.0:
		_fail("trinket_storm lightning bonus not triggered")
	await _clear_entities()
	# 熔岩护符：火焰真伤（生命上限 0.5%/层）
	_items({"fire_lava_amulet": 2})
	e = _spawn_enemy(Vector2(600, 280))
	var lava_def: Dictionary = GameState.item_def("fire_lava_amulet")
	var expected := maxi(roundi(float(e.max_hp) * GameState.item_value(lava_def, 2)), 1)
	hp_before = float(e.hp)
	_trigger("projectile_hit", {"enemy": e, "dmg": 100, "element": "fire", "crit": false, "pos": e.global_position})
	if float(e.hp) != float(hp_before) - float(expected):
		_fail("fire_lava_amulet true dmg not triggered (drop=%d want=%d)" % [int(hp_before - float(e.hp)), expected])
	await _clear_entities()
	# 暴击率：幸运（crit_lucky）+ 四叶草 + 雷暴预感 + 潮汐之力（projectile 判定路径）
	var proj2 = PROJECTILE_SCENE.instantiate()
	proj2.setup({"position": Vector2.ZERO, "direction": Vector2.RIGHT, "speed": 0.0,
		"range": 10.0, "damage": 1.0, "element": "fire", "aoe": 0.0, "mods": {}, "status": {}, "chain": 0})
	add_child(proj2)
	_items({"crit_lucky": 3})
	GameState.run.crit_chance = 0.0
	var crits := 0
	for i in 400:
		if bool(proj2.call("_roll_crit")):
			crits += 1
	if crits < 30 or crits > 80:
		_fail("crit_lucky crit chance out of range (got %d/400)" % crits)
	_items({"lucky_clover": 10})
	GameState.run.crit_chance = 0.5
	crits = 0
	for i in 400:
		if bool(proj2.call("_roll_crit")):
			crits += 1
	# 四叶草 10 层：重掷概率 ≈36.2%，期望暴击 ≈0.5+0.5×0.362×0.5 ≈0.59 → ≈236/400
	# 阈值 220：无四叶草基线 200±10（z≈2.0 误放 <3%），有四叶草 236±9.8（误杀 <6%）
	if crits < 220:
		_fail("lucky_clover reroll not effective (got %d/400)" % crits)
	_items({"thunder_10": 2})
	GameState.run.crit_chance = 0.0
	proj2._element = "lightning"
	crits = 0
	for i in 400:
		if bool(proj2.call("_roll_crit")):
			crits += 1
	if crits < 10 or crits > 80:
		_fail("thunder_10 lightning crit out of range (got %d/400)" % crits)
	proj2._element = "water"
	_items({"water_tide_power": 2})
	crits = 0
	for i in 400:
		if bool(proj2.call("_roll_crit")):
			crits += 1
	if crits < 10 or crits > 80:
		_fail("water_tide_power water crit out of range (got %d/400)" % crits)
	proj2.queue_free()


# ================= 构筑筛选（roll_item_choices） =================

func _test_filter() -> void:
	# 只有 fire 技能：不含 poison/lightning 元素构筑（数值+机制），通用/火保留
	GameState.new_run()
	GameState.run.grid = [{"core": "fireball", "shell": ""}]
	GameState.run.items = {"attack_speed_potion": 1}
	var choices := GameState.roll_item_choices(20)
	if choices.size() < 3:
		_fail("roll_item_choices too few (%d)" % choices.size())
	var bad: Array[String] = []
	for c in choices:
		if str(c.get("id", "")).begins_with("spell_part:"):
			continue
		var el: String = GameState._element_key(c)
		if el == "poison" or el == "lightning":
			bad.append(str(c.get("id", "")))
	if not bad.is_empty():
		_fail("filter leaked unheld elements: " + str(bad))
	var has_spell := false
	for c in choices:
		if str(c.get("id", "")).begins_with("spell_part:"):
			has_spell = true
	if not has_spell:
		_fail("spell_part option missing after filter")
	# 持有毒构筑：不再过滤毒系（无崩溃 + 数量正常）
	GameState.run.items = {"poison_essence": 1}
	choices = GameState.roll_item_choices(20)
	if choices.size() < 3:
		_fail("roll_item_choices with poison held too few")
	# 无元素持有：回退不过滤（池子照旧）
	GameState.run.grid = []
	GameState.run.items = {}
	choices = GameState.roll_item_choices(20)
	if choices.size() < 3:
		_fail("roll_item_choices fallback too few")
