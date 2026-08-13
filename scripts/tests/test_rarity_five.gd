extends SceneTree
## 稀有度五档实施校验（2026-08-13，见 docs/design/稀有度五档实施报告.md）：
##  1. items.json / wands.json 五档 rarity 均存在且合法，迁移后数量合理
##  2. UiTheme.RARITY 五色映射 = 白 #d9d9e2 / 绿 #6fce6f / 蓝 #4a9eff /
##     金 #ffc84d / 红 #ff5c5c（含 RARITY_NAMES 中文档名）
##  3. drops.json item_rarity_weights = 0.42/0.26/0.19/0.10/0.03（和=1）
##  4. wand_shop.gd RARITY_WEIGHT = 100/70/30/20/6、LUCKY_RARITY_BOOST = 1/1.5/2/2.5/4
##  5. wands 硬规则：连发/齐射（shape=rapid 或 shots>=3）必须 legendary 红；
##     每流派至少 1 把红；价格五档区间严格不重叠
##  6. 构筑商店 _build_price 五档 80/110/150/200/260
## 运行：godot --headless --path . -s res://scripts/tests/test_rarity_five.gd

const RARITY_ORDER: Array = ["common", "uncommon", "rare", "epic", "legendary"]
const RARITY_COLORS := {
	"common": Color("#d9d9e2"),
	"uncommon": Color("#6fce6f"),
	"rare": Color("#4a9eff"),
	"epic": Color("#ffc84d"),
	"legendary": Color("#ff5c5c"),
}
const ITEM_WEIGHTS := {
	"common": 0.42, "uncommon": 0.26, "rare": 0.19, "epic": 0.10, "legendary": 0.03,
}
const SHOP_WEIGHTS := {
	"common": 100.0, "uncommon": 70.0, "rare": 30.0, "epic": 20.0, "legendary": 6.0,
}
const SHOP_BOOST := {
	"common": 1.0, "uncommon": 1.5, "rare": 2.0, "epic": 2.5, "legendary": 4.0,
}
const PRICE_BANDS := {
	"common": [120, 250], "uncommon": [260, 360], "rare": [370, 550],
	"epic": [560, 690], "legendary": [700, 1200],
}

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
		print("RARITY FIVE OK")
	else:
		for f in failures:
			push_error("RARITY FIVE FAIL: " + f)
	quit(0 if failures.is_empty() else 1)
	return true

func fail(msg: String) -> void:
	failures.append(msg)

func _gs() -> Node:
	return root.get_node_or_null("GameState")

func _counts(items: Array, key: String) -> Dictionary:
	var c := {}
	for it in items:
		var r: String = str(it.get(key, ""))
		c[r] = int(c.get(r, 0)) + 1
	return c

