extends SynergyBase
## 近战狂暴流机制脚本（10 机制，SynergyRegistry 钩子实现）
## ============================================================
## 挂载方式：由 SynergyRegistry.load_synergy_scripts() 自动扫描
## scripts/synergies/*.gd 并实例化挂树，_ready() 中自动注册全部回调。
## 设计文档：docs/design/流派构筑大全.md 第 6 章「近战狂暴流」
## （核心：旋风刃 whirl_blade · element "blade" · 攻速/吸血永动机）。
## 强度模型：机制强度由持有 melee_ 前缀构筑总层数控制（_melee_power()，
## 即 GameState.run.items 中 id 以 "melee_" 开头的堆叠数之和）。
## 数值构筑 melee_1..melee_10 在战斗侧由本脚本按"每层固定值"结算
## （与文档"每层 +X%"一致；JSON 曲线仅供入库展示/DPS 估算参考）。
##
## 钩子使用：
##   projectile_hit 近M1 旋风斩 / 近M4 战意 / 近M7 破甲斩 / 近M10 处刑
##                   （+ 近1 战斧 / 近7 战吼 / 近8 巨力 / 近10 嗜血）
##   enemy_died     近M2 连环处决 / 近M6 屠戮（+ 破甲斩护甲还原）
##   player_hit     近M3 血之狂暴 / 近M5 弹反（+ 近4 铁壁 / 近8 血池抵扣 / 近9 钢体）
##   damage_dealt   近M8 血池（吸血溢出 → 护盾，钩子在主线程吸血结算后触发）
##   _process 轮询：近5 狂战腰带（生命上限）/ 近M9 狂化（低血攻速）/
##       近M2 窗口 / 近M3 层数衰减 / 近M6 连杀与暴击接管 / 近M7 破甲还原
##
## 防御性约定：SynergyRegistry.trigger 不捕获回调异常（异常会冒泡崩游戏），
## 因此所有回调对空值/失效节点/缺失字段一律兜底，不抛异常。
## 已知近似（受钩子能力限制，各函数内亦有注释）：
##   - 近M1 旋风斩：钩子无 whirl_blade 专用点，用 projectile_hit(blade) 近似——
##     命中附加刀刃伤害并在命中点扩散扫击（半径由近6 放大），模拟
##     "旋转半径 +30%、持续命中"的大刃盘扫击；
##   - 近M3/近M9 攻速加成写入 run.attack_speed_bonus（主线程攻速接线点），
##     并同步暴露 run.melee_m3_as_bonus / run.melee_m9_as_bonus；
##   - 近M5 弹反：game_root 广播 attacker=null，回退为受击点最近敌人；
##     眩晕用 blind（致盲状态=不移动不攻击）近似；
##   - 近M8 血池：护盾先记账，受击时以回补方式抵扣（伤害已由主线程扣血）；
##   - 近M6 屠戮：接管 run.crit_chance 期间若主线程重算面板，恢复时按
##     接管前保存值还原（与火M2 攻速接线同类限制）；
##   - 近M10 处刑：直接调用 enemy._take_raw 跳过护甲结算（真伤处决）。

## ===== 机制构筑 id（与 .tools/build_defs/melee.json 的 items 一致）=====
const M1 := "melee_m1"     ## 近M1 旋风斩
const M2 := "melee_m2"     ## 近M2 连环处决
const M3 := "melee_m3"     ## 近M3 血之狂暴
const M4 := "melee_m4"     ## 近M4 战意
const M5 := "melee_m5"     ## 近M5 弹反
const M6 := "melee_m6"     ## 近M6 屠戮
const M7 := "melee_m7"     ## 近M7 破甲斩
const M8 := "melee_m8"     ## 近M8 血池
const M9 := "melee_m9"     ## 近M9 狂化
const M10 := "melee_m10"   ## 近M10 处刑

