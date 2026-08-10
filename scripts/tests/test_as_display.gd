extends SceneTree
## 攻速效果展示测试（F 批，2026-08-10）：
## 模拟总攻速 0% / 50% / 100%，断言：
##  - 换算公式：attack_speed_pct / attack_speed_cd_reduction_pct（0→0%、50→33%、100→50%，
##    cd_mult = 1/(1+as)，与 spell_caster._cooldown_of / melee_attack._interval 同公式）；
##  - 流派贡献读取点（melee_m3_as_bonus 等）计入总攻速（显示值与运行时一致）；
##  - build_panel 统计区追加换算行（"攻速 +50%：施法更快，冷却缩短 33%"）；
##  - levelup_overlay 攻速类道具描述自动追加"（当前攻速 50%，冷却 -33%）"，非攻速道具不追加；
##  - hud DPS 行旁小字显示"攻速+50%"，攻速 0 时留空。
## Run: godot --headless --path . -s res://scripts/tests/test_as_display.gd

var failures: Array[String] = []
var _frame := 0

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false
	_run_all()
	if failures.is_empty():
		print("ALL PASS")
	else:
		for f in failures:
			push_error("AS DISPLAY FAIL: " + f)
	quit(0 if failures.is_empty() else 1)
	return true

func fail(msg: String) -> void:
	failures.append(msg)
	print("[AS] FAIL: " + msg)

func _gs() -> Node:
	return root.get_node_or_null("GameState")

func _set_as(bonus: float) -> void:
	## 模拟 apply_item_effects_to_stats 写入的攻速聚合（含清流派键，保证确定值）
	var gs := _gs()
	gs.run["attack_speed_bonus"] = bonus
	for key in gs.AS_SYNERGY_KEYS:
		gs.run.erase(key)

func _has_text(node: Node, needle: String) -> bool:
	if node is Label and str((node as Label).text).contains(needle):
		return true
	for ch in node.get_children():
		if _has_text(ch, needle):
			return true
	return false

func _run_all() -> void:
	var gs := _gs()
	if gs == null:
		fail("GameState autoload missing")
		return
	gs.new_run()
	# ---- ① 换算公式：0% / 50% / 100% ----
	_set_as(0.0)
	if gs.attack_speed_pct() != 0:
		fail("0% 攻速 pct != 0: %d" % gs.attack_speed_pct())
	if gs.attack_speed_cd_reduction_pct() != 0:
		fail("0% 攻速冷却缩减 != 0: %d" % gs.attack_speed_cd_reduction_pct())
	_set_as(0.5)
	if gs.attack_speed_pct() != 50:
		fail("50% 攻速 pct != 50: %d" % gs.attack_speed_pct())
	if gs.attack_speed_cd_reduction_pct() != 33:
		fail("50% 攻速冷却缩减 != 33: %d" % gs.attack_speed_cd_reduction_pct())
	if gs.attack_speed_cd_reduction_pct(0.5) != 33:
		fail("预览换算(0.5) != 33: %d" % gs.attack_speed_cd_reduction_pct(0.5))
	_set_as(1.0)
	if gs.attack_speed_pct() != 100:
		fail("100% 攻速 pct != 100: %d" % gs.attack_speed_pct())
	if gs.attack_speed_cd_reduction_pct() != 50:
		fail("100% 攻速冷却缩减 != 50: %d" % gs.attack_speed_cd_reduction_pct())
	# 流派贡献读取点：0.3 基础 + 0.2 近M3 = 0.5（与 spell_caster._total_attack_speed 同口径）
	gs.run["attack_speed_bonus"] = 0.3
	gs.run["melee_m3_as_bonus"] = 0.2
	if gs.attack_speed_pct() != 50:
		fail("流派贡献键未计入总攻速: %d" % gs.attack_speed_pct())
	# 未聚合回退：无 attack_speed_bonus 时用道具聚合（新局 1 瓶攻速药水 = +15%）
	gs.run.erase("attack_speed_bonus")
	for key in gs.AS_SYNERGY_KEYS:
		gs.run.erase(key)
	if gs.attack_speed_pct() != 15:
		fail("未聚合回退攻速 != 15%%: %d" % gs.attack_speed_pct())
	# ---- ② build_panel 统计区 ----
	_set_as(0.5)
	var bp: CanvasLayer = load("res://scenes/ui/build_panel.tscn").instantiate()
	bp.name = "BuildPanel"
	root.add_child(bp)
	bp.refresh()
	if not str(bp._stats_label.text).contains("攻速 +50%：施法更快，冷却缩短 33%"):
		fail("build_panel 缺攻速换算行: %s" % str(bp._stats_label.text))
	# ---- ③ levelup_overlay 攻速卡片描述 ----
	var lv: CanvasLayer = load("res://scenes/ui/levelup_overlay.tscn").instantiate()
	lv.name = "LevelUpOverlay"
	root.add_child(lv)
	lv.show_choices([
		{"id": "attack_speed_potion", "name": "攻速药水", "rarity": "common",
			"description": "攻击速度 +15%（每层）", "icon": "", "tags": ["attack_speed"]},
		{"id": "strength_badge", "name": "力量徽章", "rarity": "rare",
			"description": "攻击 +10%（每层）", "icon": "", "tags": ["atk"]},
	])
	var as_cards := 0
	for card in lv._box.get_children():
		if _has_text(card, "当前攻速"):
			as_cards += 1
			if not _has_text(card, "（当前攻速 50%，冷却 -33%）"):
				fail("攻速卡片换算文案错误")
	if as_cards != 1:
		fail("攻速卡片数量 != 1（应仅 attack_speed 道具追加）: %d" % as_cards)
	# ---- ④ hud DPS 行旁小字 ----
	var hud: CanvasLayer = load("res://scenes/ui/hud.tscn").instantiate()
	hud.name = "HUD"
	root.add_child(hud)
	if str(hud._as_label.text) != "攻速+50%":
		fail("hud 攻速小字 != 攻速+50%%: %s" % str(hud._as_label.text))
	_set_as(0.0)
	hud._refresh()
	if str(hud._as_label.text) != "":
		fail("hud 攻速 0 时应留空: %s" % str(hud._as_label.text))
