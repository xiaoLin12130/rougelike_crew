extends SceneTree
## 商店 UI 修复测试（2026-08-12，对应 docs/design/商店修复报告.md）：
## ① 选择页无 CloseBtn 节点，按钮顺序 = 强化→购买→构筑→回血→下一波
## ② 构筑购买成功 → shop_closed 信号发出（0.5s 展示购买成功后自动关闭商店）
## ③ 商品卡锁钮位于卡片内右上角 20x20：不遮挡图标中心、不与价格行重叠；
##    整卡点击（图标中心）能触发购买并关闭商店
## ④ 强化页/菜单/购买页所有 Label 文本无 "??" 码点、无缺失字形
## 运行：godot --headless --path . -s res://scripts/tests/test_wand_shop_ui.gd

var failures: Array[String] = []
var _started := false
var _gs: Node

func _process(_delta: float) -> bool:
	## MainLoop._process 返回 true 会立即退出主循环；因此首帧启动协程后
	## 一直返回 false，由 _run 协程完成全部检查后自行 quit(code)
	if not _started:
		_started = true
		_run()
	return false

func fail(msg: String) -> void:
	failures.append(msg)
	push_error("WAND SHOP UI FAIL: " + msg)

func _find_node(node: Node, nname: String) -> Node:
	if node.name == nname:
		return node
	for ch in node.get_children():
		var r := _find_node(ch, nname)
		if r != null:
			return r
	return null

func _find_button(node: Node, bname: String) -> Button:
	if node is Button and node.name == bname:
		return node as Button
	for ch in node.get_children():
		var r := _find_button(ch, bname)
		if r != null:
			return r
	return null

func _find_button_by_text(node: Node, needle: String) -> Button:
	if node is Button and node.text.contains(needle):
		return node as Button
	for ch in node.get_children():
		var r := _find_button_by_text(ch, needle)
		if r != null:
			return r
	return null

func _collect_labels(node: Node) -> Array:
	var out: Array = []
	if node is Label:
		out.append(node)
	for ch in node.get_children():
		out.append_array(_collect_labels(ch))
	return out

func _run() -> void:
	_gs = root.get_node_or_null("GameState")
	if _gs == null:
		fail("GameState autoload missing")
		_finish()
		return
	_gs.new_run()
	_gs.run.gold = 2000
	_gs.run.wands = ["basic_wand"]
	root.size = Vector2i(360, 640)
	var shop: CanvasLayer = load("res://scenes/ui/wand_shop.tscn").instantiate()
	shop.name = "WandShopUI"
	root.add_child(shop)
	shop.show_shop()
	await process_frame
	await process_frame

	_check_menu(shop)
	_check_fonts(shop, "选择页")
	# 强化页码点检查（用户反馈 4）：进入强化页 → 全 Label 无 "??" / 无缺字形
	_find_button(shop, "EnhanceBtn").pressed.emit()
	await process_frame
	await process_frame
	_check_fonts(shop, "强化页")
	_find_button(shop, "BackBtnEnhance").pressed.emit()
	await process_frame
	_check_lock_buttons(shop)
	_check_build_buy_closes(shop)
	shop.free()
	_finish()

