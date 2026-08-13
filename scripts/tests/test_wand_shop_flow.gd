extends SceneTree
## 法杖商店 v2 流程测试（问题 1/2：先选强化或购买 + 手机端适配）：
## ① 打开商店默认显示选择页（强化/购买/离开按钮存在且在选择页可见区内）
## ② 点购买 → 显示 3 把法杖 + 返回按钮（卡片纵向不重叠、不超屏）
## ③ 点强化 → 显示已持有法杖强化卡 + 返回按钮
## ④ 手机模拟（force_mobile(true)）：所有按钮 ≥44px、激活页卡片不超屏
## 运行：godot --headless --path . -s res://scripts/tests/test_wand_shop_flow.gd

var failures: Array[String] = []
var _frame := 0
var _phase := 0
var _gs: Node
var _shop: CanvasLayer

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	match _phase:
		0:
			_setup()
			_phase = 1
		1:
			_check_menu(_shop, "pc")
			_phase = 2
		2:
			_find_button(_shop, "BuyBtn").pressed.emit()
			_phase = 3
		3:
			_check_buy(_shop, "pc")
			_phase = 4
		4:
			_find_button(_shop, "BackBtnBuy").pressed.emit()
			_find_button(_shop, "EnhanceBtn").pressed.emit()
			_phase = 5
		5:
			_check_enhance(_shop, "pc")
			_phase = 6
		6:
			_find_button(_shop, "BackBtnEnhance").pressed.emit()
			# autoplay：优先强化最便宜可负担的（basic_wand 250金）
			_gs.run.gold = 300
			_shop.autoplay_handle()
			if not _shop._upgraded:
				fail("autoplay 未优先强化最便宜可负担的法杖（gold=300 应强化 basic_wand 250金）")
			if _gs.run.gold != 50:
				fail("autoplay 强化后金币异常: gold=%d 期望 50" % _gs.run.gold)
			_phase = 7
		7:
			# autoplay：强化已用 → 购买最贵可负担（满 3 把进入替换模式 → 替换槽位 0 → 关闭）
			_gs.run.gold = 1000
			_shop.autoplay_handle()
			if not _shop._replace_mode:
				fail("autoplay 购买未进入替换模式（已持有 3 把）")
			_shop.autoplay_handle()
			if _shop._shop_open:
				fail("autoplay 替换后应关闭商店")
			if _gs.run.gold >= 1000:
				fail("autoplay 替换未扣款: gold=%d" % _gs.run.gold)
			_shop.free()
			UiLayout.force_mobile(true)
			_shop = load("res://scenes/ui/wand_shop.tscn").instantiate()
			_shop.name = "WandShopMobile"
			root.add_child(_shop)
			_shop.show_shop()
			_phase = 8
		8:
			_check_buttons_min(_shop, "mobile-all")
			_check_menu(_shop, "mobile")
			_find_button(_shop, "BuyBtn").pressed.emit()
			_phase = 9
		9:
			_check_buy(_shop, "mobile")
			_find_button(_shop, "BackBtnBuy").pressed.emit()
			_find_button(_shop, "EnhanceBtn").pressed.emit()
			_phase = 10
		10:
			_check_enhance(_shop, "mobile")
			_shop.free()
			UiLayout.force_mobile(false)
			_phase = 11
		11:
			if failures.is_empty():
				print("WAND SHOP FLOW ALL PASS")
			else:
				for f in failures:
					push_error("WAND SHOP FLOW FAIL: " + f)
			quit(0 if failures.is_empty() else 1)
			return true
	return false

func fail(msg: String) -> void:
	failures.append(msg)

func _setup() -> void:
	_gs = root.get_node_or_null("GameState")
	if _gs == null:
		fail("GameState autoload missing")
		return
	_gs.new_run()
	_gs.run.gold = 2000
	_gs.run.wands = ["basic_wand", "fire_staff", "shatter_staff"]
	root.size = Vector2i(360, 640)
	_shop = load("res://scenes/ui/wand_shop.tscn").instantiate()
	_shop.name = "WandShop"
	root.add_child(_shop)
	_shop.show_shop()

func _find_button(node: Node, bname: String) -> Button:
	if node is Button and node.name == bname:
		return node as Button
	for ch in node.get_children():
		var r := _find_button(ch, bname)
		if r != null:
			return r
	return null

func _viewport_rect() -> Rect2:
	## 滚动区可视矩形（“屏幕”= 商店滚动视口；区块按需滚动到视口内）
	return (_shop._scroll as Control).get_global_rect()

func _cards_in(box: Node) -> Array:
	var out: Array = []
	for c in box.get_children():
		if c is PanelContainer and not c.is_queued_for_deletion():
			out.append(c as Control)
	return out

