extends Node
## 毒系瘟疫流 · 机制脚本（毒M1 传染 / 毒M2 毒爆 / 毒M3 毒雾弥漫 / 毒M4 腐蚀 /
## 毒M5 毒刃 / 毒M6 抗性渗透 / 毒M7 慢性死亡 / 毒M8 解毒反哺 / 毒M9 疫病之源 /
## 毒M10 五毒俱全），并承载毒1-毒10 数值构筑在战斗中的实际结算。
##
## 强度模型：机制强度由持有的 poison_ 前缀构筑总层数驱动（GameState.run.items
## 中 id 以 poison_ 开头的堆叠数之和，即 GameState.total_stacks 的聚合）。
## 钩子：enemy_status / enemy_died / projectile_hit / cast（SynergyRegistry），
## 另监听 EventBus.apply_status 做毒层跟踪（先于敌人自身 _on_status 触发）。
## 回调全部防御性编写：空对象 / 缺字段 / 无效实例一律静默返回。

# ---------- 毒雾地面视觉（只加视觉，不动伤害/扩散判定） ----------
const FxManagerScript := preload("res://scripts/fx/fx_manager.gd")

# ---------- 基础数值（文档第 4 章 + 验收克制） ----------
const POISON_DURATION_BASE := 3.0   # 毒基础持续时间（秒）
const POISON_CAP_BASE := 5          # 毒层上限基础值（毒2 每层 +2）
const BURST_RADIUS_BASE := 70.0     # 毒爆 / 传染 / 毒雾基础半径（px）
const SPREAD_CHANCE_MIN := 0.15     # 传染概率下限（验收：15%）
const SPREAD_CHANCE_MAX := 0.25     # 传染概率上限（验收：25%）
const BUG_BASE_CHANCE := 0.08       # 毒爆虫基础概率（毒M9）
const RAMP_BASE_RATE := 0.05        # 慢性死亡每秒增幅（毒M7）
const RAMP_MAX_MULT := 2.5          # 慢性死亡增幅上限（+150%）
const FEED_BASE_RATE := 0.05        # 解毒反哺基础比例（毒M8）
const FEED_MAX_RATE := 0.20         # 反哺上限
const CORRODE_BASE := 0.30          # 腐蚀护甲穿透（毒M4）
const PENTAD_BASE_MULT := 2.0       # 五毒俱全毒伤倍率（毒M10）
const PENTAD_MAX_MULT := 4.0        # 五毒俱全倍率上限

const ENEMY_SCENE := preload("res://scenes/game/enemy.tscn")

# 按敌人实例 id 维护的毒状态（敌人本体只存 _poison_left / _poison_dps）
var _stacks := {}             # id -> int   当前毒层（受毒2 上限钳制）
var _poison_time := {}        # id -> float 本次中毒累计时长（毒M7）
var _pending_duration := {}   # id -> float 待写入持续时间（毒3 / 毒M3）
var _spread_timer := {}       # id -> float 毒雾扩散倒计时（毒M3）
var _corroded := {}           # id -> true  已腐蚀（毒M4）
var _orig_armor := {}         # id -> float 腐蚀前护甲
var _weakened := {}           # id -> true  已削弱攻击（毒5）
var _orig_attack := {}        # id -> int   削弱前攻击
var _slowed := {}             # id -> true  已减速（毒7）
var _orig_speed := {}         # id -> float 减速前移速


func _ready() -> void:
	SynergyRegistry.register("enemy_status", _on_enemy_status)
	SynergyRegistry.register("enemy_died", _on_enemy_died)
	SynergyRegistry.register("projectile_hit", _on_projectile_hit)
	SynergyRegistry.register("cast", _on_cast)
	EventBus.apply_status.connect(_on_apply_status)


# ================= 防御性取值 =================

## Object.get() 静态只接受 1 参：带默认值的读取统一走这里（缺字段返回 def）。
func _num(node: Node, key: String, def: float) -> float:
	var v: Variant = node.get(key)
	return float(v) if v != null else def


