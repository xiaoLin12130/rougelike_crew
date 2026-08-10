extends Node2D
## 流派机制接线回归测试（P0+P1，基于 docs/design/流派机制缺口审计.md）：
## ① G3 暴击 6 个新道具（crit_crit_bounce/weak_mark/execute/headhunter/lethal_blow/crit_storm）
##    存在 items.json，且 crit_synergy 对应 _on_m3/_on_m4/_on_m6/_on_m8/_on_m9/_on_m10 可触发；
## ② G1+G2 攻速聚合：持有 attack_speed 道具后 spell_caster 施法冷却缩短（与近战同公式），
##    各流派贡献读取点（fire_m2/melee_m3/melee_m9/wind_*）求和生效，移9 迅捷冷却读取点；
## ③ 移M4：持有 wind_hunter 后弹数增加（run.wind_m4_shots → spell_caster shots）；
## ④ 移M7：持有 wind_tail_shot 后弹幕伤害提高（run.wind_m7_dmg + 移6 风刃）；
## ⑤ 冰1：持有 ice_1 后冰系伤害提高（tag 聚合验证）；
## ⑥ 召1：持有 summon_1 后召唤总上限 +1（summon.gd._enforce_cap）；
## 附：player 移速聚合（追风/破风/风行者上限/水M7 洋流）。
## 运行：godot --headless --path . res://scripts/tests/test_sync_hooks.tscn

const ENEMY_SCENE := preload("res://scenes/game/enemy.tscn")
const PROJECTILE_SCENE := preload("res://scenes/game/projectile.tscn")
const PROJECTILE_SCRIPT := preload("res://scripts/combat/projectile.gd")
const SPELL_CASTER_SCRIPT := preload("res://scripts/combat/spell_caster.gd")
const MELEE_SCRIPT := preload("res://scripts/combat/melee_attack.gd")
const SUMMON_SCRIPT := preload("res://scripts/combat/summon.gd")

const G3_ITEMS := [
	"crit_crit_bounce",
	"crit_weak_mark",
	"crit_execute",
	"crit_headhunter",
	"crit_lethal_blow",
	"crit_crit_storm",
]

var _failures: Array[String] = []
var _player: Node2D
var _slow_mo_fired := false  ## 暴M10 信号回调标记（成员变量，勿用 lambda 改局部变量）


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
	EventBus.slow_mo.connect(_on_slow_mo)
	await _test_crit_g3()
	await _test_attack_speed()
	await _test_wind_m4()
	await _test_wind_m7()
	await _test_ice_1()
	await _test_summon_1()
	await _test_trinket_ember()
	await _test_player_speed()
	if _failures.is_empty():
		print("SYNC HOOKS OK")
		get_tree().quit(0)
	else:
		for f in _failures:
			push_error("[TEST] FAIL: " + f)
		print("SYNC HOOKS FAILED: %d" % _failures.size())
		get_tree().quit(1)


func _on_slow_mo(_factor: float, _duration: float) -> void:
	_slow_mo_fired = true


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


func _tanky(e: Node, hp: float = 10000.0) -> void:
	e.max_hp = hp
	e.hp = hp


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


func _fire_core() -> Dictionary:
	for c in GameState.tables.get("spells", {}).get("cores", []):
		if str(c.get("id", "")) == "fireball":
			return c
	return {}


func _ice_core() -> Dictionary:
	for c in GameState.tables.get("spells", {}).get("cores", []):
		if str(c.get("id", "")) == "ice_shard":
			return c
	return {}


# ================= ① G3 暴击 6 道具 + 门控触发 =================

