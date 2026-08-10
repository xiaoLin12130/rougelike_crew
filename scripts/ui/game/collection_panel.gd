extends CanvasLayer
## 图鉴面板（P3，竖版 360x640）：主菜单"图鉴"按钮进入，Esc/返回按钮退回主菜单。
## 五分类 tab：法杖 55 / 法术核心 15 / 法术外壳 10 / 装备饰品 274+ / 召唤物 10，
## 条目网格（GridContainer 4 列，格 64x64 = 图标 48 + 名称 12px 底部）。
## 已收集：图标 + 名称 + 稀有度描边，点击弹详情（名称/稀有度/描述）；
## 未收集：图标 modulate 压黑（Color(0,0,0,0.6) 黑色剪影）+ 名称"？？？"，无描述、点击无效。
## 数据只读 data/*.json（GameState.tables），收集状态只读 GameState.collection。
const UiLayout := preload("res://scripts/ui/ui_layout.gd")

const PANEL_BG := Color(0.07, 0.05, 0.11, 0.94)
const PANEL_BORDER := Color(0.38, 0.28, 0.62, 0.9)
const CELL_BG := Color(0.10, 0.08, 0.16, 0.85)
const CELL_BORDER_DIM := Color(0.28, 0.24, 0.36, 0.8)
const UNCOLLECTED_ICON := Color(0, 0, 0, 0.6)  # 未收集：原图标压黑 + 60% 不透明
const CELL_SIZE := Vector2(64, 64)
const ICON_SIZE := Vector2(48, 44)
const GRID_COLUMNS := 4
## 手机端（is_mobile，同 wand_shop 分支风格）：3 列 72x72 格（触控目标更大）+ 图标 56
## + 两行缩略 tab（"法杖\n1/55"）+ 字号略小；PC 保持 4 列 64x64。
const CELL_SIZE_MOBILE := Vector2(72, 72)
const ICON_SIZE_MOBILE := Vector2(56, 56)
const GRID_COLUMNS_MOBILE := 3
const TAB_W := 60.0
## 手机端 tab 短名：法杖/法术/外壳/装备/召唤（长名"装备饰品 274/276"放不下，改两行）
const TAB_SHORT_NAMES: Array = ["法杖", "法术", "外壳", "装备", "召唤"]

## 分类定义：["categories 键", "中文名", "稀有度兜底"]（cores/shells/summons 数据表无 rarity 字段）
const CATEGORIES: Array = [
	["wands", "法杖", "rare"],
	["cores", "法术核心", "rare"],
	["shells", "法术外壳", "rare"],
	["items", "装备饰品", "common"],
	["summons", "召唤物", "common"],
]

var _tab_idx := 0
var _tabs: Array[Button] = []
var _grid: Container  # 2026-08-10：HFlowContainer（填满宽度自动换行）
var _progress: Label
var _detail: PanelContainer
var _detail_title: Label
var _detail_body: Label
## 平台分支尺寸：_ready 按 UiLayout.is_mobile() 初始化（PC 默认值，手机端覆盖）
var _mobile := false
var _grid_columns := GRID_COLUMNS
var _cell_size := CELL_SIZE
var _icon_size := ICON_SIZE
var _tab_w := TAB_W
var _name_sz := 10

