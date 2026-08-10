class_name EnemyBase
extends CharacterBody2D
## 敌人基类：AI（近战/远程）、词缀、状态效果、受击/死亡事件

const BULLET_SCENE := preload("res://scenes/game/enemy_bullet.tscn")
const ARENA := Rect2(24, 16, 1232, 688)  # 敌人活动区=整张地图（草地铺满全屏后可走）

var enemy_id := ""
var conf: Dictionary = {}
var hp := 1.0
var max_hp := 1.0
var attack := 1
var speed := 60.0
var armor := 0.0
var is_boss := false
var is_elite := false
var affix_name := ""

var _player: Node2D
var _atk_cd := 0.0
var _shoot_cd := 0.0
var _freeze_left := 0.0
var _poison_left := 0.0
var _poison_dps := 0.0
var _slow_left := 0.0
var _root_left := 0.0
var _blind_left := 0.0
var _burn_left := 0.0
var _burn_dps := 0.0
var _dead := false
var behavior := ""
var _elite_skills: Array = []
var _elite_cd := 0.0
var _elite_frenzy_left := 0.0
var _water_left := 0.0  # wet marker (visual-only; not emitted by gameplay)
var _lightning_left := 0.0  # electrified marker (visual-only; not emitted by gameplay)
var _paralyze_left := 0.0  # paralysis visual marker (written by thunder_synergy; drives blue-white flash + stun icon only)
var _poison_fx_cd := 0.0  # 毒 DOT 特效节流（独立，避免与燃烧互相抢占）
var _burn_fx_cd := 0.0    # 燃烧 DOT 特效节流（独立）
var _hp_bar_left := 0.0  # 受击血条剩余显示时间（秒）

const HP_BAR_W := 26.0
const HP_BAR_H := 3.0
const KNOCKBACK := 9.0
const DOT_FX_INTERVAL := 0.35  # status DOT particle throttle (sec)
const FX_MANAGER := preload("res://scripts/fx/fx_manager.gd")
const ATTACH_ARC_INTERVAL := 0.07  # lightning arc redraw interval (sec)
var _status_attach_root: Node2D
var _status_attach_kind := ""  # current attachment visual kind
var _status_attach_timer := 0.0  # lightning arc refresh throttle
var _lt_arc: Line2D
var _lt_branch: Line2D
var _freeze_shell: Line2D
var _freeze_shards: Array[Line2D] = []
var _paralyze_icon: Node2D

# 技能状态
var _skill_cd := 0.0
var _dive_dir := Vector2.ZERO
var _dive_time := 0.0
var _phase_timer := 0.0
var _invuln_left := 0.0
var _charge_state := 0
var _charge_dir := Vector2.RIGHT
var _charge_timer := 0.0
var _heal_cd := 0.0
var _sep_timer := 0.0
var _rng := RandomNumberGenerator.new()
var _is_split := false  # 分裂产物：弱化属性，防第一关怪数爆炸
var _swarm_cd := 0.0
var _burrow_state := 0
var _burrow_timer := 0.0
var _vanish_left := 0.0
var _vanish_cd := 0.0
var _totem_cd := 0.0
var _camouflage_awake := false

func get_enemy_id() -> String:
	return enemy_id

func is_ranged() -> bool:
	return conf.get("range", 0) > 0

func setup(enemy_id_: String, level: int, loop: int, affix_id: String = "") -> void:
	enemy_id = enemy_id_
	conf = _find_conf(enemy_id_)
	var affixes: Dictionary = GameState.tables.get("enemies", {}).get("affixes", {})
	var affix: Dictionary = affixes.get(affix_id, {})
	affix_name = str(affix.get("name", ""))
	var base_hp: float = conf.get("hp", 45)
	var base_atk: float = conf.get("attack", 8)
	# 精英血量钳制上限 3.5 倍（数据表可调但代码兜底，保证精英可击杀、血包供应稳定）
	var hp_mult: float = minf(float(affix.get("hp_mult", 1.0)), 3.5)
	hp = GameState.enemy_hp(base_hp, level, loop) * hp_mult
	max_hp = hp
	attack = int(roundi(GameState.enemy_atk(base_atk, level, loop) * float(affix.get("atk_mult", 1.0))))
	speed = float(conf.get("speed", 60)) * float(affix.get("speed_mult", 1.0))
	armor = float(affix.get("armor", 0.0))
	var size: float = float(conf.get("size", 1.0)) * float(affix.get("size_mult", 1.0))
	scale = Vector2.ONE * size
	behavior = str(conf.get("behavior", ""))
	_rng.randomize()

func _find_conf(enemy_id_: String) -> Dictionary:
	for e in GameState.tables.get("enemies", {}).get("enemies", []):
		if str(e.get("id", "")) == enemy_id_:
			return e
	return {}

func _ready() -> void:
	add_to_group("enemy")
	_player = get_tree().get_first_node_in_group("player")
	_build_sprite()
	_status_attach_root = Node2D.new()
	_status_attach_root.name = "StatusAttach"
	_status_attach_root.z_index = 2
	add_child(_status_attach_root)
	if is_elite:
		_apply_elite_visual()
	EventBus.apply_status.connect(_on_status)

