extends CharacterBody2D
## 玩家：移动 / 闪避 / 无敌帧 / 四方向行走动画（DEMO）。
## 受击入口 damage_taken()：只广播 EventBus.player_hit，扣血与死亡由 game_root 处理。

const SPRITE_PATHS := {
	"up": [
		"res://assets/sprites/gen/player_up_1.png",
		"res://assets/sprites/gen/player_up_2.png",
	],
	"down": [
		"res://assets/sprites/gen/player_down_1.png",
		"res://assets/sprites/gen/player_down_2.png",
	],
	"left": [
		"res://assets/sprites/gen/player_left_1.png",
		"res://assets/sprites/gen/player_left_2.png",
	],
	"right": [
		"res://assets/sprites/gen/player_right_1.png",
		"res://assets/sprites/gen/player_right_2.png",
	],
}
const ANIM_FPS := 8.0

var facing := "down"
var _anim: AnimatedSprite2D
var _dash_time_left := 0.0
var _dash_cd_left := 0.0
var _invuln_left := 0.0
var _dash_dir := Vector2.DOWN


func _ready() -> void:
	_anim = $AnimatedSprite2D
	_anim.sprite_frames = _build_frames()
	_anim.animation = facing
	_anim.play(facing)


## 代码构建 SpriteFrames：4 方向 × 2 帧循环动画。
func _build_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	for dir in SPRITE_PATHS:
		frames.add_animation(dir)
		frames.set_animation_speed(dir, ANIM_FPS)
		frames.set_animation_loop(dir, true)
		for path in SPRITE_PATHS[dir]:
			frames.add_frame(dir, load(path))
	return frames


func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	_try_dash()
	if _dash_time_left > 0.0:
		velocity = _dash_dir * _dash_speed()
	else:
		velocity = InputRouter.move_vector * _move_speed()
	move_and_slide()
	_update_anim(velocity)


## 速度 = balance.player.speed × (1 + 移速聚合加成)。
func _move_speed() -> float:
	var base: float = GameState.balance().get("player", {}).get("speed", 220.0)
	return base * (1.0 + GameState.aggregate_bonus("speed"))


func _dash_speed() -> float:
	return GameState.balance().get("player", {}).get("dash_speed", 520.0)


func _tick_timers(delta: float) -> void:
	_dash_time_left = maxf(_dash_time_left - delta, 0.0)
	_dash_cd_left = maxf(_dash_cd_left - delta, 0.0)
	_invuln_left = maxf(_invuln_left - delta, 0.0)


func _try_dash() -> void:
	if _dash_cd_left > 0.0 or not Input.is_action_just_pressed("dash"):
		return
	var bal: Dictionary = GameState.balance().get("player", {})
	_dash_dir = InputRouter.move_vector if InputRouter.move_vector.length_squared() > 0.0 else _facing_vector()
	_dash_time_left = bal.get("dash_time", 0.18)
	_dash_cd_left = bal.get("dash_cd", 2.0)
	_invuln_left = bal.get("invuln_time", 0.35)


func _facing_vector() -> Vector2:
	match facing:
		"up":
			return Vector2.UP
		"left":
			return Vector2.LEFT
		"right":
			return Vector2.RIGHT
		_:
			return Vector2.DOWN


func _update_anim(v: Vector2) -> void:
	if v.length_squared() > 1.0:
		if absf(v.x) > absf(v.y):
			facing = "left" if v.x < 0.0 else "right"
		else:
			facing = "up" if v.y < 0.0 else "down"
		if _anim.animation != facing or not _anim.is_playing():
			_anim.play(facing)
	elif _anim.is_playing():
		_anim.stop()
		_anim.frame = 0


## 受击入口：无敌期间忽略，否则广播 EventBus.player_hit（game_root 扣血/死亡）。
func damage_taken(dmg: int) -> void:
	if _invuln_left > 0.0:
		return
	EventBus.player_hit.emit(dmg, global_position)


func is_invulnerable() -> bool:
	return _invuln_left > 0.0
