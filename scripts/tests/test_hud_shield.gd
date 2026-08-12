extends SceneTree
## 护盾显示测试（问题5 + Brotato 化 2026-08-12）：hud.gd 血条灰蓝叠层 + 护盾数值小字
##  - 有护盾（defense_synergy._shield=30，max_hp=120）时：灰色层节点可见、
##    value=30/max=120、血条右端护盾小字 "护盾 30"
##  - 无护盾/归零时：灰色层与护盾小字隐藏、血量文本保持 "100/120"
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
	if _hud._shield_label.visible:
		fail("无护盾时护盾小字应隐藏")


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
	if str(_hud._hp_label.text) != "100/120":
		fail("有护盾时血量文本仍应为紧凑 100/120: " + _hud._hp_label.text)
	if not _hud._shield_label.visible:
		fail("有护盾时护盾小字应可见")
	if str(_hud._shield_label.text) != "护盾 30":
		fail("护盾小字应为 '护盾 30': " + _hud._shield_label.text)
	# 护盾归零 -> 灰色层与护盾小字隐藏 + 文本保持
	ds._shield = 0.0
	_hud._refresh()
	if _hud._shield_bar.visible:
		fail("护盾归零后灰色层应隐藏")
	if _hud._shield_label.visible:
		fail("护盾归零后护盾小字应隐藏")
	if str(_hud._hp_label.text) != "100/120":
		fail("护盾归零后血量文本应为 100/120: " + _hud._hp_label.text)
