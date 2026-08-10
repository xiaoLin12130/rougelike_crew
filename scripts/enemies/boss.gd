extends EnemyBase
## Boss 状态机 AI：IDLE → APPROACH → WINDUP（预警）→ CAST → RECOVER
## 技能池读 enemies.json 的 skills 表（min_phase 门控）；血线触发转阶段（无敌 + 演出 + 清屏冲击波）

const BEAM_RANGE := 300.0
const BEAM_HALF_WIDTH := 18.0
const WHIRL_SPEED := 2.6          # 旋转激光角速度（弧度/秒）
const CHARGE_HIT_DIST := 34.0
const CHARGE_CAST_TIME := 0.9     # 冲撞持续施法时间（_begin_cast 与 charge 预告线长共用）
const BULLET_SPAWN_DIST := 14.0   # ring_barrage 弹幕发射点距 Boss 距离（与 _fire_bullet 一致）
const RECOVER_MIN := 0.5
const RECOVER_MAX := 0.8

enum State { IDLE, APPROACH, WINDUP, CAST, RECOVER }

var phase := 1
var _phases: Array = []
var _summon_enemy := "slime"
var _is_final := false

# ---- 状态机 ----
var state: int = State.IDLE
var _state_time := 0.0
var _current_skill: Dictionary = {}
var _windup_left := 0.0
var _cast_left := 0.0
var _recover_left := 0.0
var _skill_cds: Dictionary = {}   # skill id -> 剩余冷却
var _telegraphs: Array = []       # 预警数据（_draw 渲染）
var auto_casts := true            # 测试可关闭自动 AI，仅保留 debug_cast

# ---- 施法运行数据 ----
var _locked_target := Vector2.ZERO
var _locked_dir := Vector2.RIGHT
var _leap_active := false
var _leap_to := Vector2.ZERO
var _leap_speed := 0.0
var _charge_speed := 0.0
var _beam_dir := Vector2.RIGHT
var _whirl_angle := 0.0
var _hit_timer := 0.0
var _fx_timer := 0.0
var _eruption_queue: Array = []
var _eruption_timer := 0.0
var _zones: Array = []

# ---- 增益 / 护盾 ----
var _buff_armor := 0.0
var _buff_left := 0.0
var _shield_left := 0.0

func setup_boss(boss_id: String, level: int, loop: int, final_boss: bool = false) -> void:
	_is_final = final_boss
	enemy_id = boss_id
	conf = _find_boss_conf(boss_id)
	var base_hp: float = conf.get("hp", 600)
	var base_atk: float = conf.get("attack", 18)
	hp = GameState.enemy_hp(base_hp, level, loop)
	hp *= 1.0 + 0.25 * float(maxi(level, 1) - 1)  # Boss 额外随关卡增强（血量）
	if _is_final:
		hp *= 1.6  # 最终 Boss 额外加强
	max_hp = hp
	attack = int(roundi(GameState.enemy_atk(base_atk, level, loop)))
	speed = float(conf.get("speed", 50))
	scale = Vector2.ONE * float(conf.get("size", 1.6))
	_phases = conf.get("phases", [])
	phase = 1
	state = State.IDLE
	_current_skill = {}
	_skill_cds.clear()
	_telegraphs.clear()
	_eruption_queue.clear()
	_buff_armor = 0.0
	_buff_left = 0.0
	_shield_left = 0.0
	_invuln_left = 0.0
	modulate = Color.WHITE
	match boss_id:
		"slime_king":
			_summon_enemy = "slime"
		"tree_golem":
			_summon_enemy = "goblin"
		"skeleton_king":
			_summon_enemy = "skeleton"
		"imp_king":
			_summon_enemy = "imp"
		"ancient_guardian":
			_summon_enemy = "goblin_archer"
		_:
			_summon_enemy = "bat"
	EventBus.boss_spawned.emit(str(conf.get("name", boss_id)), int(max_hp))
	queue_redraw()

func take_damage(dmg: int, element: String, is_crit: bool) -> void:
	if _dead or _invuln_left > 0.0:
		return
	var reduced := int(dmg * (1.0 - clampf(armor + _buff_armor, 0.0, 1.0)))
	if _shield_left > 0.0:
		reduced = 0  # 护盾完全吸收
	if reduced <= 0:
		if dmg > 0:
			_flash()
		return
	_take_raw(reduced)

