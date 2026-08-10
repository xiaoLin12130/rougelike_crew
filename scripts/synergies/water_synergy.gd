extends Node
## 水控场流机制脚本（水M1 水泽 ~ 水M10 水龙卷，SynergyRegistry 钩子实现）
## ============================================================
## 挂载方式：由 SynergyRegistry.load_synergy_scripts() 自动扫描
## scripts/synergies/*.gd 并实例化挂树（game_root 或 autoload 亦可），
## _ready() 中自动注册全部回调。
## 强度读取：机制强度由持有 water_ 前缀构筑数量控制
##   （GameState.run.items 中 id 以 water_ 开头的条目总堆叠，_water_stacks()）；
## 数值联动：水1 水系伤害、水2 减速强度、水3 减速时长、水5 定身概率、
##   水6 范围、水7 击退、水9 沼泽增伤 由各机制按需读取。
## 防御性约定：所有回调先做对象/字段有效性检查；回调内不做可能抛错的
## 操作（GDScript 无 try/except），保证异常只影响本流派、不扩散到其他流派。
## 已知限制（对主线程的接线说明）：
## - enemy.gd 当前按固定 slow=0.45 结算减速，本脚本额外写入读取点
##   enemy._slow_strength（0.2 + 0.08×水2 层），主线程接线后改读此字段；
## - player.gd 移动速度当前不消费水M7 洋流，读取点为
##   GameState.run.water_m7_speed（默认 1.0）；
## - 区域节点为轻量自管理：挂当前场景，1.5-2.5s 后 queue_free，总数上限 10。

const PREFIX := "water_"

## ===== 机制构筑 id（与 .tools/build_defs/water.json 的 items 一致）=====
const M1 := "water_marsh"          ## 水M1 水泽
const M2 := "water_vortex"         ## 水M2 旋涡
const M3 := "water_vine_tangle"    ## 水M3 藤蔓缠绕
const M4 := "water_conduct"        ## 水M4 湿润导电
const M5 := "water_tide_lock"      ## 水M5 潮汐锁定
const M6 := "water_curtain"        ## 水M6 水幕
const M7 := "water_ocean_current"  ## 水M7 洋流
const M8 := "water_storm"          ## 水M8 暴雨
const M9 := "water_boil"           ## 水M9 沸腾
const M10 := "water_tornado"       ## 水M10 水龙卷

## ===== 数值构筑 id（联动读取）=====
const N1 := "water_essence"        ## 水1 水元素精粹（水系伤害）
const N2 := "water_tide_rune"      ## 水2 潮汐符（减速强度）
const N3 := "water_deep_water"     ## 水3 深水（减速时长）
const N5 := "water_root_rune"      ## 水5 定身符（定身概率）
const N6 := "water_moist"          ## 水6 潮湿（范围）
const N7 := "water_torrent"        ## 水7 激流（击退）
const N9 := "water_swamp"          ## 水9 沼泽（减速增伤）

## ===== 强度常量（克制参考：减速强度 8%/层、区域 1.5-2s、概率 15-25%）=====
const MASTERY_PER := 0.05          ## 每持有 1 件 water_ 构筑，机制强度 +5%
const ZONE_MAX := 10               ## 区域节点总数上限（防堆叠/泄漏）
const ZONE_DURATION_BASE := 1.8    ## 水泽基础持续（1.5-2s 区间）
const ZONE_DURATION_CAP := 2.0
const ZONE_RADIUS_BASE := 62.0     ## 水泽基础半径
const ZONE_TICK := 0.25            ## 区域判定节流
const SLOW_STRENGTH_BASE := 0.20   ## 减速强度基础 20%
const SLOW_STRENGTH_PER := 0.08    ## 水2 潮汐符 +8%/层
const SLOW_STRENGTH_CAP := 0.85
const SLOW_DURATION_BASE := 1.2    ## 水泽施加减速基础时长
const SLOW_DURATION_PER := 0.6     ## 水3 深水 +0.6s/层
const ROOT_DURATION := 1.5         ## 缠绕定身时长（与 enemy.gd 默认一致）
const VINE_CHANCE_BASE := 0.15     ## 藤蔓缠绕概率（15-25% 区间）
const VINE_CHANCE_PER := 0.02
const VINE_CHANCE_CAP := 0.25
const VINE_RADIUS_BASE := 90.0
const VORTEX_PULL := 22.0          ## 旋涡吸拉速度 px/s（仅被减速敌人）
const CONDUCT_MULT := 0.30         ## 水M4 湿润导电：雷伤 +30%
const BOIL_MULT := 0.30            ## 水M9 沸腾：火伤 +30%
const SWAMP_K := 0.08              ## 水9 沼泽：减速目标受伤 +8%/层
const CURTAIN_MULT := 0.40         ## 水M6 水幕：弹幕速度 ×0.4（-60%）
const CURRENT_BONUS := 0.20        ## 水M7 洋流：水泽内玩家移速 +20%
const STORM_INTERVAL := 6.0        ## 水M8 暴雨周期
const STORM_INTERVAL_MIN := 4.0
const STORM_SLOW_TIME := 0.8       ## 暴雨减速时长
const TORNADO_KILLS := 5           ## 水M10 水龙卷击杀计数
const TORNADO_DURATION := 2.0
const TORNADO_RADIUS_BASE := 58.0
const TORNADO_DPS_BASE := 10.0
const TORNADO_PUSH_BASE := 26.0    ## 击退 px/s（水7 激流加成）
const PRUNE_LIMIT := 256           ## 跟踪字典防泄漏阈值

