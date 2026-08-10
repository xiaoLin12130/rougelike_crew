extends Node2D
## Boss 状态机技能测试：force 触发全部技能类型，断言预警生成 / 伤害事件 / 技能效果 / 不卡死
## 运行：godot --headless --path . res://scripts/tests/test_boss_skills.tscn

const BOSS_SCENE := preload("res://scenes/game/boss.tscn")
const SKILL_TESTS := [
	{"tag": "projectile_spread", "skill": {
		"id": "t_spread", "type": "projectile_spread", "shots": 3, "spread": 24.0,
		"bullet_speed": 190.0, "windup": 0.3, "cooldown": 1.0, "min_phase": 1}},
	{"tag": "leap", "skill": {
		"id": "t_leap", "type": "leap", "damage_mult": 1.5, "radius": 90.0,
		"windup": 0.3, "telegraph": "circle", "cooldown": 1.0, "min_phase": 1}},
	{"tag": "root_zone", "skill": {
		"id": "t_root", "type": "root_zone", "radius": 80.0, "duration": 1.2, "dps_mult": 0.05,
		"windup": 0.3, "telegraph": "circle", "cooldown": 1.0, "min_phase": 1}},
	{"tag": "summon_minions", "skill": {
		"id": "t_summon", "type": "summon_minions", "count": 2,
		"windup": 0.2, "cooldown": 1.0, "min_phase": 1}},
	{"tag": "summon_elite", "skill": {
		"id": "t_summon_elite", "type": "summon_minions", "count": 1, "elite": true,
		"windup": 0.2, "cooldown": 1.0, "min_phase": 1}},
	{"tag": "self_buff", "skill": {
		"id": "t_buff", "type": "self_buff", "armor": 0.7, "duration": 2.0,
		"windup": 0.2, "cooldown": 1.0, "min_phase": 1}},
	{"tag": "lava_eruption", "skill": {
		"id": "t_lava", "type": "lava_eruption", "count": 3, "radius": 40.0,
		"windup": 0.3, "telegraph": "circle", "cooldown": 1.0, "min_phase": 1}},
	{"tag": "charge", "skill": {
		"id": "t_charge", "type": "charge", "speed_mult": 4.0, "trail": "fire",
		"windup": 0.3, "telegraph": "line", "cooldown": 1.0, "min_phase": 1}},
	{"tag": "beam", "skill": {
		"id": "t_beam", "type": "beam", "duration": 0.8,
		"windup": 0.3, "telegraph": "line", "cooldown": 1.0, "min_phase": 1}},
	{"tag": "shield_ring", "skill": {
		"id": "t_shield", "type": "shield_ring", "duration": 2.0,
		"windup": 0.2, "cooldown": 1.0, "min_phase": 1}},
	{"tag": "whirl_laser", "skill": {
		"id": "t_whirl", "type": "whirl_laser", "duration": 1.0,
		"windup": 0.3, "telegraph": "line", "cooldown": 1.0, "min_phase": 1}},
	{"tag": "meteor", "skill": {
		"id": "t_meteor", "type": "meteor", "count": 3, "radius": 45.0,
		"windup": 0.3, "telegraph": "circle", "cooldown": 1.0, "min_phase": 1}},
	{"tag": "ring_barrage", "skill": {
		"id": "t_ring", "type": "ring_barrage", "shots": 16, "waves": 2, "bullet_speed": 180.0,
		"windup": 0.3, "telegraph": "dot", "cooldown": 1.0, "min_phase": 1}},
	{"tag": "summon_wave", "skill": {
		"id": "t_wave", "type": "summon_wave", "count": 2, "elite_count": 1,
		"windup": 0.2, "cooldown": 1.0, "min_phase": 1}},
]

var _failures: Array[String] = []
var _hits := 0
var _fx_fire := 0
var _boss: Node2D
var _dummy: CharacterBody2D
var _boss_pos := Vector2(460, 360)

