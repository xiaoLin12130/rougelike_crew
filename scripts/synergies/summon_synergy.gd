extends SynergyBase
## 召唤军团流机制脚本（钩子式流派系统）
## 由 SynergyRegistry.load_synergy_scripts() 自动扫描 scripts/synergies/*.gd 并实例化注册。
## 设计文档：docs/design/流派构筑大全.md 第 5 章「召唤军团流」（核心：召唤 · 10 种召唤物）。
## 构筑 id 与 .tools/build_defs/summon.json 一致：数值 summon_1..summon_10，机制 summon_m1..summon_m10。
## 机制强度由持有 summon_ 前缀构筑总层数控制（_summon_stacks）。
##
## 钩子使用：
##   cast         召M6 首领（精英预标记）/ 召M10 军团冲锋 / 召7 共鸣水晶
##   enemy_hit    召M4 集火（精英优先增伤）/ 召10 召唤精通（召唤物暴击）/ 召M7 狂热击杀归属标记
##   enemy_died   召M7 狂热（召唤物命中过的敌人死亡 → 全体召唤物攻速 +8%×3s，可叠加）
##   player_hit   召M5 共生（15% 分摊）/ 召M8 替身（死亡时消耗召唤物回血）
##   _physics_process 轮询：
##       召M1 军团光环（攻速）/ 召8 兽群本能（玩家伤害）→ 写入 run.synergy_bonus
##       召M2 献祭（周期引爆 + 3s 重生）/ 召M3 亡语（tree_exiting）/ 召M9 召唤阵（减速法阵）
##       召2 军团号角 / 召3 先祖图腾 / 召4 御兽鞭 / 召5 契约符文 / 召6 灵魂石（每帧换算）
##
## 防御性约定：SynergyRegistry.trigger 不捕获回调异常（异常会冒泡崩游戏），
## 因此所有回调对空值/失效节点/缺失字段一律兜底，不抛异常。
## 已知近似（受钩子能力限制，各函数内亦有注释）：
##   - 狂热无法得知击杀者，用"最近被召唤物命中过"的敌人死亡近似；
##   - 灵魂石只拦截寿命自然死亡（_life 归零），自爆/上限淘汰无法拦截；
##   - 契约符文作用于召唤物技能冷却（法术核心冷却在 spell_caster 内部，不可钩取）；
##   - 献祭无玩家主动输入钩子，按固定周期自动引爆。

const SUMMON_SCRIPT := preload("res://scripts/combat/summon.gd")

# —— 数值常量（与 .tools/build_defs/summon.json 的曲线含义一致）——
const HORN_DMG_PER_STACK := 0.12        # 召2 军团号角：召唤物伤害 +12%/层
const TOTEM_HP_PER_STACK := 0.15        # 召3 先祖图腾：召唤物生命 +15%/层
const WHIP_ASPD_PER_STACK := 0.10       # 召4 御兽鞭：召唤物攻速 +10%/层（冷却换算）
const RUNE_CD_PER_STACK := 0.08         # 召5 契约符文：召唤系冷却 -8%/层
const SOUL_SAVE_CHANCE := 0.25          # 召6 灵魂石：死亡 25% 概率不消失（每层独立）
const CRYSTAL_EXTRA_CHANCE := 0.15      # 召7 共鸣水晶：召唤时 15% 概率额外召唤（每层独立）
const PACK_DMG_PER_SUMMON := 0.02       # 召8 兽群本能：每存在 1 只召唤物，玩家伤害 +2%/层
const PACK_DMG_CAP := 0.60
const WHISPER_HEAL_PCT := 0.01          # 召9 亡者低语：召唤物死亡时玩家回复 1% 生命/层
const MASTERY_CRIT_PER_STACK := 0.06    # 召10 召唤精通：召唤物暴击率 +6%/层
const MASTERY_CRIT_CAP := 0.50