func _bool(node: Node, key: String, def: bool) -> bool:
	var v: Variant = node.get(key)
	return bool(v) if v != null else def


# ================= 强度与取值 =================

## 机制强度：持有 poison_ 前缀构筑的总层数（含数值与机制构筑）。
func _poison_power() -> int:
	if GameState == null or not (GameState.run is Dictionary):
		return 0
	var n := 0
	for id in GameState.run.get("items", {}):
		if str(id).begins_with("poison_"):
			n += int(GameState.run["items"][id])
	return n


func _stacks_of(item_id: String) -> int:
	if GameState == null or not (GameState.run is Dictionary):
		return 0
	return GameState.total_stacks(item_id)


func _poison_cap() -> int:
	return POISON_CAP_BASE + 2 * _stacks_of("poison_cap")


## 毒6 毒囊：毒系范围 +12%/层（毒爆 / 传染 / 毒雾共用半径）。
func _burst_radius() -> float:
	return minf(BURST_RADIUS_BASE * (1.0 + 0.12 * float(_stacks_of("poison_area"))), 220.0)


## 毒M1 传染概率：15% 起，构筑每多 1 层 +1%，孢子囊每层 +2%，上限 25%。
func _spread_chance() -> float:
	if _poison_power() < 1:
		return 0.0
	var c := SPREAD_CHANCE_MIN + 0.01 * float(maxi(_poison_power() - 1, 0))
	c += 0.02 * float(_stacks_of("poison_spore"))
	return clampf(c, SPREAD_CHANCE_MIN, SPREAD_CHANCE_MAX)


## 毒M3 毒雾持续时间：+100% 起步，构筑每多 1 层 +25%，上限 ×4。
func _cloud_duration_mult() -> float:
	if _poison_power() < 1:
		return 1.0
	return minf(1.0 + 1.0 * (1.0 + 0.25 * float(maxi(_poison_power() - 1, 0))), 4.0)


## 毒M7 慢性死亡：每秒 +5% 起步，慢性毒囊每层 +10%，总增幅上限 +150%。
func _ramp_rate() -> float:
	if _poison_power() < 1:
		return 0.0
	return RAMP_BASE_RATE * (1.0 + 0.10 * float(_stacks_of("poison_ramp")))


func _ramp_mult(elapsed: float) -> float:
	return minf(1.0 + _ramp_rate() * elapsed, RAMP_MAX_MULT)


## 毒M8 解毒反哺：基础 5%，反哺血清每层 +1%，上限 20%。
func _feed_rate() -> float:
	if _poison_power() < 1:
		return 0.0
	return minf(FEED_BASE_RATE + 0.01 * float(_stacks_of("poison_serum")), FEED_MAX_RATE)


## 毒M4 腐蚀：基础护甲穿透 30%，强腐蚀酸每层 +4%，上限 60%。
func _corrode_pen() -> float:
	if _poison_power() < 1:
		return 0.0
	return minf(CORRODE_BASE + 0.04 * float(_stacks_of("poison_corrosive")), 0.60)


## 毒M10 五毒俱全：中毒 + 燃烧时毒伤翻倍，五毒符每层 +0.5 倍率，上限 ×4。
func _pentad_mult() -> float:
	if _poison_power() < 1:
		return 1.0
	return minf(PENTAD_BASE_MULT + 0.5 * float(_stacks_of("poison_pentad")), PENTAD_MAX_MULT)


## 毒M9 疫病之源：基础 8%，构筑每多 1 层 +0.4%，毒虫卵每层 +2%，上限 30%。
func _bug_chance() -> float:
	if _poison_power() < 1:
		return 0.0
	var c := BUG_BASE_CHANCE * (1.0 + 0.05 * float(maxi(_poison_power() - 1, 0)))
	c += 0.02 * float(_stacks_of("poison_bug_egg"))
	return minf(c, 0.30)


