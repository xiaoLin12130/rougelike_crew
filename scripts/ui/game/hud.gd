extends CanvasLayer
## HUD（竖版 360x640，土豆兄弟化 2026-08-12）：
## 依据 docs/design/土豆兄弟UI适配方案.md §5.2 + ui-rag（道具格=图标+数量角标、
## 底部常驻构筑栏、获得 XX ×N 提示）：
##  - 左上资源区（y24，右缘<=185）：① HP 数字+血条（护盾灰蓝叠层+数值小字）
##    ② 材料图标+金币数 ③ Lv 徽章+XP 条同排 ④ 第N关·DPS·攻速小字；
##  - 波次横幅：顶部中右（x186..356，y24..52）「第 N 波 + 倒计时 + 金色计时条」，
##    与 Boss 血条带（y4..20）和资源区（x<186）互斥；Boss 在场自动隐藏；
##  - Boss 血条：顶部居中（总宽<=260，y4..20），灰蓝边框+暗红填充，不隐藏经验条；
##  - 底部武器/法术栏：PC 5 格单行 / 手机 3+2 两行，图标+×N 角标+外壳小角标，
##    与左下角按钮（x<=60）互斥；点击格打开构筑面板；
##  - 获得提示（拾取/流派）：屏幕中下，图标+名称+×N；
##  - TAB 键（PC）开关构筑面板，等价于左下构筑按钮。
const UiLayout := preload("res://scripts/ui/ui_layout.gd")

const TOUCH_BTN := Vector2(UiLayout.TOUCH_MIN + 8, UiLayout.TOUCH_MIN + 8)  # 52x52
const SHIELD_SCRIPT_PATH := "res://scripts/synergies/defense_synergy.gd"  # 护盾池所在脚本（只读查询）
const MAT_ICON_PATH := "res://assets/icons/shikashi/shikashi_r12_c10.png"  # 材料金币堆（Brotato 材料位）
const WEAPON_BAND_LEFT := 64.0   # 武器栏安全带左缘（左下按钮 x6..58 之外）
const WEAPON_BAND_RIGHT := 356.0 # 武器栏安全带右缘
const WEAPON_BOTTOM_GAP := 30.0  # 武器栏底缘距视口底（含底部安全区）

var _hp_bar: ProgressBar
var _shield_bar: ProgressBar  # 护盾灰色层（叠加在 HP 条上，宽度 = 护盾/最大生命）
var _shield_source: Node = null  # defense_synergy 节点缓存（只读查询 _shield）
var _hp_label: Label
var _shield_label: Label  # 护盾数值小字（叠在血条右端）
var _xp_bar: ProgressBar
var _lv_badge: PanelContainer  # Lv 徽章（金底黑字，与 XP 条同排）
var _lv_label: Label
var _mat_icon: TextureRect  # 材料图标（16x16 金币堆）
var _gold_label: Label
var _dps_label: Label
var _as_label: Label  # 攻速加成小字
var _level_label: Label
var _res_box: BoxContainer
var _wave_root: PanelContainer  # 波次横幅容器（含标题+倒计时+计时条）
var _wave_label: Label
var _wave_time_label: Label
var _wave_bar: ProgressBar
var _wave_dur := 0.0
var _wave_start := 0.0
var _wave_active := false
var _boss_bar: ProgressBar
var _boss_name: Label
var _boss_root: HBoxContainer
var _pickup_root: HBoxContainer  # 获得提示容器（图标+文字）
var _pickup_icon: TextureRect
var _pickup_label: Label
var _build_btn: Button
var _pause_btn: Button
var _weapon_bar: Container  # 底部武器/法术栏（PC HBox / 手机 Grid 3+2）
var _weapon_slots: Array = []
var _grid_sig := ""
var _form_label: Label
var _formed_tiers: Dictionary = {}  # 已触发过的成型档位（key: "school:tier"），每档只触发一次
var _form_banner_count := 0         # 横幅累计触发次数（供 headless 测试断言）