func _finish() -> void:
	if failures.is_empty():
		print("WAND SHOP UI TEST OK")
	else:
		print("WAND SHOP UI TEST FAILED: %d 项" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _check_menu(shop: CanvasLayer) -> void:
	if _find_node(shop, "CloseBtn") != null:
		fail("选择页仍存在已删除的 CloseBtn")
	var order: Array[String] = []
	for ch in shop._menu_box.get_children():
		if ch is Button:
			order.append(ch.name)
	var expect := ["EnhanceBtn", "BuyBtn", "BuildBtn", "PotionBtn", "NextWaveBtn"]
	if order != expect:
		fail("选择页按钮顺序错误: %s（期望 %s）" % [str(order), str(expect)])

func _check_fonts(shop: CanvasLayer, tag: String) -> void:
	## 逐 Label 检查：文本无 "??" 且每个非 ASCII 字符都在所用字体中（码点回归）
	for l in _collect_labels(shop):
		var t: String = l.text
		if t.contains("??"):
			fail("[%s] 文本含 ?? 码点: %r" % [tag, t])
		var f: Font = l.get_theme_font("font")
		if f == null:
			fail("[%s] Label 未设置字体: %r" % [tag, t])
			continue
		for ch in t:
			if ch.unicode_at(0) > 127 and not f.has_char(ch.unicode_at(0)):
				fail("[%s] 缺字形 U+%04X: %r" % [tag, ch.unicode_at(0), t])

func _check_lock_buttons(shop: CanvasLayer) -> void:
	_find_button(shop, "BuyBtn").pressed.emit()
	await process_frame
	await process_frame
	_check_fonts(shop, "购买页")
	var cards: Array = shop._box.get_children()
	if cards.size() != 3:
		fail("购买页应有 3 张法杖卡，实际 %d" % cards.size())
		return
	for c in cards:
		var lock := _find_button(c, "LockBtn")
		if lock == null:
			fail("商品卡缺少 LockBtn")
			continue
		var lr: Rect2 = lock.get_global_rect()
		var cr: Rect2 = (c as Control).get_global_rect()
		if lr.size.x < 18.0 or lr.size.y < 18.0 or lr.size.x > 26.0 or lr.size.y > 26.0:
			fail("锁钮尺寸异常（应为 20x20）: %s" % str(lr.size))
		if not cr.encloses(lr):
			fail("锁钮不在卡片内部: lock=%s card=%s" % [str(lr), str(cr)])
		if lr.position.y >= cr.position.y + cr.size.y * 0.35:
			fail("锁钮未贴卡片右上角（y 应 < 卡高 35%%）: %s" % str(lr))
		var icon := _first_tex(c)
		if icon != null:
			var icon_c: Vector2 = (icon as Control).get_global_rect().get_center()
			if lr.has_point(icon_c):
				fail("锁钮遮挡图标中心: lock=%s icon_center=%s" % [str(lr), str(icon_c)])
		var price := _first_price_row(c)
		if price != null and lr.intersects((price as Control).get_global_rect()):
			fail("锁钮与价格行重叠（会拦截购买点击）: %s" % str(lr))
	# 整卡点击 = 购买：向图标中心发射真实鼠标事件，应触发购买并关闭商店
	var card0 := cards[0] as Control
	var offer: Dictionary = shop._offers[0]
	var price0: int = int(offer.get("price", 0))
	var gold_before: int = int(_gs.run.gold)
	var icon0 := _first_tex(card0) as Control
	var click_pos: Vector2 = icon0.get_global_rect().get_center() if icon0 != null else card0.get_global_rect().get_center()
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = click_pos
	root.push_input(ev)
	var ev2 := InputEventMouseButton.new()
	ev2.button_index = MOUSE_BUTTON_LEFT
	ev2.pressed = false
	ev2.position = click_pos
	root.push_input(ev2)
	await process_frame
	if shop._shop_open:
		fail("整卡点击未购买法杖（商店未关闭）: click=%s price=%d gold=%d→%d" % [
			str(click_pos), price0, gold_before, int(_gs.run.gold)])
	elif int(_gs.run.gold) != gold_before - price0:
		fail("整卡购买扣款异常: gold=%d 期望 %d" % [int(_gs.run.gold), gold_before - price0])

func _first_tex(node: Node) -> TextureRect:
	if node is TextureRect:
		return node as TextureRect
	for ch in node.get_children():
		var r := _first_tex(ch)
		if r != null:
			return r
	return null

func _first_price_row(node: Node) -> HBoxContainer:
	if node is HBoxContainer:
		return node as HBoxContainer
	for ch in node.get_children():
		var r := _first_price_row(ch)
		if r != null:
			return r
	return null

func _check_build_buy_closes(shop: CanvasLayer) -> void:
	# 上一段购买法杖已关闭商店 → 重新开店进入构筑页
	shop.show_shop()
	_find_button(shop, "BuildBtn").pressed.emit()
	await process_frame
	await process_frame
	if shop._build_offers.is_empty():
		fail("构筑货架为空")
		return
	var closed := false
	shop.shop_closed.connect(func() -> void: closed = true)
	var gold_before: int = int(_gs.run.gold)
	var buy_btn := _find_button_by_text(shop._build_box, "购买")
	if buy_btn == null:
		fail("构筑卡缺少购买按钮")
		return
	buy_btn.pressed.emit()
	await process_frame
	if not shop._build_bought:
		fail("构筑购买未标记 _build_bought")
	if not shop._shop_open:
		fail("构筑购买后商店立即关闭（应 0.5s 后关闭以展示购买成功）")
	if int(_gs.run.gold) >= gold_before:
		fail("构筑购买未扣款: gold=%d（购买前 %d）" % [int(_gs.run.gold), gold_before])
	# 等待 0.5s 延时关闭
	await create_timer(0.9).timeout
	await process_frame
	if not closed:
		fail("构筑购买后未发出 shop_closed 信号")
	if shop._shop_open:
		fail("构筑购买后商店未自动关闭")
