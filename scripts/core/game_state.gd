extends Node
## 全局游戏状态：跨场景共享的唯一数据源（数据驱动，勿硬编码数值）

const DATA_DIR := "res://data/"
const MAP_SIZE := Vector2(1280, 720)  # 关卡地图尺寸（视口 640x360，相机跟随）
const PROJECTILE_SCRIPT := preload("res://scripts/combat/projectile.gd")  # 清弹道辅助（替换/添加法术后）

var run: Dictionary = {}
var tables: Dictionary = {}  # items/spells/enemies/levels/drops/balance

func _ready() -> void:
	load_tables()
	new_run()

func load_tables() -> void:
	for t in ["balance", "items", "spells", "enemies", "levels", "drops", "wands", "summons"]:
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
		"wands": ["basic_wand"],  # 法杖槽（最多 3 把，初始学徒法杖）
		"wand_upgrade_levels": {},
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
	var leveled := false
	while run.xp >= need:
		run.xp -= need
		run.player_level += 1
		leveled = true
		need = xp_to_next(run.player_level)
	if leveled:
		# 升级短暂无敌（体验优化）：1.2s 无敌帧 + 回满血，避免升级瞬间被围殴秒杀
		var p := get_tree().get_first_node_in_group("player")
		if is_instance_valid(p) and p.has_method("grant_invuln"):
			p.call("grant_invuln", 1.2)
		run.hp = run.max_hp
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
			# linear 语义修正（2026-08-10）：base×(1+k×(n-1)) —— 第 1 层 = base，
			# 每多一层 +base×k；此前 base×(1+k×n) 使"每层 +X%"首层就变成 X×(1+X)，
			# 与描述不符。k=base 的全库物品多层数值不变，仅首层与描述对齐。
			v = base * (1.0 + c.get("k", 0.0) * maxi(n - 1, 0))
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
	## 升级三选一：混合法术部件与数值道具（用户需求：三选一既有技能又有物品）
	## 网格未满时必含 1 个法术部件，其余为道具；整体洗牌保证顺序随机
	## 元素权重倾向（F9）：持有某元素越多，该元素选项出现概率越高
	## 公式：权重 = 基础 × (1 + 0.02 × 持有件数 × 关卡系数)，总提升上限 +60%；
	## 非主流元素保底：若存在非主流元素池，至少 1 个选项来自其中
	var choices: Array = []
	var pool: Array = tables.get("items", {}).get("items", []).duplicate()
	var weights: Dictionary = tables.get("drops", {}).get("item_rarity_weights", {})
	var lv_factor := 1.0 + 0.25 * maxf(float(run.get("level", 1)) - 1.0, 0.0)
	var holdings := _element_holdings()
	# N2 构筑筛选：玩家未持有的元素流派构筑（数值/机制）不进入选项池——它们依赖对应
	# 元素技能触发（mechanic:xxx 条目同样带流派 tag）；无元素 tag 的通用构筑
	# （attack_speed/crit/defense/lifesteal/speed/cooldown/area 等）与法术部件保留。
	# 过滤后不足 count 个选项时放宽到不过滤（避免抽空池子）。
	var filtered_pool: Array = []
	for it in pool:
		var el := _element_key(it)
		if el != "" and not holdings.has(el):
			continue
		filtered_pool.append(it)
	if filtered_pool.size() >= count:
		pool = filtered_pool
	var main_el := _main_element(holdings)
	# 非主流元素保底池（仅当存在主流元素且有非主流选项时生效）
	var off_pool: Array = []
	if main_el != "":
		for it in pool:
			if _element_key(it) != "" and _element_key(it) != main_el:
				off_pool.append(it)
	var spell_choice := _make_spell_choice()
	if not spell_choice.is_empty():
		choices.append(spell_choice)
	# 保底：从非主流池取 1 个（若池非空且尚未被法术部件占用）
	if not off_pool.is_empty() and choices.size() < count and not _choice_is_off(spell_choice, main_el):
		var pick = off_pool[randi() % off_pool.size()]
		choices.append(pick)
		pool.erase(pick)
		off_pool.erase(pick)
	while choices.size() < count and not pool.is_empty():
		var total := 0.0
		for it in pool:
			total += _element_weight(it, weights, holdings, lv_factor)
		var roll := randf() * total
		var acc := 0.0
		var picked := -1
		for i in pool.size():
			acc += _element_weight(pool[i], weights, holdings, lv_factor)
			if roll <= acc:
				picked = i
				break
		if picked < 0:
			picked = pool.size() - 1
		choices.append(pool[picked])
		pool.remove_at(picked)
	choices.shuffle()
	return choices

