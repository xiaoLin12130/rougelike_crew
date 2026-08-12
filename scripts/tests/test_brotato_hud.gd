extends SceneTree
## 土豆兄弟 UI 适配专项测试（2026-08-12，docs/design/土豆兄弟UI适配方案.md §5）：
## ① 左上资源区（HP/材料/Lv徽章+XP条/关卡·DPS）与底部武器栏不重叠；
## ② Boss 血条与经验条互斥，且 Boss 出现不隐藏经验条；
## ③ 底部武器/法术栏：PC 5 格单行 / 手机 3+2 两行（Grid 3 列），图标+×N 角标；
## ④ 波次横幅：顶部中右 + 倒计时 + 计时条；Boss 在场自动隐藏；
## ⑤ 商店：2 列商品卡网格 + 每卡锁钮 + 顶栏材料图标 + "开始下一波"金色大按钮。
## Run: godot --headless --path . -s res://scripts/tests/test_brotato_hud.gd

var failures: Array[String] = []
var _frame := 0
var _phase := 0
var _hud: CanvasLayer
var _hud_mobile: CanvasLayer
var _shop: CanvasLayer

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false
	match _phase:
		0:
			_setup()
			_phase = 1
		1:
			_assert_pc_hud()
			_phase = 2
		2:
			UiLayout.force_mobile(true)
			_hud_mobile = load("res://scenes/ui/hud.tscn").instantiate()
			_hud_mobile.name = "HUDMobile"
			root.add_child(_hud_mobile)
			_phase = 3
		3:
			_assert_mobile_hud()
			UiLayout.force_mobile(false)
			_phase = 4
		4:
			_assert_shop()
			_phase = 5
		5:
			_assert_wave_banner()
			if failures.is_empty():
				print("BROTATO HUD ALL PASS")
			else:
				for f in failures:
					push_error("BROTATO FAIL: " + f)
			quit(0 if failures.is_empty() else 1)
			return true
	return false

func fail(msg: String) -> void:
	failures.append(msg)
	print("[BROTATO] FAIL: " + msg)

func _setup() -> void:
	root.size = Vector2i(360, 640)
	var gs: Node = root.get_node_or_null("GameState")
	if gs == null:
		fail("GameState autoload missing")
		return
	gs.new_run()
	gs.run.items = {"attack_speed_potion": 2, "strength_badge": 3}
	gs.run.grid = [
		{"core": "fireball", "shell": ""},
		{"core": "fireball", "shell": "rapid"},
		{"core": "ice_shard", "shell": ""},
	]
	_hud = load("res://scenes/ui/hud.tscn").instantiate()
	_hud.name = "HUD"
	root.add_child(_hud)
	_shop = load("res://scenes/ui/wand_shop.tscn").instantiate()
	_shop.name = "WandShop"
	root.add_child(_shop)
	_shop.show_shop()

func _rect(c: Control) -> Rect2:
	return c.get_global_rect()

func _assert_pc_hud() -> void:
	var res := _rect(_hud._res_box)
	var xp := _rect(_hud._xp_bar)
	var weapon := _rect(_hud._weapon_bar)
	var screen := Rect2(Vector2.ZERO, Vector2(360, 640))
	# 资源区/XP条/武器栏位置不重叠
	if weapon.intersects(res):
		fail("武器栏与资源区重叠: %s / %s" % [str(weapon), str(res)])
	if weapon.intersects(xp):
		fail("武器栏与 XP 条重叠: %s / %s" % [str(weapon), str(xp)])
	if not res.encloses(xp):
		fail("XP 条不在资源区内: xp=%s res=%s" % [str(xp), str(res)])
	if not screen.encloses(res) or not screen.encloses(weapon):
		fail("资源区/武器栏越出视口")
	# 材料图标存在（Brotato 材料位）
	if _hud._mat_icon == null or _hud._mat_icon.texture == null:
		fail("HUD 缺少材料图标")
	# Lv 徽章与 XP 条同排（同一行内）
	var badge := _rect(_hud._lv_badge)
	if absf(badge.position.y - xp.position.y) > 5.0:
		fail("Lv 徽章未与 XP 条同排: badge=%s xp=%s" % [str(badge), str(xp)])
	# PC 武器栏：5 格单行（HBox），无 ×N 角标缺失
	if _hud._weapon_bar is HBoxContainer:
		if _hud._weapon_slots.size() != 5:
			fail("PC 武器栏槽位数 != 5: " + str(_hud._weapon_slots.size()))
		var y0 := -1.0
		for s in _hud._weapon_slots:
			var r := _rect(s)
			if y0 < 0:
				y0 = r.position.y
			elif absf(r.position.y - y0) > 2.0:
				fail("PC 武器栏未单行排列: " + str(r))
				break
	else:
		fail("PC 武器栏应为 HBox 单行，实际: " + str(_hud._weapon_bar.get_class()))
	# 堆叠角标：fireball 出现 ×2
	var has_x2 := false
	for s in _hud._weapon_slots:
		if _label_text(s).contains("×2"):
			has_x2 = true
	if not has_x2:
		fail("武器栏缺少 ×N 堆叠角标（fireball ×2）")
	# Boss 与经验条互斥 + 不隐藏
	var bus: Node = root.get_node_or_null("EventBus")
	if bus != null:
		bus.boss_spawned.emit("暗影魔像", 500)
	if not _hud._xp_bar.visible:
		fail("Boss 出现后经验条被隐藏")
	var boss := _rect(_hud._boss_root)
	if boss.intersects(xp):
		fail("Boss 血条与经验条重叠: %s / %s" % [str(boss), str(xp)])

