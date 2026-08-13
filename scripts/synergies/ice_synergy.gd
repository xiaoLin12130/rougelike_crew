extends SynergyBase
## 冰系冻结流机制脚本（钩子式流派系统）
## 由 SynergyRegistry.load_synergy_scripts() 自动扫描 scripts/synergies/*.gd 并实例化注册。
## 设计文档：docs/design/流派构筑大全.md 第 2 章「冰系冻结流」（核心：冰锥 · 状态 freeze）。
## 机制强度由持有 ice_ 前缀构筑数量控制（GameState.total_stacks）；数值构筑 ice_1..ice_10 供机制引用。
##
## 钩子使用：
##   enemy_died     冰M1 碎冰（冻结死亡爆炸）/ 冰M3 冰霜新星 / 冰M9 冰晶碎裂 / 冰7 冰晶护体回血
##   enemy_hit      冰M4 冰封王座（深冻易伤 +20%）
##   enemy_status   冰M8 永冻（冻结中免疫燃烧）
##   projectile_hit 冰M5 冰刃（冻结目标 +40% 独立乘区）/ 冰4 增伤 / 冰2 附加冻结 / 冰3 冻结时长
##   player_hit     冰M6 寒冰护盾（12% 冻结攻击者）
##   player_move    冰M7 冰雪风暴（移动身后留下减速区域 1s）
##   _physics_process 自行轮询 enemy._freeze_left 变化（enemy_status 钩子目前只在
##       poison/burn tick 触发，冻结 tick 由本脚本扫描实现）：
##       冰M1 冻结结束爆炸 / 冰M2 极寒扩散 / 冰M4 深冻检测 / 冰M8 减速免疫 / 冰10 深寒
##       冰M10 绝对零度（每 8s 脉冲）/ 冰5 冰锥术架 + 冰9 冰棱（冰系施法冷却加速）
##
## 防御性约定：SynergyRegistry.trigger 不捕获回调异常（异常会冒泡崩游戏），
## 因此所有回调对空值/失效节点/缺失字段一律兜底，不抛异常。

const PROJECTILE_SCRIPT := preload("res://scripts/combat/projectile.gd")

# —— 数值常量（与 .tools/build_defs/ice.json 的曲线含义一致）——
const SHATTER_BASE := 12.0          # 碎冰基础伤害：参考冰锥（ice_shard）base_damage 10-14
const SHATTER_RADIUS := 72.0        # 碎冰爆炸半径
const SHATTER_MASTERY := 0.05       # 每持有 1 件 ice_ 构筑，碎冰伤害 +5%（流派成型奖励）
const FROZEN_DMG_K := 0.08          # 冰4 冰雪精粹：冻结中目标受伤 +8%/层
const BLADE_BONUS := 0.40           # 冰M5 冰刃：冻结目标 +40%（与燃烧增伤独立）
const FREEZE_TIME_K := 0.3          # 冰3 极寒之心：冻结时长 +0.3s/层（基础 1.0s）
const FREEZE_CHANCE_K := 0.08       # 冰2 冰封符：冻结概率 +8%/层
const SPREAD_RADIUS := 110.0        # 冰M2 极寒扩散范围
const SPREAD_TICK := 0.5            # 冻结 tick 间隔（扩散判定频率）
const SPREAD_CHANCE_BASE := 0.15    # 冰M2 基础扩散概率
const NOVA_RADIUS := 130.0          # 冰M3 冰霜新星范围
const DEEP_TIME := 2.0              # 冰M4 深冻完全控制时长
const DEEP_VULN := 0.20             # 冰M4 深冻易伤 +20%
const FROST_ATK_K := 0.06           # 冰6 霜甲：冻结目标攻击 -6%/层
const FROST_ATK_CAP := 0.5
const ICE_HEAL_K := 0.01            # 冰7 冰晶护体：冻结死亡回 1% 生命/层
const ICE_SPD_K := 0.08             # 冰5 冰锥术架：冰系攻速 +8%/层
const ICE_CD_K := 0.06              # 冰9 冰棱：冰系冷却 -6%/层
const ICE_CD_CAP := 0.45
const DEEP_SLOW_K := 0.10           # 冰10 深寒：冻结目标移速额外 -10%/层
const SHIELD_CHANCE_BASE := 0.12    # 冰M6 寒冰护盾冻结概率
const TRAIL_INTERVAL := 56.0        # 冰M7 雪迹间隔 px
const TRAIL_RADIUS := 64.0
const TRAIL_LIFE := 1.0
const AZ_RADIUS := 150.0            # 冰M10 绝对零度范围
const AZ_INTERVAL := 8.0            # 冰M10 脉冲间隔
const AZ_TIME := 0.8                # 冰M10 冻结时长
const SHARD_COUNT := 3              # 冰M9 冰晶碎裂冰弹数
const SHARD_DMG_BASE := 6.0
const SHARD_SPEED := 260.0
const SHARD_RANGE := 320.0