## 精英怪：affix 强化 + 金色描边标识（掉落血包见 game_root）
func set_elite() -> void:
	is_elite = true
	scale *= 1.15
	# 精英技能：狂暴（通用）+ 1 个类型技能（近战冲锋/召唤/治疗，远程三连/召唤/治疗）
	_elite_skills = ["frenzy"]
	var pool: Array = ["charge", "summon", "heal"] if not is_ranged() else ["triple", "summon", "heal"]
	_elite_skills.append(str(pool[randi() % pool.size()]))

func _apply_elite_visual() -> void:
	# 精英标识：金色色调即可（不叠加四边形光晕，避免视觉噪声）
	var spr := get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if spr == null:
		return
	spr.modulate = Color(1.35, 1.1, 0.35, 1.0)

func _build_sprite() -> void:
	var frames: int = int(conf.get("frames", 2))
	var base_path: String = str(conf.get("sprite", ""))
	var anim := AnimatedSprite2D.new()
	anim.name = "AnimatedSprite2D"
	anim.sprite_frames = SpriteFrames.new()
	anim.sprite_frames.add_animation("idle")
	anim.sprite_frames.set_animation_speed("idle", 6.0)
	for i in frames:
		var p := base_path.replace("_1.png", "_%d.png" % (i + 1)) if frames > 1 else base_path
		anim.sprite_frames.add_frame("idle", load(p))
	var tex := anim.sprite_frames.get_frame_texture("idle", 0)
	if tex != null and tex.get_width() > 64:
		# 宽幅贴图（96px retro Boss）：按内容重心居中，补偿画布内偏移
		anim.offset = _sprite_content_offset(tex)
	anim.play("idle")
	add_child(anim)

## 计算贴图内容（alpha > 0.78）重心相对画布中心的偏移；内容为空时返回零
func _sprite_content_offset(tex: Texture2D) -> Vector2:
	var img := tex.get_image()
	if img == null:
		return Vector2.ZERO
	var sum_x := 0
	var sum_y := 0
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.78:
				sum_x += x
				sum_y += y
				n += 1
	if n == 0:
		return Vector2.ZERO
	return Vector2(img.get_width() / 2.0 - float(sum_x) / n,
		img.get_height() / 2.0 - float(sum_y) / n)

func _physics_process(delta: float) -> void:
	if _dead:
		return
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			return
	_tick(delta)
	_update_status_attachments(delta)
	_tick_skills(delta)
	_tick_separation(delta)
	# 状态效果：灼烧 DOT / 致盲（不攻击）
	if _burn_left > 0.0:
		_burn_left -= delta
		_take_raw(int(_burn_dps * delta))
		if _burn_fx_cd <= 0.0:
			_burn_fx_cd = DOT_FX_INTERVAL
			# 特效分级：DOT tick 走轻量命中（fx_hit），不再每跳触发复合大爆炸
			EventBus.fx_hit.emit(global_position + Vector2(randf_range(-8.0, 8.0), randf_range(-8.0, 8.0)), "fire")
			EventBus.fx_dot_text.emit(global_position, maxi(int(_burn_dps * DOT_FX_INTERVAL), 1), "burn")
	if _blind_left > 0.0:
		return  # 致盲：原地发呆（不移动不攻击）
	var to_player := _player.global_position - global_position
	var dist := to_player.length()
	# 定身/减速：藤蔓缠绕 / 水弹
	if _root_left > 0.0:
		return
	if _slow_left > 0.0:
		var slow = 0.45
		_ai_ranged(dist * slow, to_player, delta) if conf.get("range", 0) > 0 else _ai_melee(dist * slow, to_player, delta)
		global_position = global_position.clamp(ARENA.position, ARENA.end)
		return
	if _charge_state == 2:
		velocity = _charge_dir * speed * 4.0
		move_and_slide()
		if dist <= 22.0:
			EventBus.player_hit.emit(int(attack * 2), global_position)
			_charge_state = 0
		global_position = global_position.clamp(ARENA.position, ARENA.end)
		return
	if conf.get("range", 0) > 0:
		_ai_ranged(dist, to_player, delta)
	else:
		_ai_melee(dist, to_player, delta)
	global_position = global_position.clamp(ARENA.position, ARENA.end)

