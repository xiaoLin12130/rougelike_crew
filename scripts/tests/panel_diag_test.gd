extends SceneTree
## 构筑面板/HUD 布局诊断（竖版 360x640）：找出越界/超大节点与重叠区域
## Run: godot --headless --path . -s res://scripts/tests/panel_diag_test.gd

var _frame := 0
var _phase := 0
var _hud: CanvasLayer
var _panel: CanvasLayer

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 4:
		return false
	match _phase:
		0:
			root.size = Vector2i(360, 640)
			_setup_run()
			_hud = load("res://scenes/ui/hud.tscn").instantiate()
			_hud.name = "HUD"
			root.add_child(_hud)
			_panel = load("res://scenes/ui/build_panel.tscn").instantiate()
			_panel.name = "BuildPanel"
			root.add_child(_panel)  # 先入树（_ready 构建成员），再 refresh
			_panel.refresh()
			_panel.show()
			_phase = 1
		1:
			_dump_tree(_panel, "")
			_dump_tree(_hud, "")
			_check_overlap()
			print("[DIAG] DONE")
			quit(0)
			return true
	return false

func _setup_run() -> void:
	var gs := root.get_node("GameState")
	gs.new_run()
	gs.run.items = {
		"attack_speed_potion": 2,
		"strength_badge": 3,
		"lucky_clover": 1,
		"crit_glasses": 2,
		"vampire_fang": 1,
	}
	gs.run.grid = [
		{"core": "fireball", "shell": ""},
		{"core": "whirl_blade", "shell": "rapid"},
		{"core": "lightning", "shell": "homing"},
	]

func _dump_tree(node: Node, indent: String) -> void:
	var name := node.name
	var extra := ""
	if node is Control:
		var c := node as Control
		var r := c.get_global_rect()
		extra = " rect=(%.0f,%.0f %.0fx%.0f)" % [r.position.x, r.position.y, r.size.x, r.size.y]
		if r.size.x > 340.0 or r.size.y > 560.0:
			print("[BIG]%s %s%s" % [indent, name, extra])
		if r.position.x < -2.0 or r.position.y < -2.0 or r.end.x > 362.0 or r.end.y > 642.0:
			print("[OUT]%s %s%s" % [indent, name, extra])
	print("[NODE]%s %s%s" % [indent, name, extra])
	for ch in node.get_children():
		_dump_tree(ch, indent + "  ")

func _check_overlap() -> void:
	var found := _panel.find_children("*", "PanelContainer", true, false)
	var panel_rect: Rect2 = (found[0] as Control).get_global_rect() if not found.is_empty() else Rect2()
	# HUD 中可能与面板重叠的关键元素
	for path in ["_wave_label", "_boss_root"]:
		if _hud.get(path) != null:
			var r := (_hud.get(path) as Control).get_global_rect()
			if r.intersects(panel_rect):
				print("[OVERLAP] HUD.%s 与构筑面板重叠" % path)