# —— 机制常量（强度随 _summon_stacks() 提升）——
const AURA_ASPD_PER_SUMMON := 0.02      # 召M1 军团光环：每只召唤物 +2% 玩家攻速
const AURA_CAP := 0.50
const SACRIFICE_BASE_CD := 4.0          # 召M2 献祭：基础周期 4s
const SACRIFICE_MIN_CD := 2.0
const SACRIFICE_RESPAWN_T := 3.0        # 引爆 3s 后重生
const SACRIFICE_DMG_MULT := 1.5         # 基础伤害倍率（随构筑系数至多 3.0×）
const SACRIFICE_DMG_CAP := 3.0
const DEATH_BURST_MULT := 0.40          # 召M3 亡语：40% 伤害爆炸
const FOCUS_BONUS := 0.25               # 召M4 集火：+25%/点强度（1~3 点）
const SYMBIOSIS_SHARE := 0.15           # 召M5 共生：15% 分摊（随构筑系数）
const SYMBIOSIS_CAP := 0.45
const ELITE_EVERY := 5                  # 召M6 首领：每 5 只召唤物后，第 6 只精英
const ELITE_MULT := 1.5                 # 精英 +50% 属性
const FRENZY_ASPD := 0.08               # 召M7 狂热：击杀后攻速 +8%
const FRENZY_TIME := 3.0                # 持续 3s
const SUBSTITUTE_HEAL_PCT := 0.30       # 召M8 替身：回 30% 血
const SUBSTITUTE_HEAL_CAP := 0.50
const CIRCLE_TIME := 3.0                # 召M9 召唤阵：持续 3s
const CIRCLE_TICK := 0.6                # 减速刷新间隔
const CHARGE_EVERY := 3                 # 召M10 军团冲锋：每 3 次召唤
const CHARGE_EXTRA := 2                 # 本次补召 2 只（共 3 只）
const MIN_CD := 0.05
const LIFETIME_REFRESH := 30.0          # 灵魂石保命时刷新寿命

## 运行状态
var _player: Node2D = null
var _pending_elite := false             # 下次召唤为精英（召M6）
var _charge_count := 0                  # 召唤计数（召M10）
var _sacrifice_timer := 0.0             # 献祭倒计时（召M2）
var _frenzy := {}                       # summon instance_id -> {"stacks": float, "t": float}（召M7）
var _summon_hit := {}                   # enemy instance_id -> true：被召唤物命中过（召M7 归属近似）
var _respawns := []                     # [{type, pos, t, dmg}]（召M2 重生）
var _circles := []                      # [{pos, radius, t, tick}]（召M9）
var _in_hit_bonus := false              # enemy_hit 增伤重入守卫（召M4 / 召10）


func _ready() -> void:
	super._ready()
	_register("cast", _on_cast)
	_register("enemy_hit", _on_enemy_hit)
	_register("enemy_died", _on_enemy_died)
	_register("player_hit", _on_player_hit)


## 每物理帧轮询召唤物（注册/属性换算/灵魂石保命）与周期机制
func _physics_process(delta: float) -> void:
	if GameState.run.is_empty() or get_tree() == null:
		return
	_update_summons(delta)
	_update_respawns(delta)
	_update_circles(delta)
	_update_sacrifice(delta)
	_update_auras()
	_prune_summon_hit()


# ================= 工具 =================

func _player_ref() -> Node2D:
	if _player != null and is_instance_valid(_player):
		return _player
	_player = get_tree().get_first_node_in_group("player") as Node2D
	return _player


func _sget(node: Node, prop: String, def: float) -> float:
	## Object.get 无默认参数，这里统一做防御取值（缺失字段返回 def）
	var v: Variant = node.get(prop)
	return float(v) if v != null else def


func _sget_str(node: Node, prop: String, def: String) -> String:
	var v: Variant = node.get(prop)
	return str(v) if v != null else def
## 持有 summon_ 前缀构筑总层数（机制强度主控，含数值与机制构筑）
func _summon_stacks() -> int:
	if GameState.run.is_empty():
		return 0
	var items: Variant = GameState.run.get("items", {})
	if not (items is Dictionary):
		return 0
	var total := 0
	for k in items:
		if str(k).begins_with("summon_"):
			total += int(items[k])
	return total


## 构筑系数：n=1 时为 1.0（设计文档基准数值），上限 2.0
func _scale() -> float:
	var n := _summon_stacks()
	if n <= 0:
		return 0.0
	return minf(0.6 + 0.4 * float(n), 2.0)