func _test_crit_g3() -> void:
	var crit := _synergy("res://scripts/synergies/crit_synergy.gd")
	if crit == null:
		_fail("crit_synergy not loaded")
		return
	# 0) 6 个新道具 id 存在于 items.json（id 与脚本门控常量一致）
	var ids := {}
	for it in GameState.tables.get("items", {}).get("items", []):
		ids[str(it.get("id", ""))] = it
	for item_id in G3_ITEMS:
		if not ids.has(item_id):
			_fail("G3 item missing in items.json: " + item_id)
	# 门控基线：无道具时暴M3 不弹射
	_items({})
	GameState.run.crit_chance = 0.0
	var e := _spawn_enemy(Vector2(500, 300))
	_trigger("projectile_hit", {"enemy": e, "dmg": 100, "element": "fire", "crit": true, "pos": e.global_position})
	await get_tree().process_frame
	if not get_tree().get_nodes_in_group("player_projectile").is_empty():
		_fail("crit handlers fire without G3 items (gate broken)")
	await _clear_entities()
	# 1) 暴M3 暴击弹射（crit_crit_bounce）：暴击 → 生成追踪弹幕
	_items({"crit_crit_bounce": 1})
	GameState.run.crit_chance = 0.0
	e = _spawn_enemy(Vector2(500, 300))
	_trigger("projectile_hit", {"enemy": e, "dmg": 100, "element": "fire", "crit": true, "pos": e.global_position})
	await get_tree().process_frame
	if get_tree().get_nodes_in_group("player_projectile").is_empty():
		_fail("crit_crit_bounce ricochet not spawned")
	await _clear_entities()
	# 2) 暴M4 弱点标记（crit_weak_mark）：暴击标记 → 后续命中 +15%
	_items({"crit_weak_mark": 1})
	e = _spawn_enemy(Vector2(500, 300))
	_tanky(e)
	_trigger("projectile_hit", {"enemy": e, "dmg": 100, "element": "fire", "crit": true, "pos": e.global_position})
	var hp0: float = float(e.hp)
	_trigger("projectile_hit", {"enemy": e, "dmg": 100, "element": "fire", "crit": false, "pos": e.global_position})
	if hp0 - float(e.hp) < 14.0:
		_fail("crit_weak_mark bonus not applied (drop=%d)" % int(hp0 - float(e.hp)))
	await _clear_entities()
	# 3) 暴M6 终结（crit_execute）：低血目标非暴击 → 强制暴击补足差额
	_items({"crit_execute": 1})
	GameState.run.crit_dmg_bonus = 1.5
	e = _spawn_enemy(Vector2(500, 300))
	_tanky(e, 10000.0)
	e.hp = 2000.0  # 20% < 25% 斩杀线
	hp0 = float(e.hp)
	_trigger("projectile_hit", {"enemy": e, "dmg": 100, "element": "fire", "crit": false, "pos": e.global_position})
	if hp0 - float(e.hp) < 49.0:  # 差额 = 100 × (1.5-1) = 50
		_fail("crit_execute forced crit not applied (drop=%d)" % int(hp0 - float(e.hp)))
	await _clear_entities()
	# 4) 暴M8 猎头（crit_headhunter）：暴击击杀 → 3s 暴击率 +15%
	_items({"crit_headhunter": 1})
	GameState.run.crit_hunt_bonus = 0.0
	e = _spawn_enemy(Vector2(500, 300))
	_tanky(e, 10000.0)
	e.hp = 10.0
	_trigger("projectile_hit", {"enemy": e, "dmg": 10, "element": "fire", "crit": true, "pos": e.global_position})
	if float(GameState.run.get("crit_hunt_bonus", 0.0)) < 0.149:
		_fail("crit_headhunter hunt bonus not armed (%.3f)" % float(GameState.run.get("crit_hunt_bonus", 0.0)))
	await _clear_entities()
	# 5) 暴M9 致命一击（crit_lethal_blow）：每个敌人首次命中必暴
	_items({"crit_lethal_blow": 1})
	GameState.run.crit_dmg_bonus = 1.5
	e = _spawn_enemy(Vector2(500, 300))
	_tanky(e)
	hp0 = float(e.hp)
	_trigger("projectile_hit", {"enemy": e, "dmg": 100, "element": "fire", "crit": false, "pos": e.global_position})
	if hp0 - float(e.hp) < 49.0:
		_fail("crit_lethal_blow first-hit crit not applied (drop=%d)" % int(hp0 - float(e.hp)))
	await _clear_entities()
	# 6) 暴M10 暴击风暴（crit_crit_storm）：暴击 → 慢动作事件
	_slow_mo_fired = false
	_items({"crit_crit_storm": 1})
	crit._m10_last = -100.0  # 引擎刚启动不足 1.5s 节流间隔，伪造上次触发时间戳
	e = _spawn_enemy(Vector2(500, 300))
	_trigger("projectile_hit", {"enemy": e, "dmg": 10, "element": "fire", "crit": true, "pos": e.global_position})
	if not _slow_mo_fired:
		_fail("crit_crit_storm slow_mo not triggered")
	await _clear_entities()
	_items({})


# ================= ② G1+G2 攻速聚合（法术与近战同公式） =================

