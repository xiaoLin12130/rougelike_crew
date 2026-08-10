extends Area2D
## 投射物：由 spell_caster.setup() 注入速度/射程/伤害/元素/修饰参数。
## 命中敌人 → enemy.take_damage(dmg, element, is_crit) + EventBus 事件。
## 支持 homing / pierce / bounce / orbit / delay / explode / 毒雾 / 冰锥 / 暴击。

const ARENA_MIN := Vector2(16.0, 16.0)
const ARENA_MAX := Vector2(1264.0, 704.0)
const CONTACT_RADIUS := 9.0
const ORBIT_RADIUS := 90.0
const ORBIT_SPEED := 4.5
const SPLIT_DAMAGE_MULT := 0.6  # split 外壳：小弹伤害倍率
const SPLIT_FAN_DEG := 60.0  # split 外壳：扇形总开角
const SPLIT_MINI_SPEED := 240.0  # 瞬发核心分裂时小弹的保底速度
const CHAIN_RANGE := 160.0  # 闪电链跳跃搜索半径
const CHAIN_FALLOFF := 0.7  # 闪电链每跳伤害衰减
const BLIND_BURST_RADIUS := 90.0  # flash 瞬发（数据 aoe=0）的失明爆发半径
const STATUS_TEXTURES := {
	"fire": "res://assets/sprites/gen/proj_fireball.png",
	"ice": "res://assets/sprites/gen/proj_ice.png",
	"lightning": "res://assets/sprites/gen/proj_lightning.png",
	"poison": "res://assets/sprites/gen/proj_poison.png",
	"blade": "res://assets/sprites/gen/proj_blade.png",
}

var _spawn_pos := Vector2.ZERO
var _dir := Vector2.RIGHT
var _speed := 0.0
var _range := 360.0
var _damage := 0.0
var _element := "fire"
var _aoe := 0.0
var _mods: Dictionary = {}
var _travelled := 0.0
var _pierce_left := 0
var _bounce_left := 0
var _delay_left := 0.0
var _instant := false
var _orbit_mode := false
var _orbit_center := Vector2.ZERO
var _orbit_angle := 0.0
var _orbit_life := 2.0
var _player_ref: Node2D = null
var _is_whirl := false  # 旋风刃标记：基础刀刃不触发轨道接触爆炸（问题2/14 区分）
var _hit_enemies := {}  # instance_id -> true：同一投射物对同一敌人只结算一次
var _impacted := false
var _status: Dictionary = {}  # 核心状态参数（burn/slow/root/poison/blind）
var _chain_left := 0  # 闪电链剩余跳跃次数
var _split := 0  # split 外壳：分裂数量
var _drain := 0.0  # drain 外壳：命中回血比例


func setup(p: Dictionary) -> void:
	_spawn_pos = p.get("position", Vector2.ZERO)
	global_position = _spawn_pos
	var d: Vector2 = p.get("direction", Vector2.RIGHT)
	_dir = d.normalized()
	_speed = float(p.get("speed", 0.0))
	_range = float(p.get("range", 360.0))
	_damage = float(p.get("damage", 0.0))
	_element = str(p.get("element", "fire"))
	_aoe = float(p.get("aoe", 0.0))
	_mods = p.get("mods", {})
	_pierce_left = int(_mods.get("pierce", 0))
	_bounce_left = int(_mods.get("bounce", 0))
	# N2 弹射镜：每 3 层 +1 次弹射（阈值曲线），层数来自构筑堆叠
	if GameState != null and GameState.has_method("item_def"):
		var bm_def := GameState.item_def("bounce_mirror")
		if not bm_def.is_empty():
			_bounce_left += int(GameState.item_value(bm_def, GameState.total_stacks("bounce_mirror")))
	_delay_left = float(_mods.get("delay", 0.0))
	_status = p.get("status", {})
	_chain_left = int(p.get("chain", 0))
	_split = int(_mods.get("split", 0))
	_drain = float(_mods.get("drain", 0.0))
	_is_whirl = bool(_mods.get("_whirl", false))
	_instant = _speed <= 0.0
	_orbit_mode = bool(_mods.get("orbit", false))
	_orbit_life = maxf(float(_mods.get("orbit", 2.0)), 0.5)