func _take_raw(dmg: int) -> void:
	if _dead or dmg <= 0:
		return
	hp -= dmg
	_flash()
	EventBus.boss_hp_changed.emit(int(maxf(hp, 0.0)), int(max_hp))
	queue_redraw()
	if hp <= 0.0:
		_die()

func _draw() -> void:
	# Boss 头顶血条（局部坐标，随 Boss 缩放）
	var w := 90.0
	var h := 7.0
	var y := -34.0
	draw_rect(Rect2(-w / 2.0, y, w, h), Color(0.08, 0.05, 0.12, 0.9))
	draw_rect(Rect2(-w / 2.0, y, w, h), Color(0.4, 0.3, 0.55, 1.0), false, 1.5)
	if max_hp > 0.0:
		var ratio := clampf(hp / max_hp, 0.0, 1.0)
		var fill := Color(1.0, 0.32, 0.28) if ratio > 0.33 else Color(1.0, 0.75, 0.2)
		draw_rect(Rect2(-w / 2.0 + 1.0, y + 1.0, (w - 2.0) * ratio, h - 2.0), fill)
	# 技能预警（半透明红）：circle = 落点/范围红圈，line = 射线红线
	for t in _telegraphs:
		var kind: String = str(t.get("kind", "circle"))
		var tpos: Vector2 = t.get("pos", Vector2.ZERO) - global_position
		if kind == "circle":
			var alpha := float(t.get("alpha", 0.28))
			draw_circle(tpos, float(t.get("radius", 80.0)), Color(1.0, 0.1, 0.08, alpha))
			draw_arc(tpos, float(t.get("radius", 80.0)), 0.0, TAU, 48,
				Color(1.0, 0.28, 0.22, 0.85), 2.0)
		elif kind == "dot":
			# 发射点小圈（ring_barrage）：仅标记弹幕喷出位置，圈内无伤害，故不画"伤害区"大圈
			var dr: float = float(t.get("radius", 6.0))
			draw_circle(tpos, dr, Color(1.0, 0.78, 0.25, 0.32))
			draw_arc(tpos, dr, 0.0, TAU, 14, Color(1.0, 0.9, 0.55, 0.9), 1.5)
		else:
			# line：宽度字段 = 实际伤害判定宽度（光束半宽×2 / 冲撞命中距离×2），画成半透明色带
			var tend: Vector2 = tpos + t.get("dir", Vector2.RIGHT) * float(t.get("length", 300.0))
			var band: float = float(t.get("width", 5.0))
			if band > 8.0:
				draw_line(tpos, tend, Color(1.0, 0.1, 0.08, 0.15), band)
			draw_line(tpos, tend, Color(1.0, 0.1, 0.08, 0.45), 5.0)
	# 护盾环
	if _shield_left > 0.0:
		draw_arc(Vector2.ZERO, 34.0 * scale.x, 0.0, TAU, 40, Color(1.0, 0.85, 0.3, 0.9), 3.0)

func _find_boss_conf(boss_id: String) -> Dictionary:
	for b in GameState.tables.get("enemies", {}).get("bosses", []):
		if str(b.get("id", "")) == boss_id:
			return b
	return {}

func _physics_process(delta: float) -> void:
	if _dead:
		return
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			state = State.IDLE
			velocity = Vector2.ZERO
			return
	_tick_boss(delta)
	_check_phase()
	match state:
		State.IDLE:
			state = State.APPROACH
		State.APPROACH:
			_update_approach(delta)
		State.WINDUP:
			_update_windup(delta)
		State.CAST:
			_update_cast(delta)
		State.RECOVER:
			_update_recover(delta)
	global_position = global_position.clamp(ARENA.position, ARENA.end)
	queue_redraw()

func _tick_boss(delta: float) -> void:
	_tick(delta)  # 基类状态效果（灼烧/毒 DOT、减速、无敌递减等）
	_buff_left = maxf(_buff_left - delta, 0.0)
	_shield_left = maxf(_shield_left - delta, 0.0)
	if _buff_left <= 0.0 and _buff_armor > 0.0:
		_buff_armor = 0.0
		modulate = Color.WHITE
	for key in _skill_cds:
		_skill_cds[key] = maxf(float(_skill_cds[key]) - delta, 0.0)

