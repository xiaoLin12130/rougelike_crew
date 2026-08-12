extends Node
## 暴击暴伤流机制脚本（10 机制，SynergyRegistry 钩子实现）
## ============================================================
## 挂载方式：由 SynergyRegistry.load_synergy_scripts() 自动扫描
## scripts/synergies/*.gd 并实例化挂树，_ready() 中自动注册全部回调。
## 机制开关：GameState.total_stacks("crit_xxx")（id 与 .tools/build_defs/crit.json 一致）。
## 机制强度：由持有 crit_ 前缀构筑总件数控制（_crit_count()，含已有道具
##   crit_glasses/crit_gem；机制构筑 id 全部使用新 crit_ 前缀）。
## 数值联动：暴1 暴击眼镜/暴3 敏锐/暴4 猎杀标记/暴6 弱点洞悉/暴10 暴风眼
##   → 理论暴击率；暴2 暴伤宝石/暴8 处刑者/暴10 暴风眼 → 暴伤；
##   暴5 致命节奏/暴7 暴击术架 → 攻速（主线程消费）。
## 防御性约定：所有回调先做对象/树/字段有效性检查；回调内不做可能抛错的
## 操作（GDScript 无 try/except），异常只影响本流派、不扩散到其他流派。
## 已知限制（接线说明）：
## - projectile_hit 钩子在 enemy.take_damage 之前广播，ctx.crit 即本次暴击判定；
## - 暴M6/暴M9 的强制暴击以「补足暴击差额伤害」实现（额外伤害 = 原伤害 × (暴伤倍率-1)），
##   经 take_damage 结算，死亡/掉落链路完整；
## - 暴M1 溢出转伤 / 暴M8 猎头 / 数值暴击属性：由本脚本 _sync_stats() 周期
##   重算并写回 run.crit_chance / run.crit_dmg_bonus（绝对值写入，幂等），
##   防止 game_state 属性刷新覆盖；主线程读取点 run.crit_m1_overflow /
##   run.crit_hunt_bonus / run.crit_combo_stacks；
## - 暴M4 猎杀标记/暴6 弱点洞悉为条件暴击（精英、低血），主线程弹幕暴击
##   判定无法按条件分流，故计入理论暴击率（近似，注释标注）。

## ===== 机制构筑 id（与 .tools/build_defs/crit.json 的 mechanisms 一致）=====
const M1 := "crit_overflow_damage"  ## 暴M1 溢出转伤
const M2 := "crit_deadly_combo"     ## 暴M2 致命连击
const M3 := "crit_crit_bounce"      ## 暴M3 暴击弹射
const M4 := "crit_weak_mark"        ## 暴M4 弱点标记
const M5 := "crit_storm_spread"     ## 暴M5 暴风扩散
const M6 := "crit_execute"          ## 暴M6 终结
const M7 := "crit_crit_echo"        ## 暴M7 暴击回响
const M8 := "crit_headhunter"       ## 暴M8 猎头
const M9 := "crit_lethal_blow"      ## 暴M9 致命一击
const M10 := "crit_crit_storm"      ## 暴M10 暴击风暴

## ===== 数值构筑 id（联动读取）=====
const N1 := "crit_glasses"          ## 暴1 暴击眼镜（已有道具）
const N2 := "crit_gem"              ## 暴2 暴伤宝石（已有道具）
const N3 := "crit_sharp_senses"     ## 暴3 敏锐
const N4 := "crit_hunters_mark"     ## 暴4 猎杀标记
const N6 := "crit_weakness_insight" ## 暴6 弱点洞悉
const N8 := "crit_executioner"      ## 暴8 处刑者
const N10 := "crit_storm_eye"       ## 暴10 暴风眼