func _ready() -> void:
	add_to_group("player_projectile")
	var spr := $Sprite2D as Sprite2D
	if spr != null:
		spr.texture = load(STATUS_TEXTURES.get(_element, STATUS_TEXTURES["fire"]))
	_player_ref = get_tree().get_first_node_in_group("player")
	if _orbit_mode:
		_orbit_angle = _dir.angle()
		_orbit_center = _player_ref.global_position if _player_ref != null else _spawn_pos


func _physics_process(delta: float) -> void:
	if _impacted:
		return
	if _delay_left > 0.0:
		_delay_left -= delta
		return
	if _orbit_mode:
		_orbit_step(delta)
		return
	if _instant:
		global_position = _spawn_pos + _dir * _range
		_explode_at(global_position)
		return
	_move_step(delta)


func _move_step(delta: float) -> void:
	if _mods.get("homing", false):
		var target := _nearest_enemy()
		if target != null:
			var to: Vector2 = (target.global_position - global_position).normalized()
			_dir = _dir.lerp(to, minf(6.0 * delta, 1.0)).normalized()
	position += _dir * _speed * delta
	_travelled += _speed * delta
	if _bounce_left > 0:
		# 弹射：触墙（Clamp 边界）或射程尽头反弹，弹数耗尽则消失。
		var clamped := position.clamp(ARENA_MIN, ARENA_MAX)
		if clamped != position or _travelled >= _range:
			_bounce_at(clamped)
			return
	else:
		position = position.clamp(ARENA_MIN, ARENA_MAX)
		if _travelled >= _range:
			queue_free()
			return
	_scan_contact()


func _scan_contact() -> void:
	for e in _enemies_in_radius(global_position, CONTACT_RADIUS):
		var id: int = e.get_instance_id()
		if _hit_enemies.has(id):
			continue
		if _aoe > 0.0:
			# AOE 核：爆炸结算统一由 _explode_at 标记+伤害（含直接接触的敌人——
			# 此前先预标记会跳过接触敌人的伤害，导致弹道核直击无伤）。
			# AOE核×穿透/弹射（问题1）：爆炸后弹体保留继续飞行，
			# 每次接触爆炸消耗一次穿透（优先）/弹射次数，直至耗尽才销毁。
			var keep := _pierce_left > 0 or _bounce_left > 0
			_explode_at(global_position, keep)
			if keep:
				if _pierce_left > 0:
					_pierce_left -= 1
				else:
					_bounce_left -= 1
			return
		_hit_enemies[id] = true
		_hit_enemy(e, 1.0, true)
		if _chain_left > 0:
			_try_chain(e.global_position)
		if _pierce_left > 0:
			_pierce_left -= 1
		else:
			queue_free()
			return


## 爆炸结算：范围内敌人全部受击；keep_alive=true 时弹体保留（AOE×穿透/弹射、轨道接触爆炸）。
func _explode_at(pos: Vector2, keep_alive: bool = false) -> void:
	if not keep_alive:
		_impacted = true
	var radius := maxf(_aoe, 1.0)
	# 移8 踏浪：每 100% 移速 +6% 技能范围（run.wind_speed_area 读取点接线）
	radius *= 1.0 + maxf(float(GameState.run.get("wind_speed_area", 0.0)), 0.0)
	# 特效范围同步：按实际 AOE 半径缩放爆炸特效（范围变大时视觉可感知）
	EventBus.fx_explosion_scaled.emit(pos, _element, radius)
	# flash（数据 aoe=0）瞬发时以固定爆发半径命中，保证失明/伤害生效
	# 闪光×爆发（问题10）：盲爆半径参与 aoe_mult（爆发外壳"范围翻倍"对闪光兑现）
	if _instant and float(_status.get("blind", 0.0)) > 0.0:
		radius = maxf(radius, BLIND_BURST_RADIUS * float(_mods.get("aoe_mult", 1.0)))
	for e in _enemies_in_radius(pos, radius):
		var id: int = e.get_instance_id()
		if _hit_enemies.has(id):
			continue
		_hit_enemies[id] = true
		_hit_enemy(e)
	if _chain_left > 0:
		_try_chain(pos)
	if not keep_alive:
		queue_free()


