extends Node
## 移速疾风流机制脚本（10 机制，SynergyRegistry 钩子实现）
## ============================================================
## 挂载方式：由 SynergyRegistry.load_synergy_scripts() 自动扫描
## scripts/synergies/*.gd 并实例化挂树，_ready() 中自动注册全部回调。
## 设计文档：docs/design/流派构筑大全.md 第 11 章「移速疾风流」
## （核心：移速 → 攻速联动，跑得快打得快，风筝与走位本身就是输出）。
## 强度模型：机制强度由持有 wind_ 前缀构筑总层数控制（_wind_power()，
## 即 GameState.run.items 中 id 以 "wind_" 开头的堆叠数之和）。
## 钩子使用：
##   player_move     移M1 风切 / 移M3 影步 / 移M5 疾风领域 /
##                   移M6 破风 / 移M8 风之回响（+ 移动状态采集）
##   cast            移M4 追风猎手 / 移M7 顺风弹（+ 移6 风刃读取点刷新）
##   player_hit      移M2 踏风 / 移M3 影步（受击未受伤 = 闪避事件）
##   enemy_died      移4 追风（击杀 → 短时移速）
##   projectile_hit  移M9 急冻风
##   _process 轮询：移速→攻速联动（移2/移5）、暴走（移M10）、
##       各临时增益计时与风痕/风域/风刃区域 tick。
## 防御性约定：所有回调先做对象/树/字段有效性检查；回调内不做可能抛错的
## 操作（GDScript 无 try/except），保证异常只影响本流派、不扩散到其他流派。
## 已知限制（对主线程的接线说明）：
## - game_root 暂无"闪避"结算：移M2/移M3 以 player_hit.taken<=0（完全免伤）
##   近似闪避事件；移3 轻身的闪避率暴露为 run.wind_dodge_chance，由主线程
##   接入受击流程后闪避才完整生效；
## - 移M4 弹数 / 移M7 顺风弹伤害 / 移M9 减速概率 / 移M10 暴走等写入
##   run.wind_* 读取点（与火M2 run.fire_m2_atk_speed 约定一致），主线程接线后生效；
## - 攻速统一走 run.attack_speed_bonus 自校正写入（与近M3/近M9 同款约定），
##   本脚本贡献部分另暴露 run.wind_as_bonus / wind_link_as / wind_m2_atk_speed /
##   wind_m10_as_bonus 读取点；
## - 主线程接线前，本脚本内部以 aggregate_bonus("speed") + run.wind_kill_speed_bonus
##   + run.wind_m6_speed_bonus 作为"当前移速加成"口径（与 player._move_speed
##   的最终公式一致），供高速阈值/暴走/联动计算。

## ===== 机制构筑 id（与 .tools/build_defs/wind.json 的 items 一致）=====
const M1 := "wind_slice"          ## 移M1 风切
const M2 := "wind_step"           ## 移M2 踏风
const M3 := "wind_shadow"         ## 移M3 影步
const M4 := "wind_hunter"         ## 移M4 追风猎手
const M5 := "wind_domain"         ## 移M5 疾风领域
const M6 := "wind_break"          ## 移M6 破风
const M7 := "wind_tail_shot"      ## 移M7 顺风弹
const M8 := "wind_echo"           ## 移M8 风之回响
const M9 := "wind_frost"          ## 移M9 急冻风
const M10 := "wind_berserk"       ## 移M10 暴走

## ===== 数值构筑 id（联动读取）=====
const N1 := "wind_boots"          ## 移1 疾风靴
const N2 := "wind_blessing"       ## 移2 风之祝福
const N3 := "wind_feather"        ## 移3 轻身
const N4 := "wind_chase"          ## 移4 追风
const N5 := "wind_grimoire"       ## 移5 疾风术架
const N6 := "wind_blade"          ## 移6 风刃
const N7 := "wind_tailwind"       ## 移7 顺风
const N8 := "wind_surf"           ## 移8 踏浪
const N9 := "wind_haste"          ## 移9 迅捷
const N10 := "wind_walker"        ## 移10 风行者

