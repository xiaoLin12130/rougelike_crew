extends CanvasLayer
## 暂停菜单（竖版 360x640）：面板 240x220 居中（<=340 宽），
## 继续按钮置顶，按钮 44 高（触控最小），返回主菜单前自动存档。
const UiLayout := preload("res://scripts/ui/ui_layout.gd")

func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.06, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var panel := PanelContainer.new()
	UiLayout.center_panel(panel, 260.0, 300.0)
	panel.custom_minimum_size = Vector2(260, 300)
	panel.add_theme_stylebox_override("panel", UiTheme.style(UiTheme.PANEL, UiTheme.BORDER, 3, 6))
	root.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)
	var title := UiTheme.label("暂停", 20, UiTheme.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	# 视角缩放设置：滑块实时调整（摄影机高度/远近），自动持久化
	var zoom_row := HBoxContainer.new()
	zoom_row.add_theme_constant_override("separation", 6)
	zoom_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(zoom_row)
	var zoom_label := UiTheme.label("视角", 12, UiTheme.WHITE)
	zoom_row.add_child(zoom_label)
	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(110, 28)
	slider.min_value = 0.7
	slider.max_value = 1.8
	slider.step = 0.05
	var is_portrait_mode: bool = UiLayout.is_portrait()
	slider.value = Settings.current_zoom(is_portrait_mode) if Settings != null else (1.3 if is_portrait_mode else 1.8)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(func(v: float) -> void:
		if Settings != null:
			Settings.set_camera_zoom(v, is_portrait_mode))
	zoom_row.add_child(slider)
	var zoom_val := UiTheme.label("%.2fx" % slider.value, 12, UiTheme.GOLD)
	slider.value_changed.connect(func(v: float) -> void:
		zoom_val.text = "%.2fx" % v)
	zoom_row.add_child(zoom_val)
	var resume := UiTheme.button("继续", Vector2(180, UiLayout.touch_min()))
	resume.pressed.connect(_resume)
	vbox.add_child(resume)
	var menu := UiTheme.button("返回主菜单", Vector2(180, UiLayout.touch_min()))
	menu.pressed.connect(_back)
	vbox.add_child(menu)

func _resume() -> void:
	get_tree().paused = false
	hide()

func _back() -> void:
	SaveStore.save_run(GameState.run)  # 返回主菜单前保存进度
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