# —— 运行状态（key 均为 enemy instance_id）——
var _prev_freeze: Dictionary = {}   # 上一帧 _freeze_left（冻结结束/重新冻结检测）
var _spread_tick: Dictionary = {}   # 极寒扩散判定累计
var _deep_left: Dictionary = {}     # 深冻剩余秒
var _ice_slow: Dictionary = {}      # 冰10 深寒减速剩余秒（冰系施加，冰M8 不免疫）
var _atk_cut: Dictionary = {}       # 冰6 已减攻标记（持续到死亡）
var _vuln_active: Dictionary = {}   # 深冻易伤本命中已结算（防递归）
var _core_el: Dictionary = {}       # core id -> element（惰性缓存）
var _caster: Node = null            # player/SpellCaster 缓存
var _trail_dist := 0.0
var _az_left := AZ_INTERVAL


func _ready() -> void:
	super._ready()
	_register("enemy_died", _on_enemy_died)
	_register("enemy_hit", _on_enemy_hit)
	_register("enemy_status", _on_enemy_status)
	_register("projectile_hit", _on_projectile_hit)
	_register("player_hit", _on_player_hit)
	_register("player_move", _on_player_move)
	print("[SYNERGY] ice_synergy registered")


## 每物理帧轮询敌人冻结状态（enemy_status 钩子只覆盖 poison/burn tick）
func _physics_process(delta: float) -> void:
	_scan_freeze(delta)
	_tick_absolute_zero(delta)
	_tick_ice_cast_rate(delta)


# ================= 钩子回调 =================

## 敌人死亡：冰M1 碎冰 / 冰M3 冰霜新星 / 冰M9 冰晶碎裂 / 冰7 冰晶护体回血（冻结死亡才触发）
func _on_enemy_died(ctx: Dictionary) -> void:
	var e = ctx.get("enemy")
	if e == null or not is_instance_valid(e):
		return
	var id: int = e.get_instance_id()
	var fl: float = _f(e, "_freeze_left")
	_prev_freeze.erase(id)
	_spread_tick.erase(id)
	_ice_slow.erase(id)
	_atk_cut.erase(id)
	_deep_left.erase(id)
	_vuln_active.erase(id)
	if fl <= 0.0:
		return
	var pos: Vector2 = e.global_position
	var p = ctx.get("pos")
	if p is Vector2:
		pos = p
	# 冰7 冰晶护体：被冻结敌人死亡回 1% 生命/层
	var n7 := _stacks("ice_7")
	if n7 > 0:
		GameState.heal(float(GameState.run.get("max_hp", 100)) * ICE_HEAL_K * n7)
	# 冰M1 碎冰：冻结死亡爆炸（冰4 增伤）
	if _stacks("ice_m1") > 0:
		_shatter_at(pos)
	# 冰M3 冰霜新星：冻结环（新冻结者再触发碎冰/扩散，形成连锁）
	if _stacks("ice_m3") > 0:
		_nova(pos)
	# 冰M9 冰晶碎裂：3 片追踪冰弹（冰4 增伤；冰5 提速）
	if _stacks("ice_m9") > 0:
		_spawn_shards(pos, id)


