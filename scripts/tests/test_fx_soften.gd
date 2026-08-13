extends Node2D
## 特效柔化 headless 测试（docs/design/特效柔化报告.md，2026-08-13）：
## 1) 死亡碎屑不再用硬方块：DeathDebris 源码断言 draw_rect 移除、改为抗锯齿柔边圆点
## 2) 碎屑尺寸缩小（半径 < 旧下限 2.4）/ 寿命缩短（<= 0.5）/ 数量档位保持（4-6 / 8-10）
## 3) screen_shake 幅度下调：SHAKE_SMALL 3.0→1.5、SHAKE_PLAYER_HIT 2.5→1.2
## 4) 入口幂衰减压缩 compress_shake_power（power 越大衰减越快）：Boss 12 → ≈6
## 5) 实弹链路：emit 大功率震屏 → 相机收到的偏移功率显著降低
## Run: godot --headless --path . res://scripts/tests/test_fx_soften.tscn

const FX_MANAGER_SCRIPT := preload("res://scripts/fx/fx_manager.gd")

var _failures: Array[String] = []


func _ready() -> void:
	_test_debris_source()
	_test_shake_constants()
	await _test_debris_live()
	await _test_shake_pipeline()
	if _failures.is_empty():
		print("[TEST] FX SOFTEN ALL PASS")
		get_tree().quit(0)
	else:
		for f in _failures:
			push_error("[TEST] FAIL: " + f)
		print("[TEST] FX SOFTEN FAILED: %d" % _failures.size())
		get_tree().quit(1)


func _fail(msg: String) -> void:
	_failures.append(msg)
	print("[TEST] FAIL: " + msg)


## headless 首个 process delta 含引擎启动时长（>0.1s），会让短定时器立即触发；
## 先暖 2 帧消耗掉首帧大 delta，再按真实时间等待（同 test_hit_feel）。
func _wait(s: float) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(s).timeout