## ===== 强度常量（克制参考：概率 15-25%、暴走阈值 250% 移速）=====
const FAST_PCT := 0.8             ## "高速移动"阈值：≥80% 当前最大移速
const POWER_K := 0.10             ## 机制强度成长：每多 1 点 wind_ 构筑 +10%
const M1_GAP := 48.0              ## 风切：风痕生成间距（px）
const M1_DPS := 30.0              ## 风切：基础每秒伤害
const M1_DPS_K := 12.0            ## 风切：每层 +12 dps
const M1_RADIUS := 46.0           ## 风切：风痕半径
const M1_RADIUS_K := 4.0          ## 风切：每层 +4px 半径
const M1_TICK := 0.15             ## 风切：伤害判定间隔（≈dps 换算）
const M1_LEFT := 0.8              ## 风切：风痕持续秒数
const M1_MAX := 28                ## 风切：风痕数量上限（防堆积）
const M2_AS := 0.40               ## 踏风：闪避后攻速加成
const M2_DURATION := 2.0          ## 踏风：持续时间
const M3_INVULN := 0.3            ## 影步：无敌时长
const M3_GAP := 1.8               ## 影步：高速移动触发间隔（持续高速时周期性触发）
const M4_MAX_SHOTS := 3           ## 追风猎手：弹幕上限 +3 发
const M5_FAST_TIME := 2.0         ## 疾风领域：连续高速移动秒数
const M5_RADIUS := 90.0           ## 疾风领域：风域半径
const M5_RADIUS_K := 5.0          ## 疾风领域：每层 +5px 半径
const M5_LEFT := 2.5              ## 疾风领域：风域持续秒数
const M5_TICK := 0.3              ## 疾风领域：减速判定间隔
const M5_MAX := 4                 ## 疾风领域：风域数量上限
const M5_SPAWN_CD := 1.0          ## 疾风领域：生成冷却
const M6_CD_MULT := 0.5           ## 破风：冲刺冷却倍率（-50%）
const M6_SPEED_BONUS := 0.30      ## 破风：冲刺后移速加成
const M6_DURATION := 1.0          ## 破风：移速加成基础持续秒数
const M6_DURATION_K := 0.15       ## 破风：每点 wind_ 构筑 +0.15s
const M7_DMG := 0.20              ## 顺风弹：方向一致增伤
const M7_CAP := 0.50              ## 顺风弹：增伤上限
const M8_DIST := 500.0            ## 风之回响：基础触发距离（px）
const M8_DIST_K := 30.0           ## 风之回响：每层 -30px 触发距离
const M8_DMG := 14.0              ## 风之回响：风刃基础伤害
const M8_DMG_K := 5.0             ## 风之回响：每层 +5 伤害
const M8_SPEED := 420.0           ## 风之回响：风刃飞行速度
const M8_RADIUS := 26.0           ## 风之回响：风刃判定半径
const M8_LEFT := 0.9              ## 风之回响：风刃存续秒数
const M8_MAX := 6                 ## 风之回响：飞行风刃上限
const M9_CHANCE := 0.20           ## 急冻风：基础减速概率
const M9_CHANCE_K := 0.04         ## 急冻风：每层 +4%
const M9_SPEED_LINK := 0.05       ## 急冻风：移速联动（每 100% 移速 +5%）
const M9_CAP := 0.45              ## 急冻风：概率上限
const M9_FAST_LEFT := 1.5         ## 急冻风：施法时高速状态的有效窗口
const M10_SPEED_THRESHOLD := 2.5  ## 暴走：移速 ≥250% 触发
const M10_AS := 0.50              ## 暴走：攻速 +50%
const M10_TAKEN_MULT := 1.20      ## 暴走：受击伤害 +20%（读取点，主线程接线）
const N4_KILL_LEFT := 3.0         ## 追风：击杀移速持续秒数
const N4_CAP := 0.5               ## 追风：移速加成上限
const AS_CAP := 2.0               ## 移速流攻速总加成上限（防失控）

