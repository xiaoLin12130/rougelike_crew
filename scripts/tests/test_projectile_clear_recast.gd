extends Node2D
## 专项回归：施法 → 换法术（clear_player_projectiles）→ 再施法
## 池竞态复现/防回归（docs/design/projectile池竞态修复报告.md）：
## 瞬发弹被 queue_free 排队销毁后，帧末销毁前仍跑物理帧爆炸 → 旧代码 _retire()
## 把"即将销毁"的弹体回收入池 → 帧末释放 → 池内残留死引用 → 下次施法 obtain()
## 弹到死引用即硬错误中断（split 小弹 0 生成）。本用例断言：
##   ① clear_player_projectiles 后池内无死引用（is_instance_valid 全活）；
##   ② 再施法（fireball × split 外壳）命中 → split 小弹正常生成 2 枚、
##      速度 >= 240、伤害 = 父弹 ×0.6。
## Run: godot --headless --path . res://scripts/tests/test_projectile_clear_recast.tscn

const ENEMY_SCENE := preload("res://scenes/game/enemy.tscn")
const SPELL_CASTER_SCRIPT := preload("res://scripts/combat/spell_caster.gd")
const PROJECTILE_SCRIPT := preload("res://scripts/combat/projectile.gd")

var _failures: Array[String] = []


func _ready() -> void:
	GameState.run.crit_chance = 0.0  # 固定伤害，避免暴击抖动
	var player := CharacterBody2D.new()
	player.name = "TestPlayer"
	player.global_position = Vector2(300, 300)
	player.add_to_group("player")
	add_child(player)
	await _run()
	if _failures.is_empty():
		print("[TEST] PROJECTILE CLEAR-RECAST OK")
		get_tree().quit(0)
	else:
		for f in _failures:
			push_error("[TEST] FAIL: " + f)
		get_tree().quit(1)


func _fail(msg: String) -> void:
	_failures.append(msg)
	print("[TEST] FAIL: " + msg)


func _core(cid: String) -> Dictionary:
	for c in GameState.tables.get("spells", {}).get("cores", []):
		if str(c.get("id", "")) == cid:
			return c
	return {}


func _spawn_enemy(pos: Vector2) -> Node:
	var e = ENEMY_SCENE.instantiate()
	e.setup("slime", 1, 1)
	e.global_position = pos
	e.speed = 0.0
	add_child(e)
	return e


func _projectiles() -> Array:
	var out: Array = []
	for c in get_children():
		if c.get_script() == PROJECTILE_SCRIPT:
			out.append(c)
	return out


func _dead_in_pool() -> int:
	var dead := 0
	for p in PROJECTILE_SCRIPT._proj_pool:
		if not is_instance_valid(p):
			dead += 1
	return dead


func _clear_enemies() -> void:
	for c in get_children():
		if c.has_method("take_damage"):
			c.queue_free()
	await get_tree().physics_frame


func _run() -> void:
	# 隔离环境：caster._physics_process 会按 run.grid 自动施法、法杖会带 shape mods，
	# 不清空会射入未知弹体干扰断言（幽灵弹先命中敌人 → 误判 hit、小弹数=0 的抖动）
	GameState.run.grid = []
	GameState.run.wands = []
	PROJECTILE_SCRIPT.clear_pool()  # 独立进程内静态池为空，防御性清空
	await get_tree().physics_frame
	var caster := SPELL_CASTER_SCRIPT.new()
	add_child(caster)
	var player: Node = get_tree().get_first_node_in_group("player")

	# —— 阶段 1：施法（瞬发核心 poison_cloud ×3，扇面）——
	caster._cast(player, _core("poison_cloud"), {"shots": 3, "cooldown_mult": 1.5, "damage_mult": 0.8})
	if _projectiles().size() != 3:
		_fail("施法后应生成 3 团瞬发毒雾，got %d" % _projectiles().size())

	# —— 阶段 2：换法术 → clear_player_projectiles（queue_free 排队销毁）——
	PROJECTILE_SCRIPT.clear_player_projectiles(get_tree())
	# 竞态窗口：待销毁弹体本帧仍跑物理帧爆炸 → 旧代码 _retire() 在此入池，
	# 帧末 flush_delete 才真正销毁 → 再等一帧后才能观测到池内死引用
	await get_tree().physics_frame
	await get_tree().physics_frame

	# —— 阶段 3：池内不得残留死引用 ——
	var dead := _dead_in_pool()
	if dead != 0:
		_fail("clear_player_projectiles 后池内残留 %d 个死引用（被 queue_free 的弹体仍入池）" % dead)

	# —— 阶段 4：再施法（fireball × split 外壳）→ 命中 → split 小弹正常生成 ——
	await _clear_enemies()
	var e := _spawn_enemy(Vector2(520, 300))
	var fcore := _core("fireball")
	caster._cast(player, fcore, {"split": 2, "cooldown_mult": 1.5})
	# 父弹同步 add_child（obtain 非 defer），命中后会回收回池，须在命中前捕获基准伤害
	var fireball: Node = null
	for m in _projectiles():
		if int(m._split) == 2:
			fireball = m
	if fireball == null:
		_fail("再施法后父弹（split=2）未生成——obtain() 弹到死引用中断")
		return
	var base_dmg: float = float(fireball._damage)
	var full_hp: float = e.max_hp
	var hit := false
	for i in 240:
		if e.hp < full_hp:
			hit = true
			break
		await get_tree().physics_frame
	if not hit:
		_fail("再施法 fireball+split 未命中敌人（obtain 中断或弹体未生成）")
	await get_tree().physics_frame

	# 小弹：_split==0 且伤害 = 父弹 ×0.6
	var minis: Array = []
	for m in _projectiles():
		if int(m._split) == 0 and is_equal_approx(float(m._damage), base_dmg * PROJECTILE_SCRIPT.SPLIT_DAMAGE_MULT):
			minis.append(m)
	if minis.size() != 2:
		_fail("split 小弹应生成 2 枚，got %d" % minis.size())
	for m in minis:
		if float(m._speed) < PROJECTILE_SCRIPT.SPLIT_MINI_SPEED:
			_fail("split 小弹速度必须 >= %d（got %f）" % [PROJECTILE_SCRIPT.SPLIT_MINI_SPEED, float(m._speed)])
		if not m.is_inside_tree():
			_fail("split 小弹应挂树存活（got inside_tree=false）")
	if _dead_in_pool() != 0:
		_fail("再施法后池内出现死引用")

	caster.queue_free()
	await _clear_enemies()
	for p in _projectiles():
		p.queue_free()
	await get_tree().physics_frame
	PROJECTILE_SCRIPT.clear_pool()
	await get_tree().physics_frame
