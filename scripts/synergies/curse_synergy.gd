extends SynergyBase
## 诅咒弱化流 · 机制脚本（咒M1 传染诅咒 / 咒M2 痛苦加深 / 咒M3 虚弱打击 / 咒M4 恐惧 /
## 咒M5 折磨循环 / 咒M6 失衡 / 咒M7 禁疗领域 / 咒M8 厄运 / 咒M9 反噬 / 咒M10 万咒归一），
## 并承载咒1-咒10 数值构筑在战斗中的实际结算。
##
## 挂载方式：由 SynergyRegistry.load_synergy_scripts() 自动扫描 scripts/synergies/*.gd
## 实例化挂树，_ready() 中注册回调（与 fire/poison 系一致）。
## 强度模型：机制强度由持有的 curse_ 前缀构筑总层数驱动（_curse_power），
## 克制参考：概率 8%-15%、受伤加深 4%/层（上限 25%）、debuff 时长 +15%/层。
## 防御性约定：所有回调先做对象/树/字段有效性检查；回调内不做可能抛错的操作
## （GDScript 无 try/except），保证异常只影响本流派、不扩散到其他流派。
## 已知限制（对主线程的接线说明）：
## - 敌人本体只认 slow/root/blind/burn/poison/freeze 六种 debuff 字段
##   （_slow_left/_root_left/_blind_left/_burn_left/_poison_left/_freeze_left），
##   debuff 层数 = 同时生效的种类数，由本脚本按 enemy instance_id 内部跟踪，
##   并在 _process 节流核对（约 0.25s 一次），死亡时在 enemy_died 钩子里清理；
## - 主代码尚未触发 SynergyRegistry 的 player_hit 钩子：咒M9 反噬同时监听
##   EventBus.player_hit 兜底（attacker 缺省 → 受击点最近敌人），带 0.15s 去重，
##   主线程接好钩子后不会双倍结算；
## - 咒M6 失衡以定身（_root_left）代理眩晕（enemy.gd 中 root 同时阻断移动与攻击）；
## - 咒M4 恐惧直接修改敌人 global_position（enemy.gd 无逃跑状态，不改主文件）；
## - 咒M7 禁疗领域用逐帧血量回滚阻断敌方治疗（enemy.gd 治疗代码不可插入）；
## - 咒5 恶咒术架 / 咒7 恐惧咒 为面板类数值（攻速/敌暴击），由 HUD/主线程按
##   GameState.aggregate_bonus("attack_speed") 等读取；咒8 诅咒精通同时在
##   诅咒之魂拾取（减 CD）中生效；游戏暂无蓝条，回蓝以微量回血占位。

## ===== 机制构筑 id（与 .tools/build_defs/curse.json 的 items 一致）=====
const M1 := "curse_plague"        ## 咒M1 传染诅咒
const M2 := "curse_agony"         ## 咒M2 痛苦加深
const M3 := "curse_weak_strike"   ## 咒M3 虚弱打击
const M4 := "curse_fear"          ## 咒M4 恐惧
const M5 := "curse_agony_loop"    ## 咒M5 折磨循环
const M6 := "curse_unbalance"     ## 咒M6 失衡
const M7 := "curse_no_heal_zone"  ## 咒M7 禁疗领域
const M8 := "curse_doom"          ## 咒M8 厄运
const M9 := "curse_retribution"   ## 咒M9 反噬
const M10 := "curse_all_as_one"   ## 咒M10 万咒归一

## ===== 数值构筑 id（联动读取）=====
const N1 := "curse_ink"           ## 咒1 诅咒墨水：debuff 时长 +15%/层
const N2 := "curse_weak_word"     ## 咒2 虚弱咒：敌人攻击 -6%/层
const N3 := "curse_slow_word"     ## 咒3 失衡咒：敌人移速 -5%/层（与减速叠加）
const N4 := "curse_torment"       ## 咒4 折磨精通：受伤加深（并入咒M2/咒M5）
const N6 := "curse_no_heal_word"  ## 咒6 禁疗咒：敌人治疗 -15%/层
const N8 := "curse_mastery"       ## 咒8 诅咒精通：诅咒系冷却 -7%/层（诅咒之魂拾取）
const N9 := "curse_death_word"    ## 咒9 死咒：敌人生命上限 -3%/层
const N10 := "curse_omen"         ## 咒10 厄运预感：诅咒系暴击率 +5%/层

