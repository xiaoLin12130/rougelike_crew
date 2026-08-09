extends CanvasLayer
## HUD v2（UI 重设计，2026-08-09）
## 依据 docs/design/ui-design.md + ui-rag 结论：
##  - 物品栏格子：图标 + 名称 + 层数，稀有度描边，点击查看详情；
##  - 获得反馈：浮动提示 + 新物品高亮脉冲；
##  - 构筑条：贴左下边缘、半透明、可折叠（不遮挡战斗区）；
##  - Boss 血条：顶部居中，与右上波次横幅/左上资源互不重叠；
##  - 触屏按钮尺寸 >= 44px（逻辑 22px，2x 窗口即 44px）。

const MAX_ITEMS_SHOWN := 6
const MAX_GRID_SHOWN := 5

var _hp_bar: ProgressBar
var _hp_label: Label
var _lv_label: Label
var _xp_bar: ProgressBar
var _gold_label: Label
var _kills_label: Label
var _res_box: VBoxContainer
var _wave_label: Label
var _dps_label: Label
var _bar_root: PanelContainer
var _bar_box: HBoxContainer
var _items_box: HBoxContainer
var _grid_box: HBoxContainer
var _tab_btn: Button
var _bar_open := true
var _items_sig := ""
var _grid_sig := ""
var _boss_bar: ProgressBar
var _boss_name: Label
var _boss_root: HBoxContainer
var _pickup_label: Label
var _detail_panel: PanelContainer
var _detail_icon: TextureRect
var _detail_title: Label
var _detail_desc: Label
var _detail_dim: Button

func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_resources(root)
	_build_wave(root)
	_build_pickup_label(root)
	_build_dps(root)
	_build_bar_ui(root)
	_build_boss_bar(root)
	_build_detail(root)
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

func _style_bar(bar: ProgressBar, fill_tex: String, h: int = 10) -> void:
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(96, h)
	bar.add_theme_stylebox_override("background", UiTheme.style_compact(Color("#0d0a16"), UiTheme.BORDER_DIM, 2, 2, 2))
	var sb := StyleBoxTexture.new()
	sb.texture = load(fill_tex)
	sb.texture_margin_left = 2
	sb.texture_margin_right = 2
	sb.texture_margin_top = 2
	sb.texture_margin_bottom = 2
	bar.add_theme_stylebox_override("fill", sb)

func _build_resources(root: Control) -> void:
	# 左上：生命/等级经验/金币/击杀·波次·关卡（压缩宽度，避免与顶部中央 Boss 血条重叠）
	_res_box = VBoxContainer.new()
	_res_box.position = Vector2(8, 6)
	_res_box.add_theme_constant_override("separation", 3)
	_res_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_res_box)
	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 6)
	_res_box.add_child(hp_row)
	_hp_label = UiTheme.label("100/100", 10, UiTheme.WHITE, true)
	hp_row.add_child(_hp_label)
	_hp_bar = ProgressBar.new()
	_style_bar(_hp_bar, "res://assets/ui/hpbar_blue.png", 8)
	hp_row.add_child(_hp_bar)
	_lv_label = UiTheme.label("Lv.1", 9, UiTheme.GOLD, true)
	_res_box.add_child(_lv_label)
	_xp_bar = ProgressBar.new()
	_style_bar(_xp_bar, "res://assets/ui/hpbar_yellow.png", 5)
	_res_box.add_child(_xp_bar)
	_gold_label = UiTheme.label("金币 0", 10, UiTheme.GOLD)
	_res_box.add_child(_gold_label)
	_kills_label = UiTheme.label("击杀 0 · 波次 1", 8, Color("#9d8fc4"))
	_res_box.add_child(_kills_label)

func _build_wave(root: Control) -> void:
	# 右上：临时提示（波次），位于 Boss 血条下方，互不遮挡
	_wave_label = UiTheme.label("", 12, UiTheme.GOLD)
	_wave_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_wave_label.position = Vector2(-308, 28)
	_wave_label.custom_minimum_size = Vector2(300, 20)
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_wave_label.add_theme_stylebox_override("normal", UiTheme.style_compact(Color(0.1, 0.08, 0.16, 0.8), UiTheme.BORDER_DIM, 1, 4, 4))
	_wave_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wave_label.visible = false
	root.add_child(_wave_label)

