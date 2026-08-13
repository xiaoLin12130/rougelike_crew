extends Node
## 全局游戏状态：跨场景共享的唯一数据源（数据驱动，勿硬编码数值）

const DATA_DIR := "res://data/"
const MAP_SIZE := Vector2(1280, 720)  # 关卡地图尺寸（视口 640x360，相机跟随）
const PROJECTILE_SCRIPT := preload("res://scripts/combat/projectile.gd")  # 清弹道辅助（替换/添加法术后）

var run: Dictionary = {}
var tables: Dictionary = {}  # items/spells/enemies/levels/drops/balance
var collection: Dictionary = {}  # 图鉴收集进度（跨局持久化，与 run 分离）
## 实测 DPS 滑动窗口（问题6/Mendel 方案）：5 秒窗口内实际伤害求和
const DPS_WINDOW_SEC := 5.0
var _dps_times: Array[float] = []
var _dps_amounts: Array[float] = []
var _dps_sum := 0.0

## 图鉴分类（P3）：条目来源 = data JSON 只读表，收集状态存 user://collection.json
const COLLECTION_CATEGORIES: Array = ["items", "wands", "cores", "shells", "summons"]

func _ready() -> void:
	EventBus.damage_dealt.connect(_on_damage_dealt)
	load_tables()
	load_collection()
	new_run()


func _on_damage_dealt(dmg: int, _pos: Vector2, _is_crit: bool) -> void:
	## 问题6：实测 DPS 事件写入（滑动窗口），窗口外数据惰性弹出
	if dmg <= 0:
		return
	var t: float = run.get("time", 0.0) if run.has("time") else 0.0
	_dps_times.append(t)
	_dps_amounts.append(float(dmg))
	_dps_sum += float(dmg)
	_prune_dps_window(t)


func _prune_dps_window(t: float) -> void:
	while not _dps_times.is_empty() and t - _dps_times[0] > DPS_WINDOW_SEC:
		_dps_times.pop_front()
		_dps_sum -= _dps_amounts.pop_front()


func measured_dps() -> float:
	## 问题6：实测 DPS（窗口伤害和 ÷ 窗口跨度）；冷启动不足窗口按实际跨度
	if _dps_times.is_empty():
		return 0.0
	var t: float = run.get("time", 0.0) if run.has("time") else 0.0
	var span: float = minf(t - _dps_times[0], DPS_WINDOW_SEC)
	if span <= 0.01:
		return _dps_sum
	return _dps_sum / span


func reset_dps_window() -> void:
	_dps_times.clear()
	_dps_amounts.clear()
	_dps_sum = 0.0

## ===== 图鉴收集记录（P3，只增不改既有接口）=====
## 触发点：add_item/add_trinket（道具）、add_wand/replace_wand（法杖）、
## add_spell_part/replace_spell（法术核心×外壳，召唤核心同时记召唤物）。
## 新开局 new_run 不重置收集——图鉴进度是跨局的，与局内存档分离。

func load_collection() -> void:
	## 从 user://collection.json 恢复收集档案（兼容无包装的旧格式），并规范化去重
	var data := SaveStore.load_collection()
	if data.has("categories") and data["categories"] is Dictionary:
		data = data["categories"]
	collection = {}
	for cat in COLLECTION_CATEGORIES:
		var list: Array = data.get(cat, [])
		var out: Array = []
		for v in list:
			var s := str(v)
			if not s.is_empty() and not out.has(s):
				out.append(s)
		collection[cat] = out

func mark_collected(category: String, id: String) -> void:
	## 记录一次收集（去重）；变化后立即落盘（user://collection.json）
	if not COLLECTION_CATEGORIES.has(category) or id.is_empty():
		return
	var list: Array = collection.get(category, [])
	if list.has(id):
		return
	list.append(id)
	collection[category] = list
	SaveStore.save_collection(collection)

func collection_of(category: String) -> Array:
	## 某分类已收集的 id 列表（副本，调用方修改不影响存档）
	if not COLLECTION_CATEGORIES.has(category):
		return []
	return (collection.get(category, []) as Array).duplicate()

func is_collected(category: String, id: String) -> bool:
	return collection_of(category).has(id)

