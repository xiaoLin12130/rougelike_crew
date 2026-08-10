extends Node
## 输入抽象层：键盘 → 统一动作向量；后续微信端换成虚拟摇杆实现，战斗代码零改动

var move_vector := Vector2.ZERO
var aim_vector := Vector2.RIGHT
var aim_override := Vector2.ZERO  # 外部瞄准覆盖（自动测试/触屏瞄准用）
var external_move := false  # 外部（自动测试/虚拟摇杆）写入 move_vector 后，本帧跳过键盘覆盖

func _physics_process(_delta: float) -> void:
	if external_move:
		external_move = false
		if aim_override.length_squared() > 0.0:
			aim_vector = aim_override.normalized()
		return
	var v := Vector2.ZERO
	if Input.is_action_pressed("move_left"):
		v.x -= 1.0
	if Input.is_action_pressed("move_right"):
		v.x += 1.0
	if Input.is_action_pressed("move_up"):
		v.y -= 1.0
	if Input.is_action_pressed("move_down"):
		v.y += 1.0
	move_vector = v.normalized()
	if aim_override.length_squared() > 0.0:
		aim_vector = aim_override.normalized()
	elif move_vector.length_squared() > 0.0:
		aim_vector = move_vector