## ===== 数值构筑 id（联动读取，按每层固定值结算）=====
const N1 := "melee_1"      ## 近1 战斧：刀刃伤害 +15%/层
const N2 := "melee_2"      ## 近2 磨刀石：近战攻速 +10%/层（tag 走主线程聚合）
const N3 := "melee_3"      ## 近3 血怒：吸血 +0.5%/层（tag 走主线程聚合，全局上限 4%）
const N4 := "melee_4"      ## 近4 铁壁：近战减伤 +5%/层
const N5 := "melee_5"      ## 近5 狂战腰带：生命上限 +20/层
const N6 := "melee_6"      ## 近6 碎裂锤：近战范围 +12%/层（近M1 扩散半径）
const N7 := "melee_7"      ## 近7 战吼：近战暴击率 +5%/层
const N8 := "melee_8"      ## 近8 巨力：近战暴伤 +20%/层
const N9 := "melee_9"      ## 近9 钢体：受击保护时间 +0.1s/层
const N10 := "melee_10"    ## 近10 嗜血：低血（<40%）近战伤害 +15%/层

## ===== 强度常量（克制参考：刀刃伤害 15%/层、处刑阈值 20% 生命）=====
const M1_DMG := 10.0            ## 近M1 基础附加刀刃伤害
const M1_DMG_K := 4.0           ## 近M1 每件 melee_ 构筑再 +4
const M1_SPLASH_RADIUS := 34.0  ## 近M1 扩散扫击基础半径（px）
const M1_SPLASH_MULT := 0.35    ## 近M1 扩散扫击伤害比例（外圈轻伤）
const M2_WINDOW := 1.5          ## 近M2 处决窗口（秒）
const M2_BONUS := 0.50          ## 近M2 窗口内下一发近战伤害 +50%
const M2_BONUS_CAP := 0.90      ## 近M2 构筑提升上限
const M3_AS := 0.05             ## 近M3 每次受击 +5% 攻速
const M3_MAX := 10              ## 近M3 层数上限
const M3_TIME := 4.0            ## 近M3 持续秒数
const M4_THRESHOLD := 0.50      ## 近M4 攻速每满 50% 一档
const M4_DMG := 0.10            ## 近M4 每档近战伤害 +10%
const M4_CAP := 0.50            ## 近M4 总加成上限
const M5_CHANCE := 0.20         ## 近M5 弹反基础概率
const M5_CHANCE_CAP := 0.40
const M6_STREAK := 5            ## 近M6 击杀 5 连触发
const M6_TIME := 2.0            ## 近M6 全法术暴击持续 2s
const M6_WINDOW := 3.0          ## 近M6 连杀窗口（3s 无击杀重置）
const M7_CHANCE := 0.20         ## 近M7 破甲斩基础概率
const M7_CHANCE_CAP := 0.40
const M7_ARMOR_CUT := 0.20      ## 近M7 降低目标护甲 20%
const M7_TIME := 3.0            ## 近M7 破甲持续 3s
const M8_SHIELD_PCT := 0.30     ## 近M8 护盾上限（30% 最大生命）
const M8_GAIN_K := 0.25         ## 近M8 构筑提升：每件 +25% 转化量
const M9_HP_PCT := 0.50         ## 近M9 生命低于 50% 触发
const M9_AS := 0.25             ## 近M9 近战攻速 +25%
const M9_AS_K := 0.05           ## 近M9 构筑提升：每件 +5%
const M9_AS_CAP := 0.50
const M10_HP_PCT := 0.20        ## 近M10 处刑阈值：低于 20% 生命
const M10_HP_PCT_K := 0.01      ## 近M10 构筑提升：每件 +1% 阈值
const M10_HP_PCT_CAP := 0.35
const N4_CAP := 0.40            ## 近4 铁壁减伤上限
const N10_HP_PCT := 0.40        ## 近10 嗜血低血线
const N10_DMG := 0.15           ## 近10 低血近战伤害 +15%/层
const N9_INVULN := 0.1          ## 近9 钢体每层 +0.1s 保护
const N5_HP := 20               ## 近5 狂战腰带每层 +20 生命上限

## ===== 运行状态（key 均为 enemy instance_id）=====
var _m2_left := 0.0          ## 近M2 处决窗口剩余秒
var _m3_stacks := 0          ## 近M3 血之狂暴层数
var _m3_left := 0.0          ## 近M3 剩余秒
var _m6_streak := 0          ## 近M6 连杀计数
var _m6_streak_left := 0.0   ## 近M6 连杀窗口剩余
var _m6_left := 0.0          ## 近M6 全法术暴击剩余秒
var _m6_saved_crit := 0.0    ## 近M6 接管前暴击率
var _m6_crit_forced := false ## 近M6 当前是否接管暴击率
var _as_bonus := 0.0         ## 我方写入 run.attack_speed_bonus 的附加攻速
var _hp_bonus := 0           ## 我方写入 run.max_hp 的附加生命
var _shield := 0.0           ## 近M8 血池护盾存量
var _armor_orig := {}        ## 近M7 破甲前护甲（id -> float）
var _armor_left := {}        ## 近M7 破甲剩余秒（id -> float）
var _shield_written := -1.0  ## 上次写入 run.melee_shield 的值（去重发事件）