func _update_approach(delta: float) -> void:
	var to_player := _player.global_position - global_position
	var dist := to_player.length()
	var spd := speed * (0.5 if _freeze_left > 0.0 else 1.0) * (1.3 if phase >= 3 else 1.0)
	if dist > 40.0:
		velocity = to_player.normalized() * spd
	else:
		velocity = Vector2.ZERO
	move_and_slide()
	if dist <= 26.0 and _atk_cd <= 0.0:
		_atk_cd = 1.2
		EventBus.player_hit.emit(attack, global_position)
	if not auto_casts:
		return
	var skill := _pick_skill()
	if not skill.is_empty():
		_start_skill(skill)

func _pick_skill() -> Dictionary:
	var pool: Array = []
	for s in conf.get("skills", []):
		var sd: Dictionary = s
		if int(sd.get("min_phase", 1)) <= phase and float(_skill_cds.get(str(sd.get("id", "")), 0.0)) <= 0.0:
			pool.append(sd)
	if pool.is_empty():
		return {}
	return pool[randi() % pool.size()]

func _start_skill(skill: Dictionary) -> void:
	_current_skill = skill
	# 机制密度：关卡越高技能冷却越短（每关 -5%，最低 70%）
	_skill_cds[str(skill.get("id", "skill"))] = float(skill.get("cooldown", 6.0)) \
		* maxf(0.7, 1.0 - 0.05 * float(maxi(GameState.run.get("level", 1), 1) - 1))
	_windup_left = float(skill.get("windup", 0.6))
	_telegraphs.clear()
	_eruption_queue.clear()
	_leap_active = false
	_charge_speed = 0.0
	_setup_telegraph(skill)
	state = State.WINDUP
	_state_time = 0.0
	velocity = Vector2.ZERO

func debug_cast(skill: Dictionary) -> void:
	## 强制施法（跳过冷却 / 阶段检查），测试与调试用
	if _dead or skill.is_empty():
		return
	_start_skill(skill)

func _setup_telegraph(skill: Dictionary) -> void:
	var kind: String = str(skill.get("telegraph", ""))
	if kind == "":
		return
	var type: String = str(skill.get("type", ""))
	if type == "leap":
		# 跳跃：预告 = 冲刺方向红线 + 落点小圈（落点圈==实际伤害区）。
		# 落点锁定在竞技场内，保证 Boss 一定能跳到圈上（玩家贴墙时不会被卡在边界外）。
		var radius := float(skill.get("radius", 90.0))
		_locked_target = _player.global_position.clamp(ARENA.position, ARENA.end)
		var dir := (_locked_target - global_position).normalized()
		var dist := maxf((_locked_target - global_position).length(), 12.0)
		_telegraphs.append({"kind": "line", "pos": global_position, "dir": dir,
			"length": dist, "width": 22.0})
		_telegraphs.append({"kind": "circle", "pos": _locked_target,
			"radius": radius, "alpha": 0.18})
	elif type == "charge":
		_locked_dir = (_player.global_position - global_position).normalized()
		# 预告线长 = 实际最大冲撞距离（速度 × speed_mult × 施法时长），宽度 = 命中判定直径
		var dash_dist := speed * float(skill.get("speed_mult", 4.0)) * CHARGE_CAST_TIME
		_telegraphs.append({"kind": "line", "pos": global_position, "dir": _locked_dir,
			"length": dash_dist, "width": CHARGE_HIT_DIST * 2.0})
	elif type == "beam":
		_locked_dir = (_player.global_position - global_position).normalized()
		_telegraphs.append({"kind": "line", "pos": global_position, "dir": _locked_dir,
			"length": BEAM_RANGE, "width": BEAM_HALF_WIDTH * 2.0})
	elif type == "root_zone":
		var radius := float(skill.get("radius", 70.0))  # 与 _cast_root_zone 默认一致
		_locked_target = _player.global_position
		_telegraphs.append({"kind": "circle", "pos": _locked_target, "radius": radius})
	elif type == "lava_eruption" or type == "meteor":
		var radius := float(skill.get("radius", 40.0))  # 与 _erupt_at 默认一致
		var count := int(skill.get("count", 4))
		for i in count:
			var p := _random_arena_point()
			_eruption_queue.append(p)
			_telegraphs.append({"kind": "circle", "pos": p, "radius": radius})
	elif type == "whirl_laser":
		_locked_dir = (_player.global_position - global_position).normalized()
		_telegraphs.append({"kind": "line", "pos": global_position, "dir": _locked_dir,
			"length": BEAM_RANGE, "width": BEAM_HALF_WIDTH * 2.0})
	elif type == "ring_barrage":
		# 天女散花：圈内无直接伤害（伤害来自子弹命中），不画误导性大圈，
		# 改画弹幕发射点小圈（与 _cast_ring_barrage/_fire_bullet 的发射半径一致）
		var shots := clampi(int(skill.get("shots", 16)), 4, 48)
		for i in shots:
			var a := TAU * float(i) / float(shots)
			_telegraphs.append({"kind": "dot",
				"pos": global_position + Vector2.from_angle(a) * BULLET_SPAWN_DIST,
				"radius": 6.0})

