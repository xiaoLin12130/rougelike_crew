extends Node
## 雷系连锁流 · 机制脚本（雷M1 麻痹 ~ 雷M10 高压电网）
## 用法：本节点加入场景树后自动向 SynergyRegistry 注册钩子回调
##      （建议主线程挂到 game_root 等持久节点，存活期 = 一局流程）。
## 强度控制：全部机制数值由持有 thunder_ 前缀构筑的堆叠数驱动
##      （GameState.run.items 中 id 以 thunder_ 开头的条目总堆叠）。
## 防御约定：回调全部做空值/类型/存活检查，任何异常只影响本流派、不崩游戏。
## 闪电判定：ctx.element == "lightning"（弹幕本体与闪电链跳都走 projectile_hit 钩子）。
## 麻痹实现：复用 EnemyBase._root_left（定身 = 无法行动），
##      _slow_left / _root_left / _blind_left 等字段均按同模式防御读写。

const PREFIX := "thunder_"
const BASE_LIGHTNING_DMG := 18.0  # 参考 spells.json 闪电核心 base_damage = 18

# 雷区地面视觉（只加视觉，不动伤害判定）：经 fx_manager 静态工厂实例化
const FxManagerScript := preload("res://scripts/fx/fx_manager.gd")

# ---- 雷M1 麻痹：概率克制区间 6%–15%（每层 M1 基础 6%，雷4 麻痹针 +6%/层，上限 15%）----
const PARALYZE_CHANCE_PER := 0.06
const PARALYZE_CHANCE_CAP := 0.15
const PARALYZE_BASE_TIME := 1.0
# ---- 雷M2 雷暴：击杀敌人 12% 降雷（范围闪电）----
const STORM_KILL_PROC := 0.12
const STORM_STRIKE_RADIUS := 76.0
# ---- 雷M3 静电积累：移动充能，满 100 自动释放电弧 ----
const STATIC_CHARGE_MAX := 100.0
const STATIC_CHARGE_RATE := 0.30
# ---- 雷M4 过载：麻痹持续时间 +0.5s/层，麻痹目标受击必暴击 ----
const OVERLOAD_EXTEND_PER := 0.5
# ---- 雷M5 导雷：附近敌人每 3s 受到微型闪电（40% 伤害）----
const CONDUIT_INTERVAL := 3.0
const CONDUIT_DMG_RATIO := 0.40
const CONDUIT_RADIUS := 220.0
# ---- 雷M6 雷暴回响：链跳每命中 1 个敌人回复 1% 技能冷却 ----
const ECHO_CD_REFUND := 0.01
# ---- 雷M7 电磁脉冲：链跳 10% 致盲目标 1.5s ----
const EMP_BLIND_PROC := 0.10
const EMP_BLIND_TIME := 1.5
# ---- 雷M8 超载线圈：闪电命中同目标 3 次后爆炸 ----
const OVERLOAD_HITS_NEEDED := 3
const OVERLOAD_RADIUS := 64.0
# ---- 雷M9 雷云风暴：场上每 5s 随机降雷 1 道/层（上限 12 道，防极端场景卡顿）----
const STORM_INTERVAL := 5.0
const STORM_MAX_STRIKES := 12
const STORM_CLOUD_RADIUS := 44.0
# ---- N2 雷云（storm_cloud）：每 3s 落雷（数值道具修复）----
const STORM_CLOUD_INTERVAL := 3.0
# ---- 雷M10 高压电网：被麻痹敌人死亡时连锁电爆 ----
const GRID_AOE_RADIUS := 70.0
const GRID_AOE_DMG_RATIO := 0.8
const GRID_CHAIN_DMG_RATIO := 0.5
# ---- 连锁通用：雷2 静电力场（跳数）/ 雷3 导线（距离）/ 雷6 高压（递减）/ 雷7 避雷针（精英优先）/ 雷9 电荷（叠乘）----
const CHAIN_RANGE_BASE := 160.0
const CHAIN_RANGE_PER := 20.0
const CHAIN_FALLOFF_BASE := 0.70  # 连锁递减 30%（每跳保留 70%）
const CHAIN_FALLOFF_PER := 0.05   # 高压：每层递减再降 5%（保留 +5%）
const CHAIN_FALLOFF_CAP := 0.80   # 递减下限 20%（每跳保留 80%）
const CHARGE_MULT_PER := 1.04     # 电荷：每跳伤害 ×1.04 叠乘

