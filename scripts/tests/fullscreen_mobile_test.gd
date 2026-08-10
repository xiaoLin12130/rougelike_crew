extends SceneTree
## N3 手机全屏适配验收测试（headless）：
##  a) project 设置：stretch aspect=expand + scale_mode=fractional；
##  b) 模拟 390x844 手机视口（root.size → 逻辑视口 ≈360x779）：
##     - 相机 zoom = 基准视口高(640)/实际视口高 × 基础 zoom(0.72)，
##       世界可视高 = 视口高/zoom ≥ 640/0.72 ≈ 889px（ARENA 全高可见）；
##     - level 背景底板（Backdrop）存在、铺满可视矩形、垫在世界层之下；
##  c) 关键 UI（HUD 资源条/Boss 条/波次/获得提示/按钮 + 全部面板）在 expand
##    视口下均在屏内、锚点正确（底部贴底、顶部贴顶、面板居中）。
## Run: godot --headless --path . -s res://scripts/tests/fullscreen_mobile_test.gd

var failures: Array[String] = []
var _frame := 0
var _phase := 0
var _vp := Vector2.ZERO
var _camera: Camera2D
var _level: Node2D
var _hud: CanvasLayer
var _panels: Array = []

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false
	match _phase:
		0:
			_assert_project_settings()
			_phase = 1
		1:
			root.size = Vector2i(390, 844)  # 模拟手机：390x844 → 逻辑视口 360x779
			_phase = 2
		2:
			_vp = root.get_visible_rect().size
			print("[VP] root.size=", root.size, " visible_rect=", root.get_visible_rect())
			_build_camera()
			_build_level()
			_build_ui()
			_phase = 3
		3:
			_assert_camera()
			_assert_backdrop()
			_assert_joystick()
			_assert_ui()
			_finish()
			return true
	return false

func _finish() -> void:
	if failures.is_empty():
		print("FULLSCREEN MOBILE OK")
	else:
		for f in failures:
			push_error("MOBILE FAIL: " + f)
	quit(0 if failures.is_empty() else 1)

func fail(msg: String) -> void:
	failures.append(msg)

func approx(a: float, b: float, eps: float = 0.01) -> bool:
	return absf(a - b) <= eps

func _assert_project_settings() -> void:
	var aspect: String = ProjectSettings.get_setting("display/window/stretch/aspect", "")
	var scale_mode: String = ProjectSettings.get_setting("display/window/stretch/scale_mode", "")
	var mode: String = ProjectSettings.get_setting("display/window/stretch/mode", "")
	print("[SETTINGS] mode=", mode, " aspect=", aspect, " scale_mode=", scale_mode)
	if aspect != "expand":
		fail("stretch aspect 应为 expand，实际 " + aspect)
	if scale_mode != "fractional":
		fail("stretch scale_mode 应为 fractional，实际 " + scale_mode)
	if mode != "canvas_items":
		fail("stretch mode 应为 canvas_items，实际 " + mode)

func _build_camera() -> void:
	_camera = load("res://scripts/fx/camera_shake.gd").new()
	_camera.name = "TestCamera"
	root.add_child(_camera)  # _ready：按当前视口（360x779）计算 zoom

func _build_level() -> void:
	_level = load("res://scripts/enemies/level.gd").new()
	_level.name = "TestLevel"
	root.add_child(_level)
	_level._build_scene_background("grass")

func _build_ui() -> void:
	_setup_run()
	_hud = load("res://scenes/ui/hud.tscn").instantiate()
	_hud.name = "HUD"
	root.add_child(_hud)
	_build_panels()
	root.get_node("EventBus").boss_spawned.emit("暗影魔像", 500)
	_hud._on_wave("波次 3 来袭")

func _setup_run() -> void:
	var gs: Node = root.get_node("GameState")
	gs.new_run()
	gs.run.items = {"attack_speed_potion": 2, "strength_badge": 3, "lucky_clover": 1}
	gs.run.grid = [
		{"core": "fireball", "shell": ""},
		{"core": "whirl_blade", "shell": "rapid"},
	]

