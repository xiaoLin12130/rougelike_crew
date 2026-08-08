extends Camera2D
## 相机：position_smoothing 跟随玩家；shake() 随机噪声震屏，0.15s 内衰减归零。
## 挂入组 "camera"，fx_manager 与战斗模块通过组查找调用。

const SHAKE_DURATION := 0.15
const MAX_SHAKE_POWER := 20.0
const SMOOTHING_SPEED := 7.0
const ARENA_SIZE := Vector2i(640, 360)

var _shake_tween: Tween

func _ready() -> void:
	add_to_group("camera")
	position_smoothing_enabled = true
	position_smoothing_speed = SMOOTHING_SPEED
	limit_left = 0
	limit_top = 0
	limit_right = ARENA_SIZE.x
	limit_bottom = ARENA_SIZE.y

func _process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if is_instance_valid(player):
		global_position = player.global_position
	# 无玩家时保持当前位置静止

func shake(power: float) -> void:
	var p := clampf(power, 0.0, MAX_SHAKE_POWER)
	if p <= 0.0:
		return
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
	_shake_tween = create_tween()
	_shake_tween.tween_method(_apply_shake_offset, p, 0.0, SHAKE_DURATION)
	_shake_tween.tween_callback(_stop_shake)

func _apply_shake_offset(amount: float) -> void:
	offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * amount

func _stop_shake() -> void:
	offset = Vector2.ZERO
