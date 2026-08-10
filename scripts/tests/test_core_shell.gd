extends Node2D
## 法术核心×外壳组合修复测试（docs/design/核心外壳组合审计.md 25 条）：
## ① 组合池过滤：200 次 _make_spell_choice 断言不出现被过滤组合
##    （旋风刃×环绕/分裂、瞬发核×追踪/穿透/弹射、狂暴/回响×任何外壳等）；
## ② 召唤×连发（问题18）：mods.shots>1 时召唤数量按语义增加（受 summon.gd 上限约束）；
## ③ 毒雾×连发（问题7）：多团扇形分布不同落点；
## ④ 旋风刃×分裂（问题13）：小弹保底速度 >= 240（修复 1px/s 蠕动 bug）；
## 附 ⑤ AOE核×穿透（问题1）：爆炸后弹体保留继续飞行、二次接触再次爆炸；
## 附 ⑥ 闪光×爆发（问题10）：盲爆半径 ×aoe_mult 兑现"范围翻倍"。
## Run: godot --headless --path . res://scripts/tests/test_core_shell.tscn

const PROJECTILE_SCENE := preload("res://scenes/game/projectile.tscn")
const ENEMY_SCENE := preload("res://scenes/game/enemy.tscn")
const SPELL_CASTER_SCRIPT := preload("res://scripts/combat/spell_caster.gd")
const PROJECTILE_SCRIPT := preload("res://scripts/combat/projectile.gd")

var _failures: Array[String] = []


func _ready() -> void:
	GameState.run.crit_chance = 0.0  # 固定伤害，避免暴击抖动
	GameState.run.crit_dmg_bonus = 1.5
	GameState.run.hp = GameState.run.max_hp
	var player := CharacterBody2D.new()
	player.name = "TestPlayer"
	player.global_position = Vector2(100, 100)
	player.add_to_group("player")
	add_child(player)
	await _test_pool_filter()
	await _test_summon_rapid()
	await _test_poison_rapid_fan()
	await _test_whirl_split_speed()
	await _test_aoe_pierce_continue()
	await _test_flash_burst_radius()
	if _failures.is_empty():
		print("[TEST] CORE SHELL OK")
		get_tree().quit(0)
	else:
		for f in _failures:
			push_error("[TEST] FAIL: " + f)
		print("CORE SHELL FAILED: %d" % _failures.size())
		get_tree().quit(1)


func _fail(msg: String) -> void:
	_failures.append(msg)
	print("[TEST] FAIL: " + msg)


func _core(core_id: String) -> Dictionary:
	for c in GameState.tables.get("spells", {}).get("cores", []):
		if str(c.get("id", "")) == core_id:
			return c
	return {}


func _shell(shell_id: String) -> Dictionary:
	for s in GameState.tables.get("spells", {}).get("shells", []):
		if str(s.get("id", "")) == shell_id:
			return s
	return {}


func _is_instant(cid: String) -> bool:
	return float(_core(cid).get("speed", 0.0)) <= 0.0 \
		and cid != "whirl_blade" and cid != "summon_bat" \
		and not _core(cid).get("teleport", false) and not _core(cid).get("counter", false) \
		and not _core(cid).get("bless", false) and not _core(cid).get("frenzy", false) \
		and not _core(cid).get("mana_echo", false)


func _spawn_enemy(pos: Vector2) -> Node:
	var e = ENEMY_SCENE.instantiate()
	e.setup("slime", 1, 1)
	e.global_position = pos
	e.speed = 0.0
	add_child(e)
	return e


func _fire(params: Dictionary) -> Node:
	var proj = PROJECTILE_SCENE.instantiate()
	proj.setup(params)
	add_child(proj)
	return proj


func _wait_hit(enemy: Node, timeout := 240) -> bool:
	## 轮询至敌人掉血（命中），超时返回 false
	var full_hp: float = enemy.max_hp
	for i in timeout:
		if enemy.hp < full_hp:
			return true
		await get_tree().physics_frame
	return false


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


func _clear_enemies() -> void:
	for c in get_children():
		if c.has_method("take_damage"):
			c.queue_free()
	await get_tree().physics_frame


func _clear_summons() -> void:
	for c in get_tree().get_nodes_in_group("summons"):
		c.queue_free()
	await get_tree().physics_frame


# ================= ① 组合池过滤 =================

