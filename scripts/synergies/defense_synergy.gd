extends Node
## 防御流机制脚本（10 机制，SynergyRegistry 钩子实现）
## ============================================================
## 挂载方式：由 SynergyRegistry.load_synergy_scripts() 自动扫描
## scripts/synergies/*.gd 并实例化挂树，_ready() 中自动注册全部回调。
## 强度读取：GameState.total_stacks("defense_xxx")（id 与 .tools/build_defs/defense.json 一致）。
## 数值克制（防无敌，用户约定）：
## - 减伤 3-6%/层，上限 20-35%（防1 磐石护甲 6%/35%、防4 铁壁 3%/20%）
## - 反弹吸血 1-2%/层（防3 血棘甲 2%、防M4 反甲吸血 1%/2层，各封顶 4%）
## - 金身：生命 <30% 时 3s 无敌，冷却 30s
## - 护盾吸收 ≤ 25% 最大生命（防M6 吸收 与 防M3 护盾回响共用护盾池）
## 实现约定：
## - player_hit 钩子在 game_root 扣血后触发（ctx.taken = 结算后伤害），
##   减伤/护盾/硬化采用"钩子侧补结"（GameState.heal 退款已扣伤害）；
##   金身写玩家 _invuln_left（本回调晚于扣血、早于死亡判定，可挡致死）。
## - 反弹体系：game_root 只按旧 id（thorn_reflect）结算反弹；本脚本按同款
##   公式估算总反弹（含新 defense_ 数值构筑），并补发新构筑对应的反弹伤害
##   与吸血，保证 defense_thorn_refit / defense_blood_thorn 端到端生效。
## - 所有回调防御性编写（不做可能抛错的裸取字段，异常只影响本流派）。

## ===== 机制构筑 id（与 .tools/build_defs/defense.json 的 items 一致）=====
const M1 := "defense_thorn_field"        ## 防M1 荆棘领域
const M2 := "defense_shield_counter"     ## 防M2 盾反
const M3 := "defense_shield_echo"        ## 防M3 护盾回响
const M4 := "defense_thorn_leech"        ## 防M4 反甲吸血
const M5 := "defense_unbreakable"        ## 防M5 磐石不破
const M6 := "defense_absorb"             ## 防M6 吸收
const M7 := "defense_harden"             ## 防M7 硬化
const M8 := "defense_taunt"              ## 防M8 嘲讽
const M9 := "defense_vengeance"          ## 防M9 复仇
const M10 := "defense_golden_body"       ## 防M10 金身

## ===== 数值构筑 id（联动读取）=====
const N1 := "defense_bedrock"            ## 防1 磐石护甲
const N2 := "defense_thorn_refit"        ## 防2 荆棘甲改造
const N3 := "defense_blood_thorn"        ## 防3 血棘甲
const N4 := "defense_iron_wall"          ## 防4 铁壁
const N7 := "defense_counter_shock"      ## 防7 反震
const N8 := "defense_shield_battery"     ## 防8 护盾电池
const N10 := "defense_unyielding"        ## 防10 不屈

## ===== 机制常量（克制数值见文件头注释）=====
const M1_CHANCE := 0.12        ## 荆棘领域：基础传染概率
const M1_RADIUS := 130.0       ## 荆棘领域：传染半径
const M2_BONUS := 0.25         ## 盾反：受击后 2s 内全伤害 +25%/层
const M2_CAP := 0.75           ## 盾反：增伤叠加上限
const M2_DURATION := 2.0       ## 盾反：持续秒数
const M3_RADIUS := 130.0       ## 护盾回响：破碎爆炸半径
const M4_LEECH := 0.01         ## 反甲吸血：每 2 层 +1%
const M4_CAP := 0.04           ## 反甲吸血：上限
const M5_DR_THRESHOLD := 0.30  ## 磐石不破：减伤 ≥30% 免疫击退
const M6_CONVERT := 0.30       ## 吸收：反弹伤害的 30% 转护盾
const M6_CONVERT_CAP := 0.50   ## 吸收：转化率上限（随层提升）
const M6_SHIELD_CAP := 0.25    ## 护盾池硬上限：25% 最大生命（克制约束）
const M7_WINDOW := 1.0         ## 硬化：蓄力窗口（0.5s 受击保护 + 余量，保证下一次攻击可触发）
const M7_REDUCE := 0.50        ## 硬化：下一次攻击伤害 -50%
const M8_CHANCE := 0.20        ## 嘲讽：基础吸引概率
const M8_RADIUS := 240.0       ## 嘲讽：吸引半径
const M8_PULL := 80.0          ## 嘲讽：单次牵引距离
const M9_CRIT := 0.02          ## 复仇：每次反弹 +2% 暴击率
const M9_CAP := 0.30           ## 复仇：暴击叠加上限
const M9_DURATION := 3.0       ## 复仇：持续秒数
const M10_HP_PCT := 0.30       ## 金身：触发血线（<30% 最大生命）
const M10_DURATION := 3.0      ## 金身：无敌秒数
const M10_COOLDOWN := 30.0     ## 金身：冷却秒数