func _random_arena_point() -> Vector2:
	return Vector2(
		randf_range(ARENA.position.x + 40.0, ARENA.end.x - 40.0),
		randf_range(ARENA.position.y + 40.0, ARENA.end.y - 40.0))

func _update_windup(delta: float) -> void:
	velocity = Vector2.ZERO
	_windup_left -= delta
	if _windup_left <= 0.0:
		_begin_cast()

func _begin_cast() -> void:
	var type: String = str(_current_skill.get("type", ""))
	# 落点类技能（lava_eruption/meteor）保留预告圈，逐点喷发时逐个移除，
	# 让玩家在整个施法期间都能看到剩余危险区；其余技能施法瞬间清空预告。
	if type != "lava_eruption" and type != "meteor":
		_telegraphs.clear()
	velocity = Vector2.ZERO
	_hit_timer = 0.0
	_fx_timer = 0.0
	match type:
		"leap":
			_leap_active = true
			_leap_to = _locked_target
			_leap_speed = maxf(global_position.distance_to(_leap_to) / 0.28, 420.0)
			_cast_left = 0.6
		"charge":
			_charge_dir = _locked_dir
			_charge_speed = speed * float(_current_skill.get("speed_mult", 4.0))
			_cast_left = CHARGE_CAST_TIME
		"beam":
			_cast_left = float(_current_skill.get("duration", 1.2))
		"whirl_laser":
			_whirl_angle = _locked_dir.angle()
			_cast_left = float(_current_skill.get("duration", 2.0))
		"lava_eruption", "meteor":
			_eruption_timer = 0.0
			_cast_left = float(_eruption_queue.size()) * 0.3 + 0.2
		_:
			_cast_left = 0.05
	_execute_cast(_current_skill)
	state = State.CAST
	_state_time = 0.0

func _execute_cast(skill: Dictionary) -> void:
	var type: String = str(skill.get("type", ""))
	match type:
		"projectile_spread":
			_cast_spread(skill)
		"root_zone":
			_cast_root_zone(skill)
		"summon_minions":
			_cast_summon(skill)
		"self_buff":
			_cast_buff(skill)
		"shield_ring":
			_cast_shield(skill)
		"ring_barrage":
			_cast_ring_barrage(skill)
		"summon_wave":
			_cast_summon_wave(skill)
		_:
			pass

func _update_cast(delta: float) -> void:
	var type: String = str(_current_skill.get("type", ""))
	match type:
		"leap":
			_update_leap(delta)
		"charge":
			_update_charge(delta)
		"beam":
			_update_beam(delta)
		"whirl_laser":
			_update_whirl(delta)
		"lava_eruption", "meteor":
			_update_eruption(delta)
	_cast_left -= delta
	if _cast_left <= 0.0 and not _leap_active:
		_finish_cast()

func _finish_cast() -> void:
	velocity = Vector2.ZERO
	_leap_active = false
	_charge_speed = 0.0
	_current_skill = {}
	_telegraphs.clear()
	_recover_left = randf_range(RECOVER_MIN, RECOVER_MAX)
	state = State.RECOVER
	_state_time = 0.0

func _update_recover(delta: float) -> void:
	velocity = Vector2.ZERO
	_recover_left -= delta
	if _recover_left <= 0.0:
		state = State.APPROACH
		_state_time = 0.0

# ---------- 技能实现 ----------

func _cast_spread(skill: Dictionary) -> void:
	var shots := int(skill.get("shots", 5))
	var spread := float(skill.get("spread", 24.0))
	var bullet_speed := float(skill.get("bullet_speed", 180.0))
	if spread >= 360.0:
		# 全周环形：忽略朝向，均匀分布一周（与 ring_barrage 效果一致）
		for i in shots:
			_fire_bullet(Vector2.from_angle(TAU * float(i) / float(shots)), bullet_speed)
		return
	var base := (_player.global_position - global_position).angle()
	if shots <= 1:
		_fire_bullet(Vector2.from_angle(base), bullet_speed)
		return
	for i in shots:
		var off := (i - (shots - 1) / 2.0) * (spread / (shots - 1))
		_fire_bullet(Vector2.from_angle(base + deg_to_rad(off)), bullet_speed)

