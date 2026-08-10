extends Node2D
## 技能"追踪/落点"实测探针：验证用户反馈的闪光不自动追踪问题 + 全核心命中窗口
## 运行：godot --headless --path . res://tools/tests/experience_probe.tscn
## 退出码：0=全部符合静态预期 1=有 FAIL

const ENEMY_SCENE := preload("res://scenes/game/enemy.tscn")
const PROJECTILE_SCENE := preload("res://scenes/game/projectile.tscn")
const PLAYER_POS := Vector2(300, 300)

var _failures: Array[String] = []
var _player: CharacterBody2D
var _caster: Node
var _dmg_signals: Array = []
var _status_signals: Array = []
var _fx_signals: Array = []

func _ready() -> void:
	SynergyRegistry.load_synergy_scripts()
	await get_tree().process_frame
	GameState.new_run()
	GameState.run.hp = GameState.run.max_hp
	randomize()
	EventBus.damage_dealt.connect(func(dmg: int, pos: Vector2, crit: bool) -> void:
		_dmg_signals.append([dmg, pos]))
	EventBus.apply_status.connect(func(target: Node, kind: String, stacks: int) -> void:
		_status_signals.append([kind, stacks]))
	for sig in ["fx_explosion_scaled", "fx_explosion", "fx_cast", "fx_hit", "fx_hit_flash", "fx_dot_text"]:
		if EventBus.has_signal(sig):
			EventBus.connect(sig, func(_a = null, _b = null, _c = null) -> void:
				_fx_signals.append([sig, _a, _b, _c]))
	EventBus.enemy_died.connect(func(_a: String, _b: Vector2, _c: int, _d: int, _e: bool) -> void:
		_fx_signals.append("enemy_died"))
	_setup_player()
	await _test_flash()
	await _test_lightning()
	await _test_poison_cloud()
	await _test_inferno()
	await _test_fireball_homing()
	await _test_whirl_blade()
	if _failures.is_empty():
		print("[PROBE] ALL PASS")
		get_tree().quit(0)
	else:
		for f in _failures:
			print("[PROBE] FAIL: " + f)
		get_tree().quit(1)

func _setup_player() -> void:
	for p in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(p):
			p.free()
	_player = CharacterBody2D.new()
	_player.name = "Player"
	_player.global_position = PLAYER_POS
	_player.add_to_group("player")
	add_child(_player)
	_caster = preload("res://scripts/combat/spell_caster.gd").new()
	_caster.name = "SpellCaster"
	_player.add_child(_caster)

func _core_def(core_id: String) -> Dictionary:
	for c in GameState.tables.get("spells", {}).get("cores", []):
		if str(c.get("id", "")) == core_id:
			return c
	return {}

func _shell_def(shell_id: String) -> Dictionary:
	if shell_id == "":
		return {}
	for s in GameState.tables.get("spells", {}).get("shells", []):
		if str(s.get("id", "")) == shell_id:
			return s
	return {}

func _spawn_enemy(pos: Vector2) -> Node:
	var e := ENEMY_SCENE.instantiate()
	e.setup("slime", 1, 1)
	e.global_position = pos
	e.speed = 0.0
	e.attack = 0
	add_child(e)
	return e

func _clear_enemies() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e):
			e.queue_free()
	await get_tree().process_frame

func _cast(core_id: String, shell_id: String, d: float) -> Node:
	## 在玩家正前方 d px 处放一只史莱姆，施放一次该核心，返回敌人节点
	GameState.run.grid = [{"core": core_id, "shell": shell_id}]
	var core := _core_def(core_id)
	var shell := _shell_def(shell_id)
	var e := _spawn_enemy(PLAYER_POS + Vector2(d, 0))
	_caster._cast(_player, core, shell.get("mods", {}))
	return e

func _wait_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _check_hit(label: String, e: Node, expect_hit: bool) -> void:
	var valid := is_instance_valid(e)
	var hp_full: bool = valid and float(e.hp) >= float(e.max_hp) - 0.5
	var hit: bool = valid and not hp_full
	if hit == expect_hit:
		print("[PROBE] %-34s 期望=%-5s 实测=%s hp=%.0f/%.0f → PASS" % [
			label, str(expect_hit), str(hit), e.hp if valid else -1.0, e.max_hp if valid else -1.0])
	else:
		_failures.append("%s 期望=%s 实测=%s (hp=%s)" % [label, str(expect_hit), str(hit), str(e.hp if valid else "dead")])
		print("[PROBE] %-34s 期望=%-5s 实测=%s → FAIL" % [label, str(expect_hit), str(hit)])

