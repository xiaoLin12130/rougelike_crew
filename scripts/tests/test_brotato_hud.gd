extends SceneTree
## 土豆兄弟 UI 适配专项测试（2026-08-12，docs/design/土豆兄弟UI适配方案.md §5）：
## ① 左上资源区（HP/材料/Lv徽章+XP条/关卡·DPS）布局正确；
## ② Boss 血条与经验条互斥，且 Boss 出现不隐藏经验条；
## ③ 波次横幅：顶部中右 + 倒计时 + 计时条；Boss 在场自动隐藏；
## ④ 商店：2 列商品卡网格 + 每卡锁钮 + 顶栏材料图标 + "开始下一波"金色大按钮。
## 2026-08-12：底部武器/法术栏已按用户反馈整体移除，相关断言删除。
## Run: godot --headless --path . -s res://scripts/tests/test_brotato_hud.gd

var failures: Array[String] = []
var _frame := 0
var _phase := 0
var _hud: CanvasLayer
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
			_assert_shop()
			_phase = 3
		3:
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
	var screen := Rect2(Vector2.ZERO, Vector2(360, 640))
	if not res.encloses(xp):
		fail("XP 条不在资源区内: xp=%s res=%s" % [str(xp), str(res)])
	if not screen.encloses(res):
		fail("资源区越出视口")
	# 材料图标存在（Brotato 材料位）
	if _hud._mat_icon == null or _hud._mat_icon.texture == null:
		fail("HUD 缺少材料图标")
	# Lv 徽章与 XP 条同排（同一行内）
	var badge := _rect(_hud._lv_badge)
	if absf(badge.position.y - xp.position.y) > 5.0:
		fail("Lv 徽章未与 XP 条同排: badge=%s xp=%s" % [str(badge), str(xp)])
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