func _summons_alive() -> int:
	if get_tree() == null:
		return 0
	var n := 0
	for s in get_tree().get_nodes_in_group("summons"):
		if s != null and is_instance_valid(s) and not s.is_queued_for_deletion():
			n += 1
	return n


# ================= 召唤物注册 / 每帧属性换算 =================

func _update_summons(delta: float) -> void:
	var horn := _stacks("summon_2")
	var whip := _stacks("summon_4")
	var rune := _stacks("summon_5")
	var totem := _stacks("summon_3")
	var soul := _stacks("summon_6")
	for s in get_tree().get_nodes_in_group("summons"):
		if s == null or not is_instance_valid(s) or s.is_queued_for_deletion():
			continue
		if not s.has_meta("summon_syn_base_dmg"):
			_register_summon(s, totem)
		_apply_summon_stats(s, horn, whip, rune, delta)
		_try_soul_save(s, soul)


func _register_summon(s: Node, totem_stacks: int) -> void:
	## 记录基准属性（meta），应用一次性缩放（生命/精英），生成召唤阵，连接死亡信号
	var base_dmg := _sget(s, "_dmg", 0.0)
	var base_hp := maxf(_sget(s, "_hp", 1.0), 1.0)
	var base_max_hp := maxf(_sget(s, "_max_hp", 1.0), 1.0)
	var base_cd := maxf(_sget(s, "_skill_cd", 1.0), MIN_CD)
	s.set_meta("summon_syn_base_dmg", base_dmg)
	s.set_meta("summon_syn_base_hp", base_hp)
	s.set_meta("summon_syn_base_max_hp", base_max_hp)
	s.set_meta("summon_syn_base_cd", base_cd)
	var elite := _pending_elite
	_pending_elite = false
	s.set_meta("summon_syn_elite", elite)
	# 召3 先祖图腾：生命 +15%/层；召M6 首领：+50% 属性（生命在此一次性缩放，避免逐帧重复叠加）
	var hp_mult := 1.0 + TOTEM_HP_PER_STACK * float(totem_stacks)
	var max_hp := base_max_hp * hp_mult
	var hp := base_hp * hp_mult
	if elite:
		max_hp *= ELITE_MULT
		hp *= ELITE_MULT
		_apply_elite_visual(s)
	s.set("_max_hp", max_hp)
	s.set("_hp", hp)
	# 召M9 召唤阵：召唤点生成减速法阵
	if _stacks("summon_m9") > 0:
		_circles.append({
			"pos": s.global_position,
			"radius": 48.0 + 6.0 * float(_summon_stacks()),
			"t": CIRCLE_TIME,
			"tick": 0.0,
		})
		EventBus.fx_explosion.emit(s.global_position, "ice")
	if not s.tree_exiting.is_connected(_on_summon_exiting.bind(s)):
		s.tree_exiting.connect(_on_summon_exiting.bind(s))


func _apply_elite_visual(s: Node) -> void:
	var spr := s.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if spr != null:
		spr.modulate = Color(1.0, 0.85, 0.35, 1.0)
	EventBus.fx_explosion.emit(s.global_position, "gold")  # 落雷误触发修复：召唤精英化改金色


func _apply_summon_stats(s: Node, horn: int, whip: int, rune: int, delta: float) -> void:
	## 每帧按当前构筑重算伤害/技能冷却（天然免疫重复叠加；狂热层数在此衰减）
	var base_dmg := float(s.get_meta("summon_syn_base_dmg", 0.0))
	var dmg := base_dmg * (1.0 + HORN_DMG_PER_STACK * float(horn))
	if bool(s.get_meta("summon_syn_elite", false)):
		dmg *= ELITE_MULT
	s.set("_dmg", maxf(dmg, 0.0))
	var id := s.get_instance_id()
	var f: Dictionary = _frenzy.get(id, {})
	if not f.is_empty():
		f["t"] = float(f.get("t", 0.0)) - delta
		if float(f["t"]) <= 0.0:
			_frenzy.erase(id)
			f = {}
	var base_cd := maxf(float(s.get_meta("summon_syn_base_cd", 1.0)), MIN_CD)
	# 召4 御兽鞭：攻速 +10%/层（冷却 ÷(1+k)）；召5 契约符文：冷却 -8%/层；召M7 狂热：-8%/层
	var cd := base_cd * (1.0 - RUNE_CD_PER_STACK * float(rune)) / (1.0 + WHIP_ASPD_PER_STACK * float(whip))
	cd *= 1.0 - FRENZY_ASPD * float(f.get("stacks", 0.0))
	s.set("_skill_cd", maxf(cd, MIN_CD))


