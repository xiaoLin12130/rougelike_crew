extends EnemyBase
## Boss 状态机 AI：IDLE → APPROACH → WINDUP（预警）→ CAST → RECOVER
## 技能池读 enemies.json 的 skills 表（min_phase 门控）；血线触发转阶段（无敌 + 演出 + 清屏冲击波）

const BEAM_RANGE := 300.0
const BEAM_HALF_WIDTH := 18.0
const DEFAULT_AOE_RADIUS := 40.0  # 落点/爆炸类技能统一默认伤害半径（telegraph 与 _erupt_at 共用）
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

# ---- 新技能 v2：spiral / homing_shot / sweep / spike_trail / blink / wall / enrage / split ----
var _spiral_base := 0.0
var _spiral_rings := 0
var _sweep_start_angle := 0.0
var _sweep_end_angle := 0.0
var _enrage := false
var _enrage_speed_mult := 1.0
var _enrage_cd_mult := 1.0

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
	_enrage = false
	_enrage_speed_mult = 1.0
	_enrage_cd_mult = 1.0
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
			var dr: float = float(t.get("radius", 6.0))
			if dr > 12.0:
				# 伤害点（spike_trail 地刺）：红圈 == 实际伤害半径
				draw_circle(tpos, dr, Color(1.0, 0.1, 0.08, 0.28))
				draw_arc(tpos, dr, 0.0, TAU, 32, Color(1.0, 0.28, 0.22, 0.85), 2.0)
				draw_circle(tpos, dr * 0.35, Color(1.0, 0.9, 0.6, 0.55))
			else:
				# 发射点小圈（ring_barrage/spiral/homing）：仅标记弹幕喷出位置，圈内无伤害
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
	## 问题18：古神二阶段回血（enemies.json regen：phase 门槛 + 每秒百分比）
	var regen: Dictionary = conf.get("regen", {})
	if not regen.is_empty() and phase >= int(regen.get("phase", 99)):
		hp = minf(hp + max_hp * float(regen.get("per_sec", 0.0)) * delta, max_hp)
	## 问题18：古神阶段防御（enemies.json defense：phase 门槛 + 减伤比例）
	var defs: Dictionary = conf.get("defense", {})
	if not defs.is_empty() and phase >= int(defs.get("phase", 99)):
		armor = clampf(float(defs.get("reduce", 0.0)), 0.0, 0.6)
	if _buff_left <= 0.0 and _buff_armor > 0.0:
		_buff_armor = 0.0
		modulate = Color.WHITE
	for key in _skill_cds:
		_skill_cds[key] = maxf(float(_skill_cds[key]) - delta, 0.0)

func _update_approach(delta: float) -> void:
	var to_player := _player.global_position - global_position
	var dist := to_player.length()
	var spd := speed * (0.5 if _freeze_left > 0.0 else 1.0) * (1.3 if phase >= 3 else 1.0) \
		* (_enrage_speed_mult if _enrage else 1.0)
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
		if str(sd.get("type", "")) == "enrage":
			continue  # enrage 为阶段被动，不占施法池
		if int(sd.get("min_phase", 1)) <= phase and float(_skill_cds.get(str(sd.get("id", "")), 0.0)) <= 0.0:
			pool.append(sd)
	if pool.is_empty():
		return {}
	return pool[randi() % pool.size()]