## 敌人受击：冰M4 深冻易伤（+20%，仅深冻期间；递归防护）
func _on_enemy_hit(ctx: Dictionary) -> void:
	var e = ctx.get("enemy")
	if e == null or not is_instance_valid(e):
		return
	var id: int = e.get_instance_id()
	if not _deep_left.has(id) or float(_deep_left[id]) <= 0.0:
		return
	if _vuln_active.has(id):
		return
	var dmg := int(ctx.get("dmg", 0))
	if dmg <= 0:
		return
	_vuln_active[id] = true
	if e.has_method("_take_raw"):
		## 递归防御（2026-08-11）：enemy_hit 钩子内追加伤害走 _take_raw，防与圣印/诅咒互触
		var bonus := maxi(int(dmg * DEEP_VULN), 1)
		e.call("_take_raw", bonus)
		EventBus.damage_dealt.emit(bonus, e.global_position, false)
	elif e.has_method("take_damage"):
		var bonus2 := maxi(int(dmg * DEEP_VULN), 1)
		e.take_damage(bonus2, "ice", bool(ctx.get("crit", false)))
		EventBus.damage_dealt.emit(bonus2, e.global_position, false)
	_vuln_active.erase(id)


## 状态 tick：冰M8 永冻（冻结目标免疫燃烧；减速免疫在扫描中处理）
func _on_enemy_status(ctx: Dictionary) -> void:
	if str(ctx.get("kind", "")) != "burn":
		return
	if _stacks("ice_m8") <= 0:
		return
	var e = ctx.get("enemy")
	if e == null or not is_instance_valid(e):
		return
	if _f(e, "_freeze_left") > 0.0:
		e._burn_left = 0.0
		e._burn_dps = 0.0


## 弹幕命中：冰M5 冰刃（冻结目标 +40%，冰4 乘区）/ 冰4 增伤 / 冰2 附加冻结 / 冰3 延长冻结
func _on_projectile_hit(ctx: Dictionary) -> void:
	var e = ctx.get("enemy")
	if e == null or not is_instance_valid(e) or not _freezeable(e):
		return
	var dmg := int(ctx.get("dmg", 0))
	if dmg <= 0:
		return
	var fl: float = _f(e, "_freeze_left")
	var id: int = e.get_instance_id()
	var el := str(ctx.get("element", ""))
	if fl > 0.0:
		var bonus := 0
		if _stacks("ice_m5") > 0:
			# 冰M5 冰刃：+40%，与火系燃烧增伤独立；冰4 作为乘区
			bonus += int(dmg * BLADE_BONUS * (1.0 + FROZEN_DMG_K * _stacks("ice_4")))
		var n4 := _stacks("ice_4")
		if n4 > 0:
			bonus += int(dmg * FROZEN_DMG_K * n4)  # 冰4 冰雪精粹：冻结中目标受伤 +8%/层
		if bonus > 0 and e.has_method("take_damage"):
			var crit := bool(ctx.get("crit", false))
			e.take_damage(bonus, "ice", crit)
			EventBus.damage_dealt.emit(bonus, e.global_position, crit)
	# 冰3 极寒之心：冰系命中延长冻结（延迟到弹幕自身施加冻结之后再覆盖）
	if el == "ice" and _stacks("ice_3") > 0:
		call_deferred("_extend_freeze", id)
	# 冰2 冰封符：冻结概率 +8%/层（冰系弹幕本就必冻，此条给非冻结目标附加冻结机会）
	if fl <= 0.0 and _stacks("ice_2") > 0:
		var chance := clampf(FREEZE_CHANCE_K * _stacks("ice_2"), 0.0, 0.85)
		if randf() < chance:
			_apply_freeze(e)


## 玩家受击：冰M6 寒冰护盾（12% 冻结攻击者；当前钩子 attacker 为 null，取最近敌人）
func _on_player_hit(ctx: Dictionary) -> void:
	if _stacks("ice_m6") <= 0:
		return
	var attacker = ctx.get("attacker")
	if not _freezeable(attacker):
		var p = ctx.get("pos")
		var pos := Vector2.ZERO
		if p is Vector2:
			pos = p
		else:
			var player := get_tree().get_first_node_in_group("player")
			if player != null and is_instance_valid(player):
				pos = player.global_position
		attacker = _nearest_enemy(pos, 100.0)
	if not _freezeable(attacker):
		return
	var chance := clampf(SHIELD_CHANCE_BASE + FREEZE_CHANCE_K * _stacks("ice_2"), 0.0, 0.85)
	if randf() < chance:
		_apply_freeze(attacker)