func _build_pickup_label(root: Control) -> void:
	# 屏幕中下方：获得道具反馈（不遮挡构筑条）
	_pickup_label = UiTheme.label("", 12, UiTheme.GOLD)
	_pickup_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_pickup_label.position = Vector2(0, -104)
	_pickup_label.custom_minimum_size = Vector2(300, 22)
	_pickup_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pickup_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pickup_label.visible = false
	root.add_child(_pickup_label)

func _build_dps(root: Control) -> void:
	_dps_label = UiTheme.label("DPS 0", 10, Color("#9d8fc4"), true)
	_dps_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_dps_label.position = Vector2(-140, -56)
	_dps_label.custom_minimum_size = Vector2(130, 16)
	_dps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_dps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_dps_label)

func _build_boss_bar(root: Control) -> void:
	# 顶部居中 Boss 血条（y 4..20），左侧资源条止于 x<170，右侧波次横幅在其下方，互不重叠
	_boss_root = HBoxContainer.new()
	_boss_root.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_boss_root.position = Vector2(-150, 4)
	_boss_root.add_theme_constant_override("separation", 8)
	_boss_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_root.visible = false
	root.add_child(_boss_root)
	_boss_name = UiTheme.label("", 12, UiTheme.RED)
	_boss_root.add_child(_boss_name)
	_boss_bar = ProgressBar.new()
	_boss_bar.show_percentage = false
	_boss_bar.custom_minimum_size = Vector2(220, 12)
	_boss_bar.add_theme_stylebox_override("background", UiTheme.style_compact(Color("#120a14"), Color("#5a2a44"), 2, 3, 2))
	var fill := StyleBoxTexture.new()
	fill.texture = load("res://assets/ui/hpbar_red.png")
	fill.texture_margin_left = 2
	fill.texture_margin_right = 2
	fill.texture_margin_top = 2
	fill.texture_margin_bottom = 2
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
	# 左下角可折叠构筑条：半透明贴边，折叠后仅剩一个小标签
	_tab_btn = UiTheme.button("<<", Vector2(20, 32))
	_tab_btn.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_tab_btn.position = Vector2(4, -50)
	_tab_btn.tooltip_text = "收起构筑条（腾出战斗视野）"
	_tab_btn.pressed.connect(_toggle_bar)
	root.add_child(_tab_btn)
	_bar_root = PanelContainer.new()
	_bar_root.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_bar_root.position = Vector2(27, -50)
	_bar_root.add_theme_stylebox_override("panel", UiTheme.style_compact(Color(0.09, 0.07, 0.15, 0.78), Color(0.30, 0.22, 0.52, 0.9), 1, 4, 4))
	root.add_child(_bar_root)
	_bar_box = HBoxContainer.new()
	_bar_box.add_theme_constant_override("separation", 5)
	_bar_root.add_child(_bar_box)
	_grid_box = HBoxContainer.new()
	_grid_box.add_theme_constant_override("separation", 2)
	_bar_box.add_child(_grid_box)
	var sep := UiTheme.label("|", 16, Color(0.35, 0.28, 0.55, 0.9))
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_box.add_child(sep)
	_items_box = HBoxContainer.new()
	_items_box.add_theme_constant_override("separation", 2)
	_bar_box.add_child(_items_box)
	var build_btn := UiTheme.button("构筑", Vector2(48, 32))
	build_btn.tooltip_text = "打开构筑面板（完整物品/法术/技能）"
	build_btn.pressed.connect(_toggle_build)
	_bar_box.add_child(build_btn)
	var pause_btn := UiTheme.button("暂停", Vector2(48, 32))
	pause_btn.tooltip_text = "暂停游戏（Esc）"
	pause_btn.pressed.connect(_toggle_pause)
	_bar_box.add_child(pause_btn)

func _toggle_bar() -> void:
	_bar_open = not _bar_open
	if _bar_open:
		_bar_root.visible = true
		_tab_btn.text = "<<"
		_tab_btn.tooltip_text = "收起构筑条（腾出战斗视野）"
	else:
		_bar_root.visible = false
		_tab_btn.text = ">>"
		_tab_btn.tooltip_text = "展开构筑条"
	_hide_detail()

func _on_item_picked(item_id: String, stacks: int) -> void:
	# 获得反馈：屏幕中下方浮动提示（另有新物品格子高亮脉冲）
	var def: Dictionary = GameState.item_def(item_id)
	_pickup_label.text = "获得 %s ×%d" % [def.get("name", item_id), stacks]
	_pickup_label.visible = true
	_pickup_label.modulate = Color.WHITE
	var tw := create_tween()
	tw.tween_interval(1.8)
	tw.tween_property(_pickup_label, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func(): _pickup_label.visible = false)