func _build_panels() -> void:
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
	_panels[0].refresh()
	_panels[1].show_choices([
		{"id": "attack_speed_potion", "name": "迅捷药水", "rarity": "common", "description": "攻击速度 +12%（每层）", "icon": ""},
		{"id": "strength_badge", "name": "力量徽章", "rarity": "rare", "description": "攻击 +10%（每层）", "icon": ""},
		{"id": "lucky_clover", "name": "幸运草", "rarity": "legendary", "description": "暴击率 +2%（每层）", "icon": ""},
	])
	_panels[2].show_shop()
	_panels[3].show_replace("fireball", "rapid", root.get_node("GameState").run.grid)
	var menu: Control = load("res://scenes/main_menu.tscn").instantiate()
	menu.name = "MainMenu"
	root.add_child(menu)
	_panels.append(menu)

func _assert_camera() -> void:
	var vp_h: float = _vp.y
	var expect_zoom: float = 0.72 * 640.0 / vp_h
	print("[CAMERA] vp=", _vp, " zoom=", _camera.zoom, " expect_zoom=", expect_zoom)
	if not approx(_camera.zoom.x, expect_zoom) or not approx(_camera.zoom.y, expect_zoom):
		fail("相机 zoom 未按 640/视口高×0.72 计算: %s (期望 %.4f)" % [_camera.zoom, expect_zoom])
	var visible_h: float = vp_h / _camera.zoom.y
	if visible_h < 640.0 / 0.72 - 0.1:
		fail("世界可视高不足(需≥640/0.72≈889): %.1f" % visible_h)
	if _camera.limit_left != 0 or _camera.limit_top != 0 or _camera.limit_right != 1280 or _camera.limit_bottom != 720:
		fail("相机 limit 应保持地图边界 0..1280x720: %d,%d,%d,%d" % [_camera.limit_left, _camera.limit_top, _camera.limit_right, _camera.limit_bottom])
	# 测试钩子：其它视口比例下公式仍成立（基准 360x640 → zoom=0.72；超高 360x900 → 更小 zoom）
	_camera._viewport_size_override = Vector2(360, 640)
	_camera._apply_orientation_zoom()
	if not approx(_camera.zoom.x, 0.72):
		fail("基准视口 360x640 下 zoom 应为 0.72: " + str(_camera.zoom))
	_camera._viewport_size_override = Vector2(360, 900)
	_camera._apply_orientation_zoom()
	if not approx(_camera.zoom.y, 0.72 * 640.0 / 900.0):
		fail("测试钩子 360x900 下 zoom 未按公式: " + str(_camera.zoom))
	_camera._viewport_size_override = Vector2.ZERO
	_camera._apply_orientation_zoom()

func _assert_backdrop() -> void:
	var cl: CanvasLayer = _level.get_node_or_null("BackdropLayer") as CanvasLayer
	if cl == null:
		fail("缺少 BackdropLayer")
		return
	if cl.layer >= 0:
		fail("BackdropLayer.layer 应 <0（垫在世界层之下）: " + str(cl.layer))
	var rect: ColorRect = cl.get_node_or_null("Backdrop") as ColorRect
	if rect == null:
		fail("BackdropLayer 下缺少 Backdrop")
		return
	var r: Rect2 = rect.get_global_rect()
	var screen := Rect2(Vector2.ZERO, _vp)
	print("[BACKDROP] layer=", cl.layer, " rect=", r, " screen=", screen)
	if not screen.encloses(r) or r.size.x < screen.size.x - 1.0 or r.size.y < screen.size.y - 1.0:
		fail("背景底板未铺满可视矩形: " + str(r))
	var bg := _level.get_node_or_null("SceneBackground") as Sprite2D
	if bg == null:
		fail("缺少 SceneBackground")
	elif bg.z_index != -5:
		fail("SceneBackground.z_index 应为 -5: " + str(bg.z_index))