func _check_menu(shop: CanvasLayer, tag: String) -> void:
	if shop._page != "menu":
		fail("[%s] 打开商店默认应显示选择页，实际 page=%s" % [tag, str(shop._page)])
	# 页面互斥（2026-08-10 修复：仅滚动定位时内容少会导致多页同时可见）
	if not shop._menu_box.visible:
		fail("[%s] 选择页时 menu_box 应可见" % tag)
	if shop._enhance_section.visible or shop._buy_section.visible:
		fail("[%s] 选择页时强化/购买区块不应同时可见" % tag)
	var vp: Rect2 = (shop._scroll as Control).get_global_rect()
	# 2026-08-12：选择页 = 强化/购买/购买构筑/回血 + Brotato 金色"开始下一波"
	# （"关闭"按钮已删除，退出统一走金色按钮）
	for bname in ["EnhanceBtn", "BuyBtn", "PotionBtn", "NextWaveBtn"]:
		var b := _find_button(shop, bname)
		if b == null:
			fail("[%s] 选择页缺少按钮 %s" % [tag, bname])
		elif not vp.encloses(b.get_global_rect()):
			fail("[%s] 选择页按钮 %s 不在可视区: rect=%s vp=%s" % [tag, bname, str(b.get_global_rect()), str(vp)])
	if _find_button(shop, "CloseBtn") != null:
		fail("[%s] 选择页不应存在已删除的关闭按钮 CloseBtn" % tag)

func _check_buy(shop: CanvasLayer, tag: String) -> void:
	if shop._page != "buy":
		fail("[%s] 点击购买后应进入购买页，实际 page=%s" % [tag, str(shop._page)])
	if shop._menu_box.visible or shop._enhance_section.visible:
		fail("[%s] 购买页时选择/强化区块不应同时可见" % tag)
	var cards := _cards_in(shop._box)
	if cards.size() != 3:
		fail("[%s] 购买页应显示 3 把法杖，实际 %d" % [tag, cards.size()])
		return
	# v50 用户需求：购买法杖页每根法杖一行（columns=1）
	if shop._box.columns != 1:
		fail("[%s] 商品卡网格列数 != 1: %d" % [tag, shop._box.columns])
	var vp: Rect2 = (shop._scroll as Control).get_global_rect()
	var prev_bottom := -INF
	for c in cards:
		var r: Rect2 = (c as Control).get_global_rect()
		if r.size.x > 360.0:
			fail("[%s] 卡片过宽(>360): %s rect=%s" % [tag, c.name, str(r)])
		if not vp.encloses(r):
			fail("[%s] 卡片超出滚动可视区: rect=%s vp=%s" % [tag, str(r), str(vp)])
		if r.position.y < prev_bottom - 2.0:
			fail("[%s] 卡片纵向重叠: %s rect=%s" % [tag, c.name, str(r)])
		prev_bottom = r.end.y
	# v51：法杖卡去锁图标（LockBtn 已移除）
	var locks := 0
	for c in shop._box.get_children():
		if c is PanelContainer:
			for ch in c.get_children():
				if ch is Button and ch.name == "LockBtn":
					locks += 1
	if locks != 0:
		fail("[%s] 商品卡不应再有 LockBtn（v51 去锁图标）: %d" % [tag, locks])
	var back := _find_button(shop, "BackBtnBuy")
	if back == null:
		fail("[%s] 购买页缺少返回按钮" % tag)
	elif not vp.encloses(back.get_global_rect()):
		fail("[%s] 购买页返回按钮不在可视区: rect=%s" % [tag, str(back.get_global_rect())])

func _check_enhance(shop: CanvasLayer, tag: String) -> void:
	if shop._page != "enhance":
		fail("[%s] 点击强化后应进入强化页，实际 page=%s" % [tag, str(shop._page)])
	if shop._menu_box.visible or shop._buy_section.visible:
		fail("[%s] 强化页时选择/购买区块不应同时可见" % tag)
	var slots := _cards_in(shop._owned_box)
	if slots.size() != 3:
		fail("[%s] 强化页应显示已持有 3 把法杖强化卡，实际 %d" % [tag, slots.size()])
		return
	var vp: Rect2 = (shop._scroll as Control).get_global_rect()
	for c in slots:
		var r: Rect2 = c.get_global_rect()
		if not vp.encloses(r):
			fail("[%s] 强化卡超出滚动可视区: rect=%s vp=%s" % [tag, str(r), str(vp)])
	var back := _find_button(shop, "BackBtnEnhance")
	if back == null:
		fail("[%s] 强化页缺少返回按钮" % tag)
	elif not vp.encloses(back.get_global_rect()):
		fail("[%s] 强化页返回按钮不在可视区: rect=%s" % [tag, str(back.get_global_rect())])

func _check_buttons_min(shop: CanvasLayer, tag: String) -> void:
	_walk_buttons(shop, tag)

func _walk_buttons(node: Node, tag: String) -> void:
	if node is Button:
		if node.name == "LockBtn":
			pass  # 商品卡锁钮为 20x20 装饰钮（整卡才是触控目标），豁免 44px 断言
		else:
			var r: Rect2 = (node as Control).get_global_rect()
			if r.size.x < 44.0 or r.size.y < 44.0:
				fail("[%s] 按钮触控区过小(<44px): %s rect=%s" % [tag, node.name, str(r)])
	for ch in node.get_children():
		_walk_buttons(ch, tag)
