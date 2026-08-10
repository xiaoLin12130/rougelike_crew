extends CanvasLayer
## 法杖商店（竖版 360x640）：面板 320x540 居中（<=340 宽），内容纵向排布。
## 商店改造 v2（问题 1/2：先选强化或购买 + 手机端适配）：
##   入口选择页：Boss 战后打开商店先显示两个大按钮「强化法杖 / 购买法杖」+ 离开；
##   强化页：已持有法杖强化卡片（+8%/级，200 起每级 +100，每次进店限 1 次强化）；
##   购买页：3 把随机法杖（稀有度加权 + lucky 联动），满 3 把进入替换模式；
##   两页均有「返回选择页」按钮；手机端（is_mobile）更紧凑（卡片 280 宽、强化槽 2 列）；
##   药水/刷新保留在选择页；ScrollContainer 兜底防溢出；全部按钮触控 >=44px。
##   布局实现：三个区块（选择/强化/购买）常驻同一滚动区（保证任意时刻子节点
##   均完成排序，Godot 4.7 隐藏容器不会排序子节点），页面切换 = 滚动定位。
const UiLayout := preload("res://scripts/ui/ui_layout.gd")

signal shop_closed

const HEAL_POTION_PRICE := 120
const HEAL_PCT := 0.25
const REFRESH_PRICE := 80
const BTN_H := 44.0
## 稀有度加权抽取：基础权重 common 60 / rare 25 / legendary 15；
## lucky（tag=lucky 道具总层数，当前仅 crit_lucky「幸运」）按稀有度梯度放大：
## weight = base × (1 + lucky × 0.06 × boost)，boost：common 1.0 / rare 2.0 / legendary 4.0；
## 归一化后不放回抽取（商店每次 3 把，55 把池）。UI 卡片已按 UiTheme.RARITY 上色，零改动。
const RARITY_WEIGHT := {"common": 60.0, "rare": 25.0, "legendary": 15.0}
const LUCKY_RARITY_BOOST := {"common": 1.0, "rare": 2.0, "legendary": 4.0}
const LUCKY_PER_STACK := 0.06

const PAGE_MENU := "menu"
const PAGE_ENHANCE := "enhance"
const PAGE_BUY := "buy"

var _mobile := false
var _card_w := 296.0
var _slot_w := 92.0
var _icon_sz := 56.0
var _name_sz := 12
var _desc_sz := 9
var _page := PAGE_MENU
var _scroll: ScrollContainer
var _content: VBoxContainer
var _menu_box: VBoxContainer
var _enhance_section: VBoxContainer
var _buy_section: VBoxContainer
var _box: VBoxContainer
var _owned_box: Container
var _gold_label: Label
var _pot_bought := false
var _upgraded := false
var _shop_open := false
var _offers: Array = []
var _replace_mode := false
var _pending_wand := ""

func _ready() -> void:
	_mobile = UiLayout.is_mobile()
	if _mobile:
		# 手机端紧凑：卡片 280 宽、图标 44、强化槽 2 列（135 宽），字号略小
		_card_w = 280.0
		_slot_w = 135.0
		_icon_sz = 44.0
		_name_sz = 11
		_desc_sz = 8
	_build_ui()
	hide()

func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.015, 0.04, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var panel := PanelContainer.new()
	UiLayout.center_panel(panel, UiLayout.panel_w(), UiLayout.panel_h() + 20.0)
	panel.custom_minimum_size = Vector2(UiLayout.panel_w(), UiLayout.panel_h() + 20.0)
	panel.add_theme_stylebox_override("panel", UiTheme.style(Color(0.07, 0.05, 0.11, 0.92), UiTheme.BORDER, 2, 8))
	root.add_child(panel)
	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 8)
	panel.add_child(main)
	var title := UiTheme.label("法杖商店", 18, UiTheme.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main.add_child(title)
	_gold_label = UiTheme.label("", 12, UiTheme.GOLD)
	_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gold_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main.add_child(_gold_label)
	# 中部可滚动区：选择/强化/购买三区块常驻（保证子节点始终完成排序），
	# 页面切换只改滚动位置；ScrollContainer 兜底防竖屏溢出
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 8)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_content)
	_menu_box = VBoxContainer.new()
	_menu_box.add_theme_constant_override("separation", 8)
	_menu_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(_menu_box)
	_enhance_section = VBoxContainer.new()
	_enhance_section.add_theme_constant_override("separation", 8)
	_enhance_section.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_content.add_child(_enhance_section)
	_buy_section = VBoxContainer.new()
	_buy_section.add_theme_constant_override("separation", 8)
	_buy_section.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_content.add_child(_buy_section)
	_build_menu_page()
	_build_enhance_page()
	_build_buy_page()