func _ready() -> void:
	GameState.run.level = 1
	GameState.run.loop = 1
	EventBus.player_hit.connect(func(_dmg: int, _pos: Vector2) -> void: _hits += 1)
	EventBus.fx_explosion.connect(func(_pos: Vector2, kind: String) -> void:
		if kind == "fire":
			_fx_fire += 1)
	_spawn_dummy()
	_spawn_boss()
	await get_tree().physics_frame
	for t in SKILL_TESTS:
		await _test_one(str(t.tag), t.skill)
	await _test_phases()
	await _test_real_boss_telegraphs()
	_report()
	_boss.queue_free()
	_dummy.queue_free()
	get_tree().quit(0 if _failures.is_empty() else 1)

func _test_phases() -> void:
	## 转阶段：血线触发 + 无敌 + 清屏冲击波 + 技能池 phase 门控
	await _reset_scene()
	_hits = 0
	# phase 1：技能池只含 min_phase<=1 的技能（slime_king 的 split_frenzy 是 min_phase=2）
	var seen: Dictionary = {}
	for i in 30:
		seen[str(_boss._pick_skill().get("type", "?"))] = true
	if seen.has("summon_minions"):
		_fail("phase_gate: phase1 不应解锁 min_phase=2 技能")
	# 放一只小怪验证清屏冲击波
	var minion: Node = load("res://scenes/game/enemy.tscn").instantiate()
	minion.setup("slime", 1, 1)
	minion.global_position = _boss_pos + Vector2(80, 0)
	add_child(minion)
	await get_tree().physics_frame
	# 打到 66% 血线下（600 -> 350）
	_boss.take_damage(250, "fire", false)
	await _physics_frames(10)
	if _boss.phase != 2:
		_fail("phase_gate: 第一次转阶段未触发 phase=%d" % _boss.phase)
	if _boss._invuln_left <= 0.0:
		_fail("phase_gate: 转阶段未获得无敌")
	if is_instance_valid(minion):
		_fail("phase_gate: 清屏冲击波未击杀小怪")
	if _boss.state != _boss.State.APPROACH:
		_fail("phase_gate: 转阶段后卡在状态 %d" % _boss.state)
	await _physics_frames(55)  # 等 0.8s 无敌结束
	# 打到 33% 血线下（350 -> 198）
	_boss.take_damage(152, "fire", false)
	await _physics_frames(10)
	if _boss.phase != 3:
		_fail("phase_gate: 第二次转阶段未触发 phase=%d" % _boss.phase)
	var unlocked := false
	for i in 30:
		if str(_boss._pick_skill().get("type", "")) == "summon_minions":
			unlocked = true
	if not unlocked:
		_fail("phase_gate: phase3 未解锁 summon_minions")

func _spawn_dummy() -> void:
	_dummy = CharacterBody2D.new()
	_dummy.name = "TestDummy"
	_dummy.add_to_group("player")
	var shape := CircleShape2D.new()
	shape.radius = 10.0
	var col := CollisionShape2D.new()
	col.shape = shape
	_dummy.add_child(col)
	add_child(_dummy)
	_dummy.global_position = _boss_pos + Vector2(150, 0)

func _spawn_boss() -> void:
	_boss = BOSS_SCENE.instantiate()
	_boss.setup_boss("slime_king", 1, 1)
	_boss.global_position = _boss_pos
	add_child(_boss)
	_boss.auto_casts = false

