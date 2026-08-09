class_name EnemyBase
extends CharacterBody2D
## 敌人基类：AI（近战/远程）、词缀、状态效果、受击/死亡事件

const BULLET_SCENE := preload("res://scenes/game/enemy_bullet.tscn")
const ARENA := Rect2(24, 24, 1232, 672)

var enemy_id := ""
var conf: Dictionary = {}
var hp := 1.0
var max_hp := 1.0
var attack := 1
var speed := 60.0
var armor := 0.0
var is_boss := false
var affix_name := ""

var _player: Node2D
var _atk_cd := 0.0
var _shoot_cd := 0.0
var _freeze_left := 0.0
var _poison_left := 0.0
var _poison_dps := 0.0
var _dead := false
var behavior := ""

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
	hp = GameState.enemy_hp(base_hp, level, loop) * float(affix.get("hp_mult", 1.0))
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
	EventBus.apply_status.connect(_on_status)

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
	anim.play("idle")
	add_child(anim)

func _physics_process(delta: float) -> void:
	if _dead:
		return
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			return
	_tick(delta)
	_tick_skills(delta)
	_tick_separation(delta)
	var to_player := _player.global_position - global_position
	var dist := to_player.length()
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
	_invuln_left = maxf(_invuln_left - delta, 0.0)
	if _poison_left > 0.0:
		_poison_left -= delta
		_take_raw(int(_poison_dps * delta))

func _tick_skills(delta: float) -> void:
	_skill_cd = maxf(_skill_cd - delta, 0.0)
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
	var spd := speed * (0.5 if _freeze_left > 0.0 else 1.0)
	velocity = to_player.normalized() * spd if dist > 12.0 else Vector2.ZERO
	move_and_slide()
	if dist <= 14.0 and _atk_cd <= 0.0:
		_atk_cd = 1.0
		EventBus.player_hit.emit(attack, global_position)

func _ai_ranged(dist: float, to_player: Vector2, delta: float) -> void:
	var keep: float = float(conf.get("range", 200)) * 0.6
	var spd := speed * (0.5 if _freeze_left > 0.0 else 1.0)
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
		else:
			_fire_bullet(dir, float(conf.get("bullet_speed", 180.0)))

func _fire_bullet(dir: Vector2, speed: float) -> void:
	var bullet := BULLET_SCENE.instantiate()
	bullet.setup(global_position + dir * 12.0, dir, speed, attack, 420.0)
	get_tree().current_scene.add_child(bullet)

func take_damage(dmg: int, _element: String, _is_crit: bool) -> void:
	if _dead or _invuln_left > 0.0:
		return
	var reduced := int(dmg * (1.0 - armor))
	if behavior == "shield" and _rng.randf() < 0.25:
		reduced = int(reduced * 0.3)  # 骷髅格挡
	_take_raw(reduced)

func _take_raw(dmg: int) -> void:
	if _dead or dmg <= 0:
		return
	hp -= dmg
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
	EventBus.enemy_died.emit(enemy_id, global_position,
		GameState.enemy_xp(float(conf.get("xp", 8)), GameState.run.level, GameState.run.loop),
		int(conf.get("gold", 3)))
	EventBus.fx_explosion.emit(global_position, "blade")
	if behavior == "split":
		# 史莱姆分裂：两只小史莱姆（分裂产物不再分裂，防无限循环）
		var scene := preload("res://scenes/game/enemy.tscn")
		for i in 2:
			var e := scene.instantiate()
			e.setup("slime", GameState.run.level, GameState.run.loop)
			e.behavior = ""
			e.hp = maxf(hp * 0.4, 5.0)
			e.scale = Vector2.ONE * 0.6
			e.global_position = global_position + Vector2(randf_range(-12, 12), randf_range(-12, 12))
			get_parent().add_child(e)
			# 分裂产物 20 秒后自毁：防卡场（清场判定依赖场上敌人归零）
			var kill_timer := get_tree().create_timer(20.0)
			kill_timer.timeout.connect(func():
				if is_instance_valid(e):
					e.queue_free())
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
