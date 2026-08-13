extends SynergyBase
## 圣光庇护流 · 机制脚本（光M1 圣盾护佑 / 光M2 致盲扩散 / 光M3 圣光净化 /
## 光M4 治疗光环 / 光M5 光矛穿透 / 光M6 圣印 / 光M7 圣光爆发 / 光M8 审判 /
## 光M9 圣光复活 / 光M10 圣光领域），并承载光1-光10 数值构筑的战斗结算。
## 核心联动：flash 闪光（致盲）与 blessing 圣光（治疗）——光M2/M7/M10 施加致盲，
## 光M3/M4/M9/M10 回复生命；光M5/M8 强化光系输出（光1 经 "light" tag 由
## spell_caster._spell_damage 聚合，光6/7/8 经 attack_speed/area/cooldown tag 主线程聚合）。
##
## 强度模型（与毒系门控同规，G4/G6）：机制由持有对应 holy_mN 道具解锁
## （无道具时机制不生效），强度乘区由光1-光10 数值构筑放大。
## 钩子：enemy_status / enemy_died / enemy_hit / player_hit / damage_dealt /
##       cast / projectile_hit / player_move（SynergyRegistry 全 8 类）。
## 回调全部防御性编写：空对象 / 缺字段 / 无效实例一律静默返回。

# ---------- 机制构筑 id（与 data/items.json 的 holy_mN 一致） ----------
const M1 := "holy_m1"   ## 光M1 圣盾护佑
const M2 := "holy_m2"   ## 光M2 致盲扩散
const M3 := "holy_m3"   ## 光M3 圣光净化
const M4 := "holy_m4"   ## 光M4 治疗光环
const M5 := "holy_m5"   ## 光M5 光矛穿透
const M6 := "holy_m6"   ## 光M6 圣印
const M7 := "holy_m7"   ## 光M7 圣光爆发
const M8 := "holy_m8"   ## 光M8 审判
const M9 := "holy_m9"   ## 光M9 圣光复活
const M10 := "holy_m10" ## 光M10 圣光领域

# ---------- 数值构筑 id（联动读取） ----------
const N1 := "holy_1"    ## 光1 圣光符：光系伤害 +10%/层（tag light → 主线程聚合）
const N2 := "holy_2"    ## 光2 圣辉石：治疗量 +12%/层
const N3 := "holy_3"    ## 光3 闪光粉：致盲概率 +8%/层
const N4 := "holy_4"    ## 光4 圣盾刻印：护盾量 +15%/层
const N5 := "holy_5"    ## 光5 祝福挂坠：治疗光环范围 +12%/层
const N7 := "holy_7"    ## 光7 光棱镜：范围 +10%/层
const N9 := "holy_9"    ## 光9 圣洁印记：圣印易伤额外 +4%/层
const N10 := "holy_10"  ## 光10 曙光核心：净化回复 +1.5% 最大生命/层