func _test_attack_speed() -> void:
	var sc := SPELL_CASTER_SCRIPT.new()
	add_child(sc)
	var melee := MELEE_SCRIPT.new()
	add_child(melee)
	var core := _fire_core()
	if core.is_empty():
		_fail("fireball core missing")
		return
	# 基线：无攻速道具
	_items({})
	GameState.apply_item_effects_to_stats()
	var cd0: float = sc._cooldown_of(core, {"cooldown_mult": 1.0})
	var iv0: float = melee._interval()
	# 持有攻速药水 1 层：aggregate attack_speed = 0.15 → 冷却 ÷1.15（与近战同公式）
	_items({"attack_speed_potion": 1})
	GameState.apply_item_effects_to_stats()
	var cd1: float = sc._cooldown_of(core, {"cooldown_mult": 1.0})
	var iv1: float = melee._interval()
	if absf(cd1 - cd0 / 1.15) > 1e-6:
		_fail("attack_speed potion not shortening spell cd (%.4f vs %.4f)" % [cd1, cd0 / 1.15])
	if absf(iv1 - 0.8 / 1.15) > 1e-6:
		_fail("melee interval not shortened (%.4f vs %.4f)" % [iv1, 0.8 / 1.15])
	# 流派贡献读取点求和（G1/G2 收敛）：火M2 + 近M3 + 移速流，全部只读 run.xxx_bonus
	GameState.run.fire_m2_atk_speed = 0.4
	GameState.run.melee_m3_as_bonus = 0.2
	GameState.run.wind_as_bonus = 0.1
	var total := 0.15 + 0.4 + 0.2 + 0.1
	var cd2: float = sc._cooldown_of(core, {"cooldown_mult": 1.0})
	if absf(cd2 - cd0 / (1.0 + total)) > 1e-6:
		_fail("synergy as read points not summed (%.4f vs %.4f)" % [cd2, cd0 / (1.0 + total)])
	# 移9 迅捷：技能冷却 -5%/层（run.wind_cd_mult 读取点）
	GameState.run.fire_m2_atk_speed = 0.0
	GameState.run.melee_m3_as_bonus = 0.0
	GameState.run.wind_as_bonus = 0.0
	_items({"wind_haste": 2})
	GameState.apply_item_effects_to_stats()
	var wind := _synergy("res://scripts/synergies/wind_synergy.gd")
	if wind != null:
		wind.call("_sync_read_points")
	if absf(float(GameState.run.get("wind_cd_mult", 1.0)) - 0.9) > 1e-6:
		_fail("wind_cd_mult != 0.9 (got %f)" % float(GameState.run.get("wind_cd_mult", 1.0)))
	var cd3: float = sc._cooldown_of(core, {"cooldown_mult": 1.0})
	# 注：wind_haste 带 skill_cd tag，冷却缩减聚合也会计入（与 _cooldown_of 口径一致）
	var cd_reduce := clampf(GameState.aggregate_bonus("cooldown") + GameState.aggregate_bonus("skill_cd"), 0.0, 0.8)
	if absf(cd3 - cd0 * 0.9 * (1.0 - cd_reduce)) > 1e-6:
		_fail("wind_cd_mult not applied to spell cd (%.4f vs %.4f)" % [cd3, cd0 * 0.9 * (1.0 - cd_reduce)])
	sc.queue_free()
	melee.queue_free()
	await _clear_entities()


# ================= ③ 移M4 追风猎手：弹数读取点 =================