func _try_soul_save(s: Node, soul_stacks: int) -> void:
	## 召6 灵魂石：寿命归零时每层独立 25% 概率保命（保 1 血 + 刷新寿命）
	if soul_stacks <= 0:
		return
	var life := _sget(s, "_life", LIFETIME_REFRESH)
	if life > 1.0:
		s.set_meta("summon_syn_save_rolled", false)
		return
	if bool(s.get_meta("summon_syn_save_rolled", false)):
		return
	s.set_meta("summon_syn_save_rolled", true)
	if randf() >= 1.0 - pow(1.0 - SOUL_SAVE_CHANCE, soul_stacks):
		return
	s.set("_life", LIFETIME_REFRESH)
	s.set("_hp", maxf(_sget(s, "_hp", 1.0), 1.0))
	EventBus.fx_explosion.emit(s.global_position, "light")


func _on_summon_exiting(s: Node) -> void:
	## 召唤物死亡：召M3 亡语爆炸 + 召9 亡者低语回血
	if s == null or not is_instance_valid(s):
		return
	_frenzy.erase(s.get_instance_id())
	if GameState.run.is_empty():
		return
	var pos: Vector2 = s.global_position
	if _stacks("summon_m3") > 0:
		var dmg := _sget(s, "_dmg", 0.0)
		_aoe_damage(pos, 40.0 + 4.0 * float(_summon_stacks()), dmg * DEATH_BURST_MULT)
		EventBus.fx_explosion.emit(pos, "fire")
	var whisper := _stacks("summon_9")
	if whisper > 0:
		var max_hp := float(GameState.run.get("max_hp", 100))
		GameState.heal(max_hp * WHISPER_HEAL_PCT * float(whisper))


func _aoe_damage(center: Vector2, radius: float, dmg: float) -> void:
	if dmg <= 0.0 or get_tree() == null:
		return
	for e in GameState.get_enemies():
		if e == null or not is_instance_valid(e):
			continue
		if center.distance_to(e.global_position) <= radius + e.scale.x * 8.0:
			if e.has_method("take_damage"):
				e.take_damage(maxi(roundi(dmg), 1), "summon", false)
				EventBus.damage_dealt.emit(maxi(roundi(dmg), 1), e.global_position, false)


# ================= 钩子回调 =================

## 法术施放：召M6 首领 / 召M10 军团冲锋 / 召7 共鸣水晶（仅召唤核心）
func _on_cast(ctx: Dictionary) -> void:
	if not (ctx is Dictionary):
		return
	var core: Variant = ctx.get("core")
	if not (core is Dictionary):
		return
	if not (core.has("summon") or str(core.get("id", "")) == "summon_bat"):
		return  # 非召唤核心
	# 召M6 首领：场上召唤物数量为 5 的倍数时，本次召唤精英级
	if _stacks("summon_m6") > 0:
		var alive := _summons_alive()
		if alive > 0 and alive % ELITE_EVERY == 0:
			_pending_elite = true
	# 召M10 军团冲锋：每 3 次召唤后，本次补召 2 只
	# （deferred 保证主召唤先落地，精英标记优先给主召唤；上限淘汰由 summon.gd 内部兜底）
	if _stacks("summon_m10") > 0:
		_charge_count += 1
		if _charge_count % CHARGE_EVERY == 0:
			var pos := _spawn_pos(ctx)
			var dmg := _extra_summon_dmg(core, ctx.get("mods", {}))
			for i in CHARGE_EXTRA:
				call_deferred("_spawn_extra_summon", "", pos, dmg)
	# 召7 共鸣水晶：每层独立 15% 概率额外召唤一只
	var crystal := _stacks("summon_7")
	if crystal > 0 and randf() < 1.0 - pow(1.0 - CRYSTAL_EXTRA_CHANCE, crystal):
		call_deferred("_spawn_extra_summon", "", _spawn_pos(ctx), _extra_summon_dmg(core, ctx.get("mods", {})))


