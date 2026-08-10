extends SceneTree
## 竖版 UI 布局回归测试（headless，360x640 逻辑视口）：
##  - HUD：Boss 血条（顶部居中，总宽<=260，y 4..20）与资源条/波次提示不重叠；
##    资源条压缩为单行紧凑（y>=22）；左下按钮 >=44x44、互不重叠、尊重底部安全区；
##    获得提示在屏幕中下、不越界；
##  - 全 UI 面板：宽度 <=340、整体在 360x640 视口内、面板内按钮触控区 >=44；
##    升级三选一卡片纵向堆叠；构筑法术网格 2 列；法杖商店商品卡竖排；
##  - 构筑按钮可打开构筑面板且刷新无报错。
##  - expand 阶段（N3 手机全屏适配）：root.size=390x844 → 逻辑视口 360x779，
##    全部关键 UI 仍在屏内、锚点正确（底部按钮贴底、顶栏贴顶、面板水平居中）。
## Run: godot --headless --path . -s res://scripts/tests/hud_layout_test.gd

var failures: Array[String] = []
var _frame := 0
var _phase := 0
var _hud: CanvasLayer
var _gs: Node
var _bus: Node
var _panels: Array = []
var _best_panel: Control
var _best_area := 0.0

func _gs_node() -> Node:
	return root.get_node("GameState")

func _bus_node() -> Node:
	return root.get_node("EventBus")

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false
	match _phase:
		0:
			root.size = Vector2i(360, 640)  # 竖版逻辑视口（Agent M1 切换 project.godot 后的基准）
			_setup_run()
			_hud = load("res://scenes/ui/hud.tscn").instantiate()
			_hud.name = "HUD"
			root.add_child(_hud)
			_build_panels()
			_phase = 1
		1:
			_assert_hud()
			_assert_panels()
			_assert_build_button()
			_phase = 2
		2:
			root.size = Vector2i(390, 844)  # 模拟手机：expand 下逻辑视口 ≈360x779
			_phase = 3
		3:
			_assert_expand()
			if failures.is_empty():
				print("PORTRAIT UI OK")
				print("EXPAND UI OK")
			else:
				for f in failures:
					push_error("HUD FAIL: " + f)
			quit(0 if failures.is_empty() else 1)
			return true
	return false

func fail(msg: String) -> void:
	failures.append(msg)

func approx(a: float, b: float, eps: float = 0.01) -> bool:
	return absf(a - b) <= eps

func _setup_run() -> void:
	_gs = _gs_node()
	_bus = _bus_node()
	_gs.new_run()
	_gs.run.items = {
		"attack_speed_potion": 2,
		"strength_badge": 3,
		"lucky_clover": 1,
	}
	_gs.run.grid = [
		{"core": "fireball", "shell": ""},
		{"core": "whirl_blade", "shell": "rapid"},
	]

func _rect(c: Control) -> Rect2:
	return c.get_global_rect()

func _build_panels() -> void:
	## 实例化全部 UI 面板并触发内容构建（等一帧后断言）
	var specs := [
		["BuildPanel", "res://scenes/ui/build_panel.tscn"],
		["LevelUpOverlay", "res://scenes/ui/levelup_overlay.tscn"],
		["WandShop", "res://scenes/ui/wand_shop.tscn"],
		["SpellReplace", "res://scenes/ui/spell_replace.tscn"],
		["PauseMenu", "res://scenes/ui/pause_menu.tscn"],
		["LoopChoice", "res://scenes/ui/loop_choice.tscn"],
		["GameOver", "res://scenes/ui/game_over.tscn"],
	]
	for spec in specs:
		var ui: CanvasLayer = load(spec[1]).instantiate()
		ui.name = str(spec[0])
		root.add_child(ui)
		_panels.append(ui)
	# 触发内容构建
	_panels[0].refresh()
	_panels[1].show_choices([
		{"id": "attack_speed_potion", "name": "迅捷药水", "rarity": "common", "description": "攻击速度 +12%（每层）", "icon": ""},
		{"id": "strength_badge", "name": "力量徽章", "rarity": "rare", "description": "攻击 +10%（每层）", "icon": ""},
		{"id": "lucky_clover", "name": "幸运草", "rarity": "legendary", "description": "暴击率 +2%（每层）", "icon": ""},
	])
	_panels[2].show_shop()
	_panels[3].show_replace("fireball", "rapid", _gs.run.grid)
	# 主菜单（tscn 预置按钮）
	var menu: Control = load("res://scenes/main_menu.tscn").instantiate()
	menu.name = "MainMenu"
	root.add_child(menu)
	_panels.append(menu)