func _is_burning(enemy: Node2D) -> bool:
	return _num(enemy, "_burn_left", 0.0) > 0.0 or _num(enemy, "_burn_dps", 0.0) > 0.0


func _is_poisoned(enemy: Node2D, id: int) -> bool:
	return _num(enemy, "_poison_left", 0.0) > 0.0 or _stacks.get(id, 0) > 0


## 毒M6 抗性渗透：默认不作用于免疫目标；机制生效后无视免疫。
## （当前敌人表尚无免疫字段，防御性保留；对 Boss 加成见 _refresh_dps 的噬毒针。）
func _poison_immune(enemy: Node2D) -> bool:
	if _bool(enemy, "poison_immune", false):
		return true
	var conf: Variant = enemy.get("conf")
	if conf is Dictionary and bool(conf.get("poison_immune", false)):
		return true
	return false


func _can_apply_poison(enemy: Node2D) -> bool:
	if _poison_immune(enemy):
		return _poison_power() >= 1
	return true


# ================= 毒层跟踪（EventBus.apply_status） =================

func _on_apply_status(target: Node, kind: String, stacks: int) -> void:
	if kind != "poison" or not is_instance_valid(target):
		return
	if target.get("_poison_left") == null:
		return  # 只处理带毒槽的敌人
	var id := target.get_instance_id()
	var cap := _poison_cap()
	_stacks[id] = mini(int(_stacks.get(id, 0)) + maxi(int(stacks), 1), cap)
	# 毒3 腐蚀液：持续时间 +0.8s/层（下一帧 tick 时写入，避开敌人 _on_status 的 3.0 重置）
	_pending_duration[id] = POISON_DURATION_BASE + 0.8 * float(_stacks_of("poison_duration"))
	# 毒M4 腐蚀 / 毒5 疫病之触 / 毒7 缓蚀：进入中毒时一次性生效
	var e := target as Node2D
	if e != null:
		_corrode_enemy(e, id)
		_weaken_enemy(e, id)
		_slow_enemy(e, id)
		_refresh_dps(e, id)


func _corrode_enemy(enemy: Node2D, id: int) -> void:
	if not is_instance_valid(enemy) or _corroded.has(id) or enemy.get("armor") == null:
		return
	var pen := _corrode_pen()
	if pen <= 0.0:
		return
	_orig_armor[id] = _num(enemy, "armor", 0.0)
	enemy.set("armor", maxf(_num(enemy, "armor", 0.0) - pen, 0.0))
	_corroded[id] = true


func _weaken_enemy(enemy: Node2D, id: int) -> void:
	if not is_instance_valid(enemy) or _weakened.has(id) or enemy.get("attack") == null:
		return
	var pen := 0.08 * float(_stacks_of("poison_plague_touch"))
	if pen <= 0.0:
		return
	_orig_attack[id] = int(_num(enemy, "attack", 0.0))
	enemy.set("attack", maxi(int(_num(enemy, "attack", 0.0) * (1.0 - pen)), 1))
	_weakened[id] = true


func _slow_enemy(enemy: Node2D, id: int) -> void:
	if not is_instance_valid(enemy) or _slowed.has(id) or enemy.get("speed") == null:
		return
	var pen := minf(0.08 * float(_stacks_of("poison_slow")), 0.70)
	if pen <= 0.0:
		return
	_orig_speed[id] = _num(enemy, "speed", 0.0)
	enemy.set("speed", maxf(_num(enemy, "speed", 0.0) * (1.0 - pen), 20.0))
	_slowed[id] = true