func _ready() -> void:
	super._ready()
	_register("projectile_hit", _on_projectile_hit) ## 近M1/近M4/近M7/近M10
	_register("enemy_died", _on_enemy_died)         ## 近M2/近M6
	_register("player_hit", _on_player_hit)         ## 近M3/近M5
	_register("damage_dealt", _on_damage_dealt)     ## 近M8
	print("[SYNERGY] melee_synergy registered")


func _process(delta: float) -> void:
	if not is_inside_tree():
		return
	var dt := minf(delta, 0.1)
	_detect_run_reset()
	_tick_m2(dt)
	_tick_m3(dt)
	_tick_m6(dt)
	_tick_m7(dt)
	_tick_max_hp()
	_sync_as()
	_prune_trackers()


## ===== 近M1 旋风斩 / 近M4 战意 / 近M7 破甲斩 / 近M10 处刑（+ 近1/近7/近8/近10）=====
func _on_projectile_hit(ctx: Dictionary) -> void:
	if str(ctx.get("element", "")) != "blade":
		return
	var enemy = ctx.get("enemy")
	if not is_instance_valid(enemy):
		return
	var pos := _ctx_pos(ctx, enemy)
	var dmg := maxi(int(ctx.get("dmg", 0)), 0)
	var power := _melee_power()
	## 近M10 处刑：低于阈值一击必杀（Boss/精英跳过）
	if _stacks(M10) > 0 and _executable(enemy, power):
		_execute(enemy)
		return
	## 近M1 扩散扫击伤害独立计算（不混入弹反/处决等来源）
	var m1_extra := 0
	if _stacks(M1) > 0:
		m1_extra = maxi(int(M1_DMG + M1_DMG_K * float(maxi(power - 1, 0))), 1)
	## 综合附加伤害（近1/近10/近M2/近M4/近7/近8）
	var extra := _blade_extra(ctx, dmg, power)
	if extra > 0:
		## 递归修复（2026-08-11）：enemy_hit 钩子内追加伤害走 _take_raw（防无限链）
		if enemy.has_method("_take_raw"):
			enemy.call("_take_raw", extra)
		elif enemy.has_method("take_damage"):
			enemy.take_damage(extra, "blade", bool(ctx.get("crit", false)))
		EventBus.damage_dealt.emit(extra, pos, bool(ctx.get("crit", false)))
		EventBus.fx_hit_flash.emit(enemy)
	## 近M1 旋风斩：命中点扩散扫击（模拟大刃盘旋转半径 +30% 的持续命中）
	if m1_extra > 0:
		_m1_splash(pos, m1_extra, enemy)
	## 近M7 破甲斩：概率降低目标护甲 20%（3s）
	if _stacks(M7) > 0:
		_armor_cut(enemy, power)


## ===== 近M2 连环处决 / 近M6 屠戮（+ 近M7 破甲还原）=====
func _on_enemy_died(ctx: Dictionary) -> void:
	var enemy = ctx.get("enemy")
	var eid := _id_of(enemy)
	## 近M7 破甲斩：死亡时还原护甲并清理跟踪
	if _armor_orig.has(eid) and is_instance_valid(enemy) and enemy.get("armor") != null:
		enemy.set("armor", _armor_orig[eid])
	_armor_orig.erase(eid)
	_armor_left.erase(eid)
	## 近M2 连环处决：击杀刷新处决窗口
	if _stacks(M2) > 0:
		_m2_left = M2_WINDOW
	## 近M6 屠戮：击杀 5 连后全法术暴击 2s（期间击杀刷新）
	if _stacks(M6) > 0:
		if _m6_left > 0.0:
			_m6_left = M6_TIME
		else:
			_m6_streak += 1
			_m6_streak_left = M6_WINDOW
			if _m6_streak >= M6_STREAK:
				_m6_streak = 0
				_m6_left = M6_TIME