func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_resources(root)
	_build_wave(root)
	_build_pickup_label(root)
	_build_form_banner(root)
	_build_corner_buttons(root)
	_build_boss_bar(root)
	_build_weapon_bar(root)
	EventBus.player_stats_changed.connect(_refresh)
	EventBus.spell_arranged.connect(func(_g: Array) -> void: _refresh())
	EventBus.wave_state_changed.connect(_on_wave)
	EventBus.item_picked.connect(_on_item_picked)
	EventBus.boss_spawned.connect(_on_boss_spawned)
	EventBus.boss_hp_changed.connect(_on_boss_hp)
	EventBus.boss_died.connect(_on_boss_died)
	EventBus.synergy_formed.connect(_on_synergy)
	var t := Timer.new()
	t.wait_time = 0.5
	t.timeout.connect(_refresh_dps)
	add_child(t)
	t.start()
	_refresh()


func _process(_delta: float) -> void:
	## 波次倒计时：按 GameState.run.time 推进（暂停时 time 不走，倒计时自然停）
	if not _wave_active or _wave_root == null or not _wave_root.visible:
		return
	var remaining: float = _wave_dur - (float(GameState.run.get("time", 0.0)) - _wave_start)
	remaining = maxf(remaining, 0.0)
	_wave_bar.max_value = maxf(_wave_dur, 1.0)
	_wave_bar.value = remaining
	_wave_time_label.text = _fmt_time(remaining)
	# 互斥 1：Boss 在场横幅自动隐藏（Boss 条 y4..20 与横幅 y24..52 分界）
	if _boss_root.visible and _wave_root.visible:
		_wave_active = false
		_wave_root.visible = false


static func _fmt_time(sec: float) -> String:
	var s := maxi(int(ceili(sec)), 0)
	return "%d:%02d" % [s / 60, s % 60]


static func _wave_number_from(text: String) -> int:
	var re := RegEx.create_from_string("(\\d+)")
	var m := re.search(text)
	return int(m.get_string(1)) if m else 0


func _wave_duration_for(num: int) -> float:
	## 波次时长只读自 levels 表（UI 层不持有战斗计时数据）
	var levels: Array = GameState.tables.get("levels", {}).get("levels", [])
	if levels.is_empty():
		return 30.0
	var idx: int = clampi(int(GameState.run.get("level", 1)) - 1, 0, levels.size() - 1)
	var waves: Array = levels[idx].get("waves", [])
	if waves.is_empty():
		return 30.0
	var w: Dictionary = waves[clampi(num - 1, 0, waves.size() - 1)]
	return float(w.get("duration", 30.0))


func _style_bar(bar: ProgressBar, fill_tex: String, h: int = 8) -> void:
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(64, h)
	bar.add_theme_stylebox_override("background", UiTheme.style_compact(Color("#0d0a16"), UiTheme.BORDER_DIM, 2, 2, 2))
	var sb := StyleBoxTexture.new()
	sb.texture = load(fill_tex)
	sb.texture_margin_left = 2
	sb.texture_margin_right = 2
	sb.texture_margin_top = 2
	sb.texture_margin_bottom = 2
	bar.add_theme_stylebox_override("fill", sb)


func _style_flat_bar(bar: ProgressBar, color: Color, h: int = 8) -> void:
	## 纯色血条（玩家 HP/Boss）：无纹理，填充色直接走色板 token
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(64, h)
	bar.add_theme_stylebox_override("background", UiTheme.style_compact(Color("#0d0a16"), UiTheme.BORDER_DIM, 2, 2, 2))
	bar.add_theme_stylebox_override("fill", UiTheme.style_compact(color, Color(0, 0, 0, 0), 0, 0, 0))


