extends SceneTree
## 批次B性能优化回归测试 + benchmark（headless）
## 断言：① 背景生成后 texture 1280x1280 且像素与旧算法逐点一致（抽样）；
##       ② level.gd 背景生成不再使用 set_pixel（静态源码检查）；
##       ③ estimate_dps 与改造前线性查找算法结果一致（抽样多个法术网格）；
##       ④ apply_item_effects_to_stats 的 max_hp 与改造前语义一致。
## 附 benchmark：旧 set_pixel 双层循环 vs 新 blit_rect 按行拷贝 的耗时对比。
## Run: godot --headless --path . -s res://scripts/tests/test_perf_batch_b.gd

const GRASS_PATH := "res://assets/env/scene_grass.png"
const BG_W := 1280
const BG_H := 1280
const GRASS_TOP := 201
const GRASS_H := 519

var failures: Array[String] = []
var _frame := 0


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	_run_all()
	if failures.is_empty():
		print("TEST PERF BATCH B OK")
	else:
		for f in failures:
			push_error("TEST PERF BATCH B FAIL: " + f)
	quit(0 if failures.is_empty() else 1)
	return true


func _fail(msg: String) -> void:
	failures.append(msg)
	print("[FAIL] " + msg)


func _gs() -> Node:
	return root.get_node_or_null("GameState")


func _run_all() -> void:
	var gs := _gs()
	if gs == null:
		_fail("GameState autoload missing")
		return
	_bench_bg()
	_test_no_set_pixel()
	_test_bg_pixels()
	_test_estimate_dps(gs)
	_test_apply_items(gs)


# ================= ① 背景生成：尺寸 + 像素一致性 =================

func _test_no_set_pixel() -> void:
	## 静态检查：_build_scene_background 内不应再出现逐像素 set_pixel
	var f := FileAccess.open("res://scripts/enemies/level.gd", FileAccess.READ)
	if f == null:
		_fail("cannot read level.gd")
		return
	var src: String = f.get_as_text()
	var start := src.find("func _build_scene_background")
	var end := src.find("func _build_walls", start)
	if start < 0 or end < 0:
		_fail("level.gd structure changed (cannot locate _build_scene_background)")
		return
	if src.substr(start, end - start).contains(".set_pixel("):
		_fail("level.gd _build_scene_background still uses set_pixel")


func _test_bg_pixels() -> void:
	## 生成后尺寸 1280x1280，且抽样像素与旧算法公式 y -> 201+(y%519) 完全一致
	var lv: Node = (load("res://scenes/game/level.tscn") as PackedScene).instantiate()
	root.add_child(lv)
	lv.call("_build_scene_background", "grass")
	var bg: Node = lv.get_node_or_null("SceneBackground")
	if bg == null:
		_fail("SceneBackground node missing")
		lv.queue_free()
		return
	var tex: Texture2D = bg.get("texture")
	if tex == null:
		_fail("SceneBackground texture null")
		lv.queue_free()
		return
	var img: Image = tex.get_image()
	var size: Vector2i = img.get_size()
	if size != Vector2i(BG_W, BG_H):
		_fail("background size != 1280x1280 (got %s)" % str(size))
		lv.queue_free()
		return
	var src_img: Image = (load(GRASS_PATH) as Texture2D).get_image()
	var bad := 0
	var checked := 0
	# 关键边界行（0 / 分段交界 / 最后一行）逐行整行抽样 + 随机点
	for y in [0, 200, 201, 518, 519, 719, 720, 1000, 1279]:
		for x in range(0, BG_W, 53):
			var sy: int = GRASS_TOP + (y % GRASS_H)
			checked += 1
			if img.get_pixel(x, y) != src_img.get_pixel(x, sy):
				bad += 1
	for i in 40:
		var x := randi() % BG_W
		var y := randi() % BG_H
		var sy := GRASS_TOP + (y % GRASS_H)
		checked += 1
		if img.get_pixel(x, y) != src_img.get_pixel(x, sy):
			bad += 1
	if bad > 0:
		_fail("background pixel mismatch: %d/%d samples" % [bad, checked])
	lv.queue_free()