## ===== 强度常量（克制参考：溢出转伤 1:1、连击 +20%/次、弹射 50% 伤害）=====
const M2_BONUS := 0.20        ## 致命连击：每层连击 +20%（数值克制）
const M2_MAX := 5             ## 致命连击层数上限（+100%）
const M3_DMG_MULT := 0.50     ## 暴击弹射：50% 伤害（数值克制）
const M3_SPEED := 260.0       ## 弹射弹幕速度
const M3_RANGE := 420.0       ## 弹射弹幕射程
const M3_SEEK := 380.0        ## 弹射初始索敌半径
const M3_BURST := 3.0         ## 弹射令牌容量（防暴击链爆炸）
const M3_RATE := 3.0          ## 弹射令牌每秒补充
const M4_DURATION := 3.0      ## 弱点标记持续秒数
const M4_BONUS := 0.15        ## 弱点标记受伤加成基础
const M5_CHANCE := 0.10       ## 暴风扩散基础概率
const M5_RADIUS := 95.0       ## 暴风扩散基础半径
const M5_DMG_MULT := 0.50     ## 暴风扩散：50% 暴击伤害
const M6_THRESHOLD := 0.25    ## 终结斩杀线（低于 25% 生命）
const M7_PCT := 0.01          ## 暴击回响：每层回复 1% 技能冷却
const M8_BONUS := 0.15        ## 猎头：暴击率 +15% 基础
const M8_DURATION := 3.0      ## 猎头持续秒数
const M10_INTERVAL := 1.5     ## 暴击风暴最小触发间隔
const M10_FACTOR := 0.35      ## 暴击风暴慢动作时间倍率
const M10_DURATION := 0.12    ## 暴击风暴慢动作时长
const SYNC_GAP := 0.5         ## 属性同步节流秒数
## N2 新增机制构筑 id（crit_m1..m9；致命节奏改为触发式）
const CM1 := "crit_m1"                ## 暴M1 暴击溢出→真伤
const CM2 := "crit_m2"                ## 暴M2 暴击吸血
const CM3 := "crit_m3"                ## 暴M3 暴击连击
const CM4 := "crit_m4"                ## 暴M4 暴击减速
const CM5 := "crit_m5"                ## 暴M5 暴击爆炸
const CM6 := "crit_m6"                ## 暴M6 暴击穿透
const CM7 := "crit_m7"                ## 暴M7 暴击回能
const CM8 := "crit_m8"                ## 暴M8 完美暴击
const CM9 := "crit_m9"                ## 暴M9 暴击攻速
const HASTE_ITEM := "crit_deadly_rhythm"  ## 致命节奏（改触发式攻速）
const N2_M1_OVERFLOW_CAP := 2.0       ## 溢出转真伤转化上限 ×2
const N2_M2_LEECH := 0.02             ## 暴击吸血 2%/层
const N2_M2_LEECH_CAP := 0.10         ## 吸血上限 10%
const N2_M3_BONUS := 0.15             ## 连击伤害 +15%/层
const N2_M3_MAX := 5                  ## 连击层数上限
const N2_M4_SLOW := 0.8               ## 暴击减速 0.8s/层
const N2_M5_CHANCE := 0.30            ## 暴击爆炸基础概率
const N2_M5_CHANCE_PER := 0.10        ## 每层 +10%
const N2_M5_CHANCE_CAP := 0.80        ## 概率上限
const N2_M5_RADIUS := 70.0            ## 爆炸半径
const N2_M5_DMG := 0.50               ## 爆炸伤害比例
const N2_M7_REFUND := 0.01            ## 暴击回能 1%/层
const N2_M7_CAP := 0.05               ## 回能上限
const N2_M8_BASE := 2.0               ## 完美暴击阈值基础
const N2_M8_THRESHOLD_PER := 0.15     ## 每层阈值 -0.15
const N2_HASTE_RATE := 0.04           ## 暴击攻速 +4%/层
const N2_HASTE_CAP := 0.20            ## 攻速上限 20%
const N2_HASTE_TIME := 2.0            ## 触发持续 2s

const PROJECTILE_SCRIPT := preload("res://scripts/combat/projectile.gd")

var _m2_stacks := 0           ## 致命连击当前层数
var _m4_marks := {}           ## 弱点标记：enemy instance_id → 过期秒数
var _m9_hits := {}            ## 致命一击：enemy instance_id → 已必暴次数
var _m8_left := 0.0           ## 猎头剩余秒数
var _m8_bonus := 0.0          ## 猎头当前暴击率加成
var _m3_tokens := M3_BURST    ## 弹射令牌
var _m10_last := 0.0          ## 暴击风暴上次触发秒数
var _sync_timer := 0.0        ## 属性同步计时
var _chain_hp0 := 0.0         ## 本次 projectile_hit 链开始时目标血量（猎头斩杀判定）
var _forced_extra := 0        ## 本次链中暴M6/暴M9 追加的暴击伤害
var _forced_crit := false     ## 本次链中是否发生强制暴击
var _n2_combo := 0            ## N2 暴M3 连击层数
var _n2_haste_left := 0.0     ## N2 暴M9/致命节奏：触发式攻速剩余秒数
var _n2_haste_rate := 0.0     ## N2 当前触发式攻速加成