func _toggle_build() -> void:
	_hide_detail()
	var panel := get_tree().current_scene.get_node_or_null("BuildPanel") as CanvasLayer
	if panel:
		panel.visible = not panel.visible
		if panel.visible and panel.has_method("refresh"):
			panel.refresh()
			# 打开构筑面板时收起底部常驻条，避免遮挡
			if _bar_open:
				_toggle_bar()

func _toggle_pause() -> void:
	_hide_detail()
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
	_kills_label.text = "击杀 %d · 波次 %d · 第%d关" % [
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
	for i in mini(slots, MAX_GRID_SHOWN):
		var b := Button.new()
		b.custom_minimum_size = Vector2(22, 32)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_stylebox_override("normal", UiTheme.style_compact(Color(0.12, 0.09, 0.19, 0.9), UiTheme.BORDER_DIM, 1, 2, 2))
		b.add_theme_stylebox_override("hover", UiTheme.style_compact(Color(0.18, 0.13, 0.29, 0.95), UiTheme.BORDER, 1, 2, 2))
		b.add_theme_stylebox_override("pressed", UiTheme.style_compact(Color(0.10, 0.08, 0.17, 0.95), UiTheme.GOLD, 1, 2, 2))
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.tooltip_text = "法术格 %d（点击查看详情）" % (i + 1)
		if i < grid.size():
			var core_id: String = str(grid[i].get("core", ""))
			var shell_id: String = str(grid[i].get("shell", ""))
			var vb := VBoxContainer.new()
			vb.add_theme_constant_override("separation", 0)
			vb.set_anchors_preset(Control.PRESET_FULL_RECT)
			vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(vb)
			var icon := _core_icon(core_id)
			if icon:
				var tr := TextureRect.new()
				tr.texture = icon
				tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tr.custom_minimum_size = Vector2(16, 16)
				tr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
				tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
				vb.add_child(tr)
			var sh := UiTheme.label(_shell_short(shell_id), 7, UiTheme.GOLD, true)
			sh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
			vb.add_child(sh)
			b.pressed.connect(_on_grid_slot_clicked.bind(i))
		_grid_box.add_child(b)

func _rebuild_items(items: Dictionary) -> void:
	for c in _items_box.get_children():
		c.queue_free()
	var ids := items.keys()
	if ids.is_empty():
		var empty := UiTheme.label("（无道具）", 9, Color(0.35, 0.32, 0.47, 0.9))
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_items_box.add_child(empty)
		return
	var shown := 0
	for i in ids.size():
		var item_id: String = str(ids[i])
		var def: Dictionary = GameState.item_def(item_id)
		if def.is_empty():
			continue
		if shown >= MAX_ITEMS_SHOWN:
			break
		shown += 1
		var slot := Button.new()
		slot.custom_minimum_size = Vector2(46, 32)
		slot.focus_mode = Control.FOCUS_NONE
		var is_new: bool = str(GameState.run.get("last_picked", "")) == item_id
		var rc: Color = UiTheme.RARITY.get(def.get("rarity", "common"), UiTheme.WHITE)
		var border := rc if is_new else Color(rc.r, rc.g, rc.b, 0.55)
		slot.add_theme_stylebox_override("normal", UiTheme.style_compact(Color(0.14, 0.11, 0.22, 0.9), border, 2 if is_new else 1, 3, 2))
		slot.add_theme_stylebox_override("hover", UiTheme.style_compact(Color(0.20, 0.15, 0.32, 0.95), rc, 2, 3, 2))
		slot.add_theme_stylebox_override("pressed", UiTheme.style_compact(Color(0.10, 0.08, 0.17, 0.95), rc, 2, 3, 2))
		slot.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		slot.tooltip_text = "点击查看详情"
		slot.pressed.connect(_on_item_slot_clicked.bind(item_id, items[item_id]))
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 2)
		hb.set_anchors_preset(Control.PRESET_FULL_RECT)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(hb)
		var tex := TextureRect.new()
		tex.texture = UiTheme.icon_texture(str(def.get("icon", "")))
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.custom_minimum_size = Vector2(16, 16)
		tex.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(tex)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 0)
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(vb)
		var name_l := UiTheme.label(_short_name(str(def.get("name", item_id))), 8, Color("#d8d0ec"))
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(name_l)
		var cnt := UiTheme.label("×%d" % items[item_id], 9, UiTheme.GOLD if is_new else UiTheme.WHITE, true)
		cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cnt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(cnt)
		_items_box.add_child(slot)
		if is_new:
			_pulse_slot(slot)
	if ids.size() > shown:
		var more := UiTheme.label("+%d" % (ids.size() - shown), 9, UiTheme.GOLD, true)
		more.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_items_box.add_child(more)