func _test_one(tag: String, skill: Dictionary) -> void:
	await _reset_scene()
	_hits = 0
	_fx_fire = 0
	var enemy_before := get_tree().get_nodes_in_group("enemy").size()
	var zone_before: int = _boss._zones.size()
	var type: String = str(skill.get("type", ""))
	var windup := float(skill.get("windup", 0.3))
	_boss.debug_cast(skill)
	await _physics_frames(3)
	if str(skill.get("telegraph", "")) != "" and _boss._telegraphs.is_empty():
		_fail(tag + ": 未生成预警")
	_check_telegraph(tag, skill)
	# 等待 windup + 施法 + 硬直余量
	await _physics_frames(int((windup + _cast_estimate(skill) + 1.2) * 60.0))
	match type:
		"projectile_spread":
			if _hits <= 0:
				_fail(tag + ": 弹幕未命中玩家")
		"leap":
			if _hits <= 0:
				_fail(tag + ": 落点范围伤害未命中")
		"root_zone":
			if _boss._zones.size() <= zone_before:
				_fail(tag + ": 未生成地面圈")
			if _hits <= 0:
				_fail(tag + ": 地面圈未造成伤害")
		"summon_minions":
			var gained := get_tree().get_nodes_in_group("enemy").size() - enemy_before
			if gained < int(skill.get("count", 2)):
				_fail(tag + ": 召唤数量不足 (%d)" % gained)
			if bool(skill.get("elite", false)):
				var any_elite := false
				for e in get_tree().get_nodes_in_group("enemy"):
					if is_instance_valid(e) and e != _boss and e.is_elite:
						any_elite = true
				if not any_elite:
					_fail(tag + ": 未生成精英随从")
		"self_buff":
			if _boss._buff_armor <= 0.0:
				_fail(tag + ": 未获得护甲增益")
		"lava_eruption", "meteor":
			if _fx_fire < int(skill.get("count", 3)):
				_fail(tag + ": 爆炸次数不足 (%d)" % _fx_fire)
		"charge":
			if _hits <= 0:
				_fail(tag + ": 冲刺未命中玩家")
		"beam":
			if _hits <= 0:
				_fail(tag + ": 激光未命中玩家")
		"whirl_laser":
			if _hits <= 0:
				_fail(tag + ": 旋转激光未命中玩家")
		"shield_ring":
			if _boss._shield_left <= 0.0:
				_fail(tag + ": 护盾未激活")
			var hp_before := int(_boss.hp)
			_boss.take_damage(80, "fire", false)
			if int(_boss.hp) != hp_before:
				_fail(tag + ": 护盾未吸收伤害")
		"ring_barrage":
			var bullets := _count_bullets()
			var shot_count := int(skill.get("shots", 12))
			if bullets < shot_count:
				_fail(tag + ": 环形弹幕子弹数不足 (%d/%d)" % [bullets, shot_count])
			if _hits <= 0:
				_fail(tag + ": 环形弹幕未命中玩家")
		"summon_wave":
			var gained := get_tree().get_nodes_in_group("enemy").size() - enemy_before
			var expected := int(skill.get("count", 3)) + int(skill.get("elite_count", 1))
			if gained < expected:
				_fail(tag + ": 召唤波数量不足 (%d/%d)" % [gained, expected])
			var any_elite := false
			for e in get_tree().get_nodes_in_group("enemy"):
				if is_instance_valid(e) and e != _boss and e.is_elite:
					any_elite = true
			if not any_elite:
				_fail(tag + ": 召唤波未生成精英随从")
	# Boss 不卡死：应回到 APPROACH / IDLE 循环
	if _boss.state != _boss.State.APPROACH and _boss.state != _boss.State.IDLE:
		_fail(tag + ": Boss 卡在状态 %d" % _boss.state)

