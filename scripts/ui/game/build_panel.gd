extends CanvasLayer
## 构筑面板（竖版 360x640，雨中冒险样式）：面板 320x540 居中（<=340 宽），
## 法杖 3 槽横排；法术网格 5 格改 2 列排布（GridContainer，格 46x46）；
## 装备/饰品用 FlowContainer（宽 296，多行自动换行），整体 ScrollContainer 兜底。
## 触屏适配：格子点击已有行为（法术交换）；法杖/装备/饰品格点击弹出详情
## （_detail 弹窗，名称+描述+关闭），触屏不依赖 hover tooltip（tooltip 仅桌面附加）。
const UiLayout := preload("res://scripts/ui/ui_layout.gd")

const SLOT_SIZE := Vector2(46, 46)
const ICON_SIZE := Vector2(36, 36)
const PANEL_BG := Color(0.07, 0.05, 0.11, 0.55)
const PANEL_BORDER := Color(0.38, 0.28, 0.62, 0.5)
const SLOT_BG := Color(0.10, 0.08, 0.16, 0.75)
const SLOT_BORDER := Color(0.30, 0.22, 0.52, 0.7)

var _items_box: FlowContainer
var _trinkets_box: FlowContainer
var _grid_box: GridContainer
var _wand_box: HBoxContainer
var _stats_label: Label
var _sel_slot := -1
var _detail: PanelContainer
var _detail_title: Label
var _detail_body: Label

func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	# 全屏暗幕：降低透明度，战斗区仍可见（雨中冒险式）
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.015, 0.04, 0.38)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var panel := PanelContainer.new()
	UiLayout.center_panel(panel, UiLayout.panel_w(), UiLayout.panel_h() + 20.0)
	panel.custom_minimum_size = Vector2(UiLayout.panel_w(), UiLayout.panel_h() + 20.0)
	panel.add_theme_stylebox_override("panel", UiTheme.style(PANEL_BG, PANEL_BORDER, 2, 8))
	root.add_child(panel)
	# 内容可滚动：法杖/法术/装备/饰品 超出面板高度时滚动查看
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(UiLayout.panel_w(), UiLayout.panel_h() + 20.0)
	panel.add_child(scroll)
	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 8)
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(main)
	_section(main, "法杖（最多装备 1 把，Boss 战后可用金币购买）")
	_wand_box = HBoxContainer.new()
	_wand_box.add_theme_constant_override("separation", 6)
	_wand_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	main.add_child(_wand_box)
	_section(main, "法术序列（点击两格交换）")
	_grid_box = GridContainer.new()
	# 法术序列：PC（横屏）5 格单行展示；手机（竖屏）2 列排布
	_grid_box.columns = 5 if not UiLayout.is_portrait() else 2
	_grid_box.add_theme_constant_override("h_separation", 6)
	_grid_box.add_theme_constant_override("v_separation", 6)
	_grid_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER  # 法术格整体居中
	main.add_child(_grid_box)
	_section(main, "装备（点击查看详情）")
	_items_box = FlowContainer.new()
	_items_box.add_theme_constant_override("h_separation", 5)
	_items_box.add_theme_constant_override("v_separation", 5)
	_items_box.custom_minimum_size = Vector2(296, 0)
	_items_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	main.add_child(_items_box)
	_section(main, "饰品（点击查看详情）")
	_trinkets_box = FlowContainer.new()
	_trinkets_box.add_theme_constant_override("h_separation", 5)
	_trinkets_box.add_theme_constant_override("v_separation", 5)
	_trinkets_box.custom_minimum_size = Vector2(296, 0)
	_trinkets_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	main.add_child(_trinkets_box)
	_section(main, "玩家属性")
	_stats_label = UiTheme.label("", 10, Color("#c8c0e0"))
	main.add_child(_stats_label)
	var close := UiTheme.button("关闭 (Esc)", Vector2(160, UiLayout.touch_min()))
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(hide)
	main.add_child(close)
	_build_detail(root)

