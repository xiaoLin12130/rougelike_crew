class_name EnemyBase
extends CharacterBody2D
## 敌人基类：AI（近战/远程）、词缀、状态效果、受击/死亡事件

const BULLET_SCENE := preload("res://scenes/game/enemy_bullet.tscn")
const ARENA := Rect2(16, 16, 608, 328)

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
	var to_player := _player.global_position - global_position
	var dist := to_player.length()
	if conf.get("range", 0) > 0:
		_ai_ranged(dist, to_player, delta)
	else:
		_ai_melee(dist, to_player, delta)
	global_position = global_position.clamp(ARENA.position, ARENA.end)

func _tick(delta: float) -> void:
	_atk_cd = maxf(_atk_cd - delta, 0.0)
	_shoot_cd = maxf(_shoot_cd - delta, 0.0)
	_freeze_left = maxf(_freeze_left - delta, 0.0)
	if _poison_left > 0.0:
		_poison_left -= delta
		_take_raw(int(_poison_dps * delta))

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
	if dist > keep:
		velocity = to_player.normalized() * spd
	elif dist < keep * 0.5:
		velocity = -to_player.normalized() * spd * 0.6
	else:
		velocity = Vector2.ZERO
	move_and_slide()
	if dist <= float(conf.get("range", 200)) and _shoot_cd <= 0.0:
		_shoot_cd = float(conf.get("fire_interval", 2.5))
		_fire_bullet(to_player.normalized(), float(conf.get("bullet_speed", 180.0)))

func _fire_bullet(dir: Vector2, speed: float) -> void:
	var bullet := BULLET_SCENE.instantiate()
	bullet.setup(global_position + dir * 12.0, dir, speed, attack, 420.0)
	get_tree().current_scene.add_child(bullet)

func take_damage(dmg: int, _element: String, _is_crit: bool) -> void:
	if _dead:
		return
	var reduced := int(dmg * (1.0 - armor))
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
	EventBus.enemy_died.emit(enemy_id, global_position, int(conf.get("xp", 8)), int(conf.get("gold", 3)))
	EventBus.fx_explosion.emit(global_position, "blade")
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