func _build_resources(root: Control) -> void:
	## 左上资源区（Brotato 式四行）：右缘 <=185，为顶部波次横幅（x>=186）让位。
	var portrait: bool = UiLayout.is_mobile()
	var hp_size := 11 if portrait else 14        # HP 数字字号
	var bar_h := 10 if portrait else 14          # 血条高度
	var bar_w := 100.0 if portrait else 104.0    # 血条/XP 条宽度（收窄：资源区右缘约束）
	var stat_size := 10 if portrait else 12      # 材料/金币字号
	var small_size := 9                          # 关卡/DPS/攻速小字
	_res_box = VBoxContainer.new()
	_res_box.set_anchors_preset(Control.PRESET_TOP_LEFT)  # expand 下视口变高，顶栏必须贴顶
	_res_box.position = Vector2(8, 24)
	_res_box.add_theme_constant_override("separation", 3 if portrait else 4)
	_res_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_res_box)
	# ① HP 数字 + 血条（护盾灰蓝叠层 + 护盾数值小字，Brotato 式）
	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 6 if portrait else 8)
	_res_box.add_child(hp_row)
	_hp_label = UiTheme.label("100/100", hp_size, UiTheme.WHITE, true)
	hp_row.add_child(_hp_label)
	_hp_bar = ProgressBar.new()
	_style_flat_bar(_hp_bar, UiTheme.HP_RED, bar_h)
	_hp_bar.custom_minimum_size = Vector2(bar_w, bar_h)
	_hp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hp_row.add_child(_hp_bar)
	# 护盾叠层（问题5 保留）：作为 _hp_bar 子节点叠加绘制，value/max = 护盾/最大生命
	_shield_bar = ProgressBar.new()
	_shield_bar.show_percentage = false
	_shield_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shield_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shield_bar.add_theme_stylebox_override("background", StyleBoxEmpty.new())
	_shield_bar.add_theme_stylebox_override("fill", UiTheme.style_compact(UiTheme.SHIELD, Color(0, 0, 0, 0), 0, 3, 0))
	_shield_bar.visible = false
	_hp_bar.add_child(_shield_bar)
	_shield_label = UiTheme.label("", 9, Color("#aebfd8"))
	_shield_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shield_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_shield_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_shield_label.offset_left = -92.0
	_shield_label.offset_right = -2.0
	_shield_label.visible = false
	_hp_bar.add_child(_shield_label)
	# ② 材料：图标 + 金币数（Brotato 材料位直接对应）
	var mat_row := HBoxContainer.new()
	mat_row.add_theme_constant_override("separation", 4)
	_res_box.add_child(mat_row)
	_mat_icon = UiTheme.icon(MAT_ICON_PATH, Vector2(16, 16))
	mat_row.add_child(_mat_icon)
	_gold_label = UiTheme.label("0", stat_size, UiTheme.GOLD, true)
	mat_row.add_child(_gold_label)
	# ③ Lv 徽章 + XP 条同排（Brotato：升级进度常驻可见）
	var xp_row := HBoxContainer.new()
	xp_row.add_theme_constant_override("separation", 6)
	_res_box.add_child(xp_row)
	_lv_badge = PanelContainer.new()
	_lv_badge.custom_minimum_size = Vector2(14, 14)
	_lv_badge.add_theme_stylebox_override("panel", UiTheme.style_compact(UiTheme.GOLD, Color("#8a6a1e"), 1, 3, 0))
	_lv_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	xp_row.add_child(_lv_badge)
	_lv_label = UiTheme.label("1", 9, Color("#3d2a00"), true)
	_lv_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lv_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_lv_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lv_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lv_badge.add_child(_lv_label)
	_xp_bar = ProgressBar.new()
	_style_bar(_xp_bar, "res://assets/ui/hpbar_yellow.png", 6)
	_xp_bar.custom_minimum_size = Vector2(bar_w, 6)
	_xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	xp_row.add_child(_xp_bar)
	# ④ 关卡 · DPS · 攻速（合并一行小字）
	var info_row := HBoxContainer.new()
	info_row.add_theme_constant_override("separation", 8)
	_res_box.add_child(info_row)
	_level_label = UiTheme.label("第 1 关", small_size, Color("#9d8fc4"))
	info_row.add_child(_level_label)
	_dps_label = UiTheme.label("DPS 0", small_size, Color("#9d8fc4"), true)
	info_row.add_child(_dps_label)
	_as_label = UiTheme.label("", small_size, Color("#9d8fc4"))
	info_row.add_child(_as_label)


