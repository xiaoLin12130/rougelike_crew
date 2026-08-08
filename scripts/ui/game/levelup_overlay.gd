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
	vbox.position = Vector2(-280, -110)
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
		var card := Button.new()
		card.custom_minimum_size = Vector2(180, 150)
		card.add_theme_stylebox_override("normal", UiTheme.style(Color("#1b1430"), border, 3, 6))
		card.add_theme_stylebox_override("hover", UiTheme.style(Color("#241a3e"), border, 3, 6))
		card.add_theme_stylebox_override("pressed", UiTheme.style(Color("#191527"), UiTheme.GOLD, 3, 6))
		card.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		var vb := VBoxContainer.new()
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		card.add_child(vb)
		var tex := TextureRect.new()
		tex.texture = UiTheme.icon_texture(str(item.get("icon", "")))
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.custom_minimum_size = Vector2(40, 40)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		vb.add_child(tex)
		var name_l := UiTheme.label(str(item.get("name", "")), 14, UiTheme.RARITY.get(rarity, UiTheme.WHITE))
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(name_l)
		var desc := UiTheme.label(str(item.get("description", "")), 10, Color("#c8c0e0"))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(desc)
		card.pressed.connect(_on_choice.bind(str(item.get("id", ""))))
		_box.add_child(card)

func _on_choice(item_id: String) -> void:
	choice_made.emit(item_id)
