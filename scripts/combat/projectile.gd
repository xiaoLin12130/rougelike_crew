extends Area2D
## 投射物：由 spell_caster.setup() 注入速度/射程/伤害/元素/修饰参数。
## 命中敌人 → enemy.take_damage(dmg, element, is_crit) + EventBus 事件。
## 支持 homing / pierce / bounce / orbit / delay / explode / 毒雾 / 冰锥 / 暴击。

## 地面特效工厂（GroundVine 等）：弹体命中/爆炸点生成藤蔓生长动画用
const FxManagerScript := preload("res://scripts/fx/fx_manager.gd")

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
	## 技能视觉 P0-1（2026-08-10）：water_bolt/thorn_vine 弹体此前回退火球贴图，
	## 补 water/nature 映射（verarc 16x16 水滴/藤蔓图标，路径已核实存在）
	"water": "res://assets/icons/verarc/water_spell.png",
	"nature": "res://assets/icons/verarc/thorn_vine_spell.png",
}
## 藤蔓（nature）弹体专用：飞行阶段不用静态图标，改程序化"种子+藤须拖尾"
## （2026-08-12 用户反馈：图标直接飞出去观感差 → 见 docs/design/藤蔓护盾音效修复报告.md）
const VINE_SEED := Color(0.32, 0.66, 0.22)
const VINE_SEED_LIGHT := Color(0.72, 1.0, 0.5)
const VINE_TENDRIL := Color(0.42, 0.82, 0.28)
const VINE_GROUND_RADIUS := 40.0  # 命中生成藤蔓半径
const VINE_GROUND_LIFE := 1.5     # 命中生成藤蔓存活秒数
## 藤蔓种子视觉节点（程序化 _draw，无静态贴图；飞行时藤须在身后摆动）
class VineSeedVisual:
	extends Node2D

	var _phase := 0.0

	func _process(delta: float) -> void:
		_phase += delta
		var p := get_parent()
		if p != null:
			var d = p.get("_dir")
			if d is Vector2:
				rotation = (d as Vector2).angle()  # 种子尖端始终朝飞行方向
		queue_redraw()

	func _draw() -> void:
		# 能量光晕（脉动）
		var halo := 7.0 + 1.8 * sin(_phase * 6.0)
		draw_circle(Vector2.ZERO, halo, Color(0.5, 0.95, 0.4, 0.16))
		draw_circle(Vector2.ZERO, halo * 0.55, Color(0.65, 1.0, 0.5, 0.12))
		# 种子主体（深绿实心 + 高光点）
		draw_circle(Vector2.ZERO, 3.6, Color(VINE_SEED, 0.95))
		draw_circle(Vector2(1.1, -1.2), 1.2, Color(VINE_SEED_LIGHT, 0.9))
		# 身后藤须拖尾（曲线摆动，体现"种子带着藤蔓飞"）
		var pts := PackedVector2Array()
		for i in 6:
			var t := float(i) / 5.0
			var wob := sin(_phase * 9.0 + t * 5.0) * (2.0 + 3.0 * t)
			pts.append(Vector2(-3.0 - t * 12.0, wob))
		draw_polyline(pts, Color(VINE_TENDRIL, 0.75), 1.6, true)
		draw_polyline(pts, Color(VINE_TENDRIL, 0.28), 3.2, true)
		# 尖端嫩芽（两片小叶）
		draw_line(Vector2.ZERO, Vector2(4.5, 0.0), Color(VINE_SEED_LIGHT, 0.85), 1.2)
		draw_line(Vector2(2.8, 0.0), Vector2(4.2, -2.0), Color(VINE_SEED_LIGHT, 0.7), 1.0)
		draw_line(Vector2(2.8, 0.0), Vector2(4.2, 2.0), Color(VINE_SEED_LIGHT, 0.7), 1.0)