func _pulse_slot(slot: Button) -> void:
	# 获得反馈：新物品格子短暂放大脉冲
	var tw := create_tween()
	tw.tween_property(slot, "scale", Vector2(1.12, 1.12), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(slot, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)

func _on_item_slot_clicked(item_id: String, stacks: int) -> void:
	var def: Dictionary = GameState.item_def(item_id)
	if def.is_empty():
		return
	var tags: Array = def.get("tags", [])
	var tag_txt := ""
	if not tags.is_empty():
		var names := tags.map(func(t): return _tag_name(str(t)))
		tag_txt = "　标签：" + "、".join(names)
	_show_detail(
		"%s ×%d" % [def.get("name", item_id), stacks],
		"%s（%s）%s\n%s" % [
			def.get("description", ""),
			_rarity_name(str(def.get("rarity", "common"))),
			tag_txt,
			"点击任意处关闭",
		],
		UiTheme.RARITY.get(def.get("rarity", "common"), UiTheme.WHITE),
		UiTheme.icon_texture(str(def.get("icon", ""))),
	)

func _on_grid_slot_clicked(i: int) -> void:
	var grid: Array = GameState.run.get("grid", [])
	if i >= grid.size():
		return
	var core_id: String = str(grid[i].get("core", ""))
	var shell_id: String = str(grid[i].get("shell", ""))
	var core := _core_def(core_id)
	var shell := _shell_def(shell_id)
	var core_name := str(core.get("name", core_id))
	var shell_name := "" if shell.is_empty() else " + " + str(shell.get("name", shell_id))
	var desc := "法术格 %d：%s%s" % [i + 1, core_name, shell_name]
	var parts: Array[String] = []
	if core.has("base_damage"):
		parts.append("伤害 %d" % int(core.get("base_damage", 0)))
	if core.has("cooldown"):
		parts.append("冷却 %.1fs" % float(core.get("cooldown", 1.0)))
	var element := str(core.get("element", ""))
	if not element.is_empty():
		parts.append("属性·" + _element_name(element))
	var shell_txt := _shell_desc(shell)
	if not shell_txt.is_empty():
		parts.append("外壳·" + shell_txt)
	_show_detail(
		"%s%s" % [core_name, shell_name],
		"%s\n%s\n点击任意处关闭" % [desc, "　".join(parts)],
		UiTheme.ELEMENT.get(element, UiTheme.GOLD),
		UiTheme.icon_texture(str(core.get("icon", ""))),
	)

func _show_detail(title: String, desc: String, color: Color, icon: Texture2D) -> void:
	_detail_title.text = title
	_detail_title.add_theme_color_override("font_color", color)
	_detail_desc.text = desc
	_detail_icon.texture = icon
	_detail_dim.visible = true
	_detail_panel.visible = true

func _hide_detail() -> void:
	_detail_dim.visible = false
	_detail_panel.visible = false

func _build_detail(root: Control) -> void:
	# 详情弹窗：点击任意处/Esc/× 关闭
	_detail_dim = Button.new()
	_detail_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_detail_dim.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_detail_dim.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	_detail_dim.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	_detail_dim.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_detail_dim.focus_mode = Control.FOCUS_NONE
	_detail_dim.pressed.connect(_hide_detail)
	_detail_dim.visible = false
	root.add_child(_detail_dim)
	_detail_panel = PanelContainer.new()
	_detail_panel.set_anchors_preset(Control.PRESET_CENTER)
	_detail_panel.position = Vector2(-150, -55)
	_detail_panel.custom_minimum_size = Vector2(300, 0)
	_detail_panel.add_theme_stylebox_override("panel", UiTheme.style(UiTheme.PANEL, UiTheme.BORDER, 2, 6))
	_detail_panel.visible = false
	root.add_child(_detail_panel)
	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 4)
	_detail_panel.add_child(main)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	main.add_child(head)
	_detail_icon = TextureRect.new()
	_detail_icon.custom_minimum_size = Vector2(22, 22)
	_detail_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_detail_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	head.add_child(_detail_icon)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	head.add_child(vb)
	_detail_title = UiTheme.label("", 13, UiTheme.GOLD)
	vb.add_child(_detail_title)
	var close := UiTheme.button("×", Vector2(26, 26))
	close.tooltip_text = "关闭"
	close.pressed.connect(_hide_detail)
	head.add_child(close)
	_detail_desc = UiTheme.label("", 10, Color("#c8c0e0"))
	_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_desc.custom_minimum_size = Vector2(280, 0)
	main.add_child(_detail_desc)