func _ready() -> void:
	_mobile = UiLayout.is_mobile()
	if _mobile:
		# 手机端：网格 3 列 72x72、图标 56、tab 两行缩略、字号略小
		_grid_columns = GRID_COLUMNS_MOBILE
		_cell_size = CELL_SIZE_MOBILE
		_icon_size = ICON_SIZE_MOBILE
		_name_sz = 9
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	# 全屏暗幕：主菜单可见性降低，突出图鉴内容
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.015, 0.04, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var panel := PanelContainer.new()
	UiLayout.center_panel(panel, UiLayout.panel_w(), UiLayout.panel_h() + 20.0)
	panel.custom_minimum_size = Vector2(UiLayout.panel_w(), UiLayout.panel_h() + 20.0)
	panel.add_theme_stylebox_override("panel", UiTheme.style(PANEL_BG, PANEL_BORDER, 2, 8))
	root.add_child(panel)
	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 6)
	panel.add_child(main)
	var title := UiTheme.label("图鉴", 18, UiTheme.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main.add_child(title)
	_progress = UiTheme.label("", 9 if _mobile else 10, Color("#9d8fc4"))
	_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main.add_child(_progress)
	# 分类 tab（5 个，44 高触控目标；60 宽 x5 + 4x4 间距 = 316 ≤ 340）
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	main.add_child(tabs)
	for i in CATEGORIES.size():
		var b := UiTheme.button("", Vector2(_tab_w, UiLayout.touch_min()))
		if _mobile:
			b.add_theme_font_size_override("font_size", 9)
		b.toggle_mode = true
		b.pressed.connect(_on_tab_pressed.bind(i))
		tabs.add_child(b)
		_tabs.append(b)
	var hint := UiTheme.label("已收集条目点击查看详情 · 未收集为黑色剪影", 8 if _mobile else 9, Color("#7a6fa0"))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main.add_child(hint)
	# 条目网格：可滚动（274 件装备等多行内容）
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(scroll)
	# 2026-08-10?GridContainer ????????? ? ? HFlowContainer??????
	# ????????????????????????PC/????????
	_grid = HFlowContainer.new()
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)
	var back := UiTheme.button("返回主菜单 (Esc)", Vector2(180, UiLayout.touch_min()))
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(_close)
	main.add_child(back)
	_build_detail(root)
	refresh()

func _build_detail(root: Control) -> void:
	## 已收集条目点击详情弹窗（名称/稀有度/描述；未收集条目不触发）
	_detail = PanelContainer.new()
	# 2026-08-10?CenterContainer ???????????????+grow ?????
	# PRESET_CENTER ? grow ?? END ?????????????
	_detail.custom_minimum_size = Vector2(320, 200)
	_detail.add_theme_stylebox_override("panel", UiTheme.style(Color(0.10, 0.08, 0.18, 0.96), UiTheme.BORDER, 2, 6))
	_detail.visible = false
	var _center := CenterContainer.new()
	_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_center)
	_center.add_child(_detail)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	_detail.add_child(vb)
	_detail_title = UiTheme.label("", 16, UiTheme.GOLD)
	_detail_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_title.custom_minimum_size = Vector2(260, 0)  # 同 body：避免 min-size 按窄宽换行膨胀
	vb.add_child(_detail_title)
	_detail_body = UiTheme.label("", 12, Color("#c8c0e0"))
	_detail_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# min 宽 260（非 0）：autowrap Label 在 min-size 计算时按 1px 宽换行会膨胀到数百 px
	# 高（同 wand_shop 卡片描述坑），导致详情弹窗超高越屏
	_detail_body.custom_minimum_size = Vector2(300, 76)  # 2026-08-10??? 320 ???? 300 ????
	_detail_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	vb.add_child(_detail_body)
	var ok := UiTheme.button("知道了", Vector2(140, UiLayout.touch_min()))
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.pressed.connect(func() -> void: _detail.visible = false)
	vb.add_child(ok)

func _entries(category: String) -> Array:
	## 只读数据表条目（图鉴直接读 data/*.json，不复制数据）
	match category:
		"wands":
			return GameState.tables.get("wands", {}).get("wands", [])
		"cores":
			return GameState.tables.get("spells", {}).get("cores", [])
		"shells":
			return GameState.tables.get("spells", {}).get("shells", [])
		"items":
			return GameState.tables.get("items", {}).get("items", [])
		"summons":
			return GameState.tables.get("summons", {}).get("summons", [])
	return []

func _category_key(idx: int) -> String:
	return str(CATEGORIES[idx][0])

func _category_name(idx: int) -> String:
	return str(CATEGORIES[idx][1])

