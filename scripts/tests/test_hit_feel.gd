extends Node2D
## 打击感 S 级 headless 测试（docs/design/打击感强化方案-第二轮.md G-1~G-4）
## 断言：
##   1) 命中音效播放计数 > 0（SfxBus 池化 12 实例 + 同帧预算 3 + 节流生效）
##   2) 死亡碎块生成（普通 4-6 / 精英 8-10 / Boss 14-18，0.8-1s 内全部自毁）
##   3) 伤害数字聚合（同帧同位置合并为一个数字，跨帧分开）+ 上限 24（超限挤掉最旧）
##   4) hitstop 分级（普通 30ms / 暴击 60ms / Boss 80ms）+ 同帧同目标去重
##   5) 实弹集成：projectile 命中 → 音效计数 + 数字 + 顿帧链路完整
## Run: godot --headless --path . res://scripts/tests/test_hit_feel.tscn

const PROJECTILE_SCENE := preload("res://scenes/game/projectile.tscn")
const ENEMY_SCENE := preload("res://scenes/game/enemy.tscn")
const FX_MANAGER_SCRIPT := preload("res://scripts/fx/fx_manager.gd")

var _failures: Array[String] = []
var _fx: Node
var _slow_mo_events: Array = []  # [factor, duration]


func _ready() -> void:
	GameState.run.crit_chance = 0.0  # 固定伤害，避免暴击抖动
	_fx = FX_MANAGER_SCRIPT.new()
	_fx.name = "FxManager"
	add_child(_fx)
	EventBus.slow_mo.connect(_on_slow_mo)
	await _test_sfx_pool()
	await _test_death_debris()
	await _test_elite_boss_debris()
	await _test_dmg_merge()
	await _test_dmg_cap()
	await _test_hitstop_graded()
	await _test_projectile_integration()
	if _failures.is_empty():
		print("[TEST] HIT FEEL ALL PASS")
		get_tree().quit(0)
	else:
		for f in _failures:
			push_error("[TEST] FAIL: " + f)
		get_tree().quit(1)


func _fail(msg: String) -> void:
	_failures.append(msg)
	print("[TEST] FAIL: " + msg)


func _on_slow_mo(factor: float, duration: float) -> void:
	_slow_mo_events.append([factor, duration])


func _spawn_enemy(pos: Vector2, id: String = "bat") -> Node:
	var e = ENEMY_SCENE.instantiate()
	e.setup(id, 1, 1)
	e.global_position = pos
	e.speed = 0.0
	add_child(e)
	return e


func _debris_count() -> int:
	var n := 0
	for c in _fx.get_children():
		if c is FX_MANAGER_SCRIPT.DeathDebris:
			n += 1
	return n


func _damage_numbers() -> Array:
	var out: Array = []
	for c in _fx.get_children():
		if c is DamageNumber:
			out.append(c)
	return out


func _sfx_total() -> int:
	var n := 0
	for k in SfxBus.hit_stats():
		n += int(SfxBus.hit_stats()[k])
	return n


## headless 首个 process delta 含引擎启动时长（>0.1s），会让短定时器立即触发；
## 先暖 2 帧消耗掉首帧大 delta，再按真实时间等待。
func _wait(s: float) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(s).timeout


## 1) 音效池：12 实例固定；同帧预算 3；节流吞掉后续；跨帧恢复可播
func _test_sfx_pool() -> void:
	if SfxBus.pool_size() != 12:
		_fail("音效池大小 != 12: %d" % SfxBus.pool_size())
	var played := 0
	for i in 100:
		if SfxBus.play_hit("hit"):
			played += 1
	if played <= 0 or played > 3:
		_fail("同帧音效预算异常（应 1-3）: %d" % played)
	if SfxBus.throttled_total() <= 0:
		_fail("音效节流未生效")
	await _wait(0.12)
	var before := _sfx_total()
	for i in 5:
		SfxBus.play_hit("hit")
	await get_tree().process_frame
	if _sfx_total() <= before:
		_fail("跨帧后音效无法播放（计数 %d -> %d）" % [before, _sfx_total()])
	if SfxBus.pool_size() != 12:
		_fail("音效池膨胀: %d" % SfxBus.pool_size())
	print("[TEST] sfx pool OK (same-frame budget=%d, throttled=%d)" % [played, SfxBus.throttled_total()])


## 2) 死亡碎块：普通怪 4-6 块 + 击杀音 + 0.8s 内自毁
func _test_death_debris() -> void:
	var e := _spawn_enemy(Vector2(400, 300))
	var kill_before := int(SfxBus.hit_stats().get("kill", 0))
	e.hp = 1.0
	e.take_damage(10, "fire", false)  # 触发死亡链路（含 enemy_died）
	await get_tree().process_frame
	var n := _debris_count()
	if n < 4 or n > 6:
		_fail("普通死亡碎块数 != 4-6: %d" % n)
	if int(SfxBus.hit_stats().get("kill", 0)) <= kill_before:
		_fail("击杀音未播放")
	await get_tree().create_timer(0.8).timeout
	if _debris_count() != 0:
		_fail("碎块未在 0.8s 内自毁: %d" % _debris_count())
	print("[TEST] death debris OK (normal=%d)" % n)