## 敌人受击：召M4 集火 + 召10 召唤精通（仅强化 element=="summon" 的召唤物伤害）
func _on_enemy_hit(ctx: Dictionary) -> void:
	if not (ctx is Dictionary) or _in_hit_bonus:
		return
	var enemy: Variant = ctx.get("enemy")
	var element := str(ctx.get("element", ""))
	if element != "summon" or enemy == null or not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
		return
	var dmg := int(ctx.get("dmg", 0))
	if dmg <= 0:
		return
	# 召M7 狂热击杀归属近似：记录该敌人被召唤物命中过
	_summon_hit[enemy.get_instance_id()] = true
	var bonus := 0.0
	if _stacks("summon_m4") > 0 and _is_focus_target(enemy):
		bonus += FOCUS_BONUS * float(mini(_summon_stacks(), 3))
	var mastery := _stacks("summon_10")
	if mastery > 0 and randf() < minf(MASTERY_CRIT_PER_STACK * float(mastery), MASTERY_CRIT_CAP):
		bonus += maxf(float(GameState.run.get("crit_dmg_bonus", 1.5)) - 1.0, 0.0)
	if bonus <= 0.0:
		return
	_in_hit_bonus = true
	if enemy.has_method("take_damage"):
		enemy.take_damage(maxi(roundi(float(dmg) * bonus), 1), "summon", false)
	_in_hit_bonus = false


## 集火目标：距玩家最近的精英；无精英则最近的敌人
func _is_focus_target(enemy: Node) -> bool:
	var player := _player_ref()
	if player == null or get_tree() == null:
		return false
	var origin: Vector2 = player.global_position
	var focus: Node = null
	var focus_d := INF
	for e in GameState.get_enemies():
		if e == null or not is_instance_valid(e) or e.is_queued_for_deletion():
			continue
		if e.get("is_elite") != true:
			continue
		var d: float = origin.distance_to(e.global_position)
		if d < focus_d:
			focus_d = d
			focus = e
	if focus == null:
		for e in GameState.get_enemies():
			if e == null or not is_instance_valid(e) or e.is_queued_for_deletion():
				continue
			var d: float = origin.distance_to(e.global_position)
			if d < focus_d:
				focus_d = d
				focus = e
	return focus == enemy


## 敌人死亡：召M7 狂热（召唤物命中过的敌人死亡 → 全体召唤物攻速 +8% 持续 3s，可叠加）
func _on_enemy_died(ctx: Dictionary) -> void:
	if not (ctx is Dictionary) or _stacks("summon_m7") <= 0 or get_tree() == null:
		return
	var enemy: Variant = ctx.get("enemy")
	if enemy == null or not is_instance_valid(enemy):
		return
	var eid: int = enemy.get_instance_id()
	if not bool(_summon_hit.get(eid, false)):
		return
	_summon_hit.erase(eid)
	var cap := float(mini(1 + _summon_stacks(), 5))
	for s in get_tree().get_nodes_in_group("summons"):
		if s == null or not is_instance_valid(s) or s.is_queued_for_deletion():
			continue
		var id := s.get_instance_id()
		var f: Dictionary = _frenzy.get(id, {})
		if f.is_empty():
			f = {"stacks": 0.0, "t": 0.0}
		f["stacks"] = minf(float(f.get("stacks", 0.0)) + 1.0, cap)
		f["t"] = FRENZY_TIME
		_frenzy[id] = f


## 玩家受击：召M5 共生 + 召M8 替身（player_hit 在扣血后、player_died 判定前触发）
func _on_player_hit(ctx: Dictionary) -> void:
	if not (ctx is Dictionary):
		return
	var taken := float(ctx.get("taken", 0.0))
	if taken > 0.0 and _stacks("summon_m5") > 0:
		# 召M5 共生：15%×构筑系数 由召唤物分摊，玩家回补
		var share := minf(SYMBIOSIS_SHARE * _scale(), SYMBIOSIS_CAP)
		GameState.heal(taken * share)
		_damage_summons(taken * share)
	# 召M8 替身：玩家血量归零时消耗最弱召唤物代替死亡
	if _stacks("summon_m8") > 0 and int(GameState.run.get("hp", 0)) <= 0:
		_substitute_save()