func _start_skill(skill: Dictionary) -> void:
	_current_skill = skill
	# 机制密度（问题13：按关卡阶梯加强，幅度加大）：每关 -8% 冷却，最低 55%；
	# 弹幕密度/范围在 _setup_telegraph 与施法处按 level 缩放（见 _level_density_mult）
	_skill_cds[str(skill.get("id", "skill"))] = float(skill.get("cooldown", 6.0)) \
		* maxf(0.55, 1.0 - 0.08 * float(maxi(GameState.run.get("level", 1), 1) - 1)) \
		* (_enrage_cd_mult if _enrage else 1.0)
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
		var radius := float(skill.get("radius", DEFAULT_AOE_RADIUS))  # 与 _erupt_at 默认一致
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
	elif type == "spiral":
		# 旋转弹幕环：圈内无直接伤害（伤害来自子弹），画发射点小圈（与 ring_barrage 一致）
		var shots := clampi(int(skill.get("shots", 12)), 4, 48)
		for i in shots:
			var a := TAU * float(i) / float(shots)
			_telegraphs.append({"kind": "dot",
				"pos": global_position + Vector2.from_angle(a) * BULLET_SPAWN_DIST,
				"radius": 6.0})
	elif type == "homing_shot":
		# 追踪弹：圈内无直接伤害（伤害来自子弹命中），画发射点小圈
		var count := clampi(int(skill.get("count", 4)), 1, 12)
		var spread := float(skill.get("spread", 20.0))
		var base := (_player.global_position - global_position).angle()
		for i in count:
			var off := 0.0 if count <= 1 else (i - (count - 1) / 2.0) * (spread / float(count - 1))
			_telegraphs.append({"kind": "dot",
				"pos": global_position + Vector2.from_angle(base + deg_to_rad(off)) * BULLET_SPAWN_DIST,
				"radius": 6.0})
	elif type == "sweep":
		# 扇形激光扫：预告 = 起止两条边界线（宽度=判定宽度），实际伤害区=扫过的整个扇形
		var base := (_player.global_position - global_position).angle()
		var half := deg_to_rad(float(skill.get("sweep_angle", 120.0)) * 0.5)
		_sweep_start_angle = base - half
		_sweep_end_angle = base + half
		_telegraphs.append({"kind": "line", "pos": global_position, "dir": Vector2.from_angle(_sweep_start_angle),
			"length": BEAM_RANGE, "width": BEAM_HALF_WIDTH * 2.0})
		_telegraphs.append({"kind": "line", "pos": global_position, "dir": Vector2.from_angle(_sweep_end_angle),
			"length": BEAM_RANGE, "width": BEAM_HALF_WIDTH * 2.0})
	elif type == "spike_trail":
		# 地刺轨迹：沿玩家移动方向连续伤害点（dot 半径=伤害半径），延迟后逐点爆炸
		var count := clampi(int(skill.get("count", 6)), 2, 14)
		var spacing := float(skill.get("spacing", 64.0))
		var radius := float(skill.get("radius", DEFAULT_AOE_RADIUS))
		_locked_target = _player.global_position
		var pdir: Vector2 = _player.velocity
		if pdir.length() < 20.0:
			pdir = (_player.global_position - global_position).normalized()
		else:
			pdir = pdir.normalized()
		for i in count:
			var p := _locked_target + pdir * (spacing * 0.5 + spacing * float(i))
			p = p.clamp(ARENA.position + Vector2(24, 24), ARENA.end - Vector2(24, 24))
			_eruption_queue.append(p)
			_telegraphs.append({"kind": "dot", "pos": p, "radius": radius})
	elif type == "blink":
		# 闪现：双圈预告（起点淡圈 + 落点红圈），落点圈==实际爆炸伤害区
		var radius := float(skill.get("radius", 90.0))
		_locked_target = _player.global_position.clamp(ARENA.position, ARENA.end)
		_telegraphs.append({"kind": "circle", "pos": global_position, "radius": radius, "alpha": 0.12})
		_telegraphs.append({"kind": "circle", "pos": _locked_target, "radius": radius, "alpha": 0.34})
	elif type == "wall":
		# 弹幕墙：玩家所在行/列生成一排落点圈（==爆炸伤害区），逐点喷发
		var radius := float(skill.get("radius", DEFAULT_AOE_RADIUS))
		var count := clampi(int(skill.get("count", 8)), 3, 16)
		var horizontal := randf() < 0.5
		var lane: float
		var start: float
		var span: float
		if horizontal:
			lane = clampf(_player.global_position.y, ARENA.position.y + 50.0, ARENA.end.y - 50.0)
			start = ARENA.position.x + 60.0
			span = ARENA.size.x - 120.0
		else:
			lane = clampf(_player.global_position.x, ARENA.position.x + 50.0, ARENA.end.x - 50.0)
			start = ARENA.position.y + 60.0
			span = ARENA.size.y - 120.0
		for i in count:
			var t := span * float(i) / float(count - 1)
			var p := Vector2(start + t, lane) if horizontal else Vector2(lane, start + t)
			_eruption_queue.append(p)
			_telegraphs.append({"kind": "circle", "pos": p, "radius": radius})

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
	if type != "lava_eruption" and type != "meteor" and type != "spike_trail" and type != "wall":
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
		"spiral":
			_spiral_rings = 0
			_cast_left = float(_current_skill.get("duration", 1.6))
		"homing_shot":
			_cast_left = 0.2
		"sweep":
			_cast_left = float(_current_skill.get("duration", 1.6))
		"spike_trail", "wall":
			_eruption_timer = float(_current_skill.get("delay", 0.6))
			_cast_left = float(_current_skill.get("delay", 0.6)) \
				+ float(_current_skill.get("interval", 0.3)) * float(maxi(_eruption_queue.size(), 1)) + 0.3
		"blink":
			_cast_left = 0.1
		"enrage":
			_cast_left = 0.05
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
		"spiral":
			_spiral_base = (_player.global_position - global_position).angle()
			_fx_timer = float(skill.get("ring_interval", 0.14))
			_cast_spiral_ring(skill, 0)
		"homing_shot":
			_cast_homing(skill)
		"blink":
			_blink_now()
		"enrage":
			_apply_enrage()
		"split":
			_cast_split(skill)
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
		"spiral":
			_update_spiral(delta)
		"sweep":
			_update_sweep(delta)
		"spike_trail", "wall":
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