func _build_wave(root: Control) -> void:
	## 波次横幅：顶部中右（x186..356，y24..52），"第 N 波 + 倒计时 + 金色计时条"。
	## 与 Boss 条（y4..20）按 y 分界互斥；与资源区（右缘<=185）按 x 分界互斥。
	_wave_root = PanelContainer.new()
	_wave_root.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_wave_root.offset_left = -174.0
	_wave_root.offset_right = -4.0
	_wave_root.offset_top = 24.0
	_wave_root.offset_bottom = 52.0
	_wave_root.add_theme_stylebox_override("panel", UiTheme.style_compact(Color(0.1, 0.08, 0.16, 0.8), UiTheme.BORDER_GRAY, 1, 4, 4))
	_wave_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wave_root.visible = false
	root.add_child(_wave_root)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wave_root.add_child(vb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(row)
	_wave_label = UiTheme.label("", 13, UiTheme.GOLD)
	row.add_child(_wave_label)
	_wave_time_label = UiTheme.label("", 13, UiTheme.WHITE, true)
	row.add_child(_wave_time_label)
	_wave_bar = ProgressBar.new()
	_wave_bar.show_percentage = false
	_wave_bar.custom_minimum_size = Vector2(140, 4)
	_wave_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_wave_bar.add_theme_stylebox_override("background", UiTheme.style_compact(Color(0.05, 0.04, 0.09, 0.9), Color(0, 0, 0, 0), 0, 0, 0))
	_wave_bar.add_theme_stylebox_override("fill", UiTheme.style_compact(UiTheme.GOLD, Color(0, 0, 0, 0), 0, 0, 0))
	_wave_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(_wave_bar)


func _build_pickup_label(root: Control) -> void:
	## 屏幕中下：获得道具反馈（图标+名称+×N，Brotato/ui-rag 规范）
	_pickup_root = HBoxContainer.new()
	_pickup_root.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_pickup_root.position = Vector2(-150, -140)
	_pickup_root.custom_minimum_size = Vector2(300, 22)
	_pickup_root.alignment = BoxContainer.ALIGNMENT_CENTER
	_pickup_root.add_theme_constant_override("separation", 6)
	_pickup_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pickup_root.visible = false
	root.add_child(_pickup_root)
	_pickup_icon = UiTheme.icon("", Vector2(16, 16))
	_pickup_icon.visible = false
	_pickup_root.add_child(_pickup_icon)
	_pickup_label = UiTheme.label("", 13, UiTheme.GOLD)
	_pickup_root.add_child(_pickup_label)


func _build_form_banner(root: Control) -> void:
	## 流派成型横幅：顶部居中（y=62，位于波次横幅带 y24..56 之下），2s 渐隐。
	## A2：同流派构筑持有数达 3/6/9 件时触发；每档位只触发一次（_formed_tiers 记录）。
	_form_label = UiTheme.label("", 16, Color(1.0, 0.92, 0.45))
	_form_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_form_label.position = Vector2(-160, 62)
	_form_label.custom_minimum_size = Vector2(320, 26)
	_form_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_form_label.add_theme_stylebox_override("normal", UiTheme.style_compact(Color(0.1, 0.08, 0.16, 0.9), Color(0.85, 0.72, 0.3), 1, 6, 6))
	_form_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_form_label.visible = false
	root.add_child(_form_label)


func _build_boss_bar(root: Control) -> void:
	## 顶部居中 Boss 血条：总宽 <=260（名称 11px + 条 200px），y 4..18，
	## 与下方资源区（y>=24）/波次横幅（y>=24）互不重叠；Boss 出现不隐藏经验条。
	_boss_root = HBoxContainer.new()
	_boss_root.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_boss_root.position = Vector2(-126, 4)
	_boss_root.add_theme_constant_override("separation", 8)
	_boss_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_root.visible = false
	root.add_child(_boss_root)
	_boss_name = UiTheme.label("", 11, UiTheme.RED)
	_boss_root.add_child(_boss_name)
	_boss_bar = ProgressBar.new()
	_boss_bar.show_percentage = false
	_boss_bar.custom_minimum_size = Vector2(200, 12)
	_boss_bar.add_theme_stylebox_override("background", UiTheme.style_compact(Color("#120a14"), UiTheme.BORDER_GRAY, 2, 3, 2))
	_boss_bar.add_theme_stylebox_override("fill", UiTheme.style_compact(UiTheme.BOSS_RED, Color(0, 0, 0, 0), 0, 0, 0))
	_boss_root.add_child(_boss_bar)


func _build_corner_buttons(root: Control) -> void:
	## 左下角按钮：构筑在上、暂停在下；52x52 满足触控最小 44x44，
	## 底部留安全区（safe_bottom=24）。暂停按钮远离技能按钮（技能在右下摇杆区）。
	_build_btn = UiTheme.button("构筑", TOUCH_BTN)
	_build_btn.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_build_btn.position = Vector2(6, -(UiLayout.safe_bottom() + TOUCH_BTN.y * 2.0 + 6.0))
	_build_btn.tooltip_text = "打开构筑面板（法术/装备/饰品）"
	_build_btn.pressed.connect(_toggle_build)
	root.add_child(_build_btn)
	_pause_btn = UiTheme.button("暂停", TOUCH_BTN)
	_pause_btn.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_pause_btn.position = Vector2(6, -(UiLayout.safe_bottom() + TOUCH_BTN.y))
	_pause_btn.tooltip_text = "暂停游戏（Esc）"
	_pause_btn.pressed.connect(_toggle_pause)
	root.add_child(_pause_btn)


func _build_weapon_bar(root: Control) -> void:
	## 底部武器/法术栏（Brotato 核心表达）：PC 5 格单行 / 手机 3+2 两行，
	## 居中于安全带 x64..356（不与左下按钮 x<=60 重叠），底缘距视口底 30px。
	var mobile: bool = UiLayout.is_mobile()
	var slot_sz := 44.0 if mobile else 46.0
	var sep := 6.0
	var slots: int = GameState.tables.get("balance", {}).get("max_grid_slots", 5)
	var bar: Container
	if mobile:
		bar = GridContainer.new()
		(bar as GridContainer).columns = 3  # 3+2 两行
		bar.add_theme_constant_override("h_separation", int(sep))
		bar.add_theme_constant_override("v_separation", int(sep))
	else:
		bar = HBoxContainer.new()
		bar.add_theme_constant_override("separation", int(sep))
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar)
	_weapon_bar = bar
	# 安全带内水平居中（CENTER_BOTTOM 锚点 = 视口底中）
	var rows := 2.0 if mobile else 1.0
	var bar_w: float = (3.0 * slot_sz + 2.0 * sep) if mobile else (float(slots) * slot_sz + float(slots - 1) * sep)
	var bar_h: float = rows * slot_sz + (sep if mobile else 0.0)
	var band_w: float = WEAPON_BAND_RIGHT - WEAPON_BAND_LEFT
	var left: float = WEAPON_BAND_LEFT + (band_w - bar_w) / 2.0
	bar.offset_left = left - UiLayout.DESIGN_W / 2.0
	bar.offset_right = left + bar_w - UiLayout.DESIGN_W / 2.0
	bar.offset_top = -(WEAPON_BOTTOM_GAP + bar_h)
	bar.offset_bottom = -WEAPON_BOTTOM_GAP
	_weapon_slots.clear()
	_refresh_weapon_bar()