func _element_key(def: Dictionary) -> String:
	## 选项的元素归属：物品看 tags，法术部件看核心元素（经 id 解析）
	var tags: Array = def.get("tags", [])
	for el in ["fire", "ice", "lightning", "poison", "summon", "water", "nature", "light", "void", "blade"]:
		if el in tags:
			return el
	var id: String = str(def.get("id", ""))
	if id.begins_with("spell_part:"):
		var parts := id.split(":")
		if parts.size() > 1:
			for c in tables.get("spells", {}).get("cores", []):
				if str(c.get("id", "")) == parts[1]:
					return str(c.get("element", ""))
	return ""

func _element_holdings() -> Dictionary:
	## 当前构筑的元素持有件数：道具堆叠数 + 法术网格核心数
	var counts := {}
	for item_id in run.items:
		var el := _element_key(item_def(item_id))
		if el != "":
			counts[el] = counts.get(el, 0) + int(run.items[item_id])
	for slot in run.grid:
		var cid: String = str(slot.get("core", ""))
		for c in tables.get("spells", {}).get("cores", []):
			if str(c.get("id", "")) == cid:
				var el := str(c.get("element", ""))
				if el != "":
					counts[el] = counts.get(el, 0) + 1
				break
	return counts

func _main_element(holdings: Dictionary) -> String:
	var best := ""
	var best_n := 0
	for el in holdings:
		if int(holdings[el]) > best_n:
			best = el
			best_n = int(holdings[el])
	return best

func _element_weight(def: Dictionary, base_weights: Dictionary, holdings: Dictionary, lv_factor: float) -> float:
	var w: float = float(base_weights.get(def.get("rarity", "common"), 0.2))
	var el := _element_key(def)
	if el != "" and holdings.has(el):
		var n: int = int(holdings[el])
		if n > 0:
			w *= minf(1.0 + 0.02 * float(n) * lv_factor, 1.6)  # 上限 +60%
	return w

func _choice_is_off(def: Dictionary, main_el: String) -> bool:
	if def.is_empty() or main_el == "":
		return false
	return _element_key(def) == main_el

## ===== 法杖系统（Boss 战后金币购买，见 data/wands.json）=====

func wand_def(wand_id: String) -> Dictionary:
	for w in tables.get("wands", {}).get("wands", []):
		if str(w.get("id", "")) == wand_id:
			return w
	return {}

func current_wands() -> Array:
	## 当前装备的全部法杖（最多 3 把）；兼容旧存档的 run.wand 单值
	var ids: Array = run.get("wands", [])
	if ids.is_empty() and run.get("wand", "") != "":
		ids = [str(run["wand"])]
		run["wands"] = ids
	# 存量存档兼容：过滤已不存在的法杖 id（如被移除的 homing_staff），并写回自动修复
	var valid: Array = []
	for wid in ids:
		if not wand_def(str(wid)).is_empty():
			valid.append(wid)
	if valid.size() != ids.size():
		# 全部非法时兜底回学徒法杖，避免空法杖栏
		if valid.is_empty() and not ids.is_empty():
			valid = ["basic_wand"]
		run["wands"] = valid
	return valid