## ===== 运行态 =====
var _m2_bonus := 0.0              ## 踏风当前攻速加成（计入 _sync_as）
var _m2_left := 0.0               ## 踏风剩余秒数
var _m3_cd := 0.0                 ## 影步高速触发冷却
var _m5_fast := 0.0               ## 疾风领域连续高速计时
var _m5_cd := 0.0                 ## 疾风领域生成冷却
var _m6_dashing := false          ## 破风：冲刺中（检测冲刺结束）
var _m6_speed_left := 0.0         ## 破风：冲刺后移速加成剩余秒数
var _m8_dist := 0.0               ## 风之回响累计移动距离
var _m9_fast := false             ## 急冻风：施法时是否高速
var _m9_fast_left := 0.0          ## 急冻风：施法高速状态窗口
var _berserk := false             ## 暴走状态
var _kill_speed_left := 0.0       ## 追风（移4）：击杀移速剩余秒数
var _as_bonus := 0.0              ## 本脚本写入 run.attack_speed_bonus 的贡献
var _slices: Array = []           ## 风切风痕：[{pos, radius, dmg, left, tick}]
var _domains: Array = []          ## 疾风领域风域：[{pos, radius, left, tick}]
var _blades: Array = []           ## 风之回响风刃：[{pos, dir, dmg, radius, left, hit}]


func _ready() -> void:
	if SynergyRegistry == null:
		push_warning("[WindSynergy] SynergyRegistry 不可用，移速流机制未注册")
		return
	SynergyRegistry.register("player_move", _on_move)     ## 移M1/M3/M5/M6/M8
	SynergyRegistry.register("cast", _on_cast)            ## 移M4/M7 + 移6 读取点
	SynergyRegistry.register("player_hit", _on_hit)       ## 移M2/M3
	SynergyRegistry.register("enemy_died", _on_enemy_died) ## 移4 追风
	SynergyRegistry.register("projectile_hit", _on_m9)    ## 移M9 急冻风
	print("[SYNERGY] wind_synergy registered")


func _process(delta: float) -> void:
	if not is_inside_tree():
		return
	var dt := minf(delta, 0.1)
	_tick_timers(dt)
	_tick_slices(dt)
	_tick_domains(dt)
	_tick_blades(dt)
	_sync_read_points()
	_sync_berserk()
	_sync_as()


## ===== 移M1 风切：高速移动时留下伤害风痕 =====
func _on_m1(ctx: Dictionary) -> void:
	var stacks := _stacks(M1)
	if stacks <= 0:
		return
	var player = ctx.get("player")
	if not is_instance_valid(player):
		return
	var vel := _ctx_vel(ctx, player)
	if not _fast_moving(vel):
		return
	_m1_dist_acc(vel, stacks)


func _m1_dist_acc(vel: Vector2, stacks: int) -> void:
	_m1_dist += vel.length() * _last_delta
	if _m1_dist < M1_GAP:
		return
	_m1_dist = 0.0
	if _slices.size() >= M1_MAX:
		_slices.pop_front()
	var player := _player()
	if player == null:
		return
	var power := _wind_power()
	var scale := 1.0 + POWER_K * float(maxi(power - 1, 0))
	_slices.append({
		"pos": player.global_position,
		"radius": clampf((M1_RADIUS + M1_RADIUS_K * float(stacks - 1)) * _area_scale(), 40.0, 90.0),
		"dmg": maxi(int((M1_DPS + M1_DPS_K * float(stacks - 1)) * M1_TICK * _move_dmg_mult() * scale), 1),
		"left": M1_LEFT,
		"tick": 0.0,
	})
	EventBus.fx_explosion.emit(player.global_position, "wind")


func _tick_slices(dt: float) -> void:
	if _slices.is_empty():
		return
	var i := _slices.size() - 1
	while i >= 0:
		var z: Dictionary = _slices[i]
		z["left"] = float(z["left"]) - dt
		z["tick"] = float(z["tick"]) - dt
		if float(z["tick"]) <= 0.0:
			z["tick"] = M1_TICK
			_damage_aoe(z["pos"], float(z["radius"]), int(z["dmg"]))
		if float(z["left"]) <= 0.0:
			_slices.remove_at(i)
		i -= 1