## ===== 强度常量（克制参考：概率 8%-15%、受伤加深 4%/层上限 25%、时长 +15%/层）=====
const CHANCE_MAX := 0.15          ## 概率上限（克制验收：8%-15%）
const AGONY_PER_LAYER := 0.04     ## 痛苦加深：每层 debuff 受伤 +4%
const AGONY_CAP := 0.25           ## 痛苦加深总上限 25%
const DUR_BONUS := 0.15           ## 诅咒墨水：debuff 时长 +15%/层
const DUR_BONUS_CAP := 3.0        ## 时长加成上限 ×3
const WEAK_PENALTY := 0.20        ## 虚弱打击：攻击 -20%
const WEAK_DURATION := 3.0        ## 虚弱持续 3s
const WEAK_PENALTY_CAP := 0.60    ## 虚弱叠加上限（含咒2 虚弱咒）
const FEAR_DURATION := 2.5        ## 恐惧逃跑持续秒数
const STUN_DURATION := 1.0        ## 失衡眩晕 1s（以定身代理）
const LOOP_THROTTLE := 0.5        ## 折磨循环节流秒数
const LOOP_PCT := 0.01            ## 折磨循环：每层 debuff 每次结算 max_hp 1% 真伤
const AURA_RADIUS := 100.0        ## 禁疗领域基础半径
const AURA_RADIUS_PER := 12.0     ## 禁疗咒每层 +12px 半径
const HEAL_BLOCK_PER := 0.15      ## 禁疗咒：敌人治疗 -15%/层
const RETRIBUTION := 0.10         ## 反噬：基础反弹 10%
const RETRIBUTION_CAP := 0.15     ## 反噬上限 15%
const SPREAD_RADIUS := 110.0      ## 传染/万咒归一转移半径
const CUT_PER := 0.03             ## 死咒：生命上限 -3%/层
const CUT_CAP := 0.30             ## 死咒上限 -30%
const CRIT_PER := 0.05            ## 厄运预感：暴击率 +5%/层
const CRIT_CAP := 0.50            ## 厄运预感上限 50%
const SOUL_MAX := 10              ## 诅咒之魂场上上限
const SOUL_LIFETIME := 20.0       ## 诅咒之魂存活秒数
const SOUL_CD_PCT := 0.15         ## 拾取减 CD 基础 15%
const SOUL_CD_CAP := 0.60         ## 减 CD 上限
const SWEEP_GAP := 15             ## debuff 计数核对节流（帧，≈0.25s@60fps）
const DEBUFF_KINDS := ["slow", "root", "blind", "burn", "poison", "freeze"]

var _debuffs := {}        ## id -> Dictionary{kind:true} 当前生效 debuff 种类（乐观 + 核对）
var _pending_dur := {}    ## id -> Dictionary{kind:mult} 咒1 待写入时长倍率
var _weak_left := {}      ## id -> float 虚弱剩余秒数（咒M3）
var _weak_orig_attack := {}  ## id -> float 虚弱前攻击
var _fear_left := {}      ## id -> float 恐惧剩余秒数（咒M4）
var _loop_cd := {}        ## id -> float 折磨循环节流倒计时（咒M5）
var _slowed_speed := {}   ## id -> float 失衡咒减速前移速（咒3）
var _maxhp_cut := {}      ## id -> true 死咒已生效（咒9）
var _prev_hp := {}        ## id -> float 禁疗领域血量监测（咒M7/咒6）
var _reflect_cd := {}     ## id -> float 反噬去重（咒M9）
var _spread_rolled := {}  ## id -> true 传染已判定（进入 2 debuff 状态时掷一次）
var _fear_rolled := {}    ## id -> true 恐惧已判定（进入 3 debuff 状态时掷一次）
var _stun_rolled := {}    ## id -> true 失衡已判定（进入 4 debuff 状态时掷一次）
var _souls: Array = []    ## 场上诅咒之魂节点
var _sweep := 0
var _player: Node2D


