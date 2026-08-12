extends SceneTree
## 同流派升级权重平衡测试（2026-08-12）：
##  a) 公式验证：5 件同流派（lv=1）时 _element_weight 加成系数应为
##     1+0.0333*5=1.1665（旧公式为 1.5，降幅 ~22%），上限 1.5 不触发
##  b) 真实抽卡模拟：持有 5 件 fire 时跑 1000 次 roll_item_choices，
##     统计 fire 选项占比，应明显低于旧公式下的理论值（~40%）且高于无加成基线
## 运行：godot --headless --path . -s res://scripts/tests/test_school_weight.gd

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
		print("SCHOOL WEIGHT TEST OK")
	else:
		for f in failures:
			push_error("SCHOOL WEIGHT FAIL: " + f)
	quit(0 if failures.is_empty() else 1)
	return true

func fail(msg: String) -> void:
	failures.append(msg)

func _run() -> void:
	var gs: Node = root.get_node_or_null("GameState")
	if gs == null:
		fail("GameState autoload missing")
		return
	var base_weights: Dictionary = gs.tables.get("drops", {}).get("item_rarity_weights", {})
	# a) 公式验证：fire 5 件、lv=1（lv_factor=1.0）
	var holdings := {"fire": 5}
	var sample := {"id": "fire_ember", "rarity": "common", "tags": ["fire"]}
	var w_new: float = gs._element_weight(sample, base_weights, holdings, 1.0)
	var w_base: float = float(base_weights.get("common", 0.2))
	var mult: float = w_new / w_base
	if absf(mult - (1.0 + 0.0333 * 5.0)) > 0.001:
		fail("新公式加成系数 %.4f != 期望 1.1665" % mult)
	if not (mult < 1.5 * 0.85):
		fail("新公式加成 %.3f 未比旧公式 1.5 下降 >=15%%" % mult)
	# 上限验证：30 件时不应超过 1.5
	var holdings30 := {"fire": 30}
	var w30: float = gs._element_weight(sample, base_weights, holdings30, 1.0)
	if w30 / w_base > 1.5001:
		fail("30 件加成 %.3f 超过上限 1.5" % (w30 / w_base))
	# b) 真实抽卡：5 件 fire，1000 次三选一
	var saved_run: Dictionary = gs.run
	gs.run = gs.run.duplicate(true)
	gs.run.items = {"fire_ember": 5}
	var total := 0
	var fire := 0
	for _i in 1000:
		var choices: Array = gs.roll_item_choices(3)
		for c in choices:
			total += 1
			if gs.schools_of_item(c).has("fire"):
				fire += 1
	gs.run = saved_run
	var share: float = float(fire) / float(maxi(total, 1))
	print("real roll fire share (5 fire items): %.2f%% (%d/%d)" % [share * 100.0, fire, total])
	if share > 0.42:
		fail("新公式下 fire 占比 %.3f 过高（旧公式理论 ~0.40 已含保底）" % share)
	if share < 0.28:
		fail("新公式下 fire 占比 %.3f 过低（主流派保底应保证 >=1/3 左右）" % share)
