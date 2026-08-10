extends Node
## 火系燃烧流机制脚本（10 机制，SynergyRegistry 钩子实现）
## ============================================================
## 挂载方式：由 SynergyRegistry.load_synergy_scripts() 自动扫描
## scripts/synergies/*.gd 并实例化挂树（game_root 或 autoload 亦可），
## _ready() 中自动注册全部回调。
## 强度读取：GameState.total_stacks("fire_xxx")（id 与 items.json 一致）。
## 数值联动：火1 燃烧符/火2 火源晶石 → 伤害乘区；火3 引燃粉 → 概率；
##   火5 灼热核心 → 层数上限；火7 烈焰棱镜 → 范围；火10 火山核心 → 暴击率。
## 防御性约定：所有回调先做对象/树/字段有效性检查；回调内不做可能抛错的
## 操作（GDScript 无 try/except），保证异常只影响本流派、不扩散到其他流派。
## 已知限制（对主线程的接线说明）：
## - enemy.gd 当前 burn tick 只广播 stacks=1，叠层计数由本脚本内部维护
##   （火M4 阈值 = 基础 5 层 + 灼热核心层数）；
## - 攻速目前仅被 DPS 估算/HUD 消费：火M2 结果写入 run.attack_speed_bonus，
##   并同步暴露 run.fire_m2_atk_speed（后续攻速接线的读取点）；
## - 火M8 冷却回复直接作用于玩家 SpellCaster 节点的 _cds 数组（按剩余比例扣减）。

## ===== 机制构筑 id（与 .tools/build_defs/fire.json 的 items 一致）=====
const M1 := "fire_ash_blast"        ## 火M1 灰烬爆炸
const M2 := "fire_passing_flame"    ## 火M2 薪火相传
const M3 := "fire_pyromaniac"       ## 火M3 纵火狂
const M4 := "fire_fire_nova"        ## 火M4 烈焰新星
const M5 := "fire_rain"             ## 火M5 火雨
const M6 := "fire_sulfur"           ## 火M6 硫磺
const M7 := "fire_ash_bringer"      ## 火M7 灰烬使者
const M8 := "fire_forge_heart"      ## 火M8 熔炉之心
const M9 := "fire_undying_flame"    ## 火M9 不灭之火
const M10 := "fire_dragon_breath"   ## 火M10 龙息

## ===== 数值构筑 id（联动读取）=====
const N1 := "fire_ember"            ## 火1 燃烧符
const N2 := "fire_source_crystal"   ## 火2 火源晶石
const N3 := "fire_kindling_powder"  ## 火3 引燃粉
const N5 := "fire_heat_core"        ## 火5 灼热核心
const N7 := "fire_prism"            ## 火7 烈焰棱镜
const N10 := "fire_volcano_core"    ## 火10 火山核心

## ===== 强度常量（克制参考：爆炸范围 60-90px、概率 8-20%）=====
const M1_RADIUS := 70.0       ## 灰烬爆炸基础半径
const M1_DMG := 18.0          ## 灰烬爆炸基础伤害
const M2_CONVERT := 0.08      ## 薪火相传：燃烧伤害的 8% 转攻速
const M2_DURATION := 3.0      ## 薪火相传持续秒数
const M2_CAP := 0.30          ## 薪火相传攻速加成上限
const M3_CHANCE := 0.20       ## 纵火狂基础传染概率
const M3_RADIUS := 110.0      ## 纵火狂传染半径
const M4_THRESHOLD := 5       ## 烈焰新星基础层数上限
const M4_RADIUS := 80.0       ## 烈焰新星引爆半径
const M4_DMG := 25.0          ## 烈焰新星基础伤害
const M5_CHANCE := 0.15       ## 火雨基础触发概率
const M5_STRIKES := 3         ## 火雨落点数
const M6_MULT := 0.5          ## 硫磺：每层 +50% 燃烧时长（1 层即 ×2）
const M7_CRIT := 0.20         ## 灰烬使者：对燃烧目标附加暴击率
const M7_RADIUS := 90.0       ## 灰烬使者点燃半径
const M8_PCT := 0.02          ## 熔炉之心：燃烧敌死亡回复剩余冷却比例
const M9_CHANCE := 0.10       ## 不灭之火基础点燃概率
const M10_DPS := 8.0          ## 龙息火地每秒伤害
const M10_RADIUS := 55.0      ## 龙息火地半径
const M10_DURATION := 1.5     ## 龙息火地持续秒数
const M10_MAX_ZONES := 12     ## 火地上限（防堆积）
const M3_TICK_GAP := 30       ## 纵火狂判定节流（帧，≈0.5s@60fps）
const M4_TICK_GAP := 15       ## 烈焰新星叠层节流（帧，≈0.25s@60fps）

