extends SceneTree
## 法杖商店加权抽取单测：模拟 1000 次 _roll_offers（每次 3 把）
## 验证：
##  a) lucky=0 时 普通 > 稀有 > 传说 出现概率递减
##  b) lucky=10（crit_lucky tag=lucky）时传说概率明显高于 lucky=0
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
	var counts := {"common": 0, "rare": 0, "legendary": 0}
	for i in trials:
		shop._roll_offers()
		for w in shop._offers:
			var r: String = str(w.get("rarity", "common"))
			counts[r] = int(counts[r]) + 1
	return counts

func _run() -> void:
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
	var c0: Dictionary = _simulate(shop, 1000)
	# lucky=10：crit_lucky（tag=lucky）10 层
	gs.run.items = {"crit_lucky": 10}
	var c10: Dictionary = _simulate(shop, 1000)
	gs.run.items = saved_items
	gs.run.wands = saved_wands
	shop.free()

	var s0 := _shares(c0)
	var s10 := _shares(c10)
	print("lucky=0 : common %.1f%% rare %.1f%% legendary %.1f%%"
		% [s0["common"] * 100.0, s0["rare"] * 100.0, s0["legendary"] * 100.0])
	print("lucky=10: common %.1f%% rare %.1f%% legendary %.1f%%"
		% [s10["common"] * 100.0, s10["rare"] * 100.0, s10["legendary"] * 100.0])
	if s0["common"] <= s0["rare"] or s0["rare"] <= s0["legendary"]:
		fail("lucky=0 概率未递减：%.3f/%.3f/%.3f"
			% [s0["common"], s0["rare"], s0["legendary"]])
	if s10["common"] <= s10["rare"] or s10["rare"] <= s10["legendary"]:
		fail("lucky=10 概率未递减：%.3f/%.3f/%.3f"
			% [s10["common"], s10["rare"], s10["legendary"]])
	if s10["legendary"] <= s0["legendary"] + 0.05:
		fail("lucky=10 传说占比 %.3f 未明显高于 lucky=0 的 %.3f（需 +5pp 以上）"
			% [s10["legendary"], s0["legendary"]])
	if int(c0["common"]) + int(c0["rare"]) + int(c0["legendary"]) != 3000:
		fail("lucky=0 样本数异常：%s" % str(c0))
	if int(c10["common"]) + int(c10["rare"]) + int(c10["legendary"]) != 3000:
		fail("lucky=10 样本数异常：%s" % str(c10))

func _shares(counts: Dictionary) -> Dictionary:
	var total: float = float(int(counts["common"]) + int(counts["rare"]) + int(counts["legendary"]))
	return {
		"common": float(counts["common"]) / total,
		"rare": float(counts["rare"]) / total,
		"legendary": float(counts["legendary"]) / total,
	}
