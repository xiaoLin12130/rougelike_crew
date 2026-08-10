extends SceneTree
## 图鉴系统测试（P3，2026-08-10）：
## ① 收集记录：mark_collected 后 collection_of/is_collected 生效；重复标记去重；
##    非法分类 / 空 id 不写入；add_item/add_wand/replace_wand/add_spell_part
##    （召唤核心联动召唤物）触发点均记录；
## ② 面板渲染：已收集条目显示名称（非"？？？"）+ 稀有度描边 + 点击弹详情（含描述）；
##    未收集条目名称"？？？"、图标 modulate 压黑 Color(0,0,0,0.6)、无描述、点击无详情；
##    分类切换后网格条目数与数据表一致（法杖 55 / 核心 15 / 外壳 10 / 装备 274+ / 召唤 10）；
## ③ 持久化：mark_collected 落盘 → 清空内存 → load_collection 恢复完整；
##    SaveStore 直接 round-trip 完整；new_run 不重置收集（跨局图鉴进度）；
## ④ 主菜单：图鉴按钮存在、触控区 >=44、与其他按钮不重叠、按下可打开面板。
## Run: godot --headless --path . -s res://scripts/tests/test_collection.gd

var failures: Array[String] = []
var _frame := 0

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false
	_run_all()
	if failures.is_empty():
		print("ALL PASS")
	else:
		for f in failures:
			push_error("COLLECTION FAIL: " + f)
	quit(0 if failures.is_empty() else 1)
	return true

func fail(msg: String) -> void:
	failures.append(msg)
	print("[COLLECTION] FAIL: " + msg)

func _gs() -> Node:
	return root.get_node_or_null("GameState")

func _store() -> Node:
	return root.get_node_or_null("SaveStore")

func _def_of(category: String, id: String) -> Dictionary:
	## 与面板同源的只读数据表查询（测试用）
	var gs := _gs()
	match category:
		"wands":
			return gs.wand_def(id)
		"items":
			return gs.item_def(id)
		"cores":
			for c in gs.tables.get("spells", {}).get("cores", []):
				if str(c.get("id", "")) == id:
					return c
		"shells":
			for c in gs.tables.get("spells", {}).get("shells", []):
				if str(c.get("id", "")) == id:
					return c
		"summons":
			for c in gs.tables.get("summons", {}).get("summons", []):
				if str(c.get("id", "")) == id:
					return c
	return {}

func _live_cells(panel: CanvasLayer) -> Array:
	## 网格中未排队删除的条目格（queue_free 的旧格子在同帧内仍在 children 中）
	var out: Array = []
	for c in panel._grid.get_children():
		if not c.is_queued_for_deletion():
			out.append(c)
	return out

func _find_cell(panel: CanvasLayer, id: String) -> Control:
	for c in _live_cells(panel):
		if str(c.get_meta("entry_id", "")) == id:
			return c
	return null

func _first_uncollected(panel: CanvasLayer) -> Control:
	for c in _live_cells(panel):
		if not bool(c.get_meta("collected", false)):
			return c
	return null

func _cell_name(cell: Control) -> String:
	## 条目格内第一个 Label 的文本（名称行）
	if cell is Label:
		return str((cell as Label).text)
	for ch in cell.get_children():
		var t := _cell_name(ch)
		if t != "":
			return t
	return ""

func _cell_icon(cell: Control) -> TextureRect:
	if cell is TextureRect:
		return cell
	for ch in cell.get_children():
		var t := _cell_icon(ch)
		if t != null:
			return t
	return null

func _cell_has_text(cell: Control, needle: String) -> bool:
	if cell is Label and str((cell as Label).text).contains(needle):
		return true
	for ch in cell.get_children():
		if _cell_has_text(ch, needle):
			return true
	return false

func _click(cell: Control) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	cell.gui_input.emit(ev)

func _switch_tab(panel: CanvasLayer, idx: int) -> void:
	panel._tabs[idx].pressed.emit()