var _reg: Node = null
var _registered := {}  # kind -> Callable（注销用）
var _static_charge := 0.0
var _conduit_timer := 0.0
var _storm_timer := 0.0
var _storm_cloud_timer := 0.0
var _overload_hits := {}  # enemy instance_id -> 雷M8 已命中次数
var _crit_guard := {}     # enemy instance_id -> true（雷M4 防递归）


func _ready() -> void:
	if not is_inside_tree():
		return
	_reg = get_node_or_null("/root/SynergyRegistry")
	_register("enemy_died", _on_enemy_died)
	_register("enemy_hit", _on_enemy_hit)
	_register("projectile_hit", _on_projectile_hit)
	_register("player_move", _on_player_move)


func _exit_tree() -> void:
	_unregister_all()


func _process(delta: float) -> void:
	_tick_conduit(delta)
	_tick_storm(delta)
	_tick_storm_cloud(delta)


## ===================== 注册 / 注销 =====================

func _register(kind: String, cb: Callable) -> void:
	if _reg == null or not _reg.has_method("register"):
		return
	_reg.register(kind, cb)
	_registered[kind] = cb


func _unregister_all() -> void:
	if _reg == null:
		return
	var hooks = _reg.get("_hooks")
	if hooks == null:
		return
	for kind in _registered:
		var arr = hooks.get(kind)
		if arr is Array:
			arr.erase(_registered[kind])
	_registered.clear()


## ===================== 通用读取（防御式） =====================

func _enabled() -> bool:
	return is_inside_tree() and _reg != null


func _game_state() -> Node:
	return get_node_or_null("/root/GameState")


func _event_bus() -> Node:
	return get_node_or_null("/root/EventBus")


func _run_items() -> Dictionary:
	var gs := _game_state()
	if gs == null:
		return {}
	var run = gs.get("run")
	if run == null or not (run is Dictionary):
		return {}
	var items = run.get("items")
	if items == null or not (items is Dictionary):
		return {}
	return items


## 指定构筑（含 thunder_ 前缀机制/数值）的堆叠数
func _stacks(item_id: String) -> int:
	var n = _run_items().get(item_id, 0)
	return maxi(int(n), 0)


## 持有 thunder_ 前缀构筑的总堆叠数（机制强度主驱动）
func _thunder_stacks() -> int:
	var total := 0
	var items := _run_items()
	for item_id in items:
		if str(item_id).begins_with(PREFIX):
			total += maxi(int(items[item_id]), 0)
	return total


## ===================== 钩子回调 =====================