## 龙息火地地面视觉（只加视觉，不动伤害判定）：经 fx_manager 静态工厂实例化
const FxManagerScript := preload("res://scripts/fx/fx_manager.gd")
var _m2_bonus := 0.0          ## 薪火相传当前生效的攻速加成
var _m2_left := 0.0           ## 薪火相传剩余秒数
var _zones: Array = []        ## 龙息火地列表：[{pos, radius, dps, left, tick}]
var _zone_seq := 0            ## 火地唯一 id 计数（重入安全的删除定位用）
var _m3_ticks := {}           ## 纵火狂节流计数（enemy instance_id → 帧数）
var _m4_ticks := {}           ## 烈焰新星叠层节流计数
var _m4_stacks := {}          ## 烈焰新星当前层数（enemy instance_id → 层数）


func _ready() -> void:
	if SynergyRegistry == null:
		push_warning("[FireSynergy] SynergyRegistry 不可用，火系机制未注册")
		return
	SynergyRegistry.register("enemy_died", _on_m1)      ## 灰烬爆炸
	SynergyRegistry.register("enemy_status", _on_m2)    ## 薪火相传
	SynergyRegistry.register("enemy_status", _on_m3)    ## 纵火狂
	SynergyRegistry.register("enemy_status", _on_m4)    ## 烈焰新星
	SynergyRegistry.register("enemy_died", _on_m5)      ## 火雨
	SynergyRegistry.register("enemy_status", _on_m6)    ## 硫磺
	SynergyRegistry.register("projectile_hit", _on_m7)  ## 灰烬使者
	SynergyRegistry.register("enemy_died", _on_m8)      ## 熔炉之心
	SynergyRegistry.register("player_hit", _on_m9)      ## 不灭之火
	SynergyRegistry.register("projectile_hit", _on_m10) ## 龙息
	print("[SYNERGY] fire_synergy registered")


func _exit_tree() -> void:
	## 场景退出时把尚存火地视觉节点一并清收，防泄漏
	for z in _zones:
		_free_zone_fx(z)
	_zones.clear()


func _process(delta: float) -> void:
	if not is_inside_tree():
		return
	_tick_m2(delta)
	_tick_zones(minf(delta, 0.1))
	_prune_trackers()


## ===== 火M1 灰烬爆炸：燃烧中的敌人死亡时爆炸（范围伤害 + 扩散燃烧）=====
func _on_m1(ctx: Dictionary) -> void:
	var stacks := _stacks(M1)
	if stacks <= 0:
		return
	var enemy = ctx.get("enemy")
	if not _burning(enemy):
		return
	var pos := _ctx_pos(ctx, enemy)
	var radius := clampf((M1_RADIUS + 12.0 * float(stacks - 1)) * _area_mult(), 60.0, 120.0)
	var dmg := maxi(int((M1_DMG + 8.0 * float(stacks - 1)) * _fire_dmg_mult()), 1)
	EventBus.fx_explosion.emit(pos, "fire")
	_damage_aoe(pos, radius, dmg, true)  ## 扩散燃烧
	_ignite_zones(pos, radius)           ## 火M10 联动：爆炸引爆火地


## ===== 火M2 薪火相传：燃烧伤害的 8% 转攻速，持续 3s =====
func _on_m2(ctx: Dictionary) -> void:
	if not is_inside_tree():
		return
	var stacks := _stacks(M2)
	if stacks <= 0 or str(ctx.get("kind", "")) != "burn":
		return
	var enemy = ctx.get("enemy")
	if not is_instance_valid(enemy):
		return
	var dps := _fget(enemy, "_burn_dps", 0.0)
	_m2_left = M2_DURATION
	if dps <= 0.0:
		return
	var gain := dps * maxf(float(ctx.get("delta", 0.0)), 0.0) * M2_CONVERT * float(stacks)
	if gain <= 0.0:
		return
	var old := _m2_bonus
	_m2_bonus = minf(_m2_bonus + gain, M2_CAP)
	var add := _m2_bonus - old
	if add <= 0.0:
		return
	## G1/G2 收敛：不再写入 run.attack_speed_bonus（该字段仅 game_state 聚合写入），
	## 只写本脚本读取点 fire_m2_atk_speed，由消费端（spell_caster/melee_attack）求和。
	GameState.run.fire_m2_atk_speed = _m2_bonus
	EventBus.player_stats_changed.emit()