## 数值构筑内联回退曲线（items.json 落库前防御性取值，与 defense.json 一致）
## 注意：GameState.item_value 契约接收"完整物品字典"（含 curve 键），
## 裸曲线必须经 {"curve": ...} 包装后再传入（game_root 的反射调用同款写法）。
const C1 := {"type": "linear", "base": 0.06, "k": 0.06, "cap": 0.35}
const C2 := {"type": "linear", "base": 0.30, "k": 0.06, "cap": 0.65}
const C3 := {"type": "linear", "base": 0.02, "k": 0.02, "cap": 0.04}
const C4 := {"type": "linear", "base": 0.03, "k": 0.03, "cap": 0.20}
const C7 := {"type": "threshold", "base": 0.0, "step": 0.10, "threshold": 2}
const C10 := {"type": "threshold", "base": 0.0, "step": 0.10, "threshold": 1}
## 旧 id 曲线（与 game_root._on_player_hit 完全同款）
const OLD_STONE := {"type": "linear", "base": 0.06, "k": 0.06, "cap": 0.35}
const OLD_AMULET := {"type": "linear", "base": 0.03, "k": 0.03, "cap": 0.20}
const OLD_REFLECT := {"type": "linear", "base": 0.40, "k": 0.35, "cap": 0.95}

var _m2_left := 0.0        ## 盾反剩余秒数
var _m2_busy := false      ## 盾反补伤防重入
var _m7_left := 0.0        ## 硬化窗口剩余秒数
var _m7_armed := false     ## 硬化已蓄力（下一次攻击减半）
var _m9_left := 0.0        ## 复仇剩余秒数
var _m9_crit := 0.0        ## 复仇累计暴击加成
var _m9_base := 0.0        ## 复仇生效前暴击率快照
var _m10_cd_left := 0.0    ## 金身冷却剩余秒数
var _shield := 0.0         ## 护盾池（防M6 填充 / 防M3 结算）
var _run_tag := ""         ## run 身份标记（换局重置瞬态状态）


func _ready() -> void:
	if SynergyRegistry == null:
		push_warning("[DefenseSynergy] SynergyRegistry 不可用，防御流机制未注册")
		return
	SynergyRegistry.register("player_hit", _on_player_hit)  ## 防御流主入口
	SynergyRegistry.register("enemy_hit", _on_m2)           ## 盾反：受击后全伤害加成
	print("[SYNERGY] defense_synergy registered")


func _process(delta: float) -> void:
	if not is_inside_tree():
		return
	_sync_run()
	var dt := minf(delta, 0.1)
	_m2_left = maxf(_m2_left - dt, 0.0)
	_m7_left = maxf(_m7_left - dt, 0.0)
	if _m7_left <= 0.0:
		_m7_armed = false
	_m10_cd_left = maxf(_m10_cd_left - dt, 0.0)
	if _m9_left > 0.0:
		_m9_left -= dt
		if _m9_left <= 0.0:
			_clear_m9()


