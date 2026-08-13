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
const REFRESH_PRICE_MAX := 480  # 问题16：刷新费递增上限（80→160→320→480 封顶）
const BTN_H := 44.0
## 稀有度加权抽取（2026-08-13 五档实施，见 docs/design/稀有度五档方案.md §5.2）：
## 基础权重 common 100 / uncommon 70 / rare 30 / epic 20 / legendary 6；
## 池 7/6/11/10/21（白/绿/蓝/金/红）下 lucky=0 实出约 白39%/绿24%/蓝19%/金11%/红7%，
## lucky=10（crit_lucky「幸运」10 层）实出约 白32%/绿22%/蓝20%/金14%/红12% ——
## 两档均保持 白>绿>蓝>金>红 严格递减，红 +5pp（越稀有越难出）。
## lucky 按稀有度梯度放大：weight = base × (1 + lucky × 0.06 × boost)，
## boost：common 1.0 / uncommon 1.5 / rare 2.0 / epic 2.5 / legendary 4.0。
## 归一化后不放回抽取（商店每次 3 把，55 把池）。UI 卡片已按 UiTheme.RARITY 上色，零改动。
const RARITY_WEIGHT := {"common": 100.0, "uncommon": 70.0, "rare": 30.0, "epic": 20.0, "legendary": 6.0}
const LUCKY_RARITY_BOOST := {"common": 1.0, "uncommon": 1.5, "rare": 2.0, "epic": 2.5, "legendary": 4.0}
const LUCKY_PER_STACK := 0.06