func _level_density_mult() -> float:
	## 问题13：弹幕密度随关卡阶梯加强——第 2 关起 +12%/关，4 关起累计 +25%/关（幅度大）
	var level := maxi(int(GameState.run.get("level", 1)), 1)
	var mult := 1.0
	if level >= 2:
		mult += 0.12 * float(level - 1)
	if level >= 4:
		mult += 0.13 * float(level - 3)
	return mult

func _cast_spread(skill: Dictionary) -> void:
	var shots := maxi(int(roundi(float(skill.get("shots", 5)) * _level_density_mult())), 1)
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

func _fire_bullet(dir: Vector2, bullet_speed: float, homing: bool = false,
		turn_rate: float = 3.0, lifetime: float = 4.0) -> void:
	var bullet := BULLET_SCENE.instantiate()
	bullet.setup(global_position + dir * BULLET_SPAWN_DIST, dir, bullet_speed, attack, 420.0,
		homing, turn_rate, lifetime)
	get_tree().current_scene.add_child(bullet)

func _cast_spiral_ring(skill: Dictionary, ring: int) -> void:
	## 旋转弹幕环：一圈 shots 发，角度 = 起始朝向 + 每圈偏移递进
	var shots := clampi(int(roundi(float(skill.get("shots", 12)) * _level_density_mult())), 4, 72)
	var bullet_speed := float(skill.get("bullet_speed", 170.0))
	var offset := deg_to_rad(float(skill.get("offset", 18.0)))
	var rot := _spiral_base + offset * float(ring)
	for i in shots:
		_fire_bullet(Vector2.from_angle(rot + TAU * float(i) / float(shots)), bullet_speed)

func _update_spiral(delta: float) -> void:
	## cast 期间按 ring_interval 连发多圈，每圈角度偏移递进
	_fx_timer -= delta
	if _fx_timer <= 0.0:
		_fx_timer = float(_current_skill.get("ring_interval", 0.14))
		_spiral_rings += 1
		_cast_spiral_ring(_current_skill, _spiral_rings)

func _cast_homing(skill: Dictionary) -> void:
	## 追踪弹：小角度扇形发射 count 发，弹幕自带转向玩家（enemy_bullet.homing）
	var count := clampi(int(roundi(float(skill.get("count", 4)) * _level_density_mult())), 1, 16)
	var spread := float(skill.get("spread", 20.0))
	var bullet_speed := float(skill.get("bullet_speed", 135.0))
	var turn_rate := float(skill.get("turn_rate", 3.0))
	var lifetime := float(skill.get("lifetime", 4.0))
	var base := (_player.global_position - global_position).angle()
	for i in count:
		var off := 0.0 if count <= 1 else (i - (count - 1) / 2.0) * (spread / float(count - 1))
		_fire_bullet(Vector2.from_angle(base + deg_to_rad(off)), bullet_speed, true, turn_rate, lifetime)