## ===== 移M2 踏风：闪避后 2s 攻速 +40% =====
func _on_m2(ctx: Dictionary) -> void:
	var stacks := _stacks(M2)
	if stacks <= 0:
		return
	## 当前 game_root 广播 taken=结算后伤害：taken<=0 即完全免伤（近似闪避事件）
	if int(ctx.get("taken", -1)) > 0:
		return
	_m2_left = M2_DURATION
	_m2_bonus = M2_AS * (1.0 + POWER_K * float(maxi(_wind_power() - 1, 0)))
	_sync_as()


func _tick_m2(dt: float) -> void:
	if _m2_left <= 0.0:
		return
	_m2_left -= dt
	if _m2_left <= 0.0:
		_m2_bonus = 0.0
		_sync_as()


## ===== 移M3 影步：闪避/高速移动时 0.3s 无敌 =====
func _on_m3(ctx: Dictionary) -> void:
	var stacks := _stacks(M3)
	if stacks <= 0:
		return
	var player = ctx.get("player")
	if is_instance_valid(player):
		var vel := _ctx_vel(ctx, player)
		if _fast_moving(vel) and _m3_cd <= 0.0:
			player.set("_invuln_left", maxf(_fget(player, "_invuln_left", 0.0), M3_INVULN))
			_m3_cd = M3_GAP


func _on_hit(ctx: Dictionary) -> void:
	_on_m2(ctx)
	_on_m3_dodge(ctx)


## 影步：受击未受伤（taken<=0，闪避事件）时直接给 0.3s 无敌
func _on_m3_dodge(ctx: Dictionary) -> void:
	if _stacks(M3) <= 0 or int(ctx.get("taken", -1)) > 0:
		return
	var player := _player()
	if player == null:
		return
	player.set("_invuln_left", maxf(_fget(player, "_invuln_left", 0.0), M3_INVULN))


## ===== 移M4 追风猎手：移速每超 100% 阈值，弹幕 +1 发（最多 +3）=====
func _on_m4(ctx: Dictionary) -> void:
	if GameState == null or not (GameState.run is Dictionary):
		return
	if _stacks(M4) <= 0:
		GameState.run.wind_m4_shots = 0
		return
	## 读取点：主线程施法时在 mods.shots 上追加该值（与火M2 攻速读取点约定一致）
	GameState.run.wind_m4_shots = mini(int(_speed_bonus()), M4_MAX_SHOTS)


## ===== cast 汇总：移M4 / 移M7 + 移6 读取点 + 移M9 高速状态采集 =====
func _on_cast(ctx: Dictionary) -> void:
	_on_m4(ctx)
	_on_m7(ctx)
	var player = ctx.get("player")
	_m9_fast = is_instance_valid(player) and _fast_moving(_fget_vel(player))
	_m9_fast_left = M9_FAST_LEFT if _m9_fast else 0.0


## ===== 移M5 疾风领域：高速移动 2s 后生成减速风域 =====
func _on_m5(ctx: Dictionary) -> void:
	var stacks := _stacks(M5)
	if stacks <= 0:
		return
	var player = ctx.get("player")
	if not is_instance_valid(player):
		return
	var vel := _ctx_vel(ctx, player)
	if _fast_moving(vel):
		_m5_fast += _last_delta
		if _m5_fast >= M5_FAST_TIME and _m5_cd <= 0.0:
			_m5_fast = 0.0
			_m5_cd = M5_SPAWN_CD
			if _domains.size() >= M5_MAX:
				_domains.pop_front()
			_domains.append({
				"pos": player.global_position,
				"radius": clampf(M5_RADIUS + M5_RADIUS_K * float(stacks - 1), 70.0, 130.0),
				"left": M5_LEFT,
				"tick": 0.0,
			})
			EventBus.fx_explosion.emit(player.global_position, "wind")
	else:
		_m5_fast = 0.0