func current_wand() -> Dictionary:
	## 主法杖（第一把）：旧接口兼容（新 UI 用 current_wands）
	var ids := current_wands()
	if ids.is_empty():
		return {}
	return wand_def(str(ids[0]))

func add_wand(wand_id: String) -> void:
	## 装备新法杖（上限 3 把，超过需要先替换）
	var ids: Array = current_wands()
	if ids.size() >= 3:
		return
	ids.append(wand_id)
	run["wands"] = ids
	EventBus.player_stats_changed.emit()

func replace_wand(idx: int, wand_id: String) -> void:
	## 替换指定槽位的法杖（购买时满 3 把使用）
	var ids: Array = current_wands()
	if idx < 0 or idx >= ids.size():
		return
	ids[idx] = wand_id
	run["wands"] = ids
	EventBus.player_stats_changed.emit()

func sell_wand(idx: int) -> int:
	## 售出法杖返回 50% 金币；至少保留 1 把（不足 2 把时拒绝）
	var ids: Array = current_wands()
	if idx < 0 or idx >= ids.size() or ids.size() <= 1:
		return 0
	var def := wand_def(str(ids[idx]))
	var refund := int(float(def.get("price", 0)) * 0.5)
	ids.remove_at(idx)
	run["wands"] = ids
	run.gold += refund
	EventBus.player_stats_changed.emit()
	return refund

func _make_spell_choice() -> Dictionary:
	## 随机法术部件选项：核心×外壳（网格满时仍返回选项，选中后由 game_root 弹替换界面）
	var spells: Dictionary = tables.get("spells", {})
	var cores: Array = spells.get("cores", [])
	if cores.is_empty():
		return {}
	var core: Dictionary = cores[randi() % cores.size()]
	var shells: Array = spells.get("shells", [])
	var shell: Dictionary = {}
	if not shells.is_empty():
		shell = shells[randi() % shells.size()]
	var shell_name: String = str(shell.get("name", "原生"))
	return {
		"id": "spell_part:%s:%s" % [core.get("id", ""), shell.get("id", "")],
		"name": "%s·%s" % [shell_name, core.get("name", "法术")],
		"rarity": "rare",
		"icon": str(core.get("icon", "")),
		"description": "新法术：%s（%s 外壳）" % [core.get("name", ""), shell_name],
		"tags": ["spell_part"],
	}

func add_spell_part(core_id: String, shell_id: String = "") -> void:
	## 法术碎片掉落：自动填入网格第一个空槽（DEMO 简化，保留排序机制）
	var slots: int = tables.get("balance", {}).get("max_grid_slots", 5)
	var grid: Array = run.grid
	if grid.size() < slots:
		grid.append({"core": core_id, "shell": shell_id})
		EventBus.spell_arranged.emit(grid)
		PROJECTILE_SCRIPT.clear_player_projectiles(get_tree())  # 旧法术弹道随网格变化消失

func grid_full() -> bool:
	var slots: int = tables.get("balance", {}).get("max_grid_slots", 5)
	return run.grid.size() >= slots

func replace_spell(idx: int, core_id: String, shell_id: String = "") -> void:
	## 替换指定格子为新的核心×外壳（升级三选一栏位满时使用）
	var grid: Array = run.grid
	if idx < 0 or idx >= grid.size():
		return
	grid[idx] = {"core": core_id, "shell": shell_id}
	EventBus.spell_arranged.emit(grid)
	PROJECTILE_SCRIPT.clear_player_projectiles(get_tree())  # 替换后旧弹道立即消失

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
	# 流派成型奖励叠加（F10）
	sum += float(run.get("synergy_bonus", {}).get(tag, 0.0))
	return sum

## ===== 流派成型检测（F10）=====