func _run() -> void:
	var gs := _gs()
	if gs == null:
		fail("GameState autoload missing")
		return
	var items: Array = gs.tables.get("items", {}).get("items", [])
	var wands: Array = gs.tables.get("wands", {}).get("wands", [])
	var drops: Dictionary = gs.tables.get("drops", {})

	# 1. 五档均存在且合法
	var ic := _counts(items, "rarity")
	var wc := _counts(wands, "rarity")
	for r in RARITY_ORDER:
		if not ic.has(r) or int(ic[r]) <= 0:
			fail("items 缺少稀有度档 %s（实际 %s）" % [r, str(ic)])
		if not wc.has(r) or int(wc[r]) <= 0:
			fail("wands 缺少稀有度档 %s（实际 %s）" % [r, str(wc)])
	for it in items:
		var r: String = str(it.get("rarity", ""))
		if not RARITY_ORDER.has(r):
			fail("item %s rarity 非法：%s" % [it.get("id", "?"), r])
	for w in wands:
		var r: String = str(w.get("rarity", ""))
		if not RARITY_ORDER.has(r):
			fail("wand %s rarity 非法：%s" % [w.get("id", "?"), r])

	# 迁移后数量：白≈绿≈蓝≈金，红≈原传说数（items 57 / wands 21）
	if int(ic["common"]) < 30 or int(ic["uncommon"]) < 30 \
			or int(ic["rare"]) < 30 or int(ic["epic"]) < 30:
		fail("items 白/绿/蓝/金数量不合理：%s" % str(ic))
	if int(ic["legendary"]) != 57:
		fail("items 红应 57 件（旧传说全保留），实际 %s" % str(ic))
	if int(wc["legendary"]) != 21:
		fail("wands 红应 21 把（连发/齐射 13 + 强传说 8），实际 %s" % str(wc))

	# 2. UiTheme 五色映射 + 中文档名
	for r in RARITY_ORDER:
		var got: Color = UiTheme.RARITY.get(r, Color.BLACK)
		if got != RARITY_COLORS[r]:
			fail("UiTheme.RARITY[%s] = %s，期望 %s" % [r, str(got), str(RARITY_COLORS[r])])
	var names: Dictionary = UiTheme.RARITY_NAMES
	if names.get("common", "") != "白色" or names.get("legendary", "") != "红色" \
			or names.get("epic", "") != "金色":
		fail("UiTheme.RARITY_NAMES 缺失/错误：%s" % str(names))

	# 3. drops.json 升级三选一权重（和 = 1）
	var rw: Dictionary = drops.get("item_rarity_weights", {})
	var total := 0.0
	for r in RARITY_ORDER:
		if not rw.has(r):
			fail("drops.item_rarity_weights 缺 %s：%s" % [r, str(rw)])
		total += float(rw.get(r, 0.0))
	if absf(total - 1.0) > 1e-6:
		fail("drops.item_rarity_weights 和 = %.4f（应 1.0）" % total)
	for r in RARITY_ORDER:
		if absf(float(rw.get(r, 0.0)) - ITEM_WEIGHTS[r]) > 1e-6:
			fail("drops.item_rarity_weights[%s] = %s，期望 %s"
				% [r, str(rw.get(r)), str(ITEM_WEIGHTS[r])])

	# 4. 商店权重/幸运梯度
	var shop_script: GDScript = load("res://scripts/ui/game/wand_shop.gd")
	var sw: Dictionary = shop_script.RARITY_WEIGHT
	var sb: Dictionary = shop_script.LUCKY_RARITY_BOOST
	for r in RARITY_ORDER:
		if absf(float(sw.get(r, 0.0)) - SHOP_WEIGHTS[r]) > 1e-6:
			fail("RARITY_WEIGHT[%s] = %s，期望 %s" % [r, str(sw.get(r)), str(SHOP_WEIGHTS[r])])
		if absf(float(sb.get(r, 0.0)) - SHOP_BOOST[r]) > 1e-6:
			fail("LUCKY_RARITY_BOOST[%s] = %s，期望 %s" % [r, str(sb.get(r)), str(SHOP_BOOST[r])])

	# 5. wands 硬规则
	var schools := {}
	for w in wands:
		schools[str(w.get("school", "?"))] = int(schools.get(str(w.get("school", "?")), 0)) + 1
	for s in schools:
		var has_leg := false
		for w in wands:
			if str(w.get("school", "")) == s and str(w.get("rarity", "")) == "legendary":
				has_leg = true
				break
		if not has_leg:
			fail("流派 %s 没有 legendary 法杖" % s)
	for w in wands:
		var mods: Dictionary = w.get("shape_mods", {})
		if w.get("shape", "") == "rapid" or int(mods.get("shots", 1)) >= 3:
			if str(w.get("rarity", "")) != "legendary":
				fail("连发/齐射法杖 %s 必须 legendary，实际 %s"
					% [w.get("id", "?"), w.get("rarity")])
		var band: Array = PRICE_BANDS.get(str(w.get("rarity", "")), [])
		var p: int = int(w.get("price", 0))
		if band.is_empty() or p < int(band[0]) or p > int(band[1]):
			fail("wand %s price %d 超出 %s 档位 %s"
				% [w.get("id", "?"), p, w.get("rarity"), str(band)])

	# 6. 构筑商店 _build_price 五档
	var expected_build := {
		"common": 80, "uncommon": 110, "rare": 150, "epic": 200, "legendary": 260,
	}
	var shop: CanvasLayer = shop_script.new()
	for r in RARITY_ORDER:
		var got_p: Variant = shop._build_price({"rarity": r})
		if int(got_p) != int(expected_build[r]):
			fail("_build_price(%s) = %s，期望 %s" % [r, str(got_p), str(expected_build[r])])
	shop.free()