## 玩家移动：冰M7 冰雪风暴（身后留下 1s 减速区域，冰10 加深）
func _on_player_move(ctx: Dictionary) -> void:
	if _stacks("ice_m7") <= 0:
		return
	var player = ctx.get("player")
	if player == null or not is_instance_valid(player):
		return
	var v = ctx.get("velocity", Vector2.ZERO)
	var speed: float = v.length() if v is Vector2 else 0.0
	var delta := float(ctx.get("delta", 0.0))
	if speed < 10.0 or delta <= 0.0:
		return
	_trail_dist += speed * delta
	if _trail_dist >= TRAIL_INTERVAL:
		_trail_dist = 0.0
		_spawn_slow_zone(player.global_position)


# ================= 每帧扫描（冻结 tick）=================

func _scan_freeze(delta: float) -> void:
	for e in GameState.get_enemies():
		if not is_instance_valid(e):
			continue
		var id: int = e.get_instance_id()
		if _b(e, "_dead"):
			_prev_freeze.erase(id)
			_spread_tick.erase(id)
			_ice_slow.erase(id)
			_atk_cut.erase(id)
			_deep_left.erase(id)
			continue
		var fl: float = _f(e, "_freeze_left")
		if fl > 0.01:
			var was: float = _prev_freeze.get(id, 0.0)
			if was <= 0.01:
				_prev_freeze[id] = fl
			else:
				# 冻结中被再次冻结（满层）→ 冰M4 冰封王座深冻
				if fl > was + 0.05 and _stacks("ice_m4") > 0 and not _deep_left.has(id):
					_deep_freeze(e)
				_prev_freeze[id] = fl
			# 冰M2 极寒扩散 tick（每 0.5s 判定）
			var t: float = _spread_tick.get(id, 0.0) + delta
			if t >= SPREAD_TICK:
				_spread_tick[id] = 0.0
				_try_spread(e)
			else:
				_spread_tick[id] = t
			# 深冻剩余计时
			if _deep_left.has(id):
				var dl: float = float(_deep_left[id]) - delta
				if dl <= 0.0:
					_deep_left.erase(id)
				else:
					_deep_left[id] = dl
			# 冰10 深寒：冻结目标额外减速（冰系施加，不被冰M8 清除）
			if _ice_slow.has(id):
				var sl2: float = float(_ice_slow[id]) - delta
				if sl2 <= 0.0:
					_ice_slow.erase(id)
				else:
					_ice_slow[id] = sl2
					e._slow_left = maxf(float(e._slow_left), 0.4)
			# 冰M8 永冻：冻结目标免疫非冰系减速
			if _stacks("ice_m8") > 0 and not _ice_slow.has(id):
				var sl: float = _f(e, "_slow_left")
				if sl > 0.0:
					e._slow_left = 0.0
		else:
			# 冻结结束 → 冰M1 碎冰（自身也会吃到爆炸伤害）
			if float(_prev_freeze.get(id, 0.0)) > 0.01:
				_prev_freeze.erase(id)
				if _stacks("ice_m1") > 0:
					_shatter(e)
			_spread_tick.erase(id)
			_ice_slow.erase(id)
			_deep_left.erase(id)
	# 防泄漏：字典过大时整体清空（下一帧重新建立快照）
	if _prev_freeze.size() > 128:
		_prev_freeze.clear()
		_spread_tick.clear()
		_ice_slow.clear()
		_atk_cut.clear()
		_deep_left.clear()


## 冰M10 绝对零度：每 8s 自动冻结周围敌人（冰3 加时长；冰M4 深冻联动）
func _tick_absolute_zero(delta: float) -> void:
	if _stacks("ice_m10") <= 0:
		return
	_az_left -= delta
	if _az_left > 0.0:
		return
	# 机制强度随冰系构筑总数提升（每件 -5% 间隔，下限 4s）
	_az_left = maxf(AZ_INTERVAL / (1.0 + SHATTER_MASTERY * _ice_stacks()), 4.0)
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not is_instance_valid(player):
		return
	var pos: Vector2 = player.global_position
	var dur := AZ_TIME + FREEZE_TIME_K * _stacks("ice_3")
	for e in GameState.get_enemies():
		if not is_instance_valid(e) or _b(e, "_dead"):
			continue
		if pos.distance_to(e.global_position) <= AZ_RADIUS + e.scale.x * 8.0:
			_apply_freeze(e, dur)
	EventBus.fx_explosion.emit(pos, "ice")