func _test_wind_m4() -> void:
	var core := _fire_core()
	# 基线：未持有 wind_hunter → 1 发
	_items({})
	await _clear_projectiles()
	var caster := SPELL_CASTER_SCRIPT.new()
	add_child(caster)
	caster._cast(_player, core, {})
	if get_tree().get_nodes_in_group("player_projectile").size() != 1:
		_fail("baseline shots != 1")
	caster.queue_free()
	await _clear_entities()
	# 持有 wind_hunter：移速加成 ≥100% → 弹数 +1（run.wind_m4_shots 读取点）
	_items({"wind_hunter": 1, "wind_walker": 1, "wind_boots": 5})
	GameState.run.wind_kill_speed_bonus = 0.5
	GameState.run.wind_m6_speed_bonus = 0.3
	# 同步一次读取点（模拟 wind._process 已刷新 wind_speed_cap_bonus）
	var wind := _synergy("res://scripts/synergies/wind_synergy.gd")
	if wind != null:
		wind.call("_sync_read_points")
	# 0.14(靴) + 0.2(风行者 tag) + 0.5 + 0.3 = 1.14 → 1 档 → +1 发
	# （wind_m4_shots 由 cast 钩子写入：先触发 cast 再断言）
	_trigger("cast", {"player": _player, "core": core, "mods": {}})
	if int(GameState.run.get("wind_m4_shots", 0)) < 1:
		_fail("wind_m4_shots not armed (got %d)" % int(GameState.run.get("wind_m4_shots", 0)))
	await _clear_projectiles()
	caster = SPELL_CASTER_SCRIPT.new()
	add_child(caster)
	caster._cast(_player, core, {})
	if get_tree().get_nodes_in_group("player_projectile").size() != 2:
		_fail("wind_hunter shots not increased (got %d)" % get_tree().get_nodes_in_group("player_projectile").size())
	GameState.run.wind_kill_speed_bonus = 0.0
	GameState.run.wind_m6_speed_bonus = 0.0
	caster.queue_free()
	await _clear_entities()
	_items({})


func _clear_projectiles() -> void:
	PROJECTILE_SCRIPT.clear_player_projectiles(get_tree())
	await get_tree().process_frame


# ================= ④ 移M7 顺风弹：弹幕伤害读取点 =================

func _test_wind_m7() -> void:
	_items({"wind_tail_shot": 1})
	var e := _spawn_enemy(Vector2(360, 300))
	_tanky(e)
	# cast 钩子：移动方向与攻击方向一致 → run.wind_m7_dmg = 0.2
	_trigger("cast", {"player": _player, "velocity": Vector2(100, 0), "core": {}, "mods": {}})
	if absf(float(GameState.run.get("wind_m7_dmg", 0.0)) - 0.2) > 1e-6:
		_fail("wind_m7_dmg not armed (got %f)" % float(GameState.run.get("wind_m7_dmg", 0.0)))
	# 弹幕命中：伤害 × (1 + wind_m7_dmg)
	var proj = PROJECTILE_SCENE.instantiate()
	proj.setup({"position": Vector2.ZERO, "direction": Vector2.RIGHT, "speed": 100.0,
		"range": 300.0, "damage": 100.0, "element": "fire", "aoe": 0.0, "mods": {}, "status": {}, "chain": 0})
	add_child(proj)
	GameState.run.crit_chance = 0.0
	GameState.run.wind_speed_crit = 0.0
	var hp0: float = float(e.hp)
	proj._hit_enemy(e, 1.0, true)
	if hp0 - float(e.hp) < 119.0:
		_fail("wind_m7 dmg not applied to projectile (drop=%d)" % int(hp0 - float(e.hp)))
	# 移6 风刃：移动时伤害 +4%/层（run.wind_m6_move_dmg 读取点）
	GameState.run.wind_m6_move_dmg = 0.04
	hp0 = float(e.hp)
	proj._hit_enemy(e, 1.0, true)
	if hp0 - float(e.hp) < 123.0:
		_fail("wind_m6_move_dmg not applied (drop=%d)" % int(hp0 - float(e.hp)))
	GameState.run.wind_m6_move_dmg = 0.0
	GameState.run.wind_m7_dmg = 0.0
	proj.queue_free()
	await _clear_entities()
	_items({})


# ================= ⑤ 冰1 霜晶：冰系伤害 +10%/层 =================

func _test_ice_1() -> void:
	var sc := SPELL_CASTER_SCRIPT.new()
	add_child(sc)
	var core := _ice_core()
	if core.is_empty():
		_fail("ice_shard core missing")
		return
	_items({})
	var base_dmg: float = sc._spell_damage(core, {}, "ice")
	_items({"ice_1": 1})
	var ice_dmg: float = sc._spell_damage(core, {}, "ice")
	if ice_dmg <= base_dmg or absf(ice_dmg - base_dmg * 1.1) > 0.01:
		_fail("ice_1 ice dmg not increased (%.2f -> %.2f)" % [base_dmg, ice_dmg])
	sc.queue_free()
	await _clear_entities()
	_items({})


# ================= ⑥ 召1 召唤之书：召唤总上限 +1 =================