func _tick(delta: float) -> void:
	_atk_cd = maxf(_atk_cd - delta, 0.0)
	_shoot_cd = maxf(_shoot_cd - delta, 0.0)
	_freeze_left = maxf(_freeze_left - delta, 0.0)
	_slow_left = maxf(_slow_left - delta, 0.0)
	_root_left = maxf(_root_left - delta, 0.0)
	_blind_left = maxf(_blind_left - delta, 0.0)
	_burn_left = maxf(_burn_left - delta, 0.0)
	_water_left = maxf(_water_left - delta, 0.0)
	_lightning_left = maxf(_lightning_left - delta, 0.0)
	_paralyze_left = maxf(_paralyze_left - delta, 0.0)
	_invuln_left = maxf(_invuln_left - delta, 0.0)
	_poison_fx_cd = maxf(_poison_fx_cd - delta, 0.0)
	_burn_fx_cd = maxf(_burn_fx_cd - delta, 0.0)
	if _poison_left > 0.0:
		_poison_left -= delta
		_take_raw(int(_poison_dps * delta))
		SynergyRegistry.trigger("enemy_status", {"enemy": self, "kind": "poison", "stacks": 1, "delta": delta})
		if _poison_fx_cd <= 0.0:
			_poison_fx_cd = DOT_FX_INTERVAL
			# 特效分级：DOT tick 走轻量命中（fx_hit），不再每跳触发复合大爆炸
			EventBus.fx_hit.emit(global_position + Vector2(randf_range(-8.0, 8.0), randf_range(-8.0, 8.0)), "poison")
			EventBus.fx_dot_text.emit(global_position, maxi(int(_poison_dps * DOT_FX_INTERVAL), 1), "poison")
	if _burn_left > 0.0:
		SynergyRegistry.trigger("enemy_status", {"enemy": self, "kind": "burn", "stacks": 1, "delta": delta})
	_apply_status_visual()

func _tick_skills(delta: float) -> void:
	_skill_cd = maxf(_skill_cd - delta, 0.0)
	_tick_elite_skills(delta)
	match behavior:
		"dive":
			# 蝙蝠俯冲：每 3s 加速冲向玩家 0.8s
			if _dive_time > 0.0:
				_dive_time -= delta
				velocity = _dive_dir * speed * 2.6
				move_and_slide()
			elif _skill_cd <= 0.0 and global_position.distance_to(_player.global_position) < 220.0:
				_dive_dir = (_player.global_position - global_position).normalized()
				_dive_time = 0.8
				_skill_cd = 3.0
		"phase":
			# 幽灵相位：每 3.5s 无敌 0.7s
			_phase_timer += delta
			if _phase_timer >= 3.5:
				_phase_timer = 0.0
				_invuln_left = 0.7
				modulate = Color(1, 1, 1, 0.45)
				var tw := create_tween()
				tw.tween_property(self, "modulate", Color.WHITE, 0.7)
		"charge":
			# 冲锋兽：蓄力 0.5s → 直线冲刺
			if _charge_state == 1:
				_charge_timer -= delta
				modulate = Color(1, 0.85, 0.6) if int(_charge_timer * 10) % 2 == 0 else Color.WHITE
				if _charge_timer <= 0.0:
					_charge_state = 2
					_charge_dir = (_player.global_position - global_position).normalized()
					modulate = Color.WHITE
			elif _charge_state == 0 and _skill_cd <= 0.0 and global_position.distance_to(_player.global_position) < 260.0:
				_charge_state = 1
				_charge_timer = 0.5
				_skill_cd = 3.2
			elif _charge_state == 2:
				_charge_timer -= delta
				if _charge_timer <= -0.9:
					_charge_state = 0
		"heal":
			# 巫医：每 4s 给 150px 内友军回 5% 最大生命
			_heal_cd -= delta
			if _heal_cd <= 0.0:
				_heal_cd = 4.0
				for e in get_tree().get_nodes_in_group("enemy"):
					if is_instance_valid(e) and e != self and global_position.distance_to(e.global_position) < 150.0:
						if e.has_method("heal_ally"):
							e.heal_ally(int(e.max_hp * 0.05))
				EventBus.fx_explosion.emit(global_position, "ice")
		"swarm":
			# 蝙蝠群袭：附近 ≥2 只同类时一起俯冲加速
			_swarm_cd -= delta
			if _swarm_cd <= 0.0 and _dive_time <= 0.0:
				var allies := 0
				for e in get_tree().get_nodes_in_group("enemy"):
					var eid = e.get("enemy_id")
					if is_instance_valid(e) and e != self and str(eid) == enemy_id \
							and global_position.distance_to(e.global_position) < 200.0:
						allies += 1
				if allies >= 2 and is_instance_valid(_player):
					_dive_dir = (_player.global_position - global_position).normalized()
					_dive_time = 0.8
					_swarm_cd = 6.0
		"burrow":
			# 蜘蛛钻地：周期消失+无敌，从玩家附近钻出
			_burrow_timer -= delta
			if _burrow_state == 0 and _burrow_timer <= 0.0:
				_burrow_state = 1
				_burrow_timer = 1.2
				_invuln_left = 1.2
				modulate.a = 0.15
			elif _burrow_state == 1 and _burrow_timer <= 0.0:
				_burrow_state = 0
				_burrow_timer = 5.0
				modulate.a = 1.0
				if is_instance_valid(_player):
					global_position = _player.global_position + Vector2(randf_range(-70, 70), randf_range(-70, 70))
					global_position = global_position.clamp(ARENA.position, ARENA.end)
		"vanish":
			# 幽灵隐身：周期隐身接近玩家，现身时双倍速突进
			_vanish_cd -= delta
			if _vanish_left > 0.0:
				_vanish_left -= delta
				if _vanish_left <= 0.0:
					modulate.a = 1.0
			elif _vanish_cd <= 0.0 and is_instance_valid(_player):
				_vanish_left = 1.5
				_vanish_cd = 4.5
				_invuln_left = 1.5
				modulate.a = 0.2
		"totem":
			# 巫医图腾：放置治疗图腾（30s，范围内友军回血）
			_totem_cd -= delta
			if _totem_cd <= 0.0:
				_totem_cd = 8.0
				_spawn_totem()

