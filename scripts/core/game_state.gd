extends Node
## 全局游戏状态：跨场景共享的唯一数据源（数据驱动，勿硬编码数值）

const DATA_DIR := "res://data/"
const MAP_SIZE := Vector2(1280, 720)  # 关卡地图尺寸（视口 640x360，相机跟随）

var run: Dictionary = {}
var tables: Dictionary = {}  # items/spells/enemies/levels/drops/balance

func _ready() -> void:
	load_tables()
	new_run()

func load_tables() -> void:
	for t in ["balance", "items", "spells", "enemies", "levels", "drops"]:
		var path: String = DATA_DIR + t + ".json"
		if ResourceLoader.exists(path):
			var f := FileAccess.open(path, FileAccess.READ)
			if f:
				var parsed = JSON.parse_string(f.get_as_text())
				if parsed is Dictionary:
					tables[t] = parsed
		if not tables.has(t):
			push_warning("数据表缺失: " + t)
			tables[t] = {}

func new_run() -> void:
	run = {
		"loop": 1,
		"level": 1,
		"gold": 0,
		"xp": 0,
		"player_level": 1,
		"hp": 100,
		"max_hp": 100,
		"dps_estimate": 0.0,
		"items": {},
		"trinkets": [],
		"grid": [],
		"skill": null,
		"memory": null,
		"kills": 0,
		"time": 0.0,
		"pity": 0,
		"level_elapsed": 0.0,  # 本关已过时间（存档续波次用）
	}
	# 初始构筑：保证开局可战（DEMO 数值：两格法术 + 一件道具）
	run.grid = [
		{"core": "fireball", "shell": ""},
		{"core": "whirl_blade", "shell": "rapid"},
	]
	add_item("attack_speed_potion")

func add_item(item_id: String) -> void:
	run.items[item_id] = run.items.get(item_id, 0) + 1
	run.last_picked = item_id  # 物品栏"最近获得"高亮
	EventBus.item_picked.emit(item_id, run.items[item_id])
	EventBus.player_stats_changed.emit()

func add_gold(n: int) -> void:
	run.gold += n
	EventBus.player_stats_changed.emit()

func add_xp(n: int) -> void:
	run.xp += n
	var need := xp_to_next(run.player_level)
	while run.xp >= need:
		run.xp -= need
		run.player_level += 1
		need = xp_to_next(run.player_level)
	EventBus.player_stats_changed.emit()

func xp_to_next(level: int) -> int:
	# 平滑升级曲线：L1≈50(约6只怪) → L5≈220 → L10≈455，增幅逐级微增
	var l := maxi(level, 1)
	var xp: Dictionary = balance().get("xp", {})
	return int(xp.get("base", 50)) + int(xp.get("per_level", 30)) * (l - 1) \
		+ int(xp.get("quad", 5)) * (l - 1) * (l - 1)

func level_factor(level: int) -> float:
	return pow(1.18, level - 1)

func loop_factor_hp(loop: int) -> float:
	return pow(1.30, loop - 1)

func loop_factor_dmg(loop: int) -> float:
	return pow(1.18, loop - 1)

func loop_factor_num(loop: int) -> float:
	return pow(1.25, loop - 1)

func enemy_hp(base: float, level: int, loop: int) -> float:
	return base * level_factor(level) * loop_factor_hp(loop)

func enemy_atk(base: float, level: int, loop: int) -> float:
	return base * (1.0 + 0.12 * (level - 1)) * loop_factor_dmg(loop)

func enemy_xp(base: float, level: int, loop: int) -> int:
	# 经验随关卡递增（与敌人强度同节奏），保证后期升级不至于过慢
	var lx: float = tables.get("balance", {}).get("enemy_scaling", {}).get("level_xp", 0.12)
	return int(base * (1.0 + lx * (level - 1)) * pow(1.35, loop - 1))

func item_value(item: Dictionary, stacks: int) -> float:
	## 道具曲线求值（契约：linear/exp_proc/threshold/multiplicative）
	var c: Dictionary = item.get("curve", {})
	var t: String = c.get("type", "linear")
	var n: int = maxi(stacks, 0)
	var base: float = c.get("base", 0.0)
	var v := 0.0
	match t:
		"linear":
			v = base * (1.0 + c.get("k", 0.0) * n)
		"exp_proc":
			v = 1.0 - pow(1.0 - c.get("p", 0.1), n + 1)
		"threshold":
			var T: int = maxi(c.get("threshold", 1), 1)
			v = base + c.get("step", 0.0) * (n / T)
		"multiplicative":
			v = pow(base, n)
	if c.has("cap"):
		if t == "multiplicative" and base < 1.0:
			v = maxf(v, c["cap"])  # 乘性衰减类：cap 为下限
		else:
			v = minf(v, c["cap"])
	return v