## ===== 近M3 血之狂暴 / 近M5 弹反（+ 近4 铁壁 / 近8 血池抵扣 / 近9 钢体）=====
func _on_player_hit(ctx: Dictionary) -> void:
	var taken := maxi(int(ctx.get("dmg", 0)), 0)
	if taken <= 0:
		return
	var pos: Vector2 = ctx.get("pos", Vector2.ZERO)
	var power := _melee_power()
	## 近M8 血池：护盾抵扣（护盾在 damage_dealt 钩子中由吸血溢出蓄积）
	if _stacks(M8) > 0 and _shield > 0.0:
		var absorb := minf(_shield, float(taken))
		if absorb > 0.0:
			_shield = maxf(_shield - absorb, 0.0)
			GameState.heal(absorb)  ## 回补已被主线程扣掉的生命
			_sync_shield()
	## 近4 铁壁：近战减伤 5%/层（受击后回补，上限 40%）
	var n4 := _stacks(N4)
	if n4 > 0:
		var refund := roundi(float(taken) * minf(0.05 * float(n4), N4_CAP))
		if refund > 0:
			GameState.heal(float(refund))
	## 近9 钢体：受击保护时间 +0.1s/层（受击后延长无敌帧）
	var n9 := _stacks(N9)
	if n9 > 0:
		_extend_invuln(n9)
	## 近M3 血之狂暴：每次受击 +5% 攻速持续 4s（上限 10 层）
	if _stacks(M3) > 0:
		_m3_stacks = mini(_m3_stacks + 1, M3_MAX)
		_m3_left = M3_TIME
		_sync_as()
	## 近M5 弹反：20% 概率反弹全额伤害并眩晕攻击者
	if _stacks(M5) > 0:
		var chance := minf(M5_CHANCE + 0.02 * float(maxi(power - 1, 0)), M5_CHANCE_CAP)
		if randf() < chance:
			_parry(ctx, taken)


## ===== 近M8 血池：吸血溢出（满血时）转化为护盾 =====
func _on_damage_dealt(ctx: Dictionary) -> void:
	if _stacks(M8) <= 0:
		return
	if GameState == null or not (GameState.run is Dictionary):
		return
	var ls := float(GameState.run.get("lifesteal", 0.0))
	if ls <= 0.0:
		return
	var hp := float(GameState.run.get("hp", 0))
	var max_hp := float(GameState.run.get("max_hp", 1))
	if max_hp <= 0.0:
		return
	## 该钩子在主线程吸血结算之后触发：按 lifesteal×dmg 重算溢出量
	var amt := float(int(ctx.get("dmg", 0))) * ls
	var overflow := maxf(amt - maxf(max_hp - hp, 0.0), 0.0)
	if overflow <= 0.0:
		return
	var gain := overflow * (1.0 + M8_GAIN_K * float(maxi(_melee_power() - 1, 0)))
	var cap := max_hp * M8_SHIELD_PCT
	if _shield >= cap:
		return
	_shield = minf(_shield + gain, cap)
	_sync_shield()


## ===== 近M5 弹反实现：反弹全额伤害 + 眩晕（blind 近似）=====
func _parry(ctx: Dictionary, taken: int) -> void:
	var attacker: Node = ctx.get("attacker")
	if not is_instance_valid(attacker):
		## 当前 game_root 广播 attacker=null：回退为受击点最近敌人
		attacker = _nearest_enemy(ctx.get("pos", Vector2.ZERO))
	if not is_instance_valid(attacker):
		return
	var reflect := maxi(taken, 1)
	if attacker.has_method("take_damage"):
		attacker.take_damage(reflect, "blade", true)
		EventBus.damage_dealt.emit(reflect, _enemy_pos(attacker), true)
	## 眩晕：blind（致盲=不移动不攻击）
	EventBus.apply_status.emit(attacker, "blind", 1)
	EventBus.fx_explosion.emit(_enemy_pos(attacker), "blade")


