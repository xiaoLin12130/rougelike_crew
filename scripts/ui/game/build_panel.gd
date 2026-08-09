extends CanvasLayer
## 构筑面板：背包（图标+层数）/ 饰品 / 法术网格（点击交换）/ 技能记忆

var _items_box: VBoxContainer
var _trinkets_box: HBoxContainer
var _grid_box: HBoxContainer
var _skill_label: Label
var _sel_slot := -1

func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.06, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-270, -170)
	panel.custom_minimum_size = Vector2(540, 340)
	panel.add_theme_stylebox_override("panel", UiTheme.style(UiTheme.PANEL, UiTheme.BORDER, 3, 6))
	root.add_child(panel)
	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 6)
	panel.add_child(main)
	_title(main, "构筑面板　·　顺序 = 施放顺序")
	_title(main, "─ 道具背包 ─", 11, Color("#9d8fc4"))
	_items_box = VBoxContainer.new()
	main.add_child(_items_box)
	_title(main, "─ 饰品槽 ─", 11, Color("#9d8fc4"))
	_trinkets_box = HBoxContainer.new()
	_trinkets_box.add_theme_constant_override("separation", 10)
	main.add_child(_trinkets_box)
	_title(main, "─ 法术网格（点击两个格子交换顺序）─", 11, Color("#9d8fc4"))
	_grid_box = HBoxContainer.new()
	_grid_box.add_theme_constant_override("separation", 8)
	main.add_child(_grid_box)
	_skill_label = UiTheme.label("", 11)
	main.add_child(_skill_label)
	var close := UiTheme.button("关闭 (Esc)", Vector2(120, 32))
	close.pressed.connect(hide)
	main.add_child(close)

func _title(parent: Node, text: String, size: int = 15, color: Color = UiTheme.GOLD) -> void:
	var l := UiTheme.label(text, size, color)
	parent.add_child(l)

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		hide()
		get_viewport().set_input_as_handled()

func refresh() -> void:
	_refresh_items()
	_refresh_trinkets()
	_refresh_grid()
	_skill_label.text = "技能：%s　记忆：%s" % [
		str(GameState.run.get("skill", "—")),
		str(GameState.run.get("memory", "—")),
	]

func _item_row(parent: Node, def: Dictionary, count: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	var tex := TextureRect.new()
	tex.texture = UiTheme.icon_texture(str(def.get("icon", "")))
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE  # 关键：忽略 SVG 原生 512x512 尺寸
	tex.custom_minimum_size = Vector2(18, 18)
	tex.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	row.add_child(tex)
	var l := UiTheme.label("%s ×%d　%s" % [
		def.get("name", "?"), count, def.get("description", "")], 11,
		UiTheme.RARITY.get(def.get("rarity", "common"), UiTheme.WHITE))
	row.add_child(l)

func _refresh_items() -> void:
	for c in _items_box.get_children():
		c.queue_free()
	var items: Dictionary = GameState.run.get("items", {})
	if items.is_empty():
		_items_box.add_child(UiTheme.label("（还没有道具）", 11, Color("#5a5278")))
		return
	for item_id in items:
		_item_row(_items_box, GameState.item_def(item_id), items[item_id])

func _refresh_trinkets() -> void:
	for c in _trinkets_box.get_children():
		c.queue_free()
	var slots: int = GameState.tables.get("balance", {}).get("trinket_slots", 3)
	var trinkets: Array = GameState.run.get("trinkets", [])
	for i in slots:
		if i < trinkets.size():
			var def: Dictionary = GameState.item_def(str(trinkets[i]))
			var slot := PanelContainer.new()
			slot.custom_minimum_size = Vector2(120, 26)
			slot.add_theme_stylebox_override("panel", UiTheme.style(Color("#181226"), UiTheme.BORDER_DIM, 1, 3))
			var l := UiTheme.label(def.get("name", trinkets[i]), 10, UiTheme.RARITY.get(def.get("rarity", "common"), UiTheme.WHITE))
			slot.add_child(l)
			_trinkets_box.add_child(slot)
		else:
			var empty := PanelContainer.new()
			empty.custom_minimum_size = Vector2(120, 26)
			empty.add_theme_stylebox_override("panel", UiTheme.style(Color("#14111f"), Color("#3a3260"), 1, 3))
			var l2 := UiTheme.label("[空]", 10, Color("#5a5278"))
			empty.add_child(l2)
			_trinkets_box.add_child(empty)

func _refresh_grid() -> void:
	for c in _grid_box.get_children():
		c.queue_free()
	var grid: Array = GameState.run.get("grid", [])
	var slots: int = GameState.tables.get("balance", {}).get("max_grid_slots", 5)
	for i in slots:
		var b := Button.new()
		b.custom_minimum_size = Vector2(96, 34)
		b.add_theme_stylebox_override("normal", UiTheme.style(Color("#181226"), UiTheme.BORDER_DIM, 2, 4))
		b.add_theme_stylebox_override("hover", UiTheme.style(Color("#221a38"), UiTheme.BORDER, 2, 4))
		b.add_theme_stylebox_override("pressed", UiTheme.style(Color("#191527"), UiTheme.GOLD, 2, 4))
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.add_theme_font_override("font", UiTheme.font_cn())
		b.add_theme_font_size_override("font_size", 10)
		b.add_theme_color_override("font_color", UiTheme.GOLD)
		if i < grid.size():
			b.text = "%d.%s%s" % [i + 1, _core_name(str(grid[i].get("core", ""))), _shell_name(str(grid[i].get("shell", "")))]
		else:
			b.text = "%d.空" % (i + 1)
		b.pressed.connect(_on_slot_clicked.bind(i))
		_grid_box.add_child(b)

func _core_name(id: String) -> String:
	for c in GameState.tables.get("spells", {}).get("cores", []):
		if str(c.get("id", "")) == id:
			return str(c.get("name", id))
	return id

func _shell_name(id: String) -> String:
	if id.is_empty():
		return ""
	for s in GameState.tables.get("spells", {}).get("shells", []):
		if str(s.get("id", "")) == id:
			return "+" + str(s.get("name", id))
	return "+" + id

func _on_slot_clicked(i: int) -> void:
	if _sel_slot < 0:
		_sel_slot = i
		return
	if _sel_slot != i:
		GameState.swap_grid(_sel_slot, i)
	_sel_slot = -1
	refresh()