## ===== 主入口：player_hit（ctx = {dmg, pos, taken, attacker}，扣血后触发）=====
func _on_player_hit(ctx: Dictionary) -> void:
	if not is_inside_tree() or GameState == null:
		return
	_sync_run()
	var taken := maxf(float(ctx.get("taken", 0.0)), 0.0)
	var pos := _ctx_pos(ctx)
	## 金身判定用"扣血后、本链退款前"的 hp 快照：
	## 吸血/护盾退款会先抬高 hp，若晚判会把致死一击后的血量推过 30% 线导致金身失效。
	var hp_after_hit := int(GameState.run.get("hp", 0))
	## 反弹估算（旧 id 由 game_root 结算，新构筑由本脚本补发）
	var reflected := _reflect_total(taken)
	_supply_reflect(taken, pos)            ## 防2 荆棘甲改造（新 id）补发反弹
	_supply_leech(reflected)               ## 防3 血棘甲 + 防M4 反甲吸血
	_on_m9(reflected)                      ## 防M9 复仇：反弹叠暴击
	_on_m1(ctx, reflected)                 ## 防M1 荆棘领域：反弹传染
	var remaining := _on_m7(taken)         ## 防M7 硬化：下一次攻击 -50%
	remaining = _on_m6_m3(remaining, reflected, pos)  ## 防M6 吸收 + 防M3 护盾回响
	_on_m5()                               ## 防M5 磐石不破：减伤≥30% 免疫击退
	_on_m8(pos)                            ## 防M8 嘲讽：吸引周围敌人
	_on_m2_arm()                           ## 防M2 盾反：2s 全伤害 +25%
	_on_m10(hp_after_hit, taken, pos)      ## 防M10 金身：低血 3s 无敌


## ===== 防M1 荆棘领域：反弹伤害 12% 概率传染给附近敌人 =====
func _on_m1(ctx: Dictionary, reflected: int) -> void:
	var stacks := _stacks(M1)
	if stacks <= 0 or reflected <= 0:
		return
	var chance := minf(M1_CHANCE + 0.06 * float(stacks - 1), 0.50)
	if randf() >= chance:
		return
	var pos := _ctx_pos(ctx)
	var radius := clampf(M1_RADIUS + 12.0 * float(stacks - 1), 100.0, 200.0)
	EventBus.fx_explosion.emit(pos, "blade")
	_damage_aoe(pos, radius, reflected)


## ===== 防M2 盾反：受击后 2s 内全伤害 +25%/层（经 enemy_hit 补发增伤）=====
func _on_m2_arm() -> void:
	if _stacks(M2) <= 0:
		return
	_m2_left = M2_DURATION


func _on_m2(ctx: Dictionary) -> void:
	if _m2_left <= 0.0 or _m2_busy:
		return
	var stacks := _stacks(M2)
	if stacks <= 0:
		return
	var enemy = ctx.get("enemy")
	if not is_instance_valid(enemy) or not enemy.has_method("take_damage"):
		return
	var mult := minf(M2_BONUS * float(stacks), M2_CAP)
	var dmg := maxi(int(float(ctx.get("dmg", 0)) * mult), 0)
	if dmg <= 0:
		return
	_m2_busy = true  ## 防重入：take_damage → enemy_hit → 本回调
	enemy.take_damage(dmg, "blade", false)
	EventBus.damage_dealt.emit(dmg, _enemy_pos(enemy), false)
	_m2_busy = false


## ===== 防M3 护盾回响：护盾破碎时对周围敌人造成护盾值伤害 =====
func _on_m3_echo(absorbed: float, pos: Vector2) -> void:
	var stacks := _stacks(M3)
	if stacks <= 0 or absorbed <= 0.0:
		return
	var dmg := maxi(int(absorbed), 1)
	var radius := clampf(M3_RADIUS + 15.0 * float(stacks - 1), 100.0, 220.0)
	EventBus.fx_explosion.emit(pos, "blade")
	_damage_aoe(pos, radius, dmg)