func _build_menu_page() -> void:
	## 选择页：两个大按钮（宽 220 高 64，手机 260）+ 药水/刷新/离开（44 高，拇指可达）
	var hint := UiTheme.label("请选择商店功能", 12, Color("#9d8fc4"))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu_box.add_child(hint)
	var btn_w: float = 260.0 if _mobile else 220.0
	var enhance := UiTheme.button("强化法杖", Vector2(btn_w, 64))
	enhance.name = "EnhanceBtn"
	enhance.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	enhance.pressed.connect(_goto_enhance)
	_menu_box.add_child(enhance)
	var buy := UiTheme.button("购买法杖", Vector2(btn_w, 64))
	buy.name = "BuyBtn"
	buy.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	buy.pressed.connect(_goto_buy)
	_menu_box.add_child(buy)
	var pot := UiTheme.button("恢复药水（%d金）" % HEAL_POTION_PRICE, Vector2(0, BTN_H))
	pot.name = "PotionBtn"
	pot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pot.pressed.connect(_buy_potion)
	_menu_box.add_child(pot)
	var refresh := UiTheme.button("刷新（%d金）" % REFRESH_PRICE, Vector2(0, BTN_H))
	refresh.name = "RefreshBtn"
	refresh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	refresh.pressed.connect(_refresh_offers)
	_menu_box.add_child(refresh)
	var leave := UiTheme.button("离开", Vector2(0, BTN_H))
	leave.name = "LeaveBtn"
	leave.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	leave.pressed.connect(_close_shop)
	_menu_box.add_child(leave)

func _build_enhance_page() -> void:
	## 强化页：返回按钮 + 已持有法杖强化卡（售出 50% 返还 / 强化 +8% 每级）
	var back := UiTheme.button("← 返回选择页", Vector2(_card_w, BTN_H))
	back.name = "BackBtnEnhance"
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(_goto_menu)
	_enhance_section.add_child(back)
	var owned_title := UiTheme.label("当前法杖（售出返还 50%，至少保留 1 把）", 10, Color("#9d8fc4"))
	owned_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_enhance_section.add_child(owned_title)
	if _mobile:
		_owned_box = GridContainer.new()
		(_owned_box as GridContainer).columns = 2
		_owned_box.add_theme_constant_override("h_separation", 8)
		_owned_box.add_theme_constant_override("v_separation", 8)
	else:
		_owned_box = HBoxContainer.new()
		_owned_box.add_theme_constant_override("separation", 8)
	_owned_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_enhance_section.add_child(_owned_box)

func _build_buy_page() -> void:
	## 购买页：返回按钮 + 今日上架 3 把随机法杖（稀有度加权）
	var back := UiTheme.button("← 返回选择页", Vector2(_card_w, BTN_H))
	back.name = "BackBtnBuy"
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(_goto_menu)
	_buy_section.add_child(back)
	var offer_title := UiTheme.label("今日上架", 10, Color("#9d8fc4"))
	offer_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_buy_section.add_child(offer_title)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_buy_section.add_child(_box)

func _section_scroll_y(section: Control) -> int:
	## 区块相对滚动内容顶部的偏移（页面切换用）
	var top: float = section.get_global_rect().position.y - _content.get_global_rect().position.y
	return int(top)