func _section(parent: Node, text: String) -> void:
	var l := UiTheme.label(text, 11, Color(0.62, 0.56, 0.8, 0.85))
	parent.add_child(l)

func _build_detail(root: Control) -> void:
	## 点击格子查看详情弹窗（触屏替代 hover tooltip 的入口）。
	_detail = PanelContainer.new()
	UiLayout.center_panel(_detail, 300.0, 200.0)
	_detail.custom_minimum_size = Vector2(300, 200)
	_detail.add_theme_stylebox_override("panel", UiTheme.style(Color(0.10, 0.08, 0.18, 0.96), UiTheme.BORDER, 2, 6))
	_detail.visible = false
	root.add_child(_detail)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	_detail.add_child(vb)
	_detail_title = UiTheme.label("", 16, UiTheme.GOLD)
	_detail_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_detail_title)
	_detail_body = UiTheme.label("", 12, Color("#c8c0e0"))
	_detail_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_body.custom_minimum_size = Vector2(0, 76)
	_detail_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	vb.add_child(_detail_body)
	var ok := UiTheme.button("知道了", Vector2(140, UiLayout.touch_min()))
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.pressed.connect(func(): _detail.visible = false)
	vb.add_child(ok)

func _show_detail(title: String, body: String) -> void:
	_detail_title.text = title
	_detail_body.text = body
	_detail.visible = true

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		hide()
		get_viewport().set_input_as_handled()
	if _detail.visible and event.is_action_pressed("ui_cancel"):
		_detail.visible = false
		get_viewport().set_input_as_handled()

func refresh() -> void:
	_refresh_wand()
	_refresh_items()
	_refresh_trinkets()
	_refresh_grid()
	_refresh_stats()

func _refresh_stats() -> void:
	var run: Dictionary = GameState.run
	var stone: float = GameState.item_value(
		{"curve": {"type": "linear", "base": 0.06, "k": 0.06, "cap": 0.35}},
		GameState.total_stacks("stone_armor"))
	var reflect: float = GameState.item_value(
		{"curve": {"type": "linear", "base": 0.30, "k": 0.20, "cap": 0.65}},
		GameState.total_stacks("thorn_reflect"))
	reflect += float(run.get("synergy_bonus", {}).get("defense", 0.0))
	_stats_label.text = "生命 %d/%d · 攻击 +%d%% · 攻速 +%d%%\n暴击 %.0f%% · 暴伤 +%d%% · 移速 +%d%%\n减伤 %.0f%% · 反弹 %.0f%% · 吸血 %.1f%% · 范围 +%d%%" % [
		run.get("hp", 0), run.get("max_hp", 100),
		int(GameState.aggregate_bonus("atk") * 100),
		int(GameState.aggregate_bonus("attack_speed") * 100),
		float(run.get("crit_chance", 0.03)) * 100,
		int((float(run.get("crit_dmg_bonus", 1.5)) - 1.0) * 100),
		int(GameState.aggregate_bonus("speed") * 100),
		stone * 100 + float(run.get("synergy_bonus", {}).get("defense", 0.0)) * 100,
		reflect * 100,
		float(run.get("lifesteal", 0.0)) * 100,
		int(GameState.aggregate_bonus("area") * 100),
	]