## projectile_hit：闪电元素命中 = 链跳命中（弹幕本体 + 链跳都经过此钩子）
## 承载：雷M1 麻痹 / 雷M4 时长 / 雷M6 回响 / 雷M7 电磁脉冲 / 雷M8 超载线圈
func _on_projectile_hit(ctx: Dictionary) -> void:
	if not _enabled():
		return
	if str(ctx.get("element", "")) != "lightning":
		return
	var enemy = ctx.get("enemy")
	if not _alive_enemy(enemy):
		return
	# 雷M6 雷暴回响：链跳每命中 1 个敌人回复 1% 技能冷却
	if _stacks("thunder_m6") > 0:
		_refund_caster_cd()
	# 雷M1 麻痹：概率 = 6%×M1层 + 6%×雷4层，克制区间 6%–15%
	if _stacks("thunder_m1") > 0:
		var chance := clampf(
			PARALYZE_CHANCE_PER * _stacks("thunder_m1") + PARALYZE_CHANCE_PER * _stacks("thunder_4"),
			0.0, PARALYZE_CHANCE_CAP)
		if randf() < chance:
			_apply_paralysis(enemy, _paralyze_duration())
	# 雷M7 电磁脉冲：10% 致盲 1.5s
	if _stacks("thunder_m7") > 0 and randf() < EMP_BLIND_PROC:
		_apply_status_time(enemy, "_blind_left", EMP_BLIND_TIME)
	# 雷M8 超载线圈：同目标累计 3 次命中后爆炸（范围闪电，清计数）
	if _stacks("thunder_m8") > 0:
		var id: int = enemy.get_instance_id()
		var n := int(_overload_hits.get(id, 0)) + 1
		if n >= OVERLOAD_HITS_NEEDED:
			_overload_hits.erase(id)
			_strike(ctx.get("pos", enemy.global_position), OVERLOAD_RADIUS, maxi(roundi(_bolt_dmg()), 1))
		else:
			_overload_hits[id] = n


## enemy_hit：雷M4 过载——麻痹目标受击必暴击（非暴击时补足暴击差额）
func _on_enemy_hit(ctx: Dictionary) -> void:
	if not _enabled() or _stacks("thunder_m4") <= 0:
		return
	var enemy = ctx.get("enemy")
	if not _alive_enemy(enemy):
		return
	if bool(ctx.get("crit", false)):
		return
	if _field(enemy, "_root_left") <= 0.0:
		return
	var id: int = enemy.get_instance_id()
	if _crit_guard.has(id):
		return
	var dmg := int(ctx.get("dmg", 0))
	if dmg <= 0:
		return
	var gs := _game_state()
	var crit_mult := 1.5
	if gs != null:
		var run = gs.get("run")
		if run is Dictionary:
			crit_mult = float(run.get("crit_dmg_bonus", 1.5))
	var bonus := maxi(roundi(float(dmg) * (crit_mult - 1.0)), 1)
	_crit_guard[id] = true
	enemy.take_damage(bonus, "lightning", true)
	if is_instance_valid(enemy):
		_crit_guard.erase(id)


## enemy_died：雷M2 雷暴 / 雷M10 高压电网（并清理计数）
func _on_enemy_died(ctx: Dictionary) -> void:
	if not _enabled():
		return
	var enemy = ctx.get("enemy")
	if not is_instance_valid(enemy):
		return
	var id: int = enemy.get_instance_id()
	_overload_hits.erase(id)
	_crit_guard.erase(id)
	var pos: Vector2 = ctx.get("pos", enemy.global_position)
	# 雷M10 高压电网：被麻痹敌人死亡时连锁电爆（范围电爆 + 链跳）
	if _stacks("thunder_m10") > 0 and _field(enemy, "_root_left") > 0.0:
		_strike(pos, GRID_AOE_RADIUS, maxi(roundi(_bolt_dmg() * GRID_AOE_DMG_RATIO), 1))
		_chain_burst(pos, _chain_range(), _jump_count(),
			maxi(roundi(_bolt_dmg() * GRID_CHAIN_DMG_RATIO), 1), _prefer_elite(), {})
	# 雷M2 雷暴：击杀 12% 降雷（范围闪电，雷1 增伤）
	if _stacks("thunder_m2") > 0 and randf() < minf(STORM_KILL_PROC * _trinket_storm_mult(), 1.0):
		_strike(pos, STORM_STRIKE_RADIUS, maxi(roundi(_bolt_dmg()), 1))