func _goto_menu() -> void:
	## 返回选择页：取消替换模式与待购法杖，滚动回顶部
	_replace_mode = false
	_pending_wand = ""
	_page = PAGE_MENU
	_refresh()
	_scroll.scroll_vertical = 0

func _goto_enhance() -> void:
	_page = PAGE_ENHANCE
	_scroll.scroll_vertical = _section_scroll_y(_enhance_section)

func _goto_buy() -> void:
	_page = PAGE_BUY
	_scroll.scroll_vertical = _section_scroll_y(_buy_section)

func show_shop() -> void:
	_pot_bought = false
	_upgraded = false
	_replace_mode = false
	_pending_wand = ""
	_shop_open = true
	_roll_offers()
	_page = PAGE_MENU
	_refresh()
	_scroll.scroll_vertical = 0
	show()

static func rarity_weight(rarity: String, lucky: int) -> float:
	## 稀有度权重：base × (1 + lucky × 0.06 × 稀有度梯度)
	var base: float = float(RARITY_WEIGHT.get(rarity, 10.0))
	var boost: float = float(LUCKY_RARITY_BOOST.get(rarity, 1.0))
	return base * (1.0 + float(maxi(lucky, 0)) * LUCKY_PER_STACK * boost)

func lucky_stacks() -> int:
	## tag=lucky 道具层数合计（按 tag 扫描：当前仅 crit_lucky「幸运」）
	var n := 0
	for item_id in GameState.run.items:
		var def := GameState.item_def(str(item_id))
		if not def.is_empty() and "lucky" in def.get("tags", []):
			n += int(GameState.run.items[item_id])
	return n

static func weighted_pick(wands: Array, lucky: int, count: int) -> Array:
	## 稀有度加权不放回抽取 count 把（权重归一化后轮盘采样）
	var pool: Array = wands.duplicate()
	var out: Array = []
	while out.size() < count and not pool.is_empty():
		var total := 0.0
		for i in pool.size():
			var w: Dictionary = pool[i]
			total += rarity_weight(str(w.get("rarity", "common")), lucky)
		var r := randf() * total
		var idx := 0
		for i in pool.size():
			var w: Dictionary = pool[i]
			r -= rarity_weight(str(w.get("rarity", "common")), lucky)
			if r <= 0.0:
				idx = i
				break
		out.append(pool[idx])
		pool.remove_at(idx)
	return out

func _roll_offers() -> void:
	var wands: Array = GameState.tables.get("wands", {}).get("wands", []).duplicate()
	# 不允许重复购买：排除当前已装备的全部法杖（最多 3 把）
	var owned := GameState.current_wands()
	for oid in owned:
		var ow: String = str(oid)
		wands = wands.filter(func(w): return str(w.get("id", "")) != ow)
	# 稀有度加权抽取（幸运越高，传说/稀有占比越高）
	_offers = weighted_pick(wands, lucky_stacks(), 3)