func _rarity_of(category: String, def: Dictionary) -> String:
	## cores/shells/summons 数据表无 rarity 字段 → 用分类兜底（法术中档/召唤普通）
	var r: String = str(def.get("rarity", ""))
	if r.is_empty():
		for c in CATEGORIES:
			if c[0] == category:
				return str(c[2])
	return r

func _on_tab_pressed(idx: int) -> void:
	_tab_idx = idx
	refresh()

func _collected_count(category: String) -> int:
	## 已收集且条目仍存在于数据表的数量（数据表变动时进度不虚高）
	var n := 0
	for def in _entries(category):
		if GameState.is_collected(category, str(def.get("id", ""))):
			n += 1
	return n

func refresh() -> void:
	var category := _category_key(_tab_idx)

	for i in CATEGORIES.size():
		var ck := _category_key(i)
		var count := _collected_count(ck)
		var total := _entries(ck).size()
		if _mobile:
			# 手机端两行缩略：短名 + 进度（字号 9，5 x 60 宽不溢出）
			_tabs[i].text = "%s\n%d/%d" % [TAB_SHORT_NAMES[i], count, total]
		else:
			_tabs[i].text = "%s %d/%d" % [_category_name(i), count, total]
		_tabs[i].button_pressed = (i == _tab_idx)
	var entries := _entries(category)
	_progress.text = "收集进度：%s 已收集 %d / %d" % [
		_category_name(_tab_idx), _collected_count(category), entries.size(),
	]
	for c in _grid.get_children():
		c.queue_free()
	for def in entries:
		_grid.add_child(_make_entry(def, category))

func _make_entry(def: Dictionary, category: String) -> Control:
	## 条目格 64x64：图标（已收集原色 / 未收集压黑剪影）+ 底部名称
	var collected := GameState.is_collected(category, str(def.get("id", "")))
	var rarity := _rarity_of(category, def)
	var cell := PanelContainer.new()
	cell.custom_minimum_size = _cell_size
	cell.add_theme_stylebox_override("panel", UiTheme.style(
		CELL_BG,
		UiTheme.RARITY.get(rarity, UiTheme.BORDER) if collected else CELL_BORDER_DIM,
		1, 3))
	cell.set_meta("entry_id", str(def.get("id", "")))
	cell.set_meta("collected", collected)
	cell.set_meta("category", category)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	cell.add_child(vb)
	var icon: Texture2D = UiTheme.icon_texture(str(def.get("icon", "")))
	if icon == null:
		# 数据表图标缺失时用纯色占位（未收集保持黑色剪影语义）
		var ph := ColorRect.new()
		ph.color = Color(0.16, 0.13, 0.24, 0.9) if collected else Color(0.04, 0.03, 0.06, 0.9)
		ph.custom_minimum_size = _icon_size
		ph.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		ph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(ph)
	else:
		var tex := TextureRect.new()
		tex.texture = icon
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.custom_minimum_size = _icon_size
		tex.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		tex.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not collected:
			tex.modulate = UNCOLLECTED_ICON  # 未收集：黑色剪影（原图压黑+半透明）
		vb.add_child(tex)
	var name_l := UiTheme.label(
		str(def.get("name", "?")) if collected else "？？？",
		_name_sz,
		UiTheme.WHITE if collected else Color("#6a6280"))
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.custom_minimum_size = Vector2(_cell_size.x, 16)
	name_l.clip_text = true
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(name_l)
	# 已收集：点击弹详情（名称/稀有度/描述）；未收集：点击无效
	if collected:
		var name_text := str(def.get("name", "?"))
		var desc_text := str(def.get("description", ""))
		cell.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_show_detail(name_text, rarity, desc_text))
	return cell

func _show_detail(title: String, rarity: String, body: String) -> void:
	_detail_title.text = "%s（%s）" % [title, rarity]
	_detail_body.text = body
	_detail.visible = true

func _close() -> void:
	queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_close()
		get_viewport().set_input_as_handled()
	elif _detail != null and _detail.visible and event.is_action_pressed("ui_cancel"):
		_detail.visible = false
		get_viewport().set_input_as_handled()