func _tick_domains(dt: float) -> void:
	if _domains.is_empty():
		return
	var i := _domains.size() - 1
	while i >= 0:
		var d: Dictionary = _domains[i]
		d["left"] = float(d["left"]) - dt
		d["tick"] = float(d["tick"]) - dt
		if float(d["tick"]) <= 0.0:
			d["tick"] = M5_TICK
			_slow_aoe(d["pos"], float(d["radius"]))
		if float(d["left"]) <= 0.0:
			_domains.remove_at(i)
		i -= 1


## ===== 移M6 破风：冲刺冷却 -50%，冲刺后移速 +30% 1s =====
func _on_m6(ctx: Dictionary) -> void:
	var player = ctx.get("player")
	if not is_instance_valid(player):
		return
	## 用 player._dash_time_left 精确识别冲刺（冲刺帧内 >0），避免高移速误判
	var dashing := _fget(player, "_dash_time_left", 0.0) > 0.0
	var stacks := _stacks(M6)
	if dashing and not _m6_dashing:
		_m6_dashing = true
		if stacks > 0:
			var max_cd := _dash_cd_max()
			player.set("_dash_cd_left", minf(_fget(player, "_dash_cd_left", 0.0), max_cd * M6_CD_MULT))
			## 读取点：主线程冲刺冷却显示/计时可改读此值
			GameState.run.dash_cd = max_cd * M6_CD_MULT
	elif not dashing and _m6_dashing:
		_m6_dashing = false
		if stacks > 0:
			_m6_speed_left = M6_DURATION + M6_DURATION_K * float(maxi(_wind_power() - 1, 0))
			GameState.run.wind_m6_speed_bonus = M6_SPEED_BONUS
			EventBus.player_stats_changed.emit()


func _tick_m6(dt: float) -> void:
	if _m6_speed_left <= 0.0:
		return
	_m6_speed_left -= dt
	if _m6_speed_left <= 0.0:
		GameState.run.wind_m6_speed_bonus = 0.0
		EventBus.player_stats_changed.emit()


## ===== 移M7 顺风弹：移动方向与攻击方向一致时伤害 +20% =====
func _on_m7(ctx: Dictionary) -> void:
	var stacks := _stacks(M7)
	var player = ctx.get("player")
	if not is_instance_valid(player):
		return
	var vel := _ctx_vel(ctx, player)
	var moving := vel.length() > 30.0
	## 移6 风刃：移动时伤害 +4%/层（读取点，主线程伤害结算时消费）
	GameState.run.wind_m6_move_dmg = _curve_value(N6) if moving else 0.0
	if stacks <= 0:
		GameState.run.wind_m7_dmg = 0.0
		GameState.run.wind_m7_aligned = false
		return
	var aim := _aim_dir(player)
	var aligned := moving and vel.normalized().dot(aim) >= 0.5
	var bonus := M7_DMG * (1.0 + POWER_K * float(maxi(_wind_power() - 1, 0))) if aligned else 0.0
	GameState.run.wind_m7_dmg = minf(bonus, M7_CAP)
	GameState.run.wind_m7_aligned = aligned


## ===== 移M8 风之回响：每移动 500px 触发一道风刃（自动攻击）=====
func _on_m8(ctx: Dictionary) -> void:
	var stacks := _stacks(M8)
	if stacks <= 0:
		return
	var player = ctx.get("player")
	if not is_instance_valid(player):
		return
	var vel := _ctx_vel(ctx, player)
	if vel.length() <= 20.0:
		return
	_m8_dist += vel.length() * _last_delta
	var threshold := maxf(M8_DIST - M8_DIST_K * float(stacks - 1), 260.0)
	if _m8_dist < threshold:
		return
	_m8_dist = 0.0
	if _blades.size() >= M8_MAX:
		_blades.pop_front()
	var power := _wind_power()
	var scale := 1.0 + POWER_K * float(maxi(power - 1, 0))
	_blades.append({
		"pos": player.global_position,
		"dir": _blade_dir(player, vel),
		"dmg": maxi(int((M8_DMG + M8_DMG_K * float(stacks - 1)) * _move_dmg_mult() * scale), 1),
		"radius": M8_RADIUS,
		"left": M8_LEFT,
		"hit": {},
	})
	EventBus.fx_explosion.emit(player.global_position, "wind")