func _tick_m2(delta: float) -> void:
	if _m2_left <= 0.0:
		return
	_m2_left -= delta
	if _m2_left <= 0.0:
		_clear_m2()


func _clear_m2() -> void:
	if _m2_bonus <= 0.0:
		return
	GameState.run.fire_m2_atk_speed = 0.0
	_m2_bonus = 0.0
	EventBus.player_stats_changed.emit()


## ===== 火M3 纵火狂：燃烧目标概率传染附近 1 个未燃烧敌人 =====
func _on_m3(ctx: Dictionary) -> void:
	var stacks := _stacks(M3)
	if stacks <= 0 or str(ctx.get("kind", "")) != "burn":
		return
	var enemy = ctx.get("enemy")
	if not _burning(enemy):
		return
	var eid := _id_of(enemy)
	var n := int(_m3_ticks.get(eid, 0)) + 1
	if n < M3_TICK_GAP:
		_m3_ticks[eid] = n
		return
	_m3_ticks[eid] = 0
	var chance := minf(M3_CHANCE + 0.08 * float(_stacks(N3)) + 0.05 * float(stacks - 1), 0.90)
	if randf() >= chance:
		return
	var target := _random_enemy_near(enemy, M3_RADIUS * _area_mult())
	if target == null:
		return
	EventBus.apply_status.emit(target, "burn", 1)
	EventBus.fx_explosion.emit(_enemy_pos(target), "fire")


## ===== 火M4 烈焰新星：燃烧叠满（基础 5 层 + 灼热核心）自动引爆 =====
func _on_m4(ctx: Dictionary) -> void:
	var stacks := _stacks(M4)
	if stacks <= 0 or str(ctx.get("kind", "")) != "burn":
		return
	var enemy = ctx.get("enemy")
	if not _burning(enemy):
		return
	var eid := _id_of(enemy)
	var n := int(_m4_ticks.get(eid, 0)) + 1
	if n < M4_TICK_GAP:
		_m4_ticks[eid] = n
		return
	_m4_ticks[eid] = 0
	var counter := int(_m4_stacks.get(eid, 0)) + maxi(1, int(ctx.get("stacks", 1)))
	var threshold := M4_THRESHOLD + _stacks(N5)
	if counter < threshold:
		_m4_stacks[eid] = counter
		return
	_m4_stacks[eid] = 0
	var pos := _enemy_pos(enemy)
	var radius := clampf((M4_RADIUS + 10.0 * float(stacks - 1)) * _area_mult(), 60.0, 130.0)
	var dmg := maxi(int((M4_DMG + 12.0 * float(stacks - 1)) * _fire_dmg_mult()), 1)
	EventBus.fx_explosion.emit(pos, "fire")
	_damage_aoe(pos, radius, dmg, false)  ## 范围伤害
	if is_instance_valid(enemy):
		EventBus.apply_status.emit(enemy, "burn", 1)  ## 清空层数后重新点燃，灼烧不断


## ===== 火M5 火雨：击杀燃烧敌人概率召唤 3 发落点爆炸 =====
func _on_m5(ctx: Dictionary) -> void:
	var stacks := _stacks(M5)
	if stacks <= 0:
		return
	var enemy = ctx.get("enemy")
	if not _burning(enemy):
		return
	var chance := minf(M5_CHANCE + 0.05 * float(stacks - 1), 0.60)
	if randf() >= chance:
		return
	var pos := _ctx_pos(ctx, enemy)
	var self_id := get_instance_id()
	var tree := get_tree()
	if tree == null:
		return
	for i in M5_STRIKES:
		var delay := 0.12 * float(i)
		var t := tree.create_timer(delay)
		t.timeout.connect(func():
			var me := instance_from_id(self_id)
			if is_instance_valid(me):
				me._strike(pos, stacks))