## 重算毒 DPS：基础 ×（毒1 毒伤加成）×（毒M7 慢性死亡）×（毒M10 五毒俱全）
## ×（毒M6 噬毒针：对 Boss +10%/层）。
func _refresh_dps(enemy: Node2D, id: int) -> void:
	var stacks: int = _stacks.get(id, 0)
	if stacks <= 0 or enemy.get("_poison_dps") == null:
		return
	var base: float = _num(enemy, "max_hp", 1.0) * 0.01 * float(stacks)
	if GameState != null:
		base *= 1.0 + GameState.aggregate_bonus("poison_dmg")
	var mult := 1.0
	if _ramp_rate() > 0.0:
		mult *= _ramp_mult(_poison_time.get(id, 0.0))
	if _pentad_mult() > 1.0 and _is_burning(enemy):
		mult *= _pentad_mult()
	if _bool(enemy, "is_boss", false):
		base *= 1.0 + 0.10 * float(_stacks_of("poison_pierce"))
	enemy.set("_poison_dps", maxf(_num(enemy, "_poison_dps", 0.0), base * mult))


# ================= 钩子：enemy_status（毒跳） =================

func _on_enemy_status(ctx: Dictionary) -> void:
	if not is_inside_tree():
		return
	if not (ctx is Dictionary):
		return
	var enemy := ctx.get("enemy") as Node2D
	if not is_instance_valid(enemy) or ctx.get("kind") != "poison":
		return
	var id := enemy.get_instance_id()
	var delta: float = float(ctx.get("delta", 0.0))
	var left: float = _num(enemy, "_poison_left", 0.0)
	var ending: bool = left <= delta + 0.0001
	# 毒3 / 毒M3：把待写入的持续时间落到敌人身上（先于强度门控，保证无构筑时也收敛）
	if _pending_duration.has(id):
		var dur: float = float(_pending_duration[id]) * _cloud_duration_mult()
		_pending_duration.erase(id)
		enemy.set("_poison_left", maxf(left, dur))
		ending = false
	if _poison_power() < 1:
		return
	# 毒M7 慢性死亡：累计中毒时长
	_poison_time[id] = _poison_time.get(id, 0.0) + delta
	# 毒9 感染源：层数超过 5 时，超出部分每层每秒 1% 最大生命真伤
	var inf_stacks: int = _stacks_of("poison_infection")
	var st: int = _stacks.get(id, 0)
	if inf_stacks > 0 and st > 5:
		var extra := _num(enemy, "max_hp", 1.0) * 0.01 * float(st - 5) * delta
		extra *= 1.0 + 0.5 * float(inf_stacks - 1)
		if enemy.has_method("_take_raw"):
			enemy.call("_take_raw", int(extra))
	# 毒M8 解毒反哺：毒伤的一部分回复生命（GameState.heal 自带上限钳制）
	var rate := _feed_rate()
	if rate > 0.0:
		var tick_dmg := _num(enemy, "_poison_dps", 0.0) * delta
		if tick_dmg > 0.0 and GameState != null:
			var healed := GameState.heal(int(tick_dmg * rate))
			if healed > 0:
				EventBus.fx_heal_text.emit(enemy.global_position, healed)
	# 毒1 / 毒M7 / 毒M10 / 噬毒针 聚合刷新
	_refresh_dps(enemy, id)
	# 毒M2 毒爆：毒层叠满即爆炸（范围毒伤 + 清空层数）
	if st >= _poison_cap():
		_do_burst(enemy, id)
	# 毒M3 毒雾弥漫：缓慢向四周扩散毒
	_tick_cloud_spread(enemy, id, delta)
	# 最后一跳：还原属性并清空跟踪
	if ending:
		_cleanup(enemy, id)


func _do_burst(enemy: Node2D, id: int) -> void:
	var cap := _poison_cap()
	var radius := _burst_radius()
	var dmg := _num(enemy, "max_hp", 1.0) * 0.04 * float(cap)
	dmg *= 1.0 + 0.20 * float(_stacks_of("poison_amp"))
	if GameState != null:
		dmg *= 1.0 + GameState.aggregate_bonus("poison_dmg")
	var pos: Vector2 = enemy.global_position
	_stacks[id] = 0
	enemy.set("_poison_dps", 0.0)
	EventBus.fx_explosion.emit(pos, "poison")
	# 毒爆地面视觉：爆点留下一团短时毒雾
	FxManagerScript.spawn_ground_fx("poison", pos, radius, 1.4)
	var tree := get_tree()
	if tree == null:
		return
	for node in tree.get_nodes_in_group("enemy"):
		var e := node as Node2D
		if e == null or not is_instance_valid(e):
			continue
		if e.global_position.distance_to(pos) > radius:
			continue
		var hit := int(dmg)
		if _pentad_mult() > 1.0 and _is_burning(e):
			hit = int(float(hit) * _pentad_mult())
		if e.has_method("_take_raw"):
			e.call("_take_raw", hit)
		EventBus.damage_dealt.emit(hit, e.global_position, false)