func _run_all() -> void:
	var gs := _gs()
	if gs == null:
		fail("GameState autoload missing")
		return
	# ---- 准备：物理删档 + 清内存，隔离环境 ----
	_store().clear_collection()
	gs.collection = {}
	# ---- 数据表计数契约（图鉴条目来源）----
	var t: Dictionary = gs.tables
	if t.get("wands", {}).get("wands", []).size() != 55:
		fail("法杖条目 != 55: %d" % t.get("wands", {}).get("wands", []).size())
	if t.get("spells", {}).get("cores", []).size() != 15:
		fail("法术核心 != 15: %d" % t.get("spells", {}).get("cores", []).size())
	if t.get("spells", {}).get("shells", []).size() != 10:
		fail("法术外壳 != 10: %d" % t.get("spells", {}).get("shells", []).size())
	if t.get("items", {}).get("items", []).size() < 274:
		fail("装备饰品 < 274: %d" % t.get("items", {}).get("items", []).size())
	if t.get("summons", {}).get("summons", []).size() != 10:
		fail("召唤物 != 10: %d" % t.get("summons", {}).get("summons", []).size())
	# ---- ① 收集记录 ----
	gs.mark_collected("wands", "fire_staff")
	gs.mark_collected("wands", "fire_staff")  # 重复标记应去重
	gs.mark_collected("cores", "fireball")
	gs.mark_collected("shells", "rapid")
	gs.mark_collected("items", "attack_speed_potion")
	gs.mark_collected("summons", "bat")
	gs.mark_collected("nope", "x")  # 非法分类
	gs.mark_collected("items", "")   # 空 id
	if gs.collection_of("wands").size() != 1 or not gs.is_collected("wands", "fire_staff"):
		fail("mark_collected/去重失败: %s" % str(gs.collection_of("wands")))
	if not gs.is_collected("cores", "fireball"):
		fail("核心 fireball 未记录")
	if not gs.is_collected("shells", "rapid"):
		fail("外壳 rapid 未记录")
	if not gs.is_collected("summons", "bat"):
		fail("召唤物 bat 未记录")
	if gs.collection_of("items").size() != 1:
		fail("非法分类/空 id 不应写入: %s" % str(gs.collection_of("items")))
	# 触发点联动：add_item / add_wand / replace_wand / add_spell_part（召唤核心 → 召唤物）
	gs.add_item("vampire_fang")
	if not gs.is_collected("items", "vampire_fang"):
		fail("add_item 未触发收集")
	gs.add_wand("ice_staff")
	if not gs.is_collected("wands", "ice_staff"):
		fail("add_wand 未触发收集")
	gs.replace_wand(0, "phoenix_staff")
	if not gs.is_collected("wands", "phoenix_staff"):
		fail("replace_wand 未触发收集")
	gs.add_spell_part("summon_bat", "rapid")
	if not gs.is_collected("cores", "summon_bat"):
		fail("add_spell_part 未记录召唤核心")
	if not gs.is_collected("shells", "rapid"):
		fail("add_spell_part 未记录外壳")
	if not gs.is_collected("summons", "bat"):
		fail("召唤核心未联动记录召唤物 bat")
	# ---- ② 面板渲染 ----
	var panel: CanvasLayer = load("res://scripts/ui/collection_panel.tscn").instantiate()
	panel.name = "CollectionPanel"
	root.add_child(panel)
	_assert_panel_rendering(panel)
	# ---- ③ 持久化 ----
	gs.mark_collected("items", "strength_badge")
	var expect_items: Array = gs.collection_of("items")
	var expect_wands: Array = gs.collection_of("wands")
	gs.collection = {}  # 模拟内存丢失
	gs.load_collection()
	if gs.collection_of("items") != expect_items:
		fail("重载后 items 不完整: %s != %s" % [str(gs.collection_of("items")), str(expect_items)])
	if gs.collection_of("wands") != expect_wands:
		fail("重载后 wands 不完整: %s != %s" % [str(gs.collection_of("wands")), str(expect_wands)])
	if not gs.is_collected("cores", "fireball") or not gs.is_collected("shells", "rapid") \
			or not gs.is_collected("summons", "bat"):
		fail("重载后 cores/shells/summons 不完整")
	# SaveStore 直接 round-trip：写入后重新 load 数据完整
	_store().save_collection(gs.collection)
	var raw: Dictionary = _store().load_collection()
	if raw.get("version", 0) != 1:
		fail("collection.json 缺 version 字段")
	var cats: Dictionary = raw.get("categories", {})
	if not (cats is Dictionary) or not (cats.get("items", []) is Array):
		fail("collection.json categories 结构错误")
	if not str(cats.get("items", [])).contains("strength_badge"):
		fail("SaveStore round-trip 缺 strength_badge")
	# new_run 不重置收集（图鉴进度跨局）
	gs.new_run()
	if not gs.is_collected("items", "vampire_fang") or not gs.is_collected("wands", "fire_staff"):
		fail("new_run 重置了图鉴收集")
	# 二次重载（模拟重启）仍完整
	gs.collection = {}
	gs.load_collection()
	if not gs.is_collected("wands", "fire_staff") or not gs.is_collected("cores", "fireball") \
			or not gs.is_collected("shells", "rapid") or not gs.is_collected("summons", "bat") \
			or not gs.is_collected("items", "strength_badge"):
		fail("二次重载后收集不完整")
	# ---- ④ 主菜单 ----
	_assert_main_menu()
	panel.queue_free()

