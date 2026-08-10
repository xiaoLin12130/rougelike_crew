extends Node
## 常驻近战攻击（N7 方案 A）：玩家身边自动挥砍最近存活敌人。
## 挂载：player.gd _ready() → _mount_melee()，纯代码挂载（与 _mount_aura 同模式，不进场景文件）。
## 定位：独立常驻层，与远程法术自动施法共存；whirl_blade 作为近战流强化手段保留。
##
## 数值：
##   基础伤害 8（≈ 火球 12 的 2/3）× (1 + atk 聚合) × 暴击倍率，元素 "blade"；
##   melee_1（+15%/层）等数值由 melee_synergy 在 projectile_hit 钩子里以追加伤害聚合
##   （见 melee_synergy._blade_extra），此处不重复计入，避免双重叠加；
##   攻击间隔 0.8s / (1 + run.attack_speed_bonus)，attack_speed_bonus 由
##   GameState.apply_item_effects_to_stats（物品聚合）与 melee_synergy._sync_as（m3/m9）共同维护。
##
## 钩子：SynergyRegistry.trigger("projectile_hit", {enemy, dmg, element:"blade", crit, pos})
##   → melee_synergy 的 m1 旋风斩 / m4 战意 / m7 破甲斩 / m10 处决 + n1/n2/n8/n10 生效。
## 视觉：EventBus.fx_cast(player, "blade", dir) + fx_hit / fx_hit_flash，不 new 粒子。

const BASE_DAMAGE := 8.0
const BASE_INTERVAL := 0.8
const MELEE_RADIUS := 48.0

## 攻速全局接线（G1/G2 收敛）：与 spell_caster._SYNERGY_AS_KEYS 同步维护，
## 基础聚合（run.attack_speed_bonus）+ 各流派贡献读取点之和（近战与法术同公式）。
const _SYNERGY_AS_KEYS := [
	"fire_m2_atk_speed",   ## 火M2 薪火相传
	"melee_m3_as_bonus",   ## 近M3 血之狂暴
	"melee_m9_as_bonus",   ## 近M9 狂化
	"wind_as_bonus",       ## 移2/移5 移速→攻速联动
	"wind_m2_atk_speed",   ## 移M2 踏风
	"wind_m10_as_bonus",   ## 移M10 暴走
]

var _cooldown_left := 0.0


func _physics_process(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	var player := get_parent()
	if not is_instance_valid(player) or not (player is Node2D):
		return
	var enemy := _nearest_enemy_in_range((player as Node2D).global_position)
	if enemy == null or _cooldown_left > 0.0:
		return
	_cooldown_left = _interval()
	_swing(player as Node2D, enemy)


## 攻击间隔：0.8 / (1 + 攻速聚合)；m3/m9 由 melee_synergy 写入 run.attack_speed_bonus。
func _interval() -> float:
	var as_bonus := 0.0
	if GameState != null and (GameState.run is Dictionary):
		as_bonus = maxf(float(GameState.run.get("attack_speed_bonus", 0.0)), 0.0)
		for key in _SYNERGY_AS_KEYS:
			as_bonus += maxf(float(GameState.run.get(key, 0.0)), 0.0)
	return BASE_INTERVAL / (1.0 + as_bonus)


## 自动索敌：group "enemy" 中最近存活敌人（参考 projectile._enemies_in_radius / melee_synergy）。
## 命中判定带体型放大（+scale.x × 8），与 projectile 一致；过滤 _dead / hp<=0。
func _nearest_enemy_in_range(center: Vector2) -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var best: Node = null
	var best_d := INF
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		var dead: Variant = e.get("_dead")
		if dead != null and bool(dead):
			continue
		var hp_v: Variant = e.get("hp")
		if hp_v == null or float(hp_v) <= 0.0:
			continue
		var node := e as Node2D
		var d: float = center.distance_to(node.global_position)
		if d <= MELEE_RADIUS + node.scale.x * 8.0 and d < best_d:
			best_d = d
			best = e
	return best


func _swing(player: Node2D, enemy: Node) -> void:
	var enemy2d := enemy as Node2D
	if enemy2d == null:
		return
	var hit_pos: Vector2 = enemy2d.global_position
	var dir := hit_pos - player.global_position
	if dir.length_squared() <= 0.001:
		dir = Vector2.DOWN
	else:
		dir = dir.normalized()
	var crit := _roll_crit()
	var mult := _crit_dmg_bonus() if crit else 1.0
	var atk_bonus := 0.0
	if GameState != null and GameState.has_method("aggregate_bonus"):
		atk_bonus = maxf(float(GameState.aggregate_bonus("atk")), 0.0)
	var dmg := maxi(roundi(BASE_DAMAGE * (1.0 + atk_bonus) * mult), 1)
	EventBus.fx_cast.emit(player.global_position, "blade", dir)
	## 与 projectile._hit_enemy 同序：先触发钩子（melee_synergy 在此聚合 melee_1 等），再结算本体
	if SynergyRegistry != null:
		SynergyRegistry.trigger("projectile_hit", {
			"enemy": enemy, "dmg": dmg, "element": "blade", "crit": crit, "pos": hit_pos,
		})
	## m10 处决可能在钩子内直接击杀（_dead=true 并 queue_free），此时跳过本体结算
	if not is_instance_valid(enemy):
		return
	var dead: Variant = enemy.get("_dead")
	if dead != null and bool(dead):
		return
	if enemy.has_method("take_damage"):
		enemy.take_damage(dmg, "blade", crit)
	EventBus.damage_dealt.emit(dmg, hit_pos, crit)
	EventBus.fx_hit_flash.emit(enemy)
	EventBus.fx_hit.emit(hit_pos, "blade")


## 暴击判定：run.crit_chance（含 crit_glasses 等）+ 四叶草重掷，与 projectile._roll_crit 一致
## （blade 无元素暴击加成，thunder_10 / water_tide_power 不适用）。
func _roll_crit() -> bool:
	var chance := 0.03
	if GameState != null and (GameState.run is Dictionary):
		chance = clampf(float(GameState.run.get("crit_chance", 0.03)), 0.0, 1.0)
	var crit := randf() < chance
	if not crit and GameState != null and GameState.has_method("item_def") \
			and GameState.has_method("item_value") and GameState.has_method("total_stacks"):
		# 0 层守卫：exp_proc 曲线在 0 层返回 p（base），不加守卫会白送重掷概率
		var clover_stacks := GameState.total_stacks("lucky_clover")
		if clover_stacks > 0:
			var clover := GameState.item_def("lucky_clover")
			if not clover.is_empty():
				var reroll := float(GameState.item_value(clover, clover_stacks))
				if reroll > 0.0 and randf() < reroll:
					crit = randf() < chance
	return crit


func _crit_dmg_bonus() -> float:
	if GameState != null and (GameState.run is Dictionary):
		return float(GameState.run.get("crit_dmg_bonus", 1.5))
	return 1.5