func _tick_elite_skills(delta: float) -> void:
	if not is_elite or _elite_skills.is_empty() or _dead:
		return
	_elite_cd = maxf(_elite_cd - delta, 0.0)
	_elite_frenzy_left = maxf(_elite_frenzy_left - delta, 0.0)
	if _hp_bar_left > 0.0:
		_hp_bar_left -= delta
		if _hp_bar_left <= 0.0:
			queue_redraw()
	if _elite_cd > 0.0:
		return
	for skill in _elite_skills:
		if _try_elite_skill(str(skill)):
			_elite_cd = 6.0
			break

func _try_elite_skill(skill: String) -> bool:
	match skill:
		"frenzy":
			# 狂暴：3s 内移速+60%、攻击+50%（红色闪烁）
			_elite_frenzy_left = 3.0
			EventBus.fx_explosion.emit(global_position, "fire")
			return true
		"charge":
			if not is_instance_valid(_player) or global_position.distance_to(_player.global_position) > 260.0:
				return false
			_charge_state = 1
			_charge_timer = 0.5
			return true
		"triple":
			if not is_instance_valid(_player):
				return false
			var dir := (_player.global_position - global_position).normalized()
			for i in 3:
				_fire_bullet(dir.rotated(deg_to_rad((i - 1) * 12.0)), float(conf.get("bullet_speed", 150.0)))
			EventBus.fx_explosion.emit(global_position, "lightning")
			return true
		"heal":
			# 精英治疗：回 3% 最大生命（B- 平衡调整，12%→3%；巫医 5% 与图腾 2% 不受影响）
			heal_ally(int(max_hp * 0.03))
			EventBus.fx_explosion.emit(global_position, "ice")
			return true
		"summon":
			_spawn_elite_minion()
			return true
	return false

func _spawn_totem() -> void:
	## 治疗图腾：30s 内对 120px 友军每秒回 2% 最大生命
	var totem := Node2D.new()
	totem.name = "HealTotem"
	var spr := Sprite2D.new()
	spr.texture = load("res://assets/sprites/gen/enemy_healer_1.png")
	spr.scale = Vector2.ONE * 0.8
	totem.add_child(spr)
	totem.global_position = global_position
	get_parent().add_child(totem)
	var alive := true
	var t := 0.0
	var timer := get_tree().create_timer(30.0)
	timer.timeout.connect(func():
		if is_instance_valid(totem):
			totem.queue_free())
	while alive and t < 30.0:
		await get_tree().create_timer(1.0).timeout
		t += 1.0
		if not is_instance_valid(totem) or _dead:
			alive = false
			break
		for e in get_tree().get_nodes_in_group("enemy"):
			if is_instance_valid(e) and e != self and totem.global_position.distance_to(e.global_position) < 120.0:
				if e.has_method("heal_ally"):
					e.heal_ally(int(e.max_hp * 0.02))

func _draw() -> void:
	## 受击头顶血条：受伤后显示 2.5s（精英/Boss 用各自样式，此条仅普通怪）
	if _hp_bar_left <= 0.0 or max_hp <= 0.0 or is_boss:
		return
	var ratio := clampf(hp / max_hp, 0.0, 1.0)
	draw_rect(Rect2(-HP_BAR_W / 2.0, -20.0, HP_BAR_W, HP_BAR_H), Color(0.08, 0.05, 0.1, 0.82))
	var col := Color(0.35, 0.85, 0.4) if ratio > 0.5 else (Color(0.9, 0.75, 0.3) if ratio > 0.25 else Color(0.95, 0.3, 0.25))
	draw_rect(Rect2(-HP_BAR_W / 2.0 + 0.5, -19.5, (HP_BAR_W - 1.0) * ratio, HP_BAR_H - 1.0), col)

func _spawn_elite_minion() -> void:
	## 召唤 1 只同类弱化小怪（50% 属性，10s 自毁）
	var scene := preload("res://scenes/game/enemy.tscn")
	var e := scene.instantiate()
	e.setup(enemy_id, GameState.run.level, GameState.run.loop)
	e.hp = maxf(max_hp * 0.2, 5.0)
	e.max_hp = e.hp
	e.attack = maxi(int(attack * 0.5), 2)
	e.scale = Vector2.ONE * 0.8
	e.global_position = global_position + Vector2(randf_range(-24, 24), randf_range(-24, 24))
	get_parent().add_child(e)
	var e_id: int = e.get_instance_id()
	var kill := get_tree().create_timer(10.0)
	kill.timeout.connect(func():
		var node := instance_from_id(e_id)
		if is_instance_valid(node):
			node.queue_free())

func _atk_mult() -> float:
	return 1.5 if _elite_frenzy_left > 0.0 else 1.0