func _test_pool_filter() -> void:
	var invalid := 0
	var valid_seen := {}
	for i in 200:
		var choice: Dictionary = GameState._make_spell_choice()
		var parts: PackedStringArray = str(choice.get("id", "")).split(":")
		if parts.size() < 3:
			_fail("choice id malformed: " + str(choice.get("id")))
			continue
		var cid := str(parts[1])
		var sid := str(parts[2])
		var core := _core(cid)
		var shell := _shell(sid)
		if GameState._invalid_combo(core, shell):
			_fail("invalid combo appeared in pool: %s x %s" % [cid, sid])
			invalid += 1
		# 被过滤组合逐条断言（绝不出现"选了没效果"）
		if cid == "whirl_blade" and (sid == "orbit" or sid == "split"):
			_fail("whirl_blade x %s must be filtered" % sid)
		if _is_instant(cid) and (sid == "homing" or sid == "pierce" or sid == "bounce" or sid == "orbit"):
			_fail("instant core %s x %s must be filtered" % [cid, sid])
		if cid == "frenzy" or cid == "mana_echo":
			if sid != "":
				_fail("%s x %s must be filtered (all shells)" % [cid, sid])
		if sid == "":
			pass  # 原生（无外壳）合法出现
		else:
			valid_seen[cid + ":" + sid] = true
	# 池未抽空：有效组合应出现；狂暴/回响退化为原生应出现
	if valid_seen.is_empty():
		_fail("no valid shell combo seen in 200 choices")
	if invalid > 0:
		_fail("invalid combos in pool: %d" % invalid)
	# 确定性验证：全部外壳被过滤的核心（狂暴/回响）只能以"原生"出现
	var saved_cores: Array = GameState.tables["spells"]["cores"]
	var frenzy_core := _core("frenzy")
	var echo_core := _core("mana_echo")
	for entry in [["frenzy", frenzy_core], ["mana_echo", echo_core]]:
		GameState.tables["spells"]["cores"] = [entry[1]]
		var c2: Dictionary = GameState._make_spell_choice()
		if not str(c2.get("id", "")).ends_with(str(entry[0]) + ":"):
			_fail("%s must fall back to native (no shell), got %s" % [str(entry[0]), str(c2.get("id"))])
	GameState.tables["spells"]["cores"] = saved_cores
	# 矩阵抽查（确定性断言）
	var matrix := {
		"whirl_blade:orbit": true, "whirl_blade:split": true, "whirl_blade:homing": true,
		"whirl_blade:pierce": true, "whirl_blade:bounce": true, "whirl_blade:burst": false,
		"whirl_blade:rapid": false, "poison_cloud:homing": true, "poison_cloud:pierce": true,
		"poison_cloud:bounce": true, "poison_cloud:orbit": true, "poison_cloud:rapid": false,
		"lightning:rapid": false, "inferno:rapid": false, "flash:burst": false,
		"frenzy:rapid": true, "frenzy:burst": true, "mana_echo:delay": true,
		"summon_bat:rapid": false, "summon_bat:spread": true, "summon_bat:burst": false,
		"teleport:burst": false, "teleport:delay": false, "teleport:drain": false,
		"teleport:rapid": true, "counterspell:orbit": true, "blessing:spread": true,
		"fireball:rapid": false, "fireball:pierce": false, "fireball:orbit": false,
	}
	for key in matrix:
		var kp: PackedStringArray = str(key).split(":")
		var got: bool = GameState._invalid_combo(_core(str(kp[0])), _shell(str(kp[1])))
		if got != bool(matrix[key]):
			_fail("matrix %s: expect invalid=%s, got %s" % [key, str(matrix[key]), str(got)])


# ================= ② 召唤×连发：多召 =================

func _test_summon_rapid() -> void:
	var saved_items: Dictionary = GameState.run.items
	GameState.run.items = {"summon_book": 3}  # 总上限 = 1 + 3 + 1 = 5，容纳 3 只
	await _clear_summons()
	var caster := SPELL_CASTER_SCRIPT.new()
	add_child(caster)
	var player: Node = get_tree().get_first_node_in_group("player")
	var core: Dictionary = _core("summon_bat").duplicate()
	# bat 的 max_count=1（召唤物设计上限，超限静默中止已有）：
	# 用上限 3 的骷髅类型验证"shots>1 时召唤数量按语义增加"
	core["summon"] = "skeleton"
	caster._spawn_summon(player, core, {"shots": 3, "cooldown_mult": 1.5, "damage_mult": 0.8})
	await get_tree().process_frame
	await get_tree().process_frame
	var alive: int = get_tree().get_nodes_in_group("summons").size()
	if alive != 3:
		_fail("summon rapid: expect 3 summons (shots=3), got %d" % alive)
	await _clear_summons()
	caster._spawn_summon(player, core, {})
	await get_tree().process_frame
	await get_tree().process_frame
	alive = get_tree().get_nodes_in_group("summons").size()
	if alive != 1:
		_fail("summon base: expect 1 summon (no shots), got %d" % alive)
	await _clear_summons()
	caster.queue_free()
	GameState.run.items = saved_items
	await get_tree().process_frame


# ================= ③ 毒雾×连发：扇形分散落点 =================