func item_def(item_id: String) -> Dictionary:
	for it in tables.get("items", {}).get("items", []):
		if str(it.get("id", "")) == item_id:
			return it
	return {}

func roll_item_choices(count: int = 3) -> Array:
	## 升级三选一：按稀有度权重从掉落池取样（不重复）
	var pool: Array = tables.get("items", {}).get("items", []).duplicate()
	var weights: Dictionary = tables.get("drops", {}).get("item_rarity_weights", {})
	var chosen: Array = []
	while chosen.size() < count and not pool.is_empty():
		var total := 0.0
		for it in pool:
			total += weights.get(it.get("rarity", "common"), 0.2)
		var roll := randf() * total
		var acc := 0.0
		var picked := -1
		for i in pool.size():
			acc += weights.get(pool[i].get("rarity", "common"), 0.2)
			if roll <= acc:
				picked = i
				break
		if picked < 0:
			picked = pool.size() - 1
		chosen.append(pool[picked])
		pool.remove_at(picked)
	return chosen

func add_spell_part(core_id: String, shell_id: String = "") -> void:
	## 法术碎片掉落：自动填入网格第一个空槽（DEMO 简化，保留排序机制）
	var slots: int = tables.get("balance", {}).get("max_grid_slots", 5)
	var grid: Array = run.grid
	if grid.size() < slots:
		grid.append({"core": core_id, "shell": shell_id})
		EventBus.spell_arranged.emit(grid)

func add_trinket(trinket_id: String) -> void:
	var slots: int = tables.get("balance", {}).get("trinket_slots", 3)
	var t: Array = run.trinkets
	if t.size() < slots:
		t.append(trinket_id)
	EventBus.player_stats_changed.emit()

func swap_grid(a: int, b: int) -> void:
	var grid: Array = run.grid
	if a < 0 or b < 0 or a >= grid.size() or b >= grid.size() or a == b:
		return
	var tmp = grid[a]
	grid[a] = grid[b]
	grid[b] = tmp
	EventBus.spell_arranged.emit(grid)

func total_stacks(item_id: String) -> int:
	return run.items.get(item_id, 0)

func aggregate_bonus(tag: String) -> float:
	## 聚合某个 tag 下所有道具的曲线值（如 "attack_speed" 返回总攻速加成）
	var sum := 0.0
	for item_id in run.items:
		var it := item_def(item_id)
		if it.is_empty() or tag not in it.get("tags", []):
			continue
		sum += item_value(it, run.items[item_id])
	return sum

func estimate_dps() -> float:
	## 估算 DPS：网格内每个法术 raw×次数×攻速加成 / 冷却（供 HUD 与爽感档位）
	var bal: Dictionary = tables.get("balance", {})
	var spells: Dictionary = tables.get("spells", {})
	var atk_bonus := 1.0 + aggregate_bonus("atk")
	var speed_bonus := 1.0 + aggregate_bonus("attack_speed")
	var cd_bonus := 1.0
	var total := 0.0
	for slot in run.grid:
		var core: Dictionary = {}
		for c in spells.get("cores", []):
			if c.get("id", "") == slot.get("core", ""):
				core = c
				break
		if core.is_empty():
			continue
		var shell: Dictionary = {}
		for s in spells.get("shells", []):
			if s.get("id", "") == slot.get("shell", ""):
				shell = s
				break
		var mods: Dictionary = shell.get("mods", {})
		var dmg: float = core.get("base_damage", 0.0) * mods.get("damage_mult", 1.0)
		var shots: int = mods.get("shots", 1)
		var cd: float = core.get("cooldown", 1.0) * mods.get("cooldown_mult", 1.0)
		cd_bonus *= item_value({"curve": {"type": "multiplicative", "base": 0.9, "cap": 0.5}}, total_stacks("wand_charge"))
		total += dmg * shots / maxf(cd, 0.1)
	run.dps_estimate = total * atk_bonus * speed_bonus / cd_bonus
	return run.dps_estimate

func apply_item_effects_to_stats() -> void:
	## 把道具聚合到面板属性（HUD 读取）
	# 基础血量 + 每级成长（动作肉鸽惯例：升级提升容错）
	run.max_hp = int(balance().get("player", {}).get("hp", 100)) + 10 * (run.get("player_level", 1) - 1)
	run.attack_bonus = aggregate_bonus("atk")
	run.speed_bonus = aggregate_bonus("speed")
	run.attack_speed_bonus = aggregate_bonus("attack_speed")
	run.crit_chance = clampf(0.03 + 0.02 * total_stacks("crit_glasses"), 0.0, 0.85)
	run.crit_dmg_bonus = 1.5 * (1.0 + 0.10 * total_stacks("crit_gem"))
	EventBus.player_stats_changed.emit()

func balance() -> Dictionary:
	return tables.get("balance", {})