## 状态附着视觉：按当前激活状态动态切换附着节点（每次只挂一种，先清旧节点再建新节点）。
## 附着节点挂在 self 下，随怪物移动；状态归零后自动清除（含 _die 时）。
func _update_status_attachments(delta: float) -> void:
	var kind := _active_attach_kind()
	if kind != _status_attach_kind:
		_clear_status_attachments()
		_status_attach_kind = kind
		if kind != "":
			_build_status_attach(kind)
	if _status_attach_kind == "lightning":
		_status_attach_timer -= delta
		if _status_attach_timer <= 0.0:
			_status_attach_timer = ATTACH_ARC_INTERVAL
			_refresh_lightning_arcs()
	elif _status_attach_kind == "freeze" and is_instance_valid(_freeze_shell):
		# 冰壳呼吸微动（纯视觉）
		var t := Time.get_ticks_msec() / 1000.0
		_freeze_shell.modulate.a = 0.55 + 0.22 * (0.5 + 0.5 * sin(t * 3.5))
	elif _status_attach_kind == "paralyze" and is_instance_valid(_paralyze_icon):
		# stun icon sway + breathing (visual only)
		var t2 := Time.get_ticks_msec() / 1000.0
		_paralyze_icon.rotation = sin(t2 * 5.0) * 0.3
		_paralyze_icon.modulate.a = 0.7 + 0.3 * (0.5 + 0.5 * sin(t2 * 8.0))

## 附着优先级：冻结 > 燃烧 > 中毒 > 雷电 > 水 > 减速（同帧多状态时只显示一种）。
func _active_attach_kind() -> String:
	if _freeze_left > 0.0:
		return "freeze"
	if _paralyze_left > 0.0:
		return "paralyze"
	if _burn_left > 0.0:
		return "burn"
	if _poison_left > 0.0:
		return "poison"
	if _lightning_left > 0.0:
		return "lightning"
	if _water_left > 0.0:
		return "water"
	if _slow_left > 0.0:
		return "slow"
	return ""

func _clear_status_attachments() -> void:
	if _status_attach_root == null:
		return
	for c in _status_attach_root.get_children():
		c.queue_free()
	_lt_arc = null
	_lt_branch = null
	_freeze_shell = null
	_freeze_shards.clear()
	_paralyze_icon = null

func _build_status_attach(kind: String) -> void:
	match kind:
		"burn":
			var p := FX_MANAGER.spawn_status_particles(_status_attach_root, "burn")
			if p != null:
				p.name = "BurnFlame"
		"water":
			var p2 := FX_MANAGER.spawn_status_particles(_status_attach_root, "water")
			if p2 != null:
				p2.name = "WaterDrops"
		"poison":
			var p3 := FX_MANAGER.spawn_status_particles(_status_attach_root, "poison")
			if p3 != null:
				p3.name = "PoisonBubbles"
		"slow":
			var p4 := FX_MANAGER.spawn_status_particles(_status_attach_root, "slow")
			if p4 != null:
				p4.name = "SlowMist"
		"lightning":
			_build_lightning_attach()
		"freeze":
			_build_freeze_attach()
		"paralyze":
			_build_paralyze_attach()

## paralysis attach: procedural stun icon (3 rotating star points + vertical mark above head) + blue-white spark particles.
## The 0.5s blue-white flash is driven by _apply_status_visual; this only mounts the icon (no logic change).
func _build_paralyze_attach() -> void:
	var s := maxf(scale.x, scale.y)
	_paralyze_icon = Node2D.new()
	_paralyze_icon.name = "ParalyzeIcon"
	_paralyze_icon.position = Vector2(0.0, -26.0 * s)
	_status_attach_root.add_child(_paralyze_icon)
	for i in 3:
		var star := Line2D.new()
		star.name = "StunStar%d" % (i + 1)
		star.width = 1.5
		star.antialiased = true
		star.default_color = Color(0.72, 0.88, 1.0, 0.95)
		star.points = _star_points(4.2 * s)
		var ang := TAU * float(i) / 3.0
		star.position = Vector2(cos(ang), sin(ang)) * 6.0 * s
		star.rotation = ang + PI / 4.0
		_paralyze_icon.add_child(star)
	var mark := Line2D.new()
	mark.name = "StunMark"
	mark.width = 1.8
	mark.antialiased = true
	mark.default_color = Color(0.88, 0.95, 1.0, 0.9)
	mark.points = PackedVector2Array([Vector2(0.0, -4.0 * s), Vector2(0.0, 1.0 * s)])
	_paralyze_icon.add_child(mark)
	var spark := FX_MANAGER.spawn_status_particles(_status_attach_root, "paralyze")
	if spark != null:
		spark.name = "ParalyzeSpark"

static func _star_points(radius: float) -> PackedVector2Array:
	## four-point star closed polyline (stun icon, fully procedural, no texture)
	var pts := PackedVector2Array()
	for i in 8:
		var ang := TAU * float(i) / 8.0
		var r := radius * (0.45 if i % 2 == 1 else 1.0)
		pts.append(Vector2(cos(ang), sin(ang)) * r)
	pts.append(pts[0])
	return pts