func _check_telegraph(tag: String, skill: Dictionary) -> void:
	## P0 一致性：预告几何 == 实际伤害判定几何
	var type: String = str(skill.get("type", ""))
	if str(skill.get("telegraph", "")) == "":
		if not _boss._telegraphs.is_empty():
			_fail(tag + ": 无预告技能不应生成预警")
		return
	var radius := float(skill.get("radius", 80.0))
	match type:
		"leap":
			_assert(tag, _boss._telegraphs.size() == 2, "leap 预告数量==2（方向线+落点圈）")
			var lt: Dictionary = _boss._telegraphs[0]
			var ct: Dictionary = _boss._telegraphs[1]
			_assert(tag, str(lt.get("kind", "")) == "line", "leap 预告[0]为方向线")
			_assert(tag, str(ct.get("kind", "")) == "circle", "leap 预告[1]为落点圈")
			_assert(tag, absf(float(ct.get("radius", 0.0)) - radius) < 0.01,
				"leap 落点圈半径==伤害半径 %s" % radius)
			_assert(tag, (ct.get("pos", Vector2.ZERO) - _boss._locked_target).length() < 0.01,
				"leap 落点圈圆心==落点")
			var ldir: Vector2 = Vector2(lt.get("dir", Vector2.ZERO))
			var tdir: Vector2 = (Vector2(ct.get("pos", Vector2.ZERO))
				- Vector2(lt.get("pos", Vector2.ZERO))).normalized()
			_assert(tag, ldir.length() > 0.5 and ldir.normalized().dot(tdir) > 0.999,
				"leap 方向线指向落点")
		"root_zone":
			_assert(tag, _boss._telegraphs.size() == 1, "root_zone 预告数量==1")
			var t: Dictionary = _boss._telegraphs[0]
			_assert(tag, str(t.get("kind", "")) == "circle", "root_zone 预告为 circle")
			_assert(tag, absf(float(t.get("radius", 0.0)) - radius) < 0.01,
				"root_zone 预告半径==地面圈伤害半径 %s" % radius)
			_assert(tag, (t.get("pos", Vector2.ZERO) - _boss._locked_target).length() < 0.01,
				"root_zone 预告圆心==地面圈圆心")
		"lava_eruption", "meteor":
			var count := int(skill.get("count", 3))
			_assert(tag, _boss._telegraphs.size() == count, "落点预告数量==count")
			for i in count:
				var t: Dictionary = _boss._telegraphs[i]
				_assert(tag, str(t.get("kind", "")) == "circle", "落点预告为 circle")
				_assert(tag, absf(float(t.get("radius", 0.0)) - radius) < 0.01,
					"落点预告半径==爆炸伤害半径 %s" % radius)
				_assert(tag, (t.get("pos", Vector2.ZERO) - _boss._eruption_queue[i]).length() < 0.01,
					"落点预告位置==爆炸结算位置")
		"charge":
			_assert(tag, _boss._telegraphs.size() == 1, "charge 预告数量==1")
			var t: Dictionary = _boss._telegraphs[0]
			_assert(tag, str(t.get("kind", "")) == "line", "charge 预告为 line")
			var expected_len: float = _boss.speed * float(skill.get("speed_mult", 4.0)) * _boss.CHARGE_CAST_TIME
			_assert(tag, absf(float(t.get("length", 0.0)) - expected_len) < 0.01,
				"charge 预告线长==最大冲撞距离 %s" % expected_len)
			_assert(tag, absf(float(t.get("width", 0.0)) - _boss.CHARGE_HIT_DIST * 2.0) < 0.01,
				"charge 预告宽度==命中判定直径")
			_assert(tag, (t.get("dir", Vector2.ZERO) - _boss._locked_dir).length() < 0.01,
				"charge 预告方向==冲撞方向")
		"beam", "whirl_laser":
			_assert(tag, _boss._telegraphs.size() == 1, "光束预告数量==1")
			var t: Dictionary = _boss._telegraphs[0]
			_assert(tag, str(t.get("kind", "")) == "line", "光束预告为 line")
			_assert(tag, absf(float(t.get("length", 0.0)) - _boss.BEAM_RANGE) < 0.01,
				"光束预告线长==BEAM_RANGE")
			_assert(tag, absf(float(t.get("width", 0.0)) - _boss.BEAM_HALF_WIDTH * 2.0) < 0.01,
				"光束预告宽度==判定宽度(半宽×2)")
			_assert(tag, (t.get("dir", Vector2.ZERO) - _boss._locked_dir).length() < 0.01,
				"光束预告方向==起始朝向")
		"ring_barrage":
			# 弹幕圈内无直接伤害：禁止大圈预告，只允许发射点小圈
			var shots := clampi(int(skill.get("shots", 16)), 4, 48)
			_assert(tag, _boss._telegraphs.size() == shots, "发射点预告数量==shots")
			for t in _boss._telegraphs:
				_assert(tag, str(t.get("kind", "")) == "dot", "ring_barrage 禁止大圈预告")
				_assert(tag, float(t.get("radius", 0.0)) <= 10.0, "发射点小圈半径<=10")
				_assert(tag, absf((t.get("pos", Vector2.ZERO) - _boss.global_position).length()
					- _boss.BULLET_SPAWN_DIST) < 0.01, "发射点距 Boss==弹幕生成半径")