func _assert_panel_rendering(panel: CanvasLayer) -> void:
	## 初始分类 = 法杖：55 格；已收集 fire_staff 显示名称+稀有度描边+点击弹详情；
	## 未收集条目"？？？"+压黑图标+无描述+点击无详情
	var gs := _gs()
	if _live_cells(panel).size() != 55:
		fail("法杖网格条目 != 55: %d" % _live_cells(panel).size())
	var fc := _find_cell(panel, "fire_staff")
	if fc == null:
		fail("已收集法杖 fire_staff 格子缺失")
	else:
		if _cell_name(fc) != "烈焰法杖":
			fail("已收集名称错误: %s" % _cell_name(fc))
		var sb: StyleBoxFlat = fc.get_theme_stylebox("panel")
		if sb == null or sb.border_color != UiTheme.RARITY["common"]:
			fail("已收集条目稀有度描边错误: %s" % (str(sb.border_color) if sb != null else "null"))
		_click(fc)
		if not panel._detail.visible:
			fail("已收集条目点击未弹详情")
		elif not str(panel._detail_body.text).contains("爆发形态"):
			fail("已收集详情缺描述: %s" % str(panel._detail_body.text))
	var unc := _first_uncollected(panel)
	if unc == null:
		fail("未找到未收集法杖条目")
	else:
		if _cell_name(unc) != "？？？":
			fail("未收集名称 != ？？？: %s" % _cell_name(unc))
		var icon := _cell_icon(unc)
		if icon == null or icon.modulate != Color(0, 0, 0, 0.6):
			fail("未收集图标未压黑: %s" % (str(icon.modulate) if icon != null else "null"))
		var uid := str(unc.get_meta("entry_id", ""))
		var udef := _def_of("wands", uid)
		if not str(udef.get("description", "")).is_empty() and _cell_has_text(unc, str(udef["description"])):
			fail("未收集条目不应显示描述")
		panel._detail.visible = false
		_click(unc)
		if panel._detail.visible:
			fail("未收集条目点击不应弹详情")
	# 分类切换：法术核心 15 / 外壳 10 / 装备 274+ / 召唤 10，各分类已收集条目正常
	_switch_tab(panel, 1)
	if _live_cells(panel).size() != 15:
		fail("核心网格 != 15: %d" % _live_cells(panel).size())
	var cc := _find_cell(panel, "fireball")
	if cc == null or _cell_name(cc) != "火球":
		fail("核心条目 fireball 渲染错误: %s" % (_cell_name(cc) if cc != null else "missing"))
	_switch_tab(panel, 2)
	if _live_cells(panel).size() != 10:
		fail("外壳网格 != 10: %d" % _live_cells(panel).size())
	var sh := _find_cell(panel, "rapid")
	if sh == null or _cell_name(sh) != "连发":
		fail("外壳条目 rapid 渲染错误: %s" % (_cell_name(sh) if sh != null else "missing"))
	_switch_tab(panel, 3)
	var item_cells := _live_cells(panel)
	if item_cells.size() < 274:
		fail("装备网格 < 274: %d" % item_cells.size())
	var it := _find_cell(panel, "attack_speed_potion")
	if it == null or _cell_name(it) != "攻速药水":
		fail("装备条目 attack_speed_potion 渲染错误: %s" % (_cell_name(it) if it != null else "missing"))
	_click(it)
	if not panel._detail.visible or not str(panel._detail_body.text).contains("攻击速度 +15%"):
		fail("装备详情缺描述: %s" % str(panel._detail_body.text))
	# 未收集装备条目："？？？" + 点击无详情
	panel._detail.visible = false
	var unc_item := _first_uncollected(panel)
	if unc_item != null:
		if _cell_name(unc_item) != "？？？":
			fail("未收集装备名称 != ？？？: %s" % _cell_name(unc_item))
		_click(unc_item)
		if panel._detail.visible:
			fail("未收集装备点击不应弹详情")
	_switch_tab(panel, 4)
	if _live_cells(panel).size() != 10:
		fail("召唤网格 != 10: %d" % _live_cells(panel).size())
	var su := _find_cell(panel, "bat")
	if su == null or _cell_name(su) != "蝙蝠":
		fail("召唤条目 bat 渲染错误: %s" % (_cell_name(su) if su != null else "missing"))
	_switch_tab(panel, 0)
	# tab 文案带收集进度（"法杖 1/55"）
	var wc: int = gs.collection_of("wands").size()
	if not str(panel._tabs[0].text).contains("%d/55" % wc):
		fail("tab 进度文案错误: %s" % str(panel._tabs[0].text))
	if not str(panel._progress.text).contains("%d / 55" % wc):
		fail("进度文案错误: %s" % str(panel._progress.text))
	# 详情弹窗：Esc/知道了关闭路径存在
	if panel._detail == null:
		fail("面板缺详情弹窗")