## ===== 防M4 反甲吸血：血棘甲吸血 +1%（每 2 层，上限 4%）=====
func _supply_leech(reflected: int) -> void:
	if reflected <= 0:
		return
	var leech := 0.0
	leech += _curve_value(N3, C3)                       ## 防3 血棘甲：2%/层，上限 4%
	leech += minf(M4_LEECH * float(int(_stacks(M4) / 2)), M4_CAP)  ## 防M4：每 2 层 +1%
	leech = minf(leech, 0.08)                           ## 反弹吸血合计封顶 8%（克制：防无敌）
	if leech <= 0.0:
		return
	var healed := GameState.heal(float(reflected) * leech)
	## 吸血反馈（Agent C）：治疗飘字 + 绿色粒子飞向玩家
	if healed > 0:
		var player := _player_node()
		var hpos := Vector2.ZERO
		if player != null and (player is Node2D):
			hpos = (player as Node2D).global_position
		EventBus.fx_heal_text.emit(hpos, healed)
		EventBus.fx_explosion.emit(hpos, "heal")


## ===== 防M5 磐石不破：减伤 ≥30% 后免疫击退 =====
func _on_m5() -> void:
	var stacks := _stacks(M5)
	if stacks <= 0 or GameState == null:
		return
	## 击退免疫契约位：主线程施加玩家位移前读取 run.defense_no_knockback。
	## 当前版本游戏内暂无击退源（敌人近战/弹幕仅广播 player_hit），
	## 机制按钩子侧就位：减伤达标即写位，等待主线程击退系统接入后自动生效。
	GameState.run.defense_no_knockback = _dr_total() >= M5_DR_THRESHOLD


## ===== 防M6 吸收 + 防M3 护盾回响（共用护盾池，本函数内按顺序结算）=====
func _on_m6_m3(remaining: float, reflected: int, pos: Vector2) -> float:
	var m6 := _stacks(M6)
	if m6 > 0 and reflected > 0:
		var convert := minf(M6_CONVERT + 0.05 * float(m6 - 1), M6_CONVERT_CAP)
		_add_shield(float(reflected) * convert)
	if _shield <= 0.0 or remaining <= 0.0:
		return remaining
	var absorb := minf(remaining, _shield)
	_shield -= absorb
	GameState.heal(absorb)
	remaining -= absorb
	if _shield <= 0.0:
		_on_m3_echo(absorb, pos)
	return remaining


func _add_shield(amount: float) -> void:
	if amount <= 0.0 or GameState == null:
		return
	## 护盾池硬上限 25% 最大生命（克制约束；防8 护盾电池待主线程护盾系统接入）
	var cap := float(GameState.run.get("max_hp", 100)) * M6_SHIELD_CAP
	_shield = minf(_shield + amount, cap)


## ===== 防M7 硬化：受击后下一次攻击伤害 -50%（钩子侧退款）=====
func _on_m7(taken: float) -> float:
	var stacks := _stacks(M7)
	if stacks <= 0 or taken <= 0.0:
		return taken
	if _m7_armed and _m7_left > 0.0:
		## 本次受击正是"下 1 次攻击"：伤害已扣，按比例退款
		var refund := taken * M7_REDUCE
		GameState.heal(refund)
		_m7_armed = false
		_m7_left = 0.0
		return taken - refund
	## 受击后为下一次攻击蓄力（窗口含 0.5s 受击保护余量）
	_m7_left = M7_WINDOW
	_m7_armed = true
	return taken


## ===== 防M8 嘲讽：受击 20% 概率吸引周围敌人贴近自己（配合反弹）=====
func _on_m8(pos: Vector2) -> void:
	var stacks := _stacks(M8)
	if stacks <= 0:
		return
	var chance := minf(M8_CHANCE + 0.05 * float(stacks - 1), 0.55)
	if randf() >= chance:
		return
	var player := _player_node()
	if player == null or not (player is Node2D):
		return
	var center := (player as Node2D).global_position
	var radius := clampf(M8_RADIUS + 20.0 * float(stacks - 1), 200.0, 360.0)
	var pull := clampf(M8_PULL + 20.0 * float(stacks - 1), 60.0, 160.0)
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		if _iget(e, "_dead", false):
			continue
		var node := e as Node2D
		if node.global_position.distance_to(center) <= radius:
			node.global_position = node.global_position.move_toward(center, pull)
			EventBus.fx_hit_flash.emit(e)