func _test_flash() -> void:
	print("[PROBE] == flash 闪光（range=200 瞬发，盲半径兜底90 → 命中窗口 d∈[102,298]）==")
	# 近身：d=80 < 102 → 必脱靶（用户反馈"闪光不命中"主因）
	var e := await _cast("flash", "", 80.0)
	await _wait_frames(3)
	_check_hit("flash d=80 (近身)", e, false)
	await _clear_enemies()
	# 中距：d=200 落点正对 → 命中 + 致盲
	e = await _cast("flash", "", 200.0)
	await _wait_frames(3)
	_check_hit("flash d=200 (落点)", e, true)
	var blind := is_instance_valid(e) and float(e.get("_blind_left")) > 0.0
	print("[PROBE] flash d=200 致盲生效=%s → %s" % [str(blind), "PASS" if blind else "FAIL"])
	if not blind:
		_failures.append("flash 致盲未生效")
	await _clear_enemies()
	# 远距：d=320 > 298 → 脱靶
	e = await _cast("flash", "", 320.0)
	await _wait_frames(3)
	_check_hit("flash d=320 (超射程)", e, false)
	await _clear_enemies()

func _test_lightning() -> void:
	print("[PROBE] == lightning 闪电（落点固定260px，但 chain=2 链跳160px 兜底 → 实测有效范围远超窗口）==")
	var e := await _cast("lightning", "", 150.0)
	await _wait_frames(3)
	_check_hit("lightning d=150 (链跳兜底)", e, true)
	await _clear_enemies()
	e = await _cast("lightning", "", 260.0)
	await _wait_frames(3)
	_check_hit("lightning d=260 (落点)", e, true)
	await _clear_enemies()
	e = await _cast("lightning", "", 320.0)
	await _wait_frames(3)
	_check_hit("lightning d=320 (链跳兜底)", e, true)
	await _clear_enemies()

func _test_poison_cloud() -> void:
	print("[PROBE] == poison_cloud 毒雾（range=200 aoe=48 → 窗口[144,256]）==")
	var e := await _cast("poison_cloud", "", 100.0)
	await _wait_frames(3)
	_check_hit("poison_cloud d=100 (过近)", e, false)
	await _clear_enemies()
	e = await _cast("poison_cloud", "", 200.0)
	await _wait_frames(3)
	_check_hit("poison_cloud d=200 (落点)", e, true)
	await _clear_enemies()

func _test_inferno() -> void:
	print("[PROBE] == inferno 火柱（range=220 aoe=64 → 窗口[148,292]）==")
	var e := await _cast("inferno", "", 100.0)
	await _wait_frames(3)
	_check_hit("inferno d=100 (过近)", e, false)
	await _clear_enemies()
	e = await _cast("inferno", "", 220.0)
	await _wait_frames(3)
	_check_hit("inferno d=220 (落点)", e, true)
	await _clear_enemies()

func _test_fireball_homing() -> void:
	print("[PROBE] == fireball 火球（弹道：接触即入 _hit_enemies → 爆炸跳过直击目标，仅溅射邻敌 → 单体 0 伤害 P0 BUG）==")
	_dmg_signals.clear()
	_status_signals.clear()
	_fx_signals.clear()
	# 干净测试：手动施法后立即把冷却拉高，杜绝 caster 自动补刀干扰
	var e := await _cast("fireball", "", 200.0)
	_caster._cds.clear()
	_caster._cds.append(999.0)
	await _wait_frames(70)
	_check_hit("fireball d=200 [P0:直击0伤]", e, false)
	print("[PROBE] fireball fx=%s" % str(_fx_signals))
	await _clear_enemies()
	# 点射：d=40（出生点 12px 外，2 帧内接触）
	_dmg_signals.clear()
	_fx_signals.clear()
	e = await _cast("fireball", "", 40.0)
	_caster._cds.clear()
	_caster._cds.append(999.0)
	await _wait_frames(70)
	_check_hit("fireball d=40 [P0:直击0伤]", e, false)
	print("[PROBE] fireball pointblank fx=%s" % str(_fx_signals))
	await _clear_enemies()
	# homing 外壳
	_dmg_signals.clear()
	_fx_signals.clear()
	e = await _cast("fireball", "homing", 260.0)
	_caster._cds.clear()
	_caster._cds.append(999.0)
	await _wait_frames(90)
	_check_hit("fireball+homing d=260 [P0:直击0伤]", e, false)
	await _clear_enemies()
	# homing 外壳 + 瞬发核：落点仍是固定射程（homing 对瞬发无效）
	e = await _cast("flash", "homing", 80.0)
	await _wait_frames(3)
	_check_hit("flash+homing d=80 (仍脱靶)", e, false)
	await _clear_enemies()

func _test_whirl_blade() -> void:
	print("[PROBE] == whirl_blade 旋风刃（环绕半径90+aoe40 → 近身命中）==")
	var e := await _cast("whirl_blade", "", 80.0)
	await _wait_frames(90)
	_check_hit("whirl_blade d=80 (环绕)", e, true)
	await _clear_enemies()