func _refresh_wand() -> void:
	for c in _wand_box.get_children():
		c.queue_free()
	var owned := GameState.current_wands()
	if owned.is_empty():
		var empty := PanelContainer.new()
		empty.custom_minimum_size = Vector2(296, 38)
		empty.add_theme_stylebox_override("panel", UiTheme.style(Color(0.10, 0.08, 0.16, 0.7), SLOT_BORDER, 1, 3))
		var l := UiTheme.label("未装备法杖 —— 击败 Boss 后用金币购买（形态决定法术释放方式）", 10, Color("#5a5278"))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.add_child(l)
		_wand_box.add_child(empty)
		return
	# 最多 3 把法杖槽（点击查看详情，触屏可用）
	for i in 3:
		if i < owned.size():
			var wand := GameState.wand_def(str(owned[i]))
			var slot := PanelContainer.new()
			slot.custom_minimum_size = SLOT_SIZE
			slot.tooltip_text = "%s（%s）\n%s" % [
				wand.get("name", "?"),
				wand.get("rarity", "common"),
				wand.get("description", ""),
			]
			slot.add_theme_stylebox_override("panel", UiTheme.style(Color(0.12, 0.09, 0.19, 0.85), UiTheme.RARITY.get(str(wand.get("rarity", "common")), UiTheme.BORDER), 1, 3))
			var tex := TextureRect.new()
			tex.texture = UiTheme.icon_texture(str(wand.get("icon", "")))
			tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex.custom_minimum_size = ICON_SIZE
			tex.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			tex.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot.add_child(tex)
			var detail_text := "%s（%s）\n%s" % [
				wand.get("name", "?"), wand.get("rarity", "common"), wand.get("description", ""),
			]
			slot.gui_input.connect(func(ev: InputEvent):
				if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
					_show_detail(str(wand.get("name", "?")), str(wand.get("description", ""))))
			_wand_box.add_child(slot)
		else:
			var empty := PanelContainer.new()
			empty.custom_minimum_size = SLOT_SIZE
			empty.add_theme_stylebox_override("panel", UiTheme.style(Color(0.10, 0.08, 0.16, 0.6), Color(0.30, 0.22, 0.52, 0.4), 1, 3))
			var l := UiTheme.label("+", 16, Color("#5a5278"))
			l.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			empty.add_child(l)
			_wand_box.add_child(empty)

## 雨中冒险式格子：图标 + 右下角数量角标（数量 >1 才显示）；点击查看详情
func _icon_slot(def: Dictionary, count: int, tooltip: String) -> Control:
	var box := PanelContainer.new()
	box.custom_minimum_size = SLOT_SIZE
	box.tooltip_text = tooltip
	box.add_theme_stylebox_override("panel", UiTheme.style(SLOT_BG, SLOT_BORDER, 1, 3))
	var tex := TextureRect.new()
	tex.texture = UiTheme.icon_texture(str(def.get("icon", "")))
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.custom_minimum_size = ICON_SIZE
	tex.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tex.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(tex)
	if count > 1:
		var badge := UiTheme.label(str(count), 12, UiTheme.WHITE)
		badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		badge.position = Vector2(-16, -17)
		badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		badge.add_theme_constant_override("outline_size", 3)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(badge)
	var active: Array = []
	var holdings: Dictionary = GameState.school_holdings()
	for s in GameState.schools_of_item(def):
		if int(holdings.get(s, 0)) >= 2:
			active.append(GameState.SCHOOL_NAMES.get(s, s))
	if not active.is_empty():
		var syn := UiTheme.label("联动", 8, Color("#8fe89a"))
		syn.set_anchors_preset(Control.PRESET_TOP_LEFT)
		syn.position = Vector2(2, -4)
		syn.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		syn.add_theme_constant_override("outline_size", 3)
		syn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(syn)
	var title := str(def.get("name", "?"))
	var body := str(def.get("description", ""))
	if count > 1:
		title = "%s ×%d" % [title, count]
	if not active.is_empty():
		body = body + "\n联动：" + "、".join(active) + " 已激活"
	box.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_show_detail(title, body))
	return box

func _refresh_items() -> void:
	for c in _items_box.get_children():
		c.queue_free()
	var items: Dictionary = GameState.run.get("items", {})
	if items.is_empty():
		_items_box.add_child(UiTheme.label("（还没有装备）", 11, Color("#5a5278")))
		return
	for item_id in items:
		var def := GameState.item_def(str(item_id))
		if def.is_empty():
			continue
		var stacks: int = int(items[item_id])
		_items_box.add_child(_icon_slot(
			def, stacks,
			"%s ×%d\n%s" % [def.get("name", item_id), stacks, def.get("description", "")],
		))

