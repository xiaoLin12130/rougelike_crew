extends SceneTree
## 护盾显示测试（问题5）：hud.gd 血条灰色层 + 护盾文本
##  - 有护盾（defense_synergy._shield=30，max_hp=120）时：灰色层节点可见、
##    value=30/max=120、血量文本 "100/120（护盾 30）" 含"护盾"
##  - 无护盾/归零时：灰色层隐藏、文本不含"护盾"
## Run: godot --headless --path . -s res://scripts/tests/test_hud_shield.gd

var failures: Array[String] = []
var _frame := 0
var _phase := 0
var _hud: CanvasLayer


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false
	match _phase:
		0:
			_run_no_shield()
			_phase = 1
		1:
			_run_with_shield()
			if failures.is_empty():
				print("ALL PASS")
			else:
				for f in failures:
					push_error("HUD SHIELD FAIL: " + f)
			quit(0 if failures.is_empty() else 1)
			return true
	return false


func fail(msg: String) -> void:
	failures.append(msg)
	print("[HUD] FAIL: " + msg)


func _gs() -> Node:
	return root.get_node_or_null("GameState")


func _run_no_shield() -> void:
	var gs := _gs()
	if gs == null:
		fail("GameState autoload missing")
		return
	gs.new_run()
	gs.run.max_hp = 120
	gs.run.hp = 100
	_hud = load("res://scenes/ui/hud.tscn").instantiate()
	_hud.name = "HUD"
	root.add_child(_hud)
	_hud._refresh()
	if _hud._shield_bar == null:
		fail("灰色层节点缺失")
		return
	if _hud._shield_bar.visible:
		fail("无护盾时灰色层应隐藏")
	if str(_hud._hp_label.text) != "100/120":
		fail("无护盾文本应为 100/120: " + _hud._hp_label.text)
	if str(_hud._hp_label.text).contains("护盾"):
		fail("无护盾时文本不应含'护盾': " + _hud._hp_label.text)


func _run_with_shield() -> void:
	var reg := root.get_node_or_null("SynergyRegistry")
	if reg == null:
		fail("SynergyRegistry autoload missing")
		return
	var ds: Node = load("res://scripts/synergies/defense_synergy.gd").new()
	ds.name = "DefenseSynergy"
	reg.add_child(ds)
	ds._shield = 30.0
	_hud._refresh()
	if not _hud._shield_bar.visible:
		fail("有护盾时灰色层应可见")
	if not is_equal_approx(_hud._shield_bar.value, 30.0):
		fail("灰色层 value 应为 30: %s" % str(_hud._shield_bar.value))
	if not is_equal_approx(_hud._shield_bar.max_value, 120.0):
		fail("灰色层 max_value 应为 120: %s" % str(_hud._shield_bar.max_value))
	var label_text := str(_hud._hp_label.text)
	if label_text != "100/120（护盾 30）":
		fail("有护盾文本应为 '100/120（护盾 30）': " + label_text)
	if not label_text.contains("护盾"):
		fail("有护盾时文本应含'护盾': " + label_text)
	if not label_text.contains("30"):
		fail("有护盾时文本应含护盾数值: " + label_text)
	# 护盾归零 -> 灰色层隐藏 + 文本回退
	ds._shield = 0.0
	_hud._refresh()
	if _hud._shield_bar.visible:
		fail("护盾归零后灰色层应隐藏")
	if str(_hud._hp_label.text).contains("护盾"):
		fail("护盾归零后文本不应含'护盾': " + _hud._hp_label.text)