const PAGE_MENU := "menu"
const PAGE_ENHANCE := "enhance"
const PAGE_BUY := "buy"
const PAGE_BUILD := "build"  # 问题15：商店购买构筑页
const MAT_ICON_PATH := "res://assets/icons/shikashi/shikashi_r12_c10.png"  # 材料金币堆（Brotato 材料位）

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
var _build_section: VBoxContainer
var _box: Container  # 预存类型错误修复：Brotato 改造改赋 GridContainer，基类收敛
var _owned_box: Container
var _gold_label: Label
var _refresh_btn: Button  # 刷新按钮（_refresh 时实时更新价格文字，问题3）
var _mat_icon: TextureRect  # 顶栏材料图标（Brotato 材料位）
var _enhance_banner: Label  # 强化成功金色横幅（强化效果即时可见）
var _pot_bought := false
var _upgraded := false
var _build_bought := false  # 用户需求：构筑商店每局只允许购买 1 次
var _shop_open := false
var _offers: Array = []
var _replace_mode := false
var _pending_wand := ""
var _refresh_count := 0  # 问题16：本店刷新次数（刷新费递增）
var _locked: Array = []  # 商品卡锁定态（与 _offers 平行；锁定卡刷新保留且保价）
var _build_offers: Array = []  # 问题15：本店构筑购买选项
const BUILD_ITEM_PRICE := 120   # 构筑购买单价（传说/稀有按稀有度加价见 _build_price）
var _build_box: VBoxContainer
const BUILD_REROLL_PRICE := 60  # 构筑换一批价格

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
	## Brotato 顶栏：左=标题（波次号），右=材料图标+数量；下加 1px 分隔线
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	main.add_child(top)
	var title := UiTheme.label("第 %d 波 · 商店" % maxi(int(GameState.run.get("level", 1)), 1), 16, UiTheme.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	_mat_icon = UiTheme.icon(MAT_ICON_PATH, Vector2(16, 16))
	top.add_child(_mat_icon)
	_gold_label = UiTheme.label("0", 12, UiTheme.GOLD, true)
	top.add_child(_gold_label)
	var sep := ColorRect.new()
	sep.color = UiTheme.BORDER_DIM
	sep.custom_minimum_size = Vector2(0, 1)
	sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_child(sep)
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
	_build_section = VBoxContainer.new()
	_build_section.add_theme_constant_override("separation", 8)
	_build_section.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_content.add_child(_build_section)
	_build_menu_page()
	_build_enhance_page()
	_build_buy_page()
	_build_build_page()

func _build_menu_page() -> void:
	## 选择页（2026-08-11 用户确认）：五个按钮 = 强化法杖 / 购买法杖 / 回血 / 购买构筑 / 关闭
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
	var build := UiTheme.button("购买构筑", Vector2(btn_w, 64))
	build.name = "BuildBtn"
	build.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	build.pressed.connect(_goto_build)
	_menu_box.add_child(build)
	## 2026-08-12：按钮顺序 = 强化→购买→构筑→回血→下一波（"关闭"按钮已删除，
	## 离开商店统一由金色"开始下一波"完成，避免两个退出入口）
	var pot := UiTheme.button("回血（%d金）" % HEAL_POTION_PRICE, Vector2(btn_w, 64))
	pot.name = "PotionBtn"
	pot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pot.pressed.connect(_buy_potion)
	_menu_box.add_child(pot)
	## Brotato：底部金色大按钮"开始下一波"（唯一退出入口，点击直接回战斗）
	var next_wave := UiTheme.button_gold("开始下一波", Vector2(296.0 if not _mobile else 280.0, 48))
	next_wave.name = "NextWaveBtn"
	next_wave.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	next_wave.pressed.connect(_close_shop)
	_menu_box.add_child(next_wave)

func _build_enhance_page() -> void:
	## 强化页：返回按钮 + 已持有法杖强化卡（售出 50% 返还 / 强化 +8% 每级）
	var back := UiTheme.button("← 返回选择页", Vector2(_card_w, BTN_H))
	back.name = "BackBtnEnhance"
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(_goto_menu)
	_enhance_section.add_child(back)
	## 强化成功横幅（默认隐藏；_upgrade_wand 成功后置可见，展示约 1s 后关闭商店）
	_enhance_banner = UiTheme.label("", 13, UiTheme.GOLD, true)
	_enhance_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_enhance_banner.visible = false
	_enhance_section.add_child(_enhance_banner)
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
	## 购买页（2026-08-10）：返回按钮 + 刷新（原在选择页）+ 今日上架 3 把随机法杖
	var back := UiTheme.button("← 返回选择页", Vector2(_card_w, BTN_H))
	back.name = "BackBtnBuy"
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(_goto_menu)
	_buy_section.add_child(back)
	var refresh := UiTheme.button("刷新（%d金）" % _refresh_price(), Vector2(_card_w, BTN_H))
	refresh.name = "RefreshBtn"
	_refresh_btn = refresh
	refresh.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	refresh.pressed.connect(_refresh_offers)
	_buy_section.add_child(refresh)
	var offer_title := UiTheme.label("今日上架", 10, Color("#9d8fc4"))
	offer_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_buy_section.add_child(offer_title)
	## Brotato：商品卡 2 列网格（PC/手机统一），卡 138x150
	_box = GridContainer.new()
	_box.columns = 1  ## 用户需求：购买法杖页每个法杖一行
	_box.add_theme_constant_override("h_separation", 8)
	_box.add_theme_constant_override("v_separation", 8)
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_buy_section.add_child(_box)


func _build_build_page() -> void:
	## 问题15：购买构筑独立页——随机 3 个构筑选项（稀有度加权），金币购买
	var back := UiTheme.button("← 返回选择页", Vector2(_card_w, BTN_H))
	back.name = "BackBtnBuild"
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(_goto_menu)
	_build_section.add_child(back)
	var title := UiTheme.label("构筑商店（金币购买构筑）", 11, Color("#9d8fc4"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_build_section.add_child(title)
	_build_box = VBoxContainer.new()
	_build_box.add_theme_constant_override("separation", 8)
	_build_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_section.add_child(_build_box)
	var reroll := UiTheme.button("换一批（%d金）" % BUILD_REROLL_PRICE, Vector2(_card_w, BTN_H))
	reroll.name = "BuildRerollBtn"
	reroll.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	reroll.pressed.connect(_reroll_build_offers)
	_build_section.add_child(reroll)

func _section_scroll_y(section: Control) -> int:
	## 区块相对滚动内容顶部的偏移（页面切换用）
	var top: float = section.get_global_rect().position.y - _content.get_global_rect().position.y
	return int(top)

func _goto_menu() -> void:
	## 返回选择页：取消替换模式与待购法杖，滚动回顶部
	_replace_mode = false
	_pending_wand = ""
	_page = PAGE_MENU
	_apply_page()
	_refresh()
	_scroll.scroll_vertical = 0

func _goto_enhance() -> void:
	_page = PAGE_ENHANCE
	_apply_page()
	_refresh()  # 2026-08-10：切页重建卡片——Godot 隐藏容器不排序，visible 切换后需重建布局
	_scroll.scroll_vertical = 0
	if _enhance_banner != null:
		_enhance_banner.visible = false

func _goto_buy() -> void:
	_page = PAGE_BUY
	_apply_page()
	_refresh()
	_scroll.scroll_vertical = 0

func _goto_build() -> void:
	## 问题15：进入构筑购买页（首次进入生成选项）
	if _build_offers.is_empty():
		_roll_build_offers()
	_page = PAGE_BUILD
	_apply_page()
	_refresh()
	_scroll.scroll_vertical = 0

func _apply_page() -> void:
	## 页面切换：显式控制区块可见性（2026-08-10 修复——此前仅靠滚动定位切换，
	## 内容总高 ≤ 视口时滚动范围为零，选择页与购买页同时可见）
	if _menu_box == null:
		return
	_menu_box.visible = (_page == PAGE_MENU)
	_enhance_section.visible = (_page == PAGE_ENHANCE)
	_buy_section.visible = (_page == PAGE_BUY)
	_build_section.visible = (_page == PAGE_BUILD)

func show_shop() -> void:
	_pot_bought = false
	_upgraded = false
	_replace_mode = false
	_pending_wand = ""
	_refresh_count = 0  # 问题16：每次开店刷新费重置
	_locked = []        # 每次进店重置锁定
	_build_offers = []   # 问题15：每次开店重新生成构筑货架
	_build_bought = false
	_shop_open = true
	if _enhance_banner != null:
		_enhance_banner.visible = false
	_roll_offers()
	_page = PAGE_MENU
	_apply_page()
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
	# 锁定商品保留（Brotato：锁定卡不随刷新更换且保价），其余位重新抽取
	var kept: Array = []
	var keep_ids := {}
	for i in _offers.size():
		if _locked.size() > i and _locked[i]:
			kept.append(_offers[i])
			keep_ids[str(_offers[i].get("id", ""))] = true
	wands = wands.filter(func(w): return not keep_ids.has(str(w.get("id", ""))))
	var need: int = 3 - kept.size()
	if need > 0:
		kept.append_array(weighted_pick(wands, lucky_stacks(), need))
	_offers = kept
	# 锁定数组与货架同步（截断/补 false）
	while _locked.size() < _offers.size():
		_locked.append(false)
	_locked = _locked.slice(0, _offers.size())

func _refresh() -> void:
	_gold_label.text = str(GameState.run.get("gold", 0))
	if _refresh_btn != null:
		_refresh_btn.text = "刷新（%d金）" % _refresh_price()
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
		## 强化效果展示：当前等级 + 伤害加成/新数值（落雷修复落地 wand_shop 强化显示）
		var lv: int = GameState.wand_upgrade_level(str(owned[i]))
		var pct := int(roundf(GameState.WAND_UPGRADE_BONUS * 100.0))
		## 2026-08-12：全角竖线 U+FF5C 不在中文字体子集内会显示码点，改用子集覆盖的间隔号 ·
		var stat_text := "Lv.%d · 伤害 +%d%%（×%.2f）" % [lv, pct * lv, 1.0 + GameState.WAND_UPGRADE_BONUS * float(lv)]
		var stat_l := UiTheme.label(stat_text, 9, UiTheme.GOLD if lv > 0 else Color("#7a7298"))
		stat_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stat_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(stat_l)
		var sell_btn := UiTheme.button("售出 %d金" % int(float(od.get("price", 0)) * 0.5), Vector2(84, BTN_H))
		sell_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		sell_btn.disabled = owned.size() <= 1
		sell_btn.pressed.connect(_sell_slot.bind(i))
		vb.add_child(sell_btn)
		var up_cost: int = GameState.wand_upgrade_cost(str(owned[i]))
		var up_text: String
		if lv > 0:
			up_text = "强化 Lv.%d（%d金）" % [lv, up_cost]
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
		for i in _offers.size():
			_box.add_child(_make_offer_card(_offers[i], i))
	else:
		# 替换模式：提示 + 当前 3 把法杖供选择替换（纵向 44 高按钮）
		var hint := UiTheme.label("替换模式：请选择要替换的法杖（新法杖：%s）" % str(GameState.wand_def(_pending_wand).get("name", "?")), 12, UiTheme.GOLD)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_box.add_child(hint)
		var owned2 := GameState.current_wands()
		for i in owned2.size():
			var od := GameState.wand_def(str(owned2[i]))
			var slot := Button.new()
			UiTheme.apply_font(slot, 13)
			slot.custom_minimum_size = Vector2(0, BTN_H)
			slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			slot.add_theme_stylebox_override("normal", UiTheme.style(Color(0.12, 0.09, 0.19, 0.9), UiTheme.BORDER_DIM, 2, 4))
			slot.add_theme_stylebox_override("hover", UiTheme.style(Color(0.16, 0.12, 0.26, 0.95), UiTheme.GOLD, 2, 4))
			slot.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
			slot.text = "替换：%s" % str(od.get("name", "?"))
			slot.pressed.connect(_replace_slot.bind(i))
			_box.add_child(slot)
	_refresh_build()


func _roll_build_offers() -> void:
	## 问题15：构筑商店选项 = 升级三选一生成器（稀有度加权 + 元素联动），过滤已持有满层的
	var offers: Array = GameState.roll_item_choices(4)
	var kept: Array = []
	for it in offers:
		var id: String = str(it.get("id", ""))
		if id.begins_with("spell_part:"):
			kept.append(it)
			continue
		var stacks: int = GameState.total_stacks(id)
		if stacks < 5:  # 已满 5 层的构筑不再上架（避免买了没用）
			kept.append(it)
	_build_offers = kept


func _reroll_build_offers() -> void:
	## 问题15：构筑换一批（花费递增同法杖刷新）
	var price := _refresh_price()
	if GameState.run.get("gold", 0) < price:
		return
	GameState.run.gold -= price
	SfxBus.play_hit("buy")  # 打击感 G-1：购买音
	_refresh_count += 1
	_roll_build_offers()
	_refresh()


func _build_price(def: Dictionary) -> int:
	## 问题15：构筑价格按稀有度五档（common 80 / uncommon 110 / rare 150 /
	## epic 200 / legendary 260），比法杖便宜鼓励消费（2026-08-13 五档实施）
	var rarity: String = str(def.get("rarity", "common"))
	match rarity:
		"legendary":
			return 260
		"epic":
			return 200
		"rare":
			return 150
		"uncommon":
			return 110
	return 80


func _buy_build_item(def: Dictionary) -> void:
	## 问题15：购买构筑——法术部件走 add_spell_part，道具走 add_item
	if _build_bought:
		return
	var price := _build_price(def)
	if GameState.run.get("gold", 0) < price:
		return
	GameState.run.gold -= price
	SfxBus.play_hit("buy")  # 打击感 G-1：购买音
	var id: String = str(def.get("id", ""))
	if id.begins_with("spell_part:"):
		var parts := id.split(":")
		GameState.add_spell_part(
			parts[1] if parts.size() > 1 else "",
			parts[2] if parts.size() > 2 else "")
	else:
		GameState.add_item(id)
	EventBus.fx_explosion.emit(Vector2(320, 180), "gold")
	_build_bought = true
	_roll_build_offers()  # 买一件换一件，保持货架 3-4 件
	_refresh()
	## 2026-08-12：构筑购买完成 → 0.5s 展示购买成功后自动关闭商店（与购买法杖一致进入下一关）
	## 2026-08-13（修复2）：process_always=true —— 商店打开时 get_tree().paused=true，
	## 普通 create_timer 在暂停期不触发，这是用户反馈"买完构筑不关商店"的根因
	get_tree().create_timer(0.5, true).timeout.connect(_finish_build_close)


func _refresh_build() -> void:
	## 问题15：构筑购买页卡片（图标+名称+流派标签+价格按钮）
	if _build_box == null:
		return
	for c in _build_box.get_children():
		c.queue_free()
	if _build_offers.is_empty():
		_build_box.add_child(UiTheme.label("（没有可购买的构筑）", 11, Color("#5a5278")))
		return
	if _build_bought:
		_build_box.add_child(UiTheme.label("（本局已购买构筑）", 11, Color("#c9a24b")))
		return
	for def in _build_offers:
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(_card_w, 92)
		var border: Color = UiTheme.RARITY.get(str(def.get("rarity", "common")), UiTheme.BORDER)
		card.add_theme_stylebox_override("panel", UiTheme.style(Color("#1b1430"), border, 2, 5))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		card.add_child(row)
		var tex := TextureRect.new()
		tex.texture = UiTheme.icon_texture(str(def.get("icon", "")))
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
		## 流派标签（用户需求）：名称前显示【火】【防御】等
		var schools := GameState.schools_of_item(def)
		var tag := ""
		if not schools.is_empty():
			var names: Array = []
			for s in schools:
				names.append(GameState.SCHOOL_NAMES.get(str(s), str(s)))
			tag = "【" + "、".join(names) + "】"
		var name_l := UiTheme.label(tag + str(def.get("name", "?")), _name_sz, UiTheme.RARITY.get(str(def.get("rarity", "common")), UiTheme.WHITE))
		name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info.add_child(name_l)
		var desc := UiTheme.label(str(def.get("description", "")), _desc_sz, Color("#c8c0e0"))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(180, 26)
		desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info.add_child(desc)
		var price := _build_price(def)
		var buy := UiTheme.button("%d金·购买" % price, Vector2(120, BTN_H))
		buy.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		buy.disabled = GameState.run.get("gold", 0) < price
		buy.pressed.connect(_buy_build_item.bind(def))
		info.add_child(buy)
		_build_box.add_child(card)


static func _lock_tex(locked: bool) -> ImageTexture:
	## 程序化像素挂锁 16x16（方案素材缺口 #3：锁图标程序化兜底）
	var im := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	im.fill(Color(0, 0, 0, 0))
	var body: Color = UiTheme.GOLD if locked else Color(0.42, 0.48, 0.58)
	var dark: Color = Color("#5e470f") if locked else Color(0.25, 0.29, 0.36)
	# 锁体（6..15 行，3..12 列）+ 暗色描边
	for y in range(6, 16):
		for x in range(3, 13):
			im.set_pixel(x, y, body)
	for y in range(6, 16):
		im.set_pixel(2, y, dark)
		im.set_pixel(13, y, dark)
	for x in range(3, 13):
		im.set_pixel(x, 15, dark)
	# 锁梁（1..5 行，4..11 列）
	for y in range(1, 6):
		im.set_pixel(4, y, body)
		im.set_pixel(11, y, body)
	for x in range(4, 12):
		im.set_pixel(x, 1, body)
	# 钥匙孔
	for y in range(9, 13):
		im.set_pixel(7, y, dark)
		im.set_pixel(8, y, dark)
	im.set_pixel(7, 8, dark)
	im.set_pixel(8, 8, dark)
	return ImageTexture.create_from_image(im)


func _make_offer_card(w: Dictionary, idx: int) -> Control:
	## 商品卡（用户需求）：每行一个法杖——图标 + 名称/稀有度 + 描述 + 价格购买按钮 + 锁钮
	var locked: bool = _locked.size() > idx and _locked[idx]
	var rar: String = str(w.get("rarity", "common"))
	var border: Color = UiTheme.GOLD if locked else UiTheme.RARITY.get(rar, UiTheme.BORDER)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(_card_w, 72)
	card.add_theme_stylebox_override("panel", UiTheme.style(UiTheme.PANEL_CARD, border, 2 if locked else 1, 5))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	var tex := TextureRect.new()
	tex.texture = UiTheme.icon_texture(str(w.get("icon", "")))
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.custom_minimum_size = Vector2(48, 48)
	tex.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(tex)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(info)
	var name_l := UiTheme.label(str(w.get("name", "?")), _name_sz, UiTheme.RARITY.get(rar, UiTheme.WHITE))
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(name_l)
	var desc_l := UiTheme.label(str(w.get("description", "")), _desc_sz, Color("#c8c0e0"))
	desc_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_l.custom_minimum_size = Vector2(150, 26)
	desc_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(desc_l)
	var buy_col := VBoxContainer.new()
	buy_col.add_theme_constant_override("separation", 4)
	buy_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buy_col.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(buy_col)
	var buy_btn := UiTheme.button("%d金 · 购买" % int(w.get("price", 0)), Vector2(104, BTN_H))
	buy_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	buy_btn.disabled = GameState.run.get("gold", 0) < int(w.get("price", 0))
	buy_btn.pressed.connect(_buy_wand.bind(str(w.get("id", ""))))
	buy_col.add_child(buy_btn)
	# 右上角锁钮（20x20；子按钮先于卡片收到点击）
	return card


func _toggle_lock(idx: int) -> void:
	## 锁定/解锁商品卡：锁定卡在刷新时保留（保价），边框变金
	if idx < 0 or idx >= _offers.size():
		return
	while _locked.size() <= idx:
		_locked.append(false)
	_locked[idx] = not bool(_locked[idx])
	_refresh()

func _sell_slot(idx: int) -> void:
	var refund: int = GameState.sell_wand(idx)
	if refund > 0:
		EventBus.fx_explosion.emit(Vector2(320, 180), "gold")
		_refresh()

func _upgrade_wand(idx: int) -> void:
	## 强化已持有法杖（每店 1 次）：+8% 伤害/级，价格 250 起每级 +100
	if _upgraded:
		return
	var owned: Array = GameState.current_wands()
	if idx < 0 or idx >= owned.size():
		return
	var wid: String = str(owned[idx])
	if GameState.upgrade_wand(wid):
		_upgraded = true
		var lv: int = GameState.wand_upgrade_level(wid)
		EventBus.fx_explosion.emit(Vector2(320, 180), "gold")
		_refresh()  # 卡片即时更新：当前等级/伤害加成/强化按钮文本
		## 强化成功金色横幅：展示强化效果与数值变化
		if _enhance_banner != null:
			_enhance_banner.text = "强化成功 +%d%%！伤害 ×%.2f（Lv.%d）" % [
				int(roundf(GameState.WAND_UPGRADE_BONUS * 100.0)),
				1.0 + GameState.WAND_UPGRADE_BONUS * float(lv),
				lv,
			]
			_enhance_banner.visible = true
		## 强化完成即关闭商店（与购买法杖一致）：短暂展示强化效果后进入下一关
		## 2026-08-13（修复2）：同构筑购买，process_always=true 避免暂停期不触发
		get_tree().create_timer(1.0, true).timeout.connect(_finish_enhance_close)


func _finish_enhance_close() -> void:
	## 强化成功展示延时结束 → 关闭商店（节点释放后信号连接自动失效；已被其他路径关闭则跳过）
	if _shop_open:
		_close_shop()

func _finish_build_close() -> void:
	## 构筑购买成功展示延时结束 → 关闭商店（节点释放后信号连接自动失效；已被其他路径关闭则跳过）
	if _shop_open:
		_close_shop()

func _buy_wand(wand_id: String) -> void:
	var def := GameState.wand_def(wand_id)
	var price := int(def.get("price", 0))
	if GameState.run.get("gold", 0) < price:
		return
	# 已满槽位上限（问题14：3 + 扩容饰品）：进入替换模式，选择要替换的槽位
	if GameState.current_wands().size() >= GameState.max_wand_slots():
		_replace_mode = true
		_pending_wand = wand_id
		_refresh()
		return
	GameState.run.gold -= price
	SfxBus.play_hit("buy")  # 打击感 G-1：购买音
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
	SfxBus.play_hit("buy")  # 打击感 G-1：购买音
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
		# 2026-08-10：买不起法杖且有富余金币时先回血（限购 1 次），否则关闭
		if not _pot_bought and gold >= HEAL_POTION_PRICE:
			_buy_potion()
		else:
			_close_shop()

func _buy_potion() -> void:
	if _pot_bought:
		return
	if GameState.run.get("gold", 0) < HEAL_POTION_PRICE:
		return
	GameState.run.gold -= HEAL_POTION_PRICE
	SfxBus.play_hit("buy")  # 打击感 G-1：购买音
	_pot_bought = true
	GameState.heal(GameState.run.max_hp * HEAL_PCT)
	_refresh()

func _refresh_offers() -> void:
	var price := _refresh_price()
	if GameState.run.get("gold", 0) < price:
		return
	GameState.run.gold -= price
	SfxBus.play_hit("buy")  # 打击感 G-1：购买音
	_refresh_count += 1
	_roll_offers()
	_refresh()


func _refresh_price() -> int:
	## 问题16：刷新费递增（每次 ×2，封顶 480），鼓励玩家一次买齐
	return mini(REFRESH_PRICE * (1 << _refresh_count), REFRESH_PRICE_MAX)

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