## 冰5 冰锥术架 + 冰9 冰棱：冰系法术冷却加速（直接加速 spell_caster._cds 倒计时）
func _tick_ice_cast_rate(delta: float) -> void:
	var n5 := _stacks("ice_5")
	var n9 := _stacks("ice_9")
	if n5 <= 0 and n9 <= 0:
		return
	var rate := (1.0 + ICE_SPD_K * n5) * (1.0 - minf(ICE_CD_K * n9, ICE_CD_CAP))
	if rate <= 1.001:
		return
	var caster := _spell_caster()
	if caster == null:
		return
	var grid: Array = GameState.run.get("grid", [])
	if grid.is_empty():
		return
	var cds = caster.get("_cds")
	if not (cds is Array) or cds.size() <= 0:
		return
	var n := mini(grid.size(), cds.size())
	for i in n:
		if float(cds[i]) <= 0.0:
			continue
		if not _core_is_ice(str(grid[i].get("core", ""))):
			continue
		cds[i] = maxf(float(cds[i]) - delta * (rate - 1.0), 0.0)


# ================= 冰系核心动作 =================

## 施加冻结（统一入口）：冰3 时长、冰M4 满层深冻、冰6 减攻、冰10 深寒减速
func _apply_freeze(enemy: Node, dur: float = -1.0) -> void:
	if not _freezeable(enemy):
		return
	var d: float = _freeze_duration() if dur < 0.0 else dur
	var was: bool = float(enemy._freeze_left) > 0.15
	enemy._freeze_left = maxf(float(enemy._freeze_left), d)
	if was and _stacks("ice_m4") > 0:
		_deep_freeze(enemy)
	var id: int = enemy.get_instance_id()
	# 冰6 霜甲：冻结目标攻击力 -6%/层（每只敌人结算一次）
	if not _atk_cut.has(id):
		var n6 := _stacks("ice_6")
		if n6 > 0:
			var cut := 1.0 - minf(FROST_ATK_K * n6, FROST_ATK_CAP)
			enemy.attack = maxi(int(_f(enemy, "attack") * cut), 1)
		_atk_cut[id] = true
	# 冰10 深寒：冻结目标移动速度额外 -10%/层
	var n10 := _stacks("ice_10")
	if n10 > 0:
		var slow_t := d * (1.0 + DEEP_SLOW_K * n10)
		enemy._slow_left = maxf(float(enemy._slow_left), slow_t)
		_ice_slow[id] = maxf(_ice_slow.get(id, 0.0), slow_t)


## 冰M4 冰封王座：深冻（2s 完全控制 + 易伤 20%）
func _deep_freeze(enemy: Node) -> void:
	var id: int = enemy.get_instance_id()
	var d := DEEP_TIME + FREEZE_TIME_K * _stacks("ice_3")
	var cur: float = _deep_left.get(id, 0.0)
	var fresh: bool = cur <= 0.0
	_deep_left[id] = maxf(cur, d)
	enemy._freeze_left = maxf(float(enemy._freeze_left), d)
	enemy._root_left = maxf(float(enemy._root_left), d)          # 定身（完全控制）
	enemy._atk_cd = maxf(float(enemy._atk_cd), d)
	enemy._shoot_cd = maxf(float(enemy._shoot_cd), d)
	enemy._skill_cd = maxf(float(enemy._skill_cd), d)
	if fresh:
		EventBus.fx_explosion.emit(enemy.global_position, "ice")


## 冰M1 碎冰：冻结结束（自身也受击）
func _shatter(enemy: Node) -> void:
	if not is_instance_valid(enemy):
		return
	_shatter_at(enemy.global_position)


