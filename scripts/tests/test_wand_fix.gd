extends Node2D
## N1 法杖系统临时验证（用后删除）：
## a) 存量存档非法法杖 id 过滤   b) 替换/添加法术后旧弹道清除（不动敌弹/召唤物）   c) 新法杖 shape_mods 生效
## Run: godot --headless --path . res://scripts/tests/test_wand_fix.tscn

const PROJECTILE_SCENE := preload("res://scenes/game/projectile.tscn")

var _failures: Array[String] = []


func _ready() -> void:
	GameState.run.crit_chance = 0.0
	GameState.run.hp = GameState.run.max_hp
	var player := CharacterBody2D.new()
	player.position = Vector2(100, 100)
	player.add_to_group("player")
	add_child(player)
	await _test_save_filter()
	await _test_replace_clears()
	await _test_add_clears()
	await _test_new_wand_mods()
	if _failures.is_empty():
		print("WAND FIX OK")
		get_tree().quit(0)
	else:
		for f in _failures:
			push_error("FAIL: " + f)
		get_tree().quit(1)


func _fail(msg: String) -> void:
	_failures.append(msg)
	print("[TEST] FAIL: " + msg)


func _core(core_id: String) -> Dictionary:
	for c in GameState.tables.get("spells", {}).get("cores", []):
		if str(c.get("id", "")) == core_id:
			return c
	return {}


func _spawn_proj() -> Node:
	var proj = PROJECTILE_SCENE.instantiate()
	proj.setup({
		"position": Vector2(200, 200), "direction": Vector2.RIGHT, "speed": 300.0,
		"range": 360.0, "damage": 10.0, "element": "fire", "aoe": 0.0,
		"mods": {"orbit": 2.0}, "status": {}, "chain": 0,
	})
	add_child(proj)
	return proj


func _clear_projectiles() -> void:
	for c in get_tree().get_nodes_in_group("player_projectile"):
		c.queue_free()
	await get_tree().physics_frame


func _test_save_filter() -> void:
	## a) 旧存档含已删除的 homing_staff：current_wands 过滤并写回修复
	GameState.run.wands = ["homing_staff", "basic_wand"]
	var ids: Array = GameState.current_wands()
	if ids != ["basic_wand"]:
		_fail("存档过滤: 期望 [basic_wand]，得到 %s" % str(ids))
	if GameState.run.get("wands") != ["basic_wand"]:
		_fail("存档过滤: run.wands 未写回修复（got %s）" % str(GameState.run.get("wands")))
	# 全部非法 → 兜底学徒法杖
	GameState.run.wands = ["homing_staff", "ghost_wand"]
	var ids2: Array = GameState.current_wands()
	if ids2 != ["basic_wand"]:
		_fail("存档过滤: 全非法兜底失败（got %s）" % str(ids2))
	GameState.run.wands = ["basic_wand"]


func _test_replace_clears() -> void:
	## b) replace_spell 后旧弹道（含环绕弹）消失；敌人弹幕/召唤物保留
	await _clear_projectiles()
	_spawn_proj()
	var bullet := Node.new()
	bullet.add_to_group("enemy_bullet")
	add_child(bullet)
	var summon := Node.new()
	summon.add_to_group("summons")
	add_child(summon)
	if get_tree().get_nodes_in_group("player_projectile").size() != 1:
		_fail("替换前置: 玩家弹道未入组")
		return
	GameState.replace_spell(0, "ice_shard", "")
	await get_tree().physics_frame
	if get_tree().get_nodes_in_group("player_projectile").size() != 0:
		_fail("替换法术: 旧玩家弹道未清除（剩 %d）" % get_tree().get_nodes_in_group("player_projectile").size())
	if not is_instance_valid(bullet):
		_fail("替换法术: 敌人弹幕被误清")
	if not is_instance_valid(summon):
		_fail("替换法术: 召唤物被误清")
	bullet.queue_free()
	summon.queue_free()
	await get_tree().physics_frame


func _test_add_clears() -> void:
	## b2) add_spell_part 新增法术同样清旧弹道
	await _clear_projectiles()
	_spawn_proj()
	if get_tree().get_nodes_in_group("player_projectile").size() != 1:
		_fail("添加前置: 玩家弹道未入组")
		return
	var grid_size: int = GameState.run.grid.size()
	GameState.add_spell_part("ice_shard", "")
	await get_tree().physics_frame
	if get_tree().get_nodes_in_group("player_projectile").size() != 0:
		_fail("添加法术: 旧玩家弹道未清除（剩 %d）" % get_tree().get_nodes_in_group("player_projectile").size())
	while GameState.run.grid.size() > grid_size:
		GameState.run.grid.pop_back()