## ===== 运行状态 =====
var _reg: Node = null
var _registered := {}              ## kind -> Callable（注销用）
var _zones: Array = []             ## 存活区域节点（上限 ZONE_MAX）
var _root_acc := {}                ## 水M5 潮汐锁定：enemy instance_id -> 累计秒
var _storm_left := STORM_INTERVAL
var _tornado_kills := 0            ## 水M10 击杀计数
var _amp_guard := {}               ## 水M4/M9/水9 增伤防递归（enemy id）
var _curtained := {}               ## 水M6 已减速弹幕标记（enemy_bullet id）


func _ready() -> void:
	_reg = get_node_or_null("/root/SynergyRegistry")
	if _reg == null or not _reg.has_method("register"):
		push_warning("[WaterSynergy] SynergyRegistry 不可用，水系机制未注册")
		return
	_register("enemy_died", _on_enemy_died)        ## 水M3 藤蔓缠绕 / 水M10 水龙卷
	_register("enemy_hit", _on_enemy_hit)          ## 水M4 湿润导电 / 水M9 沸腾 / 水9 沼泽
	_register("projectile_hit", _on_projectile_hit) ## 水M1 水泽
	print("[SYNERGY] water_synergy registered")


func _exit_tree() -> void:
	_unregister_all()
	_prune_zones(true)


func _process(delta: float) -> void:
	if not is_inside_tree():
		return
	_tick_tide_lock(delta)          ## 水M5 潮汐锁定
	_tick_storm(delta)              ## 水M8 暴雨
	_tick_player_current()          ## 水M7 洋流
	_prune_zones(false)
	_prune_trackers()


## ===== 注册 / 注销（防御式）=====

func _register(kind: String, cb: Callable) -> void:
	if _reg == null or not _reg.has_method("register"):
		return
	_reg.register(kind, cb)
	_registered[kind] = cb


func _unregister_all() -> void:
	if _reg == null:
		return
	var hooks = _reg.get("_hooks")
	if hooks == null or not (hooks is Dictionary):
		return
	for kind in _registered:
		var arr = hooks.get(kind)
		if arr is Array:
			arr.erase(_registered[kind])
	_registered.clear()


## ===== 水M1 水泽：水弹命中留下 1.5-2s 减速区域（重叠可叠加）=====
func _on_projectile_hit(ctx: Dictionary) -> void:
	if _stacks(M1) <= 0:
		return
	if str(ctx.get("element", "")) != "water":
		return
	var enemy = ctx.get("enemy")
	if not is_instance_valid(enemy):
		return
	_spawn_zone("marsh", _ctx_pos(ctx, enemy), _zone_radius(), _zone_duration())