func _ready() -> void:
	if SynergyRegistry == null:
		push_warning("[CritSynergy] SynergyRegistry 不可用，暴击机制未注册")
		return
	## 注册顺序即触发顺序：链起始快照最先，猎头斩杀判定最后（需读取 M6/M9 标记）
	SynergyRegistry.register("projectile_hit", _on_chain_begin) ## 链起始快照
	SynergyRegistry.register("projectile_hit", _on_m2)          ## 致命连击
	SynergyRegistry.register("projectile_hit", _on_m3)          ## 暴击弹射
	SynergyRegistry.register("projectile_hit", _on_m4)          ## 弱点标记
	SynergyRegistry.register("projectile_hit", _on_m5)          ## 暴风扩散
	SynergyRegistry.register("projectile_hit", _on_m6)          ## 终结
	SynergyRegistry.register("projectile_hit", _on_m7)          ## 暴击回响
	SynergyRegistry.register("projectile_hit", _on_m9)          ## 致命一击
	SynergyRegistry.register("projectile_hit", _on_m10)         ## 暴击风暴
	SynergyRegistry.register("projectile_hit", _on_m8)          ## 猎头（斩杀判定）
	## N2 新增机制（crit_m1..m9 / 致命节奏触发式）
	SynergyRegistry.register("projectile_hit", _on_n2_m1)       ## 暴M1 溢出转真伤
	SynergyRegistry.register("projectile_hit", _on_n2_m2)       ## 暴M2 暴击吸血
	SynergyRegistry.register("projectile_hit", _on_n2_m3)       ## 暴M3 暴击连击
	SynergyRegistry.register("projectile_hit", _on_n2_m4)       ## 暴M4 暴击减速
	SynergyRegistry.register("projectile_hit", _on_n2_m5)       ## 暴M5 暴击爆炸
	SynergyRegistry.register("projectile_hit", _on_n2_m6)       ## 暴M6 暴击穿透
	SynergyRegistry.register("projectile_hit", _on_n2_m7)       ## 暴M7 暴击回能
	SynergyRegistry.register("projectile_hit", _on_n2_m8)       ## 暴M8 完美暴击
	SynergyRegistry.register("projectile_hit", _on_n2_m9)       ## 暴M9 暴击攻速
	## 暴M1 溢出转伤为被动属性转换，无独立回调：_sync_stats() 常驻刷新
	_sync_stats(true)
	print("[SYNERGY] crit_synergy registered")


func _process(delta: float) -> void:
	if not is_inside_tree():
		return
	_sync_timer -= delta
	if _sync_timer <= 0.0:
		_sync_timer = SYNC_GAP
		_sync_stats(false)
	_m3_tokens = minf(_m3_tokens + M3_RATE * delta, M3_BURST)
	if _m8_left > 0.0:
		_m8_left -= delta
		if _m8_left <= 0.0:
			_m8_bonus = 0.0
			_sync_stats(true)
	_prune_trackers()
	_tick_n2_haste(delta)


## ===== N2 新增机制（crit_m1..m9 + 致命节奏触发式攻速）=====

## N2 暴M1 暴击溢出：暴击率超过 100% 的部分按层转真伤（每层转化 ×1，上限 ×2）
func _on_n2_m1(ctx: Dictionary) -> void:
	if _stacks(CM1) <= 0:
		return
	var enemy = ctx.get("enemy")
	if not is_instance_valid(enemy):
		return
	# 有效暴击率溢出（projectile 暴击判定时写入 run.crit_overflow）
	var overflow := float(GameState.run.get("crit_overflow", 0.0))
	if overflow <= 0.0:
		return
	var dmg := maxi(int(ctx.get("dmg", 0)), 0)
	if dmg <= 0:
		return
	var bonus := maxi(roundi(float(dmg) * overflow * minf(float(_stacks(CM1)), N2_M1_OVERFLOW_CAP)), 1)
	if enemy.has_method("_take_raw"):
		enemy.call("_take_raw", bonus)
		EventBus.damage_dealt.emit(bonus, _enemy_pos(enemy), false)


## N2 暴M2 暴击吸血：暴击回复该次伤害 2%/层 生命（上限 10%）
func _on_n2_m2(ctx: Dictionary) -> void:
	if _stacks(CM2) <= 0 or not bool(ctx.get("crit", false)):
		return
	var dmg := maxi(int(ctx.get("dmg", 0)), 0)
	if dmg <= 0:
		return
	var rate := minf(N2_M2_LEECH * float(_stacks(CM2)), N2_M2_LEECH_CAP)
	var healed := GameState.heal(float(dmg) * rate)
	if healed > 0:
		EventBus.fx_heal_text.emit(_enemy_pos(ctx.get("enemy")), healed)