## 雷电附着：体表程序化电弧折线（主弧 + 分叉，0.07s 随机跳变）+ 电花粒子。
func _build_lightning_attach() -> void:
	_lt_arc = Line2D.new()
	_lt_arc.name = "LightningArc"
	_lt_arc.width = 2.0
	_lt_arc.antialiased = true
	_lt_arc.default_color = Color(1.0, 0.86, 0.25, 0.95)
	_status_attach_root.add_child(_lt_arc)
	_lt_branch = Line2D.new()
	_lt_branch.name = "LightningBranch"
	_lt_branch.width = 1.1
	_lt_branch.antialiased = true
	_lt_branch.default_color = Color(1.0, 0.95, 0.55, 0.9)
	_status_attach_root.add_child(_lt_branch)
	var spark := FX_MANAGER.spawn_status_particles(_status_attach_root, "lightning")
	if spark != null:
		spark.name = "LightningSpark"
	_refresh_lightning_arcs()

func _refresh_lightning_arcs() -> void:
	if not is_instance_valid(_lt_arc) or not is_instance_valid(_lt_branch):
		return
	var r := 14.0 * maxf(scale.x, scale.y)
	var a1 := randf() * TAU
	var a2 := a1 + PI * randf_range(0.7, 1.3)
	var from := Vector2(cos(a1), sin(a1)) * r * randf_range(0.55, 0.95)
	var to := Vector2(cos(a2), sin(a2)) * r * randf_range(0.55, 0.95)
	var mid := (from + to) * 0.5 + Vector2(randf_range(-r, r), randf_range(-r, r)) * 0.45
	_lt_arc.points = _attach_zigzag(from, mid, 7, r * 0.28)
	_lt_branch.points = _attach_zigzag(mid, to, 5, r * 0.24)
	_lt_arc.modulate.a = randf_range(0.8, 1.0)
	_lt_branch.modulate.a = randf_range(0.6, 0.95)

## 冻结附着：冰壳覆盖（闭合锯齿折线多边形，呼吸微动）+ 冰渣尖角折线 + 下坠冰屑粒子。
func _build_freeze_attach() -> void:
	var s := maxf(scale.x, scale.y)
	var r := 15.0 * s
	_freeze_shell = Line2D.new()
	_freeze_shell.name = "IceShell"
	_freeze_shell.closed = true
	_freeze_shell.width = 2.2
	_freeze_shell.antialiased = true
	_freeze_shell.default_color = Color(0.58, 0.82, 1.0, 1.0)
	var pts := PackedVector2Array()
	var n := 14
	for i in n:
		var ang := TAU * float(i) / float(n)
		var rr := r * randf_range(0.82, 1.12)
		pts.append(Vector2(cos(ang), sin(ang)) * rr)
	_freeze_shell.points = pts
	_status_attach_root.add_child(_freeze_shell)
	_freeze_shards.clear()
	for i in 2:
		var shard := Line2D.new()
		shard.name = "IceShard%d" % (i + 1)
		shard.width = 1.4
		shard.antialiased = true
		shard.default_color = Color(0.78, 0.92, 1.0, 0.85)
		var base_ang := randf() * TAU
		var base := Vector2(cos(base_ang), sin(base_ang)) * r * randf_range(0.72, 0.95)
		var tip := base + Vector2(cos(base_ang + randf_range(-0.5, 0.5)), sin(base_ang + randf_range(-0.5, 0.5))) * r * randf_range(0.35, 0.6)
		shard.points = _attach_zigzag(base, tip, 3, r * 0.08)
		_status_attach_root.add_child(shard)
		_freeze_shards.append(shard)
	var chips := FX_MANAGER.spawn_status_particles(_status_attach_root, "ice")
	if chips != null:
		chips.name = "IceChips"