func _grid_signature() -> String:
	var parts: Array = []
	for g in GameState.run.get("grid", []):
		parts.append("%s:%s" % [str(g.get("core", "")), str(g.get("shell", ""))])
	return ",".join(parts)


func _refresh_weapon_bar_if_changed() -> void:
	if _weapon_bar == null:
		return
	var sig := _grid_signature()
	if sig == _grid_sig:
		return
	_grid_sig = sig
	_refresh_weapon_bar()


func _refresh_weapon_bar() -> void:
	## 按 GameState.run.grid 重建槽位（图标 + ×N 堆叠角标 + 外壳首字角标）
	if _weapon_bar == null:
		return
	for c in _weapon_bar.get_children():
		c.queue_free()
	_weapon_slots.clear()
	var mobile: bool = UiLayout.is_mobile()
	var slot_sz := 44.0 if mobile else 46.0
	var grid: Array = GameState.run.get("grid", [])
	var slots: int = GameState.tables.get("balance", {}).get("max_grid_slots", 5)
	var counts := {}
	for g in grid:
		var cid: String = str(g.get("core", ""))
		if not cid.is_empty():
			counts[cid] = int(counts.get(cid, 0)) + 1
	for i in slots:
		var core_id := ""
		var shell_id := ""
		if i < grid.size():
			core_id = str(grid[i].get("core", ""))
			shell_id = str(grid[i].get("shell", ""))
		var slot := _make_weapon_slot(core_id, shell_id, i, slot_sz, int(counts.get(core_id, 0)), mobile)
		_weapon_bar.add_child(slot)
		_weapon_slots.append(slot)


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