## player_move：雷M3 静电积累——移动充能，满 100 自动释放电弧
func _on_player_move(ctx: Dictionary) -> void:
	if not _enabled() or _stacks("thunder_m3") <= 0:
		return
	var player = ctx.get("player")
	if not is_instance_valid(player):
		return
	var vel: Vector2 = ctx.get("velocity", Vector2.ZERO)
	var delta := maxf(float(ctx.get("delta", 0.016)), 0.0)
	if _static_charge < STATIC_CHARGE_MAX:
		_static_charge = minf(_static_charge + vel.length() * delta * STATIC_CHARGE_RATE, STATIC_CHARGE_MAX)
	if _static_charge < STATIC_CHARGE_MAX:
		return
	# 满充能：无目标时保留充能等待下一帧（避免空放）
	var exclude := {}
	var target := _nearest_enemy(player.global_position, _chain_range(), _prefer_elite(), exclude)
	if target == null:
		return
	_static_charge = 0.0
	_fx_lightning(player.global_position)
	_chain_burst(player.global_position, _chain_range(), _jump_count(),
		_charge_jump_dmg(), _prefer_elite(), exclude)


## ===================== 周期性机制（雷M5 / 雷M9） =====================

func _tick_conduit(delta: float) -> void:
	if _stacks("thunder_m5") <= 0:
		_conduit_timer = 0.0
		return
	_conduit_timer -= delta
	if _conduit_timer > 0.0:
		return
	_conduit_timer = CONDUIT_INTERVAL
	var player := _player()
	if player == null:
		return
	# 微型闪电：40% 基础伤害，从玩家链向附近敌人（雷2 跳数 / 雷6 高压）
	var radius := maxf(_chain_range(), CONDUIT_RADIUS)
	_chain_burst(player.global_position, radius, _jump_count(),
		_bolt_dmg() * CONDUIT_DMG_RATIO, _prefer_elite(), {})


func _tick_storm(delta: float) -> void:
	if _stacks("thunder_m9") <= 0:
		_storm_timer = 0.0
		return
	_storm_timer -= delta
	if _storm_timer > 0.0:
		return
	_storm_timer = STORM_INTERVAL
	# N2 雷核（trinket_storm）：落雷数量翻倍（饰品）
	var strikes := mini(roundi(float(_thunder_stacks()) * _trinket_storm_mult()), STORM_MAX_STRIKES)
	if strikes <= 0:
		return
	var enemies := _enemies_alive()
	if enemies.is_empty():
		return
	enemies.shuffle()
	var n := mini(strikes, enemies.size())
	var bus := _event_bus()
	if bus != null and bus.has_signal("screen_shake"):
		bus.screen_shake.emit(3.0)
	for i in n:
		_strike(enemies[i].global_position, STORM_CLOUD_RADIUS, maxi(roundi(_bolt_dmg()), 1))
		# 雷M9 雷云风暴：落点生成短时电弧闪烁雷区
		FxManagerScript.spawn_ground_fx("thunder", enemies[i].global_position, STORM_CLOUD_RADIUS, 0.55)


## N2 雷云（storm_cloud）：每 3s 落雷，每 2 层 +1 道（阈值曲线，独立于雷M9）
func _tick_storm_cloud(delta: float) -> void:
	var gs := _game_state()
	if gs == null:
		return
	var def: Dictionary = gs.item_def("storm_cloud")
	if def.is_empty() or _stacks("storm_cloud") <= 0:
		_storm_cloud_timer = 0.0
		return
	_storm_cloud_timer -= delta
	if _storm_cloud_timer > 0.0:
		return
	_storm_cloud_timer = STORM_CLOUD_INTERVAL
	var strikes := maxi(int(gs.item_value(def, _stacks("storm_cloud"))), 0)
	if strikes <= 0:
		return
	var enemies := _enemies_alive()
	if enemies.is_empty():
		return
	enemies.shuffle()
	var n := mini(strikes, enemies.size())
	for i in n:
		_strike(enemies[i].global_position, STORM_CLOUD_RADIUS, maxi(roundi(_bolt_dmg()), 1))
		# N2 雷云：落点生成短时电弧闪烁雷区
		FxManagerScript.spawn_ground_fx("thunder", enemies[i].global_position, STORM_CLOUD_RADIUS, 0.55)