func _ready() -> void:
	super._ready()
	_register("enemy_status", _on_enemy_status)      ## 状态结算（恐惧/失衡补判）
	_register("enemy_hit", _on_enemy_hit)            ## 咒M2 痛苦加深
	_register("enemy_died", _on_enemy_died)          ## 咒M8 厄运 / 咒M10 万咒归一 + 清理
	_register("projectile_hit", _on_projectile_hit)  ## 咒M3 虚弱打击 / 咒10 厄运预感
	_register("player_hit", _on_player_hit)          ## 咒M9 反噬（主线程接线点）
	EventBus.apply_status.connect(_on_apply_status)                 ## debuff 跟踪中枢（传染/折磨循环等）
	EventBus.player_hit.connect(_on_player_hit_event)               ## 咒M9 兜底（当前主代码只发 EventBus）
	print("[SYNERGY] curse_synergy registered")


func _process(delta: float) -> void:
	if not is_inside_tree():
		return
	var dt := minf(delta, 0.1)
	var tree := get_tree()
	if tree != null:
		_player = tree.get_first_node_in_group("player") as Node2D
	_tick_weak(dt)
	_tick_fear(dt)
	_tick_cds(dt)
	_apply_pending_durations()
	_tick_heal_block()
	_sweep += 1
	if _sweep >= SWEEP_GAP:
		_sweep = 0
		_verify_debuffs()
	_prune_trackers()
	_prune_souls()


## 状态结算钩子（burn/poison tick）：DoT 期间补判恐惧/失衡（进入状态只掷一次）
func _on_enemy_status(ctx: Dictionary) -> void:
	if not is_inside_tree():
		return
	if not (ctx is Dictionary):
		return
	var enemy := ctx.get("enemy") as Node2D
	if not is_instance_valid(enemy):
		return
	var id := enemy.get_instance_id()
	_settle(enemy, id, _debuffs.get(id, {}).size())


## ===== 咒M1 传染诅咒 / 咒M4 恐惧 / 咒M5 折磨循环 / 咒M6 失衡 / 咒1/咒3/咒9：debuff 跟踪中枢 =====
func _on_apply_status(target: Node, kind: String, stacks: int) -> void:
	if not is_inside_tree():
		return
	var enemy := target as Node2D
	if not is_instance_valid(enemy) or _iget(enemy, "_dead", false):
		return
	if not kind in DEBUFF_KINDS:
		return
	if enemy.get("_%s_left" % kind) == null:
		return  # 只处理带 debuff 槽的敌人
	var id := enemy.get_instance_id()
	var tracked: Dictionary = _debuffs.get(id, {})
	var refresh := tracked.has(kind)
	tracked[kind] = true
	_debuffs[id] = tracked
	# 咒1 诅咒墨水：时长 +15%/层（下一帧写入，避开 enemy._on_status 的固定时长重置）
	var n1 := _stacks(N1)
	if n1 > 0:
		var pend: Dictionary = _pending_dur.get(id, {})
		pend[kind] = minf(1.0 + DUR_BONUS * float(n1), DUR_BONUS_CAP)
		_pending_dur[id] = pend
	# 咒9 死咒：首个 debuff 时削减生命上限（只生效一次）
	var n9 := _stacks(N9)
	if n9 > 0 and not _maxhp_cut.has(id):
		_maxhp_cut[id] = true
		var cut := minf(CUT_PER * float(n9), CUT_CAP)
		var mhp := maxf(_fget(enemy, "max_hp", 1.0) * (1.0 - cut), 1.0)
		enemy.set("max_hp", mhp)
		enemy.set("hp", minf(_fget(enemy, "hp", mhp), mhp))
	# 咒3 失衡咒：减速时额外削减移速（与减速叠加）
	if kind == "slow":
		var n3 := _stacks(N3)
		if n3 > 0 and not _slowed_speed.has(id):
			_slow_enemy_cut(enemy, id, n3)
	# 咒M5 折磨循环：debuff 刷新（重复施加已生效种类）时造成伤害（每层）
	if _stacks(M5) > 0 and refresh and not _loop_cd.has(id):
		_loop_cd[id] = LOOP_THROTTLE
		var count := tracked.size()
		var dmg := maxi(int(_fget(enemy, "max_hp", 1.0) * LOOP_PCT * float(count) * (1.0 + _curve_value(N4))), 1)
		_raw_dmg(enemy, dmg)
	# 状态结算：跨线触发传染（2 debuff）/恐惧（3+）/失衡（4+）
	_settle(enemy, id, tracked.size())