## ===== 近M10 处刑判定与执行 =====
func _executable(enemy, power: int) -> bool:
	if _iget(enemy, "is_boss", false) or _iget(enemy, "is_elite", false):
		return false
	## 名字兜底（enemy_id / conf.name 含 boss/elite）
	## Object.get 只接受 1 参数：缺字段先取回 null 再兜底
	var eid_v = enemy.get("enemy_id")
	var name := str(eid_v if eid_v != null else "").to_lower()
	if name.contains("boss") or name.contains("elite"):
		return false
	var conf = enemy.get("conf")
	if conf is Dictionary and str(conf.get("name", "")).to_lower().contains("boss"):
		return false
	var hp := _fget(enemy, "hp", 0.0)
	var max_hp := _fget(enemy, "max_hp", 1.0)
	if max_hp <= 0.0 or hp <= 0.0:
		return false
	var threshold := minf(M10_HP_PCT + M10_HP_PCT_K * float(maxi(power - 1, 0)), M10_HP_PCT_CAP)
	return hp < max_hp * threshold


func _execute(enemy) -> void:
	var hp := maxf(_fget(enemy, "hp", 0.0), 0.0)
	var pos := _enemy_pos(enemy)
	var dealt := maxi(int(ceil(hp)), 1)
	if enemy.has_method("_take_raw"):
		enemy._take_raw(dealt + 1)  ## 跳过护甲：直接扣至 0 触发 _die
	elif enemy.has_method("take_damage"):
		enemy.take_damage(99999, "blade", true)
	EventBus.damage_dealt.emit(dealt, pos, true)
	EventBus.fx_explosion.emit(pos, "blade")


## ===== 近M1 旋风斩：命中点扩散扫击 =====
func _m1_splash(center: Vector2, dmg: int, hit_enemy) -> void:
	var power := _melee_power()
	var radius := M1_SPLASH_RADIUS * (1.0 + 0.12 * float(_stacks(N6))) \
		* (1.0 + 0.05 * float(maxi(power - 1, 0)))
	radius = clampf(radius, 30.0, 90.0)
	var splash := maxi(int(float(dmg) * M1_SPLASH_MULT), 1)
	var tree := get_tree()
	if tree == null:
		return
	for e in GameState.get_enemies():
		if e == hit_enemy or not is_instance_valid(e) or not (e is Node2D):
			continue
		if _iget(e, "_dead", false):
			continue
		var node := e as Node2D
		if center.distance_to(node.global_position) > radius + node.scale.x * 8.0:
			continue
		if e.has_method("take_damage"):
			e.take_damage(splash, "blade", false)
			EventBus.damage_dealt.emit(splash, node.global_position, false)


## ===== 近M7 破甲斩：降低目标护甲 20%（3s，可刷新）=====
func _armor_cut(enemy, power: int) -> void:
	var eid := _id_of(enemy)
	if not is_instance_valid(enemy) or enemy.get("armor") == null:
		return
	var chance := minf(M7_CHANCE + 0.02 * float(maxi(power - 1, 0)), M7_CHANCE_CAP)
	if randf() >= chance:
		return
	if not _armor_orig.has(eid):
		_armor_orig[eid] = _fget(enemy, "armor", 0.0)
		enemy.set("armor", maxf(_fget(enemy, "armor", 0.0) * (1.0 - M7_ARMOR_CUT), 0.0))
	_armor_left[eid] = M7_TIME


func _tick_m7(dt: float) -> void:
	if _armor_left.is_empty():
		return
	var expired: Array = []
	for eid in _armor_left:
		_armor_left[eid] = maxf(float(_armor_left[eid]) - dt, 0.0)
		if float(_armor_left[eid]) <= 0.0:
			expired.append(eid)
	for eid in expired:
		var e = instance_from_id(int(eid))
		if is_instance_valid(e) and e.get("armor") != null:
			e.set("armor", _armor_orig.get(eid, 0.0))
		_armor_orig.erase(eid)
		_armor_left.erase(eid)


## ===== 近M2 窗口计时 =====
func _tick_m2(dt: float) -> void:
	if _m2_left > 0.0:
		_m2_left = maxf(_m2_left - dt, 0.0)


## ===== 近M3 层数衰减（持续 4s，受击刷新）=====
func _tick_m3(dt: float) -> void:
	if _m3_left <= 0.0:
		return
	_m3_left -= dt
	if _m3_left <= 0.0:
		_m3_stacks = 0
		_sync_as()