## N2 雷核（trinket_storm）：持有 1 件落雷数量/触发率翻倍
func _trinket_storm_mult() -> float:
	var gs := _game_state()
	if gs == null:
		return 1.0
	var n := 0
	for t in gs.run.get("trinkets", []):
		if str(t) == "trinket_storm":
			n += 1
	return 1.0 + float(n)


## ===================== 伤害 / 状态工具 =====================

## 基础雷伤 = 18 × (1 + 10%×雷1 电镀)
func _bolt_dmg() -> float:
	return BASE_LIGHTNING_DMG * (1.0 + 0.10 * _stacks("thunder_1"))


## 链跳伤害 = 基础雷伤 × 1.04^雷9层（电荷叠乘）
func _charge_jump_dmg() -> float:
	return _bolt_dmg() * pow(CHARGE_MULT_PER, _stacks("thunder_9"))


## 连锁跳数 = 1 + 雷2静电力场层数/2（threshold T=2）
func _jump_count() -> int:
	return 1 + int(_stacks("thunder_2") / 2)


## 连锁距离 = 160 + 20×雷3导线层数
func _chain_range() -> float:
	return CHAIN_RANGE_BASE + CHAIN_RANGE_PER * _stacks("thunder_3")


## 每跳保留伤害 = 70% + 5%×雷6高压层数（上限 80%，即递减最低 20%）
func _falloff() -> float:
	return clampf(CHAIN_FALLOFF_BASE + CHAIN_FALLOFF_PER * _stacks("thunder_6"),
		CHAIN_FALLOFF_BASE, CHAIN_FALLOFF_CAP)


## 避雷针（雷7）：持有 1 层后闪电优先精英/Boss
func _prefer_elite() -> bool:
	return _stacks("thunder_7") > 0


## 麻痹时长 = 1s + 0.5s×雷M4过载层数
func _paralyze_duration() -> float:
	return PARALYZE_BASE_TIME + OVERLOAD_EXTEND_PER * _stacks("thunder_m4")


## 范围闪电：命中半径内全部存活敌人（fx + 伤害 + 伤害数字）
func _strike(pos: Vector2, radius: float, dmg: int) -> void:
	if dmg <= 0:
		return
	_fx_lightning(pos)
	for e in _enemies_alive():
		var hit_r: float = radius + float(e.scale.x) * 8.0
		if pos.distance_to(e.global_position) <= hit_r:
			_hit_enemy(e, dmg)


## 闪电链：hits 次依次跳最近未命中敌人，每跳 ×衰减（雷6），目标排除字典防重复
func _chain_burst(from: Vector2, radius: float, hits: int, dmg: float, prefer_elite: bool, exclude: Dictionary) -> void:
	if hits <= 0 or dmg <= 0.0:
		return
	var pos := from
	var d := dmg
	var fx := _fx_manager()  # 链跳电弧视觉：每跳绘制闪电连线（仅视觉，不动伤害）
	for i in hits:
		var target := _nearest_enemy(pos, radius, prefer_elite, exclude)
		if target == null:
			break
		if fx != null and fx.has_method("spawn_chain_bolt"):
			fx.spawn_chain_bolt(pos, target.global_position)
		exclude[target.get_instance_id()] = true
		_hit_enemy(target, maxi(roundi(d), 1))
		pos = target.global_position
		d *= _falloff()


func _hit_enemy(enemy: Node, dmg: int) -> void:
	if not _alive_enemy(enemy) or dmg <= 0:
		return
	if _field(enemy, "_invuln_left") > 0.0:
		return
	enemy.take_damage(dmg, "lightning", false)
	var bus := _event_bus()
	if bus == null:
		return
	if bus.has_signal("damage_dealt"):
		bus.damage_dealt.emit(dmg, enemy.global_position, false)
	if bus.has_signal("fx_hit_flash"):
		bus.fx_hit_flash.emit(enemy)