func _update_sweep(delta: float) -> void:
	## 扇形激光扫：角度从 _sweep_start_angle 插值到 _sweep_end_angle；
	## 伤害语义=已扫过扇形内持续危险（与"起止边界线"预告几何一致）
	var dur := maxf(float(_current_skill.get("duration", 1.6)), 0.1)
	var t := 1.0 - clampf(_cast_left / dur, 0.0, 1.0)
	var cur := lerpf(_sweep_start_angle, _sweep_end_angle, t)
	var dir := Vector2.from_angle(cur)
	_hit_timer -= delta
	_fx_timer -= delta
	if _hit_timer <= 0.0:
		_hit_timer = 0.2
		if _player_in_swept(global_position, cur, BEAM_RANGE):
			EventBus.player_hit.emit(attack, global_position)
	if _fx_timer <= 0.0:
		_fx_timer = 0.1
		EventBus.fx_explosion.emit(global_position + dir * 80.0, "fire")  # 落雷误触发修复：敌意激光改红色系

func _player_in_swept(origin: Vector2, current_angle: float, length: float) -> bool:
	## 玩家方向角落在 [起始角, 当前角] 已扫过扇形内，且距离在射程内
	if not is_instance_valid(_player):
		return false
	var to_p := _player.global_position - origin
	if to_p.length() > length:
		return false
	var span := absf(angle_difference(_sweep_start_angle, current_angle))
	var rel := absf(angle_difference(_sweep_start_angle, to_p.angle()))
	return rel <= span + 0.02

func _blink_now() -> void:
	## 闪现：cast 瞬间瞬移到落点并范围爆炸（复用 leap 落点结算几何）
	global_position = _locked_target
	var radius := float(_current_skill.get("radius", 90.0))
	EventBus.fx_explosion.emit(_locked_target, "fire")
	EventBus.screen_shake.emit(6.0)
	if is_instance_valid(_player) and _player.global_position.distance_to(_locked_target) <= radius:
		EventBus.player_hit.emit(int(attack * float(_current_skill.get("damage_mult", 1.5))), _locked_target)

func _apply_enrage_from(skill: Dictionary) -> void:
	## 狂暴（幂等）：移速 +speed_mult、弹幕冷却 ×cd_mult，转阶段自动触发
	if _enrage:
		return
	_enrage = true
	_enrage_speed_mult = float(skill.get("speed_mult", 1.3))
	_enrage_cd_mult = float(skill.get("cd_mult", 0.7))
	EventBus.fx_explosion.emit(global_position, "fire")
	EventBus.screen_shake.emit(5.0)

func _apply_enrage() -> void:
	_apply_enrage_from(_current_skill)

func _cast_split(skill: Dictionary) -> void:
	## 分裂：原地弹开出生 count 只小怪（史莱姆王=小史莱姆）
	var count := clampi(int(skill.get("count", 2)), 1, 5)
	EventBus.fx_explosion.emit(global_position, "poison")
	var scene := preload("res://scenes/game/enemy.tscn")
	for i in count:
		var e := scene.instantiate()
		e.setup(_summon_enemy, GameState.run.level, GameState.run.loop, "")
		e.global_position = global_position + Vector2(randf_range(-22, 22), randf_range(-22, 22))
		get_tree().current_scene.add_child(e)

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
	_spawn_minions(maxi(int(roundi(float(skill.get("count", 2)) * _level_density_mult())), 1), bool(skill.get("elite", false)))

func _cast_summon_wave(skill: Dictionary) -> void:
	## 召唤波：普通小怪 + 精英混召
	_spawn_minions(maxi(int(roundi(float(skill.get("count", 3)) * _level_density_mult())), 1), false)
	_spawn_minions(maxi(int(roundi(float(skill.get("elite_count", 1)) * _level_density_mult())), 1), true)