func _unhandled_input(event: InputEvent) -> void:
	if _detail_panel.visible and event.is_action_pressed("pause"):
		_hide_detail()
		get_viewport().set_input_as_handled()

func _core_icon(core_id: String) -> Texture2D:
	return UiTheme.icon_texture(str(_core_def(core_id).get("icon", "")))

func _core_def(core_id: String) -> Dictionary:
	for c in GameState.tables.get("spells", {}).get("cores", []):
		if str(c.get("id", "")) == core_id:
			return c
	return {}

func _shell_def(shell_id: String) -> Dictionary:
	if shell_id.is_empty():
		return {}
	for s in GameState.tables.get("spells", {}).get("shells", []):
		if str(s.get("id", "")) == shell_id:
			return s
	return {}

func _shell_short(shell_id: String) -> String:
	match shell_id:
		"rapid":
			return "速"
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

func _shell_desc(shell: Dictionary) -> String:
	if shell.is_empty():
		return ""
	var mods: Dictionary = shell.get("mods", {})
	var parts: Array[String] = []
	if mods.has("shots"):
		parts.append("弹道 ×%d" % int(mods["shots"]))
	if mods.has("spread_angle"):
		parts.append("散射 %d°" % int(mods["spread_angle"]))
	if mods.has("homing"):
		parts.append("追踪")
	if mods.has("pierce"):
		parts.append("穿透 +%d" % int(mods["pierce"]))
	if mods.has("bounce"):
		parts.append("弹射 +%d" % int(mods["bounce"]))
	if mods.has("orbit"):
		parts.append("环绕 +%d" % int(mods["orbit"]))
	if mods.has("explode"):
		parts.append("爆炸")
	if mods.has("aoe_mult"):
		parts.append("范围 ×%.1f" % float(mods["aoe_mult"]))
	if mods.has("delay"):
		parts.append("延时 %.1fs" % float(mods["delay"]))
	if mods.has("damage_mult") and float(mods["damage_mult"]) != 1.0:
		parts.append("伤害 ×%.1f" % float(mods["damage_mult"]))
	if mods.has("cooldown_mult") and float(mods["cooldown_mult"]) != 1.0:
		parts.append("冷却 ×%.1f" % float(mods["cooldown_mult"]))
	return "、".join(parts)

func _element_name(e: String) -> String:
	match e:
		"fire":
			return "火焰"
		"ice":
			return "寒冰"
		"lightning":
			return "雷电"
		"poison":
			return "毒素"
		"blade":
			return "利刃"
		"summon":
			return "召唤"
		_:
			return e

func _rarity_name(r: String) -> String:
	match r:
		"common":
			return "普通"
		"rare":
			return "稀有"
		"legendary":
			return "传说"
		_:
			return r

func _tag_name(t: String) -> String:
	match t:
		"attack_speed":
			return "攻速"
		"atk":
			return "攻击"
		"crit":
			return "暴击率"
		"crit_dmg":
			return "暴击伤害"
		"crit_luck":
			return "暴击好运"
		"defense":
			return "防御"
		"lifesteal":
			return "吸血"
		"area":
			return "范围"
		"bounce":
			return "弹射"
		"cooldown":
			return "冷却"
		"gold":
			return "金币"
		"xp":
			return "经验"
		"freeze":
			return "冰冻"
		"poison":
			return "中毒"
		"lightning":
			return "落雷"
		"summon":
			return "召唤"
		"pickup":
			return "拾取"
		"speed":
			return "移速"
		"skill_cd":
			return "技能冷却"
		"skill_dmg":
			return "技能伤害"
		"fire":
			return "火焰"
		"ice":
			return "寒冰"
		"drawback":
			return "代价"
		_:
			return t

func _refresh_dps() -> void:
	if GameState.run.is_empty():
		return
	_dps_label.text = "DPS %d" % int(GameState.estimate_dps())

func _short_name(name: String) -> String:
	if name.length() <= 3:
		return name
	return name.substr(0, 3)
