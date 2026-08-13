extends SceneTree
## 商店 UI 修复测试（2026-08-12，对应 docs/design/商店修复报告.md）：
## ① 选择页无 CloseBtn 节点，按钮顺序 = 强化→购买→构筑→回血→下一波
## ② 构筑购买成功 → 暂停态下 0.5s 自动关闭商店（process_always 定时，修复2）
## ③ 购买页：3 张法杖卡（v50 每行一根 columns=1），v51 已无 LockBtn；
##    点购买按钮 → 扣款并关闭商店
## ④ 刷新费递增（80→160→320→480 封顶）+ 按钮文字实时同步（修复2）
## ⑤ 法杖稀有度分布：1000 次抽取 legendary 显著低于 common（修复2）
## ⑥ 强化页/菜单/购买页所有 Label 文本无 "??" 码点、无缺失字形
## 运行：godot --headless --path . -s res://scripts/tests/test_wand_shop_ui.gd

var failures: Array[String] = []
var _started := false
var _gs: Node
var _build_closed := false  # 构筑购买后 shop_closed 标志（成员变量：lambda 按值捕获不生效）

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
	await _check_buy_page(shop)
	await _check_build_buy_closes(shop)
	await _check_refresh_price(shop)
	_check_rarity_distribution(shop)
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

func _check_buy_page(shop: CanvasLayer) -> void:
	## 购买页（v50：每根法杖一行 columns=1；v51：已移除 LockBtn 图标）
	_find_button(shop, "BuyBtn").pressed.emit()
	await process_frame
	await process_frame
	_check_fonts(shop, "购买页")
	var cards: Array = shop._box.get_children()
	if cards.size() != 3:
		fail("购买页应有 3 张法杖卡，实际 %d" % cards.size())
		return
	if shop._box.columns != 1:
		fail("购买页网格列数 != 1（v50 每根法杖一行）: %d" % shop._box.columns)
	var locks := 0
	for c in cards:
		if _find_button(c, "LockBtn") != null:
			locks += 1
	if locks != 0:
		fail("v51 后商品卡不应再存在 LockBtn: %d" % locks)
	# 点第一张卡的购买按钮 → 扣款并关闭商店
	var card0 := cards[0] as Control
	var offer: Dictionary = shop._offers[0]
	var price0: int = int(offer.get("price", 0))
	var gold_before: int = int(_gs.run.gold)
	var buy_btn := _find_button_by_text(card0, "购买")
	if buy_btn == null:
		fail("法杖卡缺少购买按钮")
		return
	buy_btn.pressed.emit()
	await process_frame
	if shop._shop_open:
		fail("点购买按钮未关闭商店: price=%d gold=%d→%d" % [
			price0, gold_before, int(_gs.run.gold)])
	elif int(_gs.run.gold) != gold_before - price0:
		fail("购买扣款异常: gold=%d 期望 %d" % [int(_gs.run.gold), gold_before - price0])

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
	_build_closed = false
	shop.shop_closed.connect(_on_shop_closed)
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
	# 等待 0.5s 延时关闭（复现真实对局：商店打开时游戏树处于暂停态，
	# 修复前 create_timer 未设 process_always=true，暂停期不触发 → 商店永不关闭；
	# 此测试此前未暂停树，恰好漏检该 bug）
	paused = true
	await create_timer(0.9, true).timeout
	paused = false
	await process_frame
	shop.shop_closed.disconnect(_on_shop_closed)
	if not _build_closed:
		fail("构筑购买后未发出 shop_closed 信号")
	if shop._shop_open:
		fail("构筑购买后商店未自动关闭（暂停期 0.5s 定时未触发）")


func _on_shop_closed() -> void:
	_build_closed = true


func _check_refresh_price(shop: CanvasLayer) -> void:
	## 问题3：刷新费每次刷新递增（80→160→320→480 封顶），刷新按钮文字实时同步
	shop.show_shop()
	_gs.run.gold = 2000
	_find_button(shop, "BuyBtn").pressed.emit()
	await process_frame
	var refresh := _find_button(shop, "RefreshBtn") as Button
	if refresh == null:
		fail("购买页缺少 RefreshBtn")
		return
	var seq := [80, 160, 320, 480, 480]
	var gold: int = int(_gs.run.gold)
	for i in seq.size():
		var expect_price: int = seq[i]
		if shop._refresh_price() != expect_price:
			fail("第 %d 次刷新价=%d 期望 %d" % [i + 1, shop._refresh_price(), expect_price])
		if shop._refresh_count != i:
			fail("第 %d 次 _refresh_count=%d 期望 %d" % [i + 1, shop._refresh_count, i])
		var want := "刷新（%d金）" % expect_price
		if not refresh.text.contains(want):
			fail("刷新按钮文字未实时同步: %r（期望 %r）" % [refresh.text, want])
		if gold < expect_price:
			fail("金币不足以模拟第 %d 次刷新（gold=%d）" % [i + 1, gold])
		refresh.pressed.emit()
		await process_frame
		gold -= expect_price
		if int(_gs.run.gold) != gold:
			fail("第 %d 次刷新扣款异常: gold=%d 期望 %d" % [i + 1, int(_gs.run.gold), gold])


func _check_rarity_distribution(shop: CanvasLayer) -> void:
	## 问题2：法杖抽取稀有度分布（模拟 1000 次 _roll_offers，每次 3 把）
	## 五档：白>绿>蓝>金>红 严格递减，红占比应显著低于白（越稀有越难出）
	_gs.run.items = {}
	_gs.run.wands = ["basic_wand"]
	var counts := {"common": 0, "uncommon": 0, "rare": 0, "epic": 0, "legendary": 0}
	for i in 1000:
		shop._roll_offers()
		for w in shop._offers:
			var r: String = str(w.get("rarity", "common"))
			counts[r] = int(counts[r]) + 1
	var total: float = 0.0
	for r in counts:
		total += float(int(counts[r]))
	var ratios := {}
	for r in counts:
		ratios[r] = float(counts[r]) / total
	var line := ""
	for r in ["common", "uncommon", "rare", "epic", "legendary"]:
		line += "%s %.1f%% " % [r, ratios[r] * 100.0]
	print("稀有度分布(1000x3): " + line)
	var legendary_ratio: float = ratios["legendary"]
	if legendary_ratio > 0.15:
		fail("legendary 占比 %.1f%% 过高（应 <15%%，越稀有越难出）" % [legendary_ratio * 100.0])
	if ratios["common"] < 0.30:
		fail("common 占比 %.1f%% 过低（应 >30%%）" % [ratios["common"] * 100.0])
	var order := ["common", "uncommon", "rare", "epic", "legendary"]
	for i in order.size() - 1:
		if ratios[order[i]] <= ratios[order[i + 1]]:
			fail("稀有度概率未递减: %s %.1f%% <= %s %.1f%%"
				% [order[i], ratios[order[i]] * 100.0,
					order[i + 1], ratios[order[i + 1]] * 100.0])
	if legendary_ratio >= ratios["common"] * 0.5:
		fail("legendary 占比未显著低于 common: legendary=%.1f%% common=%.1f%%"
			% [legendary_ratio * 100.0, ratios["common"] * 100.0])