func _refresh() -> void:
	_gold_label.text = "持有金币：%d" % GameState.run.get("gold", 0)
	for c in _owned_box.get_children():
		c.queue_free()
	var owned := GameState.current_wands()
	for i in owned.size():
		var od := GameState.wand_def(str(owned[i]))
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(_slot_w, 64)
		slot.add_theme_stylebox_override("panel", UiTheme.style_compact(Color(0.12, 0.09, 0.19, 0.9), UiTheme.RARITY.get(str(od.get("rarity", "common")), UiTheme.BORDER), 1, 3))
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 2)
		slot.add_child(vb)
		var name_l := UiTheme.label(str(od.get("name", "?")), 10, UiTheme.WHITE)
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_l.custom_minimum_size = Vector2(0, 14)
		name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(name_l)
		var sell_btn := UiTheme.button("售出 %d金" % int(float(od.get("price", 0)) * 0.5), Vector2(84, BTN_H))
		sell_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		sell_btn.disabled = owned.size() <= 1
		sell_btn.pressed.connect(_sell_slot.bind(i))
		vb.add_child(sell_btn)
		var up_lv: int = GameState.wand_upgrade_level(str(owned[i]))
		var up_cost: int = GameState.wand_upgrade_cost(str(owned[i]))
		var up_text: String
		if up_lv > 0:
			up_text = "强化 Lv.%d（%d金）" % [up_lv, up_cost]
		else:
			up_text = "强化 +8%%（%d金）" % up_cost
		var up_btn := UiTheme.button(up_text, Vector2(84, BTN_H))
		if _mobile:
			up_btn.add_theme_font_size_override("font_size", 12)
			sell_btn.add_theme_font_size_override("font_size", 12)
		up_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		up_btn.disabled = _upgraded or GameState.run.get("gold", 0) < up_cost
		up_btn.pressed.connect(_upgrade_wand.bind(i))
		vb.add_child(up_btn)
		_owned_box.add_child(slot)
	for c in _box.get_children():
		c.queue_free()
	if not _replace_mode:
		for w in _offers:
			# 商品卡：图标+名称+描述+价格按钮内联（触屏不依赖 hover tooltip）；tooltip 仅桌面附加
			var card := PanelContainer.new()
			card.custom_minimum_size = Vector2(_card_w, 96)
			var border: Color = UiTheme.RARITY.get(str(w.get("rarity", "common")), UiTheme.BORDER)
			card.add_theme_stylebox_override("panel", UiTheme.style(Color("#1b1430"), border, 2, 5))
			card.tooltip_text = "%s（%s）\n%s\n价格 %d金 · 形态：%s" % [
				w.get("name", "?"),
				w.get("rarity", "common"),
				w.get("description", ""),
				int(w.get("price", 0)),
				w.get("shape", "none"),
			]
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			card.add_child(row)
			var tex := TextureRect.new()
			tex.texture = UiTheme.icon_texture(str(w.get("icon", "")))
			tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex.custom_minimum_size = Vector2(_icon_sz, _icon_sz)
			tex.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(tex)
			var info := VBoxContainer.new()
			info.add_theme_constant_override("separation", 2)
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(info)
			var name_l := UiTheme.label(str(w.get("name", "?")), _name_sz, UiTheme.RARITY.get(str(w.get("rarity", "common")), UiTheme.WHITE))
			name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			info.add_child(name_l)
			# 描述：min 宽度 180 避免 autowrap Label 在 min-size 计算时按 1px 换行
			# 导致卡片最小高度膨胀到数百 px；描述行数由实际宽度决定，溢出由卡片包裹裁切
			var desc := UiTheme.label(str(w.get("description", "")), _desc_sz, Color("#c8c0e0"))
			desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			desc.custom_minimum_size = Vector2(180, 26)
			desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
			info.add_child(desc)
			var price := int(w.get("price", 0))
			var affordable: bool = GameState.run.get("gold", 0) >= price
			var buy := UiTheme.button("%d金·购买" % price, Vector2(120, BTN_H))
			buy.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			buy.disabled = not affordable
			buy.pressed.connect(_buy_wand.bind(str(w.get("id", ""))))
			info.add_child(buy)
			_box.add_child(card)
	else:
		# 替换模式：提示 + 当前 3 把法杖供选择替换（纵向 44 高按钮）
		_gold_label.text = "已拥有 3 把法杖——请选择要替换的一把（新法杖：%s）" % str(GameState.wand_def(_pending_wand).get("name", "?"))
		var hint := UiTheme.label("替换模式：请选择要替换的法杖", 12, UiTheme.GOLD)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_box.add_child(hint)
		var owned2 := GameState.current_wands()
		for i in owned2.size():
			var od := GameState.wand_def(str(owned2[i]))
			var slot := Button.new()
			UiTheme.apply_font(slot, 13)
			slot.custom_minimum_size = Vector2(_card_w, BTN_H)
			slot.add_theme_stylebox_override("normal", UiTheme.style(Color(0.12, 0.09, 0.19, 0.9), UiTheme.BORDER_DIM, 2, 4))
			slot.add_theme_stylebox_override("hover", UiTheme.style(Color(0.16, 0.12, 0.26, 0.95), UiTheme.GOLD, 2, 4))
			slot.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
			slot.text = "替换：%s" % str(od.get("name", "?"))
			slot.pressed.connect(_replace_slot.bind(i))
			_box.add_child(slot)