func _assert_hud() -> void:
	_bus.boss_spawned.emit("暗影魔像", 500)
	_hud._on_wave("波次 3 来袭")
	var boss := _rect(_hud._boss_root)
	var res := _rect(_hud._res_box)
	var wave := _rect(_hud._wave_label)
	var pick := _rect(_hud._pickup_label)
	print("[RECTS] boss=%s res=%s wave=%s pickup=%s" % [boss, res, wave, pick])
	if not _hud._boss_root.visible:
		fail("Boss 血条未显示")
	if boss.size.x > 262.0 or boss.position.y < 3.0 or boss.end.y > 21.0:
		fail("Boss 血条越界(需 y 4..20, 宽<=260): " + str(boss))
	if boss.intersects(res):
		fail("Boss 血条与左上资源重叠: boss=%s res=%s" % [boss, res])
	if boss.intersects(wave):
		fail("Boss 血条与波次横幅重叠: boss=%s wave=%s" % [boss, wave])
	if res.position.y < 22.0 or res.size.y > 22.0:
		fail("资源条未压缩为单行紧凑(需 y>=22, 高<=22): " + str(res))
	if res.end.x > 360.0 or res.end.y > 640.0:
		fail("资源条越界: " + str(res))
	if pick.position.x < -1.0 or pick.end.x > 361.0 or pick.position.y < 0.0 or pick.end.y > 640.0:
		fail("获得提示越界: " + str(pick))
	if pick.position.y < 440.0:
		fail("获得提示不在屏幕中下: " + str(pick))
	# 左下角按钮：构筑/暂停均存在、尺寸 >=44、互不重叠、底部安全区
	var btns := _corner_buttons()
	if btns.size() != 2:
		fail("左下角按钮数量异常: %d != 2" % btns.size())
	for b in btns:
		var r := _rect(b)
		if r.size.x < 43.0 or r.size.y < 43.0:
			fail("按钮触控区过小(<44px): " + str(r))
		if r.end.y > 640.0 - 22.0:
			fail("按钮侵入底部安全区(<24px): " + str(r))
	if btns.size() == 2 and _rect(btns[0]).intersects(_rect(btns[1])):
		fail("构筑/暂停按钮重叠")
	# HUD 不再有底部常驻构筑条（成员已删除）
	if _hud.get("_bar_root") != null or _hud.get("_grid_bar") != null or _hud.get("_tab_btn") != null:
		fail("底部常驻构筑条仍存在")

func _corner_buttons() -> Array:
	var out: Array = []
	for c in _hud.get_children():
		if c is Control and c is not CanvasLayer:
			for ch in c.get_children():
				if ch is Button and ch.get_global_rect().position.y > 250.0:
					out.append(ch)
	return out

func _assert_panels() -> void:
	for ui in _panels:
		var tag: String = ui.name
		if tag != "MainMenu":  # 主菜单为 tscn 直排按钮（无 PanelContainer）
			_best_panel = null
			_best_area = 0.0
			_collect_panels(ui)
			if _best_panel == null:
				fail(tag + " 未找到面板节点")
				continue
			var r := _best_panel.get_global_rect()
			if r.size.x > 341.0:
				fail("%s 面板过宽(>340): %s" % [tag, str(r)])
			if r.position.x < -1.0 or r.position.y < -1.0 or r.end.x > 361.0 or r.end.y > 641.0:
				fail("%s 面板越出 360x640 视口: %s" % [tag, str(r)])
		_assert_buttons_44(ui, tag)
	# 专项断言
	_assert_levelup_stack()
	_assert_build_grid()
	_assert_wand_shop_offers()

func _collect_panels(node: Node) -> void:
	if node is PanelContainer:
		var c := node as Control
		var r := c.get_global_rect()
		var area := r.size.x * r.size.y
		if area > _best_area:
			_best_area = area
			_best_panel = c
	for ch in node.get_children():
		_collect_panels(ch)

func _assert_buttons_44(node: Node, tag: String) -> void:
	for ch in node.get_children():
		if ch is Button:
			var r := (ch as Control).get_global_rect()
			if r.size.x < 43.0 or r.size.y < 43.0:
				fail("%s 按钮触控区不足 44: %s rect=%s" % [tag, ch.name, str(r)])
		_assert_buttons_44(ch, tag)