## 共生分摊：均分到存活召唤物并扣除 _hp；归零者死亡（顺带触发亡语/低语）
func _damage_summons(amount: float) -> void:
	if amount <= 0.0 or get_tree() == null:
		return
	var alive: Array = []
	for s in get_tree().get_nodes_in_group("summons"):
		if s != null and is_instance_valid(s) and not s.is_queued_for_deletion():
			alive.append(s)
	if alive.is_empty():
		return
	var per := amount / float(alive.size())
	for s in alive:
		var hp := _sget(s, "_hp", 0.0) - per
		if hp <= 0.0:
			s.queue_free()
		else:
			s.set("_hp", hp)


## 召M8 替身：消耗最弱召唤物，回复 30%×构筑系数 生命
func _substitute_save() -> void:
	var s := _weakest_summon()
	if s == null:
		return
	var pos: Vector2 = s.global_position
	s.queue_free()
	var max_hp := float(GameState.run.get("max_hp", 100))
	GameState.heal(max_hp * minf(SUBSTITUTE_HEAL_PCT * _scale(), SUBSTITUTE_HEAL_CAP))
	EventBus.fx_explosion.emit(pos, "light")


func _weakest_summon() -> Node:
	if get_tree() == null:
		return null
	var best: Node = null
	var best_hp := INF
	for s in get_tree().get_nodes_in_group("summons"):
		if s == null or not is_instance_valid(s) or s.is_queued_for_deletion():
			continue
		var hp := _sget(s, "_hp", INF)
		if hp < best_hp:
			best_hp = hp
			best = s
	return best


# ================= 周期机制（_physics_process） =================

## 召M2 献祭：周期性引爆最弱召唤物（范围伤害+燃烧），3s 后同型重生
func _update_sacrifice(delta: float) -> void:
	if _stacks("summon_m2") <= 0 or get_tree() == null:
		_sacrifice_timer = 0.0
		return
	_sacrifice_timer -= delta
	if _sacrifice_timer > 0.0:
		return
	var n := _summon_stacks()
	_sacrifice_timer = maxf(SACRIFICE_BASE_CD - 0.5 * float(n - 1), SACRIFICE_MIN_CD)
	if GameState.get_enemies().is_empty():
		return  # 无敌人不引爆，避免空转损耗
	var s := _weakest_summon()
	if s == null:
		return
	var pos: Vector2 = s.global_position
	var type_id := _sget_str(s, "_type_id", "")
	var base_dmg := float(s.get_meta("summon_syn_base_dmg", 0.0))
	var dmg := maxf(_sget(s, "_dmg", 0.0), 1.0) * minf(SACRIFICE_DMG_MULT * _scale(), SACRIFICE_DMG_CAP)
	var radius := 56.0 + 6.0 * float(n)
	EventBus.fx_explosion.emit(pos, "fire")
	EventBus.screen_shake.emit(3.0)
	for e in GameState.get_enemies():
		if e == null or not is_instance_valid(e):
			continue
		if pos.distance_to(e.global_position) <= radius + e.scale.x * 8.0:
			if e.has_method("take_damage"):
				e.take_damage(maxi(roundi(dmg), 1), "summon", false)
				EventBus.damage_dealt.emit(maxi(roundi(dmg), 1), e.global_position, false)
			EventBus.apply_status.emit(e, "burn", 1)  # 燃烧
	s.queue_free()  # 引爆即死亡：联动召M3 亡语 / 召9 低语
	_respawns.append({"type": type_id, "pos": pos, "t": SACRIFICE_RESPAWN_T, "dmg": base_dmg})


func _update_respawns(delta: float) -> void:
	if _respawns.is_empty():
		return
	var keep: Array = []
	for r in _respawns:
		var rd: Dictionary = r
		rd["t"] = float(rd.get("t", 0.0)) - delta
		if float(rd["t"]) > 0.0:
			keep.append(rd)
		else:
			_spawn_extra_summon(str(rd.get("type", "")), rd.get("pos", Vector2.ZERO), float(rd.get("dmg", 6.0)))
	_respawns = keep