## 状态结算：进入 2/3/4 debuff 状态时各掷一次（概率 8%-15%，受 curse_ 总层数驱动）
func _settle(enemy: Node2D, id: int, count: int) -> void:
	if count >= 2 and not _spread_rolled.get(id, false) and _stacks(M1) > 0:
		_spread_rolled[id] = true
		if randf() < _chance(0.08):
			_spread_debuff(enemy, id)
	elif count < 2:
		_spread_rolled.erase(id)
	if count >= 3 and not _fear_rolled.get(id, false) and _stacks(M4) > 0:
		_fear_rolled[id] = true
		if randf() < _chance(0.10):
			_fear_left[id] = FEAR_DURATION
			EventBus.fx_hit_slow.emit(enemy, true)  # 保持顿帧 60ms（G-4 分级后）
	elif count < 3:
		_fear_rolled.erase(id)
	if count >= 4 and not _stun_rolled.get(id, false) and _stacks(M6) > 0:
		_stun_rolled[id] = true
		if randf() < _chance(0.08):
			enemy.set("_root_left", maxf(_fget(enemy, "_root_left", 0.0), STUN_DURATION))
			EventBus.fx_hit_flash.emit(enemy)
	elif count < 4:
		_stun_rolled.erase(id)


## 咒M1 传染诅咒：把来源敌人的一个随机生效 debuff 传给附近 1 个未受该 debuff 的敌人
func _spread_debuff(enemy: Node2D, id: int) -> void:
	var kinds: Array = _debuffs.get(id, {}).keys()
	if kinds.is_empty():
		return
	var kind := str(kinds[randi() % kinds.size()])
	var target := _nearest_enemy_without(_enemy_pos(enemy), SPREAD_RADIUS, enemy, kind)
	if target == null:
		return
	EventBus.apply_status.emit(target, kind, 1)
	EventBus.fx_hit_slow.emit(target, true)  # 保持顿帧 60ms（G-4 分级后）


## ===== 咒M2 痛苦加深：敌人每有 1 层 debuff 受伤 +4%（上限 25%）=====
func _on_enemy_hit(ctx: Dictionary) -> void:
	if not is_inside_tree():
		return
	if _stacks(M2) <= 0:
		return
	var enemy := ctx.get("enemy") as Node2D
	if not is_instance_valid(enemy):
		return
	var count: int = _debuffs.get(enemy.get_instance_id(), {}).size()
	if count <= 0:
		return
	var amp := minf((AGONY_PER_LAYER + _curve_value(N4)) * float(count), AGONY_CAP)
	if amp <= 0.0:
		return
	var extra := maxi(int(int(ctx.get("dmg", 0)) * amp), 1)
	_raw_dmg(enemy, extra)


## ===== 咒M3 虚弱打击（攻击被 debuff 敌人附加虚弱）+ 咒10 厄运预感（对 debuff 目标暴击）=====
func _on_projectile_hit(ctx: Dictionary) -> void:
	if not is_inside_tree():
		return
	var enemy := ctx.get("enemy") as Node2D
	if not is_instance_valid(enemy):
		return
	var id := enemy.get_instance_id()
	var count: int = _debuffs.get(id, {}).size()
	if count <= 0:
		return
	if _stacks(M3) > 0 and randf() < _chance(0.10):
		_apply_weakness(enemy, id)
	var n10 := _stacks(N10)
	if n10 > 0 and randf() < minf(CRIT_PER * float(n10), CRIT_CAP):
		var dmg: int = int(ctx.get("dmg", 0))
		var crit_bonus := 0.5
		if GameState != null:
			crit_bonus = float(GameState.run.get("crit_dmg_bonus", 1.5)) - 1.0
		var extra := maxi(int(dmg * crit_bonus), 1)
		## 递归修复（2026-08-11）：enemy_hit 钩子内追加伤害走 _take_raw，
		## 原 take_damage 会再触发 enemy_hit → 无限递归（与圣印同根因）
		if enemy.has_method("_take_raw"):
			enemy.call("_take_raw", extra)
		elif enemy.has_method("take_damage"):
			enemy.call("take_damage", extra, "curse", true)
		EventBus.damage_dealt.emit(extra, enemy.global_position, true)