func _tick_cloud_spread(enemy: Node2D, id: int, delta: float) -> void:
	# 毒雾药瓶：扩散间隔 -12%/层（下限 0.45s）
	var interval := maxf(1.2 * (1.0 - 0.12 * float(_stacks_of("poison_cloud_vial"))), 0.45)
	var t: float = _spread_timer.get(id, interval)
	t -= delta
	if t <= 0.0:
		_spread_timer[id] = interval
		_spread_to_nearby(enemy, _burst_radius(), 1, 2)
		# 毒M3 毒雾弥漫地面视觉：扩散落点生成可见毒雾团
		FxManagerScript.spawn_ground_fx("poison", enemy.global_position, _burst_radius() * 0.8, 1.1)
	else:
		_spread_timer[id] = t


## 毒M1 传染 / 毒M3 毒雾共用：向半径内最多 max_targets 个敌人施加毒。
func _spread_to_nearby(source: Node2D, radius: float, layers: int, max_targets: int) -> void:
	if get_tree() == null:
		return
	var sid := source.get_instance_id()
	var pos: Vector2 = source.global_position
	var count := 0
	for node in get_tree().get_nodes_in_group("enemy"):
		if count >= max_targets:
			break
		var e := node as Node2D
		if e == null or not is_instance_valid(e) or e.get_instance_id() == sid:
			continue
		if e.global_position.distance_to(pos) > radius:
			continue
		if not _can_apply_poison(e):
			continue
		EventBus.apply_status.emit(e, "poison", maxi(layers, 1))
		count += 1


# ================= 钩子：enemy_died（毒M1 / 毒M9） =================

func _on_enemy_died(ctx: Dictionary) -> void:
	if not is_inside_tree():
		return
	if not (ctx is Dictionary):
		return
	var enemy := ctx.get("enemy") as Node2D
	if not is_instance_valid(enemy):
		return
	var id := enemy.get_instance_id()
	var was_poisoned := _is_poisoned(enemy, id)
	_cleanup(enemy, id)
	if not was_poisoned or _poison_power() < 1:
		return
	# 毒M1 传染：中毒敌人死亡概率扩散毒（15%-25%）
	if randf() < _spread_chance():
		_spread_to_nearby(enemy, _burst_radius(), 1, 3)
	# 毒M9 疫病之源：概率生成毒爆虫（自爆小怪）
	if randf() < _bug_chance():
		_spawn_bug(enemy)


func _spawn_bug(enemy: Node2D) -> void:
	if GameState == null or not (GameState.run is Dictionary) or get_tree() == null:
		return
	if ENEMY_SCENE == null:
		return
	var bug := ENEMY_SCENE.instantiate() as Node2D
	if bug == null or not bug.has_method("setup"):
		return
	bug.call("setup", "bomber", int(GameState.run.get("level", 1)), int(GameState.run.get("loop", 1)))
	bug.global_position = enemy.global_position + Vector2(randf_range(-12.0, 12.0), randf_range(-12.0, 12.0))
	bug.scale = Vector2.ONE * 0.6
	bug.set("hp", 30.0)
	bug.set("max_hp", 30.0)
	bug.set("attack", maxi(int(bug.get("attack")), 5))
	var parent := enemy.get_parent()
	if is_instance_valid(parent):
		parent.add_child(bug)
	elif get_tree().current_scene != null:
		get_tree().current_scene.add_child(bug)


