extends SceneTree
## 落雷误触发修复回归测试（docs/design/落雷误触发修复落地报告.md）
## 断言：
## ① 无雷系 holdings 时高 DPS 档位不发 lightning 特效（fx_manager P0-1 门控），
##    持有雷系后同档位恢复 lightning（正向对照）；
## ② 法术部件三选一（_make_spell_choice）：无雷系/仅火系 holdings 时不出 lightning
##    核心，持有雷系后出现（P1-5 元素过滤）；
## ③ Boss 转阶段视觉 kind 非 lightning（P0-2 金色转阶段）；
## ④ 强化法杖后等级/伤害数值变化、金色横幅展示，且商店随后自动关闭（wand_shop 强化展示+关店）。
## Run: godot --headless --path . -s res://scripts/tests/test_no_lightning_leak.gd

var failures: Array[String] = []
var _frame := 0
var _phase := 0
var _emitted: Array[String] = []  # EventBus.fx_explosion 记录的 kind
var _gs: Node
var _shop: Node
var _close_deadline := 0
var _dps_before := 0.0

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	match _phase:
		0:
			(root.get_node("EventBus") as Node).fx_explosion.connect(_on_fx_kind)
			_test_high_dps_gate()
			_phase = 1
		1:
			_test_spell_choice_filter()
			_phase = 2
		2:
			_test_boss_phase_visual()
			_phase = 3
		3:
			_test_wand_upgrade()
			_close_deadline = Time.get_ticks_msec() + 4000
			_phase = 4
		4:
			if _shop != null and not _shop._shop_open:
				_shop.free()
				_shop = null
				_phase = 5
			elif Time.get_ticks_msec() > _close_deadline:
				fail("强化完成后商店未在 4s 内自动关闭")
				_shop.free()
				_shop = null
				_phase = 5
		5:
			if failures.is_empty():
				print("NO LIGHTNING LEAK ALL PASS")
			else:
				for f in failures:
					push_error("NO LIGHTNING LEAK FAIL: " + f)
			quit(0 if failures.is_empty() else 1)
			return true
	return false

func fail(msg: String) -> void:
	failures.append(msg)
	print("[FAIL] " + msg)

func _on_fx_kind(_pos: Vector2, kind: String) -> void:
	_emitted.append(kind)

func _test_high_dps_gate() -> void:
	## ① 高 DPS 档位随机落雷门控：无雷系 holdings → 只发 gold；持有雷系 → 恢复 lightning
	_gs = root.get_node_or_null("GameState")
	if _gs == null:
		fail("GameState autoload missing")
		return
	_gs.new_run()
	_gs.run.items = {}  # 显式清空构筑：开局随机技能可能与雷系耦合，测试需确定性无雷
	_gs.run.grid = []
	## 运行时 load（非 preload）：-s 启动期 autoload 全局未注册时 preload 会编译失败，
	## 延迟到 _process 首帧再编译可避免启动期脚本重载竞态
	var fx_script: GDScript = load("res://scripts/fx/fx_manager.gd")
	if fx_script == null:
		fail("fx_manager.gd 加载失败")
		return
	var fx: Node = fx_script.new()
	fx.name = "FxLeakTest"
	root.add_child(fx)
	fx.set_process(false)  # 手动驱动，避免引擎帧干扰
	fx._process(2.6)  # 刷新档位计时（dps≈0 → tier 0）
	fx._dps_tier = 3  # 强制最高爽感档位
	fx._firework_timer = 0.0
	_emitted.clear()
	fx._process(0.05)
	if "lightning" in _emitted:
		fail("无雷系构筑时高 DPS 档位仍发出 lightning 特效: %s" % str(_emitted))
	if "gold" not in _emitted:
		fail("高 DPS 档位应发出 gold 特效: %s" % str(_emitted))
	# 正向对照：持有雷系物品后同档位应恢复 lightning
	_gs.run.items = {"thunder_1": 1}
	if int(_gs.school_holdings().get("lightning", 0)) <= 0:
		fail("thunder_1 应计入 lightning holdings")
	fx._firework_timer = 0.0
	_emitted.clear()
	fx._process(0.05)
	if "lightning" not in _emitted:
		fail("持有雷系构筑后高 DPS 档位应恢复 lightning 特效: %s" % str(_emitted))
	fx.free()