## 雷M6：从玩家 SpellCaster 节点减冷却（1% 剩余/跳，防御式）
func _refund_caster_cd() -> void:
	var player := _player()
	if player == null:
		return
	var caster = player.get_node_or_null("SpellCaster")
	if caster == null:
		return
	var cds = caster.get("_cds")
	if cds == null or not (cds is Array):
		return
	for i in cds.size():
		var left := float(cds[i])
		if left > 0.0:
			cds[i] = maxf(left * (1.0 - ECHO_CD_REFUND), 0.0)


## 麻痹 = 定身：写入 enemy._root_left（可读写字段，取更长者）
func _apply_paralysis(enemy: Node, duration: float) -> void:
	if not is_instance_valid(enemy):
		return
	var cur = enemy.get("_root_left")
	if cur == null:
		return
	enemy.set("_root_left", maxf(float(cur), duration))
	# 麻痹视觉标记（enemy 侧仅视觉字段，驱动蓝白闪烁 + 定身图标；不动机制参数）
	if enemy.get("_paralyze_left") != null:
		enemy.set("_paralyze_left", maxf(float(enemy.get("_paralyze_left")), duration))


## 通用状态时长写入（_slow_left/_root_left/_blind_left 同模式）
func _apply_status_time(enemy: Node, field: String, duration: float) -> void:
	if not is_instance_valid(enemy):
		return
	var cur = enemy.get(field)
	if cur == null:
		return
	enemy.set(field, maxf(float(cur), duration))


func _fx_lightning(pos: Vector2) -> void:
	var bus := _event_bus()
	if bus != null and bus.has_signal("fx_explosion"):
		bus.fx_explosion.emit(pos, "lightning")
	# 落雷视觉强化：闪电柱 + 底部地面电弧溅射（FxManager 渲染，仅视觉）
	var fx := _fx_manager()
	if fx != null and fx.has_method("spawn_strike_arcs"):
		fx.spawn_strike_arcs(pos)


func _fx_manager() -> Node:
	## 查找 FxManager（game_root 子节点；测试场景由测试自行挂载同名节点）。
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene.get_node_or_null("FxManager")


## ===================== 敌人 / 玩家查找 =====================

func _player() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var p := tree.get_first_node_in_group("player")
	if p != null and is_instance_valid(p):
		return p
	return null


func _enemies_alive() -> Array:
	var tree := get_tree()
	if tree == null:
		return []
	var out: Array = []
	for e in tree.get_nodes_in_group("enemy"):
		if _alive_enemy(e):
			out.append(e)
	return out


func _alive_enemy(e: Node) -> bool:
	if e == null or not is_instance_valid(e):
		return false
	if not e.has_method("take_damage"):
		return false
	var dead = e.get("_dead")
	if dead != null and bool(dead):
		return false
	return _field(e, "hp") > 0.0


## Object.get 单参读取 + null 兜底（防御式字段读取）
func _field(node: Node, key: String, fallback: float = 0.0) -> float:
	if node == null or not is_instance_valid(node):
		return fallback
	var v = node.get(key)
	if v == null:
		return fallback
	return float(v)


## 最近未命中敌人；避雷针（prefer_elite）时优先精英/Boss
func _nearest_enemy(from: Vector2, radius: float, prefer_elite: bool, exclude: Dictionary) -> Node:
	var best: Node = null
	var best_d := INF
	for e in _enemies_alive():
		var id: int = e.get_instance_id()
		if exclude.has(id):
			continue
		var d: float = from.distance_to(e.global_position)
		if d <= radius and d < best_d:
			best_d = d
			best = e
	if best == null or not prefer_elite:
		return best
	var elite_best: Node = null
	var elite_d := INF
	for e in _enemies_alive():
		var id: int = e.get_instance_id()
		if exclude.has(id):
			continue
		var is_elite = e.get("is_elite")
		var is_boss = e.get("is_boss")
		if not ((is_elite != null and bool(is_elite)) or (is_boss != null and bool(is_boss))):
			continue
		var d: float = from.distance_to(e.global_position)
		if d <= radius and d < elite_d:
			elite_d = d
			elite_best = e
	if elite_best != null:
		return elite_best
	return best
