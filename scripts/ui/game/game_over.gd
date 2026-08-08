extends CanvasLayer
## 结算界面：胜利/失败 + 统计卡片

var _title: Label
var _stats: Label

func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.05, 0.85)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-240, -120)
	panel.custom_minimum_size = Vector2(480, 240)
	panel.add_theme_stylebox_override("panel", UiTheme.style(UiTheme.PANEL, UiTheme.BORDER, 3, 6))
	root.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)
	_title = UiTheme.label("", 30, UiTheme.GOLD)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_title)
	_stats = UiTheme.label("", 13, Color("#c8c0e0"))
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_stats)
	var btn := UiTheme.button("返回主菜单", Vector2(160, 40))
	btn.pressed.connect(_back)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(btn)

func show_result(victory: bool, stats: Dictionary) -> void:
	_title.text = "古神陨落！" if victory else "你倒下了…"
	_title.add_theme_color_override("font_color", UiTheme.GOLD if victory else UiTheme.RED)
	_stats.text = "击杀 %d　用时 %.0f 秒　轮次 %d　Lv.%d\n金币 %d　道具种类 %d　DPS %d" % [
		stats.get("kills", 0), stats.get("time", 0.0), stats.get("loop", 1),
		stats.get("player_level", 1), stats.get("gold", 0), stats.get("items", {}).size(),
		int(stats.get("dps_estimate", 0.0)),
	]

func _back() -> void:
	get_tree().paused = false
	GameState.new_run()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