func detect_synergies() -> void:
	## 检测 11 条流派路线的成型条件，成型的写入 synergy_bonus 并广播提示
	var holdings := _element_holdings()
	var fire: int = int(holdings.get("fire", 0))
	var ice: int = int(holdings.get("ice", 0))
	var lightn: int = int(holdings.get("lightning", 0))
	var poison: int = int(holdings.get("poison", 0))
	var summon: int = int(holdings.get("summon", 0))
	var atk_spd: int = total_stacks("attack_speed_potion")
	var crit: int = total_stacks("crit_glasses")
	var defense: int = total_stacks("stone_armor") + total_stacks("thorn_armor") + total_stacks("thorn_reflect")
	var life: int = total_stacks("vampire_fang") + total_stacks("blood_thorn")
	var speed: int = total_stacks("speed_boots")
	var cd: int = total_stacks("wand_charge") + total_stacks("memory_haste")
	var bonus: Dictionary = run.get("synergy_bonus", {})
	var formed: Array = []
	if fire >= 2 and bonus.get("fire", 0.0) < 0.15:
		bonus["fire"] = 0.15
		formed.append("燃烧流")
	if ice >= 2 and bonus.get("ice", 0.0) < 0.20:
		bonus["ice"] = 0.20
		formed.append("冰霜流")
	if lightn >= 2 and bonus.get("lightning", 0.0) < 0.15:
		bonus["lightning"] = 0.15
		formed.append("连锁雷流")
	if poison >= 2 and bonus.get("poison", 0.0) < 0.25:
		bonus["poison"] = 0.25
		formed.append("瘟疫毒流")
	if summon >= 2 and bonus.get("summon", 0.0) < 0.25:
		bonus["summon"] = 0.25
		formed.append("召唤军团")
	if atk_spd >= 3 and bonus.get("attack_speed", 0.0) < 0.20:
		bonus["attack_speed"] = 0.20
		formed.append("狂暴攻速流")
	if crit >= 2 and bonus.get("crit_dmg", 0.0) < 0.30:
		bonus["crit_dmg"] = 0.30
		formed.append("暴击流")
	if defense >= 2 and bonus.get("defense", 0.0) < 0.05:
		bonus["defense"] = 0.05
		formed.append("磐石防御流")
	if life >= 2 and bonus.get("max_hp", 0.0) < 20.0:
		# 吸血流：不叠加吸血（克制原则），改为生命上限 +20 增强站撸容错
		bonus["max_hp"] = 20.0
		formed.append("吸血流")
	if speed >= 2 and bonus.get("attack_speed", 0.0) < 0.10:
		# 疾风流：移速联动攻速（已有 speed_boots 加成基础上再 +10% 攻速）
		bonus["attack_speed"] = maxf(bonus.get("attack_speed", 0.0), 0.10)
		formed.append("疾风流")
	if cd >= 2 and bonus.get("cooldown", 0.0) < 0.10:
		bonus["cooldown"] = 0.10
		formed.append("冷却流")
	if not formed.is_empty():
		run["synergy_bonus"] = bonus
		for name in formed:
			print("[SYNERGY] formed: ", name)
			EventBus.synergy_formed.emit(name)

## ===== 流派成型档位计数（A2，只增不改既有接口）=====

const SCHOOL_TAGS: Array = ["fire", "ice", "lightning", "poison", "summon", "water", "wind", "blade", "defense", "curse", "crit", "speed"]
const SCHOOL_NAMES: Dictionary = {
	"fire": "火",
	"ice": "冰",
	"lightning": "雷",
	"poison": "毒",
	"summon": "召唤",
	"water": "水",
	"wind": "风",
	"blade": "剑",
	"defense": "防御",
	"curse": "诅咒",
	"crit": "暴击",
	"speed": "疾速",
}