func _bounce_at(clamped: Vector2) -> void:
	_bounce_left -= 1
	var before := position
	position = clamped
	_travelled = 0.0
	var axis := Vector2.ZERO
	if not is_equal_approx(clamped.x, before.x):
		axis.x = 1.0
	if not is_equal_approx(clamped.y, before.y):
		axis.y = 1.0
	_dir = _dir.reflect(axis.normalized()) if axis != Vector2.ZERO else -_dir


func _orbit_step(delta: float) -> void:
	_orbit_life -= delta
	if _orbit_life <= 0.0:
		queue_free()
		return
	if _player_ref != null and is_instance_valid(_player_ref):
		_orbit_center = _player_ref.global_position
	_orbit_angle += ORBIT_SPEED * delta
	global_position = _orbit_center + Vector2.from_angle(_orbit_angle) * ORBIT_RADIUS
	for e in _enemies_in_radius(global_position, CONTACT_RADIUS):
		var id: int = e.get_instance_id()
		if _hit_enemies.has(id):
			continue
		_hit_enemies[id] = true
		_hit_enemy(e, 1.0, true)
		if _chain_left > 0:
			_try_chain(e.global_position)
		# AOE弹道核×环绕（问题2）：环绕弹保留爆炸（接触点小型爆炸，弹体不销毁）；
		# 旋风刃仅在爆发外壳（explode 标志）下触发刀刃爆炸（问题14），基础刀刃不炸。
		if _aoe > 0.0 and (not _is_whirl or bool(_mods.get("explode", false))):
			_explode_at(global_position, true)


func _hit_enemy(enemy: Node, dmg_mult: float = 1.0, direct_hit: bool = false) -> void:
	if not is_instance_valid(enemy):
		return
	var crit: bool = _roll_crit()
	var mult: float = GameState.run.get("crit_dmg_bonus", 1.5) if crit else 1.0
	# 移M7 顺风弹（方向一致 +20% 起）/ 移6 风刃（移动时 +4%/层）：弹幕伤害读取点接线
	var wind_dmg := 1.0 + maxf(float(GameState.run.get("wind_m7_dmg", 0.0)), 0.0) \
		+ maxf(float(GameState.run.get("wind_m6_move_dmg", 0.0)), 0.0)
	var final_dmg := roundi(_damage * mult * dmg_mult * wind_dmg)
	SynergyRegistry.trigger("projectile_hit", {"enemy": enemy, "dmg": final_dmg, "element": _element, "crit": crit, "pos": enemy.global_position})
	if enemy.has_method("take_damage"):
		enemy.take_damage(final_dmg, _element, crit)
	EventBus.damage_dealt.emit(final_dmg, enemy.global_position, crit)
	EventBus.fx_hit_flash.emit(enemy)
	# 特效分级：普通直击走轻量命中（无扩散环）；aoe/instant 爆炸由 _explode_at 走 fx_explosion
	if direct_hit:
		EventBus.fx_hit.emit(enemy.global_position, _element)
	if _drain > 0.0:
		var healed := GameState.heal(final_dmg * _drain)
		# 吸血反馈（Agent C）：治疗飘字 + 绿色粒子飞向玩家
		if healed > 0:
			var hpos: Vector2 = global_position
			if _player_ref != null and is_instance_valid(_player_ref):
				hpos = _player_ref.global_position
			EventBus.fx_heal_text.emit(hpos, healed)
			EventBus.fx_explosion.emit(hpos, "heal")
	_apply_statuses(enemy)
	if _split > 0:
		_spawn_split_minis(enemy)