## 2b) 精英 8-10 块（掺金）/ Boss 14-18 块（slime_king 在 boss 表）+ 延迟消失
func _test_elite_boss_debris() -> void:
	EventBus.enemy_died.emit("bat", Vector2(300, 300), 0, 0, true)
	await get_tree().process_frame
	var n := _debris_count()
	if n < 8 or n > 10:
		_fail("精英碎块数 != 8-10: %d" % n)
	await _wait(0.7)  # 等精英碎块全部自毁（寿命 <= 0.5s），避免与 Boss 碎块混计
	EventBus.enemy_died.emit("slime_king", Vector2(500, 300), 0, 0, false)
	await get_tree().process_frame
	n = _debris_count()
	if n < 14 or n > 18:
		_fail("Boss 碎块数 != 14-18: %d" % n)
	await get_tree().create_timer(1.0).timeout
	if _debris_count() != 0:
		_fail("碎块残留: %d" % _debris_count())
	print("[TEST] elite/boss debris OK")


## 3) 伤害数字：同帧同位置聚合为一个数字（值相加）；跨帧同位置分开
func _test_dmg_merge() -> void:
	EventBus.damage_dealt.emit(5, Vector2(500, 200), false)
	EventBus.damage_dealt.emit(7, Vector2(505, 203), false)
	await get_tree().process_frame
	var nums := _damage_numbers()
	if nums.size() != 1:
		_fail("同帧聚合失败: %d 个数字" % nums.size())
	elif (nums[0].get_node("Label") as Label).text != "12":
		_fail("聚合值错误: %s（期望 12）" % (nums[0].get_node("Label") as Label).text)
	await get_tree().process_frame
	EventBus.damage_dealt.emit(3, Vector2(500, 200), false)
	await get_tree().process_frame
	nums = _damage_numbers()
	if nums.size() != 2:
		_fail("跨帧未分开: %d 个数字" % nums.size())
	print("[TEST] dmg merge OK (1 number for 5+7 same frame)")


## 3b) 上限 24：跨 30 帧不同位置 → 存活数 <= 24（最旧被淘汰）
func _test_dmg_cap() -> void:
	for i in 30:
		EventBus.damage_dealt.emit(i + 1, Vector2(100.0 + float(i) * 3.0, 420.0), false)
		await get_tree().process_frame
	var tracked := int(_fx.call("dmg_number_tracked"))
	if tracked > 24:
		_fail("数字存活数超上限 24: %d" % tracked)
	if tracked < 20:
		_fail("数字淘汰过度: %d" % tracked)
	await _wait(0.7)
	if _damage_numbers().size() != 0:
		_fail("数字未在寿命内全部自毁")
	print("[TEST] dmg cap OK (tracked=%d/24)" % tracked)


## 4) hitstop：普通 30ms / 暴击 60ms / Boss 80ms；同帧同目标去重
func _test_hitstop_graded() -> void:
	var e := _spawn_enemy(Vector2(600, 300))
	_slow_mo_events.clear()
	EventBus.fx_hit_slow.emit(e, false)
	await get_tree().process_frame
	if _slow_mo_events.is_empty() or absf(_slow_mo_events[0][1] - 0.03) > 0.001:
		_fail("普通 hitstop 时长 != 0.03s: %s" % str(_slow_mo_events))
	await _wait(0.25)  # 等全局顿帧 CD（0.15s）结束
	# 同帧同目标二次触发不叠加（CD + 去重双保险）
	_slow_mo_events.clear()
	EventBus.fx_hit_slow.emit(e, true)
	EventBus.fx_hit_slow.emit(e, false)
	EventBus.fx_hit_slow.emit(e, true)
	await get_tree().process_frame
	if _slow_mo_events.size() != 1:
		_fail("同帧同目标去重失败: %d 次触发" % _slow_mo_events.size())
	await _wait(0.25)  # 等全局 CD 结束
	_slow_mo_events.clear()
	EventBus.fx_hit_slow.emit(e, true)
	await get_tree().process_frame
	if _slow_mo_events.is_empty() or absf(_slow_mo_events[0][1] - 0.06) > 0.001:
		_fail("暴击 hitstop 时长 != 0.06s: %s" % str(_slow_mo_events))
	await _wait(0.25)
	_slow_mo_events.clear()
	e.is_boss = true
	EventBus.fx_hit_slow.emit(e, false)
	await get_tree().process_frame
	if _slow_mo_events.is_empty() or absf(_slow_mo_events[0][1] - 0.08) > 0.001:
		_fail("Boss hitstop 时长 != 0.08s: %s" % str(_slow_mo_events))
	print("[TEST] hitstop graded OK (30ms/60ms/80ms, dedup)")


## 5) 实弹集成：projectile 命中 → 音效计数增长 + 伤害数字 + 顿帧事件
func _test_projectile_integration() -> void:
	await _wait(0.25)  # 等上一测试遗留的顿帧 CD 结束
	var e := _spawn_enemy(Vector2(760, 360))
	var hit_before := int(SfxBus.hit_stats().get("hit", 0))
	_slow_mo_events.clear()
	var proj = PROJECTILE_SCENE.instantiate()
	proj.setup({
		"position": Vector2(700, 360),
		"direction": Vector2.RIGHT,
		"speed": 320.0,
		"range": 220.0,
		"damage": 5.0,
		"element": "fire",
		"aoe": 0.0,
		"mods": {},
	})
	add_child(proj)
	var hit := false
	for i in 120:
		if e.hp < e.max_hp:
			hit = true
			break
		await get_tree().physics_frame
	await get_tree().process_frame
	if not hit:
		_fail("弹幕未命中敌人")
	if int(SfxBus.hit_stats().get("hit", 0)) <= hit_before:
		_fail("projectile 命中未播放命中音效")
	if _damage_numbers().is_empty():
		_fail("projectile 命中未生成伤害数字")
	if _slow_mo_events.is_empty():
		_fail("projectile 命中未触发 hitstop")
	await _wait(0.8)
	if _damage_numbers().size() != 0:
		_fail("伤害数字残留")
	print("[TEST] projectile integration OK (sfx+number+hitstop)")