## verarc 法术图标 16x16 > 常规 proj_* 12x12：给这两个元素弹体放大补偿，
## 保证"水滴/藤蔓"形态可辨识（参考旋风刃 1.8x 思路，幅度更克制）
const STATUS_TEXTURE_SCALE := {
	"water": 1.5,
	"nature": 1.6,
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

## =====================================================================
## 弹幕对象池（P1 性能优化，docs/design/性能优化方案.md 热点 3）
## 所有 projectile 实例（含 split 小弹/召唤弹/冰晶/暴击弹）自然结束
## （命中/到射程/轨道到期/爆炸）时经 _retire → 静态池回收，不销毁节点；
## 施法入口经 obtain() 复用。回收时出树 + 退出组 + 状态全量重置，
## 重新 add_child 时 _ready 会重新入组并重设精灵贴图。
## =====================================================================
const PROJ_POOL_MAX := 48
const PROJECTILE_SCENE_PATH := "res://scenes/game/projectile.tscn"

static var _proj_pool: Array = []  # 空闲实例（已出树、已重置）
static var _proj_created := 0  # 累计实例化数（测试/监控）
static var _proj_reused := 0   # 累计复用数（测试/监控）

## 从池取弹幕实例并挂入 parent：空池则实例化场景（运行时 load，避免脚本↔场景循环 preload）。
## defer_add=true 时延迟到帧末 add_child（split 小弹在物理冲刷期回调内创建的既有做法）。
static func obtain(params: Dictionary, parent: Node, defer_add: bool = false) -> Node:
	var proj: Node = null
	while not _proj_pool.is_empty():
		# 池竞态修复（2026-08-13）：池内可能残留"已被 queue_free 排队销毁的弹体
		# 帧末释放后"的死引用（瞬发弹被 clear_player_projectiles 清场后，帧末销毁前
		# 仍跑物理帧爆炸入池，帧末被 pending 的 queue_free 销毁）。非类型化取值 +
		# is_instance_valid 判活：弹到死引用直接丢弃继续取下一个，避免类型化赋值
		# 在 Variant→Node 转换时对已释放实例报硬错误、中断 obtain() 返回 null。
		var cand = _proj_pool.pop_back()
		if cand is Node and is_instance_valid(cand):
			proj = cand
			_proj_reused += 1
			break
	if proj == null:
		proj = load(PROJECTILE_SCENE_PATH).instantiate()
		_proj_created += 1
	proj.setup(params)
	proj._apply_visual()  # 池化：_ready 只触发一次，视觉必须每次借用重设
	if defer_add:
		parent.call_deferred("add_child", proj)
		proj.call_deferred("add_to_group", "player_projectile")
		proj.call_deferred("_init_runtime_state")
	else:
		parent.add_child(proj)
		proj.add_to_group("player_projectile")
		proj._init_runtime_state()
	return proj

## 回收弹幕：出树 + 退出组（防 clear_player_projectiles 误清池中实例）+ 状态重置 + 入池。
## 池满则真正释放（queue_free）。
static func recycle(proj: Node) -> void:
	if proj == null or not is_instance_valid(proj):
		return
	if proj.is_inside_tree():
		proj.get_parent().remove_child(proj)
	if proj.is_in_group("player_projectile"):
		proj.remove_from_group("player_projectile")
	proj._reset_for_pool()
	if _proj_pool.size() < PROJ_POOL_MAX:
		_proj_pool.append(proj)
	else:
		proj.queue_free()

## 池统计（测试/监控）。
static func projectile_pool_stats() -> Dictionary:
	return {"created": _proj_created, "reused": _proj_reused, "idle": _proj_pool.size()}

## 清空池（场景切换/测试收尾调用）：释放池中空闲实例。
static func clear_pool() -> void:
	for p in _proj_pool:
		if is_instance_valid(p):
			p.free()
	_proj_pool.clear()

## 弹幕状态全量重置（池回收用）：位置/方向/速度/射程/伤害/元素/AOE/修饰/
## 命中记录/轨道/状态/分裂/吸血/精灵视觉，杜绝复用残留上一轮参数。
func _reset_for_pool() -> void:
	_spawn_pos = Vector2.ZERO
	_dir = Vector2.RIGHT
	_speed = 0.0
	_range = 360.0
	_damage = 0.0
	_element = "fire"
	_aoe = 0.0
	_mods = {}
	_travelled = 0.0
	_pierce_left = 0
	_bounce_left = 0
	_delay_left = 0.0
	_instant = false
	_orbit_mode = false
	_orbit_center = Vector2.ZERO
	_orbit_angle = 0.0
	_orbit_life = 2.0
	_player_ref = null
	_is_whirl = false
	_hit_enemies.clear()
	_impacted = false
	_status = {}
	_chain_left = 0
	_split = 0
	_drain = 0.0
	position = Vector2.ZERO
	# 藤蔓种子视觉：复用实例必须清掉（新元素借用时按需重建）
	var vseed := get_node_or_null("VineSeed")
	if vseed != null:
		vseed.queue_free()
	var spr := $Sprite2D as Sprite2D
	if spr != null:
		spr.texture = null
		spr.scale = Vector2.ONE
		spr.rotation = 0.0
		spr.visible = true

## 弹幕自然结束统一出口：命中/到射程/爆炸/轨道到期。
## 池竞态修复（2026-08-13）：若本帧已被 queue_free 排队销毁（换法术
## clear_player_projectiles 清场、测试 _clear_projectiles），不再回收入池——
## 待销毁弹体帧末销毁后池内会残留死引用，obtain() 弹到即硬错误中断。
## 直接跳过回收，交由 pending 的 queue_free 在帧末销毁。
func _retire() -> void:
	if is_queued_for_deletion():
		return
	recycle(self)


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
	# 池化：复用实例必须重置飞行/命中累积状态（新实例默认值）
	_travelled = 0.0
	_hit_enemies.clear()
	_impacted = false


func _ready() -> void:
	add_to_group("player_projectile")
	_apply_visual()
	_init_runtime_state()

## 视觉重设（贴图/缩放/旋转）：_ready 只在节点首次进树触发一次，
## 池化复用实例每次借用都必须由 obtain() 重新调用，保证新元素贴图生效。
func _apply_visual() -> void:
	var spr := $Sprite2D as Sprite2D
	if spr != null:
		if _is_whirl:
			# 旋风刃专用视觉（2026-08-10）：宽刀身贴图（SWORDS_120）+ 刀尖朝外，
			# 解决"刀刃太小看不出是刀在转"
			spr.texture = load("res://assets/icons/willibab/SWORDS_120.png")
			spr.scale = Vector2.ONE * 1.8
			spr.rotation = _dir.angle()
		elif _element == "nature":
			# 藤蔓弹体：不飞图标（用户反馈），改程序化种子视觉；Sprite2D 隐藏
			spr.texture = null
			spr.scale = Vector2.ONE
			spr.rotation = 0.0
			spr.visible = false
			if get_node_or_null("VineSeed") == null:
				var seed := VineSeedVisual.new()
				seed.name = "VineSeed"
				seed.z_index = 2
				add_child(seed)
		else:
			spr.texture = load(STATUS_TEXTURES.get(_element, STATUS_TEXTURES["fire"]))
			spr.scale = Vector2.ONE * STATUS_TEXTURE_SCALE.get(_element, 1.0)
			spr.visible = true

## 运行时状态重设（玩家引用/轨道参数）：同 _apply_visual，池化复用必须重跑。
func _init_runtime_state() -> void:
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
		global_position = _instant_landing()
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
			_retire()  # 池化：到射程回收复用
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
			_retire()  # 池化：命中回收复用
			return


## 爆炸结算：范围内敌人全部受击；keep_alive=true 时弹体保留（AOE×穿透/弹射、轨道接触爆炸）。
func _explode_at(pos: Vector2, keep_alive: bool = false) -> void:
	if not keep_alive:
		_impacted = true
	var radius := maxf(_aoe, 1.0)
	# 移8 踏浪：每 100% 移速 +6% 技能范围（run.wind_speed_area 读取点接线）
	radius *= 1.0 + maxf(float(GameState.run.get("wind_speed_area", 0.0)), 0.0)
	# flash（数据 aoe=0）瞬发时以固定爆发半径命中，保证失明/伤害生效
	# 闪光×爆发（问题10）：盲爆半径参与 aoe_mult（爆发外壳"范围翻倍"对闪光兑现）
	if _instant and float(_status.get("blind", 0.0)) > 0.0:
		radius = maxf(radius, BLIND_BURST_RADIUS * float(_mods.get("aoe_mult", 1.0)))
	# 特效范围同步（技能视觉 P0-2）：先算最终命中半径（含盲爆修正）再 emit，
	# 修复 flash 以 radius≈1 发最小档特效、视觉与实际 90px 盲爆差 90 倍的问题
	EventBus.fx_explosion_scaled.emit(pos, _element, radius)
	# 藤蔓（nature）AOE：落点生成藤蔓生长动画（复用 GroundVine 地面工厂）
	if _element == "nature":
		FxManagerScript.spawn_ground_fx("vine", pos, maxf(radius * 0.55, 30.0), VINE_GROUND_LIFE)
	for e in _enemies_in_radius(pos, radius):
		var id: int = e.get_instance_id()
		if _hit_enemies.has(id):
			continue
		_hit_enemies[id] = true
		_hit_enemy(e)
	if _chain_left > 0:
		_try_chain(pos)
	if not keep_alive:
		_retire()  # 池化：爆炸回收复用


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
		_retire()  # 池化：轨道到期回收复用
		return
	if _player_ref != null and is_instance_valid(_player_ref):
		_orbit_center = _player_ref.global_position
	# 旋风刃随攻速加速旋转（近战攻速堆叠 = 转得更快，2026-08-10 玩法联动）；
	# 其他轨道弹幕（法杖环绕）保持固定转速
	var spin_speed := ORBIT_SPEED
	if _is_whirl:
		spin_speed = ORBIT_SPEED * maxf(1.0 + GameState.total_attack_speed_bonus(), 1.0)
	_orbit_angle += spin_speed * delta
	global_position = _orbit_center + Vector2.from_angle(_orbit_angle) * ORBIT_RADIUS
	if _is_whirl:
		# 刀刃自转：刀身随轨道角度旋转（刀尖朝外），看起来是"刀在转"
		var spr := $Sprite2D as Sprite2D
		if spr != null:
			spr.rotation = _orbit_angle + PI / 2.0
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
	# 打击感 G-1/G-4：命中音效（暴击/精英/Boss 分级更响）+ 顿帧（暴击 60ms/普通 30ms/Boss 80ms）
	SfxBus.play_hit(SfxBus.hit_kind_for(enemy, crit))
	EventBus.fx_hit_slow.emit(enemy, crit)
	# 特效分级：普通直击走轻量命中（无扩散环）；aoe/instant 爆炸由 _explode_at 走 fx_explosion
	if direct_hit:
		EventBus.fx_hit.emit(enemy.global_position, _element)
	# 藤蔓（nature）直击：命中点生成缠绕藤蔓生长动画（技能语义"投出种子，命中缠绕"）
	if _element == "nature":
		FxManagerScript.spawn_ground_fx("vine", enemy.global_position, VINE_GROUND_RADIUS, VINE_GROUND_LIFE)
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
		var mini_mods: Dictionary = {}
		if _drain > 0.0:
			mini_mods["drain"] = _drain
		# 池化：经 obtain 复用（defer_add 保留"物理冲刷期回调内 deferred 加树"既有做法）
		var mini := obtain({
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
		}, get_tree().current_scene, true)
		# 小弹不再重复命中来源敌人（避免贴脸三连击）
		mini._hit_enemies[source.get_instance_id()] = true


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


## 瞬发核落点（体验报告 P1-2 修复：闪光/毒雾/火柱近身必脱靶）：
## 射程内存在最近敌人时，落点 = 敌人当前位置（闪光自动追踪敌人，用户原始反馈）；
## 无敌人或敌人超射程时保持方向线末端（spawn + dir × range），超程不脱靶逻辑不变。
## 敌人体型由爆炸半径兜底（毒雾 48/火柱 64/闪光盲爆 90），命中判定在 _explode_at。
func _instant_landing() -> Vector2:
	var target := _nearest_enemy()
	if target != null and _spawn_pos.distance_to(target.global_position) <= _range:
		return target.global_position
	return _spawn_pos + _dir * _range


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
	var grouped := GameState.get_enemies()
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
	## 2026-08-10：跳过旋风刃（_is_whirl）——持续型法术不应因网格变化突然消失，
	## 玩家拿新法术后正在旋转的刀刃保留到生命周期结束。
	for p in tree.get_nodes_in_group("player_projectile"):
		if is_instance_valid(p):
			if p.get("_is_whirl") == true:
				continue
			p.queue_free()