## N2 暴击判定扩展：基础暴击率 + 幸运构筑（crit_lucky 等 lucky tag 曲线）+
## 元素系暴击率（thunder_10 雷系 / water_tide_power 水系）；
## 幸运四叶草在未暴击时按曲线概率额外重掷一次。
func _roll_crit() -> bool:
	var chance := clampf(float(GameState.run.get("crit_chance", 0.03)), 0.0, 1.0)
	chance += _lucky_crit_bonus()  # 内部已按持有件数守卫（0 层不加成）
	# 移7 顺风：每 100% 移速 +4% 暴击率（run.wind_speed_crit 读取点接线）
	chance += maxf(float(GameState.run.get("wind_speed_crit", 0.0)), 0.0)
	if _element == "lightning" and GameState.total_stacks("thunder_10") > 0:
		chance += _def_value("thunder_10")
	elif _element == "water" and GameState.total_stacks("water_tide_power") > 0:
		chance += _def_value("water_tide_power")
	# N2 暴M1 消费点：有效暴击率超过 100% 的部分写入 run.crit_overflow（转真伤）
	var effective := clampf(chance, 0.0, 1.0)
	GameState.run.crit_overflow = maxf(chance - 1.0, 0.0)
	var crit := randf() < effective
	if not crit:
		var clover := GameState.item_def("lucky_clover")
		# 0 层不生效：exp_proc 在 0 层返回 4%，不加守卫会白送重掷
		if not clover.is_empty() and GameState.total_stacks("lucky_clover") > 0:
			var reroll := GameState.item_value(clover, GameState.total_stacks("lucky_clover"))
			if reroll > 0.0 and randf() < reroll:
				crit = randf() < effective
	return crit


## lucky tag 构筑的曲线值合计（暴击率小加成）
func _lucky_crit_bonus() -> float:
	var def := GameState.item_def("crit_lucky")
	# 0 层不生效：linear 在 0 层返回 base（10%），不加守卫会白送暴击率
	if def.is_empty() or GameState.total_stacks("crit_lucky") <= 0:
		return 0.0
	return float(GameState.item_value(def, GameState.total_stacks("crit_lucky")))


## 指定 id 构筑的曲线值（缺表返回 0）
func _def_value(item_id: String) -> float:
	var def := GameState.item_def(item_id)
	if def.is_empty():
		return 0.0
	return float(GameState.item_value(def, GameState.total_stacks(item_id)))


func _apply_statuses(enemy: Node) -> void:
	## 元素隐式状态（原有：毒雾/冰锥）
	if _element == "poison":
		EventBus.apply_status.emit(enemy, "poison", 1)
	elif _element == "ice":
		EventBus.apply_status.emit(enemy, "freeze", 1)
	## 核心显式状态（setup 注入：inferno/fireball/water_bolt/thorn_vine/flash）
	## 概率语义：0 < 值 < 1 = 以该概率施加 1 层；值 >= 1 = 必定施加
	## （burn/poison 的层数取整数值，enemy 侧按 stacks 放大 DPS）
	for k in ["burn", "slow", "root", "poison", "blind"]:
		var v := float(_status.get(k, 0.0))
		if v <= 0.0:
			continue
		if v < 1.0 and randf() >= v:
			continue
		var stacks := maxi(int(v), 1) if k in ["burn", "poison"] else 1
		EventBus.apply_status.emit(enemy, k, stacks)
	## N2 寒冰护符：非冰系命中按曲线概率冻结 1s（每层独立判定）
	if _element != "ice" and GameState.total_stacks("frost_charm") > 0:
		var charm := GameState.item_def("frost_charm")
		if not charm.is_empty():
			var fchance := float(GameState.item_value(charm, GameState.total_stacks("frost_charm")))
			if fchance > 0.0 and randf() < fchance:
				EventBus.apply_status.emit(enemy, "freeze", 1)
	## N2 毒液瓶：命中附加毒层（阈值曲线：基础 1 层，每 2 层 +1 层）
	var flask := GameState.item_def("venom_flask")
	if not flask.is_empty() and GameState.total_stacks("venom_flask") > 0:
		var layers := int(GameState.item_value(flask, GameState.total_stacks("venom_flask")))
		if layers > 0:
			EventBus.apply_status.emit(enemy, "poison", layers)