func _strike(center: Vector2, stacks: int) -> void:
	var pos := center + Vector2(randf_range(-60.0, 60.0), randf_range(-60.0, 60.0))
	var radius := clampf((50.0 + 8.0 * float(stacks - 1)) * _area_mult(), 40.0, 90.0)
	var dmg := maxi(int((12.0 + 5.0 * float(stacks - 1)) * _fire_dmg_mult()), 1)
	EventBus.fx_explosion.emit(pos, "fire")
	_damage_aoe(pos, radius, dmg, false)


## ===== 火M6 硫磺：燃烧时间翻倍，燃烧中的敌人免疫减速 =====
func _on_m6(ctx: Dictionary) -> void:
	var stacks := _stacks(M6)
	if stacks <= 0 or str(ctx.get("kind", "")) != "burn":
		return
	var enemy = ctx.get("enemy")
	if not is_instance_valid(enemy):
		return
	var mult := minf(1.0 + M6_MULT * float(stacks + 1), 3.0)
	var delta := maxf(float(ctx.get("delta", 0.0)), 0.0)
	## 每 tick 已衰减 delta，补回 delta*(1-1/mult)：净衰减 delta/mult → 时长 ×mult
	var left := _fget(enemy, "_burn_left", 0.0) + delta * (1.0 - 1.0 / mult)
	enemy.set("_burn_left", maxf(left, 0.0))
	if _fget(enemy, "_slow_left", 0.0) > 0.0:
		enemy.set("_slow_left", 0.0)


## ===== 火M7 灰烬使者：对燃烧目标附加暴击，暴击时点燃周围 =====
func _on_m7(ctx: Dictionary) -> void:
	var stacks := _stacks(M7)
	if stacks <= 0:
		return
	var enemy = ctx.get("enemy")
	if not _burning(enemy):
		return
	## 基础 20%/层 + 火10 火山核心联动（暴击伤害本体由主线程数值层结算）
	var bonus := M7_CRIT * float(stacks) + 0.06 * float(_stacks(N10))
	var rolled := bool(ctx.get("crit", false)) or randf() < clampf(bonus, 0.0, 0.85)
	if not rolled:
		return
	var pos := _ctx_pos(ctx, enemy)
	var radius := clampf(M7_RADIUS * _area_mult(), 60.0, 140.0)
	EventBus.fx_explosion.emit(pos, "fire")
	var tree := get_tree()
	if tree == null:
		return
	for e in GameState.get_enemies():
		if e == enemy or not is_instance_valid(e) or not (e is Node2D):
			continue
		if _fget(e, "_burn_left", 0.0) > 0.0:
			continue
		var node := e as Node2D
		if pos.distance_to(node.global_position) <= radius + node.scale.x * 8.0:
			EventBus.apply_status.emit(e, "burn", 1)


## ===== 火M8 熔炉之心：燃烧敌人死亡时回复 2% 技能冷却（全法术）=====
func _on_m8(ctx: Dictionary) -> void:
	var stacks := _stacks(M8)
	if stacks <= 0:
		return
	var enemy = ctx.get("enemy")
	if not _burning(enemy):
		return
	var pct := minf(M8_PCT * float(stacks), 0.15)
	var sc := _find_spell_caster()
	if sc == null:
		return
	var cds_v = sc.get("_cds")
	if not (cds_v is Array) or cds_v.is_empty():
		return
	var cds: Array = cds_v
	for i in cds.size():
		var cur := float(cds[i])
		if cur > 0.0:
			cds[i] = maxf(cur * (1.0 - pct), 0.0)


## ===== 火M9 不灭之火：玩家受击时概率点燃攻击者 =====
func _on_m9(ctx: Dictionary) -> void:
	var stacks := _stacks(M9)
	if stacks <= 0:
		return
	var attacker: Node = ctx.get("attacker")
	if not is_instance_valid(attacker):
		## 当前 game_root 广播 attacker=null：回退为受击点最近敌人
		attacker = _nearest_enemy(ctx.get("pos", Vector2.ZERO))
	if not is_instance_valid(attacker):
		return
	var chance := minf(M9_CHANCE + 0.08 * float(_stacks(N3)), 0.85)  ## 火3 联动
	if randf() >= chance:
		return
	EventBus.apply_status.emit(attacker, "burn", maxi(stacks, 1))
	EventBus.fx_explosion.emit(_enemy_pos(attacker), "fire")