func _refresh_trinkets() -> void:
	for c in _trinkets_box.get_children():
		c.queue_free()
	var trinkets: Array = GameState.run.get("trinkets", [])
	if trinkets.is_empty():
		_trinkets_box.add_child(UiTheme.label("（还没有饰品）", 11, Color("#5a5278")))
		return
	for tid in trinkets:
		var def := GameState.item_def(str(tid))
		if def.is_empty():
			continue
		_trinkets_box.add_child(_icon_slot(
			def, 1,
			"%s\n%s" % [def.get("name", tid), def.get("description", "")],
		))

func _refresh_grid() -> void:
	for c in _grid_box.get_children():
		c.queue_free()
	var grid: Array = GameState.run.get("grid", [])
	var slots: int = GameState.tables.get("balance", {}).get("max_grid_slots", 5)
	for i in slots:
		var box := Button.new()
		UiTheme.apply_font(box, 12)
		box.custom_minimum_size = SLOT_SIZE
		box.add_theme_stylebox_override("normal", UiTheme.style(SLOT_BG, SLOT_BORDER, 1, 3))
		box.add_theme_stylebox_override("hover", UiTheme.style(Color(0.14, 0.11, 0.22, 0.9), UiTheme.BORDER, 1, 3))
		box.add_theme_stylebox_override("pressed", UiTheme.style(Color(0.16, 0.12, 0.26, 0.9), UiTheme.GOLD, 1, 3))
		box.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		box.text = ""
		if i < grid.size():
			var core_id: String = str(grid[i].get("core", ""))
			var shell_id: String = str(grid[i].get("shell", ""))
			var core := _find_core(core_id)
			var shell: Dictionary = {}
			var tex := TextureRect.new()
			tex.texture = UiTheme.icon_texture(str(core.get("icon", "")))
			tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex.custom_minimum_size = ICON_SIZE
			tex.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			tex.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			tex.position = Vector2(5, 5)  # 图标在格内居中偏右下（修正错位）
			tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(tex)
			if not shell_id.is_empty():
				# 外壳角标：右下角小方块显示外壳序号（悬停 tooltip 查看外壳名）
				shell = _find_shell(shell_id)
				var badge := UiTheme.label(str(_shell_index(shell_id) + 1), 10, UiTheme.GOLD)
				badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
				badge.position = Vector2(-15, -16)
				badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
				badge.add_theme_constant_override("outline_size", 3)
				badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
				box.add_child(badge)
			var tooltip := "%s · %s\n冷却 %.1fs · 伤害 %.0f\n%s" % [
				core.get("name", core_id),
				shell.get("name", "原生形态") if not shell_id.is_empty() else "原生形态",
				float(core.get("cooldown", 1.0)),
				float(core.get("base_damage", 0.0)),
				str(core.get("description", "")),
			]
			box.tooltip_text = tooltip
			# 触屏：长按/双击不依赖——点击已有交换行为；tooltip 仅桌面附加
			box.pressed.connect(_on_slot_clicked.bind(i))
		else:
			box.tooltip_text = "空法术位"
			box.pressed.connect(_on_slot_clicked.bind(i))
		_grid_box.add_child(box)

func _find_core(id: String) -> Dictionary:
	for c in GameState.tables.get("spells", {}).get("cores", []):
		if str(c.get("id", "")) == id:
			return c
	return {}

func _find_shell(id: String) -> Dictionary:
	for s in GameState.tables.get("spells", {}).get("shells", []):
		if str(s.get("id", "")) == id:
			return s
	return {}

func _shell_index(id: String) -> int:
	var shells: Array = GameState.tables.get("spells", {}).get("shells", [])
	for i in shells.size():
		if str(shells[i].get("id", "")) == id:
			return i
	return -1

func _on_slot_clicked(i: int) -> void:
	if _sel_slot < 0:
		_sel_slot = i
		return
	if _sel_slot != i:
		GameState.swap_grid(_sel_slot, i)
	_sel_slot = -1
	refresh()