func _assert(tag: String, ok: bool, what: String) -> void:
	if not ok:
		_fail("%s [预告=伤害] %s" % [tag, what])


func _spawn_boss_for(boss_id: String) -> void:
	if is_instance_valid(_boss):
		_boss.queue_free()
	_boss = BOSS_SCENE.instantiate()
	_boss.setup_boss(boss_id, 1, 1)
	_boss.global_position = _boss_pos
	add_child(_boss)
	_boss.auto_casts = false


func _test_real_boss_telegraphs() -> void:
	## 全 Boss 技能预告一致性审计（P0：预告几何 == 实际伤害判定几何）
	var bosses: Array = GameState.tables.get("enemies", {}).get("bosses", [])
	for b in bosses:
		var boss_id: String = str(b.get("id", ""))
		if boss_id == "":
			continue
		_spawn_boss_for(boss_id)
		await get_tree().physics_frame
		for sk in b.get("skills", []):
			var skill: Dictionary = sk
			if str(skill.get("telegraph", "")) == "":
				continue
			await _reset_scene()
			_boss.debug_cast(skill)
			await _physics_frames(3)
			_check_real_telegraph(boss_id + "/" + str(skill.get("id", "?")), skill)


func _check_real_telegraph(tag: String, skill: Dictionary) -> void:
	## 对 enemies.json 中真实 Boss 技能做预告==伤害 几何校验
	var type: String = str(skill.get("type", ""))
	if str(skill.get("telegraph", "")) == "":
		if not _boss._telegraphs.is_empty():
			_fail(tag + ": 无预告技能不应生成预警")
		return
	match type:
		"leap":
			var radius := float(skill.get("radius", 90.0))
			_assert(tag, _boss._telegraphs.size() == 2, "leap 预告数量==2（方向线+落点圈）")
			var lt: Dictionary = _boss._telegraphs[0]
			var ct: Dictionary = _boss._telegraphs[1]
			_assert(tag, str(lt.get("kind", "")) == "line", "leap 预告[0]为方向线")
			_assert(tag, str(ct.get("kind", "")) == "circle", "leap 预告[1]为落点圈")
			_assert(tag, absf(float(ct.get("radius", 0.0)) - radius) < 0.01,
				"leap 落点圈半径==伤害半径 %s" % radius)
			_assert(tag, (ct.get("pos", Vector2.ZERO) - _boss._locked_target).length() < 0.01,
				"leap 落点圈圆心==落点")
			var ldir: Vector2 = Vector2(lt.get("dir", Vector2.ZERO))
			var tdir: Vector2 = (Vector2(ct.get("pos", Vector2.ZERO))
				- Vector2(lt.get("pos", Vector2.ZERO))).normalized()
			_assert(tag, ldir.length() > 0.5 and ldir.normalized().dot(tdir) > 0.999,
				"leap 方向线指向落点")
		"root_zone":
			var radius := float(skill.get("radius", 70.0))
			_assert(tag, _boss._telegraphs.size() == 1, "root_zone 预告数量==1")
			var t: Dictionary = _boss._telegraphs[0]
			_assert(tag, str(t.get("kind", "")) == "circle", "root_zone 预告为 circle")
			_assert(tag, absf(float(t.get("radius", 0.0)) - radius) < 0.01,
				"root_zone 预告半径==地面圈伤害半径 %s" % radius)
			_assert(tag, (t.get("pos", Vector2.ZERO) - _boss._locked_target).length() < 0.01,
				"root_zone 预告圆心==地面圈圆心")
		"lava_eruption", "meteor":
			var radius := float(skill.get("radius", 40.0))
			var count := int(skill.get("count", 4))
			_assert(tag, _boss._telegraphs.size() == count, "落点预告数量==count")
			for i in count:
				var t: Dictionary = _boss._telegraphs[i]
				_assert(tag, str(t.get("kind", "")) == "circle", "落点预告为 circle")
				_assert(tag, absf(float(t.get("radius", 0.0)) - radius) < 0.01,
					"落点预告半径==爆炸伤害半径 %s" % radius)
				_assert(tag, (t.get("pos", Vector2.ZERO) - _boss._eruption_queue[i]).length() < 0.01,
					"落点预告位置==爆炸结算位置")
		"charge":
			_assert(tag, _boss._telegraphs.size() == 1, "charge 预告数量==1")
			var t: Dictionary = _boss._telegraphs[0]
			_assert(tag, str(t.get("kind", "")) == "line", "charge 预告为 line")
			var expected_len: float = _boss.speed * float(skill.get("speed_mult", 4.0)) * _boss.CHARGE_CAST_TIME
			_assert(tag, absf(float(t.get("length", 0.0)) - expected_len) < 0.01,
				"charge 预告线长==最大冲撞距离 %s" % expected_len)
			_assert(tag, absf(float(t.get("width", 0.0)) - _boss.CHARGE_HIT_DIST * 2.0) < 0.01,
				"charge 预告宽度==命中判定直径")
		"beam", "whirl_laser":
			_assert(tag, _boss._telegraphs.size() == 1, "光束预告数量==1")
			var t: Dictionary = _boss._telegraphs[0]
			_assert(tag, str(t.get("kind", "")) == "line", "光束预告为 line")
			_assert(tag, absf(float(t.get("length", 0.0)) - _boss.BEAM_RANGE) < 0.01,
				"光束预告线长==BEAM_RANGE")
			_assert(tag, absf(float(t.get("width", 0.0)) - _boss.BEAM_HALF_WIDTH * 2.0) < 0.01,
				"光束预告宽度==判定宽度(半宽×2)")
		"ring_barrage":
			var shots := clampi(int(skill.get("shots", 16)), 4, 48)
			_assert(tag, _boss._telegraphs.size() == shots, "发射点预告数量==shots")
			for t in _boss._telegraphs:
				_assert(tag, str(t.get("kind", "")) == "dot", "ring_barrage 禁止大圈预告")
				_assert(tag, float(t.get("radius", 0.0)) <= 10.0, "发射点小圈半径<=10")
				_assert(tag, absf((t.get("pos", Vector2.ZERO) - _boss.global_position).length()
					- _boss.BULLET_SPAWN_DIST) < 0.01, "发射点距 Boss==弹幕生成半径")
		_:
			_fail(tag + ": 未覆盖的预告类型 " + type)

