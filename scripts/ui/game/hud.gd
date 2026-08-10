extends CanvasLayer
## HUD（竖版 360x640 重排，2026-08-09）：
## 依据 docs/design/ui-design.md + ui-rag：
##  - 左上资源条压缩为单行紧凑（HP 数字+条 / Lv / 金币 / DPS 小字），位于
##    Boss 血条带（y 4..20）下方 y=24，避免重叠；
##  - 波次提示放顶部中央下方（右上角 y=26，宽度 100，与资源条/Boss 条不重叠）；
##  - Boss 血条：顶部居中，总宽 <=260（名称 11px + 条 200px），y 4..18；
##  - 左下角按钮 52x52（>= 触控最小 44），构筑在上、暂停在下，尊重底部安全区；
##  - 获得提示（拾取/流派）屏幕中下 y 478..500，不挡左下按钮；
##  - 信息密度低：经验条/击杀数等次要信息折叠（升级时有三选一弹层反馈）。
## 坐标尽量通过 UiLayout 常量取值；横竖自适应接口见 scripts/ui/ui_layout.gd。
const UiLayout := preload("res://scripts/ui/ui_layout.gd")

const TOUCH_BTN := Vector2(UiLayout.TOUCH_MIN + 8, UiLayout.TOUCH_MIN + 8)  # 52x52

var _hp_bar: ProgressBar
var _hp_label: Label
var _xp_bar: ProgressBar
var _lv_label: Label
var _gold_label: Label
var _dps_label: Label
var _level_label: Label
var _res_box: BoxContainer
var _wave_label: Label
var _boss_bar: ProgressBar
var _boss_name: Label
var _boss_root: HBoxContainer
var _pickup_label: Label
var _build_btn: Button
var _pause_btn: Button

func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_resources(root)
	_build_wave(root)
	_build_pickup_label(root)
	_build_corner_buttons(root)
	_build_boss_bar(root)
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

func _build_resources(root: Control) -> void:
	## 左上资源条（y=24，位于 Boss 血条带下方）：三行 VBox（PC 与手机统一布局）——
	## ① HP 数字+血条 ② Lv·金币·DPS ③ 当前关卡。
	## PC 端血条/字号更大；手机端紧凑（小字号窄条，避免遮挡战斗视野）。
	var portrait: bool = UiLayout.is_portrait()
	var hp_size := 11 if portrait else 14        # HP 数字字号
	var bar_h := 10 if portrait else 14          # 血条高度
	var bar_w := 110 if portrait else 200        # 血条宽度
	var stat_size := 10 if portrait else 12      # Lv/金币 字号
	var dps_size := 9 if portrait else 11        # DPS 字号
	_res_box = VBoxContainer.new()
	_res_box.set_anchors_preset(Control.PRESET_TOP_LEFT)  # expand 下视口变高，顶栏必须贴顶
	_res_box.position = Vector2(8, 24)
	_res_box.add_theme_constant_override("separation", 3 if portrait else 5)
	_res_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_res_box)
	# 第 1 行：HP 数字 + 血条
	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 6 if portrait else 8)
	_res_box.add_child(hp_row)
	_hp_label = UiTheme.label("100/100", hp_size, UiTheme.WHITE, true)
	hp_row.add_child(_hp_label)
	_hp_bar = ProgressBar.new()
	_style_bar(_hp_bar, "res://assets/ui/hpbar_blue.png", bar_h)
	_hp_bar.custom_minimum_size = Vector2(bar_w, bar_h)
	_hp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hp_row.add_child(_hp_bar)
	# 第 2 行：Lv / 金币 / DPS
	var stat_row := HBoxContainer.new()
	stat_row.add_theme_constant_override("separation", 10)
	_res_box.add_child(stat_row)
	_lv_label = UiTheme.label("Lv.1", stat_size, UiTheme.GOLD, true)
	stat_row.add_child(_lv_label)
	# 第 2.5 行：经验条（Lv 下方，黄色细条）
	_xp_bar = ProgressBar.new()
	_style_bar(_xp_bar, "res://assets/ui/hpbar_yellow.png", 6)
	_xp_bar.custom_minimum_size = Vector2(bar_w, 6)
	_xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_res_box.add_child(_xp_bar)
	_gold_label = UiTheme.label("金币 0", stat_size, UiTheme.GOLD)
	stat_row.add_child(_gold_label)
	_dps_label = UiTheme.label("DPS 0", dps_size, Color("#9d8fc4"), true)
	stat_row.add_child(_dps_label)
	# 第 3 行：当前关卡
	_level_label = UiTheme.label("第 1 关", stat_size, Color("#9d8fc4"))
	_res_box.add_child(_level_label)

