extends SceneTree
## estimate_dps 对齐测试（2026-08-13）：
## ① 基准 build（fireball×rapid + basic_wand 无道具）理论 DPS 落在手算区间；
## ② 后期成型 build 理论 DPS >= 1000（与实际 1 万+ 同一数量级）；
## ③ 逐乘数接线检查：攻速/暴击/元素/减cd/法杖/外壳 shots/召唤/狂暴/连锁 都会提高估算。
## Run: godot --headless --path . -s res://scripts/tests/test_estimate_dps.gd

var failures: Array[String] = []
var _frame := 0

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	_run()
	if failures.is_empty():
		print("ESTIMATE DPS TESTS OK")
	else:
		for f in failures:
			push_error("ESTIMATE DPS FAIL: " + f)
	quit(0 if failures.is_empty() else 1)
	return true

func _fail(msg: String) -> void:
	failures.append(msg)
	print("[FAIL] " + msg)

func _gs() -> Node:
	return root.get_node_or_null("GameState")

func _run() -> void:
	var gs := _gs()
	if gs == null:
		_fail("GameState autoload missing")
		return
	_test_basic_band(gs)
	_test_late_build(gs)
	_test_multiplier_wiring(gs)
	_test_no_item_baseline(gs)

func _reset(gs: Node, grid: Array, wands: Array, items: Dictionary) -> void:
	gs.new_run()
	gs.run.grid = grid
	gs.run.wands = wands
	gs.run.items = items
	gs.run.wand_upgrade_levels = {}
	gs.apply_item_effects_to_stats()

func _test_basic_band(gs: Node) -> void:
	# 手算：dmg=12*0.8=9.6, shots=3, cd=1.2*1.5=1.8, crit×1.015, aoe18→×1.514
	# → 9.6*3/1.8*1.015*1.514 ≈ 24.6
	_reset(gs, [{"core": "fireball", "shell": "rapid"}], ["basic_wand"], {})
	var v: float = float(gs.estimate_dps())
	if v < 20.0 or v > 30.0:
		_fail("basic band: fireball×rapid 理论 DPS %.2f 不在 [20,30]" % v)
	print("[OK] basic band estimate=%.2f" % v)

func _test_late_build(gs: Node) -> void:
	# 后期成型（第 5 关/最终 Boss 前）：5 槽 + 3 法杖强化 + 元素/暴击/攻速/减cd/召唤
	_reset(gs, [
		{"core": "fireball", "shell": "rapid"},
		{"core": "inferno", "shell": "burst"},
		{"core": "lightning", "shell": "spread"},
		{"core": "whirl_blade", "shell": "orbit"},
		{"core": "summon_bat", "shell": "rapid"},
	], ["phoenix_staff", "rapid_staff", "fire_rain_staff"], {
		"strength_badge": 3, "attack_speed_potion": 3, "wand_charge": 3,
		"crit_glasses": 3, "crit_gem": 2, "memory_power": 1,
		"trinket_ember": 3, "fire_ember": 3, "fire_ember_ring": 1,
		"fire_element_badge": 3, "fire_prism": 1, "summon_1": 3,
		"fire_attack_potion": 2, "thunder_5": 1,
	})
	gs.run.wand_upgrade_levels = {"phoenix_staff": 2, "rapid_staff": 1}
	gs.apply_item_effects_to_stats()
	var v: float = float(gs.estimate_dps())
	if v < 1000.0:
		_fail("late build: 理论 DPS %.0f < 1000（与实际 1 万+ 数量级不齐）" % v)
	print("[OK] late estimate=%.0f (>= 1000)" % v)

func _test_multiplier_wiring(gs: Node) -> void:
	## 每个乘数单独接线检查：基线起步，逐一叠加，估算必须严格上升
	var base: float = _dps_of(gs, [{"core": "fireball", "shell": ""}], ["basic_wand"], {})
	print("[OK] baseline fireball native=%.2f" % base)
	var cases: Array = [
		["atk 道具 strength_badge×1", [{"core": "fireball", "shell": ""}], ["basic_wand"], {"strength_badge": 1}],
		["攻速 attack_speed_potion×1", [{"core": "fireball", "shell": ""}], ["basic_wand"], {"attack_speed_potion": 1}],
		["暴击率 crit_glasses×3", [{"core": "fireball", "shell": ""}], ["basic_wand"], {"crit_glasses": 3}],
		["暴伤 crit_gem×2", [{"core": "fireball", "shell": ""}], ["basic_wand"], {"crit_gem": 2}],
		["元素 trinket_ember×2", [{"core": "fireball", "shell": ""}], ["basic_wand"], {"trinket_ember": 2}],
		["减cd wand_charge×2", [{"core": "fireball", "shell": ""}], ["basic_wand"], {"wand_charge": 2}],
		["技能伤 memory_power×1", [{"core": "fireball", "shell": ""}], ["basic_wand"], {"memory_power": 1}],
		["外壳 shots（rapid）", [{"core": "fireball", "shell": "rapid"}], ["basic_wand"], {}],
		["法杖元素+范围（fire_staff）", [{"core": "fireball", "shell": ""}], ["fire_staff"], {}],
		["法杖强化 Lv1", [{"core": "fireball", "shell": ""}], ["basic_wand"], {}, {"basic_wand": 1}],
		["连锁核（lightning）", [{"core": "lightning", "shell": ""}], ["basic_wand"], {}],
		["召唤核（fireball+summon_bat）", [{"core": "fireball", "shell": ""}, {"core": "summon_bat", "shell": ""}], ["basic_wand"], {}],
		["狂暴核（frenzy）", [{"core": "fireball", "shell": ""}, {"core": "frenzy", "shell": ""}], ["basic_wand"], {}],
	]
	for c in cases:
		var tag: String = str(c[0])
		var grid: Array = c[1]
		var wands: Array = c[2]
		var items: Dictionary = c[3]
		var upgrades: Dictionary = c[4] if c.size() > 4 else {}
		_reset(gs, grid, wands, items)
		gs.run.wand_upgrade_levels = upgrades
		gs.apply_item_effects_to_stats()
		var v: float = float(gs.estimate_dps())
		if v <= base:
			_fail("wiring: %s 未提高估算（base=%.2f got=%.2f）" % [tag, base, v])
		else:
			print("[OK] wiring %s -> %.2f (base %.2f)" % [tag, v, base])

func _test_no_item_baseline(gs: Node) -> void:
	## 无道具、单槽原生：估算不为 0 且 > 0
	var v: float = _dps_of(gs, [{"core": "fireball", "shell": ""}], ["basic_wand"], {})
	if v <= 0.0:
		_fail("no-item baseline must be > 0 (got %.2f)" % v)
	print("[OK] no-item baseline=%.2f" % v)

func _dps_of(gs: Node, grid: Array, wands: Array, items: Dictionary) -> float:
	_reset(gs, grid, wands, items)
	return float(gs.estimate_dps())