func _fire_bullet(dir: Vector2, bullet_speed: float) -> void:
	var bullet := BULLET_SCENE.instantiate()
	bullet.setup(global_position + dir * BULLET_SPAWN_DIST, dir, bullet_speed, attack, 420.0)
	get_tree().current_scene.add_child(bullet)

func _cast_root_zone(skill: Dictionary) -> void:
	var radius := float(skill.get("radius", 70.0))
	var duration := float(skill.get("duration", 2.0))
	var dps := max_hp * float(skill.get("dps_mult", 0.05))
	var zone := GroundZone.new()
	zone.setup(_locked_target, radius, duration, dps)
	zone.name = "BossGroundZone"
	get_tree().current_scene.add_child(zone)
	_zones.append(zone)

func _cast_summon(skill: Dictionary) -> void:
	_spawn_minions(int(skill.get("count", 2)), bool(skill.get("elite", false)))

func _cast_summon_wave(skill: Dictionary) -> void:
	## 召唤波：普通小怪 + 精英混召
	_spawn_minions(int(skill.get("count", 3)), false)
	_spawn_minions(int(skill.get("elite_count", 1)), true)

func _cast_ring_barrage(skill: Dictionary) -> void:
	## 天女散花：360° 环形弹幕，多圈错相，施放瞬间全部发射
	var shots := clampi(int(skill.get("shots", 16)), 4, 48)
	var waves := clampi(int(skill.get("waves", 1)), 1, 4)
	var bullet_speed := float(skill.get("bullet_speed", 180.0))
	for w in waves:
		var offset := TAU * float(w % 2) / float(shots * 2)  # 第二圈错开半个角度
		for i in shots:
			var angle := offset + TAU * float(i) / float(shots)
			_fire_bullet(Vector2.from_angle(angle), bullet_speed)

func _cast_buff(skill: Dictionary) -> void:
	_buff_armor = clampf(float(skill.get("armor", 0.5)), 0.0, 1.0)
	_buff_left = float(skill.get("duration", 3.0))
	modulate = Color(1.35, 1.2, 0.6)
	EventBus.fx_explosion.emit(global_position, "buff")

func _cast_shield(skill: Dictionary) -> void:
	_shield_left = float(skill.get("duration", 4.0))
	EventBus.fx_explosion.emit(global_position, "lightning")

func _update_leap(delta: float) -> void:
	if not _leap_active:
		return
	global_position = global_position.move_toward(_leap_to, _leap_speed * delta)
	if global_position.distance_to(_leap_to) <= 2.0 or _cast_left <= 0.0:
		_leap_land()

func _leap_land() -> void:
	_leap_active = false
	var radius := float(_current_skill.get("radius", 90.0))
	EventBus.fx_explosion.emit(_leap_to, "fire")
	EventBus.screen_shake.emit(6.0)
	if is_instance_valid(_player) and _player.global_position.distance_to(_leap_to) <= radius:
		EventBus.player_hit.emit(int(attack * float(_current_skill.get("damage_mult", 1.5))), _leap_to)
	_finish_cast()

func _update_charge(delta: float) -> void:
	if _charge_speed <= 0.0:
		return
	velocity = _charge_dir * _charge_speed
	move_and_slide()
	_fx_timer -= delta
	if _fx_timer <= 0.0:
		_fx_timer = 0.08
		EventBus.fx_explosion.emit(global_position, str(_current_skill.get("trail", "fire")))
	if is_instance_valid(_player) and global_position.distance_to(_player.global_position) <= CHARGE_HIT_DIST:
		EventBus.player_hit.emit(int(attack * 1.5), global_position)
		_finish_cast()
		return
	if get_slide_collision_count() > 0:
		_finish_cast()

func _update_beam(delta: float) -> void:
	_beam_dir = (_player.global_position - global_position).normalized()
	_hit_timer -= delta
	_fx_timer -= delta
	if _hit_timer <= 0.0:
		_hit_timer = 0.25
		if _player_in_ray(global_position, _beam_dir, BEAM_RANGE, BEAM_HALF_WIDTH):
			EventBus.player_hit.emit(attack, global_position)
	if _fx_timer <= 0.0:
		_fx_timer = 0.12
		EventBus.fx_explosion.emit(global_position + _beam_dir * 60.0, "lightning")