func _test_new_wand_mods() -> void:
	## c) 新法杖 shape_mods 经 spell_caster._cast 合并后生效
	var saved_grid: Array = GameState.run.grid
	GameState.run.grid = []  # 防空转施法：caster 的 _physics_process 会按 grid 自动释放
	var caster = load("res://scripts/combat/spell_caster.gd").new()
	add_child(caster)
	var player: Node = get_tree().get_first_node_in_group("player")
	# ice_staff：贯穿 2 + 冰系 +35%
	await _clear_projectiles()
	GameState.run.wands = ["ice_staff"]
	caster._cast(player, _core("ice_shard"), {})
	var projs: Array = get_tree().get_nodes_in_group("player_projectile")
	if projs.size() != 1:
		_fail("ice_staff: 未生成冰弹（%d）" % projs.size())
	else:
		var p = projs[0]
		if int(p._pierce_left) != 2:
			_fail("ice_staff: pierce 期望 2，得到 %s" % str(p._pierce_left))
		if str(p._element) != "ice":
			_fail("ice_staff: 元素期望 ice，得到 %s" % str(p._element))
		var exp_dmg: float = float(_core("ice_shard").get("base_damage", 0.0)) * 1.35
		if not is_equal_approx(float(p._damage), exp_dmg):
			_fail("ice_staff: 伤害期望 %s，得到 %s" % [str(exp_dmg), str(p._damage)])
	# thunder_staff：贯穿 3 + 雷系 +50%
	await _clear_projectiles()
	GameState.run.wands = ["thunder_staff"]
	caster._cast(player, _core("lightning"), {})
	projs = get_tree().get_nodes_in_group("player_projectile")
	if projs.size() != 1:
		_fail("thunder_staff: 未生成雷弹（%d）" % projs.size())
	else:
		var p = projs[0]
		if int(p._pierce_left) != 3:
			_fail("thunder_staff: pierce 期望 3，得到 %s" % str(p._pierce_left))
		var exp_dmg: float = float(_core("lightning").get("base_damage", 0.0)) * 1.5
		if not is_equal_approx(float(p._damage), exp_dmg):
			_fail("thunder_staff: 伤害期望 %s，得到 %s" % [str(exp_dmg), str(p._damage)])
	# poison_staff：延迟 0.4 + 范围 x2 + 毒系 +50%
	await _clear_projectiles()
	GameState.run.wands = ["poison_staff"]
	caster._cast(player, _core("poison_cloud"), {})
	projs = get_tree().get_nodes_in_group("player_projectile")
	if projs.size() != 1:
		_fail("poison_staff: 未生成毒雾弹（%d）" % projs.size())
	else:
		var p = projs[0]
		if not is_equal_approx(float(p._delay_left), 0.4):
			_fail("poison_staff: delay 期望 0.4，得到 %s" % str(p._delay_left))
		var exp_aoe: float = float(_core("poison_cloud").get("aoe", 0.0)) * 2.0
		if not is_equal_approx(float(p._aoe), exp_aoe):
			_fail("poison_staff: aoe 期望 %s，得到 %s" % [str(exp_aoe), str(p._aoe)])
	# void_staff：分裂 3 + 范围 x1.6
	await _clear_projectiles()
	GameState.run.wands = ["void_staff"]
	caster._cast(player, _core("fireball"), {})
	projs = get_tree().get_nodes_in_group("player_projectile")
	if projs.size() != 1:
		_fail("void_staff: 未生成弹（%d）" % projs.size())
	else:
		var p = projs[0]
		if int(p._split) != 3:
			_fail("void_staff: split 期望 3，得到 %s" % str(p._split))
		var exp_aoe: float = float(_core("fireball").get("aoe", 0.0)) * 1.6
		if not is_equal_approx(float(p._aoe), exp_aoe):
			_fail("void_staff: aoe 期望 %s，得到 %s" % [str(exp_aoe), str(p._aoe)])
	# 数据层：弹射/圣光 mods 与"无 homing 法杖"
	var bounce := GameState.wand_def("bounce_staff")
	if int(bounce.get("shape_mods", {}).get("bounce", 0)) != 2:
		_fail("bounce_staff: 数据缺 bounce:2")
	var light := GameState.wand_def("light_staff")
	if absf(float(light.get("shape_mods", {}).get("drain", 0.0)) - 0.06) > 1e-6:
		_fail("light_staff: 数据缺 drain:0.06")
	for w in GameState.tables.get("wands", {}).get("wands", []):
		if w.get("shape_mods", {}).get("homing", false):
			_fail("法杖表仍有 homing shape_mods: " + str(w.get("id")))
	GameState.run.wands = ["basic_wand"]
	caster.queue_free()
	await _clear_projectiles()
	GameState.run.grid = saved_grid
