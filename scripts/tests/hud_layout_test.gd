extends SceneTree
## HUD v2 布局回归测试（headless）：
##  - 构筑条不超屏宽、不与 DPS 重叠；
##  - Boss 血条与左上资源/右上波次横幅互不重叠；
##  - 物品格子包含 图标+名称+层数 且可点开详情；
##  - 法术格可点开详情；构筑条可折叠；
##  - 触屏按钮逻辑尺寸 >= 22px（2x 窗口 = 44 物理 px）。
## Run: godot --headless --path . -s res://scripts/tests/hud_layout_test.gd

var failures: Array[String] = []
var _frame := 0
var _phase := 0
var _hud: CanvasLayer
var _gs: Node
var _bus: Node

func _gs_node() -> Node:
	return root.get_node("GameState")

func _bus_node() -> Node:
	return root.get_node("EventBus")

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	match _phase:
		0:
			_setup_run()
			_hud = load("res://scenes/ui/hud.tscn").instantiate()
			_hud.name = "HUD"
			root.add_child(_hud)
			_phase = 1
		1:
			_assert_layout()
			_assert_detail()
			_assert_collapse()
			_phase = 2
		2:
			if failures.is_empty():
				print("HUD LAYOUT OK")
			else:
				for f in failures:
					push_error("HUD FAIL: " + f)
			quit(0 if failures.is_empty() else 1)
			return true
	return false

func fail(msg: String) -> void:
	failures.append(msg)

func _setup_run() -> void:
	_gs = _gs_node()
	_bus = _bus_node()
	_gs.new_run()
	_gs.run.items = {
		"attack_speed_potion": 2,
		"strength_badge": 3,
		"lucky_clover": 1,
	}
	_gs.run.last_picked = "lucky_clover"
	_gs.run.grid = [
		{"core": "fireball", "shell": ""},
		{"core": "whirl_blade", "shell": "rapid"},
	]

func _rect(c: Control) -> Rect2:
	return c.get_global_rect()

func _assert_layout() -> void:
	var bar_rect := _rect(_hud._bar_root)
	if bar_rect.size.x > 640.0:
		fail("构筑条超屏宽: %.0f > 640" % bar_rect.size.x)
	if _rect(_hud._bar_root).intersects(_rect(_hud._dps_label)):
		fail("构筑条与 DPS 重叠")
	# Boss 血条 vs 左上资源 / 右上波次横幅
	_bus.boss_spawned.emit("暗影魔像", 500)
	_hud._on_wave("波次 3 来袭")
	if not _hud._boss_root.visible:
		fail("Boss 血条未显示")
	if _rect(_hud._boss_root).intersects(_rect(_hud._res_box)):
		fail("Boss 血条与左上资源重叠: boss=%s res=%s" % [_rect(_hud._boss_root), _rect(_hud._res_box)])
	if _rect(_hud._boss_root).intersects(_rect(_hud._wave_label)):
		fail("Boss 血条与波次横幅重叠")
	# 触屏按钮尺寸（逻辑 >= 22px，2x 下即 44 物理 px）
	for b in [_hud._tab_btn, _hud._bar_box.get_child(_hud._bar_box.get_child_count() - 2),
			_hud._bar_box.get_child(_hud._bar_box.get_child_count() - 1)]:
		if b is Button and _rect(b).size.y < 22.0:
			fail("按钮过小(<22px): " + str(_rect(b).size.y))
	# 物品格：应有 3 个，含图标+名称+层数文本
	var n: int = _hud._items_box.get_child_count()
	if n != 3:
		fail("物品格数量异常: %d != 3" % n)
	var found_count := false
	for slot in _hud._items_box.get_children():
		if slot is Button:
			for l in _labels(slot):
				if "×" in l.text:
					found_count = true
	if not found_count:
		fail("物品格缺少层数(×N)文本")
	# 法术格数量
	if _hud._grid_box.get_child_count() != 5:
		fail("法术格数量异常: %d != 5" % _hud._grid_box.get_child_count())

func _labels(node: Node) -> Array[Label]:
	var out: Array[Label] = []
	for c in node.get_children():
		if c is Label:
			out.append(c)
		out.append_array(_labels(c))
	return out

func _assert_detail() -> void:
	_hud._on_item_slot_clicked("strength_badge", 3)
	if not _hud._detail_panel.visible:
		fail("物品详情未弹出")
	elif not ("力量徽章 ×3" in _hud._detail_title.text):
		fail("物品详情标题错误: " + _hud._detail_title.text)
	elif not ("攻击" in _hud._detail_desc.text):
		fail("物品详情描述缺失")
	_hud._hide_detail()
	_hud._on_grid_slot_clicked(0)
	if not _hud._detail_panel.visible:
		fail("法术详情未弹出")
	elif not ("火球" in _hud._detail_title.text):
		fail("法术详情标题错误: " + _hud._detail_title.text)
	_hud._hide_detail()

func _assert_collapse() -> void:
	_hud._toggle_bar()
	if _hud._bar_root.visible:
		fail("折叠后构筑条仍可见")
	_hud._toggle_bar()
	if not _hud._bar_root.visible:
		fail("展开后构筑条不可见")