func _update_whirl(delta: float) -> void:
	_whirl_angle += WHIRL_SPEED * delta
	var dir := Vector2.from_angle(_whirl_angle)
	_hit_timer -= delta
	_fx_timer -= delta
	if _hit_timer <= 0.0:
		_hit_timer = 0.2
		if _player_in_ray(global_position, dir, BEAM_RANGE, BEAM_HALF_WIDTH):
			EventBus.player_hit.emit(attack, global_position)
	if _fx_timer <= 0.0:
		_fx_timer = 0.1
		EventBus.fx_explosion.emit(global_position + dir * 90.0, "lightning")

func _update_eruption(delta: float) -> void:
	_eruption_timer -= delta
	if _eruption_timer <= 0.0 and not _eruption_queue.is_empty():
		_eruption_timer = 0.3
		var pos: Vector2 = _eruption_queue.pop_front()
		_erupt_at(pos)

func _erupt_at(pos: Vector2) -> void:
	var type: String = str(_current_skill.get("type", "lava_eruption"))
	var radius := float(_current_skill.get("radius", 40.0))
	var dmg := int(attack * (2.0 if type == "meteor" else 1.2))
	# 喷发后移除对应预告圈（世界坐标匹配），保持"圈还在=危险还在"
	for i in range(_telegraphs.size() - 1, -1, -1):
		if Vector2(_telegraphs[i].get("pos", Vector2.ZERO)).distance_to(pos) < 1.0:
			_telegraphs.remove_at(i)
	EventBus.fx_explosion.emit(pos, "fire")
	EventBus.screen_shake.emit(4.0)
	if is_instance_valid(_player) and _player.global_position.distance_to(pos) <= radius:
		EventBus.player_hit.emit(dmg, pos)

func _player_in_ray(origin: Vector2, dir: Vector2, length: float, half_width: float) -> bool:
	if not is_instance_valid(_player):
		return false
	var to_p := _player.global_position - origin
	var proj := to_p.dot(dir)
	if proj < 0.0 or proj > length:
		return false
	return to_p.distance_to(dir * proj) <= half_width

# ---------- 转阶段 ----------

func _check_phase() -> void:
	var ratio := hp / max_hp
	while phase <= _phases.size() and ratio <= float(_phases[phase - 1]):
		phase += 1
		_on_phase_up()

func _on_phase_up() -> void:
	_interrupt_cast()
	_invuln_left = 0.8  # 转阶段无敌（EnemyBase.take_damage 直接免疫）
	EventBus.fx_explosion.emit(global_position, "lightning")
	EventBus.fx_explosion.emit(_player.global_position, "lightning")
	# 全屏闪光：四角 + 中央
	for corner in [
		ARENA.position,
		ARENA.position + Vector2(ARENA.size.x, 0.0),
		ARENA.position + Vector2(0.0, ARENA.size.y),
		ARENA.end,
	]:
		EventBus.fx_explosion.emit(corner, "lightning")
	EventBus.screen_shake.emit(10.0)
	# 清屏冲击波：对场上其他敌人造成伤害
	var shock := int(max_hp * 0.2)
	for e in GameState.get_enemies():
		if e == self or not is_instance_valid(e):
			continue
		if e.has_method("take_damage"):
			e.take_damage(shock, "lightning", false)
	# 转阶段自动补召一波小怪（普通）
	_spawn_minions(3, false)

func _interrupt_cast() -> void:
	_current_skill = {}
	_telegraphs.clear()
	_eruption_queue.clear()
	_leap_active = false
	_charge_speed = 0.0
	velocity = Vector2.ZERO
	for z in _zones:
		if is_instance_valid(z):
			z.queue_free()
	_zones.clear()
	state = State.APPROACH

# ---------- 召唤 ----------

func _spawn_minions(n: int, elite: bool = false) -> void:
	var scene := preload("res://scenes/game/enemy.tscn")
	for i in n:
		var e := scene.instantiate()
		var affix := ""
		if elite:
			var pool: Array = _enemy_conf(_summon_enemy).get("affix_pool", [])
			if not pool.is_empty():
				affix = str(pool[randi() % pool.size()])
		e.setup(_summon_enemy, GameState.run.level, GameState.run.loop, affix)
		if elite:
			e.set_elite()
		e.global_position = global_position + Vector2(randf_range(-50, 50), randf_range(-50, 50))
		get_tree().current_scene.add_child(e)