func _assert_ui() -> void:
	print("[UI] vp=", _vp)
	var screen := Rect2(Vector2.ZERO, _vp)
	# HUD 锚点断言：顶栏贴顶、底按钮贴底、中部提示相对居中锚点偏移正确
	var res: Rect2 = _hud._res_box.get_global_rect()
	if not screen.encloses(res):
		fail("资源条越界: " + str(res))
	if not approx(res.position.x, 8.0) or not approx(res.position.y, 24.0):
		fail("资源条应锚 TOP_LEFT 于 (8,24): " + str(res))
	var boss: Rect2 = _hud._boss_root.get_global_rect()
	if not screen.encloses(boss):
		fail("Boss 条越界: " + str(boss))
	if not approx(boss.position.x, _vp.x / 2.0 - 126.0) or boss.position.y < 3.0 or boss.end.y > 21.0:
		fail("Boss 条应锚 CENTER_TOP（y 4..20，顶部居中）: " + str(boss))
	var wave: Rect2 = _hud._wave_label.get_global_rect()
	if not screen.encloses(wave):
		fail("波次提示越界: " + str(wave))
	if not approx(wave.position.x, _vp.x - 100.0):
		fail("波次提示应锚 TOP_RIGHT（x=视口宽-100）: " + str(wave))
	var pick: Rect2 = _hud._pickup_label.get_global_rect()
	if not screen.encloses(pick):
		fail("获得提示越界: " + str(pick))
	if not approx(pick.position.y, _vp.y - 140.0):
		fail("获得提示应锚 CENTER_BOTTOM（y=视口高-140）: " + str(pick))
	var bbtn: Rect2 = _hud._build_btn.get_global_rect()
	var pbtn: Rect2 = _hud._pause_btn.get_global_rect()
	if not screen.encloses(bbtn) or not screen.encloses(pbtn):
		fail("底部按钮越界: build=" + str(bbtn) + " pause=" + str(pbtn))
	if not approx(pbtn.end.y, _vp.y - 24.0):
		fail("暂停按钮应贴底（end.y=视口高-安全区24）: " + str(pbtn))
	if not approx(bbtn.position.x, 6.0):
		fail("构筑按钮应锚 BOTTOM_LEFT（x=6）: " + str(bbtn))
	# 面板：全部在屏内且水平居中
	for ui in _panels:
		var tag: String = ui.name
		if tag != "MainMenu":
			_best_panel = null
			_best_area = 0.0
			_collect_panels(ui)
		if _best_panel == null:
			fail(tag + " 未找到面板节点")
			continue
		var r2: Rect2 = _best_panel.get_global_rect()
		if not screen.encloses(r2):
			fail("%s 面板越出 expand 视口: %s" % [tag, str(r2)])
		var cx: float = r2.position.x + r2.size.x / 2.0
		if absf(cx - _vp.x / 2.0) > 2.0:
			fail("%s 面板未水平居中: %s (视口宽 %.0f)" % [tag, str(r2), _vp.x])

func _assert_joystick() -> void:
	## 只读确认：摇杆左右半屏按实时视口计算（get_visible_rect），闪避按钮锚 BOTTOM_RIGHT
	var j: CanvasLayer = load("res://scripts/ui/game/virtual_joystick.gd").new()
	j.force_enable = true
	root.add_child(j)
	var db: Button = j.dash_button
	var all_bottom_right: bool = (
		db.anchor_left == 1.0 and db.anchor_top == 1.0
		and db.anchor_right == 1.0 and db.anchor_bottom == 1.0)
	if not all_bottom_right:
		fail("闪避按钮应锚 BOTTOM_RIGHT")
	var r: Rect2 = db.get_global_rect()
	var screen := Rect2(Vector2.ZERO, _vp)
	if not screen.encloses(r):
		fail("闪避按钮越界: " + str(r))
	if not approx(r.end.x, _vp.x - 14.0) or not approx(r.end.y, _vp.y - 14.0):
		fail("闪避按钮应贴右下（边距 14）: " + str(r))
	print("[JOYSTICK] dash_rect=", r, " anchors=", db.anchor_left, ",", db.anchor_top)

var _best_panel: Control
var _best_area := 0.0

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