func _spawn_split_minis(source: Node) -> void:
	## split 外壳：命中后向扇形方向分裂 N 个小弹（伤害×0.6，不分裂/不链式，保留 drain）
	## 问题5：小弹继承核心显式状态（根缚/减速/点燃/中毒控场价值保留）；
	## 问题13：速度低于保底一律用 SPLIT_MINI_SPEED（修复旋风刃 speed=1.0 → 1px/s 蠕动 bug）
	var n := maxi(_split, 1)
	var base_angle := _dir.angle()
	var spread := deg_to_rad(SPLIT_FAN_DEG)
	for i in n:
		var t := 0.0
		if n > 1:
			t = float(i) / float(n - 1) - 0.5
		var dir := Vector2.from_angle(base_angle + spread * t)
		# 运行时 load 自身场景，避免脚本↔场景循环 preload（smoke 扫描脚本优先加载会报错）
		var mini = load("res://scenes/game/projectile.tscn").instantiate()
		var mini_mods: Dictionary = {}
		if _drain > 0.0:
			mini_mods["drain"] = _drain
		mini.setup({
			"position": global_position + dir * 12.0,
			"direction": dir,
			"speed": _speed if _speed >= SPLIT_MINI_SPEED else SPLIT_MINI_SPEED,
			"range": maxf(_range * 0.5, 120.0),
			"damage": _damage * SPLIT_DAMAGE_MULT,
			"element": _element,
			"aoe": 0.0,
			"mods": mini_mods,
			"status": _status.duplicate(),
			"chain": 0,
		})
		# 小弹不再重复命中来源敌人（避免贴脸三连击）
		mini._hit_enemies[source.get_instance_id()] = true
		get_tree().current_scene.add_child(mini)


func _try_chain(from: Vector2) -> void:
	## 闪电链：向最近未命中敌人跳跃，每跳伤害 ×0.7（chain 字段 = 总跳数）
	var mult := 1.0
	while _chain_left > 0:
		var target := _nearest_unhit_enemy(from, CHAIN_RANGE)
		if target == null:
			break
		_chain_left -= 1
		mult *= CHAIN_FALLOFF
		_hit_enemies[target.get_instance_id()] = true
		_hit_enemy(target, mult, true)
		# 链跳视觉：目标之间绘制闪电连线（仅信号/节点，不动伤害逻辑）
		_emit_chain_bolt(from, target.global_position)
		from = target.global_position


func _emit_chain_bolt(from: Vector2, to: Vector2) -> void:
	## 雷系链跳视觉信号：找 FxManager 触发 LightningBolt；场景无 FX 节点时静默跳过（如 headless 测试）。
	var scene := get_tree().current_scene
	if scene == null:
		return
	var fx = scene.get_node_or_null("FxManager")
	if fx != null and fx.has_method("spawn_chain_bolt"):
		fx.spawn_chain_bolt(from, to)


func _nearest_unhit_enemy(from: Vector2, radius: float) -> Node:
	var best: Node = null
	var best_d := INF
	for e in _all_enemies():
		if not is_instance_valid(e) or not e.has_method("take_damage"):
			continue
		if float(e.get("hp")) <= 0.0:
			continue
		if _hit_enemies.has(e.get_instance_id()):
			continue
		var d: float = from.distance_to(e.global_position)
		if d <= radius and d < best_d:
			best_d = d
			best = e
	return best


func _nearest_enemy() -> Node:
	var best: Node = null
	var best_d := INF
	for e in _all_enemies():
		if not is_instance_valid(e):
			continue
		var d: float = global_position.distance_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


func _enemies_in_radius(center: Vector2, radius: float) -> Array:
	var result: Array = []
	for e in _all_enemies():
		if not is_instance_valid(e):
			continue
		# 命中判定按敌人实际体型放大（大体积 Boss 的碰撞圈远大于中心 9px）
		var hit_r: float = radius + e.scale.x * 8.0
		var d: float = center.distance_to(e.global_position)
		if d <= hit_r:
			result.append(e)
	return result


## 敌人扫描：优先 group "enemy"；组缺失时回退全树找 take_damage 节点。
func _all_enemies() -> Array:
	var grouped := get_tree().get_nodes_in_group("enemy")
	if not grouped.is_empty():
		return grouped
	var scene := get_tree().current_scene
	if scene == null:
		return []
	var found: Array = []
	for child in scene.get_children():
		_collect_enemies(child, found)
	return found


func _collect_enemies(node: Node, found: Array) -> void:
	if node != self and node.has_method("take_damage"):
		found.append(node)
	for child in node.get_children():
		_collect_enemies(child, found)


static func clear_player_projectiles(tree: SceneTree) -> void:
	## 替换/添加法术后清空场上玩家弹道（含 split 小弹）；
	## 只清 group "player_projectile"，不触碰敌人弹幕（enemy_bullet）与召唤物（summons）。
	for p in tree.get_nodes_in_group("player_projectile"):
		if is_instance_valid(p):
			p.queue_free()