func _test_summon_1() -> void:
	# summon_1=1 → 总上限 = 1 + 0 + 1 = 2
	_items({"summon_1": 1})
	var cap: int = GameState.total_stacks("summon_1") + GameState.total_stacks("summon_book") + 1
	for i in 5:
		var s := SUMMON_SCRIPT.new()
		s.setup(_player, 10.0, "summon", "")
		add_child(s)
		s.global_position = _player.position + Vector2(randf_range(-16, 16), randf_range(-16, 16))
	await get_tree().process_frame
	await get_tree().process_frame
	var alive: int = get_tree().get_nodes_in_group("summons").size()
	if alive > cap:
		_fail("summon_1 cap not enforced (%d > %d)" % [alive, cap])
	await _clear_entities()
	# summon_1 + summon_book 叠加 → 上限 3
	_items({"summon_1": 1, "summon_book": 1})
	cap = GameState.total_stacks("summon_1") + GameState.total_stacks("summon_book") + 1
	for i in 5:
		var s2 := SUMMON_SCRIPT.new()
		s2.setup(_player, 10.0, "summon", "")
		add_child(s2)
		s2.global_position = _player.position + Vector2(randf_range(-16, 16), randf_range(-16, 16))
	await get_tree().process_frame
	await get_tree().process_frame
	alive = get_tree().get_nodes_in_group("summons").size()
	if alive > cap:
		_fail("summon_1+book cap not enforced (%d > %d)" % [alive, cap])
	await _clear_entities()
	_items({})


# ================= 附：余烬坠饰（trinket_ember）：火焰伤害 +25%/件 =================

func _test_trinket_ember() -> void:
	GameState.run.items = {}
	GameState.run.trinkets = ["trinket_ember"]
	var e := _spawn_enemy(Vector2(500, 400))
	_tanky(e)
	var hp0: float = float(e.hp)
	_trigger("projectile_hit", {"enemy": e, "dmg": 100, "element": "fire", "crit": false, "pos": e.global_position})
	if hp0 - float(e.hp) < 24.0:
		_fail("trinket_ember fire bonus not applied (drop=%d)" % int(hp0 - float(e.hp)))
	# 非火系不受影响
	hp0 = float(e.hp)
	_trigger("projectile_hit", {"enemy": e, "dmg": 100, "element": "ice", "crit": false, "pos": e.global_position})
	if hp0 - float(e.hp) > 1.0:
		_fail("trinket_ember leaking to non-fire (drop=%d)" % int(hp0 - float(e.hp)))
	GameState.run.trinkets = []
	await _clear_entities()


# ================= 附：player 移速聚合（追风/破风/风行者上限/水M7） =================

func _test_player_speed() -> void:
	var p = load("res://scenes/game/player.tscn").instantiate()
	add_child(p)
	# 追风 + 疾风靴 + 水M7 洋流：220 × (1+0.1+0.2) × 1.2 = 343.2
	_items({"wind_boots": 1})
	GameState.run.wind_kill_speed_bonus = 0.2
	GameState.run.wind_m6_speed_bonus = 0.0
	GameState.run.wind_speed_cap_bonus = 0.0
	GameState.run.water_m7_speed = 1.2
	var v0: float = p._move_speed()
	if absf(v0 - 343.2) > 0.01:
		_fail("player speed agg wrong (%.2f)" % v0)
	# 移速上限：加成 1.6 被默认 cap 1.0 截断 → 220×2.0 = 440
	_items({})
	GameState.run.wind_kill_speed_bonus = 0.8
	GameState.run.wind_m6_speed_bonus = 0.8
	GameState.run.wind_speed_cap_bonus = 0.0
	GameState.run.water_m7_speed = 1.0
	var v1: float = p._move_speed()
	if absf(v1 - 440.0) > 0.01:
		_fail("speed cap not applied (%.2f)" % v1)
	# 移10 风行者提升上限：cap 1.5 → 220×2.5 = 550
	GameState.run.wind_speed_cap_bonus = 0.5
	GameState.run.water_m7_speed = 1.0
	var v2: float = p._move_speed()
	if absf(v2 - 550.0) > 0.01:
		_fail("wind_speed_cap_bonus not raising cap (%.2f)" % v2)
	GameState.run.wind_kill_speed_bonus = 0.0
	GameState.run.wind_m6_speed_bonus = 0.0
	GameState.run.water_m7_speed = 1.0
	GameState.run.wind_speed_cap_bonus = 0.0
	p.queue_free()
	await _clear_entities()
	_items({})