func _test_poison_rapid_fan() -> void:
	await _clear_projectiles()
	var saved_wands: Array = GameState.run.wands
	GameState.run.wands = ["basic_wand"]
	var caster := SPELL_CASTER_SCRIPT.new()
	add_child(caster)
	var player: Node = get_tree().get_first_node_in_group("player")
	player.global_position = Vector2(400, 360)
	var core := _core("poison_cloud")
	caster._cast(player, core, {"shots": 3, "cooldown_mult": 1.5, "damage_mult": 0.8})
	var projs := _projectiles()
	if projs.size() != 3:
		_fail("poison rapid: expect 3 clouds, got %d" % projs.size())
	else:
		var dirs := {}
		var lands := {}
		for p in projs:
			var d: Vector2 = p._dir
			dirs["%.4f,%.4f" % [d.x, d.y]] = true
			var land: Vector2 = p._spawn_pos + d * float(p._range)
			lands["%.1f,%.1f" % [land.x, land.y]] = true
		if dirs.size() != 3:
			_fail("poison rapid: 3 clouds must have distinct directions (got %d)" % dirs.size())
		if lands.size() != 3:
			_fail("poison rapid: 3 clouds must land at distinct points (got %d)" % lands.size())
	caster.queue_free()
	GameState.run.wands = saved_wands
	await _clear_projectiles()


# ================= ④ 旋风刃×分裂：小弹保底速度 =================

func _test_whirl_split_speed() -> void:
	await _clear_projectiles()
	var e := _spawn_enemy(Vector2(620, 480))
	var proj := PROJECTILE_SCENE.instantiate()
	proj.setup({
		"position": Vector2(500, 480), "direction": Vector2.RIGHT, "speed": 1.0,
		"range": 90.0, "damage": 8.0, "element": "blade", "aoe": 40.0,
		"mods": {"orbit": 4.0, "split": 2, "_whirl": true}, "status": {"root": 1.5}, "chain": 0,
	})
	add_child(proj)
	await get_tree().physics_frame
	proj._spawn_split_minis(e)
	await get_tree().physics_frame
	var minis: Array = []
	for m in _projectiles():
		if m != proj:  # 排除父弹体（轨道模式不会自毁），只统计分裂小弹
			minis.append(m)
	if minis.size() != 2:
		_fail("whirl split: expect 2 minis, got %d" % minis.size())
	for m in minis:
		if float(m._speed) < 240.0:
			_fail("whirl split: mini speed must be >= 240 (got %f)" % float(m._speed))
		# 问题5：小弹继承核心显式状态
		if float(m._status.get("root", 0.0)) != 1.5:
			_fail("whirl split: mini must inherit core status (root=1.5, got %s)" % str(m._status.get("root", 0.0)))
	await _clear_projectiles()
	await _clear_enemies()


# ================= 附⑤ AOE核×穿透：爆炸后继续飞行 =================

func _test_aoe_pierce_continue() -> void:
	await _clear_enemies()
	await _clear_projectiles()
	var a := _spawn_enemy(Vector2(620, 200))
	var b := _spawn_enemy(Vector2(780, 200))
	var ha: float = a.hp
	var hb: float = b.hp
	_fire({
		"position": Vector2(400, 200), "direction": Vector2.RIGHT, "speed": 320.0,
		"range": 520.0, "damage": 10.0, "element": "fire", "aoe": 18.0,
		"mods": {"pierce": 2}, "status": {}, "chain": 0,
	})
	if not await _wait_hit(a):
		_fail("aoe pierce: first target not hit")
		return
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_equal_approx(a.hp, ha - 10.0):
		_fail("aoe pierce: A dmg != 10 (got %s)" % str(a.hp))
	if _projectiles().is_empty():
		_fail("aoe pierce: projectile must survive first explosion (pierce remaining)")
		return
	if not await _wait_hit(b):
		_fail("aoe pierce: second target not hit (explode-and-continue broken)")
	else:
		if not is_equal_approx(b.hp, hb - 10.0):
			_fail("aoe pierce: B dmg != 10 (got %s)" % str(b.hp))
	await _clear_projectiles()
	await _clear_enemies()


# ================= 附⑥ 闪光×爆发：盲爆半径 ×aoe_mult =================

func _test_flash_burst_radius() -> void:
	await _clear_projectiles()
	# 落点 = 400 + 200 = 600；敌人距落点 130px：在基础盲爆 90 之外、180（90×2）之内
	var e := _spawn_enemy(Vector2(730, 400))
	_fire({
		"position": Vector2(400, 400), "direction": Vector2.RIGHT, "speed": 0.0,
		"range": 200.0, "damage": 6.0, "element": "light", "aoe": 0.0,
		"mods": {"explode": true, "aoe_mult": 2.0}, "status": {"blind": 2.0}, "chain": 0,
	})
	if not await _wait_hit(e):
		_fail("flash burst: enemy at 130px must be hit by 180px blind burst (aoe_mult=2)")
	else:
		if e._blind_left <= 0.0:
			_fail("flash burst: blind not applied")
	await _clear_projectiles()
	await _clear_enemies()
