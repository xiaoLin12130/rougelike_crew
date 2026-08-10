extends Node2D
## 摇杆行为诊断（方案A）：模拟触摸左侧/中间/右侧 → 全部应为移动摇杆；
## 闪避按钮区域 → 不生成摇杆；双指 → 第二指忽略
## 运行：godot --headless --path . res://scripts/tests/diag_joystick.tscn

var _fails := 0

func _ready() -> void:
	await get_tree().physics_frame
	var jsk: Node = load("res://scripts/ui/game/virtual_joystick.gd").new()
	jsk.force_enable = true
	add_child(jsk)
	await get_tree().physics_frame
	var vp: Vector2 = jsk.get_viewport().get_visible_rect().size
	print("[JSK] viewport=%s" % vp)
	var router: Node = get_tree().root.get_node("InputRouter")
	# 1) 左/中/右按下都应是移动摇杆
	for i in 3:
		var pos := Vector2(vp.x * [0.2, 0.5, 0.85][i], vp.y * 0.5)
		jsk.simulate_touch(i, true, pos)
		var kind: String = str(jsk._active.get(i, {}).get("kind", "?"))
		var ok: bool = kind == "move" and router.external_move
		print("[JSK] 位置%d(%s) 按下: kind=%s external_move=%s → %s" % [
			i, pos, kind, router.external_move, "OK" if ok else "FAIL"])
		if not ok:
			_fails += 1
		# 拖动 → move_vector 应更新
		jsk.simulate_drag(i, pos + Vector2(40, 0))
		var mv_ok: bool = router.move_vector.x > 0.9
		print("[JSK] 位置%d 拖动后: move=%s → %s" % [i, router.move_vector, "OK" if mv_ok else "FAIL"])
		if not mv_ok:
			_fails += 1
		jsk.simulate_touch(i, false, pos)
		if router.move_vector != Vector2.ZERO:
			print("[JSK] 位置%d 松手后 move 未清零 → FAIL" % i)
			_fails += 1
	# 2) 闪避按钮区域：不生成摇杆（右下角）
	var dash_pos := vp - Vector2(45, 45)
	jsk.simulate_touch(9, true, dash_pos)
	var dash_ok: bool = jsk._active.is_empty() and jsk._dash_press.has(9)
	print("[JSK] 闪避按钮区域按下: 生成摇杆=%s dash_press=%s → %s" % [
		not jsk._active.is_empty(), jsk._dash_press.has(9), "OK" if dash_ok else "FAIL"])
	if not dash_ok:
		_fails += 1
	jsk.simulate_touch(9, false, dash_pos)
	# 3) 双指：第一指移动后，第二指忽略
	jsk.simulate_touch(0, true, Vector2(50, 50))
	jsk.simulate_touch(1, true, Vector2(vp.x - 50, vp.y * 0.3))
	var second_ok: bool = not jsk._active.has(1) and jsk._active.has(0)
	print("[JSK] 双指: 第一指=%s 第二指忽略=%s → %s" % [
		jsk._active.has(0), not jsk._active.has(1), "OK" if second_ok else "FAIL"])
	if not second_ok:
		_fails += 1
	jsk.simulate_touch(0, false, Vector2(50, 50))
	jsk.simulate_touch(1, false, Vector2(vp.x - 50, vp.y * 0.3))
	print("[JSK] %s" % ("ALL OK" if _fails == 0 else "%d FAIL" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)