# ---------- 机制数值（文档《流派构筑大全》第 12 章） ----------
const SHIELD_BASE := 0.02      ## 光M1 护盾 = 2% 最大生命/层
const SHIELD_CAP := 0.30       ## 护盾池上限 30% 最大生命
const SPREAD_CHANCE := 0.25    ## 光M2 致盲扩散概率
const BLIND_DURATION := 1.5    ## 致盲时长（秒）
const SPREAD_RADIUS := 130.0   ## 致盲扩散半径
const CLEANSE_CHANCE := 0.20   ## 光M3 净化触发概率
const CLEANSE_HEAL := 0.02     ## 净化基础回复 2% 最大生命
const AURA_TICK := 0.5         ## 光M4 治疗光环节流（秒）
const AURA_HEAL := 0.008       ## 光环每跳 0.8% 最大生命
const AURA_RADIUS := 70.0      ## 光环基础半径（光5 放大）
const PIERCE_CHANCE := 0.30    ## 光M5 穿透概率
const PIERCE_DMG := 0.40       ## 穿透追加 40% 光伤
const PIERCE_RADIUS := 150.0   ## 穿透寻敌半径
const MARK_STACKS_MAX := 5     ## 光M6 圣印叠层上限
const MARK_DURATION := 3.0     ## 圣印持续（秒）
const MARK_VULN := 0.05        ## 圣印易伤 +5%/层
const MARK_VULN_CAP := 0.30    ## 圣印易伤上限
const BURST_CHANCE := 0.15     ## 光M7 爆发概率
const BURST_HEAL := 0.01       ## 爆发回复 1% 最大生命
const BURST_RADIUS := 160.0    ## 爆发致盲半径
const EXECUTE_THRESHOLD := 0.15 ## 光M8 审判斩杀线 15%
const EXECUTE_CHANCE := 0.20   ## 审判基础概率
const REVIVE_CHANCE := 0.40    ## 光M9 复活概率
const REVIVE_HP := 0.30        ## 复活 30% 生命
const REVIVE_CD := 45.0        ## 复活冷却（秒）
const DOMAIN_INTERVAL := 8.0   ## 光M10 领域间隔（秒）
const DOMAIN_HEAL := 0.03      ## 领域回复 3% 最大生命
const DOMAIN_RADIUS := 100.0   ## 领域基础半径（光7 放大）

## 圣印跟踪：id -> {"stacks": int, "left": float}
var _marks := {}
## 光M1 圣盾：当前护盾量
var _shield := 0.0
## 光M9 复活冷却
var _revive_cd_left := 0.0
## 光M10 领域倒计时
var _domain_cd_left := 0.0
## 光M4 光环节流
var _aura_timer := 0.0


func _ready() -> void:
	super._ready()
	_register("enemy_status", _on_enemy_status)
	_register("enemy_died", _on_enemy_died)
	_register("enemy_hit", _on_enemy_hit)
	_register("player_hit", _on_player_hit)
	_register("damage_dealt", _on_damage_dealt)
	_register("cast", _on_cast)
	_register("projectile_hit", _on_projectile_hit)
	_register("player_move", _on_player_move)
	print("[SYNERGY] holy registered")


func _process(delta: float) -> void:
	_revive_cd_left = maxf(_revive_cd_left - delta, 0.0)
	_domain_cd_left = maxf(_domain_cd_left - delta, 0.0)
	# 圣印到期清理
	var expired: Array = []
	for id in _marks:
		var m: Dictionary = _marks[id]
		m["left"] = float(m.get("left", 0.0)) - delta
		if float(m.get("left", 0.0)) <= 0.0:
			expired.append(id)
	for id in expired:
		_marks.erase(id)


# ================= 防御性取值 =================
func _has(item_id: String) -> bool:
	return _stacks(item_id) > 0


func _num(node: Node, key: String, def: float) -> float:
	var v: Variant = node.get(key)
	return float(v) if v != null else def


func _bool(node: Node, key: String, def: bool) -> bool:
	var v: Variant = node.get(key)
	return bool(v) if v != null else def


## 治疗量乘区：1 + 0.12 × 光2（作用于光M3/M4/M9/M10 全部圣光治疗）
func _heal_mult() -> float:
	return 1.0 + 0.12 * float(_stacks(N2))


## 致盲概率乘区：1 + 0.08 × 光3（作用于光M2/M7/M10 的致盲判定）
func _blind_mult() -> float:
	return 1.0 + 0.08 * float(_stacks(N3))


## 光M1 护盾单次授予：2% 最大生命/层 × (1 + 0.15 × 光4)
func _shield_grant(max_hp: float) -> float:
	return maxf(max_hp * SHIELD_BASE * float(_stacks(M1)) * (1.0 + 0.15 * float(_stacks(N4))), 0.0)


## 光M10 领域半径：100 × (1 + 0.10 × 光7)
func _domain_radius() -> float:
	return DOMAIN_RADIUS * (1.0 + 0.10 * float(_stacks(N7)))