func _label_text(node: Node) -> String:
	if node is Label:
		return str((node as Label).text)
	for ch in node.get_children():
		var t := _label_text(ch)
		if t != "":
			return t
	return ""

func _assert_mobile_hud() -> void:
	# 手机：Grid 3 列两行（3+2），5 格，槽位 >=44px
	var bar: Control = _hud_mobile._weapon_bar
	if bar == null or not (bar is GridContainer):
		fail("手机武器栏应为 GridContainer: " + str(bar))
		return
	if (bar as GridContainer).columns != 3:
		fail("手机武器栏列数 != 3: " + str((bar as GridContainer).columns))
	if _hud_mobile._weapon_slots.size() != 5:
		fail("手机武器栏槽位数 != 5: " + str(_hud_mobile._weapon_slots.size()))
	var rows_y: Array = []
	for s in _hud_mobile._weapon_slots:
		var r := _rect(s)
		if r.size.x < 43.0 or r.size.y < 43.0:
			fail("手机武器栏槽位 <44px: " + str(r))
		var key := roundi(r.position.y)
		if not rows_y.has(key):
			rows_y.append(key)
	if rows_y.size() != 2:
		fail("手机武器栏应为 3+2 两行，实际行数: %d" % rows_y.size())
	if not _rect(_hud_mobile._weapon_bar).intersects(_rect(_hud_mobile._res_box)) == false:
		fail("手机武器栏与资源区重叠")

func _find_button(node: Node, bname: String) -> Button:
	if node is Button and node.name == bname:
		return node as Button
	for ch in node.get_children():
		var r := _find_button(ch, bname)
		if r != null:
			return r
	return null

func _assert_shop() -> void:
	# 顶栏：材料图标存在、标题含波次
	if _shop._mat_icon == null or _shop._mat_icon.texture == null:
		fail("商店顶栏缺少材料图标")
	_shop._goto_buy()
	# 2 列卡片网格（等一帧布局）
	if _shop._box == null or _shop._box.columns != 2:
		fail("商店商品卡列数 != 2: " + str(_shop._box.columns if _shop._box else "null"))
	var cards: Array = []
	for c in _shop._box.get_children():
		if c is PanelContainer and not c.is_queued_for_deletion():
			cards.append(c)
	if cards.size() != 3:
		fail("商店商品卡数量 != 3: " + str(cards.size()))
	var locks := 0
	for c in cards:
		for ch in c.get_children():
			if ch is Button and ch.name == "LockBtn":
				locks += 1
	if locks != 3:
		fail("商品卡锁钮数量 != 3: " + str(locks))
	# 锁定后刷新保留
	_shop._toggle_lock(0)
	var locked_id: String = str(_shop._offers[0].get("id", ""))
	var locked_before: int = _shop._offers.size()
	var gs: Node = root.get_node_or_null("GameState")
	if gs != null:
		gs.run.gold = 5000  # 确保刷新费可负担（新局金币为 0）
	_shop._refresh_offers()
	if _shop._offers.size() != locked_before:
		fail("刷新后货架数量异常")
	if not _locked_has(_shop, locked_id):
		fail("锁定商品未在刷新后保留: " + locked_id)
	# "开始下一波"金色大按钮存在
	var next := _find_button(_shop, "NextWaveBtn")
	if next == null:
		fail("缺少'开始下一波'按钮")
	_shop._close_shop()

func _locked_has(shop: CanvasLayer, id: String) -> bool:
	for i in shop._offers.size():
		if str(shop._offers[i].get("id", "")) == id and shop._locked.size() > i and shop._locked[i]:
			return true
	return false

func _assert_wave_banner() -> void:
	# 波次横幅：显示 + 倒计时 + 计时条；Boss 在场自动隐藏（经验条不隐藏）
	_hud._on_wave("第 2 波来袭！")
	if not _hud._wave_root.visible:
		fail("波次横幅未显示")
	if _hud._wave_bar == null or _hud._wave_time_label == null:
		fail("波次横幅缺少倒计时/计时条")
	if not str(_hud._wave_time_label.text).contains(":"):
		fail("波次倒计时格式异常: " + _hud._wave_time_label.text)
	var bus: Node = root.get_node_or_null("EventBus")
	if bus != null:
		bus.boss_spawned.emit("古神", 999)
	if _hud._wave_root.visible:
		fail("Boss 在场波次横幅未隐藏")
	if not _hud._xp_bar.visible:
		fail("Boss 出现后经验条被隐藏（验收项）")
	if not _hud._boss_root.visible:
		fail("Boss 血条未显示")
	# 普通播报（clear/Boss）也隐藏横幅
	_hud._on_wave("clear")
	if _hud._wave_root.visible:
		fail("clear 后波次横幅未隐藏")