## ===== 近M6 屠戮：连杀窗口 + 全法术暴击接管/还原 =====
func _tick_m6(dt: float) -> void:
	if GameState == null or not (GameState.run is Dictionary):
		return
	if _m6_left > 0.0:
		_m6_left -= dt
		if not _m6_crit_forced:
			_m6_saved_crit = float(GameState.run.get("crit_chance", 0.03))
			_m6_crit_forced = true
		GameState.run.crit_chance = 1.0
		if _m6_left <= 0.0:
			GameState.run.crit_chance = clampf(_m6_saved_crit, 0.0, 1.0)
			_m6_crit_forced = false
			_m6_saved_crit = 0.0
			EventBus.player_stats_changed.emit()
	elif _m6_streak > 0:
		_m6_streak_left = maxf(_m6_streak_left - dt, 0.0)
		if _m6_streak_left <= 0.0:
			_m6_streak = 0


## ===== 近5 狂战腰带：生命上限 +20/层（自校正式附加）=====
func _tick_max_hp() -> void:
	if GameState == null or not (GameState.run is Dictionary):
		return
	var desired := N5_HP * _stacks(N5)
	## 主线程基准生命（与 game_state.apply_item_effects_to_stats 同公式）
	var base_max := 100.0
	if GameState.has_method("balance"):
		base_max = float(GameState.balance().get("player", {}).get("hp", 100.0))
	base_max += 10.0 * float(int(GameState.run.get("player_level", 1)) - 1)
	base_max += float(GameState.run.get("synergy_bonus", {}).get("max_hp", 0.0))
	if GameState.has_method("item_def") and GameState.has_method("item_value"):
		base_max += GameState.item_value(
			GameState.item_def("life_crystal"), GameState.total_stacks("life_crystal"))
	var cur := float(GameState.run.get("max_hp", 1))
	var mine := cur - base_max
	if absf(float(desired) - mine) < 0.01:
		return
	GameState.run.max_hp = maxi(int(cur + float(desired) - mine), 1)
	_hp_bonus = desired
	GameState.run.melee_max_hp_bonus = desired  ## 主线程接线点（HUD 可读）
	if int(GameState.run.get("hp", 0)) > int(GameState.run.max_hp):
		GameState.run.hp = int(GameState.run.max_hp)
	EventBus.player_stats_changed.emit()


## ===== 近M3 + 近M9 攻速：只写本脚本读取点（G1/G2 收敛）=====
## run.attack_speed_bonus 仅由 game_state 聚合写入；消费端
## （spell_caster._total_attack_speed / melee_attack._interval）读取点求和。
func _sync_as() -> void:
	if GameState == null or not (GameState.run is Dictionary):
		return
	var desired := _as_desired()
	if absf(desired - _as_bonus) < 0.0005:
		return
	_as_bonus = desired
	GameState.run.melee_m3_as_bonus = float(_m3_stacks) * M3_AS    ## 主线程接线点
	GameState.run.melee_m9_as_bonus = maxf(desired - float(_m3_stacks) * M3_AS, 0.0)
	EventBus.player_stats_changed.emit()


func _as_desired() -> float:
	var d := float(_m3_stacks) * M3_AS
	if _stacks(M9) > 0 and _low_hp(M9_HP_PCT):
		d += minf(M9_AS * (1.0 + M9_AS_K * float(maxi(_melee_power() - 1, 0))), M9_AS_CAP)
	return minf(d, float(M3_MAX) * M3_AS + M9_AS_CAP)


## ===== 近M4 战意：攻速每满 50% 一档，每档近战伤害 +10% =====
func _m4_bonus() -> float:
	if _stacks(M4) <= 0:
		return 0.0
	var base_as := 0.0
	if GameState != null and GameState.has_method("aggregate_bonus"):
		base_as = maxf(float(GameState.aggregate_bonus("attack_speed")), 0.0)
	var tiers := int((base_as + _as_bonus) / M4_THRESHOLD)
	if tiers <= 0:
		return 0.0
	var power := _melee_power()
	return minf(M4_DMG * float(tiers) * (1.0 + 0.10 * float(maxi(power - 1, 0))), M4_CAP)