## ===== 咒M8 厄运（掉诅咒之魂）/ 咒M10 万咒归一（转移全部 debuff）+ 死亡清理 =====
func _on_enemy_died(ctx: Dictionary) -> void:
	if not is_inside_tree():
		return
	var enemy := ctx.get("enemy") as Node2D
	if not is_instance_valid(enemy):
		return
	var id := enemy.get_instance_id()
	var count := 0
	for kind in DEBUFF_KINDS:
		if _fget(enemy, "_%s_left" % kind, 0.0) > 0.0:
			count += 1
	if count > 0:
		if _stacks(M8) > 0 and randf() < _chance(0.08):
			_spawn_soul(_ctx_pos(ctx, enemy))
		if _stacks(M10) > 0:
			_transfer_debuffs(enemy, id)
	_cleanup_enemy(id)


## 咒M10 万咒归一：把来源敌人全部生效 debuff（含剩余时长/DOT）传给最近敌人
func _transfer_debuffs(source: Node2D, sid: int) -> void:
	var active: Array = []
	for kind in DEBUFF_KINDS:
		var left := _fget(source, "_%s_left" % kind, 0.0)
		if left > 0.0:
			active.append([kind, left])
	if active.is_empty():
		return
	var target := _nearest_enemy(_enemy_pos(source), SPREAD_RADIUS, source)
	if target == null:
		return
	for entry in active:
		var kind := str(entry[0])
		var left := float(entry[1])
		EventBus.apply_status.emit(target, kind, 1)  ## 触发传染/折磨循环等联动
		var fname := "_%s_left" % kind
		if target.get(fname) != null:
			target.set(fname, maxf(_fget(target, fname, 0.0), left))
			if kind == "burn" and source.get("_burn_dps") != null:
				target.set("_burn_dps", maxf(_fget(target, "_burn_dps", 0.0), _fget(source, "_burn_dps", 0.0)))
			elif kind == "poison" and source.get("_poison_dps") != null:
				target.set("_poison_dps", maxf(_fget(target, "_poison_dps", 0.0), _fget(source, "_poison_dps", 0.0)))


## ===== 咒M9 反噬：被 debuff 的敌人攻击玩家时反弹伤害（双路径 + 去重）=====
func _on_player_hit(ctx: Dictionary) -> void:
	if not is_inside_tree():
		return
	if _stacks(M9) <= 0:
		return
	var attacker: Node = ctx.get("attacker")
	if not is_instance_valid(attacker):
		attacker = _nearest_enemy(ctx.get("pos", Vector2.ZERO), 100.0, null)
	if not is_instance_valid(attacker):
		return
	_do_reflect(attacker, int(ctx.get("dmg", ctx.get("taken", 0))))


## EventBus.player_hit 兜底（当前主代码只发此信号，无 attacker 上下文）
func _on_player_hit_event(dmg: int, pos: Vector2) -> void:
	if not is_inside_tree():
		return
	if _stacks(M9) <= 0:
		return
	var attacker := _nearest_enemy(pos, 100.0, null)
	if attacker == null:
		return
	_do_reflect(attacker, dmg)


func _do_reflect(attacker: Node2D, dmg: int) -> void:
	var id := attacker.get_instance_id()
	if _reflect_cd.has(id):
		return
	if _debuffs.get(id, {}).size() <= 0:
		return
	_reflect_cd[id] = 0.15
	var pct := clampf(RETRIBUTION + 0.01 * float(maxi(_stacks(M9) - 1, 0)), RETRIBUTION, RETRIBUTION_CAP)
	_raw_dmg(attacker, maxi(int(dmg * pct), 1))
	EventBus.fx_hit_flash.emit(attacker)


## ===== 逐帧维护 =====

## 咒M3 虚弱计时：到期还原攻击
func _tick_weak(dt: float) -> void:
	for id in _weak_left.keys():
		var left := float(_weak_left[id]) - dt
		if left > 0.0:
			_weak_left[id] = left
			continue
		_weak_left.erase(id)
		_restore_weak_attack(id)