static func _attach_zigzag(from: Vector2, to: Vector2, steps: int, jitter: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.append(from)
	var seg := to - from
	var perp := Vector2(-seg.y, seg.x).normalized()
	for i in steps:
		var t := float(i + 1) / float(steps)
		pts.append(from + seg * t + perp * randf_range(-jitter, jitter))
	pts[pts.size() - 1] = to
	return pts

func _apply_status_visual() -> void:
	## 状态视觉效果：中毒绿色脉动/燃烧红色/冻结蓝色/减速蓝调（精英金色为基色）
	var spr := get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if spr == null:
		return
	var base := Color(1.35, 1.1, 0.35) if is_elite else Color.WHITE
	var t := Time.get_ticks_msec() / 1000.0
	if _poison_left > 0.0:
		var pulse := 0.62 + 0.28 * (0.5 + 0.5 * sin(t * 7.0))
		var bubble := 0.90 + 0.10 * sin(t * 23.0 + 1.3)
		spr.modulate = _status_tint(base, Color(0.44 * bubble, pulse, 0.52 * bubble))
	elif _burn_left > 0.0:
		var flick := 0.5 + 0.5 * sin(t * 21.0)
		var flick2 := 0.55 + 0.45 * sin(t * 5.7 + 2.1)
		spr.modulate = _status_tint(base, Color(0.80 + 0.30 * flick * flick2, 0.62 + 0.08 * sin(t * 13.0), 0.38 + 0.08 * sin(t * 9.0)))
	elif _freeze_left > 0.0:
		spr.modulate = _status_tint(base, Color(0.56 + 0.04 * sin(t * 5.0), 0.72 + 0.05 * sin(t * 4.0 + 1.0), 1.26 + 0.10 * (0.5 + 0.5 * sin(t * 3.2))))
	elif _paralyze_left > 0.0:
		# paralysis: 0.5s period blue-white flash (bright white <-> pale blue), paired with the stun icon
		var f := 0.5 + 0.5 * sin(t * TAU * 2.0)
		spr.modulate = _status_tint(base, Color(0.62 + 0.55 * f, 0.82 + 0.36 * f, 1.30 + 0.05 * f))
	elif _blind_left > 0.0:
		spr.modulate = _status_tint(base, Color(1.25, 1.25, 0.75))
	elif _slow_left > 0.0 or _root_left > 0.0:
		spr.modulate = _status_tint(base, Color(0.84, 0.84, 1.06 + 0.05 * sin(t * 3.0)))
	else:
		spr.modulate = base
	# 钻地/隐身时的低透明度（不被状态色覆盖）
	if _burrow_state == 1 or _vanish_left > 0.0:
		spr.modulate.a = 0.15 if _burrow_state == 1 else 0.2
	elif _camouflage_awake == false and behavior == "camouflage":
		spr.modulate.a = 0.35

## Blend status color with base: normal enemies multiply; elites lerp to keep gold tone visible
func _status_tint(base: Color, status: Color) -> Color:
	if is_elite:
		return base.lerp(status, 0.62)
	return base * status

func heal_ally(amount: int) -> void:
	if _dead:
		return
	hp = minf(hp + amount, max_hp)
	_flash()

func _tick_separation(delta: float) -> void:
	# 防重叠：每 0.1s 推开附近敌人（性能：场上 ≤32）
	_sep_timer -= delta
	if _sep_timer > 0.0:
		return
	_sep_timer = 0.1
	for e in get_tree().get_nodes_in_group("enemy"):
		if e == self or not is_instance_valid(e):
			continue
		var to_self: Vector2 = global_position - e.global_position
		var d: float = to_self.length()
		var min_d: float = 18.0 * (scale.x + e.scale.x) * 0.5
		if d > 0.01 and d < min_d:
			var push: Vector2 = to_self / d * (min_d - d) * 0.5
			global_position += push
			e.global_position -= push

func _ai_melee(dist: float, to_player: Vector2, delta: float) -> void:
	var spd := speed * (0.5 if _freeze_left > 0.0 else 1.0) * (1.6 if _elite_frenzy_left > 0.0 else 1.0)
	if behavior == "camouflage":
		# 魔像伪装：玩家接近才现身（现身瞬间突进）
		var near := is_instance_valid(_player) and global_position.distance_to(_player.global_position) < 120.0
		var spr := get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
		if spr != null:
			spr.modulate.a = 1.0 if near else 0.35
		if near and not _camouflage_awake:
			_camouflage_awake = true
			_charge_state = 1
			_charge_timer = 0.3
	velocity = to_player.normalized() * spd if dist > 12.0 else Vector2.ZERO
	move_and_slide()
	if dist <= 14.0 and _atk_cd <= 0.0:
		_atk_cd = 1.0
		var dealt := int(attack * _atk_mult())
		EventBus.player_hit.emit(dealt, global_position)
		if behavior == "leech":
			heal_ally(int(dealt * 0.5))  # 骷髅吸血：命中回复 50% 伤害

func _ai_ranged(dist: float, to_player: Vector2, delta: float) -> void:
	var keep: float = float(conf.get("range", 200)) * 0.6
	var spd := speed * (0.5 if _freeze_left > 0.0 else 1.0) * (1.6 if _elite_frenzy_left > 0.0 else 1.0)
	if behavior == "rage" and hp < max_hp * 0.3:
		spd *= 1.5
	if dist > keep:
		velocity = to_player.normalized() * spd
	elif dist < keep * 0.5:
		velocity = -to_player.normalized() * spd * 0.6
	else:
		velocity = Vector2.ZERO
	move_and_slide()
	if dist <= float(conf.get("range", 200)) and _shoot_cd <= 0.0:
		_shoot_cd = float(conf.get("fire_interval", 2.5))
		var dir := to_player.normalized()
		if behavior == "triple":
			# 弓手三连射
			for i in 3:
				_fire_bullet(dir.rotated(deg_to_rad((i - 1) * 10.0)), float(conf.get("bullet_speed", 150.0)))
		elif behavior == "cast":
			# 巫师施法：前摇 0.8s（闪烁）→ 大号火球
			EventBus.fx_explosion.emit(global_position + dir * 10.0, "fire")
			var t := get_tree().create_timer(0.8)
			t.timeout.connect(func():
				if is_instance_valid(self) and not _dead:
					var b := BULLET_SCENE.instantiate()
					b.setup(global_position + dir * 14.0, dir, 130.0, int(attack * 1.8), 520.0)
					b.scale = Vector2.ONE * 1.6
					get_tree().current_scene.add_child(b))
		elif behavior == "sniper":
			# 弓手狙击：蓄力红光 → 高伤穿透弹
			EventBus.fx_explosion.emit(global_position + dir * 10.0, "lightning")
			var t2 := get_tree().create_timer(0.9)
			t2.timeout.connect(func():
				if is_instance_valid(self) and not _dead:
					var b2 := BULLET_SCENE.instantiate()
					b2.setup(global_position + dir * 14.0, dir, 300.0, int(attack * 2.2), 620.0)
					b2.scale = Vector2.ONE * 1.4
					get_tree().current_scene.add_child(b2))
		else:
			_fire_bullet(dir, float(conf.get("bullet_speed", 180.0)))

func _fire_bullet(dir: Vector2, speed: float) -> void:
	var bullet := BULLET_SCENE.instantiate()
	bullet.setup(global_position + dir * 12.0, dir, speed, int(attack * _atk_mult()), 420.0)
	get_tree().current_scene.add_child(bullet)

func take_damage(dmg: int, _element: String, _is_crit: bool) -> void:
	if _dead or _invuln_left > 0.0:
		return
	SynergyRegistry.trigger("enemy_hit", {"enemy": self, "dmg": dmg, "element": _element, "crit": _is_crit})
	# 受击击退（小怪）：精英/Boss 霸体不被击退
	if not is_elite and not is_boss and dmg > 0:
		var p := get_tree().get_first_node_in_group("player") as Node2D
		if is_instance_valid(p):
			var dir := (global_position - p.global_position).normalized()
			if dir.length_squared() > 0.01:
				global_position += dir * KNOCKBACK
	var reduced := int(dmg * (1.0 - armor))
	if behavior == "shield" and _rng.randf() < 0.25:
		reduced = int(reduced * 0.3)  # 骷髅格挡
	_take_raw(reduced)

func _take_raw(dmg: int) -> void:
	if _dead or dmg <= 0:
		return
	hp -= dmg
	_hp_bar_left = 2.5  # 受击显示血条
	queue_redraw()
	_flash()
	if hp <= 0.0:
		_die()

func _flash() -> void:
	var spr := get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if spr == null:
		return
	spr.modulate = Color.WHITE
	var tw := create_tween()
	tw.tween_property(spr, "modulate", Color(1, 1, 1, 1), 0.12).from(Color(3, 3, 3, 1))

func _die() -> void:
	_dead = true
	_clear_status_attachments()
	SynergyRegistry.trigger("enemy_died", {"enemy": self, "pos": global_position})
	var xp_gain: int = GameState.enemy_xp(float(conf.get("xp", 8)), GameState.run.level, GameState.run.loop)
	var gold_gain: int = int(conf.get("gold", 3))
	if _is_split:
		xp_gain = maxi(int(xp_gain * 0.25), 1)
		gold_gain = maxi(int(gold_gain * 0.25), 1)
	EventBus.enemy_died.emit(enemy_id, global_position,
		xp_gain, gold_gain, is_elite)
	EventBus.fx_explosion.emit(global_position, "blade")
	if behavior == "split":
		# 史莱姆分裂：一只小史莱姆（分裂产物不再分裂；单只防止第一关数量爆炸）
		var scene := preload("res://scenes/game/enemy.tscn")
		var e := scene.instantiate()
		e.setup("slime", GameState.run.level, GameState.run.loop)
		e.behavior = ""
		e._is_split = true
		e.hp = maxf(hp * 0.25, 5.0)
		e.max_hp = e.hp
		e.attack = maxi(int(e.attack * 0.5), 2)
		e.scale = Vector2.ONE * 0.5
		e.global_position = global_position + Vector2(randf_range(-12, 12), randf_range(-12, 12))
		get_parent().add_child(e)
		# 分裂产物 20 秒后自毁：防卡场（清场判定依赖场上敌人归零）
		var kill_timer := get_tree().create_timer(20.0)
		var e_id: int = e.get_instance_id()
		kill_timer.timeout.connect(func():
			var node := instance_from_id(e_id)
			if is_instance_valid(node):
				node.queue_free())
	if behavior == "bomb":
		# 爆裂者：死亡自爆
		EventBus.fx_explosion.emit(global_position, "fire")
		EventBus.screen_shake.emit(6.0)
		var p := get_tree().get_first_node_in_group("player")
		if p and p.global_position.distance_to(global_position) < 70.0:
			EventBus.player_hit.emit(int(attack * 2.2), global_position)
	queue_free()

func _on_status(target: Node, kind: String, stacks: int) -> void:
	if target != self or _dead:
		return
	match kind:
		"freeze":
			_freeze_left = 1.0
		"poison":
			_poison_left = 3.0
			_poison_dps = maxf(_poison_dps, max_hp * 0.01 * stacks)
		"slow":
			_slow_left = 1.2
		"root":
			_root_left = 1.5
		"blind":
			_blind_left = 2.0
		"burn":
			# N2 余烬指环：燃烧时长 +0.6s/层（无效道具修复，仅延长时长不改 DPS）
			_burn_left = 2.0 + 0.6 * GameState.total_stacks("fire_ember_ring")
			_burn_dps = maxf(_burn_dps, max_hp * 0.02 * stacks)