# ================= 钩子：player_hit（光M1 护盾 / 光M3 净化 / 光M9 复活） =================

func _on_player_hit(ctx: Dictionary) -> void:
	if not is_inside_tree() or GameState == null or not (GameState.run is Dictionary):
		return
	var taken := float(ctx.get("taken", 0.0))
	var max_hp := float(GameState.run.get("max_hp", 1))
	# 光M1 圣盾护佑：护盾优先抵扣（钩子侧补结：伤害已由主线程扣除，退回护盾吸收部分）
	if _has(M1):
		if _shield > 0.0 and taken > 0.0:
			var absorb := minf(_shield, taken)
			_shield -= absorb
			GameState.heal(absorb)
		_shield = minf(_shield + _shield_grant(max_hp), max_hp * SHIELD_CAP)
	# 光M3 圣光净化：受击 20% 概率净化负面状态并回复（光2/光10 加成；咒M7 反制联动）
	if _has(M3) and randf() < CLEANSE_CHANCE:
		var heal := max_hp * (CLEANSE_HEAL + 0.015 * float(_stacks(N10))) * _heal_mult()
		var healed := GameState.heal(minf(heal, max_hp * 0.08))
		if healed > 0:
			EventBus.fx_heal_text.emit(_ctx_pos(ctx), healed)
	# 光M9 圣光复活：致死一击以 30% 生命复活（与防M10 金身同模式：晚于扣血、早于死亡判定）
	if _has(M9) and _revive_cd_left <= 0.0 and int(GameState.run.get("hp", 0)) <= 0:
		_revive_cd_left = REVIVE_CD
		if randf() < REVIVE_CHANCE:
			GameState.run.hp = maxi(int(max_hp * REVIVE_HP), 1)
			var player := _player_node()
			if is_instance_valid(player) and player.get("_invuln_left") != null:
				player.set("_invuln_left", 2.0)
			EventBus.fx_heal_text.emit(_ctx_pos(ctx), int(max_hp * REVIVE_HP))


# ================= 钩子：player_move（光M4 治疗光环） =================

func _on_player_move(ctx: Dictionary) -> void:
	if not is_inside_tree() or GameState == null or not _has(M4):
		return
	var delta: float = float(ctx.get("delta", 0.0))
	if delta <= 0.0:
		return
	_aura_timer -= delta
	if _aura_timer > 0.0:
		return
	_aura_timer = AURA_TICK
	var max_hp := float(GameState.run.get("max_hp", 1))
	var healed := GameState.heal(maxi(int(max_hp * AURA_HEAL * _heal_mult()), 1))
	if healed > 0:
		var hpos := _ctx_pos(ctx)
		EventBus.fx_heal_text.emit(hpos, healed)
		EventBus.fx_explosion_scaled.emit(hpos, "light", AURA_RADIUS * (1.0 + 0.12 * float(_stacks(N5))))


# ================= 钩子：enemy_died（光M2 致盲扩散） =================

func _on_enemy_died(ctx: Dictionary) -> void:
	if not is_inside_tree() or not _has(M2):
		return
	var enemy := ctx.get("enemy") as Node2D
	if not is_instance_valid(enemy):
		return
	_marks.erase(enemy.get_instance_id())
	# 仅致盲中的敌人死亡触发扩散（闪光核心联动）
	if _num(enemy, "_blind_left", 0.0) <= 0.0:
		return
	if randf() >= SPREAD_CHANCE * _blind_mult():
		return
	var tree := get_tree()
	if tree == null:
		return
	var pos: Vector2 = enemy.global_position
	var count := 0
	for node in GameState.get_enemies():
		if count >= 2:
			break
		var e := node as Node2D
		if e == null or not is_instance_valid(e) or e == enemy:
			continue
		if e.global_position.distance_to(pos) > SPREAD_RADIUS:
			continue
		_apply_blind(e, BLIND_DURATION)
		count += 1