## N2 暴M3 暴击连击：连续暴击伤害 +15%/层，未暴击命中不享受连击加成并直接重置
func _on_n2_m3(ctx: Dictionary) -> void:
	if _stacks(CM3) <= 0:
		return
	var enemy = ctx.get("enemy")
	if not is_instance_valid(enemy):
		return
	var dmg := maxi(int(ctx.get("dmg", 0)), 0)
	if dmg <= 0:
		return
	if bool(ctx.get("crit", false)):
		## 只有暴击命中才结算连击加成（此前非暴击也按旧连击数加成，语义错误）
		if _n2_combo > 0:
			var bonus := maxi(roundi(float(dmg) * N2_M3_BONUS * float(_n2_combo) * float(_stacks(CM3))), 1)
			_hit_enemy(enemy, bonus, str(ctx.get("element", "")), false)
		_n2_combo = mini(_n2_combo + 1, N2_M3_MAX)
	else:
		## 非暴击：不享受连击加成，连击直接清零
		_n2_combo = 0


## N2 暴M4 暴击减速：暴击使目标减速 0.8s/层
func _on_n2_m4(ctx: Dictionary) -> void:
	if _stacks(CM4) <= 0 or not bool(ctx.get("crit", false)):
		return
	var enemy = ctx.get("enemy")
	if not is_instance_valid(enemy) or enemy.get("_slow_left") == null:
		return
	var t := N2_M4_SLOW * float(_stacks(CM4))
	enemy.set("_slow_left", maxf(float(enemy.get("_slow_left")), t))


## N2 暴M5 暴击爆炸：暴击 30% 概率（每层 +10%，上限 80%）范围爆炸 50% 暴击伤害
func _on_n2_m5(ctx: Dictionary) -> void:
	if _stacks(CM5) <= 0 or not bool(ctx.get("crit", false)):
		return
	var chance := clampf(N2_M5_CHANCE + N2_M5_CHANCE_PER * float(_stacks(CM5) - 1), N2_M5_CHANCE, N2_M5_CHANCE_CAP)
	if randf() >= chance:
		return
	var enemy = ctx.get("enemy")
	if not is_instance_valid(enemy):
		return
	var dmg := maxi(int(ctx.get("dmg", 0)), 0)
	if dmg <= 0:
		return
	var pos := _ctx_pos(ctx, enemy)
	var element := str(ctx.get("element", ""))
	if EventBus != null:
		EventBus.fx_explosion.emit(pos, element)
	_damage_aoe(pos, N2_M5_RADIUS, maxi(roundi(float(dmg) * N2_M5_DMG), 1), element, enemy)


## N2 暴M6 暴击穿透：暴击补足护甲减免的伤害（真伤，无视护甲）
func _on_n2_m6(ctx: Dictionary) -> void:
	if _stacks(CM6) <= 0 or not bool(ctx.get("crit", false)):
		return
	var enemy = ctx.get("enemy")
	if not is_instance_valid(enemy):
		return
	var dmg := maxi(int(ctx.get("dmg", 0)), 0)
	if dmg <= 0:
		return
	var armor := clampf(_fget(enemy, "armor", 0.0), 0.0, 0.95)
	if armor <= 0.0:
		return
	var bonus := maxi(roundi(float(dmg) * armor), 1)
	if enemy.has_method("_take_raw"):
		enemy.call("_take_raw", bonus)
		EventBus.damage_dealt.emit(bonus, _enemy_pos(enemy), true)


## N2 暴M7 暴击回能：暴击回复 1%/层 技能冷却（上限 5%）
func _on_n2_m7(ctx: Dictionary) -> void:
	if _stacks(CM7) <= 0 or not bool(ctx.get("crit", false)):
		return
	var pct := minf(N2_M7_REFUND * float(_stacks(CM7)), N2_M7_CAP)
	var sc := _find_spell_caster()
	if sc == null:
		return
	var cds_v = sc.get("_cds")
	if not (cds_v is Array) or (cds_v as Array).is_empty():
		return
	var cds: Array = cds_v
	for i in cds.size():
		var cur := float(cds[i])
		if cur > 0.0:
			cds[i] = maxf(cur * (1.0 - pct), 0.0)