func _mark_spell_parts(core_id: String, shell_id: String) -> void:
	## 法术获取统一记录：核心必记；外壳非空才记；召唤核心同时记录召唤物类型
	mark_collected("cores", core_id)
	if not shell_id.is_empty():
		mark_collected("shells", shell_id)
	for c in tables.get("spells", {}).get("cores", []):
		if str(c.get("id", "")) != core_id:
			continue
		if c.has("summon") and not str(c.get("summon", "")).is_empty():
			mark_collected("summons", str(c["summon"]))
		elif core_id.begins_with("summon_"):
			mark_collected("summons", core_id.trim_prefix("summon_"))
		break

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
	reset_dps_window()
	run = {
		"loop": 1,
		"level": 1,
		"gold": 0,
		"xp": 0,
		"player_level": 1,
		"hp": int(tables.get("balance", {}).get("player", {}).get("hp", 100)),
		"max_hp": int(tables.get("balance", {}).get("player", {}).get("hp", 100)),
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
	# 初始技能随机化（2026-08-12 需求）：开局随机 2 个「核心×外壳」技能，
	# 两个技能流派（核心 element）必须不同；外壳从该核心的有效组合池随机
	# （见 docs/design/初始技能随机方案.md）
	var starter := _roll_starter_grid()
	run.grid = starter


func _roll_starter_core_pool() -> Array:
	## 开局可选核心池：只保留至少存在一个有效外壳组合的核心
	## （frenzy/mana_echo 对所有外壳零消费/冲突，全部过滤，保证开局技能必带外壳）
	var cores: Array = tables.get("spells", {}).get("cores", [])
	var shells: Array = _active_shells(tables.get("spells", {}).get("shells", []))
	var pool: Array = []
	for c in cores:
		for s in shells:
			if not _invalid_combo(c, s):
				pool.append(c)
				break
	return pool


## ===== 自动测试流派钩子（--school / AUTOPLAY_SCHOOL，仅测试路径生效）=====
## 元素门控（未持有元素的核心不进池）是游戏机制，正常游玩保持不变；
## 此处只读与 auto_play.gd 相同的命令行/环境变量，供自动通关脚本开局/升级偏向流派。
const AUTOPLAY_SCHOOL_ALIASES := {
	"thunder": "lightning", "blade": "melee", "light": "holy",
	"void": "teleport", "nature": "wind",
}
const AUTOPLAY_SCHOOL_ELEMENTS := {
	"fire": ["fire"],
	"ice": ["ice"],
	"lightning": ["lightning"],
	"poison": ["poison"],
	"summon": ["summon"],
	"water": ["water"],
	"melee": ["blade"],
	"holy": ["light"],
	"teleport": ["void"],
}


func _autoplay_school() -> String:
	## 与 auto_play.gd 同一套流派参数：命令行 --school <name> 优先，其次 AUTOPLAY_SCHOOL 环境变量
	var school := ""
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--school" and i + 1 < args.size():
			school = str(args[i + 1]).to_lower()
	if school == "" and OS.get_environment("AUTOPLAY_SCHOOL") != "":
		school = OS.get_environment("AUTOPLAY_SCHOOL").to_lower()
	if AUTOPLAY_SCHOOL_ALIASES.has(school):
		school = AUTOPLAY_SCHOOL_ALIASES[school]
	return school


func _autoplay_school_elements() -> Array:
	## 流派 → 法术核心元素列表；未指定流派或该流派无元素映射时返回空（= 不干预）
	var school := _autoplay_school()
	if school == "" or not AUTOPLAY_SCHOOL_ELEMENTS.has(school):
		return []
	return AUTOPLAY_SCHOOL_ELEMENTS[school]


## 过滤 disabled 外壳（用户需求：移除延时/追踪外壳，数据层标 disabled: true）
static func _active_shells(all: Array) -> Array:
	var out: Array = []
	for s in all:
		if not bool(s.get("disabled", false)):
			out.append(s)
	return out


func _roll_valid_shell(core: Dictionary) -> Dictionary:
	## 从指定核心的有效外壳池随机抽 1 个（无有效组合时返回空字典=原生）
	var shells: Array = _active_shells(tables.get("spells", {}).get("shells", []))
	var valid: Array = []
	for s in shells:
		if not _invalid_combo(core, s):
			valid.append(s)
	if valid.is_empty():
		return {}
	return valid[randi() % valid.size()]


func _roll_starter_grid() -> Array:
	## 开局技能：核心1（流派A）→ 核心2（流派B != A），各配有效随机外壳
	## 自动测试钩子：--school / AUTOPLAY_SCHOOL 指定流派时，核心1偏向该流派元素（若有该元素核心）
	var pool: Array = _roll_starter_core_pool()
	if pool.is_empty():
		return []
	var core_a: Dictionary
	var el_a: String
	var school_els := _autoplay_school_elements()
	if not school_els.is_empty():
		var school_pool: Array = []
		for c in pool:
			if str(c.get("element", "")) in school_els:
				school_pool.append(c)
		if school_pool.is_empty():
			core_a = pool[randi() % pool.size()]
		else:
			core_a = school_pool[randi() % school_pool.size()]
	else:
		core_a = pool[randi() % pool.size()]
	el_a = str(core_a.get("element", ""))
	var pool_b: Array = []
	for c in pool:
		if str(c.get("element", "")) != el_a:
			pool_b.append(c)
	var core_b: Dictionary
	if pool_b.is_empty():
		core_b = pool[randi() % pool.size()]  # 防御兜底（11 种 element 下不会发生）
	else:
		core_b = pool_b[randi() % pool_b.size()]
	return [
		{"core": str(core_a.get("id", "")), "shell": str(_roll_valid_shell(core_a).get("id", ""))},
		{"core": str(core_b.get("id", "")), "shell": str(_roll_valid_shell(core_b).get("id", ""))},
	]

func add_item(item_id: String) -> void:
	run.items[item_id] = run.items.get(item_id, 0) + 1
	run.last_picked = item_id  # 物品栏"最近获得"高亮
	mark_collected("items", item_id)  # 图鉴：获得道具即记录（P3）
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
		SfxBus.play_hit("upgrade")  # 打击感 G-1：升级确认音
		# 升级短暂无敌（体验优化）：1.2s 无敌帧 + 回满血，避免升级瞬间被围殴秒杀
		var p := get_tree().get_first_node_in_group("player")
		if is_instance_valid(p) and p.has_method("grant_invuln"):
			p.call("grant_invuln", 1.2)
		run.hp = run.max_hp
	EventBus.player_stats_changed.emit()

func xp_to_next(level: int) -> int:
	# 平滑升级曲线（2026-08-12）：全等级统一走 balance.json xp 公式。
	# 移除 L1-3 硬编码加速分支（30/55/90）——玩家反馈前期升级过快；
	# 新曲线 38+30(L-1)+5(L-1)²：L1=38 → L2=73 → L3=118（详见 docs/design/升级曲线平滑调整.md）
	var l := maxi(level, 1)
	var xp: Dictionary = balance().get("xp", {})
	return int(xp.get("base", 50)) + int(xp.get("per_level", 30)) * (l - 1) \
		+ int(xp.get("quad", 5)) * (l - 1) * (l - 1)
func level_factor(level: int) -> float:
	## 难度曲线（问题11：前期不变、后期加速）：1-3 关维持 base^（level-1），
	## 4 关起额外阶梯加速 ×1.30/关（敌人更强，避免后期站撸无压力）
	var base: float = float(tables.get("balance", {}).get("enemy_scaling", {}).get("level_hp", 1.22))
	var v: float = pow(base, maxi(level - 1, 0))
	if level > 3:
		v *= pow(1.30, level - 3)
	return v

func loop_factor_hp(loop: int) -> float:
	return pow(1.34, loop - 1)

func loop_factor_dmg(loop: int) -> float:
	return pow(1.24, loop - 1)

func loop_factor_num(loop: int) -> float:
	return pow(1.25, loop - 1)

func enemy_hp(base: float, level: int, loop: int) -> float:
	return base * level_factor(level) * loop_factor_hp(loop)

func enemy_atk(base: float, level: int, loop: int) -> float:
	## 攻击同样后期加速（问题11：4 关起每关 +8% 额外攻击成长）
	var atk_growth: float = float(tables.get("balance", {}).get("enemy_scaling", {}).get("level_atk", 0.16))
	var v: float = base * (1.0 + atk_growth * (level - 1))
	if level > 3:
		v *= pow(1.08, level - 3)
	return v * loop_factor_dmg(loop)

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


func spell_core_element(core_id: String) -> String:
	## 查询法术核心元素（拾取特效取色用）；未知名返回空
	for c in tables.get("spells", {}).get("cores", []):
		if str(c.get("id", "")) == core_id:
			return str(c.get("element", ""))
	return ""

func roll_item_choices(count: int = 3) -> Array:
	## 升级三选一：混合法术部件与数值道具（用户需求：三选一既有技能又有物品）
	## 网格未满时必含 1 个法术部件，其余为道具；整体洗牌保证顺序随机
	## 元素权重倾向（F9）：持有某元素越多，该元素选项出现概率越高
	## 公式：权重 = 基础 × (1 + 0.02 × 持有件数 × 关卡系数)，总提升上限 +60%；
	## 非主流元素保底：若存在非主流元素池，至少 1 个选项来自其中
	var choices: Array = []
	var pool: Array = tables.get("items", {}).get("items", []).duplicate()
	# 批次A（2026-08-13）：排除 disabled 道具（无效/未接线，防御性过滤防未来数据回归）
	# 与 type=trinket 饰品（饰品走独立掉落/商店渠道；升级三选一选中会 add_item 进
	# run.items，而效果读取 run.trinkets → 空抽，见 docs/design/批次A审计中间态.md）。
	var playable: Array = []
	for it in pool:
		if bool(it.get("disabled", false)) or str(it.get("type", "item")) == "trinket":
			continue
		playable.append(it)
	pool = playable
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
	# 主流派保底池（2026-08-10）：持有 ≥3 件某流派时，选项池至少 1 个来自该流派
	var main_pool: Array = []
	var main_n := int(holdings.get(main_el, 0)) if main_el != "" else 0
	if main_el != "" and main_n >= 3:
		for it in pool:
			if _element_key(it) == main_el:
				main_pool.append(it)
	var spell_choice := _make_spell_choice()
	if not spell_choice.is_empty():
		choices.append(spell_choice)
	# 保底：choices 中尚无主流派选项时，从主流派池取 1 个
	if main_n >= 3 and not main_pool.is_empty() and choices.size() < count:
		var has_main := false
		for ch in choices:
			if _element_key(ch) == main_el:
				has_main = true
				break
		if not has_main:
			var pick = main_pool[randi() % main_pool.size()]
			choices.append(pick)
			pool.erase(pick)
			main_pool.erase(pick)
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
	## 当前构筑的流派持有件数：道具堆叠数 + 法术网格核心数。
	## _element_key 只认元素 tag（fire/ice/.../blade）；wind/holy/curse/defense 为
	## 纯 tag 流派，在此按 tags 补计（供 detect_synergies 12 流派检测；不影响
	## roll_item_choices 的 _element_key 过滤/权重路径）。
	var counts := {}
	for item_id in run.items:
		var def: Dictionary = item_def(item_id)
		var el := _element_key(def)
		if el != "":
			counts[el] = counts.get(el, 0) + int(run.items[item_id])
			continue
		for tag in def.get("tags", []):
			var key: String = str(tag)
			if key == "wind" or key == "holy" or key == "curse" or key == "defense":
				counts[key] = counts.get(key, 0) + int(run.items[item_id])
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
			# 2026-08-12 平衡调整：同流派权重加成降至原来的 1/3（+10%→+3.33%/件/关，
			# 上限 +150%→+50%），防止"拿得越多越容易拿"的马太效应过强；主流派保底保留。
			w *= minf(1.0 + 0.0333 * float(n) * lv_factor, 1.5)
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


func max_wand_slots() -> int:
	## 问题14：法杖槽上限 = 3 + 法杖扩容卷轴（传说饰品，最多 1 件生效）
	var extra := 0
	for t in run.get("trinkets", []):
		if str(t) == "wand_expander":
			extra = 1
			break
	return 3 + extra

func current_wand() -> Dictionary:
	## 主法杖（第一把）：旧接口兼容（新 UI 用 current_wands）
	var ids := current_wands()
	if ids.is_empty():
		return {}
	return wand_def(str(ids[0]))

func add_wand(wand_id: String) -> void:
	## 装备新法杖（上限 max_wand_slots 把，超过需要先替换）
	var ids: Array = current_wands()
	if ids.size() >= max_wand_slots():
		return
	ids.append(wand_id)
	run["wands"] = ids
	mark_collected("wands", wand_id)  # 图鉴：获得法杖即记录（P3）
	EventBus.player_stats_changed.emit()

func replace_wand(idx: int, wand_id: String) -> void:
	## 替换指定槽位的法杖（购买时满 3 把使用）
	var ids: Array = current_wands()
	if idx < 0 or idx >= ids.size():
		return
	ids[idx] = wand_id
	run["wands"] = ids
	mark_collected("wands", wand_id)  # 图鉴：替换获得的新法杖同样记录（P3）
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
	## 落雷误触发修复（Beauvoir P1）：无某元素构筑时不出该元素法术（与 N2 物品过滤对齐）。
	## 落地加固：先按 holdings 预过滤核心池——未持有元素的核心不进生成池（blade 通用保留），
	## 杜绝"8 次重抽全失败后回退随机核心"仍可能漏出未持有元素法术的路径。
	## 组合有效性过滤（docs/design/核心外壳组合审计.md 修复）：随机 core×shell 后经
	## _invalid_combo 校验，无效组合重抽（最多 8 次防死循环）；仍无有效组合时退化为
	## "原生"（无外壳）——生成池绝不出现"选了没效果"的组合。
	var spells: Dictionary = tables.get("spells", {})
	var cores: Array = spells.get("cores", [])
	if cores.is_empty():
		return {}
	var shells: Array = _active_shells(spells.get("shells", []))
	var holdings := _element_holdings()
	## 元素门控：核心池 = 无元素核心 + 通用 blade + 已持有元素核心；空池直接返回空（不给选项）
	var eligible: Array = []
	for c in cores:
		var el := str(c.get("element", ""))
		if el == "" or el == "blade" or holdings.has(el):
			eligible.append(c)
	if eligible.is_empty():
		return {}
	## 自动测试钩子：--school / AUTOPLAY_SCHOOL 指定流派时，本流派元素核心权重 ×3
	## （门控池规则不变——流派元素由开局偏向保证已持有；正常游玩无参数时行为与原来完全一致）
	var school_els := _autoplay_school_elements()
	var weighted: Array = eligible
	if not school_els.is_empty():
		weighted = []
		for c in eligible:
			weighted.append(c)
			if str(c.get("element", "")) in school_els:
				weighted.append(c)
				weighted.append(c)
	var core: Dictionary = {}
	var shell: Dictionary = {}
	for _attempt in 8:
		core = weighted[randi() % weighted.size()]
		if shells.is_empty():
			shell = {}
			break
		shell = shells[randi() % shells.size()]
		if not _invalid_combo(core, shell):
			break
		shell = {}
	if not shell.is_empty() and _invalid_combo(core, shell):
		shell = {}
	var shell_name: String = str(shell.get("name", "原生"))
	return {
		"id": "spell_part:%s:%s" % [core.get("id", ""), shell.get("id", "")],
		"name": "%s·%s" % [shell_name, core.get("name", "法术")],
		"rarity": "rare",
		"icon": str(core.get("icon", "")),
		"description": "新法术：%s（%s 外壳）" % [core.get("name", ""), shell_name],
		"tags": ["spell_part"],
	}


## 组合有效性判定（核心外壳组合审计 25 条修复的过滤矩阵）：
## 语义冲突 / 外壳 mods 零消费 / 负收益组合一律不进生成池（宁可"原生"也不出无效组合）。
##  - 狂暴/回响（问题20/21）：外壳对二者零消费（狂暴连 damage_mult 都不读），全部过滤；
##  - 传送/反制/圣光（问题19）：仅保留爆发（aoe_mult 已接线半径）/延时（正乘区）/吸血（已接线回血），
##    其余 7 个外壳仅剩负向乘区 → 过滤；
##  - 召唤（问题18）：连发=多召语义保留；其余 damage_mult<1 且无主体语义的外壳 → 过滤；
##  - 旋风刃（问题12/13/16）：环绕（orbit 被核心强制覆盖 4.0）/分裂（1px/s 小弹 bug）/
##    追踪/穿透/弹射（轨道路径零消费）→ 过滤；
##  - 瞬发核 speed<=0（问题6/8/9）：追踪/穿透/弹射/环绕零消费 → 过滤。
func _invalid_combo(core: Dictionary, shell: Dictionary) -> bool:
	if shell.is_empty():
		return false
	var cid := str(core.get("id", ""))
	var sid := str(shell.get("id", ""))
	var mods: Dictionary = shell.get("mods", {})
	if core.get("frenzy", false) or core.get("mana_echo", false):
		return true
	if core.get("teleport", false) or core.get("counter", false) or core.get("bless", false):
		return sid != "burst" and sid != "delay" and sid != "drain"
	if core.has("summon") or cid == "summon_bat":
		if sid == "rapid":
			return false
		return float(mods.get("damage_mult", 1.0)) < 1.0
	if cid == "whirl_blade":
		return sid == "orbit" or sid == "split" or sid == "homing" \
			or sid == "pierce" or sid == "bounce"
	if float(core.get("speed", 0.0)) <= 0.0:
		return mods.has("homing") or mods.has("pierce") or mods.has("bounce") or mods.has("orbit")
	return false

func add_spell_part(core_id: String, shell_id: String = "") -> void:
	## 法术碎片掉落：自动填入网格第一个空槽（DEMO 简化，保留排序机制）
	_mark_spell_parts(core_id, shell_id)  # 图鉴：获得法术部件即记录（P3）
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
	_mark_spell_parts(core_id, shell_id)  # 图鉴：替换获得的新法术同样记录（P3）
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
	mark_collected("items", trinket_id)  # 图鉴：饰品也属装备条目（P3）
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


func _tag_stacks(tag: String) -> int:
	## 按 tag 统计持有堆叠数（去硬编码辅助：detect_synergies 数值路线读持有数用）
	var total := 0
	for item_id in run.items:
		var def: Dictionary = item_def(str(item_id))
		if not def.is_empty() and tag in def.get("tags", []):
			total += int(run.items[item_id])
	return total


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

## ===== 攻速展示换算（F 批，只读查询，2026-08-10）=====

## 攻速流派贡献读取点（与 spell_caster._SYNERGY_AS_KEYS / melee_attack 同步维护）：
## 运行时总攻速 = 基础聚合 run.attack_speed_bonus（apply_item_effects_to_stats 写入）
## + 下列键求和；施法冷却与近战攻击间隔均按 1/(1+总攻速) 计算。
const AS_SYNERGY_KEYS := [
	"fire_m2_atk_speed",   ## 火M2 薪火相传
	"melee_m3_as_bonus",   ## 近M3 血之狂暴
	"melee_m9_as_bonus",   ## 近M9 狂化
	"wind_as_bonus",       ## 移2/移5 移速→攻速联动
	"wind_m2_atk_speed",   ## 移M2 踏风
	"wind_m10_as_bonus",   ## 移M10 暴走
]

func total_attack_speed_bonus() -> float:
	## 总攻速加成（小数，0.5 = 50%），与 spell_caster._total_attack_speed 同口径。
	## 未聚合时（新局/测试）回退道具聚合，保证显示值与运行时一致。
	var base: float = float(run.get("attack_speed_bonus", -1.0))
	if base < 0.0:
		base = aggregate_bonus("attack_speed")
	var total := maxf(base, 0.0)
	for key in AS_SYNERGY_KEYS:
		total += maxf(float(run.get(key, 0.0)), 0.0)
	return total

func attack_speed_pct() -> int:
	## 攻速加成百分比（0/50/100…），供 HUD/卡片/面板展示。
	return int(round(total_attack_speed_bonus() * 100.0))

func attack_speed_cd_reduction_pct(as_bonus: float = -1.0) -> int:
	## 攻速 → 施法冷却/攻击间隔缩短百分比：cd_mult = 1/(1+as)，缩短 = 1 - 1/(1+as)。
	## 不传参时按当前总攻速换算；传入数值可预览（如升级卡片）。
	var as_total := total_attack_speed_bonus() if as_bonus < 0.0 else maxf(as_bonus, 0.0)
	return int(round((1.0 - 1.0 / (1.0 + as_total)) * 100.0))

func attack_speed_summary() -> String:
	## 直白文案："攻速 +50%：施法更快，冷却缩短 33%"（构筑面板统计区用）。
	var pct := attack_speed_pct()
	var cd := attack_speed_cd_reduction_pct()
	return "攻速 +%d%%：施法更快，冷却缩短 %d%%" % [pct, cd]

## ===== 流派成型检测（F10）=====

func detect_synergies() -> void:
	## 检测 12 流派路线（fire/ice/lightning/poison/summon/water/wind/holy/curse/
	## melee/defense/teleport）的成型条件，成型的写入 synergy_bonus 并广播提示。
	## 持有数统一从 _element_holdings() 读取（元素 tag + 纯 tag 流派 + 核心元素），
	## 不写死任何道具 id；攻速/暴击/吸血/移速/冷却五条数值路线按 tag 统计。
	var holdings := _element_holdings()
	# 元素别名 → 流派规范键（nature=荆棘藤蔓等风系核心；light=圣光核心；void=传送核心）
	var wind: int = int(holdings.get("wind", 0)) + int(holdings.get("nature", 0))
	var holy: int = int(holdings.get("holy", 0)) + int(holdings.get("light", 0))
	var melee: int = int(holdings.get("blade", 0))
	var teleport: int = int(holdings.get("void", 0))
	var fire: int = int(holdings.get("fire", 0))
	var ice: int = int(holdings.get("ice", 0))
	var lightn: int = int(holdings.get("lightning", 0))
	var poison: int = int(holdings.get("poison", 0))
	var summon: int = int(holdings.get("summon", 0))
	var water: int = int(holdings.get("water", 0))
	var curse: int = int(holdings.get("curse", 0))
	var defense: int = int(holdings.get("defense", 0))
	# 数值路线：按 tag 统计（原硬编码 id 读取点去硬编码，阈值/bonus 语义不变）
	var atk_spd: int = _tag_stacks("attack_speed")
	var crit: int = _tag_stacks("crit")
	var life: int = _tag_stacks("lifesteal")
	var speed: int = _tag_stacks("speed")
	var cd: int = _tag_stacks("cooldown") + _tag_stacks("skill_cd")
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
	if water >= 2 and bonus.get("water", 0.0) < 0.15:
		bonus["water"] = 0.15
		formed.append("水控流")
	if wind >= 2 and bonus.get("wind", 0.0) < 0.10:
		bonus["wind"] = 0.10
		formed.append("追风流")
	if holy >= 2 and bonus.get("holy", 0.0) < 0.15:
		bonus["holy"] = 0.15
		formed.append("圣光流")
	if curse >= 2 and bonus.get("curse", 0.0) < 0.15:
		bonus["curse"] = 0.15
		formed.append("诅咒流")
	if melee >= 2 and bonus.get("melee", 0.0) < 0.20:
		bonus["melee"] = 0.20
		formed.append("近战流")
	if defense >= 2 and bonus.get("defense", 0.0) < 0.05:
		bonus["defense"] = 0.05
		formed.append("磐石防御流")
	if teleport >= 2 and bonus.get("teleport", 0.0) < 0.15:
		bonus["teleport"] = 0.15
		formed.append("传送流")
	if atk_spd >= 3 and bonus.get("attack_speed", 0.0) < 0.20:
		bonus["attack_speed"] = 0.20
		formed.append("狂暴攻速流")
	if life >= 2 and bonus.get("max_hp", 0.0) < 20.0:
		# 吸血流：不叠加吸血（克制原则），改为生命上限 +20 增强站撸容错
		bonus["max_hp"] = 20.0
		formed.append("吸血流")
	if speed >= 2 and bonus.get("attack_speed", 0.0) < 0.10:
		# 疾风流：移速联动攻速（已有 speed 加成基础上再 +10% 攻速）
		bonus["attack_speed"] = maxf(bonus.get("attack_speed", 0.0), 0.10)
		formed.append("疾风流")
	if cd >= 2 and bonus.get("cooldown", 0.0) < 0.10:
		bonus["cooldown"] = 0.10
		formed.append("冷却流")
	if crit >= 2 and bonus.get("crit_dmg", 0.0) < 0.30:
		bonus["crit_dmg"] = 0.30
		formed.append("暴击流")
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
	## 估算 DPS：与 spell_caster._spell_damage / _cooldown_of / _cast 及
	## projectile._hit_enemy 的实际伤害公式对齐（2026-08-13 修复"理论 100 vs 实际 1 万"）：
	## ① 伤害乘数补齐：atk / skill_dmg / 元素加成 / 法杖 damage_mult×升级×元素加成；
	## ② 冷却乘数补齐：攻速 1/(1+as)、cooldown+skill_cd 减冷却、法杖 cd_mult、充能曲线、
	##    风系 wind_cd_mult（与 _cooldown_of 逐项一致，去掉旧"每槽乘一次再整体除"的错误）；
	## ③ shots 用 shell+法杖合并后的值并计入 wind_m4_shots；
	## ④ 暴击期望 = 1 + crit_chance×(crit_dmg-1)（与 apply_item_effects_to_stats 同公式）；
	## ⑤ 群战放大（保守封顶 ×3.5）：AOE 半径 / 闪电链 / 穿透 / 分裂 / 弹射；
	## ⑥ 召唤物按 data/summons.json 的类型 max_count / skill_cd / damage_mult 折算。
	## 估算目标：与实际输出同一数量级（晚局实际 1 万+，理论数千），不追求逐帧精确。
	var spells: Dictionary = tables.get("spells", {})
	var total := 0.0
	## ---- 全局乘数（与 spell_caster 同口径）----
	var atk_mult := 1.0 + aggregate_bonus("atk")
	var skill_mult := 1.0 + aggregate_bonus("skill_dmg")
	var as_total := total_attack_speed_bonus()  # 含 synergy 攻速读点（与 _total_attack_speed 一致）
	var as_cd_mult := 1.0 / (1.0 + as_total)
	var cd_reduce := clampf(aggregate_bonus("cooldown") + aggregate_bonus("skill_cd"), 0.0, 0.8)
	var wind_cd_mult := maxf(float(run.get("wind_cd_mult", 1.0)), 0.0)
	var wand_charge_mult := item_value({"curve": {"type": "multiplicative", "base": 0.9, "cap": 0.5}},
		total_stacks("wand_charge"))
	# 暴击期望（apply_item_effects_to_stats 同公式；lucky/风系/元素系附加暴击保守不计）
	var crit_chance := clampf(0.03 + 0.02 * float(total_stacks("crit_glasses")), 0.0, 0.85)
	var crit_dmg := 1.5 * (1.0 + 0.10 * float(total_stacks("crit_gem"))) \
		+ float(run.get("synergy_bonus", {}).get("crit_dmg", 0.0))
	var crit_mult := 1.0 + crit_chance * (crit_dmg - 1.0)
	## ---- 法杖聚合（与 _spell_damage / _cooldown_of 的逐杖循环一致）----
	var wand_dmg_mult := 1.0
	var wand_cd_mult := 1.0
	var wand_element_bonus: Dictionary = {}  # element -> Π(1+eb_i)
	var wand_shape: Dictionary = {}
	for wid in current_wands():
		var wdef := wand_def(str(wid))
		if wdef.is_empty():
			continue
		wand_dmg_mult *= float(wdef.get("damage_mult", 1.0))
		wand_cd_mult *= float(wdef.get("cd_mult", 1.0))
		var eb: Dictionary = wdef.get("element_bonus", {})
		for el in eb:
			wand_element_bonus[el] = float(wand_element_bonus.get(el, 1.0)) * (1.0 + float(eb[el]))
		for k in wdef.get("shape_mods", {}):
			wand_shape[k] = wdef["shape_mods"][k]  # 后装法杖覆盖先装（与 _cast 合并顺序一致）
	var wand_upgrade_mult := 1.0
	for wid in current_wands():
		wand_upgrade_mult *= 1.0 + WAND_UPGRADE_BONUS * float(wand_upgrade_level(str(wid)))
	## ---- 索引：core_id / shell_id / summon_id -> 定义（网格循环 O(1)）----
	var core_by_id := {}
	for c in spells.get("cores", []):
		var cid := str(c.get("id", ""))
		if not core_by_id.has(cid):
			core_by_id[cid] = c
	var shell_by_id := {}
	for s in spells.get("shells", []):
		var sid := str(s.get("id", ""))
		if not shell_by_id.has(sid):
			shell_by_id[sid] = s
	var summon_defs := {}
	for s in tables.get("summons", {}).get("summons", []):
		var sid := str(s.get("id", ""))
		if not summon_defs.has(sid):
			summon_defs[sid] = s
	var frenzy := false
	var summon_slots: Array = []
	for slot in run.grid:
		var core: Dictionary = core_by_id.get(str(slot.get("core", "")), {})
		if core.is_empty():
			continue
		if core.get("frenzy", false):
			frenzy = true
			continue
		if core.get("mana_echo", false):
			continue  # 纯功能核（重置冷却），无直接输出
		var tid := str(core.get("summon", ""))
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
		## 单发伤害 = base × damage_mult × (1+atk) × (1+skill_dmg) × (1+元素) × 法杖聚合
		var dmg: float = float(core.get("base_damage", 0.0)) \
			* float(merged.get("damage_mult", 1.0)) \
			* atk_mult * skill_mult \
			* (1.0 + aggregate_bonus(element)) \
			* float(wand_element_bonus.get(element, 1.0)) \
			* wand_dmg_mult * wand_upgrade_mult
		var shots: int = maxi(int(merged.get("shots", 1)), 1) \
			+ maxi(int(run.get("wind_m4_shots", 0)), 0)
		## 有效冷却 = core.cd × shell.cd_mult × 法杖 cd_mult × 充能 × 攻速 × 风系 × (1-减cd)
		var cd: float = float(core.get("cooldown", 1.0)) \
			* float(mods.get("cooldown_mult", 1.0)) \
			* wand_cd_mult * wand_charge_mult \
			* as_cd_mult * wind_cd_mult * (1.0 - cd_reduce)
		cd = maxf(cd, 0.05)
		## 群战放大（保守）：AOE 半径 / 闪电链 / 穿透 / 分裂 / 弹射，封顶 ×3.5
		var multihit := 1.0
		var chain := int(core.get("chain", 0))
		if chain > 0:
			multihit *= 1.0 + float(chain) * 0.7
		var pierce := int(merged.get("pierce", 0))
		if pierce > 0:
			multihit *= 1.0 + float(pierce) * 0.6
		var split := int(merged.get("split", 0))
		if split > 0:
			multihit *= 1.0 + float(split) * 0.6
		var bounce := int(merged.get("bounce", 0))
		if bounce > 0:
			multihit *= 1.0 + float(bounce) * 0.35
		var aoe_r := float(core.get("aoe", 0.0)) * float(merged.get("aoe_mult", 1.0)) \
			* (1.0 + aggregate_bonus("area"))
		if aoe_r <= 0.0 and float(core.get("blind", 0.0)) > 0.0:
			aoe_r = 90.0 * float(merged.get("aoe_mult", 1.0))
		if aoe_r > 0.0:
			multihit *= 1.0 + minf(aoe_r / 35.0, 1.0)
		multihit = minf(multihit, 3.5)
		total += dmg * float(shots) / cd * crit_mult * multihit
	## 召唤物：到场总数 = min(总上限 1+summon_1, Σ各类型 max_count)；
	## 单次命中 = 核心 base_damage × 外壳 damage_mult × 类型 damage_mult × 面板乘数
	if not summon_slots.is_empty():
		var summon_cap := 1 + total_stacks("summon_1")
		var max_sum := 0
		var per_hit_w := 0.0
		var cd_w := 0.0
		for entry in summon_slots:
			var sdef: Dictionary = summon_defs.get(str(entry.get("tid", "")), {})
			if sdef.is_empty():
				continue
			var mc := int(sdef.get("max_count", 1))
			max_sum += mc
			var per_hit: float = float(entry.get("core", {}).get("base_damage", 30.0)) \
				* float(entry.get("shell", {}).get("mods", {}).get("damage_mult", 1.0)) \
				* float(sdef.get("damage_mult", 1.0)) \
				* atk_mult * skill_mult \
				* (1.0 + aggregate_bonus("summon")) \
				* float(wand_element_bonus.get("summon", 1.0)) \
				* wand_dmg_mult * wand_upgrade_mult
			per_hit_w += per_hit * float(mc)
			cd_w += maxf(float(sdef.get("skill_cd", 1.0)), 0.5) * float(mc)
		if cd_w > 0.0:
			var alive := mini(max_sum, summon_cap)
			total += float(alive) * per_hit_w / cd_w * crit_mult
	## 狂暴核：3s/6s ≈ 50% 覆盖 × 1.3 伤害 × 冷却减半 → 净约 ×1.7（保守常数）
	if frenzy:
		total *= 1.7
	run.dps_estimate = total
	return run.dps_estimate

## 性能优化（批次B）：items_by_tag 索引缓存（tag → 道具列表）。
## apply_item_effects_to_stats 每次刷新只遍历命中 tag 的道具，不再全表线性扫描查 tag；
## items 表仅在 _ready 加载一次，缓存以源数组引用做失效（源被替换时自动重建），
## 语义与旧行为一致（双 tag 道具在累计处按 id 去重只加一次）。
var _items_by_tag: Dictionary = {}   # tag -> Array[Dictionary]
var _items_by_tag_src: Array = []    # 索引对应的 items 源数组引用（失效哨兵）

func _items_with_tag(tag: String) -> Array:
	## 惰性构建 items_by_tag；源数组引用变化（tables 重载）时自动重建。
	var src: Array = tables.get("items", {}).get("items", [])
	if _items_by_tag_src != src:
		_items_by_tag = {}
		for it in src:
			for t in it.get("tags", []):
				var key := str(t)
				if not _items_by_tag.has(key):
					_items_by_tag[key] = []
				(_items_by_tag[key] as Array).append(it)
		_items_by_tag_src = src
	return _items_by_tag.get(tag, [])

func apply_item_effects_to_stats() -> void:
	## 把道具聚合到面板属性（HUD 读取）
	# 基础血量 + 每级成长（动作肉鸽惯例：升级提升容错）
	run.max_hp = int(balance().get("player", {}).get("hp", 100)) + 10 * (run.get("player_level", 1) - 1) \
		+ int(run.get("synergy_bonus", {}).get("max_hp", 0.0))
	# N2 无效道具修复：生命上限聚合所有 hp/max_hp tag 构筑（life_crystal +
	# defense_crystal 等），此前只读 life_crystal 单 id 导致同名道具无效
	# 批次B优化：经 items_by_tag 索引取命中道具（双 tag 道具按 id 去重，累计一次）
	var hp_items: Array = _items_with_tag("hp")
	var maxhp_items: Array = _items_with_tag("max_hp")
	var seen := {}
	for it in hp_items + maxhp_items:
		var key := str(it.get("id", ""))
		if seen.has(key):
			continue
		seen[key] = true
		run.max_hp += int(item_value(it, total_stacks(key)))
	# 兜底：任何原因导致 hp 超过上限时回落（防"突破上限"类状态破坏战斗）
	if run.hp > run.max_hp:
		run.hp = run.max_hp
	run.attack_bonus = aggregate_bonus("atk")
	run.speed_bonus = aggregate_bonus("speed")
	run.attack_speed_bonus = aggregate_bonus("attack_speed")
	detect_synergies()  # 流派成型检测（F10）
	# 吸血全局上限 3%（balance.json lifesteal.cap，2026-08-10 平衡调整；吸血牙曲线自身封顶 3%）
	run.lifesteal = clampf(aggregate_bonus("lifesteal"), 0.0, float(balance().get("lifesteal", {}).get("cap", 0.03)))
	run.crit_chance = clampf(0.03 + 0.02 * total_stacks("crit_glasses"), 0.0, 0.85)
	run.crit_dmg_bonus = 1.5 * (1.0 + 0.10 * total_stacks("crit_gem"))
	EventBus.player_stats_changed.emit()

func balance() -> Dictionary:
	return tables.get("balance", {})

## ===== 法杖强化（N5 金币消耗端） =====

const WAND_UPGRADE_BONUS := 0.08  # 每级 +8% 伤害
const WAND_UPGRADE_BASE_COST := 250  # 首次强化价格（2026-08-10 平衡调整 200→250）
const WAND_UPGRADE_STEP_COST := 100  # 每级递增

func wand_upgrade_level(wand_id: String) -> int:
	return int(run.get("wand_upgrade_levels", {}).get(wand_id, 0))

func wand_upgrade_cost(wand_id: String) -> int:
	return WAND_UPGRADE_BASE_COST + WAND_UPGRADE_STEP_COST * wand_upgrade_level(wand_id)

func upgrade_wand(wand_id: String) -> bool:
	## 强化已持有法杖：+8% 伤害/级，价格 250 起每级 +100；失败返回 false
	if not current_wands().has(wand_id):
		return false
	var cost := wand_upgrade_cost(wand_id)
	if run.get("gold", 0) < cost:
		return false
	run.gold -= cost
	SfxBus.play_hit("buy")  # 打击感 G-1：购买音
	var levels: Dictionary = run.get("wand_upgrade_levels", {})
	levels[wand_id] = wand_upgrade_level(wand_id) + 1
	run["wand_upgrade_levels"] = levels
	EventBus.player_stats_changed.emit()
	return true

## ===== 敌人常驻缓存（P0 性能优化，2026-08-10）=====
## 背景：get_nodes_in_group("enemy") 在 synergy 钩子/combat 读取点高频调用
## （20+ 文件，每帧/每钩子），每次调用都会构建新数组。改为常驻数组缓存：
## enemy.gd 入树（_ready）注册、出树（_exit_tree）注销，查询走 get_enemies()。
## 语义保证：
## - 缓存非空时与组 "enemy" 当前成员一致（全部敌人/Boss 均为 EnemyBase，统一注册）；
## - 缓存为空时回退组查询，与旧行为完全一致（兼容测试中用 add_to_group 的假敌人）；
## - 敌人死亡帧（_die → queue_free，tree_exiting 帧末触发）缓存仍含该敌人，
##   与 get_nodes_in_group 行为一致；遍历处保留 is_instance_valid 检查即可。
## 并发安全：注册走挂起队列、注销只置脏标记，查询时统一合并/压缩（整体重建数组，
## 不改原数组对象），任何遍历中触发注册/注销/嵌套查询都不会报"数组遍历中被修改"。
## 调用方约定：get_enemies() 返回内部数组，只读遍历，不得增删元素。

## 类型化 Array[Node]：与 get_nodes_in_group 返回类型一致，遍历元素为 Node，
## 保证 `var id := e.get_instance_id()` 等类型推断与旧代码完全一致。
var _enemy_cache: Array[Node] = []           # 常驻敌人列表（缓存）
var _enemy_cache_pending: Array[Node] = []   # 入树注册挂起（查询时合并，避免遍历中追加）
var _enemy_cache_dirty := false              # 有出树注销待压缩（查询时剔除失效条目）

func register_enemy(e: Node) -> void:
	## 敌人入树注册（enemy.gd _ready 调用；Boss 继承 EnemyBase 自动注册）
	if _enemy_cache.has(e) or _enemy_cache_pending.has(e):
		return
	_enemy_cache_pending.append(e)

func unregister_enemy(e: Node) -> void:
	## 敌人出树注销（enemy.gd _exit_tree 调用；切关/场景切换随树退出自动清理）
	# Array.erase 返回 void（不可作 if 条件）：先 has 再 erase，语义不变（P0 缓存工作区解阻塞）
	if _enemy_cache_pending.has(e):
		_enemy_cache_pending.erase(e)
		return
	if _enemy_cache.has(e):
		_enemy_cache_dirty = true

func get_enemies() -> Array[Node]:
	## 常驻敌人缓存查询（只读遍历约定）。返回内部数组，调用方不得增删元素。
	if not _enemy_cache_pending.is_empty():
		# 整体重建（duplicate + 追加），不就地修改旧数组对象：
		# 遍历期间发生注册/嵌套查询不会报"数组遍历中被修改"
		var merged: Array[Node] = _enemy_cache.duplicate()
		for e in _enemy_cache_pending:
			merged.append(e)
		_enemy_cache = merged
		_enemy_cache_pending.clear()
	if _enemy_cache_dirty:
		var keep: Array[Node] = []
		for e in _enemy_cache:
			if is_instance_valid(e) and e.is_inside_tree():
				keep.append(e)
		_enemy_cache = keep
		_enemy_cache_dirty = false
	if _enemy_cache.is_empty():
		# 缓存为空时回退组查询：保证与旧语义完全一致（含测试场景的假敌人）
		var tree := get_tree()
		if tree != null:
			return tree.get_nodes_in_group("enemy")
	return _enemy_cache