# ================= ③ estimate_dps：与改造前线性查找语义一致 =================

func _dps_ref(grid: Array) -> float:
	## estimate_dps 的独立复刻（2026-08-13 新口径：对齐 spell_caster 实际公式），
	## 作为行为基准防止后续改动漂移。逐项覆盖：atk/skill_dmg/元素/法杖/暴击/攻速/减cd/
	## 充能/shots/群战放大/召唤物/狂暴。
	var gs := _gs()
	var spells: Dictionary = gs.tables.get("spells", {})
	var atk_mult: float = 1.0 + gs.aggregate_bonus("atk")
	var skill_mult: float = 1.0 + gs.aggregate_bonus("skill_dmg")
	var as_total: float = gs.total_attack_speed_bonus()
	var as_cd_mult: float = 1.0 / (1.0 + as_total)
	var cd_reduce: float = clampf(gs.aggregate_bonus("cooldown") + gs.aggregate_bonus("skill_cd"), 0.0, 0.8)
	var wind_cd_mult: float = maxf(float(gs.run.get("wind_cd_mult", 1.0)), 0.0)
	var wand_charge_mult: float = gs.item_value(
		{"curve": {"type": "multiplicative", "base": 0.9, "cap": 0.5}}, gs.total_stacks("wand_charge"))
	var crit_chance: float = clampf(0.03 + 0.02 * float(gs.total_stacks("crit_glasses")), 0.0, 0.85)
	var crit_dmg: float = 1.5 * (1.0 + 0.10 * float(gs.total_stacks("crit_gem"))) \
		+ float(gs.run.get("synergy_bonus", {}).get("crit_dmg", 0.0))
	var crit_mult: float = 1.0 + crit_chance * (crit_dmg - 1.0)
	var wand_dmg_mult: float = 1.0
	var wand_cd_mult: float = 1.0
	var wand_element_bonus: Dictionary = {}
	var wand_shape: Dictionary = {}
	for wid in gs.current_wands():
		var wdef: Dictionary = gs.wand_def(str(wid))
		if wdef.is_empty():
			continue
		wand_dmg_mult *= float(wdef.get("damage_mult", 1.0))
		wand_cd_mult *= float(wdef.get("cd_mult", 1.0))
		var eb: Dictionary = wdef.get("element_bonus", {})
		for el in eb:
			wand_element_bonus[el] = float(wand_element_bonus.get(el, 1.0)) * (1.0 + float(eb[el]))
		for k in wdef.get("shape_mods", {}):
			wand_shape[k] = wdef["shape_mods"][k]
	var wand_upgrade_mult: float = 1.0
	for wid in gs.current_wands():
		wand_upgrade_mult *= 1.0 + gs.WAND_UPGRADE_BONUS * float(gs.wand_upgrade_level(str(wid)))
	var core_by_id := {}
	for c in spells.get("cores", []):
		core_by_id[str(c.get("id", ""))] = c
	var shell_by_id := {}
	for s in spells.get("shells", []):
		shell_by_id[str(s.get("id", ""))] = s
	var summon_defs := {}
	for s in gs.tables.get("summons", {}).get("summons", []):
		summon_defs[str(s.get("id", ""))] = s
	var total := 0.0
	var frenzy := false
	var summon_slots: Array = []
	for slot in grid:
		var core: Dictionary = core_by_id.get(str(slot.get("core", "")), {})
		if core.is_empty():
			continue
		if core.get("frenzy", false):
			frenzy = true
			continue
		if core.get("mana_echo", false):
			continue
		var tid: String = str(core.get("summon", ""))
		if str(core.get("element", "")) == "summon" or (tid != "" and tid != "true"):
			if tid == "" or tid == "true":
				tid = str(core.get("id", "")).trim_prefix("summon_")
			summon_slots.append({"tid": tid, "core": core,
				"shell": shell_by_id.get(str(slot.get("shell", "")), {})})
			continue
		var shell: Dictionary = shell_by_id.get(str(slot.get("shell", "")), {})
		var mods: Dictionary = shell.get("mods", {})
		var merged: Dictionary = mods.duplicate()
		for k in wand_shape:
			merged[k] = wand_shape[k]
		var element: String = str(core.get("element", "fire"))
		var dmg: float = float(core.get("base_damage", 0.0)) \
			* float(merged.get("damage_mult", 1.0)) \
			* atk_mult * skill_mult \
			* (1.0 + gs.aggregate_bonus(element)) \
			* float(wand_element_bonus.get(element, 1.0)) \
			* wand_dmg_mult * wand_upgrade_mult
		var shots: int = maxi(int(merged.get("shots", 1)), 1) \
			+ maxi(int(gs.run.get("wind_m4_shots", 0)), 0)
		var cd: float = float(core.get("cooldown", 1.0)) \
			* float(mods.get("cooldown_mult", 1.0)) \
			* wand_cd_mult * wand_charge_mult \
			* as_cd_mult * wind_cd_mult * (1.0 - cd_reduce)
		cd = maxf(cd, 0.05)
		var multihit := 1.0
		if int(core.get("chain", 0)) > 0:
			multihit *= 1.0 + float(core.get("chain", 0)) * 0.7
		if int(merged.get("pierce", 0)) > 0:
			multihit *= 1.0 + float(merged.get("pierce", 0)) * 0.6
		if int(merged.get("split", 0)) > 0:
			multihit *= 1.0 + float(merged.get("split", 0)) * 0.6
		if int(merged.get("bounce", 0)) > 0:
			multihit *= 1.0 + float(merged.get("bounce", 0)) * 0.35
		var aoe_r: float = float(core.get("aoe", 0.0)) * float(merged.get("aoe_mult", 1.0)) \
			* (1.0 + gs.aggregate_bonus("area"))
		if aoe_r <= 0.0 and float(core.get("blind", 0.0)) > 0.0:
			aoe_r = 90.0 * float(merged.get("aoe_mult", 1.0))
		if aoe_r > 0.0:
			multihit *= 1.0 + minf(aoe_r / 35.0, 1.0)
		multihit = minf(multihit, 3.5)
		total += dmg * float(shots) / cd * crit_mult * multihit
	if not summon_slots.is_empty():
		var summon_cap: int = 1 + gs.total_stacks("summon_1")
		var max_sum := 0
		var per_hit_w := 0.0
		var cd_w := 0.0
		for entry in summon_slots:
			var sdef: Dictionary = summon_defs.get(str(entry.get("tid", "")), {})
			if sdef.is_empty():
				continue
			var mc: int = int(sdef.get("max_count", 1))
			max_sum += mc
			var per_hit: float = float(entry.get("core", {}).get("base_damage", 30.0)) \
				* float(entry.get("shell", {}).get("mods", {}).get("damage_mult", 1.0)) \
				* float(sdef.get("damage_mult", 1.0)) \
				* atk_mult * skill_mult \
				* (1.0 + gs.aggregate_bonus("summon")) \
				* float(wand_element_bonus.get("summon", 1.0)) \
				* wand_dmg_mult * wand_upgrade_mult
			per_hit_w += per_hit * float(mc)
			cd_w += maxf(float(sdef.get("skill_cd", 1.0)), 0.5) * float(mc)
		if cd_w > 0.0:
			var alive: int = mini(max_sum, summon_cap)
			total += float(alive) * per_hit_w / cd_w * crit_mult
	if frenzy:
		total *= 1.7
	return total