## ===== 火M10 龙息：火系弹幕命中后留下 1.5s 火地（持续伤害）=====
func _on_m10(ctx: Dictionary) -> void:
	var stacks := _stacks(M10)
	if stacks <= 0 or str(ctx.get("element", "")) != "fire":
		return
	var enemy = ctx.get("enemy")
	var pos := _ctx_pos(ctx, enemy)
	var radius := clampf((M10_RADIUS + 8.0 * float(stacks - 1)) * _area_mult(), 45.0, 100.0)
	if _zones.size() >= M10_MAX_ZONES:
		var oldest: Dictionary = _zones.pop_front()
		_free_zone_fx(oldest)
	_zone_seq += 1
	_zones.append({
		"id": _zone_seq,
		"pos": pos,
		"radius": radius,
		"dps": maxf(M10_DPS + 4.0 * float(stacks - 1), 1.0),
		"left": M10_DURATION,
		"tick": 0.25,
		"fx": FxManagerScript.spawn_ground_fx("fire", pos, radius, M10_DURATION),
	})


func _tick_zones(dt: float) -> void:
	if _zones.is_empty():
		return
	## P2-4 修复：快照迭代 + 按 id 删除。_zone_hit → 敌人死亡 → 火M1 灰烬爆炸会
	## 重入 _ignite_zones 改写 _zones（还可能触发火M10 上限 pop_front 前移索引），
	## 旧版按调用时的下标继续访问/remove_at 会越界。逐条处理前先确认该 zone 仍存在。
	for z in _zones.duplicate():
		if not _zone_exists(z):
			continue
		z["left"] = float(z["left"]) - dt
		z["tick"] = float(z["tick"]) - dt
		if float(z["tick"]) <= 0.0:
			z["tick"] = 0.25
			_zone_hit(z)
		if float(z["left"]) <= 0.0:
			_free_zone_fx(z)
			_remove_zone(z)


func _free_zone_fx(z: Dictionary) -> void:
	## 火地视觉随区域结束释放（节点自身也带自计时兜底，双保险）
	var fx = z.get("fx")
	if fx != null and is_instance_valid(fx):
		fx.queue_free()


func _zone_hit(z: Dictionary) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var pos: Vector2 = z["pos"]
	var radius := float(z["radius"])
	var dmg := maxi(int(float(z["dps"]) * 0.25), 1)
	for e in GameState.get_enemies():
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		if _iget(e, "_dead", false):
			continue
		var node := e as Node2D
		if pos.distance_to(node.global_position) <= radius + node.scale.x * 8.0:
			if e.has_method("take_damage"):
				e.take_damage(dmg, "fire", false)
				EventBus.damage_dealt.emit(dmg, node.global_position, false)


## ===== 火M1 × 火M10 联动：灰烬爆炸引爆范围内的火地（剩余伤害一半立即结算）=====
func _ignite_zones(center: Vector2, radius: float) -> void:
	if _zones.is_empty():
		return
	## P2-4 修复：同上（_damage_aoe → 敌人死亡 → 火M1 → 重入本函数时旧下标失效）。
	## 先按 id 摘除再结算伤害，重入方不会对同一 zone 二次引爆/二次释放。
	for z in _zones.duplicate():
		if not _zone_exists(z):
			continue
		var zpos: Vector2 = z["pos"]
		if zpos.distance_to(center) <= radius + float(z["radius"]):
			_remove_zone(z)
			_free_zone_fx(z)
			var burst := maxi(int(float(z["dps"]) * maxf(float(z["left"]), 0.0) * 0.5), 1)
			if burst > 0:
				_damage_aoe(zpos, float(z["radius"]), burst, false)


func _zone_exists(z: Dictionary) -> bool:
	## 按唯一 id 确认 zone 仍在列表中（重入可能已删除/替换）
	var zid := int(z.get("id", -1))
	if zid < 0:
		return false
	for other in _zones:
		if int(other.get("id", -1)) == zid:
			return true
	return false


