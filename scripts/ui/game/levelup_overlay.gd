extends CanvasLayer
## 升级三选一：像素风大卡片（图标+名称+稀有度边框+描述）

signal choice_made(item_id: String)

var _box: HBoxContainer
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
	vbox.position = Vector2(-250, -100)
	root.add_child(vbox)
	var title := UiTheme.label("升级！选择一项强化", 24, UiTheme.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	_box = HBoxContainer.new()
	_box.add_theme_constant_override("separation", 18)
	vbox.add_child(_box)

func show_choices(choices: Array) -> void:
	current_choices = choices
	for c in _box.get_children():
		c.queue_free()
	for item in choices:
		var rarity: String = item.get("rarity", "common")
		var border: Color = UiTheme.RARITY.get(rarity, UiTheme.BORDER)
		# 社区标准做法：PanelContainer 承载内容 + 透明 Button 叠层点击，
		# 避免 Button 内容区对复杂子布局的干扰
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(165, 145)
		card.add_theme_stylebox_override("panel", UiTheme.style(Color("#1b1430"), border, 3, 6))
		var vb := VBoxContainer.new()
		vb.alignment = BoxContainer.ALIGNMENT_END  # 内容贴底：图标顶部居中，文字区高度一致
		vb.add_theme_constant_override("separation", 5)
		card.add_child(vb)
		var tex := TextureRect.new()
		tex.texture = UiTheme.icon_texture(str(item.get("icon", "")))
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.custom_minimum_size = Vector2(34, 34)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vb.add_child(tex)
		var name_l := UiTheme.label(str(item.get("name", "")), 13, UiTheme.RARITY.get(rarity, UiTheme.WHITE))
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_l.custom_minimum_size = Vector2(0, 20)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vb.add_child(name_l)
		var desc := UiTheme.label(str(item.get("description", "")), 10, Color("#c8c0e0"))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc.custom_minimum_size = Vector2(0, 34)  # 描述区固定高度 → 三张卡片文字高度一致
		desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		desc.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		vb.add_child(desc)
		var click := Button.new()
		click.flat = true
		click.set_anchors_preset(Control.PRESET_FULL_RECT)
		click.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		click.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		click.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
		click.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		click.pressed.connect(_on_choice.bind(str(item.get("id", ""))))
		click.mouse_entered.connect(func():
			card.add_theme_stylebox_override("panel", UiTheme.style(Color("#241a3e"), border, 3, 6)))
		click.mouse_exited.connect(func():
			card.add_theme_stylebox_override("panel", UiTheme.style(Color("#1b1430"), border, 3, 6)))
		card.add_child(click)
		_box.add_child(card)

func _on_choice(item_id: String) -> void:
	choice_made.emit(item_id)