## ===== 防M9 复仇：每次反弹获得 2% 暴击率 3s（可叠加，上限 30%）=====
func _on_m9(reflected: int) -> void:
	var stacks := _stacks(M9)
	if stacks <= 0 or reflected <= 0 or GameState == null:
		return
	if _m9_crit >= M9_CAP:
		_m9_left = M9_DURATION  ## 已满层：只刷新持续时间
		return
	if _m9_left <= 0.0:
		_m9_base = float(GameState.run.get("crit_chance", 0.03))
	var add := minf(M9_CRIT * float(stacks), M9_CAP - _m9_crit)
	if add <= 0.0:
		return
	_m9_crit = minf(_m9_crit + add, M9_CAP)
	_m9_left = M9_DURATION
	GameState.run.crit_chance = clampf(_m9_base + _m9_crit, 0.0, 0.85)
	EventBus.player_stats_changed.emit()


func _clear_m9() -> void:
	if _m9_crit <= 0.0 or GameState == null:
		return
	GameState.run.crit_chance = clampf(_m9_base, 0.0, 0.85)
	_m9_crit = 0.0
	_m9_base = 0.0
	_m9_left = 0.0
	EventBus.player_stats_changed.emit()


## ===== 防M10 金身：生命 <30% 时 3s 无敌（冷却 30s，可挡致死）=====
## hp_after_hit 为扣血后快照：本链中的吸血/护盾退款不参与血线判定，
## 保证低血致死场景下金身必然触发（数值克制：冷却 30s 防滥用）。
func _on_m10(hp_after_hit: int, taken: float, pos: Vector2) -> void:
	var stacks := _stacks(M10)
	if stacks <= 0 or _m10_cd_left > 0.0 or GameState == null:
		return
	var max_hp := float(GameState.run.get("max_hp", 1))
	if hp_after_hit > 0 and float(hp_after_hit) >= max_hp * M10_HP_PCT:
		return
	## 本帧若被击杀（hp≤0），先抵消本次伤害保命（触发晚于扣血、早于死亡判定）
	if hp_after_hit <= 0 and taken > 0.0:
		GameState.heal(taken)
	_m10_cd_left = M10_COOLDOWN
	var player := _player_node()
	if player != null:
		var invuln = player.get("_invuln_left")
		if invuln != null:
			player.set("_invuln_left", maxf(float(invuln), M10_DURATION))
	EventBus.fx_explosion.emit(pos, "lightning")


## ===== 反弹体系：旧 id 由 game_root 结算，新构筑由本脚本补发 =====
func _reflect_pct_old() -> float:
	## 与 game_root._on_player_hit 完全同款（thorn_reflect + 防御成型奖励）
	if GameState == null:
		return 0.0
	var pct := GameState.item_value({"curve": OLD_REFLECT}, GameState.total_stacks("thorn_reflect"))
	pct += float(GameState.run.get("synergy_bonus", {}).get("defense", 0.0))
	return pct


func _reflect_pct_new() -> float:
	## 新构筑：防2 荆棘甲改造（30% +6%/层，上限 65%）；防7 反震提高反弹上限
	var pct := _curve_value(N2, C2)
	if pct <= 0.0:
		return 0.0
	return minf(pct, 0.65 + _curve_value(N7, C7))


func _reflect_total(taken: float) -> int:
	## 总反弹估算（克制：反弹封顶 150% 所受伤害）
	if GameState == null or taken <= 0.0:
		return 0
	var pct := minf(_reflect_pct_old() + _reflect_pct_new(), 1.5)
	if pct <= 0.0:
		return 0
	return int(taken * pct)