# ================= 钩子：projectile_hit（毒M5 / 毒10） =================

func _on_projectile_hit(ctx: Dictionary) -> void:
	if not is_inside_tree():
		return
	if not (ctx is Dictionary):
		return
	var enemy := ctx.get("enemy") as Node2D
	if not is_instance_valid(enemy):
		return
	var n := _poison_power()
	if n < 1:
		return
	# 毒M5 毒刃：攻击附加 1 层毒（每 2 层构筑 +1；淬毒刃油每 2 层 +1）
	if _can_apply_poison(enemy):
		var added := 1 + int((float(n) + float(_stacks_of("poison_blade_oil"))) / 2.0)
		EventBus.apply_status.emit(enemy, "poison", mini(added, _poison_cap()))
	# 毒10 瘟疫预言：对中毒目标追加暴击判定（每层 +5%，上限 50%）
	var omen: int = _stacks_of("poison_omen")
	if omen > 0 and _is_poisoned(enemy, enemy.get_instance_id()):
		var chance := minf(0.05 * float(omen), 0.50)
		if randf() < chance:
			var dmg: int = int(ctx.get("dmg", 0))
			var crit_bonus := 0.5
			if GameState != null:
				crit_bonus = float(GameState.run.get("crit_dmg_bonus", 1.5)) - 1.0
			var extra := maxi(int(dmg * crit_bonus), 1)
			if enemy.has_method("take_damage"):
				enemy.call("take_damage", extra, "poison", true)
			EventBus.damage_dealt.emit(extra, enemy.global_position, true)


# ================= 钩子：cast（毒4 攻速 / 毒8 冷却） =================

func _on_cast(ctx: Dictionary) -> void:
	if not is_inside_tree():
		return
	if not (ctx is Dictionary):
		return
	var mods: Variant = ctx.get("mods")
	if not (mods is Dictionary):
		return
	var core: Variant = ctx.get("core")
	if not (core is Dictionary) or str(core.get("element", "")) != "poison":
		return
	var cd_stacks := float(_stacks_of("poison_cd"))
	var haste_stacks := float(_stacks_of("poison_haste"))
	if cd_stacks <= 0.0 and haste_stacks <= 0.0:
		return
	# shell mods 是共享字典：原值存副键，每次施法从原值重算，避免跨施法叠加
	if not mods.has("_poison_cd_orig"):
		mods["_poison_cd_orig"] = float(mods.get("cooldown_mult", 1.0))
	var orig: float = float(mods["_poison_cd_orig"])
	var mult := orig * (1.0 - 0.06 * cd_stacks) * (1.0 - 0.08 * haste_stacks)
	mods["cooldown_mult"] = maxf(mult, 0.3)


# ================= 收尾 =================

## 中毒结束 / 死亡：还原敌人属性并清空全部跟踪状态。
func _cleanup(enemy: Node2D, id: int) -> void:
	if _corroded.has(id) and _orig_armor.has(id) and is_instance_valid(enemy) and enemy.get("armor") != null:
		enemy.set("armor", _orig_armor[id])
	if _weakened.has(id) and _orig_attack.has(id) and is_instance_valid(enemy) and enemy.get("attack") != null:
		enemy.set("attack", _orig_attack[id])
	if _slowed.has(id) and _orig_speed.has(id) and is_instance_valid(enemy) and enemy.get("speed") != null:
		enemy.set("speed", _orig_speed[id])
	_corroded.erase(id)
	_weakened.erase(id)
	_slowed.erase(id)
	_orig_armor.erase(id)
	_orig_attack.erase(id)
	_orig_speed.erase(id)
	_stacks.erase(id)
	_poison_time.erase(id)
	_pending_duration.erase(id)
	_spread_timer.erase(id)
	if is_instance_valid(enemy) and enemy.get("_poison_dps") != null:
		enemy.set("_poison_dps", 0.0)