## N2 暴M8 完美暴击：暴击伤害 ≥2.0（每层阈值 -0.15）时非暴击按当前暴击率重掷
func _on_n2_m8(ctx: Dictionary) -> void:
	if _stacks(CM8) <= 0 or bool(ctx.get("crit", false)):
		return
	var enemy = ctx.get("enemy")
	if not is_instance_valid(enemy):
		return
	var dmg := maxi(int(ctx.get("dmg", 0)), 0)
	if dmg <= 0:
		return
	var threshold := maxf(N2_M8_BASE - N2_M8_THRESHOLD_PER * float(_stacks(CM8) - 1), 1.5)
	var crit_mult := float(GameState.run.get("crit_dmg_bonus", 1.5))
	if crit_mult < threshold:
		return
	if randf() < clampf(float(GameState.run.get("crit_chance", 0.03)), 0.0, 1.0):
		_force_crit(ctx, enemy)


## N2 暴M9 暴击攻速（与致命节奏共用）：暴击后 2s 内攻速 +4%/层（上限 20%）
func _on_n2_m9(ctx: Dictionary) -> void:
	if not bool(ctx.get("crit", false)):
		return
	var stacks := _stacks(CM9) + _stacks(HASTE_ITEM)
	if stacks <= 0:
		return
	var rate := minf(N2_HASTE_RATE * float(stacks), N2_HASTE_CAP)
	_n2_haste_rate = maxf(_n2_haste_rate, rate)
	_n2_haste_left = N2_HASTE_TIME
	if GameState != null:
		GameState.run.crit_haste_bonus = _n2_haste_rate
	if EventBus != null:
		EventBus.player_stats_changed.emit()


## N2 触发式攻速每帧结算：技能冷却额外流逝（等效攻速加成）
func _tick_n2_haste(delta: float) -> void:
	if _n2_haste_left <= 0.0:
		return
	_n2_haste_left -= delta
	var sc := _find_spell_caster()
	if sc != null:
		var cds_v = sc.get("_cds")
		if cds_v is Array:
			var cds: Array = cds_v
			for i in cds.size():
				var cur := float(cds[i])
				if cur > 0.0:
					cds[i] = maxf(cur - delta * _n2_haste_rate, 0.0)
	if _n2_haste_left <= 0.0:
		_n2_haste_rate = 0.0
		if GameState != null:
			GameState.run.crit_haste_bonus = 0.0
		if EventBus != null:
			EventBus.player_stats_changed.emit()


## ===== 链起始快照：记录本次 projectile_hit 触发链的初始血量 =====
func _on_chain_begin(ctx: Dictionary) -> void:
	_forced_extra = 0
	_forced_crit = false
	var enemy = ctx.get("enemy")
	_chain_hp0 = _fget(enemy, "hp", 0.0) if is_instance_valid(enemy) else 0.0


## ===== 暴M2 致命连击：连续暴击时下一击伤害 +20%/层（可叠加）=====
func _on_m2(ctx: Dictionary) -> void:
	if _stacks(M2) <= 0:
		return
	var enemy = ctx.get("enemy")
	if not is_instance_valid(enemy):
		return
	var dmg := maxi(int(ctx.get("dmg", 0)), 0)
	if dmg <= 0:
		return
	var element := str(ctx.get("element", ""))
	## 处于连击层数时，本击（连击后的"下一击"）先吃满加成，再更新层数
	if _m2_stacks > 0:
		var bonus := maxi(roundi(float(dmg) * M2_BONUS * float(_m2_stacks)), 1)
		_hit_enemy(enemy, bonus, element, false)
	if bool(ctx.get("crit", false)):
		_m2_stacks = mini(_m2_stacks + 1, M2_MAX)
	else:
		_m2_stacks = 0
	if GameState != null:
		GameState.run.crit_combo_stacks = _m2_stacks  ## HUD 消费点


## ===== 暴M3 暴击弹射：暴击时弹射 50% 伤害追踪弹幕 =====
func _on_m3(ctx: Dictionary) -> void:
	if _stacks(M3) <= 0 or not bool(ctx.get("crit", false)):
		return
	var enemy = ctx.get("enemy")
	if not is_instance_valid(enemy):
		return
	var dmg := maxi(int(ctx.get("dmg", 0)), 0)
	if dmg <= 0:
		return
	var pos := _ctx_pos(ctx, enemy)
	var element := str(ctx.get("element", ""))
	## 弹射数随持有 crit_ 构筑数提升：每 2 件 +1 发，上限 3 发
	var shots := clampi(1 + (_crit_count() - 1) / 2, 1, 3)
	for _i in shots:
		if _m3_tokens < 1.0:
			return
		_m3_tokens -= 1.0
		_fire_ricochet(pos, enemy, dmg, element)


