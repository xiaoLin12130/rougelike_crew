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
	_mount_aura()
	_mount_shield_aura()
	_mount_melee()


## 构筑光环（Agent C）：程序化特效节点，挂在玩家下自动跟随移动。
func _mount_aura() -> void:
	var aura: Node = load("res://scripts/fx/player_aura.gd").new()
	aura.name = "PlayerAura"
	add_child(aura)


## 护盾光环（2026-08-12）：淡蓝半透明环，护盾池 > 0 显示、归零隐藏。
func _mount_shield_aura() -> void:
	var aura: Node = load("res://scripts/player/shield_aura.gd").new()
	aura.name = "ShieldAura"
	add_child(aura)


## 常驻近战攻击（N7 方案 A）：独立近战层，与法术自动施法共存
func _mount_melee() -> void:
	var melee: Node = load("res://scripts/combat/melee_attack.gd").new()
	melee.name = "MeleeAttack"
	add_child(melee)


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
	SynergyRegistry.trigger("player_move", {"player": self, "velocity": velocity, "delta": delta})


## 速度 = balance.player.speed × (1 + 移速加成) × 水M7 洋流乘区。
## 移速加成聚合（P1 接线）：基础 aggregate_bonus("speed") + 移4 追风（击杀短暂加成）
## + 移6 破风（冲刺后加成），封顶 100%（移10 风行者提升上限 wind_speed_cap_bonus，
## 与 wind_synergy._speed_bonus 口径一致）；水M7 洋流（water_ocean_current 在水泽区域）
## 为独立乘区 run.water_m7_speed。
func _move_speed() -> float:
	var base: float = GameState.balance().get("player", {}).get("speed", 220.0)
	var bonus := maxf(GameState.aggregate_bonus("speed"), 0.0)
	bonus += maxf(float(GameState.run.get("wind_kill_speed_bonus", 0.0)), 0.0)
	bonus += maxf(float(GameState.run.get("wind_m6_speed_bonus", 0.0)), 0.0)
	var cap := 1.0 + maxf(float(GameState.run.get("wind_speed_cap_bonus", 0.0)), 0.0)
	var speed := base * (1.0 + minf(bonus, cap))
	speed *= maxf(float(GameState.run.get("water_m7_speed", 1.0)), 0.1)
	return speed


func _dash_speed() -> float:
	return GameState.balance().get("player", {}).get("dash_speed", 520.0)


func _tick_timers(delta: float) -> void:
	_dash_time_left = maxf(_dash_time_left - delta, 0.0)
	_dash_cd_left = maxf(_dash_cd_left - delta, 0.0)
	_invuln_left = maxf(_invuln_left - delta, 0.0)


func _try_dash(force := false) -> void:
	if _dash_cd_left > 0.0 or (not force and not Input.is_action_just_pressed("dash")):
		return
	var bal: Dictionary = GameState.balance().get("player", {})
	_dash_dir = InputRouter.move_vector if InputRouter.move_vector.length_squared() > 0.0 else _facing_vector()
	_dash_time_left = bal.get("dash_time", 0.18)
	_dash_cd_left = bal.get("dash_cd", 2.0)
	_invuln_left = bal.get("invuln_time", 0.35)


## 触屏闪避入口（虚拟摇杆调用）：跳过键盘判定，方向沿用移动向量/面朝方向
func request_dash() -> void:
	_try_dash(true)


func grant_invuln(seconds: float) -> void:
	## 升级等场景的短暂无敌：覆盖当前无敌帧并触发闪烁反馈
	_invuln_left = maxf(_invuln_left, seconds)
	if seconds > 0.0:
		var spr := get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
		if spr != null:
			var tw := create_tween()
			tw.tween_property(spr, "modulate", Color(1, 1, 1, 0.35), 0.12)
			tw.tween_property(spr, "modulate", Color.WHITE, 0.12)
			for i in maxi(int(seconds / 0.24), 2):
				tw.tween_property(spr, "modulate", Color(1, 1, 1, 0.35), 0.12)
				tw.tween_property(spr, "modulate", Color.WHITE, 0.12)


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