func _test_estimate_dps(gs: Node) -> void:
	gs.new_run()
	gs.run.items = {"wand_charge": 3, "summon_1": 2}
	gs.run.wand_upgrade_levels = {"basic_wand": 1}
	var grids: Array = [
		[],
		[{"core": "fireball", "shell": "rapid"}, {"core": "ice_shard", "shell": "spread"}],
		[{"core": "lightning", "shell": "homing"}, {"core": "summon_bat", "shell": "rapid"},
			{"core": "whirl_blade", "shell": "orbit"}, {"core": "inferno", "shell": "burst"}],
		[{"core": "fireball", "shell": "rapid"}, {"core": "no_such_core", "shell": "spread"},
			{"core": "ice_shard", "shell": ""}, {"core": "summon_bat", "shell": "delay"},
			{"core": "water_bolt", "shell": "no_such_shell"}],
	]
	for i in grids.size():
		gs.run.grid = grids[i]
		var got: float = gs.estimate_dps()
		var want: float = _dps_ref(grids[i])
		if absf(got - want) > 1e-9:
			_fail("estimate_dps mismatch grid#%d: got=%.6f want=%.6f diff=%.3e" % [i, got, want, got - want])
	print("[TEST] estimate_dps checked %d grids" % grids.size())


# ================= ④ apply_item_effects_to_stats：max_hp 语义一致 =================