func school_holdings() -> Dictionary:
	## 流派持有数：按 items.json 的 tags 统计持有层数（道具堆叠层数 + 法术网格核心），
	## 阈值 3/6/9 由消费方（HUD 横幅 / FX 档位）自行判定，本函数只提供计数。
	var counts: Dictionary = {}
	for school in SCHOOL_TAGS:
		counts[school] = 0
	for item_id in run.items:
		var def: Dictionary = item_def(str(item_id))
		var stacks: int = int(run.items[item_id])
		for tag in def.get("tags", []):
			var key: String = str(tag)
			if counts.has(key):
				counts[key] = int(counts[key]) + stacks
	for slot in run.grid:
		var cid: String = str(slot.get("core", ""))
		for c in tables.get("spells", {}).get("cores", []):
			if str(c.get("id", "")) == cid:
				var el: String = str(c.get("element", ""))
				if counts.has(el):
					counts[el] = int(counts[el]) + 1
				break
	return counts

func schools_of_item(def: Dictionary) -> Array:
	## 道具归属流派：优先取 tags 中命中流派表的元素 tag；
	## 法术部件（spell_part）无元素 tag，按 id 解析核心元素。
	var out: Array = []
	for tag in def.get("tags", []):
		var key: String = str(tag)
		if SCHOOL_TAGS.has(key):
			out.append(key)
	if out.is_empty():
		var id: String = str(def.get("id", ""))
		if id.begins_with("spell_part:"):
			var parts: PackedStringArray = id.split(":")
			if parts.size() > 1:
				for c in tables.get("spells", {}).get("cores", []):
					if str(c.get("id", "")) == parts[1]:
						var el: String = str(c.get("element", ""))
						if SCHOOL_TAGS.has(el):
							out.append(el)
						break
	return out

func heal(amount: float) -> int:
	## 回血（含上限钳制），返回实际回复量，并通知 HUD 刷新
	if amount <= 0.0:
		return 0
	var before: int = run.hp
	run.hp = mini(run.max_hp, run.hp + int(amount))
	var healed: int = run.hp - before
	if healed > 0:
		EventBus.player_stats_changed.emit()
	return healed

func estimate_dps() -> float:
	## 估算 DPS：与 spell_caster 公式对齐——每把法杖 damage_mult/cd_mult 乘法累积，
	## shape_mods 按装备顺序覆盖 shell mods（后装优先），至少计入 shots；
	## spread_angle/orbit/aoe 等形变保持保守估算（不放大 DPS）。
	var spells: Dictionary = tables.get("spells", {})
	var atk_bonus := 1.0 + aggregate_bonus("atk")
	var speed_bonus := 1.0 + aggregate_bonus("attack_speed")
	var cd_bonus := 1.0
	var total := 0.0
	var summon_cores := 0
	# 法杖聚合：damage_mult / cd_mult 全乘法累积（与 _spell_damage / _cooldown_of 一致）
	var wand_dmg_mult := 1.0
	var wand_cd_mult := 1.0
	var wand_shape: Dictionary = {}
	for wid in current_wands():
		var wdef := wand_def(str(wid))
		if wdef.is_empty():
			continue
		wand_dmg_mult *= float(wdef.get("damage_mult", 1.0))
		wand_dmg_mult *= 1.0 + WAND_UPGRADE_BONUS * float(wand_upgrade_level(str(wid)))
		wand_cd_mult *= float(wdef.get("cd_mult", 1.0))
		for k in wdef.get("shape_mods", {}):
			wand_shape[k] = wdef["shape_mods"][k]  # 后装法杖覆盖先装（与 _cast 合并顺序一致）
	for slot in run.grid:
		var core: Dictionary = {}
		for c in spells.get("cores", []):
			if c.get("id", "") == slot.get("core", ""):
				core = c
				break
		if core.is_empty():
			continue
		if str(core.get("element", "")) == "summon":
			summon_cores += 1
			continue
		var shell: Dictionary = {}
		for s in spells.get("shells", []):
			if s.get("id", "") == slot.get("shell", ""):
				shell = s
				break
		var mods: Dictionary = shell.get("mods", {})
		var merged: Dictionary = mods.duplicate()
		for k in wand_shape:
			merged[k] = wand_shape[k]
		var dmg: float = core.get("base_damage", 0.0) * merged.get("damage_mult", 1.0) * wand_dmg_mult
		var shots: int = maxi(int(merged.get("shots", 1)), 1)
		# 冷却用 shell 原始 mods（与 _cooldown_of 传入一致），法杖 cd_mult 乘法累积
		var cd: float = core.get("cooldown", 1.0) * mods.get("cooldown_mult", 1.0) * wand_cd_mult
		cd_bonus *= item_value({"curve": {"type": "multiplicative", "base": 0.9, "cap": 0.5}}, total_stacks("wand_charge"))
		total += dmg * shots / maxf(cd, 0.1)
	# 召唤物 DPS 估算：每个召唤核心 ≈ 2 只召唤物 × 30 基础伤害 × 攻速（可被召唤书加成）
	var summon_dps := float(summon_cores) * 2.0 * 30.0 * (1.0 + total_stacks("summon_book"))
	total += summon_dps
	run.dps_estimate = total * atk_bonus * speed_bonus / cd_bonus
	return run.dps_estimate