func _tick_blades(dt: float) -> void:
	if _blades.is_empty():
		return
	var i := _blades.size() - 1
	while i >= 0:
		var b: Dictionary = _blades[i]
		b["pos"] = (b["pos"] as Vector2) + (b["dir"] as Vector2) * M8_SPEED * dt
		b["left"] = float(b["left"]) - dt
		_blade_hit(b)
		if float(b["left"]) <= 0.0:
			_blades.remove_at(i)
		i -= 1


func _blade_hit(b: Dictionary) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var pos: Vector2 = b["pos"]
	var radius := float(b["radius"])
	var dmg := int(b["dmg"])
	var hits: Dictionary = b["hit"]
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		var eid := e.get_instance_id()
		if hits.has(eid):
			continue
		var node := e as Node2D
		if pos.distance_to(node.global_position) > radius + node.scale.x * 8.0:
			continue
		if _iget(e, "_dead", false):
			continue
		if e.has_method("take_damage"):
			e.take_damage(dmg, "wind", false)
			EventBus.damage_dealt.emit(dmg, node.global_position, false)
			hits[eid] = true


## ===== 移M9 急冻风：高速时攻击附带减速 =====
func _on_m9(ctx: Dictionary) -> void:
	var stacks := _stacks(M9)
	if stacks <= 0:
		return
	var enemy = ctx.get("enemy")
	if not is_instance_valid(enemy) or _iget(enemy, "_dead", false):
		return
	## 施法时高速（窗口内）或命中时仍处高速 → 触发
	if not (_m9_fast_left > 0.0 and _m9_fast):
		var player := _player()
		if player == null or not _fast_moving(_fget_vel(player)):
			return
	if randf() >= _m9_chance(stacks):
		return
	EventBus.apply_status.emit(enemy, "slow", 1)
	EventBus.fx_hit_slow.emit(enemy)


func _m9_chance(stacks: int) -> float:
	return minf(M9_CHANCE + M9_CHANCE_K * float(stacks - 1) + M9_SPEED_LINK * _speed_bonus(), M9_CAP)


## ===== 移M10 暴走：移速 ≥250% 时攻速 +50%、受击伤害 +20% =====
func _sync_berserk() -> void:
	var stacks := _stacks(M10)
	var berserk := stacks > 0 and _speed_bonus() >= M10_SPEED_THRESHOLD
	if berserk and not _berserk:
		_berserk = true
		EventBus.fx_explosion.emit(_player_pos(), "wind")
		EventBus.screen_shake.emit(3.0)
	elif not berserk and _berserk:
		_berserk = false
	## 读取点：主线程受击结算乘以此值（受击伤害 +20% 惩罚）
	GameState.run.wind_m10_taken_mult = M10_TAKEN_MULT if _berserk else 1.0
	GameState.run.wind_m10_berserk = _berserk


## ===== 移4 追风：击杀后移速 +8%/层，持续 3s =====
func _on_enemy_died(ctx: Dictionary) -> void:
	var stacks := _stacks(N4)
	if stacks <= 0:
		return
	_kill_speed_left = N4_KILL_LEFT
	## 读取点：主线程移速聚合时叠加此值
	GameState.run.wind_kill_speed_bonus = minf(_curve_value(N4), N4_CAP)
	EventBus.player_stats_changed.emit()


func _tick_kill_speed(dt: float) -> void:
	if _kill_speed_left <= 0.0:
		return
	_kill_speed_left -= dt
	if _kill_speed_left <= 0.0:
		GameState.run.wind_kill_speed_bonus = 0.0
		EventBus.player_stats_changed.emit()