func _cast_ring_barrage(skill: Dictionary) -> void:
	## 天女散花：360° 环形弹幕，多圈错相，施放瞬间全部发射
	var shots := clampi(int(roundi(float(skill.get("shots", 16)) * _level_density_mult())), 4, 72)
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
	EventBus.fx_explosion.emit(global_position, "buff")  # 落雷误触发修复：护盾不再闪雷

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
		EventBus.fx_explosion.emit(global_position + _beam_dir * 60.0, "fire")  # 落雷误触发修复：敌意光束改红色系

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
		EventBus.fx_explosion.emit(global_position + dir * 90.0, "fire")  # 落雷误触发修复：旋激光改红色系

func _update_eruption(delta: float) -> void:
	_eruption_timer -= delta
	if _eruption_timer <= 0.0 and not _eruption_queue.is_empty():
		_eruption_timer = float(_current_skill.get("interval", 0.3))
		var pos: Vector2 = _eruption_queue.pop_front()
		_erupt_at(pos)

func _erupt_at(pos: Vector2) -> void:
	var type: String = str(_current_skill.get("type", "lava_eruption"))
	var radius := float(_current_skill.get("radius", DEFAULT_AOE_RADIUS))
	var dmg := int(attack * float(_current_skill.get("damage_mult", 2.0 if type == "meteor" else 1.2)))
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
	_check_enrage_trigger()

func _check_enrage_trigger() -> void:
	## 阶段被动：type==enrage 且 phase>=min_phase 时自动狂暴（幂等）
	if _enrage:
		return
	for s in conf.get("skills", []):
		var sd: Dictionary = s
		if str(sd.get("type", "")) == "enrage" and phase >= int(sd.get("min_phase", 99)):
			_apply_enrage_from(sd)
			return

func _on_phase_up() -> void:
	_interrupt_cast()
	_invuln_left = 0.8  # 转阶段无敌（EnemyBase.take_damage 直接免疫）
	## 落雷误触发修复（Beauvoir 报告 P0-2）：转阶段视觉改金色冲击（不再是雷系技能视觉）
	EventBus.fx_explosion.emit(global_position, "gold")
	EventBus.fx_explosion.emit(_player.global_position, "gold")
	# 全屏金色闪光：四角 + 中央
	for corner in [
		ARENA.position,
		ARENA.position + Vector2(ARENA.size.x, 0.0),
		ARENA.position + Vector2(0.0, ARENA.size.y),
		ARENA.end,
	]:
		EventBus.fx_explosion.emit(corner, "gold")
	EventBus.screen_shake.emit(10.0)
	# 清屏冲击波：对场上其他敌人造成伤害
	var shock := int(max_hp * 0.2)
	for e in GameState.get_enemies():
		if e == self or not is_instance_valid(e):
			continue
		if e.has_method("take_damage"):
			e.take_damage(shock, "void", false)
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
	## 问题9：Boss 死亡先清技能产物（弹幕/地面圈/召唤残留），避免商店界面残留伤害特效
	_clear_skill_leftovers()
	var gold: int = int(conf.get("gold", 100))
	var xp: int = GameState.enemy_xp(float(conf.get("xp", 200)), GameState.run.level, GameState.run.loop)
	if _is_final:
		gold *= 3
		xp *= 3
	EventBus.enemy_died.emit(enemy_id, global_position, xp, gold, false)
	EventBus.fx_explosion.emit(global_position, "fire")
	EventBus.fx_explosion.emit(global_position, "gold")  # 落雷误触发修复：死亡爆改金色（无雷系语义）
	EventBus.screen_shake.emit(12.0)
	queue_free()

func _clear_skill_leftovers() -> void:
	## 清掉该 Boss 遗留的弹幕（enemy_bullet 无 group，按脚本路径扫描）与地面圈（BossGroundZone）
	var scene := get_tree().current_scene
	if scene == null:
		return
	# 1) Boss 地面圈（root_zone/spike 等，命名 BossGroundZone）
	for n in scene.get_children():
		if n.name == "BossGroundZone":
			n.queue_free()
	# 2) 场景中仍在飞行的敌方弹幕（按脚本路径判断，避免误杀召唤物/玩家弹幕）
	for n in scene.get_children():
		if n.get_script() != null and str(n.get_script().resource_path).ends_with("enemy_bullet.gd"):
			n.queue_free()

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