func _reset_scene() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and e != _boss:
			e.queue_free()
	for child in get_tree().current_scene.get_children():
		if child is Area2D and child.get_script() != null \
				and str(child.get_script().resource_path).ends_with("enemy_bullet.gd"):
			child.queue_free()
	if is_instance_valid(_boss):
		for z in _boss._zones:
			if is_instance_valid(z):
				z.queue_free()
		_boss._zones.clear()
		_boss.global_position = _boss_pos
	_dummy.global_position = _boss_pos + Vector2(150, 0)
	await get_tree().physics_frame

func _cast_estimate(skill: Dictionary) -> float:
	match str(skill.get("type", "")):
		"leap":
			return 0.6
		"charge":
			return 0.9
		"beam":
			return float(skill.get("duration", 1.2))
		"whirl_laser":
			return float(skill.get("duration", 2.0))
		"lava_eruption", "meteor":
			return float(skill.get("count", 3)) * 0.3 + 0.2
		_:
			return 0.05

func _physics_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _count_bullets() -> int:
	var n := 0
	for child in get_tree().current_scene.get_children():
		if child is Area2D and child.get_script() != null \
				and str(child.get_script().resource_path).ends_with("enemy_bullet.gd"):
			n += 1
	return n

func _fail(msg: String) -> void:
	_failures.append(msg)
	push_error("BOSS SKILL FAIL: " + msg)

func _report() -> void:
	if _failures.is_empty():
		print("BOSS SKILL TESTS OK")
	else:
		print("BOSS SKILL TESTS FAILED: %d" % _failures.size())
		for f in _failures:
			print("  FAIL: " + f)
