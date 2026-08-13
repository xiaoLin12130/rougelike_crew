extends SceneTree
## 批次A 数据层回归（2026-08-13）：
##  a) 4 个旧 id（stone_armor/thorn_reflect/blood_thorn/summon_book）已从数据表移除，
##     新 id（defense_bedrock/defense_thorn_refit/defense_blood_thorn/summon_1）存在；
##  b) roll_item_choices 不返回 disabled 道具与 type=trinket 道具（跑 300 次）；
##  c) detect_synergies 12 流派全部可检测（各流派 2 件成型写入 synergy_bonus）。
## 运行：godot --headless --path . -s res://scripts/tests/test_no_dead_items.gd

var failures: Array[String] = []
var _frame := 0
var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_frame += 1
	if _frame < 3:
		return false
	_done = true
	_run()
	if failures.is_empty():
		print("NO DEAD ITEMS TEST OK")
	else:
		for f in failures:
			push_error("NO DEAD ITEMS FAIL: " + f)
	quit(0 if failures.is_empty() else 1)
	return true


func fail(msg: String) -> void:
	failures.append(msg)


func _run() -> void:
	var gs: Node = root.get_node_or_null("GameState")
	if gs == null:
		fail("GameState autoload missing")
		return
	# a) 旧 id 移除 / 新 id 存在
	for old in ["stone_armor", "thorn_reflect", "blood_thorn", "summon_book"]:
		if not gs.item_def(old).is_empty():
			fail("旧 id 仍存在于数据表: " + old)
	for new in ["defense_bedrock", "defense_thorn_refit", "defense_blood_thorn", "summon_1"]:
		if gs.item_def(new).is_empty():
			fail("新 id 缺失: " + new)
	# b) roll 池不含 disabled / trinket
	var saved_run: Dictionary = gs.run
	gs.run = gs.run.duplicate(true)
	gs.run.items = {}
	for _i in 300:
		for ch in gs.roll_item_choices(3):
			if bool(ch.get("disabled", false)):
				fail("roll 池含 disabled 道具: " + str(ch.get("id", "")))
			if str(ch.get("type", "item")) == "trinket":
				fail("roll 池含 trinket 道具: " + str(ch.get("id", "")))
	# c) detect_synergies 12 流派（各 2 件成型）
	_test_school(gs, "fire", {"fire_ember": 2}, "fire", 0.15)
	_test_school(gs, "ice", {"ice_1": 2}, "ice", 0.20)
	_test_school(gs, "lightning", {"thunder_1": 2}, "lightning", 0.15)
	_test_school(gs, "poison", {"venom_flask": 2}, "poison", 0.25)
	_test_school(gs, "summon", {"summon_1": 2}, "summon", 0.25)
	_test_school(gs, "water", {"water_essence": 2}, "water", 0.15)
	_test_school(gs, "wind", {"wind_boots": 2}, "wind", 0.10)
	_test_school(gs, "holy", {"holy_1": 2}, "holy", 0.15)
	_test_school(gs, "curse", {"curse_ink": 2}, "curse", 0.15)
	_test_school(gs, "melee", {"melee_1": 2}, "melee", 0.20)
	_test_school(gs, "defense", {"defense_bedrock": 2}, "defense", 0.05)
	# teleport 无道具：2 个 void 核心
	_test_school_cores(gs, "teleport", 0.15)
	gs.run = saved_run


func _test_school(gs: Node, label: String, items: Dictionary, key: String, expected: float) -> void:
	gs.run["synergy_bonus"] = {}
	gs.run.items = items
	gs.detect_synergies()
	var got: float = float(gs.run.get("synergy_bonus", {}).get(key, 0.0))
	if absf(got - expected) > 0.0001:
		fail("%s 流派未成型: synergy_bonus.%s = %s（期望 %s）" % [label, key, str(got), str(expected)])


func _test_school_cores(gs: Node, label: String, expected: float) -> void:
	gs.run["synergy_bonus"] = {}
	gs.run.items = {}
	gs.run.grid = [
		{"core": "teleport", "shell": "rapid"},
		{"core": "teleport", "shell": "burst"},
	]
	gs.detect_synergies()
	var got: float = float(gs.run.get("synergy_bonus", {}).get("teleport", 0.0))
	if absf(got - expected) > 0.0001:
		fail("%s 流派未成型: synergy_bonus.teleport = %s（期望 %s）" % [label, str(got), str(expected)])