func _shatter_at(pos: Vector2) -> void:
	var dmg := _shatter_dmg()
	for e in GameState.get_enemies():
		if not is_instance_valid(e) or _b(e, "_dead"):
			continue
		if not e.has_method("take_damage"):
			continue
		if pos.distance_to(e.global_position) <= SHATTER_RADIUS + e.scale.x * 8.0:
			e.take_damage(dmg, "ice", false)
			EventBus.damage_dealt.emit(dmg, e.global_position, false)
	EventBus.fx_explosion.emit(pos, "ice")


func _shatter_dmg() -> int:
	# 参考冰锥 10-14；冰4 增伤 ×（1+0.08/层）；冰系构筑总数提供成型加成
	return maxi(int(SHATTER_BASE * (1.0 + FROZEN_DMG_K * _stacks("ice_4")) * (1.0 + SHATTER_MASTERY * _ice_stacks())), 1)


## 冰M2 极寒扩散：冻结目标概率冻结附近敌人（冰2 提升概率）
func _try_spread(enemy: Node) -> void:
	if _stacks("ice_m2") <= 0:
		return
	var chance := clampf(SPREAD_CHANCE_BASE + FREEZE_CHANCE_K * _stacks("ice_2"), 0.0, 0.95)
	if randf() >= chance:
		return
	var pos: Vector2 = enemy.global_position
	for o in GameState.get_enemies():
		if o == enemy or not is_instance_valid(o) or _b(o, "_dead"):
			continue
		if not _freezeable(o):
			continue
		if pos.distance_to(o.global_position) <= SPREAD_RADIUS + o.scale.x * 8.0:
			_apply_freeze(o)


## 冰M3 冰霜新星：冻结环（只冻结，新冻结目标后续触发碎冰/扩散连锁）
func _nova(pos: Vector2) -> void:
	for e in GameState.get_enemies():
		if not is_instance_valid(e) or _b(e, "_dead"):
			continue
		if pos.distance_to(e.global_position) <= NOVA_RADIUS + e.scale.x * 8.0:
			_apply_freeze(e)
	EventBus.fx_explosion.emit(pos, "ice")


## 冰M9 冰晶碎裂：3 片追踪冰弹（冰4 增伤；冰5 提速）
func _spawn_shards(pos: Vector2, source_id: int) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var dmg := maxi(int(SHARD_DMG_BASE * (1.0 + FROZEN_DMG_K * _stacks("ice_4"))), 1)
	var speed := SHARD_SPEED * (1.0 + ICE_SPD_K * _stacks("ice_5"))
	for i in SHARD_COUNT:
		# 池化：经 obtain 复用弹幕实例
		var shard = PROJECTILE_SCRIPT.obtain({
			"position": pos + Vector2(randf_range(-10.0, 10.0), randf_range(-10.0, 10.0)),
			"direction": Vector2.from_angle(randf() * TAU),
			"speed": speed,
			"range": SHARD_RANGE,
			"damage": dmg,
			"element": "ice",
			"aoe": 0.0,
			"mods": {"homing": true},
			"status": {},
			"chain": 0,
		}, scene)
		shard._hit_enemies[source_id] = true  # 不回头命中已死亡来源


## 冰M7 冰雪风暴：减速区域（手动扫描，不依赖物理碰撞）
func _spawn_slow_zone(pos: Vector2) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var zone := SlowZone.new()
	zone.setup(pos, TRAIL_RADIUS, TRAIL_LIFE)
	zone.name = "GroundIce"
	scene.add_child(zone)


## 冰3 极寒之心：弹幕自身施加冻结后延长（call_deferred 保证时序）
func _extend_freeze(id: int) -> void:
	var e = instance_from_id(id)
	if not _freezeable(e):
		return
	e._freeze_left = maxf(float(e._freeze_left), _freeze_duration())


# ================= 工具 =================

func _freeze_duration() -> float:
	return 1.0 + FREEZE_TIME_K * _stacks("ice_3")
## 持有 ice_ 前缀构筑总数量（机制强度主控）
func _ice_stacks() -> int:
	var items: Dictionary = GameState.run.get("items", {})
	var total := 0
	for k in items:
		if str(k).begins_with("ice_"):
			total += int(items[k])
	return total