func _fire_ricochet(pos: Vector2, source, dmg: int, element: String) -> void:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	var dir := Vector2.RIGHT
	var target := _random_enemy_other(pos, M3_SEEK, source)
	if target != null and target is Node2D:
		var to := (target as Node2D).global_position - pos
		if to.length_squared() > 0.01:
			dir = to.normalized()
	# 池化：经 obtain 复用弹幕实例
	PROJECTILE_SCRIPT.obtain({
		"position": pos,
		"direction": dir,
		"speed": M3_SPEED,
		"range": M3_RANGE,
		"damage": maxf(float(dmg) * M3_DMG_MULT, 1.0),
		"element": element,
		"aoe": 0.0,
		"mods": {"homing": true},
	}, tree.current_scene)


## ===== 暴M4 弱点标记：暴击后标记目标 3s，被标记者受伤 +15% =====
func _on_m4(ctx: Dictionary) -> void:
	if _stacks(M4) <= 0:
		return
	var enemy = ctx.get("enemy")
	if not is_instance_valid(enemy):
		return
	var eid: int = enemy.get_instance_id()
	var now := _now()
	## 标记生效期间命中的目标先吃加成，再决定是否刷新标记
	if _m4_marks.has(eid) and float(_m4_marks[eid]) > now:
		var dmg := maxi(int(ctx.get("dmg", 0)), 0)
		if dmg > 0:
			var bonus := maxi(roundi(float(dmg) * _m4_bonus()), 1)
			_hit_enemy(enemy, bonus, str(ctx.get("element", "")), false)
	if bool(ctx.get("crit", false)):
		_m4_marks[eid] = now + M4_DURATION


func _m4_bonus() -> float:
	return clampf(M4_BONUS + 0.01 * float(maxi(_crit_count() - 1, 0)), M4_BONUS, 0.45)


## ===== 暴M5 暴风扩散：暴击时概率让周围敌人吃 50% 暴击伤害 =====
func _on_m5(ctx: Dictionary) -> void:
	if _stacks(M5) <= 0 or not bool(ctx.get("crit", false)):
		return
	var enemy = ctx.get("enemy")
	if not is_instance_valid(enemy):
		return
	var chance := clampf(M5_CHANCE + 0.015 * float(maxi(_crit_count() - 1, 0)), M5_CHANCE, 0.40)
	if randf() >= chance:
		return
	var dmg := maxi(int(ctx.get("dmg", 0)), 0)
	if dmg <= 0:
		return
	var pos := _ctx_pos(ctx, enemy)
	var radius := clampf(M5_RADIUS + 4.0 * float(maxi(_crit_count() - 1, 0)), 70.0, 150.0)
	var hit := maxi(roundi(float(dmg) * M5_DMG_MULT), 1)
	var element := str(ctx.get("element", ""))
	if EventBus != null:
		EventBus.fx_explosion.emit(pos, element)
	_damage_aoe(pos, radius, hit, element, enemy)  ## 原目标已吃满暴击，不重复结算


## ===== 暴M6 终结：对低于 25% 生命敌人必暴击（补足暴击差额伤害）=====
func _on_m6(ctx: Dictionary) -> void:
	if _stacks(M6) <= 0 or bool(ctx.get("crit", false)):
		return
	var enemy = ctx.get("enemy")
	if not is_instance_valid(enemy):
		return
	var max_hp := _fget(enemy, "max_hp", 0.0)
	var hp := _fget(enemy, "hp", 0.0)
	if max_hp <= 0.0 or hp <= 0.0:
		return
	var threshold := clampf(M6_THRESHOLD + 0.02 * float(maxi(_crit_count() - 1, 0)), M6_THRESHOLD, 0.50)
	if hp > max_hp * threshold:
		return
	_force_crit(ctx, enemy)


## ===== 暴M9 致命一击：首次命中每个敌人必暴击（持有数提升必暴次数）=====
func _on_m9(ctx: Dictionary) -> void:
	if _stacks(M9) <= 0:
		return
	var enemy = ctx.get("enemy")
	if not is_instance_valid(enemy):
		return
	var eid: int = enemy.get_instance_id()
	var done := int(_m9_hits.get(eid, 0))
	var needed := clampi(1 + (_crit_count() - 1) / 3, 1, 3)
	if done >= needed:
		return
	_m9_hits[eid] = done + 1
	if not bool(ctx.get("crit", false)):
		_force_crit(ctx, enemy)