func _assert_main_menu() -> void:
	var menu: Control = load("res://scenes/main_menu.tscn").instantiate()
	menu.name = "MainMenu"
	root.add_child(menu)
	var cb := menu.get_node_or_null("CollectionButton")
	if cb == null:
		fail("主菜单缺图鉴按钮")
		return
	if str((cb as Button).text) != "图鉴":
		fail("图鉴按钮文字错误: %s" % str((cb as Button).text))
	var r: Rect2 = (cb as Control).get_global_rect()
	if r.size.x < 43.0 or r.size.y < 43.0:
		fail("图鉴按钮触控区不足 44: %s" % str(r))
	var screen := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	if not screen.encloses(r):
		fail("图鉴按钮越出视口: %s" % str(r))
	for bname in ["StartButton", "ContinueButton", "QuitButton"]:
		var other: Rect2 = (menu.get_node(bname) as Control).get_global_rect()
		if r.intersects(other):
			fail("图鉴按钮与 %s 重叠: %s vs %s" % [bname, str(r), str(other)])
	# 按下按钮 → 打开图鉴面板（CanvasLayer 子节点）
	(cb as Button).pressed.emit()
	var opened := menu.get_node_or_null("CollectionPanel")
	if opened == null or not opened.visible:
		fail("图鉴按钮未打开图鉴面板")
	else:
		opened.queue_free()
	menu.queue_free()
