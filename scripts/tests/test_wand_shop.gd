extends SceneTree
## 法杖商店加权抽取单测：模拟 1000 次 _roll_offers（每次 3 把）
## 验证：
##  a) lucky=0 时 白 > 绿 > 蓝 > 金 > 红 出现概率递减
##  b) lucky=10（crit_lucky tag=lucky）时红概率明显高于 lucky=0
## 运行：godot --headless --path . -s res://scripts/tests/test_wand_shop.gd

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
		print("WAND SHOP TEST OK")
	else:
		for f in failures:
			push_error("WAND SHOP FAIL: " + f)
	quit(0 if failures.is_empty() else 1)
	return true

func fail(msg: String) -> void:
	failures.append(msg)

func _simulate(shop: CanvasLayer, trials: int) -> Dictionary:
	var counts := {"common": 0, "uncommon": 0, "rare": 0, "epic": 0, "legendary": 0}
	for i in trials:
		shop._roll_offers()
		for w in shop._offers:
			var r: String = str(w.get("rarity", "common"))
			counts[r] = int(counts[r]) + 1
	return counts


const RARITY_ORDER: Array = ["common", "uncommon", "rare", "epic", "legendary"]

func _run() -> void:
	seed(20260813)  # 固定种子：抽取模拟可复现（新池 54 把，排除 basic_wand）
	var gs: Node = root.get_node_or_null("GameState")
	if gs == null:
		fail("GameState autoload missing")
		return
	var wands: Array = gs.tables.get("wands", {}).get("wands", [])
	if wands.size() != 55:
		fail("wands table size %d != 55" % wands.size())
	var shop_script: GDScript = load("res://scripts/ui/game/wand_shop.gd")
	var shop: CanvasLayer = shop_script.new()
	var saved_items: Dictionary = gs.run.items
	var saved_wands: Array = gs.run.wands
	gs.run.wands = ["basic_wand"]  # 商店池排除已装备（与正式逻辑一致）
	# lucky=0
	gs.run.items = {}
	var c0: Dictionary = _simulate(shop, 3000)
	# lucky=10：crit_lucky（tag=lucky）10 层
	gs.run.items = {"crit_lucky": 10}
	var c10: Dictionary = _simulate(shop, 3000)
	gs.run.items = saved_items
	gs.run.wands = saved_wands
	shop.free()

	var s0 := _shares(c0)
	var s10 := _shares(c10)
	var order_line0 := ""
	var order_line10 := ""
	for r in RARITY_ORDER:
		order_line0 += "%s %.1f%% " % [r, s0[r] * 100.0]
		order_line10 += "%s %.1f%% " % [r, s10[r] * 100.0]
	print("lucky=0 : " + order_line0)
	print("lucky=10: " + order_line10)
	for r in RARITY_ORDER:
		if s0[r] <= 0.0:
			fail("lucky=0 %s 占比为 0（池缺失该档）" % r)
	for i in RARITY_ORDER.size() - 1:
		if s0[RARITY_ORDER[i]] <= s0[RARITY_ORDER[i + 1]]:
			fail("lucky=0 概率未递减：%s=%.3f <= %s=%.3f"
				% [RARITY_ORDER[i], s0[RARITY_ORDER[i]],
					RARITY_ORDER[i + 1], s0[RARITY_ORDER[i + 1]]])
		if s10[RARITY_ORDER[i]] <= s10[RARITY_ORDER[i + 1]]:
			fail("lucky=10 概率未递减：%s=%.3f <= %s=%.3f"
				% [RARITY_ORDER[i], s10[RARITY_ORDER[i]],
					RARITY_ORDER[i + 1], s10[RARITY_ORDER[i + 1]]])
	if s10["legendary"] <= s0["legendary"] + 0.04:
		fail("lucky=10 红占比 %.3f 未明显高于 lucky=0 的 %.3f（需 +4pp 以上）"
			% [s10["legendary"], s0["legendary"]])
	## 商店修复2（2026-08-13）：越稀有越难出 —— lucky=0 时传说占比显著低于普通
	if s0["legendary"] > 0.15:
		fail("lucky=0 红占比 %.3f 过高（应 <15%%，越稀有越难出）" % s0["legendary"])
	if s0["common"] < 0.30:
		fail("lucky=0 白占比 %.3f 过低（应 >30%%）" % s0["common"])
	var sample_total := 0
	for r in RARITY_ORDER:
		sample_total += int(c0[r])
	if sample_total != 9000:
		fail("lucky=0 样本数异常：%s" % str(c0))
	sample_total = 0
	for r in RARITY_ORDER:
		sample_total += int(c10[r])
	if sample_total != 9000:
		fail("lucky=10 样本数异常：%s" % str(c10))

func _shares(counts: Dictionary) -> Dictionary:
	var total := 0
	for r in RARITY_ORDER:
		total += int(counts[r])
	var out := {}
	for r in RARITY_ORDER:
		out[r] = float(counts[r]) / float(total)
	return out