func _build_wave(root: Control) -> void:
	## 波次提示：顶部中央下方（右上角 y=26，Boss 血条带下方），不与资源条重叠。
	_wave_label = UiTheme.label("", 12, UiTheme.GOLD)
	_wave_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_wave_label.position = Vector2(-100, 26)
	_wave_label.custom_minimum_size = Vector2(100, 20)
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_wave_label.add_theme_stylebox_override("normal", UiTheme.style_compact(Color(0.1, 0.08, 0.16, 0.8), UiTheme.BORDER_DIM, 1, 4, 4))
	_wave_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wave_label.visible = false
	root.add_child(_wave_label)

func _build_pickup_label(root: Control) -> void:
	## 屏幕中下：获得道具反馈（不挡左下按钮/右下摇杆区）。
	_pickup_label = UiTheme.label("", 13, UiTheme.GOLD)
	_pickup_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_pickup_label.position = Vector2(-150, -140)
	_pickup_label.custom_minimum_size = Vector2(300, 22)
	_pickup_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pickup_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pickup_label.visible = false
	root.add_child(_pickup_label)

func _build_boss_bar(root: Control) -> void:
	## 顶部居中 Boss 血条：总宽 <=260（名称 11px + 条 200px），y 4..18，
	## 与下方资源条（y>=24）/波次提示（y>=26）互不重叠。
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
	_boss_bar.add_theme_stylebox_override("background", UiTheme.style_compact(Color("#120a14"), Color("#5a2a44"), 2, 3, 2))
	var fill := StyleBoxTexture.new()
	fill.texture = load("res://assets/ui/hpbar_red.png")
	fill.texture_margin_left = 2
	fill.texture_margin_right = 2
	fill.texture_margin_top = 2
	fill.texture_margin_bottom = 2
	_boss_bar.add_theme_stylebox_override("fill", fill)
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


func _on_boss_spawned(boss_name: String, max_hp: int) -> void:
	_boss_name.text = boss_name
	_boss_bar.max_value = max_hp
	_boss_bar.value = max_hp
	_boss_root.visible = true

func _on_boss_hp(hp: int, max_hp: int) -> void:
	_boss_bar.max_value = max_hp
	_boss_bar.value = hp

func _on_boss_died(_pos: Vector2 = Vector2.ZERO) -> void:
	_boss_root.visible = false

func _on_synergy(name: String) -> void:
	## 流派成型提示：飘字 + 金色脉冲（保留即时反馈）。
	_pickup_label.text = "流派成型：%s！" % name
	_pickup_label.visible = true
	_pickup_label.modulate = Color(1.0, 0.9, 0.4)
	_pickup_label.scale = Vector2.ONE
	var tw := create_tween()
	tw.tween_property(_pickup_label, "scale", Vector2(1.3, 1.3), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.4)
	tw.tween_property(_pickup_label, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func(): _pickup_label.visible = false)


func _on_item_picked(item_id: String, stacks: int) -> void:
	## 获得反馈：屏幕中下浮动提示（另有新物品格子高亮脉冲）。
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
	var root_node := get_tree().current_scene
	if root_node and root_node.has_method("_toggle_pause"):
		root_node._toggle_pause()


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
	if _xp_bar != null:
		var xp: int = GameState.run.get("xp", 0)
		var need: int = GameState.xp_to_next(lv)
		_xp_bar.max_value = maxf(need, 1)
		_xp_bar.value = xp
	_gold_label.text = "金币 %d" % GameState.run.get("gold", 0)
	if _level_label != null:
		var lvl: int = GameState.run.get("level", 1)
		_level_label.text = "第 %d 关" % lvl

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F8:
		_dump_layout()

func _dump_layout() -> void:
	## F8 布局自检（供 CDP 像素断言）：输出关键控件 rect
	for pair in [["HP", _hp_bar], ["LV", _lv_label], ["DPS", _dps_label], ["BOSS", _boss_root], ["PICKUP", _pickup_label], ["BUILD_BTN", _build_btn], ["PAUSE_BTN", _pause_btn]]:
		var node = pair[1]
		if node:
			print("[LAYOUT] %s=%s" % [pair[0], str(node.get_global_rect())])


func _refresh_dps() -> void:
	if GameState.run.is_empty():
		return
	_dps_label.text = "DPS %d" % int(GameState.estimate_dps())