## 召M9 召唤阵：持续 3s，周期减速阵内敌人
func _update_circles(delta: float) -> void:
	if _circles.is_empty():
		return
	var keep: Array = []
	for c in _circles:
		var cd: Dictionary = c
		cd["t"] = float(cd.get("t", 0.0)) - delta
		if float(cd["t"]) <= 0.0:
			continue
		cd["tick"] = float(cd.get("tick", 0.0)) - delta
		if float(cd["tick"]) <= 0.0:
			cd["tick"] = CIRCLE_TICK
			var center: Vector2 = cd.get("pos", Vector2.ZERO)
			var radius := float(cd.get("radius", 48.0))
			for e in GameState.get_enemies():
				if e == null or not is_instance_valid(e):
					continue
				if center.distance_to(e.global_position) <= radius + e.scale.x * 8.0:
					EventBus.apply_status.emit(e, "slow", 1)
					EventBus.fx_hit_slow.emit(e, true)  # 保持顿帧 60ms（G-4 分级后）
			EventBus.fx_explosion.emit(center, "ice")
		keep.append(cd)
	_circles = keep


## 召M1 军团光环（玩家攻速）+ 召8 兽群本能（玩家伤害）：写入 synergy_bonus 供 aggregate_bonus 消费
func _update_auras() -> void:
	if _stacks("summon_m1") <= 0:
		return
	var bonus: Dictionary = GameState.run.get("synergy_bonus", {})
	var alive := float(_summons_alive())
	var aura := minf(AURA_ASPD_PER_SUMMON * _scale() * alive, AURA_CAP)
	if aura > 0.0:
		bonus["attack_speed"] = maxf(float(bonus.get("attack_speed", 0.0)), aura)
	var pack := minf(PACK_DMG_PER_SUMMON * float(_stacks("summon_8")) * alive, PACK_DMG_CAP)
	if pack > 0.0:
		bonus["atk"] = maxf(float(bonus.get("atk", 0.0)), pack)
	GameState.run["synergy_bonus"] = bonus


func _prune_summon_hit() -> void:
	## 清理已消失敌人的命中标记（召M7 归属近似）
	if _summon_hit.is_empty() or get_tree() == null:
		return
	var stale: Array = []
	for eid in _summon_hit:
		var node = instance_from_id(int(eid))
		if node == null or not is_instance_valid(node) or node.is_queued_for_deletion():
			stale.append(eid)
	for eid in stale:
		_summon_hit.erase(eid)


# ================= 召唤物生成（复用 summon.gd 现有接口，不改动文件） =================

## 冲锋/共鸣/献祭重生补召；type_id 为空时按权重随机
func _spawn_extra_summon(type_id: String, pos: Vector2, base_dmg: float) -> void:
	var player := _player_ref()
	if player == null or not is_instance_valid(player) or get_tree() == null:
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var s := SUMMON_SCRIPT.new()
	s.setup(player, maxf(base_dmg, 1.0), "summon", type_id)
	scene.add_child(s)
	s.global_position = pos


## 近似 spell_caster 的召唤伤害（base × 外壳倍率 × atk 加成 × 召唤加成）
func _extra_summon_dmg(core: Dictionary, mods: Variant) -> float:
	var m := 1.0
	if mods is Dictionary:
		m = float(mods.get("damage_mult", 1.0))
	var base := float(core.get("base_damage", 6.0)) * m
	base *= 1.0 + GameState.aggregate_bonus("atk")
	base *= 1.0 + GameState.aggregate_bonus("summon")
	return maxf(base, 1.0)


func _spawn_pos(ctx: Dictionary) -> Vector2:
	var player: Variant = ctx.get("player")
	if player != null and is_instance_valid(player):
		return player.global_position + Vector2(randf_range(-12.0, 12.0), randf_range(-12.0, 12.0))
	var p := _player_ref()
	if p != null:
		return p.global_position + Vector2(randf_range(-12.0, 12.0), randf_range(-12.0, 12.0))
	return Vector2(640.0, 360.0)