# ================= 钩子：enemy_hit（光M6 圣印） =================

func _on_enemy_hit(ctx: Dictionary) -> void:
	if not is_inside_tree() or not _has(M6):
		return
	var enemy := ctx.get("enemy") as Node2D
	if not is_instance_valid(enemy):
		return
	var id := enemy.get_instance_id()
	var m: Dictionary = _marks.get(id, {"stacks": 0, "left": 0.0})
	# 已有圣印：先结算易伤追加伤害（光9 强化，上限 +20%）
	if int(m.get("stacks", 0)) > 0:
		var dmg := int(ctx.get("dmg", 0))
		var vuln := minf(MARK_VULN * float(int(m.get("stacks", 0))), MARK_VULN_CAP)
		vuln += minf(0.04 * float(_stacks(N9)), 0.20)
		if vuln > 0.0 and dmg > 0 and enemy.has_method("take_damage"):
			var extra := maxi(roundi(float(dmg) * vuln), 1)
			## 递归修复（2026-08-11）：追加伤害走 _take_raw 直接扣血——
			## 原 take_damage 会再触发 enemy_hit 钩子 → 圣印再追加 → 无限递归（实测 180+ 层堆栈）
			if enemy.has_method("_take_raw"):
				enemy.call("_take_raw", extra)
			else:
				enemy.call("take_damage", extra, "light", false)
			EventBus.damage_dealt.emit(extra, enemy.global_position, false)
	# 叠层（上限 5，刷新时长）
	m["stacks"] = mini(int(m.get("stacks", 0)) + 1, MARK_STACKS_MAX)
	m["left"] = MARK_DURATION
	_marks[id] = m


# ================= 钩子：enemy_status（光M6 圣印刷新支撑） =================

func _on_enemy_status(ctx: Dictionary) -> void:
	if not (ctx is Dictionary):
		return
	var enemy := ctx.get("enemy") as Node
	if not is_instance_valid(enemy):
		return
	var id := enemy.get_instance_id()
	# 目标存活期间持续刷新圣印时长（_process 只清离场/超时目标）
	if _marks.has(id):
		_marks[id]["left"] = MARK_DURATION


# ================= 钩子：damage_dealt（光M7 圣光爆发） =================

func _on_damage_dealt(ctx: Dictionary) -> void:
	if not is_inside_tree() or GameState == null or not _has(M7):
		return
	if randf() >= BURST_CHANCE * _blind_mult():
		return
	var pos: Variant = ctx.get("pos", Vector2.ZERO)
	if not (pos is Vector2):
		return
	var tree := get_tree()
	if tree == null:
		return
	# 致盲周围敌人（闪光核心联动）
	for node in GameState.get_enemies():
		var e := node as Node2D
		if e == null or not is_instance_valid(e):
			continue
		if e.global_position.distance_to(pos) > BURST_RADIUS:
			continue
		_apply_blind(e, BLIND_DURATION)
	# 回复 1% 最大生命
	var max_hp := float(GameState.run.get("max_hp", 1))
	var healed := GameState.heal(maxi(int(max_hp * BURST_HEAL * _heal_mult()), 1))
	if healed > 0:
		EventBus.fx_heal_text.emit(pos, healed)
	EventBus.fx_explosion_scaled.emit(pos, "light", BURST_RADIUS)


# ================= 钩子：cast（光M10 圣光领域计时） =================

