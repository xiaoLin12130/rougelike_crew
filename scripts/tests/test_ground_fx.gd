extends Node2D
## 地面效果视觉实体化验收测试：
## 依次触发 fire 火地 / water 水泽 / poison 毒雾 / ice 雪迹 / thunder 雷云风暴 各一次，
## 断言场景中出现对应 Ground* 视觉节点（2 秒内出现），且效果结束后全部消失（不泄漏）。
## 运行：godot --headless --path . res://scripts/tests/test_ground_fx.tscn

var _failures: Array[String] = []


class DummyEnemy:
	extends Node2D
	var hp := 100.0
	var _dead := false

	func _init() -> void:
		add_to_group("enemy")

	func take_damage(dmg: int, _el: String, _c: bool) -> void:
		hp -= dmg


func _ready() -> void:
	await get_tree().process_frame
	SynergyRegistry.load_synergy_scripts()
	await get_tree().process_frame
	await get_tree().process_frame
	await _test_fire()
	await _test_water()
	await _test_poison()
	await _test_ice()
	await _test_thunder()
	await _test_leak()
	_finish()


func _fail(msg: String) -> void:
	_failures.append(msg)
	push_error("[TEST] FAIL: " + msg)


func _dummy(pos: Vector2) -> Node2D:
	var e := DummyEnemy.new()
	e.global_position = pos
	add_child(e)
	return e


func _find_ground(name: String) -> Node:
	## 场景中按名字查找地面视觉节点（owned=false：代码 add_child 的节点无 owner）
	return find_child(name, true, false)


func _wait_appear(name: String, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if _find_ground(name) != null:
			return true
		await get_tree().create_timer(0.05).timeout
		t += 0.05
	return false


func _wait_gone(name: String, timeout: float, label: String) -> bool:
	var t := 0.0
	while t < timeout:
		if _find_ground(name) == null:
			print("[TEST] ", label, " 视觉节点已随效果结束消失（无泄漏）")
			return true
		await get_tree().create_timer(0.1).timeout
		t += 0.1
	_fail(label + ": 视觉节点 " + str(timeout) + " 秒后仍未消失（泄漏）")
	return false


func _check_appear(name: String, label: String, timeout: float = 2.0) -> void:
	if await _wait_appear(name, timeout):
		print("[TEST] ", label, " 地面视觉出现: ", name)
	else:
		_fail(label + ": 视觉节点 " + name + " 未在 " + str(timeout) + " 秒内出现")


## fire 火地（火M10 龙息）：命中后留 1.5s 火地 → GroundFire
func _test_fire() -> void:
	GameState.run.items["fire_dragon_breath"] = 1
	var e := _dummy(Vector2(300, 300))
	SynergyRegistry.trigger("projectile_hit", {
		"enemy": e, "element": "fire", "pos": Vector2(300, 300)})
	await _check_appear("GroundFire", "fire 火地")
	await _wait_gone("GroundFire", 3.5, "fire 火地")
	GameState.run.items.erase("fire_dragon_breath")
	e.queue_free()
	await get_tree().process_frame


## water 水泽（水M1）：水弹命中留 1.8s 水泽 → GroundWater
func _test_water() -> void:
	GameState.run.items["water_marsh"] = 1
	var e := _dummy(Vector2(420, 300))
	SynergyRegistry.trigger("projectile_hit", {
		"enemy": e, "element": "water", "pos": Vector2(420, 300)})
	await _check_appear("GroundWater", "water 水泽")
	await _wait_gone("GroundWater", 3.5, "water 水泽")
	GameState.run.items.erase("water_marsh")
	e.queue_free()
	await get_tree().process_frame


## poison 毒雾（毒M3 毒雾弥漫扩散落点）→ GroundPoison
func _test_poison() -> void:
	# 毒M3 毒雾弥漫门控（a94b85d）：需持有 poison_m3 才扩散 GroundPoison
	GameState.run.items["poison_m3"] = 1
	var e := _dummy(Vector2(540, 300))
	SynergyRegistry.trigger("enemy_status", {"enemy": e, "kind": "poison", "delta": 2.0})
	await _check_appear("GroundPoison", "poison 毒雾")
	await _wait_gone("GroundPoison", 3.0, "poison 毒雾")
	GameState.run.items.erase("poison_m3")
	e.queue_free()
	await get_tree().process_frame


## ice 雪迹（冰M7 冰雪风暴移动留痕）→ GroundIce
func _test_ice() -> void:
	GameState.run.items["ice_m7"] = 1
	var p := Node2D.new()
	p.global_position = Vector2(660, 300)
	add_child(p)
	SynergyRegistry.trigger("player_move", {
		"player": p, "velocity": Vector2(100, 0), "delta": 1.0})
	await _check_appear("GroundIce", "ice 雪迹")
	await _wait_gone("GroundIce", 3.0, "ice 雪迹")
	GameState.run.items.erase("ice_m7")
	p.queue_free()
	await get_tree().process_frame


## thunder 雷云风暴（雷M9 每 5s 随机落雷）→ 落点 GroundThunder
func _test_thunder() -> void:
	GameState.run.items["thunder_m9"] = 1
	var e := _dummy(Vector2(780, 300))
	var syn := _find_synergy("thunder_synergy.gd")
	if syn == null:
		_fail("thunder: 未找到 thunder_synergy 节点")
		return
	syn.set("_storm_timer", 0.01)  # 触发一次风暴
	await _check_appear("GroundThunder", "thunder 雷云风暴")
	await _wait_gone("GroundThunder", 2.5, "thunder 雷云风暴")
	GameState.run.items.erase("thunder_m9")
	e.queue_free()
	await get_tree().process_frame


func _find_synergy(suffix: String) -> Node:
	for c in get_tree().root.get_node_or_null("SynergyRegistry").get_children():
		if c.get_script() != null and str(c.get_script().resource_path).ends_with(suffix):
			return c
	return null


## 全部效果结束后 3.5s 再扫描一次：任何 Ground* 节点残留都算泄漏
func _test_leak() -> void:
	await get_tree().create_timer(3.5).timeout
	var leftovers: Array = []
	for c in get_children():
		if str(c.name).begins_with("Ground"):
			leftovers.append(str(c.name))
	if leftovers.is_empty():
		print("[TEST] 泄漏检查通过：所有地面视觉已释放")
	else:
		_fail("泄漏检查失败：仍有残留 " + str(leftovers))


func _finish() -> void:
	if _failures.is_empty():
		print("[TEST] GROUND_FX ALL PASS")
		get_tree().quit(0)
	else:
		print("[TEST] GROUND_FX FAILED: %d" % _failures.size())
		get_tree().quit(1)