func _remove_zone(z: Dictionary) -> void:
	## 按唯一 id 删除（索引可能已被重入修改，定位后 remove_at 保证不越界）
	var zid := int(z.get("id", -1))
	if zid < 0:
		return
	for i in _zones.size():
		if int(_zones[i].get("id", -1)) == zid:
			_zones.remove_at(i)
			return


## ===== 工具函数（全部防御性）=====

func _stacks(id: String) -> int:
	if GameState == null or not GameState.has_method("total_stacks"):
		return 0
	return maxi(int(GameState.total_stacks(id)), 0)


func _curve_value(id: String) -> float:
	if GameState == null:
		return 0.0
	var def: Dictionary = GameState.item_def(id)
	if def.is_empty():
		return 0.0
	return float(GameState.item_value(def, _stacks(id)))


## 火1 × 火2 伤害乘区
func _fire_dmg_mult() -> float:
	return (1.0 + _curve_value(N1)) * (1.0 + _curve_value(N2))


## 火7 范围乘区
func _area_mult() -> float:
	return 1.0 + _curve_value(N7)


func _burning(enemy) -> bool:
	return is_instance_valid(enemy) and _fget(enemy, "_burn_left", 0.0) > 0.0


func _id_of(enemy) -> int:
	return enemy.get_instance_id() if is_instance_valid(enemy) else 0


func _enemy_pos(enemy) -> Vector2:
	if is_instance_valid(enemy) and enemy is Node2D:
		return (enemy as Node2D).global_position
	return Vector2.ZERO


func _ctx_pos(ctx: Dictionary, enemy) -> Vector2:
	if ctx.has("pos") and ctx.get("pos") is Vector2:
		return ctx.get("pos")
	return _enemy_pos(enemy)


func _find_spell_caster() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var player := tree.get_first_node_in_group("player")
	if player == null:
		return null
	return player.get_node_or_null("SpellCaster")


func _nearest_enemy(pos: Vector2) -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var best: Node = null
	var best_d := INF
	for e in GameState.get_enemies():
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		var d: float = pos.distance_to((e as Node2D).global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


func _random_enemy_near(source, radius: float) -> Node:
	var tree := get_tree()
	if tree == null or not is_instance_valid(source) or not (source is Node2D):
		return null
	var src := source as Node2D
	var pool: Array = []
	for e in GameState.get_enemies():
		if e == source or not is_instance_valid(e) or not (e is Node2D):
			continue
		if _iget(e, "_dead", false):
			continue
		if _fget(e, "_burn_left", 0.0) > 0.0:
			continue
		var node := e as Node2D
		if src.global_position.distance_to(node.global_position) <= radius:
			pool.append(e)
	if pool.is_empty():
		return null
	return pool[randi() % pool.size()]


func _damage_aoe(center: Vector2, radius: float, dmg: int, spread_burn: bool) -> int:
	var tree := get_tree()
	if tree == null:
		return 0
	var hits := 0
	for e in GameState.get_enemies():
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		if _iget(e, "_dead", false):
			continue
		var node := e as Node2D
		if center.distance_to(node.global_position) > radius + node.scale.x * 8.0:
			continue
		if e.has_method("take_damage"):
			e.take_damage(dmg, "fire", false)
			EventBus.damage_dealt.emit(dmg, node.global_position, false)
			hits += 1
		if spread_burn:
			EventBus.apply_status.emit(e, "burn", 1)
	return hits


func _prune_trackers() -> void:
	if _m3_ticks.size() <= 256 and _m4_ticks.size() <= 256 and _m4_stacks.size() <= 256:
		return
	for d in [_m3_ticks, _m4_ticks, _m4_stacks]:
		var dead: Array = []
		for k in d:
			if not is_instance_valid(instance_from_id(int(k))):
				dead.append(k)
		for k in dead:
			d.erase(k)


## Object.get 只接受 1 参数（2 参数默认值仅 Dictionary.get 支持）：
## 对 Variant 对象统一走这里安全取值。
func _fget(obj, prop: String, def: float) -> float:
	if obj == null:
		return def
	var v = obj.get(prop)
	if v == null:
		return def
	return float(v)


func _iget(obj, prop: String, def: bool) -> bool:
	if obj == null:
		return def
	var v = obj.get(prop)
	if v == null:
		return def
	return bool(v)
