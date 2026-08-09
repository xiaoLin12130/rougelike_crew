extends CanvasLayer
## HUD：左上资源 / 左下常驻构筑条 / 右上波次 / 右下 DPS

var _hp_bar: ProgressBar
var _hp_label: Label
var _lv_label: Label
var _xp_bar: ProgressBar
var _gold_label: Label
var _kills_label: Label
var _wave_label: Label
var _dps_label: Label
var _build_bar: HBoxContainer
var _items_box: HBoxContainer
var _grid_box: HBoxContainer
var _items_sig := ""
var _grid_sig := ""
var _boss_bar: ProgressBar
var _boss_name: Label
var _boss_root: HBoxContainer
var _pickup_label: Label

func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	_build_resources(root)
	_build_wave(root)
	_build_pickup_label(root)
	_build_dps(root)
	_build_bar_ui(root)
	_build_boss_bar(root)
	EventBus.player_stats_changed.connect(_refresh)
	EventBus.spell_arranged.connect(func(_g: Array) -> void: _refresh())
	EventBus.wave_state_changed.connect(_on_wave)
	EventBus.item_picked.connect(_on_item_picked)
	EventBus.boss_spawned.connect(_on_boss_spawned)
	EventBus.boss_hp_changed.connect(_on_boss_hp)
	EventBus.boss_died.connect(_on_boss_died)
	var t := Timer.new()
	t.wait_time = 0.5
	t.timeout.connect(_refresh_dps)
	add_child(t)
	t.start()
	_refresh()

func _style_bar(bar: ProgressBar, fill: Color, h: int = 10) -> void:
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(140, h)
	bar.add_theme_stylebox_override("background", UiTheme.style(Color("#0d0a16"), UiTheme.BORDER_DIM, 2, 2))
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("fill", sb)

func _build_resources(root: Control) -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(8, 6)
	box.add_theme_constant_override("separation", 3)
	root.add_child(box)
	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 6)
	box.add_child(hp_row)
	_hp_label = UiTheme.label("100/100", 11, UiTheme.WHITE, true)
	hp_row.add_child(_hp_label)
	_hp_bar = ProgressBar.new()
	_style_bar(_hp_bar, UiTheme.RED)
	hp_row.add_child(_hp_bar)
	_lv_label = UiTheme.label("Lv.1", 10, UiTheme.GOLD, true)
	box.add_child(_lv_label)
	_xp_bar = ProgressBar.new()
	_style_bar(_xp_bar, UiTheme.GOLD, 6)
	box.add_child(_xp_bar)
	_gold_label = UiTheme.label("金币 0", 11, UiTheme.GOLD)
	box.add_child(_gold_label)
	_kills_label = UiTheme.label("击杀 0 · 轮次 1", 9, Color("#9d8fc4"))
	box.add_child(_kills_label)

func _build_wave(root: Control) -> void:
	_wave_label = UiTheme.label("", 13, UiTheme.GOLD)
	_wave_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_wave_label.position = Vector2(-160, 6)
	_wave_label.custom_minimum_size = Vector2(320, 22)
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wave_label.add_theme_stylebox_override("normal", UiTheme.style(Color(0.1, 0.08, 0.16, 0.8), UiTheme.BORDER_DIM, 1, 4))
	_wave_label.visible = false
	root.add_child(_wave_label)

func _build_pickup_label(root: Control) -> void:
	_pickup_label = UiTheme.label("", 13, UiTheme.GOLD)
	_pickup_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_pickup_label.position = Vector2(-180, -90)
	_pickup_label.custom_minimum_size = Vector2(360, 24)
	_pickup_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pickup_label.visible = false
	root.add_child(_pickup_label)

func _build_dps(root: Control) -> void:
	_dps_label = UiTheme.label("DPS 0", 11, Color("#9d8fc4"), true)
	_dps_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_dps_label.position = Vector2(-140, -26)
	_dps_label.custom_minimum_size = Vector2(130, 16)
	_dps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(_dps_label)

func _build_boss_bar(root: Control) -> void:
	_boss_root = HBoxContainer.new()
	_boss_root.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_boss_root.position = Vector2(-190, 30)
	_boss_root.add_theme_constant_override("separation", 10)
	_boss_root.visible = false
	root.add_child(_boss_root)
	_boss_name = UiTheme.label("", 13, UiTheme.RED)
	_boss_root.add_child(_boss_name)
	_boss_bar = ProgressBar.new()
	_boss_bar.show_percentage = false
	_boss_bar.custom_minimum_size = Vector2(320, 14)
	_boss_bar.add_theme_stylebox_override("background", UiTheme.style(Color("#120a14"), Color("#5a2a44"), 2, 3))
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(1.0, 0.32, 0.28)
	fill.set_corner_radius_all(3)
	_boss_bar.add_theme_stylebox_override("fill", fill)
	_boss_root.add_child(_boss_bar)