func _freezeable(e: Node) -> bool:
	if e == null or not is_instance_valid(e):
		return false
	if e.get("_freeze_left") == null:
		return false
	if _b(e, "_dead"):
		return false
	return true


## 防御性读取对象浮点字段（Godot 4 Object.get 只接受 1 参，缺失字段返回 0）
func _f(e: Object, prop: String) -> float:
	if e == null:
		return 0.0
	var v = e.get(prop)
	return float(v) if v != null else 0.0


## 防御性读取对象布尔字段（缺失/null/0 一律视为 false）
func _b(e: Object, prop: String) -> bool:
	if e == null:
		return false
	var v = e.get(prop)
	## Godot 4.7 中 bool(null) 会抛 "Nonexistent 'bool' constructor"，需先判空
	return false if v == null else bool(v)


func _nearest_enemy(pos: Vector2, radius: float) -> Node:
	var best: Node = null
	var best_d := radius
	for e in GameState.get_enemies():
		if not is_instance_valid(e) or _b(e, "_dead"):
			continue
		var d: float = pos.distance_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


func _spell_caster() -> Node:
	if _caster != null and is_instance_valid(_caster):
		return _caster
	_caster = null
	var p := get_tree().get_first_node_in_group("player")
	if p != null and is_instance_valid(p):
		_caster = p.get_node_or_null("SpellCaster")
	return _caster


func _core_is_ice(core_id: String) -> bool:
	if core_id == "":
		return false
	if _core_el.is_empty():
		for c in GameState.tables.get("spells", {}).get("cores", []):
			_core_el[str(c.get("id", ""))] = str(c.get("element", ""))
	return _core_el.get(core_id, "") == "ice"


## 冰雪风暴雪迹：1s 减速区域
class SlowZone:
	extends Area2D

	var _radius := 64.0
	var _life := 1.0
	var _scan := 0.0
	var _anim := 0.0
	var _shards: Array = []

	func setup(pos: Vector2, radius: float, life: float) -> void:
		global_position = pos
		_radius = radius
		_life = life
		_anim = 0.0
		z_index = -10
		# 预生成冰晶朝向（确定性，避免每帧抖动）
		for i in 6:
			_shards.append([randf() * TAU, randf_range(0.35, 0.9), randf_range(0.5, 1.0)])

	func _draw() -> void:
		# 地面视觉（纯程序化）：淡蓝霜地 + 冰霜结晶 + 微光
		draw_circle(Vector2.ZERO, _radius, Color(0.55, 0.8, 1.0, 0.16))
		draw_circle(Vector2.ZERO, _radius * 0.55, Color(0.7, 0.9, 1.0, 0.12))
		for s in _shards:
			var a: float = s[0]
			var len: float = _radius * s[1]
			var tw := 0.75 + 0.25 * sin(_anim * 5.0 + a * 3.0)
			var dir := Vector2.from_angle(a)
			var mid := dir * len * 0.5
			var tip := dir * len
			var branch := Vector2(-dir.y, dir.x) * len * 0.28
			draw_polyline(PackedVector2Array([Vector2.ZERO, mid, tip]),
				Color(0.78, 0.92, 1.0, 0.7 * tw), 1.8, true)
			draw_polyline(PackedVector2Array([mid - branch * 0.4, mid, mid + branch * 0.4]),
				Color(0.78, 0.92, 1.0, 0.5 * tw), 1.3, true)
			draw_circle(tip, 1.5, Color(0.9, 0.97, 1.0, 0.9 * tw))
		draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 28, Color(0.75, 0.9, 1.0, 0.4), 1.6, true)

	func _physics_process(delta: float) -> void:
		_life -= delta
		if _life <= 0.0:
			queue_free()
			return
		_anim += delta
		queue_redraw()
		_scan -= delta
		if _scan > 0.0:
			return
		_scan = 0.25
		for e in GameState.get_enemies():
			if not is_instance_valid(e):
				continue
			var dead = e.get("_dead")
			if dead != null and bool(dead):
				continue
			if global_position.distance_to(e.global_position) <= _radius + e.scale.x * 8.0:
				EventBus.apply_status.emit(e, "slow", 1)