## 强制暴击：补足差额伤害 = 本次伤害 × (暴伤倍率 - 1)，等效本击即为暴击
func _force_crit(ctx: Dictionary, enemy) -> void:
	var dmg := maxi(int(ctx.get("dmg", 0)), 0)
	if dmg <= 0:
		return
	var mult := 1.5
	if GameState != null:
		mult = maxf(float(GameState.run.get("crit_dmg_bonus", 1.5)), 1.0)
	if mult <= 1.0:
		return
	var extra := maxi(roundi(float(dmg) * (mult - 1.0)), 1)
	if _hit_enemy(enemy, extra, str(ctx.get("element", "")), true):
		_forced_extra += extra
		_forced_crit = true


## ===== 暴M7 暴击回响：暴击回复 1% 技能冷却（全法术）=====
func _on_m7(ctx: Dictionary) -> void:
	if _stacks(M7) <= 0 or not bool(ctx.get("crit", false)):
		return
	var pct := clampf(M7_PCT * float(maxi(_crit_count(), 1)), 0.01, 0.06)
	var sc := _find_spell_caster()
	if sc == null:
		return
	var cds_v = sc.get("_cds")
	if not (cds_v is Array) or (cds_v as Array).is_empty():
		return
	var cds: Array = cds_v
	for i in cds.size():
		var cur := float(cds[i])
		if cur > 0.0:
			cds[i] = maxf(cur * (1.0 - pct), 0.0)


## ===== 暴M8 猎头：暴击击杀后 3s 内暴击率 +15% =====
func _on_m8(ctx: Dictionary) -> void:
	if _stacks(M8) <= 0:
		return
	var enemy = ctx.get("enemy")
	if not is_instance_valid(enemy):
		return
	var dmg := maxi(int(ctx.get("dmg", 0)), 0)
	if dmg <= 0:
		return
	var is_crit := bool(ctx.get("crit", false)) or _forced_crit
	## 斩杀判定：按链起始血量与本次全部伤害（含 M6/M9 追加）估算，考虑护甲减伤
	var armor := clampf(_fget(enemy, "armor", 0.0), 0.0, 0.95)
	var dealt := float(dmg + _forced_extra) * (1.0 - armor)
	if is_crit and _chain_hp0 > 0.0 and dealt >= _chain_hp0:
		_m8_left = M8_DURATION
		var new_bonus := clampf(M8_BONUS + 0.01 * float(maxi(_crit_count() - 1, 0)), M8_BONUS, 0.35)
		if absf(new_bonus - _m8_bonus) > 0.0001:
			_m8_bonus = new_bonus
			_sync_stats(true)


## ===== 暴M10 暴击风暴：暴击时全屏粒子 + 小慢动作（爽感强化）=====
func _on_m10(ctx: Dictionary) -> void:
	if _stacks(M10) <= 0 or not bool(ctx.get("crit", false)):
		return
	var now := _now()
	var interval := clampf(M10_INTERVAL - 0.06 * float(maxi(_crit_count() - 1, 0)), 0.4, M10_INTERVAL)
	if now - _m10_last < interval:
		return
	_m10_last = now
	var pos := _ctx_pos(ctx, ctx.get("enemy"))
	if EventBus == null:
		return
	EventBus.fx_explosion.emit(pos, "fire")
	EventBus.screen_shake.emit(0.8)
	EventBus.slow_mo.emit(M10_FACTOR, M10_DURATION)


## ===== 暴M1 溢出转伤 + 数值暴击属性同步（绝对值写入，幂等）=====
## 持有任意 crit_ 构筑时接管 run.crit_chance / run.crit_dmg_bonus 的维护：
## 理论暴击率 = 基础 3% + 眼镜 2%/层 + 敏锐 + 猎杀标记 + 弱点洞悉 - 暴风眼惩罚；
## 暴M1：理论暴击率超过 100% 的部分按 1:1 转暴伤（数值克制）；
## 暴M8：猎头加成并入暴击率（上限随敏锐提升）。
func _sync_stats(force: bool = false) -> void:
	if GameState == null or _crit_count() <= 0:
		return
	var theor := _theoretical_crit_chance()
	var changed := false
	## 暴伤：主线程口径（宝石）+ 处刑者 + 暴风眼 + 暴M1 溢出（1:1）
	var base_dmg := 1.5 * (1.0 + 0.10 * float(_stacks(N2))) \
		+ 0.30 * float(_stacks(N8)) + 0.30 * float(_stacks(N10))
	var overflow := maxf(theor - 1.0, 0.0)
	var target_dmg := base_dmg + overflow
	if absf(float(GameState.run.get("crit_dmg_bonus", 0.0)) - target_dmg) > 0.0001 or force:
		GameState.run.crit_dmg_bonus = target_dmg
		changed = true
	GameState.run.crit_m1_overflow = overflow  ## 主线程读取点
	## 暴击率：上限 = 0.85 + 敏锐（硬上限 1.0），猎头加成并入
	var cap := minf(0.85 + _curve_value(N3), 1.0)
	var target_chance := clampf(theor + _m8_bonus, 0.0, cap)
	if absf(float(GameState.run.get("crit_chance", 0.0)) - target_chance) > 0.0001 or force:
		GameState.run.crit_chance = target_chance
		changed = true
	GameState.run.crit_hunt_bonus = _m8_bonus  ## 主线程读取点
	if changed and EventBus != null:
		EventBus.player_stats_changed.emit()