func apply_item_effects_to_stats() -> void:
	## 把道具聚合到面板属性（HUD 读取）
	# 基础血量 + 每级成长（动作肉鸽惯例：升级提升容错）
	run.max_hp = int(balance().get("player", {}).get("hp", 100)) + 10 * (run.get("player_level", 1) - 1) \
		+ int(run.get("synergy_bonus", {}).get("max_hp", 0.0))
	# N2 无效道具修复：生命上限聚合所有 hp/max_hp tag 构筑（life_crystal +
	# defense_crystal 等），此前只读 life_crystal 单 id 导致同名道具无效
	for it in tables.get("items", {}).get("items", []):
		var tags: Array = it.get("tags", [])
		if "hp" in tags or "max_hp" in tags:
			run.max_hp += int(item_value(it, total_stacks(str(it.get("id", "")))))
	# 兜底：任何原因导致 hp 超过上限时回落（防"突破上限"类状态破坏战斗）
	if run.hp > run.max_hp:
		run.hp = run.max_hp
	run.attack_bonus = aggregate_bonus("atk")
	run.speed_bonus = aggregate_bonus("speed")
	run.attack_speed_bonus = aggregate_bonus("attack_speed")
	detect_synergies()  # 流派成型检测（F10）
	# 吸血全局上限 4%（吸血牙曲线自身封顶 3%，预留反甲吸血位）
	run.lifesteal = clampf(aggregate_bonus("lifesteal"), 0.0, 0.04)
	run.crit_chance = clampf(0.03 + 0.02 * total_stacks("crit_glasses"), 0.0, 0.85)
	run.crit_dmg_bonus = 1.5 * (1.0 + 0.10 * total_stacks("crit_gem"))
	EventBus.player_stats_changed.emit()

func balance() -> Dictionary:
	return tables.get("balance", {})

## ===== 法杖强化（N5 金币消耗端） =====

const WAND_UPGRADE_BONUS := 0.08  # 每级 +8% 伤害
const WAND_UPGRADE_BASE_COST := 200  # 首次强化价格
const WAND_UPGRADE_STEP_COST := 100  # 每级递增

func wand_upgrade_level(wand_id: String) -> int:
	return int(run.get("wand_upgrade_levels", {}).get(wand_id, 0))

func wand_upgrade_cost(wand_id: String) -> int:
	return WAND_UPGRADE_BASE_COST + WAND_UPGRADE_STEP_COST * wand_upgrade_level(wand_id)

func upgrade_wand(wand_id: String) -> bool:
	## 强化已持有法杖：+8% 伤害/级，价格 200 起每级 +100；失败返回 false
	if not current_wands().has(wand_id):
		return false
	var cost := wand_upgrade_cost(wand_id)
	if run.get("gold", 0) < cost:
		return false
	run.gold -= cost
	var levels: Dictionary = run.get("wand_upgrade_levels", {})
	levels[wand_id] = wand_upgrade_level(wand_id) + 1
	run["wand_upgrade_levels"] = levels
	EventBus.player_stats_changed.emit()
	return true