## 咒M4 恐惧计时：逃跑期间持续远离玩家
func _tick_fear(dt: float) -> void:
	var pp := _player_pos()
	for id in _fear_left.keys():
		var left := float(_fear_left[id]) - dt
		var enemy := instance_from_id(int(id)) as Node2D
		if not is_instance_valid(enemy):
			_fear_left.erase(id)
			continue
		if left > 0.0:
			_fear_left[id] = left
			var away: Vector2 = enemy.global_position - pp
			if away.length() > 2.0:
				var spd := _fget(enemy, "speed", 60.0)
				var step: Vector2 = away.normalized() * spd * 1.2 * dt
				enemy.global_position = (enemy.global_position + step).clamp(Vector2(24, 210), Vector2(1256, 672))
		else:
			_fear_left.erase(id)


## 节流倒计时（折磨循环 / 反噬去重）
func _tick_cds(dt: float) -> void:
	for d in [_loop_cd, _reflect_cd]:
		for id in d.keys():
			d[id] = float(d[id]) - dt
			if float(d[id]) <= 0.0:
				d.erase(id)


## 咒1 时长倍率落地：在 enemy._on_status 写入固定时长后的下一帧乘上
func _apply_pending_durations() -> void:
	for id in _pending_dur.keys():
		var pend: Dictionary = _pending_dur[id]
		var enemy := instance_from_id(int(id)) as Node2D
		for kind in pend.keys():
			var fname := "_%s_left" % kind
			if not is_instance_valid(enemy) or enemy.get(fname) == null:
				pend.erase(kind)
				continue
			var cur := _fget(enemy, fname, 0.0)
			if cur > 0.0:
				enemy.set(fname, cur * float(pend[kind]))
			pend.erase(kind)
		if pend.is_empty():
			_pending_dur.erase(id)


## 咒M7 禁疗领域（100px 内完全禁疗）+ 咒6 禁疗咒（全局治疗 -15%/层）：逐帧血量回滚
func _tick_heal_block() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var aura_on := _stacks(M7) > 0
	var n6 := _stacks(N6)
	if not aura_on and n6 <= 0:
		return
	var radius := AURA_RADIUS + AURA_RADIUS_PER * float(n6)
	var pp := _player_pos()
	for e in GameState.get_enemies():
		if not is_instance_valid(e):
			continue
		var id := e.get_instance_id()
		var hp := _fget(e, "hp", 0.0)
		if _prev_hp.has(id):
			var prev := float(_prev_hp[id])
			if hp > prev + 0.5:
				var gain := hp - prev
				var eff := 0.0
				if aura_on and pp.distance_to((e as Node2D).global_position) <= radius:
					eff = 1.0
				elif n6 > 0:
					eff = minf(HEAL_BLOCK_PER * float(n6), 0.9)
				if eff > 0.0:
					e.set("hp", prev + gain * (1.0 - eff))
		_prev_hp[id] = hp


## debuff 计数核对：按敌人字段重算实际生效种类（过期清理 + 转移/定身落账）
func _verify_debuffs() -> void:
	for id in _debuffs.keys():
		var enemy := instance_from_id(int(id)) as Node2D
		if not is_instance_valid(enemy):
			_debuffs.erase(id)
			continue
		var actual := {}
		for kind in DEBUFF_KINDS:
			if _fget(enemy, "_%s_left" % kind, 0.0) > 0.0:
				actual[kind] = true
		if actual.is_empty():
			_debuffs.erase(id)
		else:
			_debuffs[id] = actual
		# 咒3 失衡咒：减速结束后还原移速
		if _slowed_speed.has(id) and not actual.has("slow"):
			_restore_speed(id)
		# 状态结算补判（定身/转移等直写字段的落账路径）
		_settle(enemy, id, actual.size())


## ===== 诅咒之魂（咒M8 厄运掉落物）=====