## ===== 水M3 藤蔓缠绕 / 水M10 水龙卷（共用 enemy_died）=====
func _on_enemy_died(ctx: Dictionary) -> void:
	var enemy = ctx.get("enemy")
	if not is_instance_valid(enemy):
		return
	var eid := _id_of(enemy)
	_root_acc.erase(eid)
	_amp_guard.erase(eid)
	# 水M10 水龙卷：每击杀 5 个被减速敌人生成水龙卷（持续伤害+击退）
	if _stacks(M10) > 0 and _fget(enemy, "_slow_left", 0.0) > 0.0:
		_tornado_kills += 1
		if _tornado_kills >= TORNADO_KILLS:
			_tornado_kills = 0
			var pos := _ctx_pos(ctx, enemy)
			var zone := _spawn_zone("tornado", pos, _tornado_radius(), TORNADO_DURATION)
			if zone != null:
				EventBus.fx_explosion.emit(pos, "water")
	# 水M3 藤蔓缠绕：定身敌人死亡时向周围释放缠绕（新根须）
	if _stacks(M3) <= 0:
		return
	if _fget(enemy, "_root_left", 0.0) <= 0.0:
		return
	var chance := clampf(
		VINE_CHANCE_BASE + VINE_CHANCE_PER * (float(_stacks(N5)) + float(_water_stacks()) - 1.0),
		VINE_CHANCE_BASE, VINE_CHANCE_CAP)
	if randf() >= chance:
		return
	_spread_vines(_ctx_pos(ctx, enemy))


## ===== 水M4 湿润导电（雷）+ 水M9 沸腾（火）+ 水9 沼泽增伤（共用 enemy_hit）=====
func _on_enemy_hit(ctx: Dictionary) -> void:
	var n9 := _stacks(N9)
	var m4 := _stacks(M4)
	var m9 := _stacks(M9)
	if n9 <= 0 and m4 <= 0 and m9 <= 0:
		return
	var enemy = ctx.get("enemy")
	if not is_instance_valid(enemy):
		return
	if _fget(enemy, "_slow_left", 0.0) <= 0.0:
		return
	var dmg := int(ctx.get("dmg", 0))
	if dmg <= 0:
		return
	var el := str(ctx.get("element", ""))
	var bonus := 0
	if n9 > 0:
		bonus += maxi(int(float(dmg) * SWAMP_K * float(n9)), 0)         ## 水9 沼泽
	if el == "lightning" and m4 > 0:
		bonus += maxi(int(float(dmg) * CONDUCT_MULT * _mech_mult()), 0) ## 水M4 湿润导电
	if el == "fire" and m9 > 0:
		bonus += maxi(int(float(dmg) * BOIL_MULT * _mech_mult()), 0)    ## 水M9 沸腾
	if bonus <= 0:
		return
	var eid := _id_of(enemy)
	if _amp_guard.has(eid):
		return
	_amp_guard[eid] = true
	if enemy.has_method("take_damage"):
		var crit := bool(ctx.get("crit", false))
		enemy.take_damage(maxi(bonus, 1), el, crit)
		EventBus.damage_dealt.emit(maxi(bonus, 1), _enemy_pos(enemy), crit)
	_amp_guard.erase(eid)


## ===== 水M5 潮汐锁定：定身持续期间每秒叠加减速层 =====
func _tick_tide_lock(delta: float) -> void:
	if _stacks(M5) <= 0:
		return
	var tree := get_tree()
	if tree == null:
		return
	var dur := _slow_duration()
	for e in GameState.get_enemies():
		if not is_instance_valid(e):
			continue
		var eid := _id_of(e)
		if _iget(e, "_dead", false) or _fget(e, "_root_left", 0.0) <= 0.0:
			_root_acc.erase(eid)
			continue
		var acc: float = float(_root_acc.get(eid, 0.0)) + delta
		if acc < 1.0:
			_root_acc[eid] = acc
			continue
		_root_acc[eid] = 0.0
		_apply_slow(e, dur)  ## 定身结束仍被减速，形成"锁定→缓行"衔接


## ===== 水M8 暴雨：每 6s 全场减速 0.8s（水3 加时长，强度随构筑提升）=====
func _tick_storm(delta: float) -> void:
	if _stacks(M8) <= 0:
		_storm_left = STORM_INTERVAL
		return
	_storm_left -= delta
	if _storm_left > 0.0:
		return
	_storm_left = maxf(STORM_INTERVAL / (1.0 + MASTERY_PER * float(_water_stacks())), STORM_INTERVAL_MIN)
	var tree := get_tree()
	if tree == null:
		return
	var dur := clampf(STORM_SLOW_TIME + SLOW_DURATION_PER * float(_stacks(N3)), 0.5, 2.5)
	var applied := 0
	for e in GameState.get_enemies():
		if not is_instance_valid(e) or _iget(e, "_dead", false):
			continue
		_apply_slow(e, dur)
		applied += 1
	if applied > 0:
		EventBus.fx_explosion.emit(_player_pos(), "water")


