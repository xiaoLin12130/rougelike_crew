extends SceneTree
## 构筑面板布局回归测试（2026-08-12，修复"装备盖住法术序列"错位）：
## ① 法术序列区（5 格单行）完整位于装备/饰品区上方，各区域边界互不相交；
## ② 法术序列 5 格齐全、单行排列、格子互不重叠；
## ③ 面板内所有 Label 文本无 "?" 码点（含 ×/中文首字的角标走中文字体）；
## ④ UiTheme.badge 按内容选字体：非 ASCII（×/中文）用中文字体，纯数字保留像素字体。
## Run: godot --headless --path . -s res://scripts/tests/test_build_panel_layout.gd

var failures: Array[String] = []
var _frame := 0
var _phase := 0
var _panel: CanvasLayer

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false
	match _phase:
		0:
			_setup()
			_phase = 1
		1:
			_assert_layout()
			_assert_no_codepoint()
			_assert_badge_font()
			if failures.is_empty():
				print("BUILD PANEL LAYOUT OK")
			else:
				for f in failures:
					push_error("BUILD PANEL FAIL: " + f)
			quit(0 if failures.is_empty() else 1)
			return true
	return false

func fail(msg: String) -> void:
	failures.append(msg)

func _setup() -> void:
	root.size = Vector2i(360, 640)
	var gs: Node = root.get_node("GameState")
	gs.new_run()
	gs.run.grid = [
		{"core": "fireball", "shell": ""},
		{"core": "fireball", "shell": "rapid"},   # 同核心 ×2 → 右下角标
		{"core": "ice_shard", "shell": "spread"}, # 外壳首字角标（中文 → 中文字体）
		{"core": "whirl_blade", "shell": "homing"},
	]
	gs.run.items = {"strength_badge": 3, "lucky_clover": 1}
	gs.run.trinkets = ["trinket_ember", "trinket_frost"]
	_panel = load("res://scenes/ui/build_panel.tscn").instantiate()
	_panel.name = "BuildPanel"
	root.add_child(_panel)
	_panel.refresh()

func _rect(c: Control) -> Rect2:
	return c.get_global_rect()

func _assert_layout() -> void:
	var grid := _rect(_panel._grid_box)
	var items := _rect(_panel._items_box)
	var trinkets := _rect(_panel._trinkets_box)
	print("[RECTS] grid=%s items=%s trinkets=%s" % [str(grid), str(items), str(trinkets)])
	# ① 法术区在上、装备/饰品在下：区域边界不相交，且顺序正确
	if grid.intersects(items):
		fail("法术网格与装备区重叠: grid=%s items=%s" % [str(grid), str(items)])
	if grid.intersects(trinkets):
		fail("法术网格与饰品区重叠: grid=%s trinkets=%s" % [str(grid), str(trinkets)])
	if grid.end.y > items.position.y + 0.5:
		fail("法术网格未完整位于装备区上方: grid_end_y=%f items_y=%f" % [grid.end.y, items.position.y])
	if items.end.y > trinkets.position.y + 0.5:
		fail("装备区未完整位于饰品区上方: items_end_y=%f trinkets_y=%f" % [items.end.y, trinkets.position.y])
	# ② 法术序列 5 格完整、单行、互不重叠
	var slots: Array = []
	for c in _panel._grid_box.get_children():
		if c is Button and not c.is_queued_for_deletion():
			slots.append(c)
	if slots.size() != 5:
		fail("法术序列格数 != 5: " + str(slots.size()))
		return
	var y0 := -1.0
	for s in slots:
		var r := _rect(s)
		if y0 < 0:
			y0 = r.position.y
		elif absf(r.position.y - y0) > 2.0:
			fail("法术序列未单行排列: " + str(r))
	for i in slots.size():
		for j in range(i + 1, slots.size()):
			if _rect(slots[i]).intersects(_rect(slots[j])):
				fail("法术格 %d 与 %d 重叠" % [i, j])
	# 语义顺序：法术序列标题在装备标题之上（VBox 顺序守卫）
	var spell_title_y := -1.0
	var item_title_y := -1.0
	var labels: Array = []
	_collect_labels(_panel, labels)
	for l in labels:
		var t: String = (l as Label).text
		if t.contains("法术序列"):
			spell_title_y = (l as Control).get_global_rect().position.y
		elif t == "装备（点击查看详情）":
			item_title_y = (l as Control).get_global_rect().position.y
	if spell_title_y < 0.0 or item_title_y < 0.0:
		fail("未找到法术序列/装备分区标题")
	elif item_title_y <= spell_title_y:
		fail("装备分区标题未位于法术序列之下: spell_y=%f item_y=%f" % [spell_title_y, item_title_y])

func _collect_labels(node: Node, out: Array) -> void:
	if node is Label:
		out.append(node)
	for ch in node.get_children():
		_collect_labels(ch, out)

func _assert_no_codepoint() -> void:
	## ③ 遍历面板全部 Label：文本不得含 "?"（码点）或 U+FFFD
	var labels: Array = []
	_collect_labels(_panel, labels)
	var bad: Array = []
	for l in labels:
		var t: String = (l as Label).text
		if t.contains("?") or t.contains("\uFFFD"):
			bad.append(t)
	if not bad.is_empty():
		fail("构筑面板存在码点文本: " + str(bad))

func _assert_badge_font() -> void:
	## ④ badge 按内容选字体：非 ASCII 必须落在含该字形的字体上
	var b1 := UiTheme.badge("×2", 9, UiTheme.GOLD)          # × → 中文字体
	var b2 := UiTheme.badge("迅", 8, Color("#9fb8d8"))      # 中文首字 → 中文字体
	var b3 := UiTheme.badge("12", 9, UiTheme.GOLD)          # 纯数字 → 像素字体
	if not ((b1.get_theme_font("font") as Font).has_char("×".unicode_at(0))):
		fail("badge ×2 未使用含 × 字形的字体")
	if not ((b2.get_theme_font("font") as Font).has_char("迅".unicode_at(0))):
		fail("badge 中文首字未使用中文字体")
	if (b3.get_theme_font("font") as Font).has_char("迅".unicode_at(0)):
		fail("badge 纯数字应保留像素数字字体")