func _on_boss_spawned(boss_name: String, max_hp: int) -> void:
	_boss_name.text = boss_name
	_boss_bar.max_value = max_hp
	_boss_bar.value = max_hp
	_boss_root.visible = true

func _on_boss_hp(hp: int, max_hp: int) -> void:
	_boss_bar.max_value = max_hp
	_boss_bar.value = hp

func _on_boss_died() -> void:
	_boss_root.visible = false

func _build_bar_ui(root: Control) -> void:
	_build_bar = HBoxContainer.new()
	_build_bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_build_bar.position = Vector2(8, -30)
	_build_bar.add_theme_constant_override("separation", 6)
	root.add_child(_build_bar)
	_grid_box = HBoxContainer.new()
	_grid_box.add_theme_constant_override("separation", 3)
	_build_bar.add_child(_grid_box)
	var sep := UiTheme.label("|", 16, UiTheme.BORDER_DIM)
	_build_bar.add_child(sep)
	_items_box = HBoxContainer.new()
	_items_box.add_theme_constant_override("separation", 3)
	_build_bar.add_child(_items_box)
	var btn := UiTheme.button("构筑", Vector2(64, 30))
	btn.pressed.connect(_toggle_build)
	_build_bar.add_child(btn)
	var pause_btn := UiTheme.button("暂停", Vector2(56, 30))
	pause_btn.pressed.connect(_toggle_pause)
	_build_bar.add_child(pause_btn)

func _on_item_picked(item_id: String, stacks: int) -> void:
	# 获得提示：选择/拾取强化时屏幕中下方飘出
	var def: Dictionary = GameState.item_def(item_id)
	_pickup_label.text = "获得 %s ×%d" % [def.get("name", item_id), stacks]
	_pickup_label.visible = true
	_pickup_label.modulate = Color.WHITE
	var tw := create_tween()
	tw.tween_interval(1.8)
	tw.tween_property(_pickup_label, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func(): _pickup_label.visible = false)

func _toggle_build() -> void:
	var panel := get_tree().current_scene.get_node_or_null("BuildPanel") as CanvasLayer
	if panel:
		panel.visible = not panel.visible
		if panel.visible and panel.has_method("refresh"):
			panel.refresh()

func _toggle_pause() -> void:
	var root := get_tree().current_scene
	if root and root.has_method("_toggle_pause"):
		root._toggle_pause()

func _on_wave(state: String) -> void:
	_wave_label.text = state
	_wave_label.visible = true
	_wave_label.modulate = Color.WHITE
	var tw := create_tween()
	tw.tween_interval(2.2)
	tw.tween_property(_wave_label, "modulate:a", 0.0, 0.6)
	tw.tween_callback(func(): _wave_label.visible = false)

func _refresh() -> void:
	if GameState.run.is_empty():
		return
	var hp: int = GameState.run.get("hp", 0)
	var max_hp: int = GameState.run.get("max_hp", 100)
	_hp_label.text = "%d/%d" % [hp, max_hp]
	_hp_bar.max_value = max_hp
	_hp_bar.value = hp
	var lv: int = GameState.run.get("player_level", 1)
	_lv_label.text = "Lv.%d" % lv
	var need: int = GameState.xp_to_next(lv)
	_xp_bar.max_value = need
	_xp_bar.value = GameState.run.get("xp", 0)
	_gold_label.text = "金币 %d" % GameState.run.get("gold", 0)
	_kills_label.text = "击杀 %d · 轮次 %d · 第%d关" % [
		GameState.run.get("kills", 0), GameState.run.get("loop", 1), GameState.run.get("level", 1)]
	_refresh_build_bar()

func _refresh_build_bar() -> void:
	var items: Dictionary = GameState.run.get("items", {})
	var sig := ""
	for k in items.keys():
		sig += str(k) + ":" + str(items[k]) + ";"
	if sig != _items_sig:
		_items_sig = sig
		_rebuild_items(items)
	var grid: Array = GameState.run.get("grid", [])
	var gsig := ""
	for slot in grid:
		gsig += str(slot.get("core", "")) + "+" + str(slot.get("shell", "")) + ";"
	if gsig != _grid_sig:
		_grid_sig = gsig
		_rebuild_grid(grid)