func _script_source() -> String:
	var f := FileAccess.open("res://scripts/fx/fx_manager.gd", FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()


## 1) 源码断言：DeathDebris 不再画硬方块（draw_rect 废弃），改抗锯齿柔边圆点
func _test_debris_source() -> void:
	var src := _script_source()
	if src.is_empty():
		_fail("无法读取 fx_manager.gd 源码")
		return
	if src.contains("draw_rect(Rect2(-_size"):
		_fail("DeathDebris 仍使用 draw_rect 硬方块")
	if not src.contains("draw_circle(Vector2.ZERO, r, _color, true, -1.0, true)"):
		_fail("DeathDebris 缺少抗锯齿柔边圆点绘制")
	if not src.contains("const DEBRIS_SIZE_MIN := 1.4"):
		_fail("缺少缩小后的碎屑尺寸常量 DEBRIS_SIZE_MIN")
	if not src.contains("const DEBRIS_SIZE_MAX := 2.2"):
		_fail("碎屑尺寸上限未低于旧下限 2.4（DEBRIS_SIZE_MAX）")
	if not src.contains("const GRAV := 1050.0"):
		_fail("碎屑重力未加大（下落更快）")
	if not src.contains("const FADE_WINDOW := 0.7"):
		_fail("碎屑渐隐窗口未提前（更早淡出）")
	print("[TEST] debris soft-dot source OK")


## 3)+4) 震屏常量下调 + 幂衰减压缩曲线
func _test_shake_constants() -> void:
	if FX_MANAGER_SCRIPT.SHAKE_SMALL >= 2.0:
		_fail("SHAKE_SMALL 未下调（应 1.5，当前 %.1f）" % FX_MANAGER_SCRIPT.SHAKE_SMALL)
	if FX_MANAGER_SCRIPT.SHAKE_PLAYER_HIT >= 1.5:
		_fail("SHAKE_PLAYER_HIT 未下调（应 1.2，当前 %.1f）" % FX_MANAGER_SCRIPT.SHAKE_PLAYER_HIT)
	var p12 := FX_MANAGER_SCRIPT.compress_shake_power(12.0)
	var p6 := FX_MANAGER_SCRIPT.compress_shake_power(6.0)
	var p3 := FX_MANAGER_SCRIPT.compress_shake_power(3.0)
	if absf(p12 - 6.1) > 0.4:
		_fail("compress(12) 不在 6 附近（Boss 死亡 12→6 目标）：%.2f" % p12)
	if not (p12 / 12.0 < p6 / 6.0 and p6 / 6.0 < p3 / 3.0):
		_fail("压缩衰减未随 power 增大而加快（应幂衰减）")
	if p3 >= 3.0 or p12 >= 8.0:
		_fail("压缩后幅度仍过大：12→%.2f, 3→%.2f" % [p12, p3])
	print("[TEST] shake constants OK (SMALL=%.1f HIT=%.1f 12→%.2f 3→%.2f)"
		% [FX_MANAGER_SCRIPT.SHAKE_SMALL, FX_MANAGER_SCRIPT.SHAKE_PLAYER_HIT, p12, p3])


## 2) 实弹：普通死亡生成 4-6 柔点，尺寸 < 旧 2.4、寿命 <= 0.5；精英 8-10 档位保持
func _test_debris_live() -> void:
	var fx: Node = FX_MANAGER_SCRIPT.new()
	fx.name = "FxManager"
	add_child(fx)
	await get_tree().process_frame
	EventBus.enemy_died.emit("bat", Vector2(400, 300), 0, 0, false)
	await get_tree().process_frame
	var debris: Array = []
	for c in fx.get_children():
		if c is FX_MANAGER_SCRIPT.DeathDebris:
			debris.append(c)
	if debris.size() < 4 or debris.size() > 6:
		_fail("普通死亡碎屑数不在 4-6：%d" % debris.size())
	else:
		print("[TEST] debris count OK (normal=%d)" % debris.size())
	var size_ok := true
	var life_ok := true
	for d in debris:
		var s := float(d.get("_size"))
		var l := float(d.get("_life"))
		if s <= 0.0 or s >= 2.4:
			size_ok = false
		if l <= 0.0 or l > 0.5:
			life_ok = false
	if not size_ok:
		_fail("碎屑尺寸未缩小（应 < 旧半径下限 2.4）")
	if not life_ok:
		_fail("碎屑寿命未缩短（应 <= 0.5，快速淡出）")
	if size_ok:
		print("[TEST] debris size reduced OK")
	# 等普通碎屑全部自毁后测精英档（避免混计）
	await _wait(0.5)
	EventBus.enemy_died.emit("bat", Vector2(300, 300), 0, 0, true)
	await get_tree().process_frame
	var elite_n := 0
	for c in fx.get_children():
		if c is FX_MANAGER_SCRIPT.DeathDebris:
			elite_n += 1
	if elite_n < 8 or elite_n > 10:
		_fail("精英碎屑数不在 8-10：%d" % elite_n)
	else:
		print("[TEST] elite debris count OK (elite=%d)" % elite_n)
	fx.queue_free()
	await get_tree().process_frame


class FakeCamera:
	extends Node

	var received: Array[float] = []

	func shake(power: float) -> void:
		received.append(power)


## 5) 链路：大功率震屏经 _on_screen_shake 压缩后，相机收到的功率显著降低
func _test_shake_pipeline() -> void:
	var cam := FakeCamera.new()
	cam.name = "FakeCamera"
	cam.add_to_group("camera")
	add_child(cam)
	var fx: Node = FX_MANAGER_SCRIPT.new()
	fx.name = "FxManager"
	add_child(fx)
	await get_tree().process_frame
	EventBus.screen_shake.emit(12.0)
	await get_tree().process_frame
	if cam.received.is_empty():
		_fail("screen_shake(12) 未到达相机")
	elif absf(cam.received[0] - 6.1) > 0.4:
		_fail("Boss 死亡震屏 12 → 相机收到 %.2f（应 ≈6.1）" % cam.received[0])
	else:
		print("[TEST] boss shake 12 → %.2f OK" % cam.received[0])
	await _wait(0.35)  # 等 0.25s 节流冷却
	cam.received.clear()
	EventBus.screen_shake.emit(1.5)
	await get_tree().process_frame
	await get_tree().process_frame
	if cam.received.is_empty():
		_fail("screen_shake(SMALL) 未到达相机")
	elif cam.received[0] >= 2.0:
		_fail("小震屏仍过大：%.2f（应 < 2.0）" % cam.received[0])
	else:
		print("[TEST] small shake 1.5 → %.2f OK" % cam.received[0])
	fx.queue_free()
	cam.queue_free()
	await get_tree().process_frame