func _on_cast(ctx: Dictionary) -> void:
	if not is_inside_tree() or GameState == null or not _has(M10):
		return
	if _domain_cd_left > 0.0:
		return
	_domain_cd_left = DOMAIN_INTERVAL
	var player: Variant = ctx.get("player")
	if not is_instance_valid(player):
		player = _player_node()
	if not is_instance_valid(player) or not (player is Node2D):
		return
	var tree := get_tree()
	if tree == null:
		return
	var pos: Vector2 = (player as Node2D).global_position
	var radius := _domain_radius()
	for node in GameState.get_enemies():
		var e := node as Node2D
		if e == null or not is_instance_valid(e):
			continue
		if pos.distance_to(e.global_position) > radius + e.scale.x * 8.0:
			continue
		_apply_blind(e, BLIND_DURATION)
	var max_hp := float(GameState.run.get("max_hp", 1))
	var healed := GameState.heal(maxi(int(max_hp * DOMAIN_HEAL * _heal_mult()), 1))
	if healed > 0:
		EventBus.fx_heal_text.emit(pos, healed)
	EventBus.fx_explosion_scaled.emit(pos, "light", radius)


# ================= 钩子：projectile_hit（光M5 穿透 / 光M8 审判） =================

func _on_projectile_hit(ctx: Dictionary) -> void:
	if not is_inside_tree() or not (ctx is Dictionary):
		return
	var enemy := ctx.get("enemy") as Node2D
	if not is_instance_valid(enemy):
		return
	var element := str(ctx.get("element", ""))
	var dmg := int(ctx.get("dmg", 0))
	# 光M8 审判：光系命中低血敌人概率斩杀（Boss 无效，每多 1 层 +5% 概率）
	if _has(M8) and element == "light" and dmg > 0:
		var max_hp := _num(enemy, "max_hp", 0.0)
		var hp := _num(enemy, "hp", 0.0)
		if not _bool(enemy, "is_boss", false) and max_hp > 0.0 \
				and hp <= max_hp * EXECUTE_THRESHOLD \
				and randf() < EXECUTE_CHANCE * (1.0 + 0.05 * float(_stacks(M8) - 1)):
			var kill := maxi(int(hp), 1)
			if enemy.has_method("_take_raw"):
				enemy.call("_take_raw", kill)
				EventBus.damage_dealt.emit(kill, enemy.global_position, true)
			return
	# 光M5 光矛穿透：光系命中 30% 概率追加 40% 光伤给附近最近敌人
	if _has(M5) and element == "light" and dmg > 0 and randf() < PIERCE_CHANCE:
		var target := _nearest_other_enemy(enemy, PIERCE_RADIUS)
		if target != null:
			var extra := maxi(roundi(float(dmg) * PIERCE_DMG), 1)
			## 递归修复（2026-08-11）：钩子内追加伤害走 _take_raw（防光矛→圣印→追加→无限链）
			if target.has_method("_take_raw"):
				target.call("_take_raw", extra)
			elif target.has_method("take_damage"):
				target.call("take_damage", extra, "light", false)
			EventBus.damage_dealt.emit(extra, target.global_position, false)


# ================= 工具 =================

func _apply_blind(target: Node2D, duration: float) -> void:
	if not is_instance_valid(target):
		return
	var left: Variant = target.get("_blind_left")
	if left == null:
		return
	target.set("_blind_left", maxf(float(left), duration))


func _nearest_other_enemy(self_node: Node2D, radius: float) -> Node2D:
	var tree := get_tree()
	if tree == null:
		return null
	var best: Node2D = null
	var best_d := INF
	for node in GameState.get_enemies():
		var e := node as Node2D
		if e == null or not is_instance_valid(e) or e == self_node:
			continue
		if _bool(e, "_dead", false):
			continue
		var d: float = self_node.global_position.distance_to(e.global_position)
		if d <= radius and d < best_d:
			best_d = d
			best = e
	return best


func _player_node() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group("player")


func _ctx_pos(ctx: Dictionary) -> Vector2:
	var p: Variant = ctx.get("player")
	if p != null and is_instance_valid(p) and (p is Node2D):
		return (p as Node2D).global_position
	var pos: Variant = ctx.get("pos", Vector2.ZERO)
	if pos is Vector2:
		return pos
	var n := _player_node()
	if n != null and is_instance_valid(n) and (n is Node2D):
		return (n as Node2D).global_position
	return Vector2.ZERO