func _enemy_conf(enemy_id: String) -> Dictionary:
	for e in GameState.tables.get("enemies", {}).get("enemies", []):
		if str(e.get("id", "")) == enemy_id:
			return e
	return {}

func _die() -> void:
	_dead = true
	EventBus.boss_died.emit(global_position)
	var gold: int = int(conf.get("gold", 100))
	var xp: int = GameState.enemy_xp(float(conf.get("xp", 200)), GameState.run.level, GameState.run.loop)
	if _is_final:
		gold *= 3
		xp *= 3
	EventBus.enemy_died.emit(enemy_id, global_position, xp, gold, false)
	EventBus.fx_explosion.emit(global_position, "fire")
	EventBus.fx_explosion.emit(global_position, "lightning")
	EventBus.screen_shake.emit(12.0)
	queue_free()

## 持续地面伤害圈（root_zone）：duration 内对圈内玩家造成 dps 伤害
class GroundZone:
	extends Area2D
	var radius := 60.0
	var duration := 2.0
	var dps := 0.0
	var _life := 0.0
	var _tick := 0.0
	var _anim := 0.0
	var _cracks: Array = []
	var _embers: Array = []

	func setup(center: Vector2, r: float, dur: float, damage_per_sec: float) -> void:
		global_position = center
		radius = r
		duration = dur
		dps = damage_per_sec

	func _ready() -> void:
		collision_layer = 0
		collision_mask = 0
		var shape := CircleShape2D.new()
		shape.radius = radius
		var col := CollisionShape2D.new()
		col.shape = shape
		add_child(col)
		EventBus.fx_explosion.emit(global_position, "fire")
		# 预生成岩浆裂纹与余烬点位（确定性，纯视觉）
		for i in 8:
			_cracks.append([randf() * TAU, randf_range(0.55, 1.0)])
		for i in 6:
			_embers.append([randf() * TAU, randf_range(0.2, 0.95)])

	func _physics_process(delta: float) -> void:
		_life += delta
		if _life >= duration:
			queue_free()
			return
		_anim += delta
		queue_redraw()
		_tick -= delta
		if _tick <= 0.0:
			_tick = 0.5
			var p := get_tree().get_first_node_in_group("player")
			if p != null and p.global_position.distance_to(global_position) <= radius:
				EventBus.player_hit.emit(maxi(int(dps * 0.5), 1), global_position)

	func _draw() -> void:
		# 地面视觉增强（保留原红色伤害圈语义，补充岩浆质感：焦灼底 + 裂纹 + 余烬脉动）
		draw_circle(Vector2.ZERO, radius, Color(0.12, 0.03, 0.02, 0.28))
		draw_circle(Vector2.ZERO, radius, Color(1.0, 0.28, 0.18, 0.16))
		draw_circle(Vector2.ZERO, radius * 0.6, Color(1.0, 0.45, 0.15, 0.12))
		# 岩浆裂纹（锯齿折线，橙红）
		for c in _cracks:
			var a: float = c[0]
			var len: float = radius * c[1]
			var dir := Vector2.from_angle(a)
			var pts := PackedVector2Array([dir * radius * 0.2])
			var seg := dir * len
			var perp := Vector2(-seg.y, seg.x).normalized()
			for k in 4:
				var t := float(k + 1) / 4.0
				pts.append(dir * radius * 0.2 + seg * t + perp * randf_range(-3.0, 3.0))
			pts[pts.size() - 1] = dir * radius * 0.2 + seg
			draw_polyline(pts, Color(1.0, 0.55, 0.2, 0.7), 2.0, true)
		# 余烬亮点（呼吸闪烁）
		for e in _embers:
			var tw := 0.55 + 0.45 * sin(_anim * 6.0 + e[0] * 4.0)
			draw_circle(Vector2.from_angle(e[0]) * radius * e[1],
				1.6, Color(1.0, 0.72, 0.3, 0.8 * tw))
		# 脉动红色外圈（伤害圈语义）
		var pulse := 0.6 + 0.18 * sin(_anim * 5.0)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, Color(1.0, 0.38, 0.24, pulse), 2.0)