func _assert_levelup_stack() -> void:
	var lv: Node = _panels[1]
	var cards: Array = []
	for c in lv._box.get_children():
		if c is PanelContainer:
			cards.append(c.get_global_rect())
	if cards.size() != 3:
		fail("升级卡片数量 != 3: " + str(cards.size()))
		return
	var x0: float = cards[0].position.x
	for i in cards.size():
		var r: Rect2 = cards[i]
		if absf(r.position.x - x0) > 2.0:
			fail("升级卡片未纵向堆叠(第%d张 x 偏移): %s" % [i, str(r)])
		if r.size.y < 43.0:
			fail("升级卡片过矮(<44): " + str(r))
		if i > 0 and r.position.y <= cards[i - 1].end.y:
			fail("升级卡片纵向重叠")

func _assert_build_grid() -> void:
	var bp: Node = _panels[0]
	if bp._grid_box.columns != 2:
		fail("构筑法术网格未改为 2 列: columns=%d" % bp._grid_box.columns)
	if bp._detail == null:
		fail("构筑面板缺少点击详情弹窗")
	elif bp._detail.visible:
		fail("构筑详情弹窗初始应隐藏")

func _assert_wand_shop_offers() -> void:
	var ws: Node = _panels[2]
	var cards: Array = []
	for c in ws._box.get_children():
		if c is PanelContainer:
			cards.append(c.get_global_rect())
	if cards.size() != 3:
		fail("法杖商店商品卡数量 != 3: " + str(cards.size()))
	for i in cards.size():
		var r: Rect2 = cards[i]
		if r.size.x > 341.0:
			fail("法杖商店商品卡过宽: " + str(r))
		if i > 0 and r.position.y <= cards[i - 1].end.y:
			fail("法杖商店商品卡纵向重叠")

func _assert_build_button() -> void:
	# 构筑按钮存在且切换构筑面板可见性（面板实例化+refresh 无报错）
	var scene := Node.new()
	scene.name = "Scene"
	root.add_child(scene)
	current_scene = scene
	var panel: Node = load("res://scenes/ui/build_panel.tscn").instantiate()
	panel.name = "BuildPanel"
	scene.add_child(panel)
	var before: bool = panel.visible
	_hud._toggle_build()
	if panel.visible == before:
		fail("构筑面板未切换可见性")
	_hud._toggle_build()
	panel.queue_free()
	scene.queue_free()

func _assert_expand() -> void:
	## N3：expand 视口（360x779）下全部关键 UI 在屏内、锚点正确
	var vp: Vector2 = root.get_visible_rect().size
	print("[EXPAND] viewport=", vp)
	var screen := Rect2(Vector2.ZERO, vp)
	var boss := _rect(_hud._boss_root)
	var res := _rect(_hud._res_box)
	var wave := _rect(_hud._wave_label)
	var pick := _rect(_hud._pickup_label)
	for pair in [["boss", boss], ["res", res], ["wave", wave], ["pick", pick]]:
		var r: Rect2 = pair[1]
		if not screen.encloses(r):
			fail("%s 越出 expand 视口: %s (vp=%s)" % [pair[0], str(r), str(vp)])
	if not approx(res.position.x, 8.0) or not approx(res.position.y, 24.0):
		fail("expand 下资源条未贴左上 (8,24): " + str(res))
	if not approx(boss.position.x, vp.x / 2.0 - 126.0):
		fail("expand 下 Boss 条未顶部居中: " + str(boss))
	if not approx(wave.position.x, vp.x - 100.0):
		fail("expand 下波次提示未锚右上: " + str(wave))
	if not approx(pick.position.y, vp.y - 140.0):
		fail("expand 下获得提示未锚中下（y=视口高-140）: " + str(pick))
	var btns := _corner_buttons()
	for b in btns:
		var r := _rect(b)
		if not screen.encloses(r):
			fail("expand 下底部按钮越界: " + str(r))
		if r.end.y < vp.y - 100.0:
			fail("expand 下底部按钮未贴底: " + str(r))
	# 面板：expand 视口下在屏内且水平居中；主菜单按钮全在屏内
	for ui in _panels:
		var tag: String = ui.name
		if tag == "MainMenu":
			for bname in ["StartButton", "ContinueButton", "QuitButton"]:
				var r: Rect2 = (ui.get_node(bname) as Control).get_global_rect()
				if not screen.encloses(r):
					fail("expand 下主菜单按钮越界 %s: %s" % [bname, str(r)])
			continue
		_best_panel = null
		_best_area = 0.0
		_collect_panels(ui)
		if _best_panel == null:
			continue
		var r2: Rect2 = _best_panel.get_global_rect()
		if not screen.encloses(r2):
			fail("%s 面板越出 expand 视口: %s" % [tag, str(r2)])
		var cx: float = r2.position.x + r2.size.x / 2.0
		if absf(cx - vp.x / 2.0) > 2.0:
			fail("%s 面板 expand 下未水平居中: %s" % [tag, str(r2)])