func _make_weapon_slot(core_id: String, shell_id: String, idx: int, sz: float, count: int, mobile: bool) -> Button:
	var b := Button.new()
	var shell: Dictionary = {}
	UiTheme.apply_font(b, 12)
	b.custom_minimum_size = Vector2(sz, sz)
	b.add_theme_stylebox_override("normal", UiTheme.style_slot(UiTheme.PANEL_SLOT, UiTheme.BORDER_DIM, 1, 3))
	b.add_theme_stylebox_override("hover", UiTheme.style_slot(UiTheme.PANEL_SLOT, UiTheme.BORDER_LIGHT, 1, 3))
	b.add_theme_stylebox_override("pressed", UiTheme.style_slot(UiTheme.PANEL_SLOT, UiTheme.GOLD, 1, 3))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.set_meta("core_id", core_id)
	b.set_meta("slot_index", idx)
	b.pressed.connect(_toggle_build)
	if core_id.is_empty():
		var plus := UiTheme.label("+", 14, Color("#5a5278"))
		plus.set_anchors_preset(Control.PRESET_FULL_RECT)
		plus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		plus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(plus)
		b.tooltip_text = "空法术位（打开构筑面板查看）"
		return b
	var core := _find_core(core_id)
	var icon_sz := 28.0 if mobile else 32.0
	var tex := TextureRect.new()
	tex.texture = UiTheme.icon_texture(str(core.get("icon", "")))
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.custom_minimum_size = Vector2(icon_sz, icon_sz)
	tex.set_anchors_preset(Control.PRESET_CENTER)
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(tex)
	if count > 1:
		var badge := UiTheme.badge("×%d" % count, 9, UiTheme.GOLD)
		badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		badge.position = Vector2(-2, -2)
		b.add_child(badge)
	if not shell_id.is_empty():
		shell = _find_shell(shell_id)
		var sb := UiTheme.badge(str(shell.get("name", "原")).substr(0, 1), 8, Color("#9fb8d8"))
		sb.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		sb.position = Vector2(-2, 0)
		b.add_child(sb)
	b.tooltip_text = "%s · %s\n冷却 %.1fs · 伤害 %.0f\n%s" % [
		core.get("name", core_id),
		shell.get("name", "原生形态") if not shell_id.is_empty() else "原生形态",
		float(core.get("cooldown", 1.0)),
		float(core.get("base_damage", 0.0)),
		str(core.get("description", "")),
	]
	return b