func _spawn_soul(pos: Vector2) -> void:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	if _souls.size() >= SOUL_MAX:
		return
	var area := Area2D.new()
	area.name = "CurseSoul"
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 10.0
	shape.shape = circle
	var vis := Polygon2D.new()
	vis.polygon = PackedVector2Array([Vector2(0, -8), Vector2(6, 0), Vector2(0, 8), Vector2(-6, 0)])
	vis.color = Color(0.62, 0.35, 0.92, 0.95)
	area.add_child(shape)
	area.add_child(vis)
	area.position = pos
	area.monitoring = true
	area.body_entered.connect(_on_soul_body.bind(area))
	var t := tree.create_timer(SOUL_LIFETIME)
	t.timeout.connect(_free_soul.bind(area))
	tree.current_scene.add_child(area)
	_souls.append(area)


func _on_soul_body(body: Node2D, area: Area2D) -> void:
	if body == null or not body.is_in_group("player"):
		return
	_collect_soul(body)
	if is_instance_valid(area):
		area.queue_free()


## 拾取：削减全部法术冷却（咒8 提升幅度）；蓝条未接入，以微量回血占位
func _collect_soul(player: Node2D) -> void:
	var sc := player.get_node_or_null("SpellCaster")
	if sc != null:
		var cds_v = sc.get("_cds")
		if cds_v is Array and not (cds_v as Array).is_empty():
			var pct := clampf(SOUL_CD_PCT + 0.07 * float(_stacks(N8)), 0.0, SOUL_CD_CAP)
			var cds: Array = cds_v
			for i in cds.size():
				var cur := float(cds[i])
				if cur > 0.0:
					cds[i] = maxf(cur * (1.0 - pct), 0.0)
	if GameState != null:
		var healed := GameState.heal(2)
		if healed > 0:
			EventBus.fx_heal_text.emit(player.global_position, healed)
	EventBus.fx_explosion.emit(player.global_position, "poison")


func _free_soul(area: Area2D) -> void:
	if is_instance_valid(area):
		area.queue_free()


func _prune_souls() -> void:
	var i := _souls.size() - 1
	while i >= 0:
		if not is_instance_valid(_souls[i]):
			_souls.remove_at(i)
		i -= 1


## ===== 工具函数（全部防御性）=====

## 机制强度：持有 curse_ 前缀构筑的总层数（含数值与机制构筑）
func _curse_power() -> int:
	if GameState == null or not (GameState.run is Dictionary):
		return 0
	var n := 0
	for id in GameState.run.get("items", {}):
		if str(id).begins_with("curse_"):
			n += int(GameState.run["items"][id])
	return n
func _curve_value(id: String) -> float:
	if GameState == null:
		return 0.0
	var def: Dictionary = GameState.item_def(id)
	if def.is_empty():
		return 0.0
	return float(GameState.item_value(def, _stacks(id)))


## 概率区间 8%-15%：基础值 + 每多 1 件诅咒构筑 +0.5%，封顶 15%
func _chance(base: float) -> float:
	return clampf(base + 0.005 * float(maxi(_curse_power() - 1, 0)), base, CHANCE_MAX)


## 咒M3 虚弱：攻 -20%（咒2 每层再 -6%），持续 3s
func _apply_weakness(enemy: Node2D, id: int) -> void:
	if enemy.get("attack") == null:
		return
	var penalty := minf(WEAK_PENALTY + 0.06 * float(_stacks(N2)), WEAK_PENALTY_CAP)
	if _weak_left.has(id) and _weak_orig_attack.has(id):
		_weak_left[id] = WEAK_DURATION
		enemy.set("attack", maxi(int(float(_weak_orig_attack[id]) * (1.0 - penalty)), 1))
		return
	_weak_orig_attack[id] = _fget(enemy, "attack", 0.0)
	enemy.set("attack", maxi(int(_fget(enemy, "attack", 0.0) * (1.0 - penalty)), 1))
	_weak_left[id] = WEAK_DURATION


func _restore_weak_attack(id: int) -> void:
	if not _weak_orig_attack.has(id):
		return
	var enemy := instance_from_id(int(id))
	if is_instance_valid(enemy) and enemy.get("attack") != null:
		enemy.set("attack", _weak_orig_attack[id])
	_weak_orig_attack.erase(id)