## ===== 水M7 洋流：玩家在水泽区域移速 +20%（读取点 water_m7_speed）=====
func _tick_player_current() -> void:
	if GameState == null:
		return
	var tree := get_tree()
	if tree == null:
		return
	var player := tree.get_first_node_in_group("player")
	if player == null or not is_instance_valid(player) or not (player is Node2D):
		return
	var bonus := 0.0
	if _stacks(M7) > 0:
		var ppos: Vector2 = (player as Node2D).global_position
		for z in _zones:
			if not is_instance_valid(z):
				continue
			## Object.get 只接受 1 参数（无默认值），判空后取值
			var zkind = z.get("kind")
			if zkind == null or str(zkind) != "marsh":
				continue
			var zpos: Vector2 = z.global_position
			var zradius = z.get("radius")
			if zradius == null:
				continue
			if zpos.distance_to(ppos) <= float(zradius) + 8.0:
				bonus = maxf(bonus, CURRENT_BONUS)
	GameState.run.water_m7_speed = 1.0 + bonus  ## 主线程移速结算处可改读此值


## ===== 水M3 藤蔓缠绕：向周围释放缠绕 =====
func _spread_vines(pos: Vector2) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var radius := VINE_RADIUS_BASE * _area_mult()
	var applied := 0
	for e in GameState.get_enemies():
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		if _iget(e, "_dead", false):
			continue
		var node := e as Node2D
		if pos.distance_to(node.global_position) > radius + node.scale.x * 8.0:
			continue
		_apply_root(e)
		applied += 1
	if applied > 0:
		EventBus.fx_explosion.emit(pos, "nature")


## ===== 区域节点管理（轻量：短生命周期节点，上限 ZONE_MAX）=====

func _spawn_zone(kind: String, pos: Vector2, radius: float, left: float) -> Node2D:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return null
	if _zones.size() >= ZONE_MAX:
		var oldest = _zones.pop_front()
		if oldest != null and is_instance_valid(oldest):
			oldest.queue_free()
	var zone := WaterZone.new()
	zone.setup(self, kind, pos, radius, left)
	zone.name = "GroundTornado" if kind == "tornado" else "GroundWater"
	_zones.append(zone)
	tree.current_scene.add_child(zone)
	return zone


func _on_zone_freed(zone: Node) -> void:
	_zones.erase(zone)


func _prune_zones(free_all: bool) -> void:
	var i := _zones.size() - 1
	while i >= 0:
		var z = _zones[i]
		if not is_instance_valid(z):
			_zones.remove_at(i)
		elif free_all:
			z.queue_free()
			_zones.remove_at(i)
		i -= 1


## 水M6 水幕：进入水泽区域的敌方弹幕速度 -60%（一次性标记）
func _curtain_bullets_in(zone_pos: Vector2, zone_radius: float) -> void:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	_curtain_scan(tree.current_scene, zone_pos, zone_radius)


func _curtain_scan(node: Node, zone_pos: Vector2, zone_radius: float) -> void:
	if not _is_enemy_bullet(node):
		for child in node.get_children():
			_curtain_scan(child, zone_pos, zone_radius)
		return
	var bid := node.get_instance_id()
	if _curtained.has(bid):
		return
	if not (node is Node2D):
		return
	var pos: Vector2 = (node as Node2D).global_position
	if pos.distance_to(zone_pos) > zone_radius + 6.0:
		return
	var spd = node.get("_speed")
	if spd == null or float(spd) <= 0.0:
		return
	node.set("_speed", float(spd) * CURTAIN_MULT)
	_curtained[bid] = true