func _supply_reflect(taken: float, pos: Vector2) -> void:
	## 防2 荆棘甲改造（新 id）补发反弹：game_root 只结算旧 id thorn_reflect，
	## 这里把新构筑对应的反弹份额按同款"最近敌人"取法补发给攻击者。
	if GameState == null or taken <= 0.0:
		return
	var new_pct := _reflect_pct_new()
	var budget := maxf(1.5 - _reflect_pct_old(), 0.0)
	var extra := int(taken * minf(new_pct, budget))
	if extra <= 0:
		return
	var attacker := _nearest_enemy(pos)
	if attacker == null or not attacker.has_method("take_damage"):
		return
	attacker.take_damage(extra, "blade", false)
	EventBus.damage_dealt.emit(extra, _enemy_pos(attacker), false)


## ===== 减伤聚合（与 game_root 同口径，另加防御流新数值构筑）=====
func _dr_total() -> float:
	if GameState == null:
		return 0.0
	var dr := 0.0
	## 旧 id 经 {"curve": ...} 包装求值（item_value 契约），与设计数值一致
	dr += GameState.item_value(
		{"curve": GameState.item_def("stone_armor").get("curve", OLD_STONE)},
		GameState.total_stacks("stone_armor"))
	dr += GameState.item_value(
		{"curve": GameState.item_def("defense_amulet").get("curve", OLD_AMULET)},
		GameState.total_stacks("defense_amulet"))
	dr += _curve_value(N1, C1)   ## 防1 磐石护甲
	dr += _curve_value(N4, C4)   ## 防4 铁壁
	## 防10 不屈：生命低于 40% 时减伤 +10%
	if _stacks(N10) > 0 and float(GameState.run.get("hp", 0)) < float(GameState.run.get("max_hp", 1)) * 0.40:
		dr += _curve_value(N10, C10)
	return dr


## ===== 工具函数（全部防御性）=====

func _stacks(id: String) -> int:
	if GameState == null or not GameState.has_method("total_stacks"):
		return 0
	return maxi(int(GameState.total_stacks(id)), 0)


func _curve_value(id: String, fallback: Dictionary) -> float:
	## 曲线从数据表读取，落库前回退到内联曲线（与 game_root 同款防御写法）
	if GameState == null:
		return 0.0
	var def: Dictionary = GameState.item_def(id)
	if def.is_empty():
		return GameState.item_value({"curve": fallback}, _stacks(id))
	return GameState.item_value(def, _stacks(id))


func _ctx_pos(ctx: Dictionary) -> Vector2:
	var p = ctx.get("pos", Vector2.ZERO)
	return p if p is Vector2 else Vector2.ZERO


func _player_node() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group("player")


func _nearest_enemy(pos: Vector2) -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var best: Node = null
	var best_d := INF
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		var d: float = pos.distance_to((e as Node2D).global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


func _enemy_pos(enemy) -> Vector2:
	if is_instance_valid(enemy) and enemy is Node2D:
		return (enemy as Node2D).global_position
	return Vector2.ZERO


func _damage_aoe(center: Vector2, radius: float, dmg: int) -> int:
	var tree := get_tree()
	if tree == null or dmg <= 0:
		return 0
	var hits := 0
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		if _iget(e, "_dead", false):
			continue
		var node := e as Node2D
		if center.distance_to(node.global_position) > radius + node.scale.x * 8.0:
			continue
		if e.has_method("take_damage"):
			e.take_damage(dmg, "blade", false)
			EventBus.damage_dealt.emit(dmg, node.global_position, false)
			hits += 1
	return hits


## run 身份标记：新一局（GameState.new_run / 读档换 run）时重置瞬态状态，
## 防止金身冷却、护盾池等跨局残留。
func _sync_run() -> void:
	if GameState == null or not (GameState.run is Dictionary):
		return
	var tag: String = str(GameState.run.get("_defense_tag", ""))
	if tag == _run_tag:
		return
	_run_tag = tag
	GameState.run["_defense_tag"] = tag
	_reset_state()


func _reset_state() -> void:
	_m2_left = 0.0
	_m2_busy = false
	_m7_left = 0.0
	_m7_armed = false
	_m9_left = 0.0
	_m9_crit = 0.0
	_m9_base = 0.0
	_m10_cd_left = 0.0
	_shield = 0.0


## Object.get 只接受 1 参数（默认值仅 Dictionary.get 支持）：
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
