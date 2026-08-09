extends CanvasLayer
## 暂停菜单

func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.06, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-120, -90)
	panel.custom_minimum_size = Vector2(240, 180)
	panel.add_theme_stylebox_override("panel", UiTheme.style(UiTheme.PANEL, UiTheme.BORDER, 3, 6))
	root.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)
	var title := UiTheme.label("暂停", 22, UiTheme.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	var resume := UiTheme.button("继续", Vector2(160, 38))
	resume.pressed.connect(_resume)
	vbox.add_child(resume)
	var menu := UiTheme.button("返回主菜单", Vector2(160, 38))
	menu.pressed.connect(_back)
	vbox.add_child(menu)

func _resume() -> void:
	get_tree().paused = false
	hide()

func _back() -> void:
	SaveStore.save_run(GameState.run)  # 返回主菜单前保存进度
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