func _test_apply_items(gs: Node) -> void:
	gs.new_run()
	gs.run.player_level = 3
	gs.run.items = {"life_crystal": 2, "defense_crystal": 1, "wand_charge": 4}
	gs.run.synergy_bonus = {"max_hp": 30.0}
	# 改造前语义：基础 + 每级成长 + synergy_bonus.max_hp + 全表线性扫 hp/max_hp tag 道具
	var expected: int = int(gs.balance().get("player", {}).get("hp", 100)) \
		+ 10 * (gs.run.get("player_level", 1) - 1) \
		+ int(gs.run.get("synergy_bonus", {}).get("max_hp", 0.0))
	for it in gs.tables.get("items", {}).get("items", []):
		var tags: Array = it.get("tags", [])
		if "hp" in tags or "max_hp" in tags:
			expected += int(gs.item_value(it, gs.total_stacks(str(it.get("id", "")))))
	gs.apply_item_effects_to_stats()
	if gs.run.max_hp != expected:
		_fail("max_hp mismatch: got=%d want=%d" % [gs.run.max_hp, expected])
	# 再刷一次（走索引缓存路径），结果必须一致
	gs.apply_item_effects_to_stats()
	if gs.run.max_hp != expected:
		_fail("max_hp mismatch on cached index refresh: got=%d want=%d" % [gs.run.max_hp, expected])
	print("[TEST] apply_item_effects_to_stats max_hp=%d (want %d)" % [gs.run.max_hp, expected])


# ================= benchmark：旧 set_pixel vs 新 blit_rect =================

func _bench_bg() -> void:
	var src_img: Image = (load(GRASS_PATH) as Texture2D).get_image()
	src_img.convert(Image.FORMAT_RGBA8)
	# 改造前：双层 for 逐像素 set_pixel（约 164 万次调用）
	var old_us := 0
	for _r in 1:
		var t0 := Time.get_ticks_usec()
		var square := Image.create(BG_W, BG_H, false, Image.FORMAT_RGBA8)
		for y in BG_H:
			var src_y := GRASS_TOP + (y % GRASS_H)
			for x in BG_W:
				square.set_pixel(x, y, src_img.get_pixel(x, src_y))
		ImageTexture.create_from_image(square)
		old_us += Time.get_ticks_usec() - t0
	# 改造后：每行一次 blit_rect 批量拷贝（共 1280 次）
	var new_us := 0
	for _r in 3:
		var t0 := Time.get_ticks_usec()
		var square := Image.create(BG_W, BG_H, false, Image.FORMAT_RGBA8)
		for y in BG_H:
			var src_y := GRASS_TOP + (y % GRASS_H)
			square.blit_rect(src_img, Rect2i(0, src_y, BG_W, 1), Vector2i(0, y))
		ImageTexture.create_from_image(square)
		new_us += Time.get_ticks_usec() - t0
	var old_ms := float(old_us) / 1000.0
	var new_ms := float(new_us) / 3000.0
	print("[BENCH] bg_gen old=%.1fms new=%.1fms speedup=%.1fx" % [old_ms, new_ms, old_ms / maxf(new_ms, 0.001)])
	# 完整 _build_scene_background（含资源加载 + Sprite2D 创建）参考耗时
	var t0 := Time.get_ticks_usec()
	var lv: Node = (load("res://scenes/game/level.tscn") as PackedScene).instantiate()
	root.add_child(lv)
	lv.call("_build_scene_background", "grass")
	var full_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("[BENCH] _build_scene_background full=%.1fms" % full_ms)
	lv.queue_free()