## ===== 刀刃综合附加伤害（近1/近10/近M2/近M4/近7/近8）=====
func _blade_extra(ctx: Dictionary, dmg: int, power: int) -> int:
	var extra := 0.0
	var crit := bool(ctx.get("crit", false))
	## 近1 战斧：刀刃伤害 +15%/层
	if _stacks(N1) > 0:
		extra += float(dmg) * 0.15 * float(_stacks(N1))
	## 近10 嗜血：生命低于 40% 时近战伤害 +15%/层
	if _stacks(N10) > 0 and _low_hp(N10_HP_PCT):
		extra += float(dmg) * N10_DMG * float(_stacks(N10))
	## 近M2 连环处决：窗口内下一发近战伤害 +50%（消耗窗口）
	if _stacks(M2) > 0 and _m2_left > 0.0:
		var m2 := minf(M2_BONUS * (1.0 + 0.05 * float(maxi(power - 1, 0))), M2_BONUS_CAP)
		extra += float(dmg) * m2
		_m2_left = 0.0
	## 近M4 战意：攻速阈值档位加成
	extra += float(dmg) * _m4_bonus()
	## 近7 战吼：近战暴击率 +5%/层（补掷；命中本体已按原暴击结算）
	var n7 := _stacks(N7)
	if not crit and n7 > 0 and randf() < minf(0.05 * float(n7), 0.60):
		crit = true
	## 近8 巨力：近战暴伤 +20%/层（对暴击命中附加暴伤差额）
	if crit and _stacks(N8) > 0:
		extra += float(dmg) * 0.20 * float(_stacks(N8))
	return maxi(roundi(extra), 0)


## ===== 近9 钢体：受击后延长无敌帧 =====
func _extend_invuln(stacks: int) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var player = tree.get_first_node_in_group("player")
	if player == null or player.get("_invuln_left") == null:
		return
	var base := 0.35
	if GameState != null and GameState.has_method("balance"):
		base = float(GameState.balance().get("player", {}).get("invuln_time", 0.35))
	var target := base + N9_INVULN * float(stacks)
	player.set("_invuln_left", maxf(_fget(player, "_invuln_left", 0.0), target))


## ===== 近M8 血池：护盾写回 run（HUD 接线点）=====
func _sync_shield() -> void:
	if GameState == null or not (GameState.run is Dictionary):
		return
	var max_hp := float(GameState.run.get("max_hp", 1))
	if absf(_shield_written - _shield) < 0.01:
		return
	_shield_written = _shield
	GameState.run.melee_shield = _shield
	GameState.run.melee_shield_max = max_hp * M8_SHIELD_PCT
	EventBus.player_stats_changed.emit()


## ===== 新一局检测：run 字典被 new_run() 重建时清空本脚本残留 =====
func _detect_run_reset() -> void:
	if GameState == null or not (GameState.run is Dictionary):
		return
	if GameState.run.has("melee_shield"):
		return
	_m2_left = 0.0
	_m3_stacks = 0
	_m3_left = 0.0
	_m6_streak = 0
	_m6_streak_left = 0.0
	_m6_left = 0.0
	_m6_crit_forced = false
	_m6_saved_crit = 0.0
	_as_bonus = 0.0
	_hp_bonus = 0
	_shield = 0.0
	_shield_written = -1.0
	_armor_orig.clear()
	_armor_left.clear()


## ===== 工具函数（全部防御性）=====

## 机制强度：持有 melee_ 前缀构筑的总层数（含数值与机制构筑）
func _melee_power() -> int:
	if GameState == null or not (GameState.run is Dictionary):
		return 0
	var items = GameState.run.get("items", {})
	if not (items is Dictionary):
		return 0
	var n := 0
	for id in items:
		if str(id).begins_with("melee_"):
			n += maxi(int(items[id]), 0)
	return n
func _low_hp(pct: float) -> bool:
	if GameState == null or not (GameState.run is Dictionary):
		return false
	var max_hp := float(GameState.run.get("max_hp", 1))
	if max_hp <= 0.0:
		return false
	return float(GameState.run.get("hp", 0)) < max_hp * pct


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


func _prune_trackers() -> void:
	if _armor_orig.size() <= 256 and _armor_left.size() <= 256:
		return
	var dead: Array = []
	for k in _armor_left:
		if not is_instance_valid(instance_from_id(int(k))):
			dead.append(k)
	for k in dead:
		_armor_orig.erase(k)
		_armor_left.erase(k)


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