func _theoretical_crit_chance() -> float:
	var v := 0.03 + 0.02 * float(_stacks(N1))
	v += _curve_value(N3)
	v += _curve_value(N4)  ## 条件暴击（精英/Boss）计入理论值（近似）
	v += _curve_value(N6)  ## 条件暴击（低血）计入理论值（近似）
	v += _curve_penalty(N10)
	return maxf(v, 0.0)


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


## 暴风眼（暴10）为 tradeoff 曲线：crit_penalty 字段为每层暴击率惩罚
func _curve_penalty(id: String) -> float:
	if GameState == null:
		return 0.0
	var def: Dictionary = GameState.item_def(id)
	if def.is_empty():
		return 0.0
	var c: Dictionary = def.get("curve", {})
	return float(c.get("crit_penalty", 0.0)) * float(_stacks(id))


## 持有 crit_ 前缀构筑总件数（含已有道具 crit_glasses/crit_gem）→ 机制强度标尺
func _crit_count() -> int:
	if GameState == null or GameState.run == null:
		return 0
	var total := 0
	for item_id in GameState.run.items:
		if str(item_id).begins_with("crit_"):
			total += int(GameState.run.items[item_id])
	return total


func _hit_enemy(enemy, dmg: int, element: String, crit: bool) -> bool:
	if not is_instance_valid(enemy) or dmg <= 0:
		return false
	if _iget(enemy, "_dead", false):
		return false
	if not enemy.has_method("take_damage"):
		return false
	enemy.take_damage(dmg, element, crit)
	if EventBus != null:
		EventBus.damage_dealt.emit(dmg, _enemy_pos(enemy), crit)
	return true


func _damage_aoe(center: Vector2, radius: float, dmg: int, element: String, exclude = null) -> int:
	var tree := get_tree()
	if tree == null:
		return 0
	var hits := 0
	for e in GameState.get_enemies():
		if e == exclude or not is_instance_valid(e) or not (e is Node2D):
			continue
		if _iget(e, "_dead", false):
			continue
		var node := e as Node2D
		if center.distance_to(node.global_position) > radius + node.scale.x * 8.0:
			continue
		if _hit_enemy(e, dmg, element, false):
			hits += 1
	return hits


func _random_enemy_other(pos: Vector2, radius: float, exclude) -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var pool: Array = []
	for e in GameState.get_enemies():
		if e == exclude or not is_instance_valid(e) or not (e is Node2D):
			continue
		if _iget(e, "_dead", false):
			continue
		var node := e as Node2D
		if pos.distance_to(node.global_position) <= radius:
			pool.append(e)
	if pool.is_empty():
		return null
	return pool[randi() % pool.size()]


func _find_spell_caster() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var player := tree.get_first_node_in_group("player")
	if player == null:
		return null
	return player.get_node_or_null("SpellCaster")


func _enemy_pos(enemy) -> Vector2:
	if is_instance_valid(enemy) and enemy is Node2D:
		return (enemy as Node2D).global_position
	return Vector2.ZERO


func _ctx_pos(ctx: Dictionary, enemy) -> Vector2:
	if ctx.has("pos") and ctx.get("pos") is Vector2:
		return ctx.get("pos")
	return _enemy_pos(enemy)


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _prune_trackers() -> void:
	if _m4_marks.size() <= 64 and _m9_hits.size() <= 64:
		return
	var now := _now()
	for d in [_m4_marks, _m9_hits]:
		var dead: Array = []
		for k in d:
			if not is_instance_valid(instance_from_id(int(k))):
				dead.append(k)
		for k in dead:
			d.erase(k)
	if _m4_marks.size() > 256:
		for k in _m4_marks.keys():
			if float(_m4_marks[k]) <= now:
				_m4_marks.erase(k)


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