## ===== 移速→攻速联动（移2 联动系数 + 移5 疾风术架 + 移M2/移M10）=====
func _sync_as() -> void:
	if GameState == null or not (GameState.run is Dictionary):
		return
	var base_as := 0.0
	if GameState.has_method("aggregate_bonus"):
		base_as = maxf(float(GameState.aggregate_bonus("attack_speed")), 0.0)
	var desired := _as_desired()
	var stored := float(GameState.run.get("attack_speed_bonus", 0.0))
	var mine := stored - base_as
	if absf(desired - mine) < 0.0005 and absf(_as_bonus - desired) < 0.0005:
		return
	GameState.run.attack_speed_bonus = maxf(stored + (desired - mine), 0.0)
	_as_bonus = desired
	GameState.run.wind_as_bonus = desired
	GameState.run.wind_link_as = _link_as()
	GameState.run.wind_m2_atk_speed = _m2_bonus
	GameState.run.wind_m10_as_bonus = M10_AS if _berserk else 0.0
	EventBus.player_stats_changed.emit()


func _as_desired() -> float:
	var d := _link_as()
	d += _curve_value(N5)                                ## 移5 疾风术架
	d += _m2_bonus                                       ## 移M2 踏风
	if _berserk:
		d += M10_AS                                     ## 移M10 暴走
	return minf(d, AS_CAP)


## 移速 → 攻速：移速加成 × 联动系数（基础 0.5，移2 每层 +0.2）
func _link_as() -> float:
	var coef := 0.5 + 0.2 * float(_stacks(N2))
	return _speed_bonus() * coef


## ===== 数值读取点（主线程接线参考）=====
func _sync_read_points() -> void:
	if GameState == null or not (GameState.run is Dictionary):
		return
	GameState.run.wind_atk_link_coef = 0.5 + 0.2 * float(_stacks(N2))  ## 移2
	GameState.run.wind_dodge_chance = minf(_curve_value(N3), 0.6)      ## 移3 轻身
	var tiers := floorf(_speed_bonus())                                ## 每 100% 移速一档
	GameState.run.wind_speed_crit = tiers * _curve_value(N7)           ## 移7 顺风
	GameState.run.wind_speed_area = tiers * _curve_value(N8)           ## 移8 踏浪
	GameState.run.wind_cd_mult = maxf(1.0 - 0.05 * float(_stacks(N9)), 0.5)  ## 移9 迅捷
	GameState.run.wind_speed_cap_bonus = _curve_value(N10)             ## 移10 风行者
	GameState.run.wind_m9_slow_chance = _m9_chance(_stacks(M9))        ## 移M9
	GameState.run.wind_fast_moving = _fast_moving(_fget_vel(_player())) ## 供 HUD/其他系统


## ===== 移速/移动工具 =====
var _last_delta := 0.0            ## player_move 的 delta（physics 帧）
var _m1_dist := 0.0               ## 风切累计移动距离


func _on_move(ctx: Dictionary) -> void:
	_last_delta = maxf(float(ctx.get("delta", 0.0)), 0.0)
	_on_m1(ctx)
	_on_m3(ctx)
	_on_m5(ctx)
	_on_m6(ctx)
	_on_m8(ctx)


## 当前移速加成口径：聚合（含移1 疾风靴）+ 追风 + 破风（与 player._move_speed 最终公式一致）
func _speed_bonus() -> float:
	if GameState == null or not (GameState.run is Dictionary):
		return 0.0
	var s := 0.0
	if GameState.has_method("aggregate_bonus"):
		s = maxf(float(GameState.aggregate_bonus("speed")), 0.0)
	s += maxf(float(GameState.run.get("wind_kill_speed_bonus", 0.0)), 0.0)
	s += maxf(float(GameState.run.get("wind_m6_speed_bonus", 0.0)), 0.0)
	return s


func _move_speed() -> float:
	if GameState == null or not GameState.has_method("balance"):
		return 220.0
	var bal: Dictionary = GameState.balance()
	return float(bal.get("player", {}).get("speed", 220.0)) * (1.0 + _speed_bonus())