func _test_spell_choice_filter() -> void:
	## ② 法术部件三选一元素过滤：未持有元素的核心不进生成池
	_gs.new_run()
	_gs.run.items = {}
	_gs.run.grid = []  # 空构筑：仅通用 blade 核心可出
	var saw: Dictionary = {}
	for i in 60:
		var ch: Dictionary = _gs._make_spell_choice()
		if ch.is_empty():
			fail("空构筑下 _make_spell_choice 不应返回空（blade 通用核心保底）")
			continue
		var parts := str(ch.get("id", "")).split(":")
		if parts.size() < 2:
			fail("法术部件 id 格式异常: %s" % str(ch.get("id", "")))
			continue
		var el: String = _gs.spell_core_element(parts[1])
		saw[el] = true
		if el == "lightning":
			fail("无雷系 holdings 时三选一出 lightning 核心: %s" % str(ch.get("id", "")))
	if not saw.has("blade"):
		fail("空构筑下应保底 blade 核心，实际: %s" % str(saw))
	# 仅火系构筑：不得出 lightning
	_gs.run.grid = [{"core": "fireball", "shell": ""}]
	_gs.run.items = {}
	saw.clear()
	for i in 60:
		var ch: Dictionary = _gs._make_spell_choice()
		if ch.is_empty():
			continue
		var parts := str(ch.get("id", "")).split(":")
		if parts.size() < 2:
			continue
		var el: String = _gs.spell_core_element(parts[1])
		saw[el] = true
		if el == "lightning":
			fail("仅火系构筑时三选一出 lightning 核心: %s" % str(ch.get("id", "")))
	if not saw.has("fire"):
		fail("火系构筑应能出 fire 核心，实际: %s" % str(saw))
	# 正向对照：持有雷系核心后应能出 lightning
	_gs.run.grid = [{"core": "lightning", "shell": ""}]
	var saw_l := false
	for i in 60:
		var ch: Dictionary = _gs._make_spell_choice()
		if ch.is_empty():
			continue
		var parts := str(ch.get("id", "")).split(":")
		if parts.size() < 2:
			continue
		if _gs.spell_core_element(parts[1]) == "lightning":
			saw_l = true
			break
	if not saw_l:
		fail("持有雷系核心后三选一应能出 lightning 核心")

func _test_boss_phase_visual() -> void:
	## ③ Boss 转阶段视觉非 lightning kind（金色敌技视觉 + void 清屏伤害）
	var host := Node.new()
	host.name = "LeakHost"
	root.add_child(host)
	current_scene = host  # _spawn_minions 需要 current_scene
	var player := CharacterBody2D.new()
	player.name = "LeakPlayer"
	player.add_to_group("player")
	player.position = Vector2(320, 300)
	host.add_child(player)
	var boss: Node = (load("res://scenes/game/boss.tscn") as PackedScene).instantiate()
	boss.setup_boss("skeleton_king", 1, 1)
	host.add_child(boss)  # 先 setup（conf/贴图就绪）再入树，避免 _ready 空配置加载
	boss._player = player  # 直接驱动转阶段（跳过物理帧解析玩家）
	_emitted.clear()
	boss._on_phase_up()
	if "lightning" in _emitted:
		fail("Boss 转阶段仍发出 lightning 视觉: %s" % str(_emitted))
	if "gold" not in _emitted:
		fail("Boss 转阶段应发出金色敌技视觉: %s" % str(_emitted))
	boss.queue_free()
	player.queue_free()
	host.queue_free()

func _test_wand_upgrade() -> void:
	## ④ 强化法杖：等级/数值变化 + 金色横幅 + 商店自动关闭
	_gs.new_run()
	_gs.run.gold = 2000
	var before: float = float(_gs.estimate_dps())
	_shop = (load("res://scenes/ui/wand_shop.tscn") as PackedScene).instantiate()
	_shop.name = "LeakShop"
	root.add_child(_shop)
	_shop.show_shop()
	_shop._goto_enhance()
	var cost: int = _gs.wand_upgrade_cost("basic_wand")
	_shop._upgrade_wand(0)
	var lv: int = _gs.wand_upgrade_level("basic_wand")
	if lv != 1:
		fail("强化后 wand 等级 != 1: %d" % lv)
	if _gs.run.gold != 2000 - cost:
		fail("强化后金币未正确扣款: gold=%d 期望 %d" % [_gs.run.gold, 2000 - cost])
	var mult: float = 1.0 + float(_gs.WAND_UPGRADE_BONUS) * float(lv)
	if absf(mult - 1.08) > 1e-6:
		fail("强化后伤害倍率异常: %.3f" % mult)
	var after: float = float(_gs.estimate_dps())
	if after <= before:
		fail("强化后 DPS 数值应提升: before=%.2f after=%.2f" % [before, after])
	if _shop._enhance_banner == null:
		fail("强化页缺少成功横幅节点")
	elif not _shop._enhance_banner.visible:
		fail("强化成功后未显示金色成功横幅")
	elif not str(_shop._enhance_banner.text).contains("强化成功"):
		fail("横幅文本异常: %s" % str(_shop._enhance_banner.text))
	# 卡片文本更新：强化按钮显示 Lv.1 与下一级费用；等级/伤害行显示 Lv.1
	var up_btn := _find_button_text(_shop._owned_box, "强化 Lv.1")
	if up_btn == null:
		fail("强化后卡片按钮未更新为 Lv.1: %s" % _collect_texts(_shop._owned_box))
	if not _find_label_text(_shop._owned_box, "Lv.1"):
		fail("强化后卡片未显示等级/伤害加成行")

func _find_button_text(node: Node, prefix: String) -> Button:
	if node is Button and str((node as Button).text).begins_with(prefix):
		return node as Button
	for ch in node.get_children():
		var r := _find_button_text(ch, prefix)
		if r != null:
			return r
	return null

func _find_label_text(node: Node, needle: String) -> bool:
	if node is Label and str((node as Label).text).contains(needle):
		return true
	for ch in node.get_children():
		if _find_label_text(ch, needle):
			return true
	return false

func _collect_texts(node: Node) -> String:
	var out: Array[String] = []
	_collect_texts_into(node, out)
	return " / ".join(out)

func _collect_texts_into(node: Node, out: Array[String]) -> void:
	if node is Button or node is Label:
		var t: Variant = node.get("text")
		out.append("" if t == null else str(t))
	for ch in node.get_children():
		_collect_texts_into(ch, out)