func _rebuild_grid(grid: Array) -> void:
	for c in _grid_box.get_children():
		c.queue_free()
	var slots: int = GameState.tables.get("balance", {}).get("max_grid_slots", 5)
	for i in slots:
		var b := Button.new()
		b.custom_minimum_size = Vector2(30, 30)
		b.add_theme_stylebox_override("normal", UiTheme.style(Color("#181226"), UiTheme.BORDER_DIM, 2, 3))
		b.add_theme_stylebox_override("hover", UiTheme.style(Color("#221a38"), UiTheme.BORDER, 2, 3))
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.tooltip_text = "法术格 %d（空）" % (i + 1)
		if i < grid.size():
			var core_id: String = str(grid[i].get("core", ""))
			var shell_id: String = str(grid[i].get("shell", ""))
			var icon := _core_icon(core_id)
			if icon:
				b.icon = icon
				b.expand_icon = true
			b.text = _shell_short(shell_id)
			b.add_theme_font_override("font", UiTheme.font_cn())
			b.add_theme_font_size_override("font_size", 8)
			b.add_theme_color_override("font_color", UiTheme.GOLD)
			b.tooltip_text = "%d.%s %s" % [i + 1, _core_name(core_id), _shell_name(shell_id)]
		_grid_box.add_child(b)

func _rebuild_items(items: Dictionary) -> void:
	for c in _items_box.get_children():
		c.queue_free()
	var ids := items.keys()
	if ids.is_empty():
		var empty := UiTheme.label("（无道具）", 9, Color("#5a5278"))
		_items_box.add_child(empty)
		return
	for i in mini(ids.size(), 10):
		var item_id: String = str(ids[i])
		var def: Dictionary = GameState.item_def(item_id)
		if def.is_empty():
			continue
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(56, 32)
		var is_new: bool = str(GameState.run.get("last_picked", "")) == item_id
		var border := UiTheme.GOLD if is_new else UiTheme.BORDER_DIM
		slot.add_theme_stylebox_override("panel", UiTheme.style(Color("#221a38"), border, 2 if is_new else 1, 3))
		slot.tooltip_text = "%s ×%d\n%s" % [def.get("name", item_id), items[item_id], def.get("description", "")]
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 2)
		slot.add_child(hb)
		var tex := TextureRect.new()
		tex.texture = UiTheme.icon_texture(str(def.get("icon", "")))
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.custom_minimum_size = Vector2(16, 16)
		tex.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		hb.add_child(tex)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 0)
		hb.add_child(vb)
		var name_l := UiTheme.label(_short_name(str(def.get("name", item_id))), 8, Color("#d8d0ec"))
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(name_l)
		var cnt := UiTheme.label("×%d" % items[item_id], 10, UiTheme.GOLD if is_new else UiTheme.WHITE, true)
		cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(cnt)
		_items_box.add_child(slot)
	if ids.size() > 10:
		var more := UiTheme.label("+%d" % (ids.size() - 10), 9, UiTheme.GOLD, true)
		_items_box.add_child(more)

func _core_icon(core_id: String) -> Texture2D:
	for c in GameState.tables.get("spells", {}).get("cores", []):
		if str(c.get("id", "")) == core_id:
			return UiTheme.icon_texture(str(c.get("icon", "")))
	return null

func _core_name(core_id: String) -> String:
	for c in GameState.tables.get("spells", {}).get("cores", []):
		if str(c.get("id", "")) == core_id:
			return str(c.get("name", core_id))
	return core_id

func _shell_name(shell_id: String) -> String:
	if shell_id.is_empty():
		return ""
	for s in GameState.tables.get("spells", {}).get("shells", []):
		if str(s.get("id", "")) == shell_id:
			return str(s.get("name", shell_id))
	return shell_id

func _shell_short(shell_id: String) -> String:
	match shell_id:
		"rapid":
			return "连"
		"spread":
			return "散"
		"homing":
			return "追"
		"pierce":
			return "穿"
		"bounce":
			return "弹"
		"orbit":
			return "绕"
		"burst":
			return "爆"
		"delay":
			return "延"
		_:
			return ""

func _refresh_dps() -> void:
	if GameState.run.is_empty():
		return
	_dps_label.text = "DPS %d" % int(GameState.estimate_dps())

func _short_name(name: String) -> String:
	if name.length() <= 3:
		return name
	return name.substr(0, 3)