func _dash_cd_max() -> float:
	if GameState == null or not GameState.has_method("balance"):
		return 2.0
	return float(GameState.balance().get("player", {}).get("dash_cd", 2.0))


## "高速移动"：速度 ≥ 80% 当前最大移速（冲刺必然满足）
func _fast_moving(vel: Vector2) -> bool:
	return vel.length() >= _move_speed() * FAST_PCT and vel.length() > 20.0


func _ctx_vel(ctx: Dictionary, player) -> Vector2:
	if ctx.has("velocity") and ctx.get("velocity") is Vector2:
		return ctx.get("velocity")
	return _fget_vel(player)


func _fget_vel(player) -> Vector2:
	if is_instance_valid(player):
		var v = player.get("velocity")
		if v is Vector2:
			return v
	return Vector2.ZERO


## ===== 通用工具（全部防御性）=====

func _wind_power() -> int:
	if GameState == null or not (GameState.run is Dictionary):
		return 0
	var items = GameState.run.get("items", {})
	if not (items is Dictionary):
		return 0
	var n := 0
	for id in items:
		if str(id).begins_with("wind_"):
			n += maxi(int(items[id]), 0)
	return n


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


## 移6 风刃：移动时伤害乘区（风切/风之回响直接结算；弹幕侧走 run.wind_m6_move_dmg）
func _move_dmg_mult() -> float:
	return 1.0 + _curve_value(N6)


## 移8 踏浪：范围乘区（弹幕侧走 run.wind_speed_area，这里仅供风痕半径参考）
func _area_scale() -> float:
	return 1.0 + _curve_value(N8)


func _player() -> Node2D:
	var tree := get_tree()
	if tree == null:
		return null
	var p: Node = tree.get_first_node_in_group("player")
	if p is Node2D:
		return p as Node2D
	return null


func _player_pos() -> Vector2:
	var p := _player()
	return p.global_position if p != null else Vector2.ZERO


## 攻击方向（与 spell_caster._aim_dir 同口径：自动索敌最近敌人）
func _aim_dir(player: Node2D) -> Vector2:
	var nearest := _nearest_enemy(player.global_position)
	if nearest != null:
		return (nearest.global_position - player.global_position).normalized()
	if InputRouter != null and InputRouter.aim_vector.length_squared() > 0.0:
		return InputRouter.aim_vector.normalized()
	return Vector2.RIGHT


func _blade_dir(player: Node2D, vel: Vector2) -> Vector2:
	var nearest := _nearest_enemy(player.global_position)
	if nearest != null:
		return (nearest.global_position - player.global_position).normalized()
	if vel.length() > 20.0:
		return vel.normalized()
	return Vector2.RIGHT


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


func _damage_aoe(center: Vector2, radius: float, dmg: int) -> int:
	var tree := get_tree()
	if tree == null:
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
			e.take_damage(dmg, "wind", false)
			EventBus.damage_dealt.emit(dmg, node.global_position, false)
			hits += 1
	return hits


## 风域减速：对半径内敌人持续刷减速状态（enemy._slow_left=1.2s）
func _slow_aoe(center: Vector2, radius: float) -> void:
	var tree := get_tree()
	if tree == null:
		return
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		if _iget(e, "_dead", false):
			continue
		var node := e as Node2D
		if center.distance_to(node.global_position) > radius + node.scale.x * 8.0:
			continue
		EventBus.apply_status.emit(e, "slow", 1)
		EventBus.fx_hit_slow.emit(e)


func _tick_timers(dt: float) -> void:
	if GameState == null or not (GameState.run is Dictionary):
		return
	_m3_cd = maxf(_m3_cd - dt, 0.0)
	_m5_cd = maxf(_m5_cd - dt, 0.0)
	_m9_fast_left = maxf(_m9_fast_left - dt, 0.0)
	_tick_m2(dt)
	_tick_m6(dt)
	_tick_kill_speed(dt)


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
