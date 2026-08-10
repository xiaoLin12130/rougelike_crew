extends CanvasLayer
## 法术栏替换界面（竖版 360x640）：面板 320x540（<=340 宽），
## 卡片纵向堆叠（新法术卡 + 现有格子卡，卡 296x62，整卡可点），
## 超出面板高度由 ScrollContainer 兜底；放弃按钮 44 高。
## 触屏：整卡 Button 点击替换/放弃，不依赖 hover。
const UiLayout := preload("res://scripts/ui/ui_layout.gd")

signal choose_made(idx: int)  # -1 = 放弃

var _box: VBoxContainer

func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.015, 0.04, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var panel := PanelContainer.new()
	UiLayout.center_panel(panel, UiLayout.panel_w(), UiLayout.panel_h() + 20.0)
	panel.custom_minimum_size = Vector2(UiLayout.panel_w(), UiLayout.panel_h() + 20.0)
	panel.add_theme_stylebox_override("panel", UiTheme.style(Color(0.07, 0.05, 0.11, 0.92), UiTheme.GOLD, 2, 8))
	root.add_child(panel)
	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 10)
	panel.add_child(main)
	var title := UiTheme.label("法术栏已满 —— 选择要替换的法术", 15, UiTheme.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(scroll)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_box)
	var skip := UiTheme.button("放弃新法术", Vector2(UiLayout.panel_w(), UiLayout.touch_min()))
	skip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	skip.pressed.connect(_on_skip)
	main.add_child(skip)
	hide()

func show_replace(core_id: String, shell_id: String, grid: Array) -> void:
	for c in _box.get_children():
		c.queue_free()
	# 新法术卡片（高亮）
	var new_card := _spell_card(core_id, shell_id, true, -1)
	_box.add_child(new_card)
	# 现有格子（点击替换）
	for i in grid.size():
		var card := _spell_card(str(grid[i].get("core", "")), str(grid[i].get("shell", "")), false, i)
		_box.add_child(card)
	show()

func _spell_card(core_id: String, shell_id: String, is_new: bool, idx: int) -> Control:
	var core: Dictionary = _find_core(core_id)
	var shell: Dictionary = _find_shell(shell_id)
	var card := Button.new()
	UiTheme.apply_font(card, 11)
	card.custom_minimum_size = Vector2(296, 62)
	card.tooltip_text = "%s%s" % [
		core.get("name", core_id),
		" + " + str(shell.get("name", "")) if not shell.is_empty() else "",
	]
	var border: Color = UiTheme.GOLD if is_new else UiTheme.BORDER_DIM
	card.add_theme_stylebox_override("normal", UiTheme.style(Color(0.12, 0.09, 0.19, 0.9), border, 2, 4))
	card.add_theme_stylebox_override("hover", UiTheme.style(Color(0.16, 0.12, 0.26, 0.95), UiTheme.BORDER, 2, 4))
	card.add_theme_stylebox_override("pressed", UiTheme.style(Color(0.10, 0.08, 0.17, 0.95), UiTheme.GOLD, 2, 4))
	card.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	card.text = ""
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	var tex := TextureRect.new()
	tex.texture = UiTheme.icon_texture(str(core.get("icon", "")))
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.custom_minimum_size = Vector2(40, 40)
	tex.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(tex)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(info)
	var name_l := UiTheme.label(str(core.get("name", "?")), 13, UiTheme.GOLD if is_new else UiTheme.WHITE)
	info.add_child(name_l)
	if not shell.is_empty():
		var sh_l := UiTheme.label("+" + str(shell.get("name", "")), 9, Color("#9d8fc4"))
		info.add_child(sh_l)
	var tag := UiTheme.label("新法术" if is_new else "点击替换", 9, UiTheme.GOLD if is_new else Color("#5a5278"))
	info.add_child(tag)
	if idx >= 0:
		card.pressed.connect(_on_choose.bind(idx))
	return card

func _find_core(id: String) -> Dictionary:
	for c in GameState.tables.get("spells", {}).get("cores", []):
		if str(c.get("id", "")) == id:
			return c
	return {}

func _find_shell(id: String) -> Dictionary:
	if id.is_empty():
		return {}
	for s in GameState.tables.get("spells", {}).get("shells", []):
		if str(s.get("id", "")) == id:
			return s
	return {}

func _on_choose(idx: int) -> void:
	hide()
	choose_made.emit(idx)

func _on_skip() -> void:
	hide()
	choose_made.emit(-1)

func choose_first() -> void:
	## 自动脚本：替换第一个格子
	hide()
	choose_made.emit(0)

func choose_skip() -> void:
	hide()
	choose_made.emit(-1)