func _sell_slot(idx: int) -> void:
	var refund: int = GameState.sell_wand(idx)
	if refund > 0:
		EventBus.fx_explosion.emit(Vector2(320, 180), "gold")
		_refresh()

func _upgrade_wand(idx: int) -> void:
	## 强化已持有法杖（每店 1 次）：+8% 伤害/级，价格 200 起每级 +100
	if _upgraded:
		return
	var owned: Array = GameState.current_wands()
	if idx < 0 or idx >= owned.size():
		return
	if GameState.upgrade_wand(str(owned[idx])):
		_upgraded = true
		EventBus.fx_explosion.emit(Vector2(320, 180), "gold")
		_refresh()

func _buy_wand(wand_id: String) -> void:
	var def := GameState.wand_def(wand_id)
	var price := int(def.get("price", 0))
	if GameState.run.get("gold", 0) < price:
		return
	# 已满 3 把：进入替换模式，选择要替换的槽位
	if GameState.current_wands().size() >= 3:
		_replace_mode = true
		_pending_wand = wand_id
		_refresh()
		return
	GameState.run.gold -= price
	GameState.add_wand(wand_id)
	EventBus.fx_explosion.emit(Vector2(320, 180), "gold")
	_close_shop()  # 购买完成：自动关闭商店进入下一关

func _replace_slot(idx: int) -> void:
	## 替换模式下：用待购法杖替换指定槽位，扣款并关闭商店
	if _pending_wand.is_empty():
		return
	var def := GameState.wand_def(_pending_wand)
	var price := int(def.get("price", 0))
	if GameState.run.get("gold", 0) < price:
		return
	GameState.run.gold -= price
	GameState.replace_wand(idx, _pending_wand)
	_pending_wand = ""
	_replace_mode = false
	EventBus.fx_explosion.emit(Vector2(320, 180), "gold")
	_close_shop()

func autoplay_handle() -> void:
	## 自动脚本（v2 选择逻辑）：优先强化最便宜可负担的 → 否则购买 → 否则离开；
	## 替换模式优先处理（选第一个槽位）
	if _replace_mode:
		_replace_slot(0)
		return
	var gold: int = GameState.run.get("gold", 0)
	if not _upgraded:
		var owned := GameState.current_wands()
		var best_idx := -1
		var best_cost := 1 << 30
		for i in owned.size():
			var cost := GameState.wand_upgrade_cost(str(owned[i]))
			if cost <= gold and cost < best_cost:
				best_cost = cost
				best_idx = i
		if best_idx >= 0:
			_upgrade_wand(best_idx)
			return
	var best_price := 0
	var best_id := ""
	for w in _offers:
		var price := int(w.get("price", 0))
		if price <= gold and price > best_price:
			best_price = price
			best_id = str(w.get("id", ""))
	if best_id != "":
		_buy_wand(best_id)
	else:
		_close_shop()

func _buy_potion() -> void:
	if _pot_bought:
		return
	if GameState.run.get("gold", 0) < HEAL_POTION_PRICE:
		return
	GameState.run.gold -= HEAL_POTION_PRICE
	_pot_bought = true
	GameState.heal(GameState.run.max_hp * HEAL_PCT)
	_refresh()

func _refresh_offers() -> void:
	if GameState.run.get("gold", 0) < REFRESH_PRICE:
		return
	GameState.run.gold -= REFRESH_PRICE
	_roll_offers()
	_refresh()

func _close_shop() -> void:
	if not _shop_open:
		return  # 防重入：快速连点离开不会重复推进关卡
	_shop_open = false
	hide()
	shop_closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if _shop_open and event.is_action_pressed("pause"):
		_close_shop()
		get_viewport().set_input_as_handled()