func _pulse_weapon_slot(core_id: String) -> void:
	## 新获得法术：对应格脉冲高亮（item_picked 信号，spell_part 直配）
	for s in _weapon_slots:
		if is_instance_valid(s) and str(s.get_meta("core_id", "")) == core_id:
			var tw := create_tween()
			tw.tween_property(s, "scale", Vector2(1.25, 1.25), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(s, "scale", Vector2.ONE, 0.2)
			break


func _on_boss_spawned(boss_name: String, max_hp: int) -> void:
	_boss_name.text = boss_name
	_boss_bar.max_value = max_hp
	_boss_bar.value = max_hp
	_boss_root.visible = true
	# 互斥 1：Boss 在场波次横幅自动隐藏（不隐藏经验条）
	_wave_active = false
	_wave_root.visible = false


func _on_boss_hp(hp: int, max_hp: int) -> void:
	_boss_bar.max_value = max_hp
	_boss_bar.value = hp


func _on_boss_died(_pos: Vector2 = Vector2.ZERO) -> void:
	_boss_root.visible = false


func _on_synergy(name: String) -> void:
	## 流派成型提示：飘字 + 金色脉冲（保留即时反馈）
	_pickup_icon.visible = false
	_pickup_label.text = "流派成型：%s！" % name
	_pickup_root.visible = true
	_pickup_root.modulate = Color(1.0, 0.9, 0.4)
	_pickup_root.scale = Vector2.ONE
	var tw := create_tween()
	tw.tween_property(_pickup_root, "scale", Vector2(1.3, 1.3), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.4)
	tw.tween_property(_pickup_root, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func(): _pickup_root.visible = false)


func _on_item_picked(item_id: String, stacks: int) -> void:
	## 获得反馈：屏幕中下浮动提示（图标+名称+×N）+ 新法术格脉冲
	var def: Dictionary = GameState.item_def(item_id)
	_pickup_icon.texture = UiTheme.icon_texture(str(def.get("icon", "")))
	_pickup_icon.visible = _pickup_icon.texture != null
	_pickup_label.text = "获得 %s ×%d" % [def.get("name", item_id), stacks]
	_pickup_root.visible = true
	_pickup_root.modulate = Color.WHITE
	var tw := create_tween()
	tw.tween_interval(1.8)
	tw.tween_property(_pickup_root, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func(): _pickup_root.visible = false)
	if str(item_id).begins_with("spell_part:"):
		var parts: PackedStringArray = str(item_id).split(":")
		if parts.size() > 1:
			_pulse_weapon_slot(parts[1])


func _toggle_build() -> void:
	var panel := get_tree().current_scene.get_node_or_null("BuildPanel") as CanvasLayer
	if panel:
		panel.visible = not panel.visible
		if panel.visible and panel.has_method("refresh"):
			panel.refresh()
		if panel.visible and panel.has_method("focus_grid"):
			panel.focus_grid()


func _toggle_pause() -> void:
	var root_node := get_tree().current_scene
	if root_node and root_node.has_method("_toggle_pause"):
		root_node._toggle_pause()


func _on_wave(state: String) -> void:
	## 波次横幅：波次开始 → 显示横幅并启动倒计时；其余（Boss/clear）隐藏。
	if state.contains("来袭"):
		var n := _wave_number_from(state)
		_wave_label.text = "第 %d 波" % n
		_wave_dur = _wave_duration_for(n)
		_wave_start = float(GameState.run.get("time", 0.0))
		_wave_active = true
		_wave_bar.max_value = maxf(_wave_dur, 1.0)
		_wave_bar.value = _wave_dur
		_wave_time_label.text = _fmt_time(_wave_dur)
		_wave_root.visible = true
		_wave_root.modulate = Color.WHITE
		return
	_wave_active = false
	_wave_root.visible = false


func _refresh() -> void:
	if GameState.run.is_empty():
		return
	var hp: int = GameState.run.get("hp", 0)
	var max_hp: int = GameState.run.get("max_hp", 100)
	_hp_label.text = "%d/%d" % [hp, max_hp]
	_hp_bar.max_value = max_hp
	_hp_bar.value = hp
	_update_shield_display()
	var lv: int = GameState.run.get("player_level", 1)
	_lv_label.text = str(lv)
	if _xp_bar != null:
		var xp: int = GameState.run.get("xp", 0)
		var need: int = GameState.xp_to_next(lv)
		_xp_bar.max_value = maxf(need, 1)
		_xp_bar.value = xp
	_gold_label.text = str(GameState.run.get("gold", 0))
	if _as_label != null:
		var as_pct: int = GameState.attack_speed_pct()
		_as_label.text = "攻速+%d%%" % as_pct if as_pct > 0 else ""
	if _level_label != null:
		var lvl: int = GameState.run.get("level", 1)
		_level_label.text = "第 %d 关" % lvl
	_refresh_weapon_bar_if_changed()
	_check_form_tiers()


func _check_form_tiers() -> void:
	## 流派成型自检（A2）：GameState 只提供 school_holdings 计数，阈值 3/6/9 在此判定。
	## 持有数跨档（如 2→3、5→6、8→9）时每档触发一次横幅，重复刷新不重触发。
	if GameState.run.is_empty() or _form_label == null:
		return
	var holdings: Dictionary = GameState.school_holdings()
	for school in holdings:
		var n: int = int(holdings[school])
		for tier in [3, 6, 9]:
			if n < tier:
				break
			var key: String = "%s:%d" % [school, tier]
			if _formed_tiers.has(key):
				continue
			_formed_tiers[key] = true
			_form_banner_count += 1
			_show_form_banner(school, tier, n)


func _show_form_banner(school: String, tier: int, n: int) -> void:
	## 顶部居中横幅：弹出放大 + 停留 2s + 渐隐（设计 A2 全屏小横幅）
	var sname: String = GameState.SCHOOL_NAMES.get(school, school)
	_form_label.text = "流派成型：%s Lv.%d（%d 件）" % [sname, tier, n]
	_form_label.visible = true
	_form_label.modulate = Color(1.0, 0.92, 0.45)
	_form_label.scale = Vector2.ONE
	var tw := create_tween()
	tw.tween_property(_form_label, "scale", Vector2(1.12, 1.12), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.6)
	tw.tween_property(_form_label, "modulate:a", 0.0, 0.6)
	tw.tween_callback(func(): _form_label.visible = false)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F8:
		_dump_layout()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_TAB and not UiLayout.is_mobile():
		_toggle_build()
		get_viewport().set_input_as_handled()


func _dump_layout() -> void:
	## F8 布局自检（供 CDP 像素断言）：输出关键控件 rect
	for pair in [["HP", _hp_bar], ["LV", _lv_label], ["DPS", _dps_label], ["BOSS", _boss_root],
			["WAVE", _wave_root], ["XP", _xp_bar], ["PICKUP", _pickup_root],
			["BUILD_BTN", _build_btn], ["PAUSE_BTN", _pause_btn], ["WEAPON", _weapon_bar]]:
		var node = pair[1]
		if node:
			print("[LAYOUT] %s=%s" % [pair[0], str(node.get_global_rect())])


func _refresh_dps() -> void:
	if GameState.run.is_empty():
		return
	## 问题6：HUD 显示实测 DPS（5s 滑动窗口），构筑面板保留理论估算
	_dps_label.text = "DPS %d" % int(GameState.measured_dps())
	_update_shield_display()  # 护盾池可能在无 player_stats_changed 的路径变化（如换局重置），0.5s 定时兜底


func _update_shield_display() -> void:
	if _shield_bar == null or GameState.run.is_empty():
		return
	var shield := roundi(_shield_value())
	_shield_bar.max_value = maxf(float(GameState.run.get("max_hp", 100)), 1.0)
	_shield_bar.value = shield
	_shield_bar.visible = shield > 0
	_shield_label.text = "护盾 %d" % shield
	_shield_label.visible = shield > 0


## 护盾显示（问题5）：护盾池在 defense_synergy._shield（synergy 内部状态，非 run 字段），
## HUD 只读查询：按脚本路径定位节点，未挂载（如 headless 测试场景）时返回 0
func _shield_value() -> float:
	var src := _shield_source_node()
	if src == null:
		return 0.0
	var v = src.get("_shield")
	return 0.0 if v == null else float(v)


func _shield_source_node() -> Node:
	if _shield_source != null and is_instance_valid(_shield_source):
		return _shield_source
	_shield_source = _find_synergy_node(get_tree().root)
	return _shield_source


func _find_synergy_node(node: Node) -> Node:
	var script: Script = node.get_script()
	if script != null and script.resource_path == SHIELD_SCRIPT_PATH:
		return node
	for child in node.get_children():
		var hit := _find_synergy_node(child)
		if hit != null:
			return hit
	return null