## 咒3 失衡咒：减速时移速 -5%/层（与减速叠加），上限 -50%
func _slow_enemy_cut(enemy: Node2D, id: int, n3: int) -> void:
	if enemy.get("speed") == null:
		return
	_slowed_speed[id] = _fget(enemy, "speed", 0.0)
	var cut := minf(0.05 * float(n3), 0.50)
	enemy.set("speed", maxf(_fget(enemy, "speed", 0.0) * (1.0 - cut), 20.0))


func _restore_speed(id: int) -> void:
	if not _slowed_speed.has(id):
		return
	var enemy := instance_from_id(int(id))
	if is_instance_valid(enemy) and enemy.get("speed") != null:
		enemy.set("speed", _slowed_speed[id])
	_slowed_speed.erase(id)


## 真伤入口（绕过护甲/敌人受击钩子，避免递归）；缺失时回退普通伤害
func _raw_dmg(enemy: Node2D, dmg: int) -> void:
	if dmg <= 0 or not is_instance_valid(enemy):
		return
	if enemy.has_method("_take_raw"):
		enemy.call("_take_raw", dmg)
	elif enemy.has_method("take_damage"):
		enemy.call("take_damage", dmg, "curse", false)


## 死亡清理：还原属性并清空全部跟踪状态（enemy_died 钩子内调用）
func _cleanup_enemy(id: int) -> void:
	_restore_weak_attack(id)
	_restore_speed(id)
	for d in [_debuffs, _pending_dur, _weak_left, _fear_left, _loop_cd, _slowed_speed,
			_maxhp_cut, _prev_hp, _reflect_cd, _spread_rolled, _fear_rolled, _stun_rolled]:
		d.erase(id)


func _tracker_dicts() -> Array:
	return [_debuffs, _pending_dur, _weak_left, _weak_orig_attack, _fear_left, _loop_cd,
			_slowed_speed, _maxhp_cut, _prev_hp, _reflect_cd, _spread_rolled, _fear_rolled, _stun_rolled]


## 兜底清理：任意跟踪表超阈值时扫描并剔除已释放实例（防异常路径泄漏）
func _prune_trackers() -> void:
	var total := 0
	for d in _tracker_dicts():
		total += d.size()
	if total <= 256:
		return
	for d in _tracker_dicts():
		var dead: Array = []
		for k in d:
			if not is_instance_valid(instance_from_id(int(k))):
				dead.append(k)
		for k in dead:
			d.erase(k)


func _enemy_pos(enemy) -> Vector2:
	if is_instance_valid(enemy) and enemy is Node2D:
		return (enemy as Node2D).global_position
	return Vector2.ZERO


func _ctx_pos(ctx: Dictionary, enemy) -> Vector2:
	if ctx.has("pos") and ctx.get("pos") is Vector2:
		return ctx.get("pos")
	return _enemy_pos(enemy)


func _player_pos() -> Vector2:
	var p: Node2D = _player
	if not is_instance_valid(p):
		var tree := get_tree()
		if tree != null:
			p = tree.get_first_node_in_group("player") as Node2D
	if p == null:
		return Vector2.ZERO
	return p.global_position


func _nearest_enemy(pos: Vector2, radius: float, exclude: Node) -> Node2D:
	var tree := get_tree()
	if tree == null:
		return null
	var best: Node2D = null
	var bd := INF
	for e in GameState.get_enemies():
		if e == exclude or not is_instance_valid(e):
			continue
		var node := e as Node2D
		if node == null or _iget(e, "_dead", false):
			continue
		var d: float = pos.distance_to(node.global_position)
		if d <= radius and d < bd:
			bd = d
			best = node
	return best


## 传染专用：半径内最近且未携带指定 debuff 的存活敌人
func _nearest_enemy_without(pos: Vector2, radius: float, exclude: Node, avoid_kind: String) -> Node2D:
	var tree := get_tree()
	if tree == null:
		return null
	var best: Node2D = null
	var bd := INF
	for e in GameState.get_enemies():
		if e == exclude or not is_instance_valid(e):
			continue
		var node := e as Node2D
		if node == null or _iget(e, "_dead", false):
			continue
		if _fget(e, "_%s_left" % avoid_kind, 0.0) > 0.0:
			continue
		var d: float = pos.distance_to(node.global_position)
		if d <= radius and d < bd:
			bd = d
			best = node
	return best


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
