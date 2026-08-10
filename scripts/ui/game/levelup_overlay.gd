extends CanvasLayer
## 升级三选一（竖版 360x640）：3 张卡片纵向堆叠（VBox），
## 卡片 300x110（图标+名称+描述横排），3x110+标题+间距≈400 < 640，不超屏。
## 触控：整卡可点（透明 Button 全卡叠层），按压有高亮反馈；
## 悬停高亮仅桌面附加（触屏无 hover，不依赖）。
const UiLayout := preload("res://scripts/ui/ui_layout.gd")

signal choice_made(item_id: String)

var _box: VBoxContainer
var current_choices: Array = []

func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.06, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.position = Vector2(-(UiLayout.panel_w() + 20.0) / 2.0, -205)  # 卡片含左右边距共 340 宽，对称居中
	vbox.custom_minimum_size = Vector2(UiLayout.panel_w() + 20.0, 0.0)
	vbox.add_theme_constant_override("separation", 12)
	root.add_child(vbox)
	var title := UiTheme.label("升级！选择一项强化", 20, UiTheme.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 12)
	vbox.add_child(_box)

func show_choices(choices: Array) -> void:
	current_choices = choices
	for c in _box.get_children():
		c.queue_free()
	for item in choices:
		var rarity: String = item.get("rarity", "common")
		var border: Color = UiTheme.RARITY.get(rarity, UiTheme.BORDER)
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(UiLayout.panel_w(), 110)
		card.add_theme_stylebox_override("panel", UiTheme.style(Color("#1b1430"), border, 3, 6))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.size_flags_vertical = Control.SIZE_EXPAND_FILL
		card.add_child(row)
		var tex := TextureRect.new()
		tex.texture = UiTheme.icon_texture(str(item.get("icon", "")))
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.custom_minimum_size = Vector2(56, 56)
		tex.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(tex)
		var info := VBoxContainer.new()
		info.add_theme_constant_override("separation", 4)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(info)
		var name_l := UiTheme.label(str(item.get("name", "")), 14, UiTheme.RARITY.get(rarity, UiTheme.WHITE))
		name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_l.custom_minimum_size = Vector2(0, 20)
		info.add_child(name_l)
		var desc := UiTheme.label(str(item.get("description", "")), 10, Color("#c8c0e0"))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(0, 46)  # 描述区固定高度 → 卡片文字高度一致
		desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		desc.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		info.add_child(desc)
		var click := Button.new()
		click.flat = true
		click.set_anchors_preset(Control.PRESET_FULL_RECT)
		click.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		click.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		click.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
		click.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		click.pressed.connect(_on_choice.bind(str(item.get("id", ""))))
		# 桌面悬停高亮（触屏无 hover，不依赖；按压反馈走 button_down/up）
		click.mouse_entered.connect(func():
			card.add_theme_stylebox_override("panel", UiTheme.style(Color("#241a3e"), border, 3, 6)))
		click.mouse_exited.connect(func():
			card.add_theme_stylebox_override("panel", UiTheme.style(Color("#1b1430"), border, 3, 6)))
		click.button_down.connect(func():
			card.add_theme_stylebox_override("panel", UiTheme.style(Color("#2c2150"), border, 3, 6)))
		click.button_up.connect(func():
			card.add_theme_stylebox_override("panel", UiTheme.style(Color("#1b1430"), border, 3, 6)))
		card.add_child(click)
		_box.add_child(card)

func _on_choice(item_id: String) -> void:
	choice_made.emit(item_id)