func _is_enemy_bullet(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	var script: Script = node.get_script()
	if script == null:
		return false
	return str(script.resource_path).ends_with("enemy_bullet.gd")


## ===== 状态工具（全部防御式）=====

## 施加减速：延长 _slow_left（取更长者）+ 写入减速强度读取点 _slow_strength
func _apply_slow(enemy: Node, duration: float) -> void:
	if not is_instance_valid(enemy):
		return
	var cur = enemy.get("_slow_left")
	if cur == null:
		return
	enemy.set("_slow_left", maxf(float(cur), duration))
	enemy.set("_slow_strength", clampf(
		SLOW_STRENGTH_BASE + SLOW_STRENGTH_PER * float(_stacks(N2)),
		0.0, SLOW_STRENGTH_CAP))


## 施加定身：延长 _root_left（取更长者）
func _apply_root(enemy: Node) -> void:
	if not is_instance_valid(enemy):
		return
	var cur = enemy.get("_root_left")
	if cur == null:
		return
	enemy.set("_root_left", maxf(float(cur), ROOT_DURATION))


## ===== 工具函数（全部防御式）=====

func _stacks(id: String) -> int:
	if GameState == null:
		return 0
	var items: Dictionary = GameState.run.get("items", {})
	return maxi(int(items.get(id, 0)), 0)


## 持有 water_ 前缀构筑总堆叠数（机制强度主驱动）
func _water_stacks() -> int:
	if GameState == null:
		return 0
	var items: Dictionary = GameState.run.get("items", {})
	var total := 0
	for k in items:
		if str(k).begins_with(PREFIX):
			total += maxi(int(items[k]), 0)
	return total


## 机制强度倍率：每件 water_ 构筑 +5%
func _mech_mult() -> float:
	return 1.0 + MASTERY_PER * float(_water_stacks())


## 水6 潮湿：水系范围 +12%/层
func _area_mult() -> float:
	return 1.0 + 0.12 * float(_stacks(N6))


## 水1 水元素精粹：水系伤害 +12%/层
func _water_dmg_mult() -> float:
	return 1.0 + 0.12 * float(_stacks(N1))


func _zone_radius() -> float:
	return clampf(ZONE_RADIUS_BASE * _area_mult() * _mech_mult(), 40.0, 110.0)


func _zone_duration() -> float:
	return clampf(ZONE_DURATION_BASE + 0.2 * float(_stacks(N3)), 1.5, ZONE_DURATION_CAP)


func _slow_duration() -> float:
	return clampf(SLOW_DURATION_BASE + SLOW_DURATION_PER * float(_stacks(N3)), 0.5, 2.5)


func _tornado_radius() -> float:
	return clampf(TORNADO_RADIUS_BASE * (1.0 + 0.04 * float(maxi(_water_stacks() - 1, 0))), 45.0, 90.0)


func _tornado_dps() -> float:
	return maxf(TORNADO_DPS_BASE * _water_dmg_mult() * _mech_mult(), 1.0)


func _tornado_push() -> float:
	return TORNADO_PUSH_BASE * (1.0 + 0.15 * float(_stacks(N7)))  ## 水7 激流


func _vortex_pull() -> float:
	return VORTEX_PULL * _mech_mult()


func _prune_trackers() -> void:
	if _root_acc.size() <= PRUNE_LIMIT and _amp_guard.size() <= PRUNE_LIMIT \
			and _curtained.size() <= PRUNE_LIMIT:
		return
	var tree := get_tree()
	for d in [_root_acc, _amp_guard, _curtained]:
		var dead: Array = []
		for k in d:
			var obj = instance_from_id(int(k)) if tree != null else null
			if not is_instance_valid(obj):
				dead.append(k)
		for k in dead:
			d.erase(k)


## Object.get 只接受 1 参数（无默认值），对 Variant 对象统一走这里安全取值
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


func _player_pos() -> Vector2:
	var tree := get_tree()
	if tree == null:
		return Vector2.ZERO
	var p := tree.get_first_node_in_group("player")
	if p != null and is_instance_valid(p) and p is Node2D:
		return (p as Node2D).global_position
	return Vector2.ZERO


## ===== 水泽区域节点（轻量：挂当前场景，到期 queue_free）=====
## 水M1 减速 + 水M2 旋涡吸拉 + 水M6 水幕弹幕减速；
## 水M7 洋流由宿主每帧按区域覆盖结算（见 _tick_player_current）。
class WaterZone:
	extends Area2D

	var host: Node = null
	var kind := "marsh"
	var radius := 60.0
	var left := 2.0
	var tick := 0.0
	var slow_duration := 1.2
	var _anim := 0.0

	func setup(host_: Node, kind_: String, pos: Vector2, radius_: float, left_: float) -> void:
		host = host_
		kind = kind_
		global_position = pos
		radius = radius_
		left = left_
		tick = 0.0
		_anim = 0.0
		z_index = -12

	func _process(delta: float) -> void:
		left -= delta
		if left <= 0.0:
			_finish()
			queue_free()
			return
		_anim += delta
		tick -= delta
		if tick > 0.0:
			queue_redraw()
			return
		tick = 0.25
		_apply()
		queue_redraw()

	func _draw() -> void:
		## 地面视觉（纯程序化，不参与碰撞/伤害）：水泽=半透明水面+涟漪；水龙卷=旋转螺旋
		if kind == "tornado":
			_draw_tornado()
		else:
			_draw_marsh()

	func _draw_marsh() -> void:
		# 半透明水面（暗蓝底 + 亮蓝内芯）
		draw_circle(Vector2.ZERO, radius, Color(0.16, 0.4, 0.9, 0.28))
		draw_circle(Vector2.ZERO, radius * 0.62, Color(0.42, 0.68, 1.0, 0.16))
		# 涟漪环：半径随时间呼吸扩散
		for i in 3:
			var ph := _anim * (2.2 + 0.5 * float(i)) + float(i) * 1.9
			var rr := radius * (0.28 + 0.22 * float(i)) + sin(ph) * 4.0
			var aa := 0.4 - 0.1 * float(i)
			draw_arc(Vector2.ZERO, rr, 0.0, TAU, 24, Color(0.65, 0.85, 1.0, aa), 1.6, true)
		# 水M2 旋涡：有旋涡构筑时叠加旋转涡流线
		if host != null and is_instance_valid(host) and host.has_method("_stacks") \
				and host._stacks("water_vortex") > 0:
			for i in 2:
				var sw := _anim * (2.0 + 0.7 * float(i)) + float(i) * PI
				draw_arc(Vector2.ZERO, radius * 0.42, sw, sw + 3.2, 14,
					Color(0.75, 0.9, 1.0, 0.5), 2.0, true)
		# 边缘亮线
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, Color(0.7, 0.9, 1.0, 0.45), 2.0, true)

	func _draw_tornado() -> void:
		# 水龙卷：三圈旋转螺旋（青色）+ 底部水眼
		for i in 3:
			var rr := radius * (0.32 + 0.26 * float(i))
			var start := _anim * (3.0 + 1.4 * float(i)) + float(i) * TAU / 3.0
			draw_arc(Vector2.ZERO, rr, start, start + 4.6, 22,
				Color(0.55, 0.8, 1.0, 0.5 - 0.1 * float(i)), 2.4 + 0.6 * float(i), true)
		draw_circle(Vector2.ZERO, radius * 0.14, Color(0.75, 0.9, 1.0, 0.7))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 26, Color(0.5, 0.75, 1.0, 0.35), 1.8, true)

	func _exit_tree() -> void:
		_finish()

	func _finish() -> void:
		if host != null and is_instance_valid(host) and host.has_method("_on_zone_freed"):
			host._on_zone_freed(self)

	func _apply() -> void:
		var tree := get_tree()
		if tree == null or host == null or not is_instance_valid(host):
			return
		if kind == "marsh":
			_apply_marsh(tree)
		elif kind == "tornado":
			_apply_tornado(tree)

	func _apply_marsh(tree: SceneTree) -> void:
		var has_vortex: bool = host._stacks("water_vortex") > 0
		var has_curtain: bool = host._stacks("water_curtain") > 0
		for e in GameState.get_enemies():
			if not _valid(e):
				continue
			var d: float = global_position.distance_to(e.global_position)
			var hit_r: float = radius + float(e.scale.x) * 8.0
			if d > hit_r:
				continue
			# 水M2 旋涡：被减速敌人缓慢吸向水泽中心（定身敌人不受牵引）
			if has_vortex and host._fget(e, "_slow_left", 0.0) > 0.0 \
					and host._fget(e, "_root_left", 0.0) <= 0.0 and d > 4.0:
				var pull: float = host._vortex_pull()
				e.global_position += (global_position - e.global_position) / d * minf(pull * 0.25, d)
			# 水M1 水泽：施加/刷新减速（重叠区域各自叠加，取更长者）
			host._apply_slow(e, slow_duration)
		# 水M6 水幕：进入区域的敌方弹幕速度 -60%
		if has_curtain:
			host._curtain_bullets_in(global_position, radius)

	func _apply_tornado(tree: SceneTree) -> void:
		var dmg := maxi(int(host._tornado_dps() * 0.25), 1)
		var push: float = host._tornado_push() * 0.25
		for e in GameState.get_enemies():
			if not _valid(e):
				continue
			var d: float = global_position.distance_to(e.global_position)
			if d > radius + float(e.scale.x) * 8.0:
				continue
			if e.has_method("take_damage"):
				e.take_damage(dmg, "water", false)
				EventBus.damage_dealt.emit(dmg, e.global_position, false)
			# 击退（水7 激流加成）
			if push > 0.0 and d > 4.0:
				e.global_position += (e.global_position - global_position) / d * minf(push, d * 0.5)

	func _valid(e: Node) -> bool:
		if e == null or not is_instance_valid(e):
			return false
		if not (e is Node2D):
			return false
		var dead = e.get("_dead")
		return not (dead != null and bool(dead))
